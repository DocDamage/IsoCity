extends RefCounted
const Plan=preload("res://scripts/builder/zone_plan.gd")
const Runtime=preload("res://scripts/builder/zone_runtime.gd")
var studio: Control
var panel: ScrollContainer
var enabled: CheckButton
var seconds: SpinBox
var seed: SpinBox
var paused: CheckButton
var kind: OptionButton
var theme_choice: OptionButton
var density: OptionButton
var max_price: SpinBox
var theme_note: Label
var name_input: LineEdit
var x_input: SpinBox
var y_input: SpinBox
var width: SpinBox
var depth: SpinBox
var shown: CheckButton
var locked: CheckButton
var lots: ItemList
var detail: Label
var managers: Dictionary={}
var selected: String=""
var dirty: bool=true
var fields_stamp: int=0
var fields_mode: String=""
var settings_stamp: int=-1
var drawing: bool=false
var start_point: Vector2
var end_point: Vector2
var preview: Node
var elapsed: float=0
func _init(host: Control) -> void:
	studio=host; panel=ScrollContainer.new(); panel.name="Zoning"; panel.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; panel.follow_focus=true; studio.workspace_layout.tabs.add_child(panel)
	var box:=VBoxContainer.new(); box.size_flags_horizontal=Control.SIZE_EXPAND_FILL; box.add_theme_constant_override("separation",8); panel.add_child(box)
	studio.label(box,"Zoning and development",17)
	enabled=CheckButton.new(); enabled.text="Enable gradual development"; box.add_child(enabled)
	seconds=field(box,"Seconds per development stage",2,300,1); seed=field(box,"Development seed",1,2147483647,1)
	button(box,"Apply growth settings",apply_settings)
	paused=CheckButton.new(); paused.text="Pause growth preview"; box.add_child(paused); paused.toggled.connect(func(value: bool): managers[studio.mode].paused=value)
	button(box,"Draw lots on the canvas",draw_mode)
	kind=OptionButton.new(); kind.fit_to_longest_item=false; kind.clip_text=true; box.add_child(kind)
	for id in Plan.definitions(): kind.add_item(Plan.definitions()[id]["label"]); kind.set_item_metadata(kind.item_count-1,id)
	studio.label(box,"Building theme",12);theme_choice=OptionButton.new();theme_choice.fit_to_longest_item=false;theme_choice.clip_text=true;theme_choice.accessibility_name="Zoning building theme";box.add_child(theme_choice)
	for key in ["native","any","pixel_city","hanx_modern","village","historical","industrial","korean_street"]:
		theme_choice.add_item(Plan.Candidates.definitions()["themes"][key]["label"]);theme_choice.set_item_metadata(theme_choice.item_count-1,key)
	theme_note=studio.label(box,"",12);theme_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;theme_choice.item_selected.connect(func(_at: int):refresh_theme_note());refresh_theme_note()
	studio.label(box,"Building density",12);density=OptionButton.new();density.accessibility_name="Zoning building density";density.fit_to_longest_item=false;density.clip_text=true;box.add_child(density)
	for key in Plan.Candidates.DENSITIES:density.add_item("Any density" if key=="any" else key.capitalize());density.set_item_metadata(density.item_count-1,key)
	max_price=field(box,"Maximum building price · 0 means no cap",0,1000000000,100)
	name_input=LineEdit.new(); name_input.placeholder_text="Lot name"; box.add_child(name_input)
	x_input=field(box,"Lot center · ground X",-100000,100000,1); y_input=field(box,"Lot center · ground Z",-100000,100000,1)
	width=field(box,"Lot width",4,64,2); depth=field(box,"Lot depth",4,64,2); width.value=48; depth.value=48
	button(box,"Add lot near view center",add_center)
	button(box,"Apply fields to selected lot",apply_lot)
	lots=ItemList.new(); lots.custom_minimum_size=Vector2(180,170); box.add_child(lots); lots.item_selected.connect(func(index: int): selected=lots.get_item_metadata(index); fields_stamp=0; refresh_lot())
	shown=CheckButton.new(); shown.text="Show selected lot"; box.add_child(shown); shown.toggled.connect(func(value: bool): set_flag("visible",value))
	locked=CheckButton.new(); locked.text="Lock selected lot"; box.add_child(locked); locked.toggled.connect(func(value: bool): set_flag("locked",value))
	button(box,"Locate selected lot",locate)
	button(box,"Advance selected lot one stage",advance_selected)
	button(box,"Restart selected construction plan",restart_lot)
	button(box,"Remove lot (keep its building)",remove_lot)
	detail=studio.label(box,"Draw or add a lot to begin.",12); detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var help: Label=studio.label(box,"Drag a rectangle on the ground, or add a lot near the view center and edit its center and size. Lots cannot overlap and must be 4–64 ground units wide and deep. Connected roads must be within 12 units of a lot edge. Commercial lots need one nearby home, and civic lots need two. Parks and civic amenities accelerate housing. Large civic sprites need larger lots. Development shows foundation, framing and finishing scenery before creating an editable building. The full building price is charged at completion. Growth waits for obstructions and people to clear the footprint. Hiding or locking lots and protected Buildings suspend growth. Changing lot fields restarts its plan and keeps any finished building. Remove the building normally to clear an occupied lot. Save retains stages, and partial preview clocks restart on load. Authored changes and growth transitions support Undo.",12); help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
