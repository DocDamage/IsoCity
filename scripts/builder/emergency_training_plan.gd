extends RefCounted

const PATH = "res://resources/catalog/emergency_training.json"
const Service = preload("res://scripts/builder/service_plan.gd")
const Zone = preload("res://scripts/builder/zone_plan.gd")
const Repair = preload("res://scripts/builder/repair_assets.gd")
const Terrain = preload("res://scripts/builder/terrain_plan.gd")
const Site = preload("res://scripts/builder/terrain_site.gd")
const MAX_WALK = 85.0
const REACH = 1.55
static var catalog: Dictionary = {}

static func definitions() -> Dictionary:
	if catalog.is_empty():
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if raw is Dictionary and raw.get("version") == 1: catalog = raw["drills"]
	return catalog

static func recognized(id: Variant) -> bool:
	return id is String and definitions().has(id)

static func identity(value: Variant) -> bool:
	return value is String and not value.is_empty() and value.length() <= 128 and not value.contains("\n")

static func fields(id: String) -> Array[String]:
	var result: Array[String] = ["station", "desk", "incident", "subject"]
	if definitions().get(id, {}).has("kit"): result.append("kit")
	return result

static func valid(config: Dictionary) -> bool:
	var id: Variant = config.get("id")
	if not recognized(id) or not identity(config.get("attempt")): return false
	var recipe: Dictionary = definitions()[id]
	var keys: Array[String] = fields(id)
	if config.size() != keys.size() + 3: return false
	var seen: Dictionary = {}
	for key in keys:
		var uid: Variant = config.get(key)
		if not identity(uid) or seen.has(uid): return false
		seen[uid] = true
	var perimeter: Variant = config.get("perimeter")
	if not perimeter is Array or perimeter.size() != int(recipe["perimeter_count"]): return false
	for uid in perimeter:
		if not identity(uid) or seen.has(uid): return false
		seen[uid] = true
	return true

static func failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func matches(recipe: Dictionary, role: String, item: Dictionary, library: RefCounted) -> bool:
	var id: String = item.get("asset", "")
	if not library.assets.has(id): return false
	match role:
		"station":
			return id in recipe["station"] and Service.profile(item)["kind"] == recipe["service"]
		"incident":
			var behavior: Dictionary = preload("res://scripts/builder/asset_behavior.gd").for_asset(id, library)
			return (behavior.get("building", false) or item.has("interior")) and Service.profile(item)["kind"] == "none"
		"perimeter":
			return id in recipe["barriers"]
		_:
			return id in recipe.get(role, [])

static func eligible(recipe: Dictionary, role: String, item: Dictionary, data: Dictionary, library: RefCounted) -> bool:
	return matches(recipe, role, item, library) and Zone.usable(item, data, library)

static func walking_point(item: Dictionary, data: Dictionary, library: RefCounted, context: Dictionary, toward: Vector2) -> Dictionary:
	var box: Rect2 = Zone.footprint(item, data["mode"], library)
	var center: Vector2 = box.get_center()
	var choices: Array[Vector2] = []
	for offset in [1.45, 2.2]:
		var sides: Rect2 = box.grow(offset)
		choices.append_array([Vector2(center.x, sides.position.y), Vector2(center.x, sides.end.y),
			Vector2(sides.position.x, center.y), Vector2(sides.end.x, center.y)])
	choices.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_squared_to(toward) < b.distance_squared_to(toward))
	for point in choices:
		var stand := Rect2(point - Vector2.ONE * .42, Vector2.ONE * .84)
		if context["objects"].any(func(other: Rect2) -> bool: return other.intersects(stand)): continue
		var floor: Dictionary = Site.foundation(data, stand, context["heights"], context["waters"])
		if not floor["ok"]: continue
		var elevation: float = item["position"][2] if data["mode"] == "2d" else item["position"][1]
		if absf(elevation - (0.0 if data["mode"] == "2d" else float(floor["height"]))) > .7: continue
		return {"point": point, "height": floor["height"], "uid": item["uid"]}
	return {}

