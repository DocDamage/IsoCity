extends RefCounted

const Layers = preload("res://scripts/builder/layers.gd")
const Roads = preload("res://scripts/builder/roads.gd")
const RoadSettings = preload("res://scripts/builder/road_settings.gd")
const Traffic = preload("res://scripts/builder/traffic_plan.gd")
const Zone = preload("res://scripts/builder/zone_plan.gd")
const Props = preload("res://scripts/builder/prop_plan.gd")
const Terrain = preload("res://scripts/builder/terrain_plan.gd")
const Connector = preload("res://scripts/builder/connector_plan.gd")
const SourceAssets = preload("res://scripts/builder/repair_assets.gd")
const MAX_OBJECTS = 256
const MAX_ROADS = 64

static func failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func identity(value: Variant) -> bool:
	return value is String and not value.is_empty() and value.length() <= 128

static func coordinates(value: Variant, count: int, limit: float, integral: bool = false) -> bool:
	if not value is Array or value.size() != count:
		return false
	for number in value:
		if not (number is int or number is float) or not is_finite(float(number)) or absf(number) > limit:
			return false
		if integral and float(number) != floorf(number):
			return false
	return true

static func road_valid(road: Variant) -> bool:
	if not road is Dictionary or not road.get("settings",{}) is Dictionary or not RoadSettings.valid(road.get("settings", {})):
		return false
	if not coordinates(road.get("start"), 2, 10000, true) or not coordinates(road.get("end"), 2, 10000, true):
		return false
	return road_length(road) <= 256

static func road_length(road: Dictionary) -> int:
	return 1 + absi(int(road["end"][0]) - int(road["start"][0])) + absi(int(road["end"][1]) - int(road["start"][1]))

# Inspect nested collections before calling Document.valid. Assembly templates
# contain room content, with no recursively embedded construction proposals.
static func bounded_scope(scope: Variant, count: Array, depth: int = 0) -> bool:
	if not scope is Dictionary or depth > 4 or not scope.get("objects") is Array or not scope.get("floors", []) is Array:
		return false
	for field in ["blueprints", "zones", "transit_lines"]:
		if scope.has(field) and scope[field] != []:
			return false
	for item in scope["objects"]:
		count[0] += 1
		if count[0] > MAX_OBJECTS or not item is Dictionary or not identity(item.get("uid")) or not item.get("asset") is String:
			return false
		if not coordinates(item.get("position"), 3, 100000):
			return false
		if item.has("interior") and not bounded_scope(item["interior"], count, depth + 1):
			return false
	if scope.get("floors", []).size() > 7:
		return false
	for floor in scope.get("floors", []):
		if not floor is Dictionary or not bounded_scope(floor.get("room"), count, depth + 1):
			return false
	return true

static func valid(entry: Dictionary, mode: String, library: RefCounted) -> bool:
	if entry.get("version") != 1 or not identity(entry.get("name")) or not entry.get("roads") is Array:
		return false
	if entry["roads"].size() > MAX_ROADS or not entry.get("connections", []) is Array or entry.get("connections", []).size() > 256:
		return false
	var edge_ids: Dictionary = {}
	for connection in entry.get("connections", []):
		if not Connector.record_valid(connection) or edge_ids.has(connection["uid"]):
			return false
		edge_ids[connection["uid"]] = true
		var outside: int = 0
		for endpoint in [connection["from"], connection["to"]]:
			if not endpoint.get("external", false) is bool:
				return false
			if endpoint.get("external", false): outside += 1
		if outside > 1:
			return false
	for road in entry["roads"]:
		if not road_valid(road):
			return false
	var scope: Dictionary = {"title": entry["name"], "mode": mode, "objects": entry.get("objects"), "tiles": [], "group_names": entry.get("group_names", {})}
	if not bounded_scope(scope, [0]) or scope["objects"].is_empty():
		return false
	# Document also validates proposal collections. The wrapper has none.
	if not load("res://scripts/builder/document.gd").valid(scope, mode, library):
		return false
	var declared: Variant = entry.get("external_targets", [])
	if not declared is Array or declared.size() > MAX_OBJECTS:
		return false
	var objects: Dictionary = {}
	for item in entry["objects"]:
		objects[item["uid"]] = item
	var seen: Dictionary = {}
	for reference in declared:
		if not reference is Dictionary or not identity(reference.get("object_uid")) or not identity(reference.get("target_uid")):
			return false
		var uid: String = reference["object_uid"]
		var target: String = reference["target_uid"]
		if seen.has(uid) or not objects.has(uid) or objects.has(target) or objects[uid].get("prop", {}).get("target", "") != target:
			return false
		seen[uid] = true
	return true