func chosen_filters() -> Dictionary:return {"theme":theme_choice.get_item_metadata(theme_choice.selected),"density":density.get_item_metadata(density.selected),"max_price":int(max_price.value)}
func refresh_theme_note() -> void:
	if theme_choice.selected<0:return
	var note: String=Plan.Candidates.definitions()["themes"][theme_choice.get_item_metadata(theme_choice.selected)]["note"];theme_note.text=note;theme_choice.tooltip_text=note
func field(parent: Node,title: String,low: float,high: float,step: float) -> SpinBox:
	var caption: Label=studio.label(parent,title,12);caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	return studio.spin(parent,low,high,step,low)
func button(parent: Node,title: String,callback: Callable) -> void:
	var control:=Button.new(); control.text=title; control.clip_text=true; parent.add_child(control); control.pressed.connect(callback)
func start() -> void:
	for mode in ["2d","3d"]:
		var manager:=Runtime.new(); studio.worlds[mode].add_child(manager); managers[mode]=manager; manager.advance_requested.connect(func(uid: String): advance(uid,mode))
	refresh_settings()
func show() -> void:
	studio.workspace_presets.set_focus(false)
	if studio.walking: studio.set_walking(false)
	studio.workspace_layout.inspector_toggle.button_pressed=true; studio.workspace_layout.tabs.current_tab=panel.get_index(); refresh_settings(); refresh()
func root_document(mode: String="") -> RefCounted: return studio.interior_tools.root_document(studio.mode if mode.is_empty() else mode)
func refresh_settings() -> void:
	if not studio.documents.has(studio.mode): return
	var config: Dictionary=Plan.settings(root_document().data)
	settings_stamp=hash(config)
	enabled.set_pressed_no_signal(config["enabled"]); seconds.set_value_no_signal(config["stage_seconds"]); seed.set_value_no_signal(config["seed"])
	paused.set_pressed_no_signal(managers[studio.mode].paused if managers.has(studio.mode) else false)
func editable() -> bool:
	if studio.interior_tools.editing(): studio.status.text="Edit zoning from the exterior city."; return false
	if not Plan.Layers.shown(root_document().data,"Buildings") or Plan.Layers.locked(root_document().data,"Buildings"): studio.status.text="Show and unlock Buildings to edit lots."; return false
	return true
func lot() -> Dictionary:
	for item in root_document().data.get("zones",[]):
		if item["uid"]==selected: return item
	return {}
func commit(before: Dictionary) -> void:
	root_document().record_completed_change(before); studio.changed(); dirty=true; refresh()
func apply_settings() -> void:
	if studio.interior_tools.editing(): return
	studio.finish_edit(studio.canvas_pointer()); var doc: RefCounted=root_document(); doc.finish_checkpoint()
	var value: Dictionary={"enabled":enabled.button_pressed,"stage_seconds":seconds.value,"seed":int(seed.value)}
	if value==Plan.settings(doc.data): return
	var before: Dictionary=doc.data.duplicate(true); var config: Dictionary=doc.data.get("zoning",{}).duplicate(true); config.merge(value,true); doc.data["zoning"]=config; commit(before)
func draw_mode() -> void:
	if not editable(): return
	studio.finish_edit(studio.canvas_pointer()); studio.set_walking(false); studio.set_tool("zone"); studio.clear_assembly(); studio.status.text="Zoning · drag a ground rectangle; right-click cancels."
	studio.control_settings.refresh_mode_hint()
