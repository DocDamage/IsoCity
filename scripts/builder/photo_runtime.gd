extends Node
const Plan=preload("res://scripts/builder/photo_plan.gd")
var exploration: Node
var control_input: Callable
var input_allowed: Callable
var active: bool=false
var view: Dictionary={}
var config: Dictionary={}
var saved: Dictionary={}
var scope: String=""
var camera: Node
var recording: bool=false
var recorded: Array=[]
var record_elapsed: float=0
var next_sample: float=.1
var pending_take: bool=false
var record_scope: String=""
var playing: Array=[]
var play_elapsed: float=0
var loop: bool=false
var dragging: bool=false
var capture_busy: bool=false
var notice: String=""
var focus_layer: CanvasLayer
var focus_screen: ColorRect
var attributes: CameraAttributesPractical
var hidden: Array=[]

func _ready() -> void:
	process_priority=1000
	focus_layer=CanvasLayer.new(); focus_layer.name="PhotoFocus"; focus_layer.layer=5; add_child(focus_layer)
	focus_screen=ColorRect.new(); focus_screen.mouse_filter=Control.MOUSE_FILTER_IGNORE; focus_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var material:=ShaderMaterial.new(); material.shader=preload("res://scripts/builder/photo_focus.gdshader"); focus_screen.material=material; focus_layer.add_child(focus_screen); focus_layer.hide()
func context() -> Dictionary: return preload("res://scripts/builder/prop_plan.gd").context(exploration)
func capture_view() -> Dictionary:
	var result: Dictionary={}
	var source: Node=exploration.get_parent().camera
	var frame: Node=context()["world"]; var position: Variant=frame.to_local(source.global_position)
	if exploration.dimension=="2d":
		var height: float=maxf(1,get_viewport().get_visible_rect().size.y); var reference: float=view.get("frame_height",height) if active else height; var zoom: Vector2=source.zoom*reference/height
		if active: zoom=zoom.clamp(Vector2.ONE*.1,Vector2.ONE*16)
		result={"position":[position.x,position.y],"zoom":[zoom.x,zoom.y],"frame_height":reference,"rotation":source.global_rotation-frame.global_rotation}
	else:
		var angles: Vector3=(frame.global_basis.inverse()*source.global_basis).get_euler()
		result={"position":[position.x,position.y,position.z],"rotation":[angles.x,angles.y,angles.z],"fov":source.fov,"size":source.size,"projection":source.projection}
	for key in ["dof_enabled","focus_distance","focus_range","blur","focus_band","band_width","hide_avatar","move_speed"]: result[key]=config.get(key,Plan.defaults()[key])
	return result
func hide_node(node: Node,values: Array) -> void:
	if is_instance_valid(node) and (node is CanvasItem or node is Node3D or node is CanvasLayer or node is Window): values.append({"node":node,"visible":node.visible}); node.hide()
func restore_nodes(values: Array) -> void:
	for entry in values:
		if is_instance_valid(entry["node"]): entry["node"].visible=entry["visible"]
	values.clear()
func start() -> bool:
	if active: return true
	if exploration.arcade: exploration.arcade.close("Arcade closed for Photo.")
	if exploration.camping: exploration.camping.cancel_player("Camping interrupted for Photo.")
	camera=exploration.get_parent().camera
	if not is_instance_valid(camera) or not is_instance_valid(exploration.player): return false
	config=Plan.settings(context()["data"]); scope=preload("res://scripts/builder/prop_plan.gd").scope(exploration); view=capture_view()
	if exploration.dimension=="3d" and not context()["data"].get("photo",{}).has("focus_distance") and camera.projection==Camera3D.PROJECTION_ORTHOGONAL:
		config["focus_distance"]=clampf(camera.size,.1,500); view["focus_distance"]=config["focus_distance"]
	var player: Node=exploration.player
	saved={"view":view.duplicate(true),"transform":camera.transform,"physics":player.is_physics_processing(),"visible":player.visible,"attributes":camera.attributes if exploration.dimension=="3d" else null}
	if exploration.props and not exploration.props.active.is_empty(): saved["use_physics"]=exploration.props.saved.get("physics",false)
	elif exploration.driving and not exploration.driving.active.is_empty(): saved["use_physics"]=exploration.driving.saved.get("physics",false)
	if exploration.driving and not exploration.driving.active.is_empty(): exploration.driving.speed=0
	player.set_physics_process(false); player.velocity=Vector2.ZERO if exploration.dimension=="2d" else Vector3.ZERO
	var world: Node=exploration.get_parent()
	for key in ["grid","selection","ghost"]:
		if key in world: hide_node(world.get(key),hidden)
	attributes=CameraAttributesPractical.new() if exploration.dimension=="3d" else null
	active=true; notice=""; apply_view(view)
	set_render_detail(true)
	return true

