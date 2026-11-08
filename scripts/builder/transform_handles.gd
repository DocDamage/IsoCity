extends RefCounted

const Rotation = preload("res://scripts/builder/rotation.gd")
const Layers = preload("res://scripts/builder/layers.gd")
const MODES = ["move","rotate","resize","off"]
const AXES = [Vector3.RIGHT,Vector3.UP,Vector3.BACK]
const COLORS = [Color("ff9292"),Color("a3ed96"),Color("8fc9ff")]
const FIELDS = ["position","direction","angle","tilt","scale"]
const LIMIT = 1000000.0
var studio: Control
var mode: String = "move"
var choice: OptionButton
var note: Label
var overlay: Control
var handles: Array[Dictionary] = []
var origin: Vector2
var pivot: Vector3
var terrain_height: float=0
var dragging: bool = false
var active: Dictionary = {}
var start: Vector2
var originals: Array[Dictionary] = []
var before: Dictionary = {}
var document: RefCounted
var dimension: String
var drag_pivot: Vector3
var orbit: bool
var total_angle: float = 0
var last_angle: float = 0
var report: String = ""

func _init(host: Control) -> void:
	studio=host
	var parent: Node=studio.height_input.get_parent()
	var row:=HFlowContainer.new(); parent.add_child(row)
	parent.move_child(row,studio.height_input.get_index())
	for child in parent.get_children():
		if child is Label and child.text=="Height": parent.move_child(row,child.get_index()); break
	choice=OptionButton.new()
	choice.fit_to_longest_item=false; choice.clip_text=true; choice.custom_minimum_size.x=140
	for name in ["Move handles","Rotate handles","Resize uniformly","Hide handles"]: choice.add_item(name)
	choice.tooltip_text="Drag a labeled world axis on the canvas. Rotation keeps the supplied artwork view; ground objects use quarter turns. Resize preserves proportions. Snap to grid also snaps handle increments. Escape/right-click cancels."
	row.add_child(choice)
	choice.item_selected.connect(func(index: int): set_mode(MODES[index]))
	var frame:=Button.new(); frame.text="Frame"; frame.tooltip_text="Center the camera on the selection's chosen pivot"; row.add_child(frame); frame.pressed.connect(frame_handles)
	note=studio.label(parent,"",12); note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	parent.move_child(note,row.get_index()+1)
	overlay=Control.new(); overlay.name="TransformHandles"; overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); studio.canvas.add_child(overlay)
	overlay.draw.connect(draw)

func set_mode(value: String) -> void:
	finish()
	mode=value if value in MODES else "move"
	choice.select(MODES.find(mode)); tick()

func settings() -> Dictionary: return {"mode":mode}
func restore(value: Variant) -> void:
	var data: Dictionary=value if value is Dictionary else {}
	set_mode(str(data.get("mode","move")))

func eligible() -> bool:
	return studio.enhancements_ready and not studio.walking and studio.tool=="select" and mode!="off" and not studio.arrange_tools.picking_pivot and not studio.selection_items().is_empty()

func project(point: Vector3) -> Vector2:
	return studio.overlay_position([point.x,point.y,point.z],terrain_height)

func radius() -> float: return 22.0 if studio.accessibility_settings.large_targets else 12.0

