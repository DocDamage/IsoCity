extends Control

const DiagnosticsOverlay=preload("res://scripts/builder/simulation_diagnostic_overlay.gd")

var boxes: Array[Rect2] = []
var marquee: Rect2
var marquee_visible: bool = false
var footprint: PackedVector2Array = []
var warning: bool = false
var caption: String = ""
var brush_polygon := PackedVector2Array()
var terrain_ring := PackedVector2Array()
var terrain_markers := PackedVector2Array()
var modular_paths: Array = []
var part_polygons: Array[PackedVector2Array] = []
var caption_position := Vector2(10, 10)
var caption_area := Rect2()
var snap_point := Vector2.ZERO
var snap_visible: bool = false
var pivot_point := Vector2.ZERO
var pivot_visible: bool = false
var accessible_markers: bool = true
var high_contrast: bool = false
var text_scale: float = 1.0
var tile_outline := PackedVector2Array()
var socket_markers: Array = []
var socket_area: Rect2
var socket_line: PackedVector2Array = []

func caption_font_size() -> int: return roundi(13*text_scale)
func caption_line_height() -> int: return roundi(19*text_scale)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _draw() -> void:
	for path in modular_paths:
		var line: PackedVector2Array = path["points"]
		var opening: bool = path["opening"]
		draw_polyline(line, Color.BLACK, 7 if opening else 5, true)
		draw_polyline(line, Color.WHITE if high_contrast else (Color("ffcf8d") if opening else Color("90dfc2")), 3 if opening else 2, true)
	if terrain_ring.size()>2:
		draw_polyline(terrain_ring,Color.BLACK,5,true); draw_polyline(terrain_ring,Color.WHITE if high_contrast else Color("8acfff"),2,true)
	for at in terrain_markers:
		var color: Color=Color.WHITE if high_contrast else Color("ffcb79")
		var diamond:=PackedVector2Array([at+Vector2(0,-10),at+Vector2(10,0),at+Vector2(0,10),at+Vector2(-10,0)])
		draw_colored_polygon(diamond,Color.BLACK)
		diamond.append(diamond[0])
		draw_polyline(diamond,color,2,true)
		draw_string(ThemeDB.fallback_font,at+Vector2(-2.5,4.5),"!",HORIZONTAL_ALIGNMENT_LEFT,-1,12,color)
	if brush_polygon.size() > 2:
		draw_colored_polygon(brush_polygon, Color(0.3, 0.75, 1, 0.15))
		draw_polyline(brush_polygon, Color("8acfff"), 2)
	for polygon in part_polygons:
		if polygon.size() > 2:
			draw_colored_polygon(polygon, Color(0.1, 1.0, 0.85, 0.22))
			var outline := polygon.duplicate()
			outline.append(outline[0])
			draw_polyline(outline, Color("6fffe0"), 1.5)
	for box in boxes: draw_rect(box.grow(3), Color("67dfcc"), false, 1.5)
	if accessible_markers:
		for i in boxes.size(): draw_selection_marker(boxes[i],i+1)
		if tile_outline.size()>2:
			var closed: PackedVector2Array=tile_outline.duplicate(); closed.append(closed[0])
			draw_polyline(closed,Color.BLACK,6); draw_polyline(closed,Color.WHITE,2)
			for at in tile_outline: draw_rect(Rect2(at-Vector2(3,3),Vector2(6,6)),Color.WHITE)
		for polygon in part_polygons:
			if polygon.size()<3: continue
			var closed: PackedVector2Array=polygon.duplicate(); closed.append(closed[0])
			draw_polyline(closed,Color.BLACK,5); draw_polyline(closed,Color.WHITE,2)
			for at in polygon: draw_circle(at,3,Color.WHITE)
	if marquee_visible:
		draw_rect(marquee, Color(0.3, 0.9, 0.8, 0.12))
		draw_rect(marquee, Color("67dfcc"), false, 1.5)
	if footprint.size() > 2:
		var color := Color("eeac6d") if warning else Color("72e8ba")
		draw_colored_polygon(footprint, Color(color, 0.14))
		var outline := footprint.duplicate()
		outline.append(outline[0])
		draw_polyline(outline, color, 2)
		if accessible_markers and warning:
			var at: Vector2=Vector2.ZERO
			for point in footprint: at+=point
			at/=footprint.size()
			var triangle:=PackedVector2Array([at+Vector2(0,-15),at+Vector2(15,12),at+Vector2(-15,12)])
			draw_colored_polygon(triangle,Color.BLACK)
			triangle.append(triangle[0]); draw_polyline(triangle,Color.WHITE,2)
			draw_string(ThemeDB.fallback_font,at+Vector2(-3,7),"!",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color.WHITE)
	if snap_visible:
		draw_circle(snap_point, 5, Color("111c29"))
		draw_circle(snap_point, 5, Color("ffdf83"), false, 2)
		draw_line(snap_point - Vector2(9, 0), snap_point + Vector2(9, 0), Color("ffdf83"), 1)
		draw_line(snap_point - Vector2(0, 9), snap_point + Vector2(0, 9), Color("ffdf83"), 1)
	if pivot_visible:
		draw_arc(pivot_point, 9, 0, TAU, 28, Color("c7a2ff"), 2)
		draw_line(pivot_point - Vector2(14, 0), pivot_point + Vector2(14, 0), Color("c7a2ff"), 1.5)
		draw_line(pivot_point - Vector2(0, 14), pivot_point + Vector2(0, 14), Color("c7a2ff"), 1.5)
	if socket_line.size()==2:
		var segment: PackedVector2Array=DiagnosticsOverlay.clip_segment(socket_line[0],socket_line[1],socket_bounds().grow(-12))
		if segment.size()==2:
			draw_dashed_line(segment[0],segment[1],Color.BLACK,5,8,false,true)
			draw_dashed_line(segment[0],segment[1],socket_tint(socket_markers[-1]),2,8,false,true)
	if not caption.is_empty():
		var area: Rect2=socket_area if socket_area.has_area() else Rect2(Vector2.ZERO,size)
		if caption_area.has_area(): area=caption_area
		var lines: PackedStringArray = caption_lines(caption,maxf(40,area.size.x-40))
		var width: float = 0
		for line in lines: width = maxf(width, ThemeDB.fallback_font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, caption_font_size()).x + 20)
		width = minf(width, area.size.x - 20)
		var height: float = lines.size() * caption_line_height() + 12
		var minimum: Vector2=area.position+Vector2(10,10)
		var maximum: Vector2=(area.end-Vector2(width+10,height+10)).max(minimum)
		var at: Vector2=caption_position.clamp(minimum,maximum)
		var labels: Rect2
		for marker in socket_markers:
			var label_rect: Rect2=socket_label_rect(marker)
			if not label_rect.has_area(): continue
			labels=labels.merge(label_rect) if labels.has_area() else label_rect
		if labels.has_area():
			if labels.intersects(Rect2(at,Vector2(width,height))):
				at.x=minimum.x
				at.y=minimum.y if labels.get_center().y>area.get_center().y else maximum.y
		draw_style_box(caption_style(), Rect2(at, Vector2(width, height)))
		for i in lines.size(): draw_string(ThemeDB.fallback_font, at + Vector2(10, caption_font_size()+7 + i * caption_line_height()), lines[i], HORIZONTAL_ALIGNMENT_LEFT, width - 20, caption_font_size(), Color.WHITE if high_contrast else Color("e3efe9"))
	for marker in socket_markers: draw_socket(marker)

