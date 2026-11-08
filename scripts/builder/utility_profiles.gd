extends RefCounted

const Connector=preload("res://scripts/builder/connector_plan.gd")
const Terrain=preload("res://scripts/builder/terrain_plan.gd")
const Traffic=preload("res://scripts/builder/traffic_plan.gd")
const Grid=preload("res://scripts/builder/grid_fit.gd")
const Layers=preload("res://scripts/builder/layers.gd")
const Weather=preload("res://scripts/builder/weather_plan.gd")
const Props=preload("res://scripts/builder/prop_plan.gd")
const Laundry=preload("res://scripts/builder/laundry_plan.gd")
const CATALOGS: Dictionary={"water":"res://resources/catalog/water_profiles.json","power":"res://resources/catalog/power_profiles.json"}
const SIDES: Dictionary={"north":Vector2.UP,"east":Vector2.RIGHT,"south":Vector2.DOWN,"west":Vector2.LEFT}
const STORAGE_PORTS: Dictionary={"north":"north","east":"east","south":"south","west":"west"}
static var catalogs: Dictionary={}

static func catalog(kind: String) -> Dictionary:
	if not catalogs.has(kind):
		var path: String=CATALOGS.get(kind,"")
		var source: Variant=JSON.parse_string(FileAccess.get_file_as_string(path)) if not path.is_empty() else null
		catalogs[kind]=source if source is Dictionary and source.get("version")==1 else {}
	return catalogs[kind]

static func profile(item: Dictionary,library: RefCounted,kind: String) -> Dictionary:
	var asset: String=item.get("asset","")
	var definitions: Dictionary=catalog(kind)
	if definitions.get("assets",{}).has(asset): return definitions["assets"][asset]
	if kind=="water" and asset.begins_with("2d:Supplemental_Water_towers_"):
		var family: String=library.assets.get(asset,{}).get("data",{}).get("family_id","")
		var capacity: int=definitions.get("tower_capacities",{}).get(family.get_file(),0)
		if capacity>0 and family.begins_with("supplemental/water_towers/"): return {"role":"storage","capacity":capacity}
	return {}

static func port_definitions(value: Dictionary,kind: String="water") -> Dictionary:
	if value.has("ports"): return value["ports"]
	match value.get("role"):
		"storage","relay": return STORAGE_PORTS
		"consumer": return {"input" if kind=="power" else "inlet":"west"}
		"source": return {"output":"east","output_west":"west"}
	return {}

static func production_context(data: Dictionary) -> Dictionary:
	var weather: Dictionary=Weather.state(data)
	return {"solar":0.0 if data.get("night",false) else 1.0-.75*maxf(weather["rain"],weather["snow"]),
		"wind":weather["wind_vector"].length() if weather["enabled"] else .5}

static func fixture_load(item: Dictionary) -> int:
	var fixture: Dictionary=catalog("power").get("assets",{}).get(item.get("asset",""),{})
	var cooking: Variant=item.get("cooking",{})
	var kitchen_load: bool=cooking is Dictionary and cooking.get("enabled",false)==true and cooking.get("power",false)==true
	return int(fixture["quantity"]) if fixture.get("effect")=="fixture" and (Props.power_device(item) or kitchen_load) else 0

static func interior_load(room: Dictionary,library: RefCounted,kind: String="power",laundry_enabled: bool=false) -> int:
	var units: int=0
	for item in room.get("objects",[]):
		if not availability(item,library,room).is_empty(): continue
		var existing: int=fixture_load(item) if kind=="power" else 0
		var station: Dictionary=Laundry.station(item) if laundry_enabled else {}
		var facility: int=profile(item,library,kind).get("quantity",0) if station.get(kind,false) else 0
		units+=maxi(existing,facility)
	for floor in room.get("floors",[]): units+=interior_load(floor["room"],library,kind,laundry_enabled)
	return units

static func footprint(item: Dictionary,library: RefCounted,mode: String) -> Rect2:
	var bounds: AABB=Grid.footprint_bounds(item,mode,library)
	var ratio: float=2.0 if mode=="2d" else 1.0
	var origin: Vector2=Traffic.metric(item["position"],mode)
	return Rect2(origin+Vector2(bounds.position.x,bounds.position.z)*ratio,Vector2(bounds.size.x,bounds.size.z)*ratio)

static func side_point(bounds: Rect2,side: String,clearance: float=.35) -> Vector2:
	var direction: Vector2=SIDES[side]
	return bounds.get_center()+direction*(absf(direction.dot(bounds.size))*.5+clearance)

static func terminal_ports(item: Dictionary,value: Dictionary,library: RefCounted,data: Dictionary,heights: Dictionary,kind: String="water") -> Dictionary:
	var mode: String=data["mode"]
	var bounds: Rect2=footprint(item,library,mode)
	var result: Dictionary={}
	var definitions: Dictionary=port_definitions(value,kind)
	for name in definitions:
		var point: Vector2=side_point(bounds,definitions[name])
		var height: float=Terrain.sample(data,point,heights)["height"] if Terrain.settings(data)["enabled"] else 0.0
		var role: String=value["role"]
		result[name]={"point":point,"height":height+.15,"position":Traffic.world(point,mode,height+.15),
			"normal":Connector.vector(Traffic.world(SIDES[definitions[name]],mode)),
			"polarity":"out" if role=="source" else "in" if role=="consumer" else "tap"}
	return result

static func pipe_ports(item: Dictionary,mode: String,data: Dictionary,heights: Dictionary,kind: String) -> Dictionary:
	var result: Dictionary={}
	if Connector.sockets(item,mode).is_empty(): return result
	var rise: float=Connector.terrain_height(data,item,mode,heights)
	for frame in Connector.frames(item,mode,rise):
		if frame["kind"]!=kind: continue
		var position: Vector3=frame["point"]
		var at: Array=[position.x,position.y+(position.z+rise)*8.0,position.z+rise] if mode=="2d" else [position.x,position.y,position.z]
		result[frame["socket"]]={"point":Traffic.metric(at,mode),"height":at[2] if mode=="2d" else at[1],
			"position":at,"polarity":"tap","normal":frame["normal"]}
	return result

static func availability(item: Dictionary,library: RefCounted,data: Dictionary) -> String:
	if item.has("missing_asset") or not library.assets.has(item["asset"]) or library.assets[item["asset"]].get("unavailable",false):
		return "The placed asset is unavailable."
	if not item.get("visible",true) or not Layers.shown(data,Layers.layer(item,library)):
		return "Show this object and its layer to operate the connection."
	return ""

static func access_reason(item: Dictionary,value: Dictionary,ports: Dictionary,data: Dictionary,library: RefCounted,heights: Dictionary,waters: Dictionary) -> String:
	if not Terrain.settings(data)["enabled"]:
		return "The pump intake needs surface water." if value.has("intake") else ""
	for port in ports.values():
		var point: Vector2=port["point"]
		var surface: Dictionary=Terrain.sample(data,point,heights)
		var water: Variant=Terrain.water_level(data,point,heights,waters)
		if surface["normal"].y<Terrain.WALKABLE_NORMAL or water!=null and water-surface["height"]>Terrain.WADING_DEPTH:
			return "A service port is flooded or on an unsupported slope."
	if value.has("intake"):
		var intake: Vector2=side_point(footprint(item,library,data["mode"]),value["intake"],2.0)
		var water: Variant=Terrain.water_level(data,intake,heights,waters)
		if water==null or water-Terrain.sample(data,intake,heights)["height"]<.25:
			return "The pump needs water at its marked north intake."
	return ""
