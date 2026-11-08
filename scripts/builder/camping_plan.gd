extends RefCounted

const PATH = "res://resources/catalog/camping.json"
const Utility = preload("res://scripts/builder/utility_profiles.gd")
const Traffic = Utility.Traffic
const Terrain = Utility.Terrain
const Citizens = preload("res://scripts/builder/citizen_plan.gd")
const Routes = preload("res://scripts/builder/terrain_navigation.gd")
const Hours = preload("res://scripts/builder/business_plan.gd")
const REFERENCES = ["park","activity"]
const MAX_SITES = 24
const MAX_CAPACITY = 4
const ARRIVAL_TIMEOUT = 40.0
const ACTIVITY_SECONDS = 4.0
const REST_SECONDS = 4.0
const HISTORY_LIMIT = 32
const DEFAULTS = {"enabled":false,"capacity":1,"open_hour":9.0,"close_hour":19.0,"checkout":8.0,
	"overnight":false,"park":"","activity":""}
static var catalog: Dictionary

static func definitions() -> Dictionary:
	if catalog.is_empty():
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if raw is Dictionary and raw.get("version") == 1: catalog = raw
	return catalog

static func enabled(data: Dictionary) -> bool:
	var value: Variant = data.get("camping",{})
	return valid_settings(value) and value.get("enabled",false)

static func valid_settings(value: Variant) -> bool:
	return value is Dictionary and value.get("enabled",false) is bool

static func number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= low and value <= high

static func valid_site(value: Variant) -> bool:
	if not valid_settings(value) or not value.get("overnight",false) is bool: return false
	var capacity: Variant = value.get("capacity",1)
	if not number(capacity,1,MAX_CAPACITY) or floorf(float(capacity)) != float(capacity): return false
	for key in ["open_hour","close_hour","checkout"]:
		if not number(value.get(key,DEFAULTS[key]),0,23.999): return false
	for key in REFERENCES:
		if not value.get(key,"") is String or value.get(key,"").length() > 128: return false
	return true

static func shelter(item: Dictionary) -> int:
	return int(definitions().get("shelters",{}).get(item.get("asset",""),0))

static func activity(item: Dictionary) -> String:
	return definitions().get("activities",{}).get(item.get("asset",""),"")

static func config(item: Dictionary) -> Dictionary:
	var settings: Variant = item.get("camping",{})
	var result: Dictionary = DEFAULTS.duplicate()
	if valid_site(settings): result.merge(settings,true)
	result["capacity"] = mini(int(result["capacity"]),shelter(item))
	return result

static func selected(item: Dictionary) -> bool:
	return shelter(item) > 0 and config(item)["enabled"]

static func copy_references(item: Dictionary, identities: Dictionary) -> void:
	var setting: Variant = item.get("camping",{})
	if not valid_site(setting): return
	for key in REFERENCES:
		var previous: String = setting.get(key,"")
		if identities.has(previous): setting[key] = identities[previous]
		elif not previous.is_empty():
			setting[key] = ""
			setting["enabled"] = false

static func due(config_value: Dictionary, time: float) -> float:
	var day: float = floorf(time/24.0)
	var hour: float = fposmod(time,24)
	var opening: float = config_value["open_hour"]
	var closing: float = config_value["close_hour"]
	if opening > closing and hour < closing: day -= 1
	if config_value["overnight"]: return (day+1)*24+config_value["checkout"]
	if is_equal_approx(opening,closing): return (day+1)*24
	return (day + (1 if opening > closing else 0))*24+closing

static func open(site: Dictionary, time: float) -> bool:
	var setting: Dictionary = site["config"]
	var hours: Dictionary = {"kind":"camp","open_hour":setting["open_hour"],"close_hour":setting["close_hour"]}
	return site["reason"].is_empty() and Hours.open(hours,time) and due(setting,time) > time

static func storm(weather: Dictionary) -> bool:
	return weather["rain"] >= .8 or weather["snow"] >= .8 or weather["wind_vector"].length() > .85

static func fire_safe(weather: Dictionary) -> bool:
	return weather["rain"] < .35 and weather["snow"] < .35 and weather["wind_vector"].length() <= .65

static func point(value: Vector2, mode: String) -> Vector2:
	return Citizens.metric(Traffic.world(value,mode),mode)

static func footprint_box(bounds: Rect2, mode: String) -> Rect2:
	var first: Vector2 = point(bounds.position,mode)
	var result := Rect2(first,Vector2.ZERO)
	for vertex in [bounds.end,Vector2(bounds.position.x,bounds.end.y),Vector2(bounds.end.x,bounds.position.y)]:
		result = result.expand(point(vertex,mode))
	return result

static func terrain_point(value: Vector2, mode: String) -> Vector2:
	return Vector2(value.x+value.y,value.y-value.x) if mode == "2d" else value

static func route_ok(a: Vector2,b: Vector2,obstacles: Array[Rect2]) -> bool:
	var route: Dictionary = Citizens.route(a,b,obstacles)
	return not route["path"].is_empty() and a.distance_to(route["start"]) <= .65 and b.distance_to(route["goal"]) <= .65