func tick() -> void:
	if dragging and not valid_targets(): cancel(); return
	handles.clear()
	if not eligible():
		if not dragging: note.text="Canvas handles hidden." if mode=="off" else "Select editable objects in Select / move to use canvas handles."
		overlay.queue_redraw(); return
	var items: Array=studio.selection_items()
	pivot=studio.arrange_tools.pivot(items)
	if not dragging:
		terrain_height=studio.terrain_height([pivot.x,pivot.y,pivot.z]) if studio.mode=="2d" else 0.0
		if studio.mode=="2d" and items.size()==1 and studio.arrange_tools.pivot_mode.selected!=2:
			terrain_height=studio.worlds["2d"].instances[items[0]["uid"]].get_meta("terrain_height",terrain_height)
	origin=project(pivot)
	var reach: float=minf(72,minf(minf(origin.x,studio.canvas.size.x-origin.x),minf(origin.y,studio.canvas.size.y-origin.y))-20)
	if reach<24:
		note.text="The selection or custom pivot is outside the canvas. Frame handles to bring its axes into view."
		overlay.queue_redraw(); return
	if mode=="move":
		for axis in 3:
			var vector: Vector2=project(pivot+AXES[axis])-origin
			if vector.length_squared()<0.00001: continue
			handles.append({"axis":axis,"name":axis_name(axis),"end":origin+vector.normalized()*reach,"vector":vector})
	elif mode=="resize":
		handles.append({"axis":-1,"name":"Uniform","end":origin+Vector2(1,-1).normalized()*reach})
	else:
		var ground: bool=items.any(func(item: Dictionary): return studio.library.is_ground_tile(item["asset"]))
		for axis in ([2] if studio.mode=="2d" else ([1] if ground else [0,1,2])):
			var u: Vector2
			var v: Vector2
			if studio.mode=="2d": u=Vector2.RIGHT; v=Vector2.DOWN
			else:
				var basis_u: Vector3=Vector3.UP if axis==0 else Vector3.RIGHT
				var basis_v: Vector3=AXES[axis].cross(basis_u)
				u=project(pivot+basis_u)-origin; v=project(pivot+basis_v)-origin
			if absf(u.cross(v))<0.001: continue
			var size: float=minf(68,reach)/maxf(u.length(),v.length())
			var points:=PackedVector2Array()
			for i in 65:
				var a: float=TAU*i/64.0
				points.append(origin+(u*cos(a)+v*sin(a))*size)
			handles.append({"axis":axis,"name":"Heading" if studio.mode=="2d" else axis_name(axis),"points":points,"u":u,"v":v,"end":points[8+axis*13]})
	if not dragging: note.text="Drag a labeled axis. Escape or right-click cancels."
	if not dragging and mode=="rotate" and studio.mode=="3d" and handles.size()<3 and not items.any(func(item: Dictionary): return studio.library.is_ground_tile(item["asset"])):
		note.text="An axis is edge-on. Orbit the camera to expose its rotation ring."
	overlay.queue_redraw()

func axis_name(axis: int) -> String:
	return ["X","Y","Height"][axis] if studio.mode=="2d" else ["X","Y","Z"][axis]

func hit(at: Vector2) -> Dictionary:
	var nearest: Dictionary={}
	var distance: float=radius()
	for handle in handles:
		var d: float=at.distance_to(handle["end"])
		if label_rect(handle).has_point(at): return handle
		if mode=="rotate":
			var points: PackedVector2Array=handle["points"]
			for i in points.size()-1: d=minf(d,at.distance_to(Geometry2D.get_closest_point_to_segment(at,points[i],points[i+1])))
		if d<distance: nearest=handle; distance=d
	return nearest

func input(event: InputEvent) -> bool:
	if dragging:
		if event is InputEventMouseMotion: update_drag(event.position); return true
		if event is InputEventMouseButton:
			if event.button_index==MOUSE_BUTTON_RIGHT and event.pressed: cancel(); return true
			if event.button_index==MOUSE_BUTTON_LEFT and not event.pressed: update_drag(event.position); finish(); return true
			if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]: finish(); return false
			return true
	if not eligible() or studio.modal_visible() or not event is InputEventMouseButton or not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT or event.alt_pressed or event.shift_pressed: return false
	tick()
	var handle: Dictionary=hit(event.position)
	if handle.is_empty(): return false
	begin(handle,event.position)
	return true

func begin(handle: Dictionary,at: Vector2) -> void:
	var keyboard_drag: bool=studio.control_settings.dragging and studio.control_settings.synthetic_input
	studio.finish_edit(at)
	if keyboard_drag: studio.control_settings.dragging=true
	var focus: Control=studio.get_viewport().gui_get_focus_owner()
	if focus: focus.release_focus()
	document=studio.current(); document.finish_checkpoint()
	dimension=studio.mode
	before=document.data.duplicate(true); originals.clear()
	for item in studio.selection_items(): originals.append(item.duplicate(true))
	active=handle.duplicate(true); start=at; drag_pivot=pivot
	orbit=studio.arrange_tools.orbit_enabled(originals)
	total_angle=0; last_angle=plane_angle(at)
	dragging=true; report=""; overlay.queue_redraw()

func valid_targets() -> bool:
	if studio.mode!=dimension or studio.current()!=document or studio.walking or studio.tool!="select": return false
	for item in originals:
		var current: Dictionary=document.object(item["uid"])
		if current.is_empty() or current.get("asset")!=item["asset"] or not Layers.editable(document.data,current,studio.library): return false
	return true

