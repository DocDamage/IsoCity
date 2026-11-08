@tool
extends Node2D

const IsoMath = preload("res://scripts/iso_math.gd")

func _draw() -> void:
	var fp: Vector2i = get_meta("footprint", Vector2i(1, 1))
	var poly: PackedVector2Array = IsoMath.get_footprint_diamond(Vector2i.ZERO, fp, 0)
	# Draw translucent diamond footprint
	draw_colored_polygon(poly, Color(0.1, 0.7, 1.0, 0.25))
	# Draw crisp borders
	draw_polyline(poly, Color(0.2, 0.9, 1.0, 0.9), 1.5)
	draw_line(poly[3], poly[0], Color(0.2, 0.9, 1.0, 0.9), 1.5)
