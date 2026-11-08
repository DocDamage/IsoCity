extends RefCounted

const PATH="res://resources/catalog/vehicle_services.json"
const Drive=preload("res://scripts/builder/driving_plan.gd")
const Traffic=preload("res://scripts/builder/traffic_plan.gd")
const Anchors=preload("res://scripts/builder/entrance_anchors.gd")
const Terrain=preload("res://scripts/builder/terrain_plan.gd")
const Economy=preload("res://scripts/builder/economy_plan.gd")
const MAX_BAYS: int=128
const CLASSES: Array[String]=["car","van","heavy"]
const TITLES: Dictionary={"fuel":"Refuel","charge":"Recharge","wash":"Wash vehicle","repair":"Repair vehicle"}
const VEHICLE: Dictionary={"enabled":false,"energy":"fuel","class":"car","capacity":100.0,"initial":40.0,"condition":70.0,"cleanliness":35.0,"use_per_metre":.35}
const BAY: Dictionary={"enabled":false,"offset_x":0.0,"offset_z":0.0,"yaw":0.0,"width":3.8,"length":6.0,"approach":18.0,"queue":3,"price":0,"seconds":4.0}
const VEHICLE_RANGES: Dictionary={"capacity":[1,250],"initial":[0,250],"condition":[0,100],"cleanliness":[0,100],"use_per_metre":[.05,5]}
const BAY_RANGES: Dictionary={"offset_x":[-32,32],"offset_z":[-32,32],"yaw":[0,360],"width":[2,12],"length":[3,24],"approach":[2,80],"seconds":[.5,90]}
static var catalog: Dictionary={}

static func definitions() -> Dictionary:
	if catalog.is_empty():
		var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if raw is Dictionary and raw.get("version")==1: catalog=raw
	return catalog

static func vehicle_asset(item: Dictionary) -> bool:
	return Drive.definitions().get("assets",{}).has(item.get("asset",""))

static func site_asset(item: Dictionary) -> bool:
	return definitions().get("sites",{}).has(item.get("asset",""))

static func values(defaults: Dictionary,raw: Variant) -> Dictionary:
	var result: Dictionary=defaults.duplicate()
	if raw is Dictionary:
		for key in defaults:
			if raw.has(key): result[key]=raw[key]
	return result

static func vehicle_settings(item: Dictionary) -> Dictionary:
	var defaults: Dictionary=VEHICLE.duplicate()
	defaults["class"]=definitions().get("vehicle_classes",{}).get(item.get("asset",""),"car")
	return values(defaults,item.get("vehicle_care",{}))

static func bay_settings(item: Dictionary) -> Dictionary:
	var defaults: Dictionary=BAY.duplicate()
	var source: Dictionary=definitions().get("sites",{}).get(item.get("asset",""),{})
	for key in BAY:
		if source.has(key): defaults[key]=source[key]
	return values(defaults,item.get("vehicle_bay",{}))

static func numeric(value: Variant,bounds: Array) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and value>=bounds[0] and value<=bounds[1]

static func valid_fields(raw: Variant,defaults: Dictionary,ranges: Dictionary) -> bool:
	if not raw is Dictionary or raw.has("enabled") and not raw["enabled"] is bool: return false
	for key in raw:
		if not defaults.has(key) or ranges.has(key) and not numeric(raw[key],ranges[key]): return false
	return true

static func valid_vehicle(item: Dictionary) -> bool:
	var raw: Variant=item.get("vehicle_care",{})
	if not vehicle_asset(item) or not valid_fields(raw,VEHICLE,VEHICLE_RANGES): return false
	var config: Dictionary=vehicle_settings(item)
	return config["energy"] in ["fuel","charge"] and config["class"] in CLASSES and config["initial"]<=config["capacity"]

static func valid_bay(item: Dictionary) -> bool:
	var raw: Variant=item.get("vehicle_bay",{})
	if not site_asset(item) or not valid_fields(raw,BAY,BAY_RANGES): return false
	var config: Dictionary=bay_settings(item)
	return Economy.integer(config["queue"],0,8) and Economy.integer(config["price"],0,100000)

static func vehicle(item: Dictionary) -> Dictionary:
	var raw: Variant=item.get("vehicle_care",{})
	if item.has("missing_asset") or not raw is Dictionary or not raw.get("enabled",false) or not valid_vehicle(item) or Drive.profile(item).is_empty(): return {}
	return vehicle_settings(item)

static func bay(item: Dictionary) -> Dictionary:
	var raw: Variant=item.get("vehicle_bay",{})
	if item.has("missing_asset") or not raw is Dictionary or not raw.get("enabled",false) or not valid_bay(item): return {}
	var result: Dictionary=bay_settings(item)
	var source: Dictionary=definitions()["sites"][item["asset"]]
	result["kind"]=source["kind"]
	result["classes"]=source["classes"]
	return result

static func metric(value: Variant,mode: String) -> Vector2:
	return Traffic.metric([value.x,value.y,0] if mode=="2d" else [value.x,value.y,value.z],mode)