func draw_selection_marker(bounds: Rect2,index: int) -> void:
	if bounds.size.x<=0 or bounds.size.y<=0: return
	var rect: Rect2=bounds.grow(4)
	var length: float=minf(16,minf(rect.size.x,rect.size.y)/2)
	for corner in [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]:
		var sign: Vector2=Vector2(1 if corner.x==rect.position.x else -1,1 if corner.y==rect.position.y else -1)
		for end in [corner+Vector2(length*sign.x,0),corner+Vector2(0,length*sign.y)]:
			draw_line(corner,end,Color.BLACK,6); draw_line(corner,end,Color.WHITE,2)
	var font_size: int=roundi(12*text_scale)
	var width: float=maxf(22,ThemeDB.fallback_font.get_string_size(str(index),HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x+12)
	var at:=Vector2(clampf(rect.position.x,2,maxf(2,size.x-width-2)),clampf(rect.position.y-font_size-8,2,maxf(2,size.y-font_size-12)))
	draw_rect(Rect2(at,Vector2(width,font_size+8)),Color.BLACK)
	draw_rect(Rect2(at,Vector2(width,font_size+8)),Color.WHITE,false,1)
	draw_string(ThemeDB.fallback_font,at+Vector2(6,font_size+2),str(index),HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color.WHITE)

func caption_style() -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = Color.BLACK if high_contrast else Color(0.05, 0.12, 0.17, 0.9)
	result.set_corner_radius_all(5)
	return result

func caption_lines(text: String, available: float) -> PackedStringArray:
	var result:=PackedStringArray()
	var font: Font=ThemeDB.fallback_font
	for paragraph in text.split("\n"):
		var line: String=""
		for word in paragraph.split(" "):
			var candidate: String=line+" "+word if not line.is_empty() else word
			if not line.is_empty() and font.get_string_size(candidate,HORIZONTAL_ALIGNMENT_LEFT,-1,caption_font_size()).x>available:
				result.append(line)
				line=""
			for character in word:
				var next: String=line+character
				if not line.is_empty() and font.get_string_size(next,HORIZONTAL_ALIGNMENT_LEFT,-1,caption_font_size()).x>available:
					result.append(line)
					line=""
				line+=character
			line+=" "
		result.append(line.strip_edges())
	var limit: int=maxi(1,floori((size.y-32)/caption_line_height()))
	if result.size()>limit:
		result.resize(limit)
		result[limit-1]=result[limit-1].left(maxi(0,result[limit-1].length()-2))+"…"
	return result

func socket_tint(marker: Dictionary) -> Color:
	if high_contrast: return Color.WHITE
	if marker["blocked"]: return Color("#ffab84")
	return {"water":Color("#7dd8ff"),"power":Color("#ffe096")}.get(marker["kind"],Color("#83f0bd"))

func socket_bounds() -> Rect2:
	return socket_area if socket_area.has_area() else Rect2(Vector2.ZERO,size)

func socket_center(marker: Dictionary) -> Vector2:
	var at: Vector2=marker["at"]
	if not at.is_finite(): return Vector2.INF
	var area: Rect2=socket_bounds().grow(-12)
	if area.has_point(at): return at
	if area.has_area() and socket_line.size()==2:
		var segment: PackedVector2Array=DiagnosticsOverlay.clip_segment(socket_line[0],socket_line[1],area)
		if segment.size()==2: return segment[0] if marker.get("source",false) else segment[1]
	return at.clamp(area.position,area.end) if area.has_area() else at

func draw_socket(marker: Dictionary) -> void:
	var at: Vector2 = socket_center(marker)
	if not at.is_finite(): return
	var source: bool = marker.get("source", false)
	var tint: Color=socket_tint(marker)
	var radius: float = 6 if source else 10
	var delta: Vector2=marker["at"]-at
	var direction: Vector2=(delta if delta.length_squared()>1 else marker["direction"]).normalized()
	if not direction.is_zero_approx():
		var bounds: Rect2=socket_bounds().grow(-3)
		var tip: Vector2=(at+direction*26).clamp(bounds.position,bounds.end)
		draw_line(at,tip,Color.BLACK,5,true)
		draw_line(at,tip,tint,2.5,true)
		if tip.distance_to(at)>radius+6:
			var rear: Vector2=tip-direction*7
			var side:=Vector2(-direction.y,direction.x)*4
			var arrow:=PackedVector2Array([rear+side,tip,rear-side])
			draw_polyline(arrow,Color.BLACK,5,true)
			draw_polyline(arrow,tint,2,true)
	if marker["kind"] == "water":
		draw_arc(at, radius, 0, TAU, 32, Color.BLACK, 5, true)
		draw_arc(at, radius, 0, TAU, 32, tint, 2, true)
	elif marker["kind"] == "power":
		var diamond := PackedVector2Array([at+Vector2(0,-radius), at+Vector2(radius,0), at+Vector2(0,radius), at+Vector2(-radius,0), at+Vector2(0,-radius)])
		draw_polyline(diamond, Color.BLACK, 5, true)
		draw_polyline(diamond, tint, 2, true)
	else:
		var square := Rect2(at-Vector2.ONE*radius, Vector2.ONE*radius*2)
		draw_rect(square, Color.BLACK, false, 5)
		draw_rect(square, tint, false, 2)
	if marker["blocked"]:
		for sign in [-1,1]:
			var end:=Vector2(4,4*sign)
			draw_line(at-end,at+end,Color.BLACK,5,true)
			draw_line(at-end,at+end,tint,2,true)
	var rect: Rect2=socket_label_rect(marker)
	if not rect.has_area(): return
	draw_rect(rect, Color.BLACK if high_contrast else Color("#101820"))
	draw_string(ThemeDB.fallback_font,rect.position+Vector2(6,caption_font_size()+1),socket_label(marker),HORIZONTAL_ALIGNMENT_LEFT,rect.size.x-12,caption_font_size(),tint)

func socket_label(marker: Dictionary) -> String:
	var offscreen: bool=not socket_bounds().has_point(marker["at"])
	return ("Off-screen · " if offscreen else "")+("Blocked · " if marker["blocked"] else "")+str(marker["kind"]).capitalize()+" "+marker["label"].to_lower()

func socket_label_rect(marker: Dictionary) -> Rect2:
	var rect: Rect2=natural_socket_label(marker)
	if not marker.get("source",false) or not rect.has_area(): return rect
	var area: Rect2=socket_bounds()
	for other in socket_markers:
		if other.get("source",false): continue
		var target: Rect2=natural_socket_label(other)
		if not rect.intersects(target): continue
		var above: float=target.position.y-rect.size.y-3
		rect.position.y=above if above>=area.position.y+2 else minf(target.end.y+3,area.end.y-rect.size.y-2)
	return rect

func natural_socket_label(marker: Dictionary) -> Rect2:
	var area: Rect2=socket_bounds()
	var at: Vector2=socket_center(marker)
	if not at.is_finite() or area.size.x<24 or area.size.y<24: return Rect2()
	var font_size: int=caption_font_size()
	var width: float=minf(area.size.x-4,ThemeDB.fallback_font.get_string_size(socket_label(marker),HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x+12)
	var label_x: float=at.x+14 if at.x+14+width<area.end.x-2 else at.x-width-14
	var label_y: float=at.y-(font_size+20 if marker.get("source",false) else -12)
	var label_at:=Vector2(clampf(label_x,area.position.x+2,maxf(area.position.x+2,area.end.x-width-2)),clampf(label_y,area.position.y+2,maxf(area.position.y+2,area.end.y-font_size-10)))
	return Rect2(label_at,Vector2(width,font_size+8))