static func external_targets(items: Array) -> Array:
	var selected: Dictionary = {}
	for item in items:
		selected[item["uid"]] = true
	var result: Array = []
	for item in items:
		var target: String = item.get("prop", {}).get("target", "")
		if not target.is_empty() and not selected.has(target):
			result.append({"object_uid": item["uid"], "target_uid": target})
	return result

static func new_id(path: Array) -> String:
	return "assembly_" + JSON.stringify(path).sha256_text().substr(0, 32)

static func allocate(scope: Dictionary, path: Array) -> Dictionary:
	var maps: Dictionary = {"objects": {}, "groups": {}, "floors": {"ground": "ground"}, "links": {}, "entrances": {}, "rooms": {}, "upper_rooms": {}, "connections": {}}
	for item in scope["objects"]:
		var uid: String = item["uid"]
		maps["objects"][uid] = new_id(path + ["object", uid])
		if item.has("group"):
			maps["groups"][item["group"]] = new_id(path + ["group", item["group"]])
		if item.has("interior"):
			maps["rooms"][uid] = allocate(item["interior"], path + ["object", uid, "room"])
	for floor in scope.get("floors", []):
		var uid: String = floor["uid"]
		maps["floors"][uid] = new_id(path + ["floor", uid])
		maps["upper_rooms"][uid] = allocate(floor["room"], path + ["floor", uid])
	for link in scope.get("floor_links", []):
		maps["links"][link["uid"]] = new_id(path + ["link", link["uid"]])
	for entrance in scope.get("floor_entrances", []):
		maps["entrances"][entrance["uid"]] = new_id(path + ["entrance", entrance["uid"]])
	for link in scope.get("connections", []):
		maps["connections"][link["uid"]] = new_id(path + ["connection", link["uid"]])
	return maps

static func remapped_connections(links: Array, maps: Dictionary, original_ids: Dictionary) -> Dictionary:
	var result: Array = []
	for link in links:
		var copy: Dictionary = {"uid": maps["connections"][link["uid"]], "kind": link["kind"]}
		for side in ["from", "to"]:
			var endpoint: Dictionary = link[side]
			var uid: String = endpoint["object_uid"]
			if endpoint.get("external", false):
				if maps["objects"].has(uid) or not original_ids.has(uid):
					return failure("A required utility or structural socket target is absent from this city.")
			else:
				if not maps["objects"].has(uid):
					return failure("Resolve this assembly's utility or structural socket reference before construction.")
				uid = maps["objects"][uid]
			copy[side] = {"object_uid": uid, "socket": endpoint["socket"]}
		result.append(copy)
	return {"ok": true, "links": result}

static func resolve(scope: Dictionary, maps: Dictionary, exterior: bool) -> String:
	for item in scope["objects"]:
		var uid: String = item["uid"]
		var target: String = item.get("prop", {}).get("target", "")
		if not target.is_empty():
			if maps["objects"].has(target):
				item["prop"]["target"] = maps["objects"][target]
			elif not exterior:
				return "A copied room has a prop target outside its floor."
		item["uid"] = maps["objects"][uid]
		preload("res://scripts/builder/camping_plan.gd").copy_references(item,maps["objects"])
		preload("res://scripts/builder/cycling_plan.gd").copy_reference(item,maps["objects"])
		preload("res://scripts/builder/village_plan.gd").copy_link(item,maps["objects"])
		item.erase("zone_uid")
		if item.has("group"):
			item["group"] = maps["groups"][item["group"]]
		if item.has("interior"):
			var reason: String = resolve(item["interior"], maps["rooms"][uid], false)
			if not reason.is_empty():
				return reason
	if scope.has("group_names"):
		var names: Dictionary = {}
		for old in maps["groups"]:
			if scope["group_names"].has(old):
				names[maps["groups"][old]] = scope["group_names"][old]
		scope["group_names"] = names
	for floor in scope.get("floors", []):
		var old: String = floor["uid"]
		floor["uid"] = maps["floors"][old]
		var reason: String = resolve(floor["room"], maps["upper_rooms"][old], false)
		if not reason.is_empty():
			return reason
	for link in scope.get("floor_links", []):
		link["uid"] = maps["links"][link["uid"]]
		link["lower"] = maps["floors"][link["lower"]]
		link["upper"] = maps["floors"][link["upper"]]
	for entrance in scope.get("floor_entrances", []):
		entrance["uid"] = maps["entrances"][entrance["uid"]]
		entrance["floor"] = maps["floors"][entrance["floor"]]
	if not exterior and scope.has("connections"):
		var mapped: Dictionary = remapped_connections(scope["connections"], maps, {})
		if not mapped["ok"]: return mapped["reason"]
		scope["connections"] = mapped["links"]
	if scope.has("modular_rooms"):
		scope["modular_rooms"] = preload("res://scripts/builder/modular_building_plan.gd").copied(scope["modular_rooms"],maps["objects"],maps["groups"],maps["connections"])
	return ""

