extends RefCounted

const PATH: String="res://resources/catalog/ambience.json"
const ACTIVITY_KINDS: Array[String] = ["school","arcade","workshop","market"]
const PLACE_KINDS: Array[String] = ["school","arcade","workshop","market","harbor"]
const KINDS: Array[String] = ["traffic","fountain","birds","shop","interior","school","arcade","workshop","market","harbor"]
const PLACE_VOICES: int = 3
const HARBOR_DEPTH: float = .15
const HARBOR_REACH: float = 7.0
const NEIGHBORS: Array[Vector2i] = [Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP]
const MAX_VOICES: int=24
const Traffic=preload("res://scripts/builder/traffic_plan.gd")
const Layers=preload("res://scripts/builder/layers.gd")
const Zone=preload("res://scripts/builder/zone_plan.gd")
const Terrain=preload("res://scripts/builder/terrain_plan.gd")
static var catalog: Dictionary={}

static func definitions() -> Dictionary:
	if catalog.is_empty(): catalog=JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return catalog

static func defaults() -> Dictionary:
	return {"enabled":true,"volume":.65,"preview_in_build":false,"range_scale":1.0,"traffic":.7,"fountain":.7,"birds":.7,"shop":.6,"interior":.65,
		"school":.60,"arcade":.64,"workshop":.63,"market":.62,"harbor":.66}

static func valid_settings(value: Variant) -> bool:
	if not value is Dictionary: return false
	for key in ["enabled","preview_in_build"]:
		if value.has(key) and not value[key] is bool: return false
	for key in ["volume","range_scale"]+KINDS:
		if value.has(key):
			var n: Variant=value[key]
			if not (n is int or n is float) or not is_finite(float(n)) or n<(0.25 if key=="range_scale" else 0) or n>(4 if key=="range_scale" else 1): return false
	return true

static func settings(data: Dictionary) -> Dictionary:
	var result: Dictionary=defaults(); var raw: Variant=data.get("ambience",{})
	if valid_settings(raw):
		for key in result:
			if raw.has(key): result[key]=raw[key]
	return result

