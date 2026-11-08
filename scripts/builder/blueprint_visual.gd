extends Node2D
var fill_tint:=Color(.15,.65,1,.22)
var outline_tint:=Color(.35,.8,1,.85)
var polygons: Array[PackedVector2Array]=[]
func _draw() -> void:
	for polygon in polygons:
		draw_colored_polygon(polygon,fill_tint)
		var outline: PackedVector2Array=polygon.duplicate(); outline.append(polygon[0]); draw_polyline(outline,outline_tint,2,true)
