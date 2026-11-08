extends RefCounted
const Plan=preload("res://scripts/builder/terrain_plan.gd")
const Traffic=preload("res://scripts/builder/traffic_plan.gd")
var studio: Control
var panel: ScrollContainer
var enabled: CheckButton
var protect_objects: CheckButton
var protect_roads: CheckButton
var protect_actors: CheckButton
var connected_shores: CheckButton
var connected_cliffs: CheckButton
var operation: OptionButton
var radius: SpinBox
var amount: SpinBox
var target: SpinBox
var center_x: SpinBox
var center_z: SpinBox
var width: SpinBox
var depth: SpinBox
var land: ColorPickerButton
var water: ColorPickerButton
var detail: Label
var drawing: bool=false
var before: Dictionary={}
var last: Vector2
var changed_count: int=0
var fields_stamp: int=-1
var fields_mode: String=""
var elapsed: float=0
var obstacles: Array[Rect2]=[]
var obstacles_stamp: int=0
func _init(host: Control) -> void:
	studio=host; panel=ScrollContainer.new(); panel.name="Terrain"; panel.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; panel.follow_focus=true; studio.workspace_layout.tabs.add_child(panel)
	var box:=VBoxContainer.new(); box.size_flags_horizontal=Control.SIZE_EXPAND_FILL; box.add_theme_constant_override("separation",8); panel.add_child(box)
	studio.label(box,"Terrain and water",17); detail=studio.label(box,"",12); detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	enabled=toggle(box,"Enable sculpted terrain")
	center_x=field(box,"Terrain center X",-512,512,1); center_z=field(box,"Terrain center Z",-512,512,1); width=field(box,"Terrain width",8,256,2); depth=field(box,"Terrain depth",8,256,2)
	studio.label(box,"Land color",12); land=ColorPickerButton.new(); land.custom_minimum_size.y=36; box.add_child(land)
	studio.label(box,"Water color",12); water=ColorPickerButton.new(); water.custom_minimum_size.y=36; box.add_child(water)
	protect_objects=toggle(box,"Protect placed objects"); protect_roads=toggle(box,"Protect roads"); protect_actors=toggle(box,"Protect people and vehicles")
	connected_shores=toggle(box,"Connected shore tiles")
	connected_cliffs=toggle(box,"Connected rock faces")
	button(box,"Apply terrain settings",apply_settings)
	operation=OptionButton.new(); operation.fit_to_longest_item=false; box.add_child(operation)
	for title in ["Raise hills","Lower ground","Flatten to height","Smooth banks","Paint water","Drain water","Dig a filled basin","Reset to flat and dry"]: operation.add_item(title)
	radius=field(box,"Brush radius",1,24,.5); amount=field(box,"Strength / basin depth",.01,8,.05); target=field(box,"Target height / water level",-24,24,.25); radius.value=4; amount.value=.5
	button(box,"Sculpt on canvas",activate); button(box,"Apply brush at view center",dab_center)
	var help: Label=studio.label(box,"Choose an operation, then drag on the canvas or use the keyboard canvas cursor and drag shortcut. A stroke is one Undo step. Basin lowers land and adds level water; use Smooth to soften banks. Reset restores dry, flat samples under the brush. Protected areas leave a small blending margin. Terrain settings, heights and water save with the project. Changing bounds must retain existing samples. Terrain editing is available from the exterior city.",12); help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
func field(parent: Node,title: String,low: float,high: float,step: float) -> SpinBox:
	studio.label(parent,title,12); return studio.spin(parent,low,high,step,low)
func toggle(parent: Node,title: String) -> CheckButton:
	var result:=CheckButton.new(); result.text=title; parent.add_child(result); return result
func button(parent: Node,title: String,callback: Callable) -> void:
	var result:=Button.new(); result.text=title; result.clip_text=true; parent.add_child(result); result.pressed.connect(callback)
func start() -> void: refresh()
func document() -> RefCounted: return studio.interior_tools.root_document(studio.mode)
func editable() -> bool:
	if studio.interior_tools.editing() or studio.worlds[studio.mode].exploration.interior!=null: studio.status.text="Sculpt terrain from the exterior city."; return false
	if not Plan.Layers.shown(document().data,"Ground") or Plan.Layers.locked(document().data,"Ground"): studio.status.text="Show and unlock Ground before sculpting."; return false
	return true
func show() -> void:
	studio.workspace_presets.set_focus(false)
	if studio.walking: studio.set_walking(false)
	studio.workspace_layout.inspector_toggle.button_pressed=true; studio.workspace_layout.tabs.current_tab=panel.get_index(); studio.workspace_layout.tabs.get_tab_bar().call_deferred("ensure_tab_visible",panel.get_index()); refresh()