func point(at: Vector2) -> Vector2: return Plan.Traffic.metric(studio.worlds[studio.mode].point(at,false,0),studio.mode).snapped(Vector2.ONE)
func drawn_rect() -> Rect2: return Rect2(start_point,end_point-start_point).abs()
func input(event: InputEvent) -> bool:
	if studio.tool!="zone" or studio.walking: return false
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT and event.pressed: cancel_draw(); return true
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			if not editable(): return true
			var focus: Control=studio.get_viewport().gui_get_focus_owner()
			if focus: focus.release_focus()
			start_point=point(event.position); end_point=start_point; drawing=true; studio.stroke=true; update_preview()
		else: finish_draw(event.position)
		return true
	if event is InputEventMouseMotion and drawing: end_point=point(event.position); update_preview(); return true
	return false
func cancel_draw() -> void:
	drawing=false; studio.stroke=false
	if is_instance_valid(preview): preview.free()
	preview=null
func update_preview() -> void:
	if is_instance_valid(preview): preview.free()
	var bounds: Rect2=drawn_rect()
	if bounds.size.x<.01 or bounds.size.y<.01: return
	var manager: Node=managers[studio.mode]
	if not is_instance_valid(manager.container): manager.configure(root_document().data,studio.library,studio.worlds[studio.mode].objects)
	if not is_instance_valid(manager.container):
		manager.data=root_document().data; manager.library=studio.library; manager.container=Node2D.new() if studio.mode=="2d" else Node3D.new(); studio.worlds[studio.mode].objects.add_child(manager.container)
	preview=manager.make_visual({"uid":"preview","kind":kind.get_item_metadata(kind.selected),"rect":[bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y],"stage":0})
func finish_draw(at: Vector2) -> void:
	if not drawing: return
	end_point=point(at); var bounds: Rect2=drawn_rect(); cancel_draw(); add_rect(bounds)
func add_center() -> void:
	if not editable(): return
	studio.finish_edit(studio.canvas_pointer()); var center: Vector2=point(studio.canvas.size*.5)
	add_rect(Rect2(center-Vector2(width.value,depth.value)*.5,Vector2(width.value,depth.value)))
func add_rect(bounds: Rect2) -> void:
	if not editable(): return
	var doc: RefCounted=root_document(); doc.finish_checkpoint()
	var item: Dictionary={"uid":"lot_"+str(Time.get_ticks_usec())+"_"+str(randi()),"kind":kind.get_item_metadata(kind.selected),"rect":[bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y],"stage":0}
	item.merge(chosen_filters(),true)
	if not name_input.text.strip_edges().is_empty(): item["name"]=name_input.text.strip_edges()
	var proposed: Array=doc.data.get("zones",[]).duplicate(true)+[item]
	if not Plan.valid_lots(proposed,studio.mode,studio.library): studio.status.text="Cannot add lot: use a nonoverlapping rectangle 4–64 units wide and deep (maximum 128 lots)."; return
	var before: Dictionary=doc.data.duplicate(true); doc.data["zones"]=proposed; selected=item["uid"]; fields_stamp=0; commit(before); studio.status.text="Designated "+Plan.definitions()[item["kind"]]["label"]+" lot."
func apply_lot() -> void:
	if not editable() or lot().is_empty(): return
	if lot().get("locked",false): studio.status.text="Unlock the selected lot before changing its fields."; return
	studio.finish_edit(studio.canvas_pointer()); var doc: RefCounted=root_document(); doc.finish_checkpoint(); var before: Dictionary=doc.data.duplicate(true)
	var item: Dictionary=lot();var bounds:=Rect2(x_input.value-width.value*.5,y_input.value-depth.value*.5,width.value,depth.value)
	var restart: bool=item["kind"]!=kind.get_item_metadata(kind.selected) or Plan.rectangle(item)!=bounds or Plan.Candidates.options(item)!=chosen_filters()
	item.merge({"kind":kind.get_item_metadata(kind.selected),"rect":[bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y],"name":name_input.text},true);item.merge(chosen_filters(),true)
	if restart:item["stage"]=0;item.erase("proposal");item.erase("selection")
	if item==before.get("zones",[]).filter(func(entry: Dictionary):return entry["uid"]==selected)[0]:studio.status.text="Lot fields are unchanged.";return
	if not Plan.valid_lots(doc.data["zones"],studio.mode,studio.library): doc.data=before; studio.status.text="Lot fields would overlap another lot or exceed supported bounds."; return
	commit(before); studio.status.text="Lot fields applied; existing buildings were retained."