static func walk_connects(a: Vector2, b: Vector2, obstacles: Array[Rect2]) -> bool:
	if a.distance_to(b) > MAX_WALK: return false
	var route: Dictionary = Zone.Citizen.route(a, b, obstacles, .32)
	if route["path"].is_empty() or route["start"].distance_to(a) > 1.65 or route["goal"].distance_to(b) > 1.65: return false
	var points: PackedVector2Array = route["path"]
	var distance: float = 0.0
	for index in range(1, points.size()): distance += points[index - 1].distance_to(points[index])
	return distance <= MAX_WALK

static func asset_at(uid: String, items: Dictionary, recipe: Dictionary, role: String, data: Dictionary, library: RefCounted) -> Dictionary:
	var item: Dictionary = items.get(uid, {})
	if item.is_empty(): return failure("A drill placement is missing · " + role.capitalize() + ".")
	if not eligible(recipe, role, item, data, library) or not Repair.available(item["asset"], library, {}):
		return failure("Restore the visible prepared " + role + " for this drill.")
	return {"ok": true, "item": item}

static func inspect(data: Dictionary, library: RefCounted, service_plan: Dictionary = {}) -> Dictionary:
	var config: Variant = data.get("scenario")
	if not config is Dictionary or not valid(config): return failure("Choose a complete emergency drill setup.")
	if data.get("interior_room", false): return failure("Emergency drills run in the exterior city.")
	if not Service.settings(data)["enabled"]: return failure("Enable City Services before dispatching a drill.")
	var recipe: Dictionary = definitions()[config["id"]]
	var items: Dictionary = {}
	for item in data["objects"]: items[item["uid"]] = item
	var selected: Dictionary = {}
	for role in fields(config["id"]):
		var checked: Dictionary = asset_at(config[role], items, recipe, role, data, library)
		if not checked["ok"]: return checked
		selected[role] = checked["item"]
	var markers: Array[Dictionary] = []
	for uid in config["perimeter"]:
		var checked: Dictionary = asset_at(uid, items, recipe, "perimeter", data, library)
		if not checked["ok"]: return checked
		markers.append(checked["item"])
	var mode: String = data["mode"]
	var station: Vector2 = Zone.approach(selected["station"], mode, library)
	var incident: Vector2 = Zone.approach(selected["incident"], mode, library)
	var desk: Vector2 = Service.Traffic.metric(selected["desk"]["position"], mode)
	if station.distance_to(desk) > 12: return failure("Place the dispatch equipment within twelve metres of the selected station’s approach.")
	if station.distance_to(incident) < 12: return failure("Separate the station and incident approaches by at least twelve metres.")
	var approach: Dictionary = {config["station"]: Service.Traffic.world(station, mode, selected["station"]["position"][2 if mode == "2d" else 1]),
		config["incident"]: Service.Traffic.world(incident, mode, selected["incident"]["position"][2 if mode == "2d" else 1])}
	var response: Dictionary = service_plan if not service_plan.is_empty() else Service.build(data, library, approach)
	var trip: Dictionary = Service.choose(response, recipe["service"], config["incident"], {}, config["attempt"], config["station"])
	if not trip["ok"]: return failure("Response route · " + trip["reason"])
	var context: Dictionary = Zone.site_context(data, library)
	var obstacles: Array[Rect2] = []
	obstacles.assign(context["objects"] + context["terrain_obstacles"])
	var steps: Dictionary = {}
	steps["desk"] = walking_point(selected["desk"], data, library, context, station)
	if steps["desk"].is_empty(): return failure("Clear a dry standing point beside the dispatch equipment.")
	var previous: Vector2 = steps["desk"]["point"]
	var order: Array[Dictionary] = []
	if recipe.has("kit"):
		var kit: Vector2 = Service.Traffic.metric(selected["kit"]["position"], mode)
		if kit.distance_to(desk) > 12: return failure("Keep the kit near the dispatch equipment.")
		order.append({"role": "kit", "item": selected["kit"]})
	for index in markers.size():
		var item: Dictionary = markers[index]
		var box: Rect2 = Zone.footprint(item, mode, library)
		if box.get_center().distance_to(incident) > 24: return failure("Keep perimeter points near the incident.")
		if context["roads"].any(func(other: Rect2) -> bool: return other.intersects(box.grow(.2))):
			return failure("Place training barriers off the response road.")
		order.append({"role": "perimeter_%d" % index, "item": item})
	var subject: Vector2 = Service.Traffic.metric(selected["subject"]["position"], mode)
	if subject.distance_to(incident) > 24: return failure("Keep the participant near the incident.")
	order.append({"role": "subject", "item": selected["subject"]})
	for step in order:
		var point: Dictionary = walking_point(step["item"], data, library, context, previous)
		if point.is_empty() or not walk_connects(previous, point["point"], obstacles):
			return failure("No clear walking route to " + step["role"].replace("_", " ") + ".")
		steps[step["role"]] = point
		previous = point["point"]
	if not walk_connects(previous, steps["desk"]["point"], obstacles):
		return failure("No clear walking return to the dispatch desk.")
	var service_sites: Array = []
	for role in ["station", "incident"]:
		var placement: Dictionary = selected[role]
		service_sites.append([placement["uid"], placement["asset"], placement["position"], placement["direction"],
			placement["scale"], placement.get("angle", 0), placement.get("tilt", [])])
	return {"ok": true, "reason": "", "steps": steps, "trip": trip, "service_sites": service_sites,
		"service": recipe["service"], "subject_action": recipe["subject_action"]}

