extends RefCounted

const SHADER = preload("res://scripts/isometric_tile_rotation.gdshader")
const DIRECTIONS: Array[String] = ["SE", "SW", "NW", "NE"]
static var materials: Dictionary = {}

static func supported(category: String) -> bool:
	return category in ["Floors", "City Ground"] or category.ends_with(" - Ground")

static func quarter_turns(direction: String) -> int:
	return posmod(roundi(degrees(direction) / 90), 4)

static func degrees(direction: String) -> float:
	return wrapf(float(direction), 0, 360) if direction.is_valid_float() else maxi(0, DIRECTIONS.find(direction)) * 90.0

static func direction_for(value: float) -> String:
	value = snappedf(wrapf(value, 0, 360), 0.01)
	if is_equal_approx(fposmod(value, 90), 0): return DIRECTIONS[posmod(roundi(value / 90), 4)]
	return str(roundi(value)) if is_equal_approx(value, roundf(value)) else str(value)

static func material_for(direction: String, atlas_coords: Vector2i = Vector2i.ZERO, frame_columns: int = 1, tile_size: Vector2 = Vector2(32, 16)) -> ShaderMaterial:
	var turns: int = quarter_turns(direction)
	var angle: float = degrees(direction)
	if is_zero_approx(angle):
		return null
	var key: String = "%s:%d:%d:%d:%s" % [str(angle), atlas_coords.x, atlas_coords.y, frame_columns, str(tile_size)]
	if not materials.has(key):
		var material := ShaderMaterial.new()
		material.shader = SHADER
		material.set_shader_parameter("quarter_turns", turns)
		material.set_shader_parameter("angle_radians", deg_to_rad(angle))
		material.set_shader_parameter("region_origin", Vector2(atlas_coords * Vector2i(32, 16)))
		material.set_shader_parameter("frame_columns", frame_columns)
		material.set_shader_parameter("tile_size", tile_size)
		materials[key] = material
	return materials[key]