static func targets_valid(scope: Dictionary, library: RefCounted, selected: Array) -> bool:
	for item in selected:
		if not Props.profile(item).get("target", "").is_empty() and Props.target_record(item, scope, library).is_empty():
			return false
		if item.has("interior") and not targets_valid(item["interior"], library, item["interior"]["objects"]):
			return false
	for floor in scope.get("floors", []):
		if not targets_valid(floor["room"], library, floor["room"]["objects"]):
			return false
	return true

static func availability(scope: Dictionary, library: RefCounted, cache: Dictionary) -> String:
	for key in ["objects", "tiles"]:
		for record in scope.get(key, []):
			var asset: String = record["asset"]
			var missing: Variant = record.get("missing_asset")
			if record.has("missing_asset") or library.assets.get(asset, {}).get("unavailable", false) or not SourceAssets.available(asset, library, cache):
				var source: String = str(missing.get("id", asset)) if missing is Dictionary else asset
				return "Restore the source asset for " + source + " before construction."
			if record.has("interior"):
				var reason: String = availability(record["interior"], library, cache)
				if not reason.is_empty():
					return reason
	for floor in scope.get("floors", []):
		var reason: String = availability(floor["room"], library, cache)
		if not reason.is_empty():
			return reason
	return ""

static func append_to(entry: Dictionary, candidate: Dictionary, original_ids: Dictionary, library: RefCounted) -> Dictionary:
	var scope: Dictionary = {"objects": entry["objects"].duplicate(true), "group_names": entry.get("group_names", {}).duplicate(true), "connections": entry.get("connections", [])}
	var reason: String = availability(scope, library, {})
	if not reason.is_empty():
		return failure(reason)
	var declared: Array = entry.get("external_targets", [])
	for required in external_targets(scope["objects"]):
		if required not in declared:
			return failure("Declare the external prop target as a required connection before construction.")
		if not original_ids.has(required["target_uid"]):
			return failure("A required external prop target is absent from this city.")
	var maps: Dictionary = allocate(scope, [entry["uid"]])
	reason = resolve(scope, maps, true)
	if not reason.is_empty():
		return failure(reason)
	var occupied: Dictionary = {}
	for existing in candidate["objects"]:
		occupied[existing["uid"]] = true
	for item in scope["objects"]:
		if occupied.has(item["uid"]):
			return failure("An existing object already uses this assembly identity.")
		if not Layers.editable(candidate, item, library):
			return failure("Show and unlock every assembly object's destination layer before construction.")
	candidate["objects"].append_array(scope["objects"])
	if not scope["connections"].is_empty():
		var existing: Dictionary = {}
		for item in candidate["objects"]:
			if original_ids.has(item["uid"]): existing[item["uid"]] = item
		var cache: Dictionary = {}
		for edge in scope["connections"]:
			for side in ["from", "to"]:
				var reference: Dictionary = edge[side]
				if not reference.get("external", false): continue
				var target: Dictionary = existing.get(reference["object_uid"], {})
				if target.is_empty() or not Layers.editable(candidate, target, library) or not availability({"objects": [target]}, library, cache).is_empty():
					return failure("The required utility or structural socket target must be available and unlocked.")
		var links: Dictionary = remapped_connections(scope["connections"], maps, original_ids)
		if not links["ok"]: return links
		var proposed: Array = candidate.get("connections", []) + links["links"]
		if Connector.retained(candidate, proposed) != proposed:
			return failure("Assembly sockets must mate at the reviewed pose and both endpoints must be free.")
		candidate["connections"] = proposed

	if not scope["group_names"].is_empty():
		if not candidate.has("group_names"): candidate["group_names"] = {}
		candidate["group_names"].merge(scope["group_names"])
	if not targets_valid(candidate, library, scope["objects"]):
		return failure("A linked prop needs an available powered device in the same scope.")
	if not entry["roads"].is_empty() and (not Layers.shown(candidate, "Ground") or Layers.locked(candidate, "Ground")):
		return failure("Show and unlock Ground before building the assembly's roads.")
	var network: Dictionary = Roads.lookup(candidate)
	var road_cells: Dictionary = {}
	if not candidate.has("roads") and not entry["roads"].is_empty():
		candidate["roads"] = []
	for road in entry["roads"]:
		var profile: Dictionary = RoadSettings.profile(road["settings"])
		for cell in Roads.path(Vector2i(road["start"][0], road["start"][1]), Vector2i(road["end"][0], road["end"][1])):
			var key: String = Roads.key(cell)
			if network.has(key) and RoadSettings.profile(network[key]) != profile:
				return failure("An assembly road conflicts with the existing road profile at " + key + ".")
			if not network.has(key):
				if network.size() >= 4096:
					return failure("Construction exceeds the road section limit.")
				var section: Dictionary = {"cell": [cell.x, cell.y], "crossing": false}
				section.merge(profile)
				candidate["roads"].append(section)
				network[key] = section
				road_cells[key] = section
	return {"ok": true, "objects": scope["objects"], "roads": road_cells.values(), "remap": maps}

