extends RefCounted

const Rotation = preload("res://scripts/builder/rotation.gd")
const Traffic = preload("res://scripts/builder/traffic_plan.gd")
const Terrain = preload("res://scripts/builder/terrain_plan.gd")
const SOURCE = "res://resources/catalog/connectors.json"
const KINDS = ["structure", "water", "power"]
const LIMIT = 4096
const BUCKET = 48.0
static var catalog: Dictionary = {}

static func definitions() -> Dictionary:
	if catalog.is_empty() and FileAccess.file_exists(SOURCE):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
		if parsed is Dictionary and parsed.get("version") == 1:
			catalog = parsed.get("assets", {})
	return catalog

static func failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func id_valid(value: Variant) -> bool:
	return value is String and not value.is_empty() and value.length() <= 128

static func endpoint_valid(value: Variant) -> bool:
	return value is Dictionary and id_valid(value.get("object_uid")) and id_valid(value.get("socket"))

static func record_valid(value: Variant) -> bool:
	return value is Dictionary and id_valid(value.get("uid")) and value.get("kind") in KINDS and endpoint_valid(value.get("from")) and endpoint_valid(value.get("to")) and value["from"]["object_uid"] != value["to"]["object_uid"]

static func socket_key(value: Dictionary) -> String:
	return JSON.stringify([value["object_uid"], value["socket"]])

static func vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2] if values.size() > 2 else 0)

static func sockets(item: Dictionary, mode: String) -> Array:
	var source: Dictionary = definitions().get(item.get("asset", ""), {})
	if mode == "2d":
		return source.get("views", {}).get(item.get("direction", ""), [])
	return source.get("sockets", [])

static func basis_for(normal: Vector3, up: Vector3) -> Basis:
	var outward: Vector3 = normal.normalized()
	var right: Vector3 = up.cross(outward).normalized()
	return Basis(right, outward.cross(right).normalized(), outward)

static func orthogonal_uniform(value: Basis) -> bool:
	if not value.is_finite() or value.determinant() <= .000001:
		return false
	var size: Vector3 = value.get_scale()
	if size.x <= .0001 or absf(size.x - size.y) > .0001 or absf(size.x - size.z) > .0001:
		return false
	return value.scaled(Vector3.ONE / size.x).is_equal_approx(value.orthonormalized())

# Local +Z faces out of the socket and local +Y points up.
static func socket_transform(target: Transform3D, source: Transform3D, size: float) -> Dictionary:
	if not target.is_finite() or not source.is_finite() or not is_finite(size) or size < .1 or size > 8:
		return failure("Invalid socket transform.")
	if not orthogonal_uniform(target.basis) or source.basis.determinant() < .999 or not source.basis.is_equal_approx(source.basis.orthonormalized()):
		return failure("Mirrored, singular, sheared and unevenly scaled socket frames cannot mate.")
	var rotation: Basis = target.basis.orthonormalized() * Basis(Vector3.UP, PI) * source.basis.inverse()
	var scaled: Basis = rotation.scaled(Vector3.ONE * size)
	return {"ok": true, "transform": Transform3D(scaled, target.origin - scaled * source.origin)}

static func terrain_height(data: Dictionary, item: Dictionary, mode: String, heights: Dictionary) -> float:
	if mode != "2d" or not Terrain.settings(data)["enabled"]:
		return 0.0
	return Terrain.sample(data, Traffic.metric(item["position"], mode), heights)["height"]