func set_render_detail(enabled: bool) -> void:
	if not is_instance_valid(camera): return
	if enabled: camera.set_meta("iso_photo_detail",true)
	else: camera.remove_meta("iso_photo_detail")
	if is_inside_tree(): get_tree().call_group("iso_render_presenters","refresh_for_viewport",get_viewport())
func apply_view(value: Dictionary) -> bool:
	if not active or not Plan.view_valid(value,exploration.dimension): return false
	view=value.duplicate(true)
	var frame: Node=context()["world"]
	if exploration.dimension=="2d":
		var ratio: float=maxf(1,get_viewport().get_visible_rect().size.y)/float(view.get("frame_height",maxf(1,get_viewport().get_visible_rect().size.y)))
		camera.global_position=frame.to_global(Vector2(view["position"][0],view["position"][1])); camera.zoom=Vector2(view["zoom"][0],view["zoom"][1])*ratio; camera.global_rotation=frame.global_rotation+view.get("rotation",0)
	else:
		camera.global_position=frame.to_global(Vector3(view["position"][0],view["position"][1],view["position"][2])); camera.global_basis=frame.global_basis*Basis.from_euler(Vector3(view["rotation"][0],view["rotation"][1],view["rotation"][2])); camera.projection=int(view["projection"]); camera.fov=view["fov"]; camera.size=view["size"]
	for key in ["dof_enabled","focus_distance","focus_range","blur","focus_band","band_width","hide_avatar","move_speed"]:
		if view.has(key): config[key]=view[key]
	apply_focus(); return true
func apply_focus() -> void:
	if not active: return
	var enabled: bool=config.get("dof_enabled",false)
	if exploration.dimension=="3d":
		attributes.dof_blur_far_enabled=enabled; attributes.dof_blur_near_enabled=enabled; attributes.dof_blur_amount=config["blur"]
		attributes.dof_blur_far_distance=config["focus_distance"]+config["focus_range"]*.5; attributes.dof_blur_far_transition=config["focus_range"]*.5
		attributes.dof_blur_near_distance=maxf(0,config["focus_distance"]-config["focus_range"]*.5); attributes.dof_blur_near_transition=config["focus_range"]*.5; camera.attributes=attributes
	else:
		focus_layer.visible=enabled; focus_screen.size=get_viewport().get_visible_rect().size
		focus_screen.material.set_shader_parameter("focus_band",config["focus_band"]); focus_screen.material.set_shader_parameter("band_width",config["band_width"]); focus_screen.material.set_shader_parameter("amount",config["blur"])
	if is_instance_valid(exploration.player): exploration.player.visible=false if config["hide_avatar"] else saved["visible"]
func configure(changes: Dictionary) -> void:
	if not Plan.valid(changes,exploration.dimension): return
	for key in changes:
		if not key in ["bookmarks","paths"]: config[key]=changes[key]; view[key]=changes[key]
	apply_focus()
