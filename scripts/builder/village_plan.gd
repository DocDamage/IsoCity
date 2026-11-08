extends RefCounted

const PATH = "res://resources/catalog/village_production.json"
const Utility = preload("res://scripts/builder/utility_profiles.gd")
const Terrain = Utility.Terrain
const Traffic = Utility.Traffic
const Stock = preload("res://scripts/builder/activity_stock.gd")
const Citizens = preload("res://scripts/builder/citizen_plan.gd")
const Navigation = preload("res://scripts/builder/terrain_navigation.gd")
const Economy = preload("res://scripts/builder/economy_plan.gd")
const MAX_SITES = 24
const MAX_TRANSFERS = 8
const MAX_RECEIPTS = 128
const QUANTITY = 2
const MAX_GAP = 44.0
const DEFAULTS = {"enabled":false,"recipe":"","destination":"","transport":"porter"}
static var catalog: Dictionary

static func definitions() -> Dictionary:
	if catalog.is_empty():
		var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if source is Dictionary and source.get("version") == 1: catalog = source
	return catalog

static func goods() -> Dictionary: return definitions()["goods"]

static func title(good: String) -> String:
	return goods().get(good,{}).get("name",good)

static func valid_settings(value: Variant) -> bool:
	return value is Dictionary and value.get("enabled",false) is bool

static func enabled(data: Dictionary) -> bool:
	var value: Variant = data.get("village",{})
	return not data.get("interior_room",false) and valid_settings(value) and value.get("enabled",false)

static func valid_site(value: Variant) -> bool:
	if not valid_settings(value): return false
	var recipe: Variant = value.get("recipe","")
	var destination: Variant = value.get("destination","")
	return (recipe is String and (recipe.is_empty() or definitions()["recipes"].has(recipe))
		and destination is String and destination.length() <= 128
		and value.get("transport","porter") in ["porter","truck"])

static func profile(item: Dictionary, library: RefCounted) -> Dictionary:
	var id: String = item.get("asset","")
	if item.has("missing_asset") or not library.assets.has(id): return {}
	var family: String = library.assets[id]["data"].get("family_id","")
	var role: String = definitions()["families"].get(family,definitions()["assets"].get(id,""))
	if role.is_empty(): return {}
	var result: Dictionary = definitions()["roles"][role].duplicate()
	result["role"] = role
	result["family"] = family if not family.is_empty() else id
	return result

static func config(item: Dictionary, facility: Dictionary) -> Dictionary:
	var result: Dictionary = DEFAULTS.duplicate()
	var raw: Variant = item.get("village",{})
	if valid_site(raw): result.merge(raw,true)
	if result["recipe"].is_empty() and not facility["recipes"].is_empty(): result["recipe"] = facility["recipes"][0]
	return result

static func copy_link(item: Dictionary, identities: Dictionary) -> void:
	var value: Variant = item.get("village",{})
	if not valid_site(value) or value.get("destination","").is_empty(): return
	value["destination"] = identities.get(value["destination"],"")

static func key(uid: String, good: String) -> String:
	return JSON.stringify([uid,good])

static func metric(point: Vector2, mode: String) -> Vector2:
	return Citizens.metric(Traffic.world(point,mode),mode)

static func terrain_point(point: Vector2, mode: String) -> Vector2:
	return Vector2(point.x+point.y,point.y-point.x) if mode == "2d" else point

static func projected(box: Rect2, mode: String) -> Rect2:
	var result := Rect2(metric(box.position,mode),Vector2.ZERO)
	for point in [box.end,Vector2(box.position.x,box.end.y),Vector2(box.end.x,box.position.y)]:
		result = result.expand(metric(point,mode))
	return result

static func approaches(bounds: Rect2, data: Dictionary, heights: Dictionary, waters: Dictionary, obstacles: Array[Rect2]) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for side in ["south","east","west","north"]:
		var point: Vector2 = Utility.side_point(bounds,side,1.65)
		if obstacles.any(func(box: Rect2)->bool: return box.grow(.54).has_point(point)): continue
		if Terrain.settings(data)["enabled"]:
			var ground: Vector2 = terrain_point(point,data["mode"])
			var surface: Dictionary = Terrain.sample(data,ground,heights)
			var water: Variant = Terrain.water_level(data,ground,heights,waters)
			if (not surface["inside"] or surface["normal"].y < Terrain.WALKABLE_NORMAL
				or (water != null and float(water)-surface["height"] > Terrain.WADING_DEPTH)):
				continue
		result.append(point)
	return result

