extends RefCounted

const PATH = "res://resources/catalog/pets.json"
const Floors = preload("res://scripts/builder/floor_plan.gd")
const Props = preload("res://scripts/builder/prop_plan.gd")
const Utility = preload("res://scripts/builder/utility_profiles.gd")
const Routes = preload("res://scripts/builder/citizen_plan.gd")
const Terrain = Utility.Terrain
const DEFAULTS = {"enabled":false,"asset":"","home":"","building":"","floor":"ground","park":"","leash":12.0}
const MAX_LEASH = 20.0
const MIN_LEASH = 6.0
const ARRIVAL = .24
static var catalog: Dictionary = {}

static func definitions() -> Dictionary:
	if catalog.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if data is Dictionary and data.get("version") == 1: catalog = data
	return catalog

static func species(id: String) -> String:
	for kind in definitions().get("species",{}):
		if id in catalog["species"][kind]: return kind
	return ""

static func supported(id: String, library: RefCounted) -> bool:
	if species(id).is_empty() or not library.assets.has(id): return false
	var asset: Dictionary = library.assets[id]
	var views: Dictionary = asset["data"].get("directions",{})
	return asset["category"] == "Pets" and ResourceLoader.exists(asset["path"]) and catalog["views"].all(
		func(direction: String)->bool: return views.has(direction) and not str(views[direction].get("file","")).is_empty())

static func valid(value: Variant) -> bool:
	if not value is Dictionary or not value.get("enabled",false) is bool: return false
	for key in ["asset","home","building","floor","park"]:
		if not value.get(key,DEFAULTS[key]) is String or value.get(key,DEFAULTS[key]).length() > 128: return false
	var distance: Variant = value.get("leash",DEFAULTS["leash"])
	return Floors.number(distance) and distance >= MIN_LEASH and distance <= MAX_LEASH

static func settings(data: Dictionary) -> Dictionary:
	var result: Dictionary = DEFAULTS.duplicate()
	var raw: Variant = data.get("pet",{})
	if valid(raw): result.merge(raw,true)
	return result

static func required(data: Dictionary) -> String:
	var config: Dictionary = settings(data)
	return config["asset"] if config["enabled"] and not species(config["asset"]).is_empty() else ""

static func object(data: Dictionary, uid: String) -> Dictionary:
	if uid.is_empty(): return {}
	for item in data.get("objects",[]):
		if item["uid"] == uid: return item
	return {}

static func home_scope(config: Dictionary) -> String:
	return "city:" if config["building"].is_empty() else "room:"+config["building"]+":"+config["floor"]+":"

static func home_world(data: Dictionary, config: Dictionary) -> Dictionary:
	if config["building"].is_empty(): return data
	var host: Dictionary = object(data,config["building"])
	return Floors.room(host.get("interior",{}),config["floor"])

static func fixture(item: Dictionary, role: String) -> bool:
	return item.get("asset","") in definitions().get(role,[])

static func fixture_points(item: Dictionary, role: String, library: RefCounted, mode: String) -> Array[Vector2]:
	var bounds: Rect2 = Utility.footprint(item,library,mode)
	var projected := Rect2(metric(bounds.position,mode),Vector2.ZERO)
	for vertex in [bounds.end,Vector2(bounds.position.x,bounds.end.y),Vector2(bounds.end.x,bounds.position.y)]:
		projected = projected.expand(metric(vertex,mode))
	var result: Array[Vector2] = []
	if role == "rest": result.append(projected.get_center())
	for clearance in [1.1,1.85]:
		for side in ["south","east","west","north"]:
			result.append(Utility.side_point(projected,side,clearance))
	return result

static func metric(point: Vector2, mode: String) -> Vector2:
	return Routes.metric(Utility.Traffic.world(point,mode),mode)

static func terrain_point(point: Vector2, mode: String) -> Vector2:
	return Vector2(point.x+point.y,point.y-point.x) if mode == "2d" else point

static func eligible(config: Dictionary, data: Dictionary, library: RefCounted) -> String:
	if not supported(config["asset"],library): return "Choose a supported Pixel cat or dog."
	var home: Dictionary = home_world(data,config)
	if not fixture(object(home,config["home"]),"rest"): return "Link a home resting mat."
	if not config["park"].is_empty() and (species(config["asset"]) != "dog" or not config["building"].is_empty()
		or not fixture(object(data,config["park"]),"park")): return "Link a dog station in the same outdoor world."
	return ""