func held(id: String) -> bool:
	if control_input.is_valid(): return control_input.call(id)
	match id:
		"move_up": return Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)
		"move_down": return Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)
		"move_left": return Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)
		"move_right": return Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)
		"jump": return Input.is_physical_key_pressed(KEY_SPACE)
		"recover": return Input.is_physical_key_pressed(KEY_X)
	return false
func navigate(delta: float,axis: Vector3) -> void:
	if not active or axis.is_zero_approx(): return
	playing=[]; var amount: float=config["move_speed"]*clampf(delta,0,.1)
	if exploration.dimension=="2d":
		var delta_position: Vector2=Vector2(axis.x,axis.z)*amount*16/camera.zoom.x; view["position"][0]+=delta_position.x; view["position"][1]+=delta_position.y
	else:
		var basis: Basis=Basis.from_euler(Vector3(view["rotation"][0],view["rotation"][1],view["rotation"][2])); var delta_position: Vector3=(basis.x*axis.x+basis.z*axis.z+Vector3.UP*axis.y)*amount
		for index in 3: view["position"][index]+=delta_position[index]
	apply_view(view)
func input(event: InputEvent) -> bool:
	if not active: return false
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]: dragging=event.pressed; return true
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			playing=[]; var factor: float=1.1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1/1.1
			if exploration.dimension=="2d":
				for index in 2: view["zoom"][index]=clampf(view["zoom"][index]*factor,.1,16)
			elif view["projection"]==1: view["size"]=clampf(view["size"]/factor,1,500)
			else: view["fov"]=clampf(view["fov"]/factor,10,140)
			apply_view(view); return true
	if event is InputEventMouseMotion and dragging:
		playing=[]
		if exploration.dimension=="2d": view["position"][0]-=event.relative.x/camera.zoom.x; view["position"][1]-=event.relative.y/camera.zoom.y
		else: view["rotation"][0]=clampf(view["rotation"][0]-event.relative.y*.005,deg_to_rad(-85),deg_to_rad(85)); view["rotation"][1]=wrapf(view["rotation"][1]-event.relative.x*.005,-PI,PI)
		apply_view(view); return true
	return event is InputEventMouseButton or event is InputEventMouseMotion
func action(id: String) -> bool:
	if not active: return false
	if id in ["zoom_in","zoom_out"]:
		var wheel:=InputEventMouseButton.new(); wheel.pressed=true; wheel.button_index=MOUSE_BUTTON_WHEEL_UP if id=="zoom_in" else MOUSE_BUTTON_WHEEL_DOWN; input(wheel); return true
	if exploration.dimension=="3d" and id in ["orbit_left","orbit_right","tilt_up","tilt_down"]:
		playing=[]
		if id.begins_with("orbit_"): view["rotation"][1]=wrapf(view["rotation"][1]+(-PI/12 if id=="orbit_left" else PI/12),-PI,PI)
		else: view["rotation"][0]=clampf(view["rotation"][0]+(PI/24 if id=="tilt_up" else -PI/24),deg_to_rad(-85),deg_to_rad(85))
		apply_view(view); return true
	return false
func start_recording() -> bool:
	if not start(): return false
	playing=[]; recorded=[{"time":0.0,"view":view.duplicate(true)}]; record_elapsed=0; next_sample=.1; recording=true; pending_take=false; record_scope=scope; return true
func stop_recording() -> Array:
	if not recording: return recorded
	recording=false
	var time: float=maxf(.016,minf(record_elapsed,Plan.MAX_SECONDS))
	if time>float(recorded[-1]["time"]) and recorded.size()<Plan.MAX_SAMPLES: recorded.append({"time":time,"view":view.duplicate(true)})
	pending_take=recorded.size()>=2; return recorded
func play(path: Dictionary,repeat: bool=false) -> bool:
	if not Plan.entry_valid(path,exploration.dimension,true) or recording or not start(): return false
	playing=path["samples"].duplicate(true); play_elapsed=0; loop=repeat; apply_view(playing[0]["view"]); return true
