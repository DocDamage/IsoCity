extends Control

var direction: String = "SE"
var dimension: String = "2d"
var angle_offset: float = 0
var model_compass: bool = false
var view_yaw: float = 45
var vertical_scale: float = 0.5

func _ready() -> void:
	custom_minimum_size = Vector2(150, 75)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var center := size / 2
	var points := PackedVector2Array([center + Vector2(0, -27), center + Vector2(50, 0), center + Vector2(0, 27), center + Vector2(-50, 0), center + Vector2(0, -27)])
	draw_polyline(points, Color("496a80"), 1)
	var directions: Dictionary = {"N": Vector2(0, -27), "NE": Vector2(42, -21), "E": Vector2(50, 0), "SE": Vector2(42, 21), "S": Vector2(0, 27), "SW": Vector2(-42, 21), "W": Vector2(-50, 0), "NW": Vector2(-42, -21), "Left": Vector2(-42, 21), "Right": Vector2(42, 21)}
	var vector: Vector2 = directions.get(direction, Vector2.UP.rotated(deg_to_rad(float(direction))) * 27 if dimension == "3d" else Vector2.ZERO)
	vector = vector.rotated(deg_to_rad(angle_offset))
	var caption: String = "Facing " + direction
	if model_compass:
		var delta: float = deg_to_rad(view_yaw + 180 - float(direction))
		vector = Vector2(sin(delta) * 50, -cos(delta) * 50 * vertical_scale)
		var name: String = preload("res://scripts/builder/rotation.gd").compass_name(float(direction), view_yaw)
		caption = "Facing " + (name + " · " if not name.is_empty() else "") + direction + "°"
	draw_line(center, center + vector, Color("6ce0c7"), 3)
	draw_circle(center + vector, 4, Color("6ce0c7"))
	draw_string(ThemeDB.fallback_font, Vector2(8, size.y - 3), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("bfd3df"))