func refresh() -> void:
	if studio.documents.is_empty(): return
	var config: Dictionary=Plan.settings(document().data); var stamp: int=hash([studio.mode,config])
	if stamp==fields_stamp: return
	fields_stamp=stamp; var area: Rect2i=Plan.bounds(document().data)
	enabled.set_pressed_no_signal(config["enabled"]); center_x.set_value_no_signal((area.position.x+area.size.x*.5)*Plan.CELL_SIZE); center_z.set_value_no_signal((area.position.y+area.size.y*.5)*Plan.CELL_SIZE); width.set_value_no_signal(area.size.x*Plan.CELL_SIZE); depth.set_value_no_signal(area.size.y*Plan.CELL_SIZE); land.color=Color(config["land_color"]); water.color=Color(config["water_color"])
	protect_objects.set_pressed_no_signal(config["protect_objects"]); protect_roads.set_pressed_no_signal(config["protect_roads"]); protect_actors.set_pressed_no_signal(config["protect_actors"])
	for control in [connected_shores,connected_cliffs]:
		control.disabled=studio.mode!="2d"
		control.tooltip_text="The reviewed connected textures are available in the Pixel world." if control.disabled else "Use native pixel artwork on compatible terrain surfaces."
	connected_shores.set_pressed_no_signal(config["connected_shores"])
	connected_cliffs.set_pressed_no_signal(config["connected_cliffs"])
func apply_settings() -> void:
	if not editable(): return
	studio.finish_edit(studio.canvas_pointer()); var doc: RefCounted=document(); doc.finish_checkpoint()
	var size:=Vector2i(roundi(width.value/Plan.CELL_SIZE),roundi(depth.value/Plan.CELL_SIZE)); var origin:=Vector2i(roundi(center_x.value/Plan.CELL_SIZE-size.x*.5),roundi(center_z.value/Plan.CELL_SIZE-size.y*.5))
	var config: Dictionary=doc.data.get("terrain",{}).duplicate(true); config.merge({"enabled":enabled.button_pressed,"bounds":[origin.x,origin.y,size.x,size.y],"land_color":land.color.to_html(),"water_color":water.color.to_html(),"protect_objects":protect_objects.button_pressed,"protect_roads":protect_roads.button_pressed,"protect_actors":protect_actors.button_pressed},true)
	var surfaces: Dictionary={"connected_shores":connected_shores,"connected_cliffs":connected_cliffs}
	for field in surfaces:
		if studio.mode=="2d" and surfaces[field].button_pressed: config[field]=true
		else: config.erase(field)
	var candidate: Dictionary=doc.data.duplicate(false); candidate["terrain"]=config
	if not Plan.valid_settings(config) or not Plan.valid_records(doc.data.get("terrain_vertices",[]),candidate) or not Plan.valid_records(doc.data.get("water_cells",[]),candidate,true): studio.status.text="Terrain bounds must fit the supported area and retain all existing samples."; return
	if config==doc.data.get("terrain",{}): return
	var old: Dictionary=doc.data.duplicate(true); doc.data["terrain"]=config; doc.record_completed_change(old); studio.changed(); refresh(); show(); studio.status.text="Terrain settings applied."
func activate() -> void:
	if not editable() or not Plan.settings(document().data)["enabled"]: studio.status.text="Enable terrain and apply its settings before sculpting."; return
	studio.finish_edit(studio.canvas_pointer()); studio.set_walking(false); studio.set_tool("terrain"); studio.clear_assembly(); show(); studio.status.text="Terrain · drag to sculpt; right-click cancels the current stroke."
func point(at: Vector2) -> Dictionary:
	var world: Node=studio.worlds[studio.mode]
	if studio.mode=="2d":
		var pixel: Vector2=world.get_viewport().get_canvas_transform().affine_inverse()*at
		return world.terrain.pick(pixel,operation.selected in [4,5])
	var hit: Dictionary=Plan.raycast(document().data,world.camera.project_ray_origin(at),world.camera.project_ray_normal(at),1000,operation.selected in [4,5])
	if hit["ok"]: hit["point"]=Vector2(hit["point"].x,hit["point"].z)
	return hit
func preview_circle(at: Vector2) -> PackedVector2Array:
	var points:=PackedVector2Array()
	if studio.tool!="terrain" or studio.walking or not Plan.settings(document().data)["enabled"]: return points
	var hit: Dictionary=point(at)
	if not hit["ok"]: return points
	var center: Vector2=hit["point"]; var world: Node=studio.worlds[studio.mode]
	for index in 49:
		var p: Vector2=center+Vector2.RIGHT.rotated(index*TAU/48)*radius.value; var height: float=Plan.sample(document().data,p,world.terrain_traversal.heights)["height"]
		if operation.selected in [4,5]:
			var level: Variant=Plan.water_level(document().data,p,world.terrain_traversal.heights,world.terrain_traversal.waters)
			if level!=null: height=maxf(height,level)
		points.append(world.get_viewport().get_canvas_transform()*Plan.project_2d(Vector3(p.x,height,p.y)) if studio.mode=="2d" else world.camera.unproject_position(Vector3(p.x,height,p.y)))
	return points