func plane_angle(at: Vector2) -> float:
	if not active.has("u"): return 0
	var d: Vector2=at-project(drag_pivot)
	var u: Vector2=active["u"]; var v: Vector2=active["v"]
	return atan2(u.cross(d)/u.cross(v),d.cross(v)/u.cross(v))

func update_drag(at: Vector2) -> void:
	if not dragging: return
	if not valid_targets(): cancel(); return
	var axis: int=active["axis"]
	var delta: float=0
	var ratio: float=1
	if mode=="move":
		var vector: Vector2=active["vector"]
		delta=(at-start).dot(vector)/vector.length_squared()
		if studio.snap_input.button_pressed:
			var step: float=([32.0,16.0,0.25][axis] if dimension=="2d" else (0.25 if axis==1 else 1.0))
			delta=snappedf(delta,step)
		var low: float=-INF; var high: float=INF
		for item in originals: low=maxf(low,-LIMIT-float(item["position"][axis])); high=minf(high,LIMIT-float(item["position"][axis]))
		delta=clampf(delta,low,high)
		report="Move %s · %+.2f %s" % [active["name"],delta,"px" if dimension=="2d" and axis<2 else "m"]
	elif mode=="resize":
		ratio=exp(clampf((at-start).dot(Vector2(1,-1).normalized())/110,-8,8))
		if studio.snap_input.button_pressed: ratio=maxf(.1,snappedf(float(originals[0]["scale"])*ratio,.1))/float(originals[0]["scale"])
		var low: float=0; var high: float=INF
		for item in originals: low=maxf(low,.1/float(item["scale"])); high=minf(high,8/float(item["scale"]))
		if orbit:
			for item in originals:
				for index in 3:
					var offset: float=float(item["position"][index])-drag_pivot[index]
					if absf(offset)<0.000001: continue
					var a: float=(-LIMIT-drag_pivot[index])/offset; var b: float=(LIMIT-drag_pivot[index])/offset
					low=maxf(low,minf(a,b)); high=minf(high,maxf(a,b))
		ratio=clampf(ratio,low,high)
		report="Resize · uniform ×%.2f" % ratio
	else:
		var angle: float=plane_angle(at)
		total_angle+=wrapf(angle-last_angle,-PI,PI); last_angle=angle
		delta=rad_to_deg(total_angle)
		var ground: bool=originals.any(func(item: Dictionary): return studio.library.is_ground_tile(item["asset"]))
		if ground: delta=snappedf(delta,90)
		elif studio.snap_input.button_pressed: delta=snappedf(delta,studio.rotation_step.value)
		report="Rotate %s · %+.1f°" % [active["name"],delta]
	var previous: Array[Dictionary]=[]
	for original in originals: previous.append(transform_record(document.object(original["uid"])))
	for original in originals:
		var item: Dictionary=document.object(original["uid"])
		restore_fields(item,original)
		if (mode=="resize" and is_equal_approx(ratio,1)) or (mode!="resize" and is_zero_approx(delta)): continue
		var position:=Vector3(original["position"][0],original["position"][1],original["position"][2])
		if mode=="move": position[axis]+=delta
		elif mode=="resize":
			item["scale"]=float(original["scale"])*ratio
			if orbit: position=drag_pivot+(position-drag_pivot)*ratio
		elif dimension=="2d":
			var sign: float=-1 if item["asset"].begins_with("3d:") else 1
			Rotation.set_heading(item,Rotation.heading(original,studio.library)+delta*sign,studio.library)
			if orbit:
				var values: Array=Rotation.orbit_position(original["position"],drag_pivot,delta,"2d")
				position=Vector3(values[0],values[1],values[2])
		else:
			if studio.library.is_ground_tile(item["asset"]): Rotation.set_heading(item,Rotation.heading(original,studio.library)+delta,studio.library)
			else:
				var angles: Vector3=Rotation.euler(original)*PI/180
				angles=(Basis(AXES[axis],deg_to_rad(delta))*Basis.from_euler(angles)).get_euler()*180/PI
				Rotation.set_heading(item,angles.y,studio.library)
				if absf(angles.x)<.00001 and absf(angles.z)<.00001: item.erase("tilt")
				else: item["tilt"]=[angles.x,angles.z]
			if orbit: position=drag_pivot+(position-drag_pivot).rotated(AXES[axis],deg_to_rad(delta))
		item["position"]=[position.x,position.y,position.z]
		if not position.is_finite() or maxf(absf(position.x),maxf(absf(position.y),absf(position.z)))>LIMIT:
			for record in previous: restore_fields(document.object(record["uid"]),record)
			report="Transform would exceed the supported editing range."
			note.text=report; overlay.queue_redraw(); return
	studio.changed()
	note.text=report+" · release to commit · Escape cancels"
	overlay.queue_redraw()