func set_flag(flag: String,value: bool) -> void:
	if not editable() or lot().is_empty(): return
	var doc: RefCounted=root_document(); doc.finish_checkpoint(); var before: Dictionary=doc.data.duplicate(true); lot()[flag]=value; commit(before)
func locate() -> void:
	if lot().is_empty(): return
	var point: Array=Plan.Traffic.world(Plan.rectangle(lot()).get_center(),studio.mode)
	if studio.mode=="2d": studio.worlds[studio.mode].camera.position=Vector2(point[0],point[1])
	else: studio.worlds[studio.mode].target=Vector3(point[0],0,point[2]); studio.worlds[studio.mode].update_camera()
func occupied(mode: String) -> Array[Vector2]:
	var result: Array[Vector2]=[]; var actors: Array=[]
	if studio.walking and mode==studio.mode: actors.append(studio.worlds[mode].player)
	for resident in studio.citizen_tools.managers[mode].residents:
		if is_instance_valid(resident["actor"]) and resident["actor"].visible: actors.append(resident["actor"])
	for crew in studio.service_tools.managers[mode].crews.values():
		if is_instance_valid(crew["worker"]) and crew["worker"].visible: actors.append(crew["worker"])
	for actor in actors:
		var point: Vector2=Plan.Traffic.metric([actor.position.x,actor.position.y,0] if mode=="2d" else [actor.position.x,actor.position.y,actor.position.z],mode)
		var terrain=preload("res://scripts/builder/terrain_plan.gd"); var level: float=terrain.sample(root_document(mode).data,point,studio.worlds[mode].terrain_traversal.heights)["height"] if terrain.settings(root_document(mode).data)["enabled"] else 0.0
		if mode=="3d" and absf(actor.position.y-level)>.5: continue
		result.append(point)
	result.append_array(Plan.vehicle_points(studio.traffic_tools.managers[mode].vehicles))
	if studio.transit_tools:
		var transit: Node=studio.transit_tools.managers[mode]
		result.append_array(Plan.vehicle_points(transit.vehicle_states()))
		for actor in transit.pedestrian_actors():
			result.append(Plan.Traffic.metric([actor.position.x,actor.position.y,0] if mode=="2d" else [actor.position.x,actor.position.y,actor.position.z],mode))
	result.append_array(Plan.vehicle_points(studio.service_tools.managers[mode].crews.values().map(func(crew: Dictionary):return crew["vehicle"])))
	return result
func advance_selected() -> void:
	if not editable() or lot().is_empty(): return
	studio.finish_edit(studio.canvas_pointer()); advance(selected,studio.mode)
func advance(uid: String,mode: String) -> void:
	if mode!=studio.mode or studio.interior_tools.editing() or studio.worlds[mode].exploration.interior!=null or studio.modal_visible() or studio.stroke or studio.road_drawing or studio.ground_brush.drawing or studio.transform_handles.dragging: return
	var doc: RefCounted=root_document(mode); doc.finish_checkpoint(); var value: Dictionary=Plan.advance(doc.data,uid,studio.library,"",occupied(mode))
	if not value["ok"] or not value.has("data"):
		managers[mode].states[uid]=value; studio.status.text=value["reason"]; return
	var before: Dictionary=doc.data.duplicate(true); doc.data=value["data"]; commit(before); studio.status.text="Lot development · "+value["reason"]
func restart_lot() -> void:
	if not editable() or lot().is_empty() or lot().get("locked",false): return
	var doc: RefCounted=root_document(); doc.finish_checkpoint(); var before: Dictionary=doc.data.duplicate(true); lot()["stage"]=0; lot().erase("proposal");lot().erase("selection"); commit(before)
func remove_lot() -> void:
	if not editable() or lot().is_empty() or lot().get("locked",false): return
	studio.finish_edit(studio.canvas_pointer()); var doc: RefCounted=root_document(); doc.finish_checkpoint(); var before: Dictionary=doc.data.duplicate(true)
	doc.data["zones"].erase(lot())
	selected=""; commit(before)
