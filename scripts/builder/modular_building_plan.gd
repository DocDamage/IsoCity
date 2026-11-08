extends RefCounted

const PATH = "res://resources/catalog/modular_building_kits.json"
const MAX_ROOMS = 32
const MAX_CORNERS = 24
const MAX_SPAN = 24
const MAX_PARTS = 256
const CONNECTOR = preload("res://scripts/builder/connector_plan.gd")
const ROTATION = preload("res://scripts/builder/rotation.gd")
const LAYERS = preload("res://scripts/builder/layers.gd")
const FIT = preload("res://scripts/builder/grid_fit.gd")
const SOURCES = preload("res://scripts/builder/repair_assets.gd")

static func kits() -> Dictionary:
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return catalog.get("kits", {}) if catalog is Dictionary and catalog.get("version") == 1 else {}

static func failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func identifier(value: Variant) -> bool:
	return value is String and not value.is_empty() and value.length() <= 128

static func integer(value: Variant, limit: int) -> bool:
	return (value is int or value is float) and is_finite(value) and absf(value) <= limit and floorf(value) == float(value)

static func point(value: Variant) -> bool:
	return value is Array and value.size() == 2 and integer(value[0], 10000) and integer(value[1], 10000)

static func slot(role: String, at: Vector2) -> String:
	return "%s/%d/%d" % [role, roundi(at.x), roundi(at.y)]

static func heading(direction: Vector2) -> int:
	if direction.x > 0: return 0
	if direction.y < 0: return 90
	if direction.x < 0: return 180
	return 270

static func corner_heading(incoming: Vector2, outgoing: Vector2) -> int:
	var sides: Array = [heading(-incoming), heading(outgoing)]
	for angle in sides:
		if (angle + 90) % 360 in sides:
			return angle
	return 0