static func layout(item: Dictionary,node: Node,mode: String,library: RefCounted) -> Dictionary:
	var result: Dictionary=bay(item)
	if result.is_empty() or not is_instance_valid(node) or not node.visible or not library.assets.has(item["asset"]): return {}
	if absf(float(item.get("tilt",[0,0])[0]))>1 or absf(float(item.get("tilt",[0,0])[1]))>1: return {}
	var start:=Vector3(result["offset_x"],0,result["offset_z"])
	var yaw: float=deg_to_rad(result["yaw"])
	var end: Vector3=start+Vector3(sin(yaw),0,cos(yaw))
	var center: Variant=Anchors.source_position(node,item,mode,library,start)
	var guide: Variant=Anchors.source_position(node,item,mode,library,end)
	result["center"]=metric(center,mode)
	result["axis"]=result["center"].direction_to(metric(guide,mode))
	if result["axis"].is_zero_approx(): return {}
	result["height"]=float(item["position"][2]) if mode=="2d" else center.y
	result["uid"]=item["uid"]
	result["name"]=str(item.get("name",library.assets[item["asset"]]["name"]))
	return result

static func protected_area(item: Dictionary,mode: String,library: RefCounted) -> Rect2:
	var config: Dictionary=bay(item)
	if config.is_empty() or not library.assets.has(item["asset"]): return Rect2()
	var source=load("res://scripts/builder/resident_activity_plan.gd")
	var origin:=Vector3(config["offset_x"],0,config["offset_z"])
	var yaw: float=deg_to_rad(config["yaw"])
	var a: Vector3=source.point(item,origin,mode,library,true)
	var b: Vector3=source.point(item,origin+Vector3(sin(yaw),0,cos(yaw)),mode,library,true)
	var center: Vector2=metric(Vector2(a.x,a.y) if mode=="2d" else a,mode)
	var axis: Vector2=center.direction_to(metric(Vector2(b.x,b.y) if mode=="2d" else b,mode))
	var side: Vector2=Vector2(axis.y,-axis.x)*float(config["width"])*.5
	var entry: Vector2=center-axis*(config["length"]*.5+config["approach"])
	var exit: Vector2=center+axis*config["length"]*.5
	return Rect2(entry-side,Vector2.ZERO).expand(entry+side).expand(exit-side).expand(exit+side).grow(.05)

static func support(bay_value: Dictionary,data: Dictionary,heights: Dictionary,waters: Dictionary) -> bool:
	if not Terrain.settings(data)["enabled"]: return absf(bay_value["height"])<=.5
	var center: Vector2=bay_value["center"]
	var axis: Vector2=bay_value["axis"]
	var side:=Vector2(-axis.y,axis.x)
	var middle: Dictionary=Terrain.sample(data,center,heights)
	if absf(bay_value["height"]-middle["height"])>.5: return false
	for offset in [Vector2.ZERO,-axis*bay_value["length"]*.5,axis*bay_value["length"]*.5,-side*bay_value["width"]*.5,side*bay_value["width"]*.5]:
		var point: Vector2=center+offset
		var sample: Dictionary=Terrain.sample(data,point,heights)
		var water: Variant=Terrain.water_level(data,point,heights,waters)
		if sample["normal"].y<.94 or absf(sample["height"]-middle["height"])>.5 or water!=null and water-sample["height"]>.26: return false
	return true

static func geometry(vehicle_pose: Dictionary,bay_value: Dictionary) -> Dictionary:
	var axis: Vector2=bay_value["axis"]
	var heading: Vector2=vehicle_pose["heading"]
	var dimensions: Vector2=vehicle_pose["extent"]
	var relative: Vector2=vehicle_pose["point"]-bay_value["center"]
	var along: float=relative.dot(axis)
	var across: float=absf(relative.cross(axis))
	var alignment: float=absf(heading.dot(axis))
	var skew: float=absf(heading.cross(axis))
	var half_length: float=dimensions.y*alignment+dimensions.x*skew
	var half_width: float=dimensions.x*alignment+dimensions.y*skew
	var in_bay: bool=across+half_width<=bay_value["width"]*.5+.01 and absf(along)+half_length<=bay_value["length"]*.5+.01
	var approach: bool=across<=bay_value["width"]*.5+.55 and along<=bay_value["length"]*.5+.55 and along>=-bay_value["length"]*.5-bay_value["approach"]
	return {"in_bay":in_bay and alignment>=.94,"approach":approach,"alignment":alignment}

static func reason(config: Dictionary,vehicle_pose: Dictionary,bay_value: Dictionary) -> String:
	if not bay_value.get("supported",true): return "This bay needs a dry, level approach."
	if config["class"] not in bay_value["classes"]: return "This bay does not accept that vehicle class."
	if bay_value["kind"] in ["fuel","charge"] and config["energy"]!=bay_value["kind"]:
		return "This vehicle needs a charger." if config["energy"]=="charge" else "This vehicle needs a fuel pump."
	var extent: Vector2=vehicle_pose["extent"]
	if extent.x*2>bay_value["width"] or extent.y*2>bay_value["length"]: return "This vehicle is too wide or too long for the bay."
	if not geometry(vehicle_pose,bay_value)["approach"]: return "Drive along the marked bay approach."
	if absf(vehicle_pose.get("speed",0.0))>.2: return "Brake to a stop before requesting service."
	return ""

static func initial(config: Dictionary) -> Dictionary:
	return {"energy":float(config["initial"]),"condition":float(config["condition"]),"cleanliness":float(config["cleanliness"])}

static func result(state: Dictionary,config: Dictionary,kind: String) -> Dictionary:
	var next: Dictionary=state.duplicate()
	match kind:
		"fuel","charge": next["energy"]=float(config["capacity"])
		"repair": next["condition"]=100.0
		"wash": next["cleanliness"]=100.0
	return next
