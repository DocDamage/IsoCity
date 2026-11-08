extends Node2D
const Plan=preload("res://scripts/builder/zone_plan.gd")
const Stages=preload("res://scripts/builder/zone_stage_plan.gd")
var lot: Dictionary={}
var stage_layout: Dictionary={}
var text_scale: float=1.0
var terrain_data: Dictionary={}
var heights: Dictionary={}
func points(rect: Rect2,height: float=0) -> PackedVector2Array:
	var result: PackedVector2Array=[]
	for at in [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]:
		var ground: float=preload("res://scripts/builder/terrain_plan.gd").sample(terrain_data,at,heights)["height"] if preload("res://scripts/builder/terrain_plan.gd").settings(terrain_data)["enabled"] else 0.0
		var raw: Array=Plan.Traffic.world(at,"2d"); result.append(Vector2(raw[0],raw[1]-height*12-ground*8))
	return result
func outline(poly: PackedVector2Array,color: Color,width: float=2) -> void:
	var closed: PackedVector2Array=poly.duplicate(); closed.append(closed[0]); draw_polyline(closed,color,width,true)
func _draw() -> void:
	if lot.is_empty(): return
	var color:=Color(Plan.definitions()[lot["kind"]]["color"])
	var base: PackedVector2Array=points(Plan.rectangle(lot))
	draw_colored_polygon(base,Color(color,.10)); outline(base,color,2)
	var stage: int=int(lot.get("stage",0))
	var box: Rect2=stage_layout.get("pad",Rect2())
	if box.has_area():
		var floor_poly: PackedVector2Array=points(box,.1)
		draw_colored_polygon(floor_poly,Stages.pad_color(stage)); outline(floor_poly,Color("d3d8dc"),2)
		if stage_layout["fallback"] and stage==Plan.Stage.FRAMING:
			var roof: PackedVector2Array=points(box,4)
			outline(roof,Color("e6b977"),3)
			for index in 4:
				draw_line(floor_poly[index],roof[index],Color("e6b977"),3,true)
				draw_line(floor_poly[index],roof[(index+1)%4],Color("d49c55"),1.5,true)
		elif stage_layout["fallback"] and stage==Plan.Stage.FINISHING:
			var size: Vector2=box.size*.32
			for side in [-1,1]:
				var center: Vector2=box.get_center()+Vector2(size.x*.68*side,0)
				var pallet: PackedVector2Array=points(Rect2(center-size*.5,size),.35)
				draw_colored_polygon(pallet,Color("c98751")); outline(pallet,Color("e5c496"),1.5)
	var text: String=Plan.definitions()[lot["kind"]]["label"]+" · "+Plan.stage_name(lot)
	if lot.get("locked",false): text+=" · locked"
	draw_string(ThemeDB.fallback_font,base[0]+Vector2(4,-6),text,HORIZONTAL_ALIGNMENT_LEFT,-1,roundi(12*text_scale),Color("ffffff"))