static func axes_intersect(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var low: Vector2 = a.min(b).max(c.min(d))
	var high: Vector2 = a.max(b).min(c.max(d))
	return low.x <= high.x and low.y <= high.y

static func module(kit: Dictionary, role: String, at: Vector2, yaw: int = 0) -> Dictionary:
	var elevation: float = float(kit["floor_lift"]) if role == "floor" else 0.0
	return {"asset": kit["parts"][role], "position": [float(at.x), elevation, float(at.y)],
		"direction": ROTATION.angle_text(yaw), "scale": 1.0}

# Footprints are expressed in room-local Model world units. Slots name a physical
# position and axis so an opening never jumps to a new wall during a resize.
static func layout(kit: Dictionary, outline: Variant, openings: Variant) -> Dictionary:
	if kit.is_empty(): return failure("This modular kit is unavailable.")
	if not outline is Array or outline.size() < 4 or outline.size() > MAX_CORNERS:
		return failure("Draw a closed outline with 4 to 24 corners.")
	if not openings is Dictionary or openings.size() > MAX_PARTS:
		return failure("The room has an invalid opening list.")
	var panel: int = kit["wall_span"]
	var corner: int = kit["corner_reach"]
	var tile: int = kit["floor_span"]
	var vertices := PackedVector2Array()
	var seen: Dictionary = {}
	for coordinate in outline:
		if not point(coordinate): return failure("Use whole-number outline coordinates.")
		var at := Vector2(coordinate[0], coordinate[1])
		if posmod(int(at.x), tile) != 0 or posmod(int(at.y), tile) != 0:
			return failure("Place every outline corner on the %d-unit grid." % tile)
		if seen.has(at): return failure("The outline touches itself at a repeated corner.")
		seen[at] = true
		vertices.append(at)
	var area := Rect2(vertices[0], Vector2.ZERO)
	for at in vertices: area = area.expand(at)
	if area.size.x > MAX_SPAN or area.size.y > MAX_SPAN:
		return failure("A room outline can span at most %d units on either axis." % MAX_SPAN)
	for index in vertices.size():
		var start: Vector2 = vertices[index]
		var end: Vector2 = vertices[(index + 1) % vertices.size()]
		var delta: Vector2 = end - start
		if delta.x != 0 and delta.y != 0: return failure("Use straight, right-angle walls. Diagonals and curves need manual construction.")
		var previous: Vector2 = start - vertices[posmod(index - 1, vertices.size())]
		if previous.cross(delta) == 0: return failure("Each outline point must turn a corner.")
		var length: int = int(delta.length())
		if length < corner * 2 or (length - corner * 2) % panel != 0:
			return failure("Wall lengths must fit two corner ends and whole %d-unit bays." % panel)
		for other in range(index + 2, vertices.size()):
			if index == 0 and other == vertices.size() - 1: continue
			if axes_intersect(start, end, vertices[other], vertices[(other + 1) % vertices.size()]):
				return failure("An outline cannot cross or touch a nonadjacent wall.")
	var parts: Dictionary = {}
	var bays: Dictionary = {}
	for index in vertices.size():
		var at: Vector2 = vertices[index]
		var next: Vector2 = vertices[(index + 1) % vertices.size()]
		var delta: Vector2 = next - at
		var direction: Vector2 = delta.normalized()
		parts[slot("corner", at)] = module(kit, "corner", at,
			corner_heading(at - vertices[posmod(index - 1, vertices.size())], delta))
		for offset in range(corner, int(delta.length()) - corner, panel):
			var center: Vector2 = at + direction * (offset + panel / 2.0)
			var yaw: int = 0 if direction.x != 0 else 90
			var key: String = slot("x" if yaw == 0 else "z", center)
			var role: Variant = openings.get(key, "wall")
			if role not in ["wall", "door", "window"]:
				return failure("Choose a doorway or a window for each opening.")
			parts[key] = module(kit, role, center, yaw)
			bays[key] = {"position": center, "direction": yaw, "role": role}
	for key in openings:
		if not bays.has(key) or openings[key] not in ["door", "window"]:
			return failure("An opening overlaps a corner or its wall bay moved. Remove or reposition the opening.")
	for x in range(int(area.position.x), int(area.end.x), tile):
		for z in range(int(area.position.y), int(area.end.y), tile):
			var center := Vector2(x + tile / 2.0, z + tile / 2.0)
			if Geometry2D.is_point_in_polygon(center, vertices):
				parts[slot("floor", center)] = module(kit, "floor", center)
	if parts.size() > MAX_PARTS: return failure("This outline needs too many modules.")
	return {"ok": true, "parts": parts, "bays": bays, "outline": vertices, "bounds": area}

static func fingerprint(item: Dictionary) -> String:
	var payload: Dictionary = item.duplicate()
	payload.erase("uid")
	payload.erase("group")
	# JSON project loading normalizes integer literals to floats.
	return JSON.stringify(JSON.parse_string(JSON.stringify(payload))).sha256_text()

static func valid_record(value: Variant) -> bool:
	if not value is Dictionary or not identifier(value.get("uid")) or not identifier(value.get("kit")):
		return false
	if not value.get("outline") is Array or value["outline"].size() < 4 or value["outline"].size() > MAX_CORNERS:
		return false
	if not value["outline"].all(point): return false
	if not value.get("openings") is Dictionary or value["openings"].size() > MAX_PARTS:
		return false
	for key in value["openings"]:
		if not identifier(key) or value["openings"][key] not in ["door", "window"]: return false
	if not value.get("owned") is Dictionary or value["owned"].size() > MAX_PARTS:
		return false
	var modules: Dictionary = {}
	for key in value["owned"]:
		var part: Variant = value["owned"][key]
		if not identifier(key) or not part is Dictionary or not identifier(part.get("uid")) or modules.has(part["uid"]):
			return false
		var signature: Variant = part.get("signature")
		if not signature is String or signature.length() != 64 or not signature.is_valid_hex_number(false):
			return false
		modules[part["uid"]] = true
	for key in ["skipped", "joints"]:
		var entries: Variant = value.get(key, [])
		if not entries is Array or entries.size() > MAX_PARTS or not entries.all(identifier): return false
	return true

static func retained(records: Variant, mode: String) -> Array:
	var result: Array = []
	if mode != "3d" or not records is Array: return result
	var ids: Dictionary = {}
	for room in records:
		if result.size() == MAX_ROOMS: break
		if not valid_record(room) or ids.has(room["uid"]): continue
		result.append(room)
		ids[room["uid"]] = true
	return result

static func valid(records: Variant, mode: String) -> bool:
	return records is Array and retained(records, mode) == records

static func copied(records: Array, objects: Dictionary, groups: Dictionary, joints: Dictionary) -> Array:
	var result: Array = []
	for record in records:
		if not groups.has(record["uid"]): continue
		var clone: Dictionary = record.duplicate(true)
		clone["uid"] = groups[record["uid"]]
		clone["skipped"] = record.get("skipped", []).duplicate()
		for key in record["owned"]:
			var old: String = record["owned"][key]["uid"]
			if objects.has(old): clone["owned"][key]["uid"] = objects[old]
			else:
				clone["owned"].erase(key)
				if key not in clone["skipped"]: clone["skipped"].append(key)
		clone["joints"] = []
		for old in record.get("joints", []):
			if joints.has(old): clone["joints"].append(joints[old])
		result.append(clone)
	return result

static func new_identity() -> String:
	return "room_" + Crypto.new().generate_random_bytes(16).hex_encode()

static func planned_identity(room: String, detail: Variant) -> String:
	return "module_" + JSON.stringify([room, detail]).sha256_text().substr(0, 32)

static func bounds_for(item: Dictionary, library: RefCounted) -> AABB:
	var bounds: AABB
	if item["asset"].begins_with("3d:"):
		var orientation: Basis = Basis.from_euler(ROTATION.euler(item) * PI / 180.0)
		bounds = Transform3D(orientation.scaled(Vector3.ONE * float(item["scale"])), Vector3.ZERO) * FIT.bounds_for(item["asset"], library, false)
	else:
		bounds = FIT.footprint_bounds(item, "3d", library)
	var at: Array = item["position"]
	bounds.position += Vector3(at[0], at[1], at[2])
	return bounds

static func intersects(a: AABB, b: AABB) -> bool:
	# Exactly flush module ends and floor surfaces do not intersect.
	var extent: Vector3 = a.end.min(b.end) - a.position.max(b.position)
	return extent.x > .015 and extent.y > .015 and extent.z > .015

static func access_box(item: Dictionary, kit: Dictionary) -> AABB:
	var span: float = float(kit["doorway_width"]) - .06
	var depth: float = 1.6
	var size := Vector3(span, float(kit["doorway_height"]) - .15, depth)
	if item["direction"] == "90": size = Vector3(depth, size.y, span)
	var at: Array = item["position"]
	return AABB(Vector3(at[0] - size.x / 2, .09, at[2] - size.z / 2), size)

static func joint_updates(scope: Dictionary, owned: Dictionary, created: Dictionary, room: String) -> Array:
	var occupied: Dictionary = CONNECTOR.occupancy(scope)
	var buckets: Dictionary = {}
	var fresh: Dictionary = {}
	for item in created.values(): fresh[item["uid"]] = true
	for item in owned.values():
		for endpoint in CONNECTOR.frames(item, "3d"):
			if occupied.has(CONNECTOR.socket_key(endpoint)): continue
			var key: Vector3i = Vector3i((endpoint["point"] * 1000).round())
			if not buckets.has(key): buckets[key] = []
			buckets[key].append(endpoint)
	var result: Array = []
	for group in buckets.values():
		if group.size() != 2 or not CONNECTOR.aligned_pair(group[0], group[1], "3d"): continue
		if not fresh.has(group[0]["object_uid"]) and not fresh.has(group[1]["object_uid"]): continue
		var source: Dictionary = {"object_uid": group[0]["object_uid"], "socket": group[0]["socket"]}
		var target: Dictionary = {"object_uid": group[1]["object_uid"], "socket": group[1]["socket"]}
		var endpoints: Array = [CONNECTOR.socket_key(source), CONNECTOR.socket_key(target)]
		endpoints.sort()
		result.append({"uid": planned_identity(room, endpoints), "kind": "structure", "from": source, "to": target})
	return result

static func propose(source: Dictionary, request: Dictionary, library: RefCounted, ceiling: float = INF, cutouts: Array = []) -> Dictionary:
	if source.get("mode") != "3d":
		return failure("This kit needs Model world geometry. Pixel sprites have no matching reverse faces or openings.")
	var kit: Dictionary = kits().get(request.get("kit"), {})
	var preview: Dictionary = layout(kit, request.get("outline"), request.get("openings"))
	if not preview["ok"]: return preview
	if ceiling < float(kit["wall_height"]) + .16:
		return failure("The next floor is too low for these walls and its floor slab.")
	if source.get("terrain", {}).get("enabled", false):
		return failure("Use a level floor for the modular outline. Sculpted ground needs manual modules.")
	var availability: Dictionary = {}
	for asset in kit["parts"].values():
		if library.assets.get(asset, {}).get("unavailable", false) or not SOURCES.available(asset, library, availability):
			return failure("A prepared kit part is unavailable. Restore the installed module before building.")
	var uid: String = request.get("uid", "")
	if not identifier(uid): return failure("Choose a valid room identity.")
	var rooms: Array = source.get("modular_rooms", []).duplicate(true)
	var room_index: int = rooms.find_custom(func(entry: Dictionary) -> bool: return entry["uid"] == uid)
	var previous: Dictionary = rooms[room_index] if room_index >= 0 else {}
	if previous.is_empty() and rooms.size() >= MAX_ROOMS: return failure("This floor has reached the modular room limit.")
	if not previous.is_empty() and previous["kit"] != request["kit"]:
		return failure("Detach this room before replacing its calibrated kit.")
	var objects: Dictionary = {}
	for item in source["objects"]: objects[item["uid"]] = item
	var old_owned: Dictionary = previous.get("owned", {})
	var parts: Dictionary = preview["parts"]
	var skipped: Array = previous.get("skipped", []).duplicate()
	var consumed: Dictionary = {}
	var removed: Dictionary = {}
	var owned: Dictionary = {}
	var created: Dictionary = {}
	for key in old_owned:
		var tracked: Dictionary = old_owned[key]
		var item: Dictionary = objects.get(tracked["uid"], {})
		if item.is_empty() or item.get("group") != uid or fingerprint(item) != tracked["signature"]:
			if key not in skipped: skipped.append(key)
			continue
		consumed[item["uid"]] = true
		if parts.has(key) and tracked["signature"] == fingerprint(parts[key]):
			owned[key] = item
		else:
			if not LAYERS.editable(source, item, library): return failure("Show and unlock the parts that the outline would replace.")
			removed[item["uid"]] = true
	if skipped.size() > MAX_PARTS: return failure("Detach this assembly before starting a new outline with more manual overrides.")
	for key in parts:
		if owned.has(key) or key in skipped: continue
		var item: Dictionary = parts[key].duplicate()
		item["uid"] = planned_identity(uid, [key, item["asset"]])
		if objects.has(item["uid"]) and not removed.has(item["uid"]):
			return failure("A detached or copied part already uses this room slot.")
		item["group"] = uid
		if not LAYERS.editable(source, item, library): return failure("Show and unlock the Ground and module layers before building.")
		owned[key] = item
		created[key] = item
	var existing: Array = []
	var cutout_boxes: Array = []
	for polygon in cutouts:
		if polygon.is_empty(): continue
		var area := Rect2(polygon[0], Vector2.ZERO)
		for at in polygon: area = area.expand(at)
		cutout_boxes.append(AABB(Vector3(area.position.x, -.03, area.position.y), Vector3(area.size.x, float(kit["wall_height"]), area.size.y)))
	for item in source["objects"]:
		if consumed.has(item["uid"]): continue
		if not library.assets.has(item["asset"]) or library.assets[item["asset"]].get("unavailable", false): continue
		if not item.get("visible", true) or not LAYERS.shown(source, LAYERS.layer(item, library)): continue
		existing.append({"item": item, "bounds": bounds_for(item, library)})
	var floor_centers: Array = []
	for key in parts:
		if key.begins_with("floor/"):
			var at: Array = parts[key]["position"]
			floor_centers.append(Vector2(at[0], at[2]))
	for entry in existing:
		var box: AABB = entry["bounds"]
		if box.position.y < .8 or box.position.y >= float(kit["doorway_height"]) - .2: continue
		if library.assets[entry["item"]["asset"]].get("behavior", {}).get("collision", "box") == "none": continue
		var projection := Rect2(Vector2(box.position.x, box.position.z), Vector2(box.size.x, box.size.z))
		var span: float = float(kit["floor_span"])
		for center in floor_centers:
			if projection.intersects(Rect2(center - Vector2.ONE * span / 2, Vector2.ONE * span)):
				return failure("A low overhead object obstructs walking space inside the outline.")
	for key in created:
		var item: Dictionary = created[key]
		var box: AABB = bounds_for(item, library)
		if not key.begins_with("floor/"):
			for hole in cutout_boxes:
				if intersects(box, hole): return failure("A wall would block an existing stair or elevator cutout.")
		for entry in existing:
			if intersects(box, entry["bounds"]):
				return failure("A new module intersects %s. Move the outline or clear that spot." % entry["item"].get("name", library.assets[entry["item"]["asset"]]["name"]))
	for key in request["openings"]:
		if request["openings"][key] != "door": continue
		var access: AABB = access_box(parts[key], kit)
		for entry in existing:
			if intersects(access, entry["bounds"]):
				return failure("A doorway approach is blocked by an existing object or low ceiling.")
		for hole in cutout_boxes:
			if intersects(access, hole): return failure("A doorway opens into an existing floor cutout.")
	var result: Dictionary = source.duplicate(true)
	result["objects"] = result["objects"].filter(func(item: Dictionary) -> bool: return not removed.has(item["uid"]))
	for item in result["objects"]:
		if removed.has(item.get("prop", {}).get("target", "")):
			return failure("A manual object still references a module that would be replaced.")
	result["objects"].append_array(created.values())
	var links: Array = []
	var joint_ids: Array = []
	for link in source.get("connections", []):
		var procedural: bool = link["uid"] in previous.get("joints", [])
		if removed.has(link["from"]["object_uid"]) or removed.has(link["to"]["object_uid"]):
			if not procedural: return failure("Disconnect the manual joint before replacing its module.")
			continue
		links.append(link)
		if procedural: joint_ids.append(link["uid"])
	result["connections"] = links
	for link in joint_updates(result, owned, created, uid):
		links.append(link)
		joint_ids.append(link["uid"])
	if CONNECTOR.retained(result, links) != links:
		return failure("A module joint cannot be preserved at the selected site.")
	var signatures: Dictionary = {}
	for key in owned:
		signatures[key] = {"uid": owned[key]["uid"], "signature": fingerprint(owned[key])}
	var next: Dictionary = {"uid": uid, "kit": request["kit"], "outline": request["outline"].duplicate(true),
		"openings": request["openings"].duplicate(), "owned": signatures, "skipped": skipped, "joints": joint_ids}
	if room_index < 0: rooms.append(next)
	else: rooms[room_index] = next
	result["modular_rooms"] = rooms
	var names: Dictionary = result.get("group_names", {})
	if not names.has(uid): names[uid] = "Modular room %d" % rooms.size()
	result["group_names"] = names
	if not load("res://scripts/builder/document.gd").valid(result, "3d", library):
		return failure("The modules exceed the current document or connection limits.")
	return {"ok": true, "data": result, "layout": preview, "room": next,
		"created": created.size(), "removed": removed.size(), "preserved_edits": skipped.size()}

static func detached(source: Dictionary, uid: String) -> Dictionary:
	var result: Dictionary = source.duplicate(true)
	var rooms: Array = result.get("modular_rooms", [])
	result["modular_rooms"] = rooms.filter(func(room: Dictionary) -> bool: return room["uid"] != uid)
	return result
