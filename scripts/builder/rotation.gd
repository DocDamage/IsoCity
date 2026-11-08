extends RefCounted

const COMPASS: Array[String] = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

# The supplied models face +Z (the model-front convention). Offset by 180
# degrees from camera forward so compass labels match the actual vehicle nose.
static func compass_yaw(facing: String, view_yaw: float = 45.0) -> float:
	var index: int = COMPASS.find(facing)
	return wrapf(view_yaw + 180 - index * 45.0, 0, 360) if index >= 0 else wrapf(view_yaw + 180, 0, 360)

static func compass_name(yaw: float, view_yaw: float = 45.0) -> String:
	var turns: float = wrapf(view_yaw + 180 - yaw, 0, 360) / 45.0
	return COMPASS[posmod(roundi(turns), 8)] if absf(turns - roundf(turns)) < 0.0001 else ""

static func heading(item: Dictionary, library: RefCounted) -> float:
	var id: String = item.get("asset", "")
	if id.begins_with("3d:"): return wrapf(float(item.get("direction", "0")), 0, 360)
	if library.is_ground_tile(id): return preload("res://scripts/iso_tile_rotation.gd").degrees(item.get("direction", "SE"))
	return float(item.get("angle", 0))

static func set_heading(item: Dictionary, value: float, library: RefCounted) -> void:
	value = snappedf(wrapf(value, 0, 360), 0.01)
	if item["asset"].begins_with("3d:"): item["direction"] = angle_text(value)
	elif library.is_ground_tile(item["asset"]): item["direction"] = preload("res://scripts/iso_tile_rotation.gd").direction_for(value)
	elif is_zero_approx(value): item.erase("angle")
	else: item["angle"] = value

static func angle_text(value: float) -> String:
	return str(roundi(value)) if is_equal_approx(value, roundf(value)) else str(snappedf(value, 0.01))

static func euler(item: Dictionary) -> Vector3:
	var tilt: Array = item.get("tilt", [0, 0])
	return Vector3(float(tilt[0]), float(item.get("direction", "0")) if item["asset"].begins_with("3d:") else float(item.get("angle", 0)), float(tilt[1]))

static func orbit_position(values: Array, pivot: Vector3, degrees_value: float, mode: String) -> Array:
	var delta := Vector3(values[0], values[1], values[2]) - pivot
	if mode == "2d":
		var ground := Vector2(delta.x, delta.y * 2).rotated(deg_to_rad(degrees_value))
		delta.x = ground.x
		delta.y = ground.y * 0.5
	else: delta = delta.rotated(Vector3.UP, deg_to_rad(degrees_value))
	delta += pivot
	return [delta.x, delta.y, delta.z]