static func valid_source(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.has("kind") and not value["kind"] in ["auto","none"]+KINDS: return false
	if value.has("enabled") and not value["enabled"] is bool: return false
	for key in ["volume","range"]:
		if value.has(key):
			var n: Variant=value[key]
			if not (n is int or n is float) or not is_finite(float(n)) or n<(1 if key=="range" else 0) or n>(128 if key=="range" else 2): return false
	return true

static func profile(item: Dictionary, activity: Dictionary = {}) -> Dictionary:
	var raw: Variant=item.get("audio",{})
	if not valid_source(raw) or not raw.get("enabled",true) or item.has("missing_asset"): return {}
	var kind: String=raw.get("kind","auto")
	if kind=="auto":
		for candidate in ACTIVITY_KINDS:
			if activity.has(candidate):
				kind = candidate
				break
		if kind == "auto": kind = definitions()["assets"].get(item["asset"],"none")
		if kind == "none" and preload("res://scripts/builder/business_plan.gd").profile(item)["kind"] != "none": kind = "shop"
	if kind=="none": return {}
	var result: Dictionary=definitions()["kinds"][kind].duplicate(true)
	result["kind"]=kind; result["gain"]*=float(raw.get("volume",1))*float(activity.get(kind,1)); result["range"]=float(raw.get("range",result["range"]))
	return result

static func point(values: Array,mode: String,height: float=0) -> Vector3:
	var horizontal: Vector2=Traffic.metric(values,mode)
	return Vector3(horizontal.x,height+float(values[2] if mode=="2d" else values[1]),horizontal.y)

static func emitters(data: Dictionary,library: RefCounted,hour: float=12,floor_height: float=0,scope: String="",instances: Dictionary={},activity: Dictionary={}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var mode: String = data["mode"]
	var sculpted: bool = Terrain.settings(data)["enabled"]
	var heights: Dictionary = Terrain.lookup(data) if sculpted else {}
	var waters: Dictionary = Terrain.lookup(data,true) if sculpted and scope in ["","city:"] else {}
	for item in data["objects"]:
		if not item.get("visible",true) or not Layers.shown(data,Layers.layer(item,library)) or library.assets.get(item["asset"],{}).get("unavailable",false): continue
		var states: Dictionary = activity.get(item["uid"],{})
		var value: Dictionary = profile(item,states)
		if value.is_empty(): continue
		var kind: String = value["kind"]
		if kind in ACTIVITY_KINDS and not states.has(kind): continue
		if kind in PLACE_KINDS and instances.has(item["uid"]):
			var instance: Node = instances[item["uid"]]
			if not is_instance_valid(instance) or not instance.is_visible_in_tree(): continue
		var box: Rect2=Zone.footprint(item,mode,library); var center: Vector2=box.get_center(); var anchor_height: float=0
		if kind == "harbor":
			if waters.is_empty(): continue
			var shore: Variant = harbor_shore(data,center,heights,waters)
			if shore == null: continue
			value["uid"] = scope+item["uid"]+":place:"+kind
			value["position"] = shore
			result.append(value)
			continue
		if kind=="shop":
			var business: Dictionary=preload("res://scripts/builder/business_plan.gd").profile(item)
			if business["kind"]!="none" and not preload("res://scripts/builder/business_plan.gd").open(business,hour): continue
		if kind in ["shop","school"] and instances.has(item["uid"]) and (preload("res://scripts/builder/asset_behavior.gd").for_asset(item["asset"],library).get("building",false) or item.get("interior") is Dictionary):
			var anchor: Variant=preload("res://scripts/builder/entrance_anchors.gd").position_for(instances[item["uid"]],item,mode,library,false)
			center=Traffic.metric([anchor.x,anchor.y,0],mode) if mode=="2d" else Vector2(anchor.x,anchor.z)
			if mode=="3d": anchor_height=anchor.y-float(item["position"][1])
		var elevation: float=float(item["position"][2] if mode=="2d" else item["position"][1])+floor_height+anchor_height
		if mode=="2d" and sculpted: elevation+=Terrain.sample(data,center,heights)["height"]
		value["uid"]=scope+item["uid"]
		if kind in PLACE_KINDS: value["uid"] += ":place:"+kind
		value["position"]=Vector3(center.x,elevation+(2.5 if kind=="birds" else .7),center.y)
		if kind == "market" and states.has("market_position"): value["position"] = states["market_position"]
		if value["kind"]=="birds" and data.get("night",false): value["gain"]*=.12
		result.append(value)
	return result

# A shoreline needs a dry walkable bank and two wet cells sharing an
# uninterrupted surface. Inspect only the immediate area of an authored anchor.
static func harbor_shore(data: Dictionary,center: Vector2,heights: Dictionary,waters: Dictionary) -> Variant:
	var origin := Vector2i((center/Terrain.CELL_SIZE).floor())
	var best: Variant = null
	var nearest: float = HARBOR_REACH*HARBOR_REACH
	var area: Rect2i = Terrain.bounds(data)
	for x in range(-4,5):
		for z in range(-4,5):
			var cell: Vector2i = origin+Vector2i(x,z)
			var record: Dictionary = waters.get(Terrain.key(cell),{})
			if record.is_empty(): continue
			var point: Vector2 = (Vector2(cell)+Vector2.ONE*.5)*Terrain.CELL_SIZE
			var distance: float = point.distance_squared_to(center)
			if distance >= nearest: continue
			var level: float = record["level"]
			if level-Terrain.sample(data,point,heights)["height"] < HARBOR_DEPTH: continue
			var connected: bool = false
			var bank: bool = false
			for direction in NEIGHBORS:
				var neighbor: Vector2i = cell+direction
				if not area.has_point(neighbor): continue
				var next: Vector2 = point+Vector2(direction)*Terrain.CELL_SIZE
				var surface: Dictionary = Terrain.sample(data,next,heights)
				var wet: Dictionary = waters.get(Terrain.key(neighbor),{})
				if wet.is_empty() or float(wet["level"])-surface["height"] <= .001:
					bank = bank or surface["normal"].y >= Terrain.WALKABLE_NORMAL
				elif is_equal_approx(wet["level"],level) and level-surface["height"] >= HARBOR_DEPTH:
					var edge: Vector2 = (point+next)*.5
					connected = connected or level-Terrain.sample(data,edge,heights)["height"] >= HARBOR_DEPTH
			if bank and connected:
				best = Vector3(point.x,level+.15,point.y)
				nearest = distance
	return best

static func interior(data: Dictionary,floor_height: float=0,scope: String="") -> Dictionary:
	var value: Dictionary=definitions()["kinds"]["interior"].duplicate(true)
	var home: Array=data.get("exit",data.get("spawn",[0,0,0]))
	value["kind"]="interior"; value["uid"]=scope+"room_tone"; value["position"]=point(home,data["mode"],floor_height)+Vector3.UP*.7
	if Terrain.settings(data)["enabled"] and (data["mode"]=="2d" or absf(float(home[1]))<=.35):
		value["position"].y+=Terrain.sample(data,Vector2(value["position"].x,value["position"].z),Terrain.lookup(data))["height"]
	return value

static func gain(source: Dictionary,listener: Vector3,config: Dictionary) -> float:
	if not config["enabled"] or config["volume"]<=0: return 0
	var radius: float=float(source["range"])*float(config["range_scale"]); var distance: float=source["position"].distance_to(listener)
	var inner: float=minf(2,radius*.2)
	var falloff: float=1-clampf((distance-inner)/maxf(.01,radius-inner),0,1)
	return clampf(float(source["gain"])*float(config["volume"])*float(config.get(source["kind"],0))*falloff*falloff,0,1)

static func mix(sources: Array,listener: Vector3,config: Dictionary,available: Callable=Callable()) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	if not listener.is_finite(): return result
	for source in sources:
		var level: float=gain(source,listener,config)
		if level<.0001 or (available.is_valid() and not available.call(source["kind"])): continue
		var value: Dictionary=source.duplicate(true); value["level"]=level; result.append(value)
	result.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return a["level"]>b["level"] if a["level"]!=b["level"] else str(a["uid"])<str(b["uid"]))
	var selection: Array[Dictionary] = []
	var seen: Dictionary = {}
	var places: Dictionary = {}
	for source in result:
		var uid: String = source["uid"]
		if seen.has(uid): continue
		var kind: String = source["kind"]
		if kind in PLACE_KINDS:
			var neighbors: Array = places.get(kind,[])
			var position: Vector3 = source["position"]
			if neighbors.size() >= PLACE_VOICES or neighbors.any(func(other: Vector3)->bool:
				return absf(other.y-position.y)<.75 and Vector2(other.x-position.x,other.z-position.z).length_squared()<2.25):
				continue
			neighbors.append(position)
			places[kind] = neighbors
		seen[uid] = true
		selection.append(source)
		if selection.size() == MAX_VOICES: break
	result = selection
	var power: float=0; var total: float=0
	for source in result: power+=float(source["level"])*float(source["level"]); total+=float(source["level"])
	var scale: float=minf(1,minf(.75/sqrt(maxf(.000001,power)),1.25/maxf(.000001,total)))
	for source in result: source["level"]*=scale
	return result

static func smooth(current: float,target: float,delta: float) -> float:
	if not is_finite(delta) or delta<=0: return current
	return lerpf(current,target,1-exp(-minf(delta,.25)/.18))
