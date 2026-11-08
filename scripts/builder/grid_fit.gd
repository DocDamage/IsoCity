extends RefCounted

const Bounds = preload("res://scripts/model_bounds.gd")
const Rotation = preload("res://scripts/builder/rotation.gd")
static var models: Dictionary = {}
static var sprite_boxes: Dictionary = {}

static func grid(point: Vector2) -> Vector2:
	return Vector2((point.x / 16 + point.y / 8) * 0.5, (point.y / 8 - point.x / 16) * 0.5)

static func pixels(point: Vector2) -> Vector2:
	return Vector2((point.x - point.y) * 16, (point.x + point.y) * 8)

# The same projection for saved coordinates, without a single-precision Vector2
# round trip introducing noise into otherwise simple authored decimal values.
static func pixel_values(point: Array) -> Array:
	var x: float=point[0];var z: float=point[1]
	return [(x-z)*16.0,(x+z)*8.0]

static func bounds_for(id: String, library: RefCounted, contact: bool = true) -> AABB:
	if models.is_empty() and FileAccess.file_exists("res://resources/catalog/model_grid_bounds.json"):
		models = JSON.parse_string(FileAccess.get_file_as_string("res://resources/catalog/model_grid_bounds.json")).get("assets", {})
	if not models.has(id):
		var sample: Node3D = load(library.assets[id]["path"]).instantiate()
		var box: AABB = Bounds.get_bounds(sample)
		var base: AABB = Bounds.contact_bounds(sample)
		sample.free()
		models[id] = {"min": [box.position.x, box.position.y, box.position.z], "size": [box.size.x, box.size.y, box.size.z], "base_min": [base.position.x, base.position.y, base.position.z], "base_size": [base.size.x, base.size.y, base.size.z]}
	var entry: Dictionary = models[id]
	var low: Array = entry.get("base_min", entry["min"]) if contact else entry["min"]
	var size: Array = entry.get("base_size", entry["size"]) if contact else entry["size"]
	return AABB(Vector3(low[0], low[1], low[2]), Vector3(size[0], size[1], size[2]))

static func sprite_box(item: Dictionary, library: RefCounted) -> AABB:
	var id: String = item["asset"]
	var cache_key: String = id + ":" + item["direction"]
	if sprite_boxes.has(cache_key): return sprite_boxes[cache_key]
	var views: Dictionary = library.assets[id]["data"]["directions"]
	var view: Dictionary = views.get(item["direction"], views.get("SE", views.values()[0]))
	var foot: Array = view.get("footprint", [1, 1])
	var height: float = 0.03
	if not library.is_ground_tile(id):
		var source: Node2D = load(library.assets[id]["path"]).instantiate()
		source.direction = item["direction"]
		var sprite: Sprite2D = source.get_node_or_null("Sprite2D")
		if sprite:
			var rect: Rect2 = sprite.transform * sprite.get_rect()
			if not sprite.transform.is_equal_approx(Transform2D.IDENTITY): rect.position = rect.position.floor()
			var contact := Vector2.ZERO
			var raw: Array = view.get("grid_contact", [])
			if raw.size() == 2 and source is IsoObject: contact = sprite.transform * (Vector2(raw[0], raw[1]) - source.origin_offset)
			height = maxf(0.1, (contact.y - rect.position.y) / 32.0)
		source.free()
	var box := AABB(Vector3(-foot[0] * 0.5, 0, -foot[1] * 0.5), Vector3(foot[0], height, foot[1]))
	sprite_boxes[cache_key] = box
	return box

static func sprite_basis(item: Dictionary, library: RefCounted) -> Basis:
	var angles: Vector3 = Rotation.euler(item)
	# Freely rotated cards use the same +45-degree correction as SpriteIn3D.
	if not library.is_ground_tile(item["asset"]) and not angles.is_zero_approx(): angles.y += 45
	return Basis.from_euler(angles * PI / 180.0)

static func footprint_bounds(item: Dictionary, mode: String, library: RefCounted) -> AABB:
	var size: float = item.get("scale", 1)
	if item["asset"].begins_with("3d:"):
		var angles: Vector3 = Rotation.euler(item)
		var contact: bool = is_zero_approx(angles.x) and is_zero_approx(angles.z)
		var rotated: AABB = Transform3D(Basis.from_euler(angles * PI / 180.0).scaled(Vector3.ONE * size), Vector3.ZERO) * bounds_for(item["asset"], library, contact)
		return rotated
	var views: Dictionary = library.assets[item["asset"]]["data"]["directions"]
	var view: Dictionary = views.get(item["direction"], views.get("SE", views.values()[0]))
	var foot: Array = view.get("footprint", [1, 1])
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	if mode == "2d":
		# Native characters are authored with their feet at the grid point.
		if library.assets[item["asset"]]["category"] in ["Characters", "Pets"]: return AABB()
		for point in [Vector2.ZERO, Vector2(foot[0], 0), Vector2(foot[0], foot[1]), Vector2(0, foot[1])]:
			var transformed: Vector2 = pixels(point * size).rotated(deg_to_rad(item.get("angle", 0)))
			low = low.min(grid(transformed))
			high = high.max(grid(transformed))
		return AABB(Vector3(low.x, 0, low.y), Vector3(high.x - low.x, 0, high.y - low.y))
	var box: AABB = sprite_box(item, library)
	var rotated: AABB = Transform3D(sprite_basis(item, library).scaled(Vector3.ONE * size), Vector3.ZERO) * box
	return rotated

