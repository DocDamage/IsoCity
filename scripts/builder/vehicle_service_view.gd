extends Node

const Plan=preload("res://scripts/builder/vehicle_service_plan.gd")
const Colors: Dictionary={"fuel":Color("ffc66d"),"charge":Color("74d5ff"),"wash":Color("8fe9ff"),"repair":Color("ffd785")}
var driver: Node
var panel: PanelContainer
var text: Label
var request: Button
var cancel: Button
var marker: Node
var marked: Array=[]
var effects: Dictionary={}
var elapsed: float=0
var animation: float=0
var ui_scale: float=1
var large_targets: bool=false
var high_contrast: bool=false
var bottom_inset: float=74
var available_width: float=INF
var style_signature: Array=[]

func _ready() -> void:
	var layer:=CanvasLayer.new()
	layer.layer=23
	add_child(layer)
	panel=PanelContainer.new()
	layer.add_child(panel)
	var box:=VBoxContainer.new()
	panel.add_child(box)
	text=Label.new()
	text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	box.add_child(text)
	var actions:=HBoxContainer.new()
	box.add_child(actions)
	request=Button.new()
	request.text="Request"
	request.accessibility_name="Request vehicle care"
	request.pressed.connect(driver.request_vehicle_service)
	actions.add_child(request)
	cancel=Button.new()
	cancel.text="Cancel"
	cancel.accessibility_name="Cancel vehicle care"
	cancel.pressed.connect(driver.cancel_vehicle_service)
	actions.add_child(cancel)
	for button in [request,cancel]:
		button.clip_text=true
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	panel.hide()

func display_point(point: Vector2,height: float) -> Variant:
	if driver.exploration.dimension=="2d": return Plan.Drive.world(point,"2d")-Vector2(0,height*8)
	return Plan.Drive.world(point,"3d",height)

func _process(delta: float) -> void:
	if not driver.care_visible():
		panel.hide()
		if is_instance_valid(marker): marker.hide()
		for effect in effects.values(): effect["root"].hide()
		return
	animation+=minf(delta,.1)
	elapsed+=delta
	if elapsed>=.12:
		elapsed=0
		refresh()
	draw_effects()

func nearest(pose: Dictionary) -> Dictionary:
	var best: float=24*24
	var result: Dictionary={}
	for bay in driver.care.bays.values():
		var distance: float=pose["point"].distance_squared_to(bay["center"])
		if distance<best:
			best=distance
			result=bay
	return result

func refresh() -> void:
	var uid: String=driver.care_uid()
	var runtime=driver.care
	var pose: Dictionary=driver.care_snapshot(uid)
	panel.visible=not pose.is_empty()
	if not panel.visible:
		if is_instance_valid(marker): marker.hide()
		return
	var state: Dictionary=runtime.state(uid)
	var config: Dictionary=runtime.vehicles[uid]["config"]
	var job: Dictionary=runtime.jobs.get(uid,{})
	var bay: Dictionary=runtime.bays.get(job.get("bay",""),nearest(pose))
	var supply: String="Charge" if config["energy"]=="charge" else "Fuel"
	text.text="%s %.1f / %.1f · Condition %d%% · Clean %d%%\n%s"%[
		supply,state["energy"],config["capacity"],roundi(state["condition"]),roundi(state["cleanliness"]),
		"Vehicle-care wallet · %d credits"%runtime.wallet if runtime.wallet>=0 else "Vehicle care · creative preview"]
	if not bay.is_empty():
		text.text+="\n%s · %d credits"%[Plan.TITLES[bay["kind"]],bay["price"]] if runtime.wallet>=0 else "\n"+Plan.TITLES[bay["kind"]]
		update_marker(bay)
	elif is_instance_valid(marker): marker.hide()
	if not job.is_empty():
		if job["state"]=="servicing":
			text.text+="\nService in progress · %.1fs"%job["remaining"]
		else:
			text.text+="\nQueue %d · Park inside the marked bay."%(runtime.queues[job["bay"]].find(uid)+1)
	elif runtime.feedback.has(uid): text.text+="\n"+runtime.feedback[uid]
	elif bay.is_empty(): text.text+="\nDrive to a marked service bay."
	else:
		var reason: String=Plan.reason(config,pose,bay)
		if not reason.is_empty(): text.text+="\n"+reason
	request.text=driver.care_key+" · Request"
	request.disabled=not job.is_empty() or driver.active.is_empty() or bay.is_empty()
	cancel.text=driver.care_cancel_key+" · Cancel"
	cancel.disabled=job.is_empty()
	apply_style()
	var viewport: Vector2=get_viewport().get_visible_rect().size
	var width_limit: float=minf(maxf(260,viewport.x*.42),available_width)
	panel.custom_minimum_size.x=minf(minf(340*ui_scale,width_limit),viewport.x-24)
	panel.reset_size()
	panel.position=Vector2(12,maxf(12,viewport.y-panel.size.y-bottom_inset))

