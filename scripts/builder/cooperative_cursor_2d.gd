extends Node2D
var caption: String="Builder"
var tint:=Color("6ed8ff")
var text_scale: float=1
func _draw() -> void:
	draw_colored_polygon(PackedVector2Array([Vector2.ZERO,Vector2(5,18),Vector2(10,11),Vector2(18,10)]),tint)
	draw_polyline(PackedVector2Array([Vector2.ZERO,Vector2(5,18),Vector2(10,11),Vector2(18,10),Vector2.ZERO]),Color.WHITE,1.5,true)
	draw_string(ThemeDB.fallback_font,Vector2(20,14),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,roundi(15*text_scale),tint)
