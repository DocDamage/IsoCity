extends Node2D
var ropes: Array[Vector2]=[]
var seat:=PackedVector2Array()
var color:=Color("e9584d")
func _draw() -> void:
	if ropes.size()==4:
		draw_line(ropes[0],ropes[1],Color("b5bbc4"),1.2,true); draw_line(ropes[2],ropes[3],Color("b5bbc4"),1.2,true)
	if seat.size()==4: draw_colored_polygon(seat,color)