static func location(candidate: Dictionary, copies: Array, added_roads: Array, library: RefCounted) -> String:
	var mode: String = candidate["mode"]
	var identities: Dictionary = {}
	for item in copies:
		identities[item["uid"]] = true
	var obstructions: Dictionary = {}
	for item in candidate["objects"]:
		if Zone.usable(item, candidate, library) and not identities.has(item["uid"]) and Layers.layer(item, library) != "Ground":
			obstructions[item["uid"]] = Zone.footprint(item, mode, library)
	var road_bounds: Array[Rect2] = []
	for section in candidate.get("roads", []):
		var center: Vector2 = Traffic.center(Vector2i(section["cell"][0], section["cell"][1]), mode)
		var half: float = RoadSettings.half_width(section)
		road_bounds.append(Rect2(center - Vector2.ONE * half, Vector2.ONE * half * 2.0))
	var terrain_bounds := Rect2(Terrain.bounds(candidate))
	terrain_bounds = Rect2(terrain_bounds.position * 2.0, terrain_bounds.size * 2.0)
	var use_terrain: bool = Terrain.settings(candidate)["enabled"]
	var barriers: Array = preload("res://scripts/builder/terrain_navigation.gd").obstacles(candidate)
	var heights: Dictionary = Terrain.lookup(candidate) if use_terrain else {}
	var waters: Dictionary = Terrain.lookup(candidate,true) if use_terrain else {}
	var building_sites: Array[Rect2] = []
	for item in copies:
		var footprint: Rect2 = Zone.footprint(item, mode, library)
		var ground: bool = Layers.layer(item, library) == "Ground"
		if use_terrain and not terrain_bounds.encloses(footprint):
			return "An assembly object is outside the terrain bounds."
		if not ground:
			var mates: Dictionary = {}
			for link in candidate.get("connections", []):
				var a: String = link["from"]["object_uid"]
				var b: String = link["to"]["object_uid"]
				if a == item["uid"]: mates[b] = true
				if b == item["uid"]: mates[a] = true
			for uid in obstructions:
				if not mates.has(uid) and obstructions[uid].intersects(footprint):
					return "An assembly object overlaps existing city content."
		var building: bool = preload("res://scripts/builder/asset_behavior.gd").for_asset(item["asset"], library).get("building", false)
		if not building:
			continue
		if building_sites.any(func(rect: Rect2): return rect.intersects(footprint)):
			return "Two assembly buildings overlap."
		building_sites.append(footprint)
		if road_bounds.any(func(rect: Rect2): return rect.intersects(footprint)):
			return "An assembly building overlaps a road."
		if use_terrain:
			var foundation: Dictionary=preload("res://scripts/builder/terrain_site.gd").foundation(candidate,footprint,heights,waters)
			if not foundation["ok"]: return foundation["reason"]
		var entrance: Vector2 = Zone.approach(item, mode, library)
		if (use_terrain and not terrain_bounds.has_point(entrance)) or barriers.any(func(rect: Rect2): return rect.has_point(entrance)):
			return "An assembly building has an obstructed entrance approach."
		for other in candidate["objects"]:
			if other["uid"] == item["uid"] or not Zone.usable(other, candidate, library) or Layers.layer(other, library) == "Ground":
				continue
			if Zone.footprint(other, mode, library).has_point(entrance):
				return "An assembly building's entrance approach overlaps another object."
	for section in added_roads:
		var center: Vector2 = Traffic.center(Vector2i(section["cell"][0], section["cell"][1]), mode)
		if use_terrain and not terrain_bounds.has_point(center):
			return "An assembly road is outside the terrain bounds."
		if obstructions.values().any(func(rect: Rect2): return rect.has_point(center)):
			return "An assembly road is blocked by existing city content."
		if barriers.any(func(rect: Rect2): return rect.has_point(center)):
			return "An assembly road crosses an impassable terrain section."
	return ""