func protected_regions() -> Array[Rect2]:
	var data: Dictionary=document().data; var config: Dictionary=Plan.settings(data); var stamp: int=hash([data["objects"],data.get("roads",[]),config["protect_objects"],config["protect_roads"]])
	if stamp!=obstacles_stamp:
		obstacles_stamp=stamp; obstacles.clear()
		if config["protect_objects"]:
			for item in data["objects"]: obstacles.append(preload("res://scripts/builder/zone_plan.gd").footprint(item,studio.mode,studio.library))
		if config["protect_roads"]:
			for road in data.get("roads",[]):
				var center: Vector2=Traffic.center(Vector2i(road["cell"][0],road["cell"][1]),studio.mode); var half: float=float(road.get("width",6))*.5+(1 if road.get("sidewalks",true) else 0); obstacles.append(Rect2(center-Vector2.ONE*half,Vector2.ONE*half*2))
	var result: Array[Rect2]=obstacles.duplicate()
	if config["protect_actors"]:
		var actors: Array=[studio.worlds[studio.mode].player]
		for resident in studio.citizen_tools.managers[studio.mode].residents: actors.append(resident["actor"])
		for crew in studio.service_tools.managers[studio.mode].crews.values(): actors.append(crew["worker"])
		actors.append_array(studio.transit_tools.managers[studio.mode].pedestrian_actors())
		for actor in actors:
			if not is_instance_valid(actor) or not actor.visible: continue
			var p: Vector2=Traffic.metric([actor.position.x,actor.position.y,0] if studio.mode=="2d" else [actor.position.x,actor.position.y,actor.position.z],studio.mode); result.append(Rect2(p-Vector2.ONE*.8,Vector2.ONE*1.6))
		var vehicles: Array=studio.traffic_tools.managers[studio.mode].vehicles+studio.service_tools.managers[studio.mode].vehicle_states()+studio.transit_tools.managers[studio.mode].vehicle_states()
		for vehicle in vehicles:
			var extent: float=vehicle.get("half_length",1.5); result.append(Rect2(vehicle["point"]-Vector2.ONE*extent,Vector2.ONE*extent*2))
	return result
func dab(where: Vector2) -> void:
	var result: Dictionary=Plan.brush(document().data,Plan.OPERATIONS[operation.selected],where,radius.value,amount.value,target.value,protected_regions())
	if not result["ok"]: studio.status.text=result["reason"]; return
	if result["changed"]==0: return
	document().data=result["data"]; changed_count+=result["changed"]; studio.changed(); studio.workspace_layout.tabs.current_tab=panel.get_index()
func begin(where: Vector2) -> void:
	document().finish_checkpoint(); before=document().data.duplicate(true); changed_count=0; last=where; drawing=true; studio.stroke=true; dab(where)
func input(event: InputEvent) -> bool:
	if studio.tool!="terrain" or studio.walking: return false
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT and event.pressed: cancel(); return true
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			if not editable() or not Plan.settings(document().data)["enabled"]: return true
			var hit: Dictionary=point(event.position)
			if not hit["ok"]: studio.status.text=hit["reason"]; return true
			var focus: Control=studio.get_viewport().gui_get_focus_owner()
			if focus: focus.release_focus()
			begin(hit["point"])
		else: finish()
		return true
	if event is InputEventMouseMotion and drawing:
		var hit: Dictionary=point(event.position)
		if hit["ok"]:
			var destination: Vector2=hit["point"]; var count: int=mini(128,maxi(1,ceili(last.distance_to(destination)/maxf(.5,minf(1,radius.value*.5)))))
			for index in range(1,count+1): dab(last.lerp(destination,float(index)/count))
			last=destination
		return true
	return false
func finish() -> void:
	if not drawing: return
	drawing=false; studio.stroke=false; document().record_completed_change(before); before={}; studio.status.text="Terrain stroke · %d sample changes. Undo restores the whole stroke."%changed_count
func cancel() -> void:
	if not drawing: return
	drawing=false; studio.stroke=false; document().data=before; before={}; studio.changed(); studio.status.text="Terrain stroke cancelled."
func dab_center() -> void:
	if not editable() or not Plan.settings(document().data)["enabled"]: return
	studio.finish_edit(studio.canvas_pointer()); var hit: Dictionary=point(studio.canvas.size*.5)
	if not hit["ok"]: studio.status.text=hit["reason"]; return
	begin(hit["point"]); finish()
func tick(delta: float) -> void:
	if fields_mode!=studio.mode: fields_mode=studio.mode; fields_stamp=-1
	refresh(); elapsed+=delta
	if elapsed>=.4:
		elapsed=0; detail.text="%d sculpted vertices · %d water cells\n%s · radius %.1f"%[document().data.get("terrain_vertices",[]).size(),document().data.get("water_cells",[]).size(),operation.get_item_text(operation.selected),radius.value]
		if studio.mode=="2d":
			var unsupported: int=studio.worlds["2d"].terrain.family_warnings.size()
			if unsupported>0: detail.text+="\n%d unsupported terrain transitions."%unsupported
		else: detail.text+="\nConnected terrain artwork is available in the Pixel world."
func reset() -> void:
	cancel(); fields_stamp=-1; obstacles_stamp=0