static func frames(item: Dictionary, mode: String, rise: float = 0.0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var size: float = item.get("scale", 1.0)
	if not is_finite(size) or size < .1 or size > 8 or item.has("missing_asset"):
		return result
	var local_sockets: Array = sockets(item, mode)
	if local_sockets.is_empty():
		return result
	var pose: Vector3 = vector(item["position"])
	var model: Basis = Basis.from_euler(Rotation.euler(item) * PI / 180.0) if mode == "3d" else Basis.IDENTITY
	var angle: float = deg_to_rad(item.get("angle", 0))
	for local in local_sockets:
		var offset: Vector3 = vector(local["position"])
		var normal: Vector3 = vector(local["normal"]).normalized()
		var up: Vector3 = vector(local["up"]).normalized()
		var position: Vector3
		if mode == "2d":
			var pixel: Vector2 = Vector2(offset.x, offset.y).rotated(angle) * size
			var out_2d: Vector2 = Vector2(normal.x, normal.y).rotated(angle)
			var up_2d: Vector2 = Vector2(up.x, up.y).rotated(angle)
			normal = Vector3(out_2d.x, out_2d.y, 0)
			up = Vector3(up_2d.x, up_2d.y, 0)
			position = Vector3(pose.x + pixel.x, pose.y + pixel.y - (pose.z + rise) * 8.0, pose.z)
		else:
			position = pose + model * offset * size
			normal = model * normal
			up = model * up
		result.append({
			"object_uid": item.get("uid", ""), "socket": local["id"],
			"kind": local["kind"], "profile": local["profile"], "mates": local["mates"],
			"size": Vector2(local["size"][0], local["size"][1]) * size,
			"point": position, "normal": normal, "up": up, "local": local
		})
	return result

static func compatible(source: Dictionary, target: Dictionary) -> String:
	if source["object_uid"] != "" and source["object_uid"] == target["object_uid"]:
		return "A socket cannot connect to the same object."
	if source["kind"] != target["kind"] or source["profile"] not in target["mates"] or target["profile"] not in source["mates"]:
		return "These socket profiles do not mate."
	if source["size"].distance_to(target["size"]) > .001:
		return "Socket sizes differ at the chosen scales."
	return ""

static func solve(item: Dictionary, source: Dictionary, target: Dictionary, mode: String, data: Dictionary, heights: Dictionary) -> Dictionary:
	var reason: String = compatible(source, target)
	if not reason.is_empty():
		return failure(reason)
	var pose: Dictionary = item.duplicate(true)
	var local: Dictionary = source["local"]
	var outward: Vector3 = vector(local["normal"]).normalized()
	var up: Vector3 = vector(local["up"]).normalized()
	var offset: Vector3 = vector(local["position"])
	var size: float = item["scale"]
	if mode == "2d":
		var source_direction := Vector2(outward.x, outward.y)
		var desired := -Vector2(target["normal"].x, target["normal"].y)
		var angle: float = source_direction.angle_to(desired)
		var new_up: Vector2 = Vector2(up.x, up.y).rotated(angle)
		if new_up.dot(Vector2(target["up"].x, target["up"].y)) < .999:
			return failure("The prepared views do not align upright.")
		var pixel: Vector2 = Vector2(offset.x, offset.y).rotated(angle) * size
		var at: Vector3 = target["point"]
		pose["angle"] = rad_to_deg(angle)
		pose["position"] = [at.x - pixel.x, at.y - pixel.y + at.z * 8, at.z]
		# Terrain presentation uses the unprojected object origin. Solve its
		# height offset again at the resulting origin and reject unstable sites.
		for iteration in 5:
			var rise: float = terrain_height(data, pose, mode, heights)
			pose["position"][1] = at.y - pixel.y + (at.z + rise) * 8
	else:
		var target_frame := Transform3D(basis_for(target["normal"], target["up"]), target["point"])
		var local_frame := Transform3D(basis_for(outward, up), offset)
		var aligned: Dictionary = socket_transform(target_frame, local_frame, size)
		if not aligned["ok"]:
			return aligned
		var transform: Transform3D = aligned["transform"]
		var angles: Vector3 = transform.basis.orthonormalized().get_euler() * 180.0 / PI
		pose["direction"] = str(angles.y)
		pose["tilt"] = [angles.x, angles.z]
		pose["position"] = [transform.origin.x, transform.origin.y, transform.origin.z]
	var result: Dictionary = frame_by_id(frames(pose, mode, terrain_height(data, pose, mode, heights)), source["socket"])
	if result.is_empty() or not aligned_pair(result, target, mode):
		return failure("The exact socket alignment cannot be represented at this site.")
	return {"ok": true, "pose": pose, "source": result, "target": target}

static func aligned_pair(source: Dictionary, target: Dictionary, mode: String) -> bool:
	return compatible(source, target).is_empty() and source["point"].distance_to(target["point"]) <= (.08 if mode == "2d" else .001) and source["normal"].dot(target["normal"]) < -.999 and source["up"].dot(target["up"]) > .999

static func frame_by_id(values: Array, id: String) -> Dictionary:
	for frame in values:
		if frame["socket"] == id:
			return frame
	return {}

static func occupancy(data: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for link in data.get("connections", []):
		if record_valid(link):
			for side in ["from", "to"]:
				result[socket_key(link[side])] = true
	return result

static func index(values: Array) -> Dictionary:
	var buckets: Dictionary = {}
	for value in values:
		var key := Vector2i((value["screen"] / BUCKET).floor())
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(value)
	return buckets

static func nearby(buckets: Dictionary, point: Vector2, radius: float) -> Array:
	var first := Vector2i(((point - Vector2.ONE * radius) / BUCKET).floor())
	var last := Vector2i(((point + Vector2.ONE * radius) / BUCKET).floor())
	var found: Array = []
	for x in range(first.x, last.x + 1):
		for y in range(first.y, last.y + 1):
			for value in buckets.get(Vector2i(x, y), []):
				if value["screen"].distance_to(point) <= radius:
					found.append(value)
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left: float = a["screen"].distance_squared_to(point)
		var right: float = b["screen"].distance_squared_to(point)
		return socket_key(a) < socket_key(b) if is_equal_approx(left, right) else left < right
	)
	return found

static func retained(data: Dictionary, links: Variant) -> Array:
	var result: Array = []
	if not links is Array:
		return result
	var objects: Dictionary = {}
	var used: Dictionary = {}
	var ids: Dictionary = {}
	var values: Dictionary = {}
	var mode: String = data["mode"]
	var heights: Dictionary = Terrain.lookup(data) if mode == "2d" and Terrain.settings(data)["enabled"] else {}
	for item in data["objects"]:
		if item is Dictionary and item.get("uid") is String:
			objects[item["uid"]] = item
	for link in links:
		if result.size() >= LIMIT:
			break
		if not record_valid(link) or ids.has(link["uid"]):
			continue
		var endpoints: Array[Dictionary] = []
		for side in ["from", "to"]:
			var reference: Dictionary = link[side]
			var uid: String = reference["object_uid"]
			if used.has(socket_key(reference)) or not objects.has(uid):
				break
			if not values.has(uid):
				var item: Dictionary = objects[uid]
				values[uid] = frames(item, mode, terrain_height(data, item, mode, heights))
			var found: Dictionary = frame_by_id(values[uid], reference["socket"])
			if found.is_empty():
				break
			endpoints.append(found)
		if endpoints.size() != 2 or endpoints[0]["kind"] != link["kind"] or not aligned_pair(endpoints[0], endpoints[1], mode):
			continue
		ids[link["uid"]] = true
		for side in ["from", "to"]:
			used[socket_key(link[side])] = true
		result.append(link)
	return result

static func copied_links(links: Array, identities: Dictionary, id_source: Callable, id_map: Variant = null) -> Array:
	var result: Array = []
	for link in links:
		if not record_valid(link): continue
		var a: String = link["from"]["object_uid"]
		var b: String = link["to"]["object_uid"]
		if not identities.has(a) or not identities.has(b):
			continue
		var copy: Dictionary = link.duplicate(true)
		copy["uid"] = id_source.call()
		if id_map != null: id_map[link["uid"]] = copy["uid"]
		copy["from"]["object_uid"] = identities[a]
		copy["to"]["object_uid"] = identities[b]
		result.append(copy)
	return result