func apply_style() -> void:
	var next: Array=[ui_scale,large_targets,high_contrast]
	if style_signature==next: return
	style_signature=next
	text.add_theme_font_size_override("font_size",roundi(13*ui_scale))
	for button in [request,cancel]:
		button.add_theme_font_size_override("font_size",roundi(13*ui_scale))
		button.custom_minimum_size.y=44 if large_targets else 34
	var style:=StyleBoxFlat.new()
	style.bg_color=Color.BLACK if high_contrast else Color("142730")
	style.border_color=Color.WHITE if high_contrast else Color("6bafc5")
	style.set_border_width_all(2 if high_contrast else 1)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel",style)

func update_marker(bay: Dictionary) -> void:
	var signature: Array=[bay["uid"],bay["center"],bay["axis"],bay["width"],bay["length"],bay["height"],bay["supported"]]
	if is_instance_valid(marker):
		if marked==signature:
			marker.show()
			return
		marker.free()
	marked=signature
	var center: Vector2=bay["center"]
	var forward: Vector2=bay["axis"]
	var right:=Vector2(forward.y,-forward.x)
	var side: Vector2=right*bay["width"]*.5
	var end: Vector2=forward*bay["length"]*.5
	var entry: Vector2=center-end
	var arrow: Vector2=entry-forward*.45
	var tail: Vector2=arrow-forward*minf(bay["approach"],3.0)
	var pieces: Array=[[center-end-side,center-end+side,center+end+side,center+end-side,center-end-side],[tail,arrow],[arrow-forward*.8-right*.6,arrow,arrow-forward*.8+right*.6]]
	var tint: Color=Colors[bay["kind"]] if bay["supported"] else Color("ff7166")
	var height: float=bay["height"]+.06
	if driver.exploration.dimension=="2d":
		marker=Node2D.new()
		marker.z_index=60
		for piece in pieces:
			var line:=Line2D.new()
			line.width=2.5
			line.default_color=tint
			for point in piece: line.add_point(display_point(point,height))
			marker.add_child(line)
	else:
		var mesh:=ImmediateMesh.new()
		var material:=StandardMaterial3D.new()
		material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color=tint
		mesh.surface_begin(Mesh.PRIMITIVE_LINES,material)
		for piece in pieces:
			for index in range(1,piece.size()):
				mesh.surface_add_vertex(display_point(piece[index-1],height))
				mesh.surface_add_vertex(display_point(piece[index],height))
		mesh.surface_end()
		marker=MeshInstance3D.new()
		marker.mesh=mesh
		marker.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(marker)

func make_effect(kind: String) -> Dictionary:
	var dimension: String=driver.exploration.dimension
	var root: Node=Node2D.new() if dimension=="2d" else Node3D.new()
	if dimension=="2d": root.z_index=120
	add_child(root)
	var tint: Color=Colors[kind].lightened(.2)
	var sphere:=SphereMesh.new()
	sphere.radial_segments=6
	sphere.rings=3
	sphere.radius=.08
	sphere.height=.16
	var material:=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color=tint
	for index in 10:
		if dimension=="2d":
			var particle:=Polygon2D.new()
			var polygon:=PackedVector2Array()
			for side in 6: polygon.append(Vector2.from_angle(side*TAU/6)*3)
			particle.polygon=polygon
			particle.color=tint
			root.add_child(particle)
		else:
			var particle:=MeshInstance3D.new()
			particle.mesh=sphere
			particle.material_override=material
			particle.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(particle)
	return {"root":root,"kind":kind}

func draw_effects() -> void:
	var shown: Dictionary={}
	var runtime=driver.care
	for uid in runtime.jobs:
		if shown.size()>=8: break
		if not runtime.locked(uid): continue
		var pose: Dictionary=driver.care_snapshot(uid)
		if pose.is_empty(): continue
		var bay: Dictionary=runtime.bays[runtime.jobs[uid]["bay"]]
		var kind: String=bay["kind"]
		shown[uid]=true
		if not effects.has(uid): effects[uid]=make_effect(kind)
		var root: Node=effects[uid]["root"]
		root.show()
		var heading: Vector2=pose["heading"]
		var right:=Vector2(heading.y,-heading.x)
		for index in root.get_child_count():
			var t: float=fposmod(animation*(1.5 if kind=="wash" else 2.0)+index*.19,1.0)
			var p: Vector2=pose["point"]+right*sin(index*2.4)*pose["extent"].x*(.55+t*.55)+heading*cos(index*1.8)*pose["extent"].y*.7
			root.get_child(index).position=display_point(p,bay["height"]+.45+t*1.35)
	for uid in effects.keys():
		if not shown.has(uid):
			effects[uid]["root"].free()
			effects.erase(uid)
