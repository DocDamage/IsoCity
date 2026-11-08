extends RefCounted

const GridFit = preload("res://scripts/builder/grid_fit.gd")
const Behavior = preload("res://scripts/builder/asset_behavior.gd")

static func profile(item: Dictionary, library: RefCounted) -> Dictionary:
	var authored: Dictionary = Behavior.for_asset(item["asset"], library).get("entrance_anchor", {})
	var override: Dictionary = item.get("entrance_anchor", {})
	if library.assets[item["asset"]]["mode"] == "2d":
		var views: Dictionary = authored.get("views", {})
		var direction: String = item["direction"]
		return override.get("views", {}).get(direction, views.get(direction, views.get("SE", {})))
	return override if not override.is_empty() else authored

static func valid(value: Variant, sprite: bool) -> bool:
	if not value is Dictionary: return false
	if sprite:
		if not value.get("views") is Dictionary: return false
		for view in value["views"].values():
			if not valid_point(view, 2): return false
		return not value["views"].is_empty()
	return valid_point(value, 3)

static func valid_point(value: Variant, count: int) -> bool:
	if not value is Dictionary: return false
	for key in ["point", "arrival"]:
		if not value.get(key) is Array or value[key].size() != count: return false
		for number in value[key]:
			if not (number is int or number is float) or not is_finite(float(number)) or absf(float(number)) > 10000: return false
	return true

# Authored source points are transformed as points, not by a rotated bounding box.
# The approach is separate from the doorway so the character can stand outside.
static func position_for(node: Node, item: Dictionary, dimension: String, library: RefCounted, arrival: bool = true) -> Variant:
	var anchor: Dictionary = profile(item, library)
	var raw: Array = anchor.get("arrival" if arrival else "point", [])
	if raw.is_empty(): return node.position
	var sprite: bool = library.assets[item["asset"]]["mode"] == "2d"
	return source_position(node,item,dimension,library,Vector3(raw[0],0,raw[1]) if sprite else Vector3(raw[0],raw[1],raw[2]))

# All three coordinates use source metres: X, height and depth. Sprite source
# X/depth retain their authored footprint origin, including in mixed worlds.
static func source_position(node: Node,item: Dictionary,dimension: String,library: RefCounted,source: Vector3) -> Variant:
	var sprite: bool=library.assets[item["asset"]]["mode"]=="2d"
	if sprite:
		var point := Vector2(source.x, source.z)
		if dimension == "2d": return node.transform * (GridFit.pixels(point)+Vector2(0,-source.y*8))
		var views: Dictionary = library.assets[item["asset"]]["data"]["directions"]
		var view: Dictionary = views.get(item["direction"], views.get("SE", views.values()[0]))
		var foot: Array = view.get("footprint", [1, 1])
		return node.transform * Vector3(point.x - foot[0] * 0.5, source.y+0.02, point.y - foot[1] * 0.5)
	var point := source
	if dimension == "3d": return node.transform * point
	# ModelIn2D rotates its source model inside an independent viewport. Project
	# that source transform, then apply the wrapper's 2D rotation/scale/position.
	point = node.model.transform * point
	var view_basis := Basis.from_euler(Vector3(deg_to_rad(-30), deg_to_rad(45), 0))
	var pixel: Vector3 = view_basis.inverse() * point
	return node.transform * (Vector2(pixel.x, -pixel.y) * node.PIXELS_PER_UNIT)