func refresh_lot() -> void:
	var item: Dictionary=lot()
	if item.is_empty(): return
	var stamp: int=hash([studio.mode,item.get("name",""),item["kind"],item["rect"],item.get("visible",true),item.get("locked",false),Plan.Candidates.options(item)])
	if stamp==fields_stamp: return
	fields_stamp=stamp; var bounds: Rect2=Plan.rectangle(item); x_input.set_value_no_signal(bounds.get_center().x); y_input.set_value_no_signal(bounds.get_center().y); width.set_value_no_signal(bounds.size.x); depth.set_value_no_signal(bounds.size.y); name_input.text=item.get("name","")
	for index in kind.item_count:
		if kind.get_item_metadata(index)==item["kind"]: kind.select(index)
	var options: Dictionary=Plan.Candidates.options(item)
	for index in theme_choice.item_count:
		if theme_choice.get_item_metadata(index)==options["theme"]:theme_choice.select(index)
	for index in density.item_count:
		if density.get_item_metadata(index)==options["density"]:density.select(index)
	max_price.set_value_no_signal(options["max_price"]);refresh_theme_note()
	shown.set_pressed_no_signal(item.get("visible",true)); locked.set_pressed_no_signal(item.get("locked",false))
func refresh() -> void:
	if managers.is_empty(): return
	lots.clear(); var manager: Node=managers[studio.mode]
	for item in root_document().data.get("zones",[]):
		lots.add_item(item.get("name",Plan.definitions()[item["kind"]]["label"])+" · "+Plan.stage_name(item)); lots.set_item_metadata(lots.item_count-1,item["uid"])
		if item["uid"]==selected: lots.select(lots.item_count-1)
	refresh_lot()
	var state: Dictionary=manager.states.get(selected,{})
	detail.text=state.get("reason","Select a lot. Growth checks run incrementally.")
	var candidate: Dictionary=lot().get("proposal",state.get("proposal",{}))
	if not candidate.is_empty():
		detail.text+="\nBuilding: "+studio.library.assets.get(candidate["asset"],{}).get("name",candidate["asset"])+" · %d credits at completion"%Plan.Economy.profile(candidate["asset"],studio.library)["construction"]
		var source: Dictionary=lot().get("selection",state.get("selection",{}))
		if source.get("representation")=="flat_sprite_in_3d":detail.text+="\nSupplied flat artwork in 3D; no added model depth."
		if source.get("revision",Plan.Candidates.definitions()["revision"])!=Plan.Candidates.definitions()["revision"]:detail.text+="\nSaved earlier-catalog selection retained. Restart only to choose again."
		if state.get("eligible_families",0)>0:detail.text+="\n%d eligible designs · appearance is chosen within its design."%state["eligible_families"]
	if not lot().is_empty(): detail.text+="\nStage progress: %.1f / %.1f seconds" % [manager.timers.get(selected,0),Plan.settings(root_document().data)["stage_seconds"]]
	var visual: Node=manager.visuals.get(selected)
	if is_instance_valid(visual) and visual.get_meta("stage_scenery_missing",false):
		detail.text+="\nSome construction scenery is unavailable. Restore HanX Construction to show all pieces."
func tick(delta: float) -> void:
	if managers.is_empty(): return
	for mode in managers:
		var manager: Node=managers[mode]
		manager.set_text_scale(studio.accessibility_settings.text_scale)
		manager.active=studio.shared_authority() and mode==studio.mode and not studio.modal_visible() and not studio.interior_tools.editing() and studio.worlds[mode].exploration.interior==null and not studio.stroke and not studio.road_drawing and not studio.ground_brush.drawing and not studio.transform_handles.dragging and not drawing
		if manager.active and Plan.settings(root_document(mode).data)["enabled"] and not root_document(mode).data.get("zones",[]).is_empty(): manager.people=occupied(mode)
		else: manager.people.clear()
		if is_instance_valid(manager.container): manager.container.visible=mode==studio.mode and not studio.interior_tools.editing() and studio.worlds[mode].exploration.interior==null and Plan.Layers.shown(root_document(mode).data,"Buildings") and Plan.Layers.shown(root_document(mode).data,"Ground")
	if fields_mode!=studio.mode: fields_mode=studio.mode; fields_stamp=0; selected=""; refresh_settings(); dirty=true
	if settings_stamp!=hash(Plan.settings(root_document().data)): refresh_settings()
	if dirty and not studio.interior_tools.editing() and studio.worlds[studio.mode].exploration.interior==null and not studio.stroke and not studio.road_drawing and not studio.ground_brush.drawing and not drawing:
		managers[studio.mode].configure(root_document().data,studio.library,studio.worlds[studio.mode].objects); dirty=false
	elapsed+=delta
	if elapsed>=.4: elapsed=0; refresh()
func reset() -> void:
	cancel_draw()
	for manager in managers.values(): manager.reset(); manager.paused=false
	selected=""; fields_stamp=0; fields_mode=""; settings_stamp=-1; dirty=true