const TARGETS: Array[String] = ["base", "center", "origin", "corner_0", "corner_x", "corner_z", "corner_xz", "edge_min_x", "edge_max_x", "edge_min_z", "edge_max_z", "top"]
const TARGET_LABELS: Array[String] = ["Base minimum corner", "Base center", "Object origin", "Source corner 0 / 0", "Source corner X / 0", "Source corner 0 / depth", "Source corner X / depth", "Source edge -X", "Source edge +X", "Source edge -depth", "Source edge +depth", "Top surface center"]

static func minimum(item: Dictionary, mode: String, library: RefCounted) -> Vector3:
	return footprint_bounds(item, mode, library).position

static func anchor(item: Dictionary, mode: String, library: RefCounted, target: String = "base") -> Vector3:
	if target == "origin": return Vector3.ZERO
	if target == "base": return minimum(item, mode, library)
	var uv := Vector2(0.5, 0.5)
	match target:
		"corner_0": uv = Vector2.ZERO
		"corner_x": uv = Vector2(1, 0)
		"corner_z": uv = Vector2(0, 1)
		"corner_xz": uv = Vector2(1, 1)
		"edge_min_x": uv.x = 0
		"edge_max_x": uv.x = 1
		"edge_min_z": uv.y = 0
		"edge_max_z": uv.y = 1
	var size: float = item.get("scale", 1)
	var angles: Vector3 = Rotation.euler(item)
	if item["asset"].begins_with("3d:"):
		var box: AABB = bounds_for(item["asset"], library, target != "top" and is_zero_approx(angles.x) and is_zero_approx(angles.z))
		var point := Vector3(lerpf(box.position.x, box.end.x, uv.x), box.end.y if target == "top" else box.position.y, lerpf(box.position.z, box.end.z, uv.y))
		return Basis.from_euler(angles * PI / 180.0) * point * size
	var views: Dictionary = library.assets[item["asset"]]["data"]["directions"]
	var view: Dictionary = views.get(item["direction"], views.get("SE", views.values()[0]))
	var foot: Array = view.get("footprint", [1, 1])
	if mode == "2d":
		var pixel: Vector2 = pixels(Vector2(uv.x * foot[0], uv.y * foot[1]) * size).rotated(deg_to_rad(item.get("angle", 0)))
		var cell: Vector2 = grid(pixel)
		return Vector3(cell.x, 0, cell.y)
	var box: AABB = sprite_box(item, library)
	var point := Vector3((uv.x - 0.5) * foot[0], box.end.y if target == "top" else 0, (uv.y - 0.5) * foot[1])
	return sprite_basis(item, library) * point * size

static func anchor_position(item: Dictionary, mode: String, library: RefCounted, target: String = "base") -> Array:
	var offset: Vector3 = anchor(item, mode, library, target)
	var values: Array = item["position"]
	if mode == "3d": return [values[0] + offset.x, values[1] + offset.y, values[2] + offset.z]
	var pixel: Vector2 = pixels(Vector2(offset.x, offset.z))
	return [values[0] + pixel.x, values[1] + pixel.y, values[2]]

static func place(values: Array, item: Dictionary, mode: String, library: RefCounted, target: String = "base") -> Array:
	var low: Vector3 = anchor(item, mode, library, target)
	if mode == "3d": return [float(values[0]) - low.x, float(values[1]) - low.y, float(values[2]) - low.z]
	var offset: Vector2 = pixels(Vector2(low.x, low.z))
	return [float(values[0]) - offset.x, float(values[1]) - offset.y, float(values[2])]

static func snap(item: Dictionary, mode: String, library: RefCounted, target: String = "base") -> Array:
	var low: Vector3 = anchor(item, mode, library, target)
	var position: Array = item["position"]
	if mode == "3d":
		return [roundf(position[0] + low.x) - low.x, position[1], roundf(position[2] + low.z) - low.z]
	var location: Vector2 = grid(Vector2(position[0], position[1])) + Vector2(low.x, low.z)
	var origin: Vector2 = pixels(location.round() - Vector2(low.x, low.z))
	return [origin.x, origin.y, position[2]]