func restore_fields(item: Dictionary,original: Dictionary) -> void:
	for key in FIELDS:
		if original.has(key): item[key]=original[key].duplicate(true) if original[key] is Array else original[key]
		else: item.erase(key)

func transform_record(item: Dictionary) -> Dictionary:
	var result: Dictionary={"uid":item["uid"]}
	for key in FIELDS:
		if item.has(key): result[key]=item[key].duplicate(true) if item[key] is Array else item[key]
	return result

func finish() -> void:
	if not dragging: return
	dragging=false
	if studio.current()==document:
		if document.record_completed_change(before): studio.status.text=report+" · one undo step"
		studio.changed()
	clear_drag()

func cancel() -> void:
	if not dragging: return
	dragging=false
	for original in originals:
		var item: Dictionary=document.object(original["uid"])
		if not item.is_empty(): restore_fields(item,original)
	if studio.current()==document: studio.changed()
	studio.status.text="Handle drag cancelled. Original transforms restored."
	clear_drag()

func clear_drag() -> void:
	before={}; originals.clear(); active={}; document=null; tick()

func frame_handles() -> void:
	finish()
	var items: Array=studio.selection_items()
	if items.is_empty(): return
	var at: Vector3=studio.arrange_tools.pivot(items)
	if studio.mode=="2d": studio.worlds["2d"].camera.position=Vector2(at.x,at.y-(at.z+studio.terrain_height([at.x,at.y,at.z]))*8)
	else: studio.worlds["3d"].target=at; studio.worlds["3d"].update_camera()
	tick()

func draw() -> void:
	if handles.is_empty() or not eligible(): return
	var font_size: int=roundi(13*studio.accessibility_settings.text_scale)
	for handle in handles:
		var color: Color=COLORS[maxi(0,handle["axis"])]
		if dragging: color=Color.WHITE if handle["axis"]==active["axis"] else color.darkened(.45)
		if mode=="rotate":
			overlay.draw_polyline(handle["points"],Color.BLACK,5); overlay.draw_polyline(handle["points"],color,2)
		else:
			overlay.draw_line(origin,handle["end"],Color.BLACK,6); overlay.draw_line(origin,handle["end"],color,2)
		var at: Vector2=handle["end"]
		if mode=="move":
			var direction: Vector2=(at-origin).normalized()
			var triangle:=PackedVector2Array([at+direction*8,at-direction*6+direction.orthogonal()*6,at-direction*6-direction.orthogonal()*6])
			overlay.draw_colored_polygon(triangle,color)
		elif mode=="resize": overlay.draw_rect(Rect2(at-Vector2(7,7),Vector2(14,14)),color)
		else: overlay.draw_circle(at,6,color)
		var label: Rect2=label_rect(handle)
		overlay.draw_rect(label,Color.BLACK)
		overlay.draw_rect(label,Color.WHITE,false,1)
		overlay.draw_string(ThemeDB.fallback_font,label.position+Vector2(6,font_size+1),handle["name"],HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color.WHITE)
	overlay.draw_circle(origin,4,Color.WHITE)
	if dragging:
		var lines: PackedStringArray=studio.overlay.caption_lines(report,maxf(40,studio.canvas.size.x-32))
		var width: float=0
		for line in lines: width=maxf(width,ThemeDB.fallback_font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x)
		var size:=Vector2(minf(width+16,studio.canvas.size.x),lines.size()*(font_size+5)+10)
		var at: Vector2=(origin+Vector2(18,85)).clamp(Vector2.ZERO,(studio.canvas.size-size).max(Vector2.ZERO))
		overlay.draw_rect(Rect2(at,size),Color.BLACK)
		for i in lines.size(): overlay.draw_string(ThemeDB.fallback_font,at+Vector2(8,font_size+2+i*(font_size+5)),lines[i],HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color.WHITE)

func label_rect(handle: Dictionary) -> Rect2:
	var font_size: int=roundi(13*studio.accessibility_settings.text_scale)
	var size: Vector2=ThemeDB.fallback_font.get_string_size(handle["name"],HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)+Vector2(12,8)
	return Rect2((handle["end"]+Vector2(12,-12)).clamp(Vector2.ZERO,(studio.canvas.size-size).max(Vector2.ZERO)),size)