static func cycles(sites: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for uid in sites:
		var steps: Array[String] = []
		var at: String = uid
		while sites.has(at) and not sites[at]["profile"]["ships"].is_empty():
			var repeated: int = steps.find(at)
			if repeated >= 0:
				for entry in steps.slice(repeated): result[entry] = true
				break
			steps.append(at)
			at = sites[at]["config"]["destination"]
	return result

static func link(site: Dictionary, sites: Dictionary, loops: Dictionary, obstacles: Array[Rect2]) -> Dictionary:
	var destination: String = site["config"]["destination"]
	if destination.is_empty(): return {"reason":"Link a destination to ship stock."}
	var target: Dictionary = sites.get(destination,{})
	if target.is_empty(): return {"reason":"The linked destination is missing or disabled."}
	var good: String = site["profile"]["ships"]
	if good.is_empty() or good not in target["profile"]["accepts"]:
		return {"reason":"The destination cannot accept "+title(good)+"."}
	if loops.has(site["uid"]): return {"reason":"Circular supply link. Change a destination to open the chain."}
	if not site["reason"].is_empty() or not target["reason"].is_empty(): return {"reason":"A transfer stop is blocked."}
	var transport: String = site["config"]["transport"]
	if transport == "truck":
		return {"reason":"","transport":transport,"target":destination,"good":good,"path":PackedVector2Array()}
	for from in site["points"]:
		for to in target["points"]:
			if from.distance_to(to) > MAX_GAP or from.distance_to(to) < 1.0: continue
			var route: Dictionary = Citizens.route(from,to,obstacles,.23)
			if route["path"].is_empty() or from.distance_to(route["start"]) > .65 or to.distance_to(route["goal"]) > .65: continue
			var path: PackedVector2Array = route["path"]
			path.insert(0,from)
			path.append(to)
			return {"reason":"","transport":transport,"target":destination,"good":good,"path":path}
	return {"reason":"No dry walking route connects these facilities."}

static func compile(data: Dictionary, library: RefCounted) -> Dictionary:
	var sites: Dictionary = {}
	if not enabled(data): return sites
	var candidates: Array[Dictionary] = []
	for item in data["objects"]:
		var value: Variant = item.get("village",{})
		if not valid_site(value) or not value.get("enabled",false): continue
		var facility: Dictionary = profile(item,library)
		if not facility.is_empty(): candidates.append({"item":item,"profile":facility})
	if candidates.is_empty(): return sites
	candidates.sort_custom(func(a: Dictionary,b: Dictionary)->bool: return a["item"]["uid"] < b["item"]["uid"])
	var mode: String = data["mode"]
	var obstacles: Array[Rect2] = Navigation.obstacles(data,mode == "2d")
	for item in data["objects"]:
		if not Utility.availability(item,library,data).is_empty(): continue
		var behavior: Dictionary = library.assets[item["asset"]].get("behavior",{})
		if (not behavior.get("ground",false) and behavior.get("collision","box") != "none"
			and absf(item["position"][2 if mode == "2d" else 1]) <= 1.4):
			obstacles.append(projected(Utility.footprint(item,library,mode),mode))
	var heights: Dictionary = Terrain.lookup(data)
	var waters: Dictionary = Terrain.lookup(data,true)
	for entry in candidates.slice(0,MAX_SITES):
		var item: Dictionary = entry["item"]
		var facility: Dictionary = entry["profile"]
		var settings: Dictionary = config(item,facility)
		var bounds: Rect2 = projected(Utility.footprint(item,library,mode),mode)
		var reason: String = Utility.availability(item,library,data)
		var points: Array[Vector2] = []
		if reason.is_empty():
			points = approaches(bounds,data,heights,waters,obstacles)
			if points.is_empty(): reason = "Clear a dry approach to the facility."
			elif not settings["recipe"].is_empty() and settings["recipe"] not in facility["recipes"]:
				reason = "Choose a recipe for this building family."
		var uid: String = item["uid"]
		sites[uid] = {"uid":uid,"name":str(item.get("name",facility["name"])),"item":item,"profile":facility,"config":settings,
			"owner":[facility["family"],facility["role"]],"batch":[facility["family"],settings["recipe"],bounds],
			"points":points,"reason":reason}
	var loops: Dictionary = cycles(sites)
	for uid in sites:
		sites[uid]["link"] = link(sites[uid],sites,loops,obstacles)
	return sites

static func required_delivery_art(data: Dictionary) -> Array[String]:
	if enabled(data) and data.get("objects",[]).any(func(item: Dictionary)->bool:
		var value: Variant = item.get("village",{})
		return valid_site(value) and value.get("enabled",false) and value.get("transport","porter") == "truck"):
		return ["2d:crate"] if data["mode"] == "2d" else ["3d:HanX_Shop/Cardboard_Boxes"]
	return []
