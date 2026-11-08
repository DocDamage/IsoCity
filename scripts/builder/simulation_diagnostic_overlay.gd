extends Control

const COLORS: Dictionary={"error":Color("ff917f"),"warning":Color("ffc878"),"pending":Color("ffe078"),
	"info":Color("83d9ff"),"ok":Color("95f5ca")}
var studio: Control
var rows: Array[Dictionary]=[]
var selected: Array=[]
var contrast: bool=false
var text_scale: float=1.0

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hide()

func clear() -> void:
	rows=[]
	selected=[]
	hide()
	queue_redraw()

func projected(at: Vector3) -> Vector2:
	if studio.mode=="3d" and studio.worlds["3d"].camera.is_position_behind(at): return Vector2.INF
	return studio.overlay_position([at.x,at.y,at.z],0.0)

static func clip_segment(start: Vector2,finish: Vector2,screen: Rect2) -> PackedVector2Array:
	if not start.is_finite() or not finish.is_finite(): return []
	var inside_start: bool=screen.has_point(start)
	var inside_finish: bool=screen.has_point(finish)
	if inside_start and inside_finish: return PackedVector2Array([start,finish])
	var bounds: Rect2=Rect2(start,Vector2.ZERO).expand(finish).grow(.01)
	if not screen.intersects(bounds): return []
	var hits: Array[Vector2]=[]
	if inside_start: hits.append(start)
	if inside_finish: hits.append(finish)
	var corners: Array[Vector2]=[screen.position,Vector2(screen.end.x,screen.position.y),screen.end,Vector2(screen.position.x,screen.end.y)]
	for index in 4:
		var hit: Variant=Geometry2D.segment_intersects_segment(start,finish,corners[index],corners[(index+1)%4])
		if hit!=null and not hits.has(hit): hits.append(hit)
	if hits.size()<2: return []
	if hits[0].distance_squared_to(start)>hits[1].distance_squared_to(start): hits.reverse()
	return PackedVector2Array([hits[0],hits[1]])

func _draw() -> void:
	if not is_instance_valid(studio) or studio.worlds[studio.mode].exploration.photo.active: return
	var tools: RefCounted=studio.simulation_diagnostic_tools
	if not tools or tools.scope_key()!=tools.active_scope: return
	var screen:=Rect2(Vector2.ZERO,size)
	for row in rows:
		var active: bool=preload("res://scripts/builder/simulation_diagnostics.gd").identity(row)==selected
		var tint: Color=Color.WHITE if contrast else COLORS.get(row["severity"],Color.WHITE)
		for shape in row["details"]["geometry"]:
			var points: PackedVector3Array=shape["points"]
			if points.size()==1:
				var center: Vector2=projected(points[0])
				if center.is_finite() and screen.grow(-12).has_point(center):
					draw_pin(center,shape["kind"],shape.get("label",""),row["severity"],tint,active)
				continue
			var start: Vector2=projected(points[0])
			for index in range(1,points.size()):
				var finish: Vector2=projected(points[index])
				var segment: PackedVector2Array=clip_segment(start,finish,screen)
				if segment.size()==2:
					var path_color: Color=Color("66e0ff") if shape["kind"]=="water_run" and not contrast else tint
					if shape["kind"]=="power_run" and not contrast: path_color=Color("ffd078")
					draw_path(segment[0],segment[1],shape["kind"],path_color,active)
				start=finish

func draw_path(from: Vector2,to: Vector2,kind: String,tint: Color,active: bool) -> void:
	var width: float=4.0 if active else 2.8
	var dash: float=5.0 if kind.begins_with("walk") else 11.0 if kind in ["coverage","water_interrupted","power_interrupted"] else 0.0
	if dash>0.0:
		draw_dashed_line(from,to,Color.BLACK,width+2.5,dash,false,true)
		draw_dashed_line(from,to,tint,width,dash,false,true)
	else:
		draw_line(from,to,Color.BLACK,width+2.5,true)
		draw_line(from,to,tint,width,true)
		if kind=="power_run" and from.distance_squared_to(to)>400.0:
			var center: Vector2=from.lerp(to,.5)
			draw_rect(Rect2(center-Vector2.ONE*4,Vector2.ONE*8),Color.BLACK)
			draw_rect(Rect2(center-Vector2.ONE*3,Vector2.ONE*6),tint,false,1.5)
		elif kind!="water_run" and from.distance_squared_to(to)>400.0:
			var center: Vector2=from.lerp(to,.58)
			var direction: Vector2=from.direction_to(to)
			var side:=Vector2(-direction.y,direction.x)
			var arrow:=PackedVector2Array([center+direction*4.0,center-direction*4.0+side*4.0,center-direction*4.0-side*4.0])
			draw_colored_polygon(arrow,tint)

func draw_pin(center: Vector2,kind: String,label: String,severity: String,tint: Color,active: bool) -> void:
	var radius: float=10.0 if active else 8.0
	if kind in ["queue","station"]:
		if not label.is_empty(): radius=maxf(radius,8.0+label.length()*text_scale)
		var rect:=Rect2(center-Vector2.ONE*radius,Vector2.ONE*radius*2.0)
		draw_rect(rect.grow(2.0),Color.BLACK)
		draw_rect(rect,tint,false,2)
	elif severity=="error" or severity=="warning":
		var outline:=PackedVector2Array([center+Vector2(0,-radius),center+Vector2(radius,radius*.8),center+Vector2(-radius,radius*.8)])
		draw_colored_polygon(outline,Color.BLACK)
		outline.append(outline[0])
		draw_polyline(outline,tint,2.2,true)
	elif severity=="pending":
		var outline:=PackedVector2Array([center+Vector2(0,-radius),center+Vector2(radius,0),center+Vector2(0,radius),center+Vector2(-radius,0)])
		draw_colored_polygon(outline,Color.BLACK)
		outline.append(outline[0])
		draw_polyline(outline,tint,2.2,true)
	else:
		draw_circle(center,radius+2,Color.BLACK)
		draw_arc(center,radius,0,TAU,20,tint,2,true)
	if not label.is_empty():
		var font: Font=ThemeDB.fallback_font
		var font_size: int=roundi(12*text_scale)
		var width: float=font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
		draw_string(font,center+Vector2(-width*.5,font_size*.36),label,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,tint)
