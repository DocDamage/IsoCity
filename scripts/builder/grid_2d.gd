extends Node2D

func _draw() -> void:
	var tint := Color(0.5, 0.7, 0.85, 0.10)
	for index in range(-48, 49):
		draw_line(IsoMath.tile_to_world(Vector2i(index, -48)), IsoMath.tile_to_world(Vector2i(index, 48)), tint)
		draw_line(IsoMath.tile_to_world(Vector2i(-48, index)), IsoMath.tile_to_world(Vector2i(48, index)), tint)