static func begin(data: Dictionary, library: RefCounted, config: Dictionary) -> Dictionary:
	var candidate: Dictionary = data.duplicate(true)
	candidate["scenario"] = config.duplicate(true)
	var check: Dictionary = inspect(candidate, library)
	return {"ok": true, "data": candidate} if check["ok"] else check

static func practice(data: Dictionary, library: RefCounted, id: String, attempt: String) -> Dictionary:
	if not recognized(id): return failure("Choose an emergency drill.")
	for key in ["objects", "tiles", "roads", "protected_areas", "water_cells", "terrain_vertices"]:
		if not data.get(key, []).is_empty(): return failure("Use a blank city for a practice drill.")
	var next: Dictionary = data.duplicate(true)
	var mode: String = next["mode"]
	var definition: Dictionary = definitions()[id]
	var config := {"id": id, "attempt": attempt, "perimeter": []}
	var roles: Array = [
		["station", definition["station"][0], Vector2(1, -10), .85],
		["desk", definition["desk"][0], Vector2(10, -9.5), 1.0],
		["incident", "2d:House_Blue", Vector2(34, -10), 1.0],
		["subject", "2d:Construction_Worker", Vector2(39, -10), 1.0]
	]
	if definition.has("kit"): roles.append(["kit", definition["kit"][0], Vector2(15, -9.5), 1.0])
	for index in int(definition["perimeter_count"]):
		roles.append(["perimeter_%d" % index, "3d:Fire_Station_PSX/traffic_cone" if id == "fire_drill" else "2d:Construction_Barrier", Vector2(27 + 4 * index, -8), 1.0])
	var doc = preload("res://scripts/builder/document.gd")
	for role in roles:
		var asset: String = role[1]
		if not Repair.available(asset, library, {}):
			return failure("Install the supplied drill artwork · " + asset)
		var uid: String = "training_" + role[0]
		var item: Dictionary = doc.placement_item(uid, asset, Service.Traffic.world(role[2], mode),
			str(library.directions(asset)[0]), role[3])
		item["name"] = str(role[0]).replace("_", " ").capitalize()
		if role[0] in ["station", "incident"]:
			var anchor: Vector2 = role[2] * 2.0 - Zone.approach(item, mode, library)
			item["position"] = Service.Traffic.world(anchor, mode)
		next["objects"].append(item)
		if str(role[0]).begins_with("perimeter_"): config["perimeter"].append(uid)
		else: config[role[0]] = uid
	var corners := [Vector2i(-2, 0), Vector2i(7, 0), Vector2i(7, 2), Vector2i(-2, 2)]
	var roads = preload("res://scripts/builder/roads.gd")
	for index in corners.size():
		roads.paint(next, corners[index], corners[(index + 1) % corners.size()], false,
			{"width": 6, "style": "asphalt", "sidewalks": true})
	next["services"] = {"enabled": true, "automatic": false, "interval": 30, "seed": 1}
	next["scenario"] = config
	var plan: Dictionary = inspect(next, library)
	if not plan["ok"]: return plan
	var spawn: Dictionary = plan["steps"]["desk"]
	next["spawn"] = Service.Traffic.world(spawn["point"], mode, spawn["height"] + (.025 if mode == "3d" else 0.0))
	return {"ok": true, "data": next}