static func floor_reason(data: Dictionary, samples: Array, heights: Dictionary, waters: Dictionary) -> String:
	if not Terrain.settings(data)["enabled"]: return ""
	for point_value in samples:
		var ground: Dictionary = Terrain.sample(data,point_value,heights)
		var depth: Variant = Terrain.water_level(data,point_value,heights,waters)
		if depth != null and depth-ground["height"] > Terrain.WADING_DEPTH: return "The campsite or its approach is flooded."
		if not ground["inside"] or ground["normal"].y < Terrain.WALKABLE_NORMAL: return "The campsite needs a safe walking surface."
	return ""

static func compile(data: Dictionary, library: RefCounted, outdoors: bool) -> Dictionary:
	var found: Dictionary = {}
	var mode: String = data.get("mode","2d")
	var objects: Dictionary = {}
	var bounds: Dictionary = {}
	var candidates: Array = []
	for item in data.get("objects",[]):
		objects[item["uid"]] = item
		if selected(item): candidates.append(item)
	if candidates.is_empty(): return found
	candidates.sort_custom(func(a: Dictionary,b: Dictionary)->bool: return a["uid"] < b["uid"])
	var obstacles: Array[Rect2] = Routes.obstacles(data,mode == "2d")
	for item in objects.values():
		if not Utility.availability(item,library,data).is_empty(): continue
		bounds[item["uid"]] = Utility.footprint(item,library,mode)
		var behavior: Dictionary = library.assets[item["asset"]].get("behavior",{})
		if not behavior.get("ground",false) and behavior.get("collision","box") != "none" \
			and absf(item["position"][2 if mode == "2d" else 1]) <= 1.4:
			obstacles.append(footprint_box(bounds[item["uid"]],mode))
	var sculpted: bool = Terrain.settings(data)["enabled"]
	var heights: Dictionary = Terrain.lookup(data) if sculpted else {}
	var waters: Dictionary = Terrain.lookup(data,true) if sculpted else {}
	var stations: Dictionary = {}
	for item in candidates.slice(0,MAX_SITES):
		var settings: Dictionary = config(item)
		var uid: String = item["uid"]
		var site: Dictionary = {"uid":uid,"item":item,"config":settings,"reason":"","kind":"","points":[],
			"name":str(item.get("name",library.assets.get(item["asset"],{}).get("name","Campsite")))}
		found[uid] = site
		var park: Dictionary = objects.get(settings["park"],{})
		var destination: Dictionary = objects.get(settings["activity"],{})
		var role: String = activity(destination)
		var issue: String = ""
		if not bounds.has(uid): issue = "Show the campsite shelter and its layer."
		elif park.is_empty() or Citizens.role(park) != "park" or not bounds.has(park["uid"]): issue = "Link a visible park arrival."
		elif role.is_empty() or not bounds.has(destination["uid"]): issue = "Link a visible picnic or campfire station."
		elif settings["overnight"] and not outdoors: issue = "Overnight visits need an outdoor campsite."
		elif role == "fire" and not outdoors: issue = "Campfires require an outdoor site."
		if not issue.is_empty():
			site["reason"] = issue
			continue
		site["kind"] = role
		site["park"] = park
		site["activity"] = destination
		var fixture: String = destination["uid"]
		if stations.has(fixture):
			issue = "Each campsite needs its own activity station."
			found[stations[fixture]]["reason"] = issue
		stations[fixture] = uid
		var rest_bounds: Rect2 = bounds[uid]
		var activity_bounds: Rect2 = bounds[fixture]
		var rest: Vector2 = Utility.side_point(footprint_box(rest_bounds,mode),"south",1.65)
		var use: Vector2 = Utility.side_point(footprint_box(activity_bounds,mode),"south",1.6)
		var entry: Vector2 = Utility.side_point(footprint_box(bounds[park["uid"]],mode),"south",1.6)
		if rest.distance_to(entry) > 48 or rest.distance_to(use) > 18:
			issue = "Move the park arrival and activity closer to this shelter."
		elif role == "fire" and rest_bounds.grow(1.35).intersects(activity_bounds):
			issue = "Leave clear space between the fire and shelter."
		if issue.is_empty():
			issue = floor_reason(data,[terrain_point(entry,mode),terrain_point(rest,mode),terrain_point(use,mode),
				rest_bounds.get_center(),activity_bounds.get_center()],heights,waters)
		site["entry"] = entry
		for slot in settings["capacity"]:
			if not issue.is_empty(): break
			var offset: Vector2 = Vector2((slot-(settings["capacity"]-1)*.5)*1.05,0)
			var land: Vector2 = rest+offset
			var work: Vector2 = use+offset
			issue = floor_reason(data,[terrain_point(land,mode),terrain_point(work,mode)],heights,waters)
			if issue.is_empty() and (not route_ok(entry,land,obstacles) or not route_ok(land,work,obstacles)):
				issue = "No safe walking route connects the arrival, shelter and activity."
			site["points"].append({"shelter":land,"activity":work})
		site["reason"] = issue
		site["identity"] = [item.duplicate(true),park.duplicate(true),destination.duplicate(true)]
	return found