func advance(delta: float) -> void:
	if not active or not is_finite(delta) or delta<0: return
	if not playing.is_empty():
		play_elapsed+=delta; var duration: float=playing[-1]["time"]
		if loop: play_elapsed=fmod(play_elapsed,duration)
		apply_view(Plan.sample(playing,play_elapsed,exploration.dimension))
		if not loop and play_elapsed>=duration: playing=[]
	if recording:
		record_elapsed=minf(Plan.MAX_SECONDS,record_elapsed+delta)
		if record_elapsed>=next_sample and recorded.size()<Plan.MAX_SAMPLES-1:
			recorded.append({"time":record_elapsed,"view":view.duplicate(true)}); next_sample=record_elapsed+.1
		if record_elapsed>=Plan.MAX_SECONDS or recorded.size()>=Plan.MAX_SAMPLES-1: stop_recording(); notice="Recording limit reached · save this take."
func _process(delta: float) -> void:
	if not active: return
	if scope!=preload("res://scripts/builder/prop_plan.gd").scope(exploration) or not is_instance_valid(camera): stop(); return
	for entry in hidden:
		if is_instance_valid(entry["node"]): entry["node"].hide()
	if not input_allowed.is_valid() or input_allowed.call(): navigate(delta,Vector3(float(held("move_right"))-float(held("move_left")),float(held("jump"))-float(held("recover")),float(held("move_down"))-float(held("move_up"))).limit_length(1))
	advance(delta); apply_view(view)
func stop() -> void:
	if not active: return
	if recording: stop_recording()
	playing=[]; dragging=false
	if is_instance_valid(camera):
		camera.transform=saved["transform"]
		if exploration.dimension=="3d": camera.projection=int(saved["view"]["projection"]); camera.fov=saved["view"]["fov"]; camera.size=saved["view"]["size"]; camera.attributes=saved["attributes"]
		else: camera.zoom=Vector2(saved["view"]["zoom"][0],saved["view"]["zoom"][1])
	if is_instance_valid(exploration.player):
		var using_prop: bool=is_instance_valid(exploration.props) and not exploration.props.active.is_empty()
		var driving: bool=is_instance_valid(exploration.driving) and not exploration.driving.active.is_empty()
		var physics: bool=false if using_prop or driving else saved.get("use_physics",saved["physics"])
		exploration.player.set_physics_process(physics); exploration.player.visible=saved["visible"]
	restore_nodes(hidden); focus_layer.hide(); attributes=null; active=false; saved={}
	set_render_detail(false)
func reset() -> void:
	stop(); recorded=[]; pending_take=false; record_scope=""; scope=""; notice=""
func clean_nodes(node: Node,values: Array) -> void:
	if node.get_meta("photo_hide",false): hide_node(node,values); return
	if node is Window: hide_node(node,values); return
	if node is SubViewport: return
	if node is CanvasLayer and not node.name in ["WeatherLayer","PhotoFocus"]: hide_node(node,values)
	if node is Label or node is Label3D: hide_node(node,values)
	for child in node.get_children(): clean_nodes(child,values)
func screenshot(path: String) -> Error:
	if capture_busy: return ERR_BUSY
	if DisplayServer.get_name()=="headless": notice="Screenshots require a rendering window."; return ERR_UNAVAILABLE
	var was_active: bool=active
	if not start(): return ERR_UNCONFIGURED
	set_render_detail(true)
	capture_busy=true; var visibility: Array=[]
	for child in get_viewport().get_children(): clean_nodes(child,visibility)
	await get_tree().process_frame; RenderingServer.force_draw(false); RenderingServer.force_draw(false)
	var frame: Image=get_viewport().get_texture().get_image(); var result: Error=frame.save_png(path if path.to_lower().ends_with(".png") else path+".png") if frame and not frame.is_empty() else ERR_CANT_CREATE
	restore_nodes(visibility); capture_busy=false
	if not was_active: stop()
	notice="Saved clean screenshot: "+path if result==OK else "Screenshot failed: "+error_string(result)
	return result
func _exit_tree() -> void: stop()
