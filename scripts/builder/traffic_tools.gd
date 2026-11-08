extends RefCounted
const Plan=preload("res://scripts/builder/traffic_plan.gd")
const Runtime=preload("res://scripts/builder/traffic_runtime.gd")
var studio: Control
var panel: ScrollContainer
var enabled: CheckButton
var population: SpinBox
var seed: SpinBox
var speed: SpinBox
var dwell: SpinBox
var paused: CheckButton
var status: Label
var notices: Label
var selection: Label
var list: ItemList
var managers: Dictionary={}
var dirty: bool=true
var elapsed: float=0
var control_label: Label
var control_timing: VBoxContainer
var timing_fields: Dictionary={}
var binding_action: Button
var unbind_action: Button
var selection_stamp: int=0
var fleets: RefCounted

func _init(host: Control) -> void:
	studio=host
	panel=ScrollContainer.new(); panel.name="Traffic"; panel.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; panel.follow_focus=true; studio.workspace_layout.tabs.add_child(panel)
	var box:=VBoxContainer.new(); box.size_flags_horizontal=Control.SIZE_EXPAND_FILL; box.add_theme_constant_override("separation",8); panel.add_child(box)
	studio.label(box,"Signs and signals",17)
	control_label=studio.label(box,"Select a placed traffic sign or signal.",12)
	control_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	control_label.accessibility_name="Traffic control status"
	binding_action=button(box,"Bind to nearest road",bind_control)
	unbind_action=button(box,"Remove road binding",unbind_control)
	control_timing=VBoxContainer.new()
	box.add_child(control_timing)
	for pair in [["green","Green per direction (seconds)",3,45],["walk","Pedestrian walk (seconds)",3,45],["clear","All-red clearance (seconds)",1,8]]:
		var value: SpinBox=field(control_timing,pair[1],pair[2],pair[3],1)
		value.accessibility_name=pair[1]
		timing_fields[pair[0]]=value
	var instructions: Label=studio.label(box,"Face the artwork toward the incoming lane. For a one-way sign, use the arrow's direction. Signals share timings at the same junction. Copies can be bound at their new location.",12)
	instructions.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	fleets=preload("res://scripts/builder/fleet_tools.gd").new(studio)
	studio.label(box,"Moving traffic and parking",17)
	button(box,"Configure vehicle fleets",func():studio._command("vehicle_fleets",null))
	status=studio.label(box,"Traffic simulation is off.",12); status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	notices=studio.label(box,"",12); notices.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	enabled=CheckButton.new(); enabled.text="Enable traffic"; box.add_child(enabled)
	population=field(box,"Maximum vehicles",0,64,1)
	seed=field(box,"Journey seed",1,2147483647,1)
	speed=field(box,"Driving speed (units / second)",1,8,.5)
	dwell=field(box,"Parking stay (seconds)",2,120,1)
	button(box,"Apply traffic settings",apply_settings)
	paused=CheckButton.new(); paused.text="Pause traffic preview"; box.add_child(paused)
	paused.toggled.connect(func(value: bool):
		if managers.has(studio.mode): managers[studio.mode].paused=value)
	button(box,"Restart traffic preview",restart)
	studio.label(box,"Parking spaces",14)
	button(box,"Add parking near view center",add_parking)
	selection=studio.label(box,"",12); selection.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	button(box,"Mark selection as parking spaces",func(): mark_parking(true))
	button(box,"Remove selected parking spaces",func(): mark_parking(false))
	var help: Label=studio.label(box,"Draw connected roads with Road tools. Vehicles use right-hand lanes, all-way stops at intersections, timed pedestrian crossings and yielding to nearby walkers. Add parking near the view center to create a selectable surface beside the nearest straight road. Move it with Select / move if needed. You can also mark selected ground objects: each supplies one bay at its center, away from crossings and junctions. Leave its driveway clear. Road edits retain vehicles. Cars reroute from reachable lanes and wait when the road beneath them is lost. Positions, parking occupancy and preview time are temporary.",12)
	help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	list=ItemList.new(); list.custom_minimum_size=Vector2(180,160); box.add_child(list)
	button(box,"Locate selected vehicle",locate)
	studio.get_viewport().gui_focus_changed.connect(reveal_control)
	panel.resized.connect(func(): reveal_control(studio.get_viewport().gui_get_focus_owner()))

func reveal_control(control: Control) -> void:
	if not is_instance_valid(control) or not panel.is_ancestor_of(control): return
	for frame in 2: await studio.get_tree().process_frame
	if not is_instance_valid(control) or not control.has_focus() or not panel.is_visible_in_tree() or not panel.is_ancestor_of(control): return
	panel.ensure_control_visible(control)
	var outer: ScrollContainer=studio.accessibility_settings.root_scroll
	if is_instance_valid(outer) and outer.is_ancestor_of(control): outer.ensure_control_visible(control)

func field(parent: Node,title: String,low: float,high: float,step: float) -> SpinBox:
	studio.label(parent,title,12); return studio.spin(parent,low,high,step,low)

func button(parent: Node,title: String,callback: Callable) -> Button:
	var control:=Button.new(); control.text=title; control.clip_text=true; control.tooltip_text=title; control.accessibility_name=title; parent.add_child(control); control.pressed.connect(callback)
	return control

func start() -> void:
	for mode in ["2d","3d"]:
		var manager:=Runtime.new(); manager.name="Traffic"; studio.worlds[mode].add_child(manager); managers[mode]=manager
		manager.driving=studio.worlds[mode].exploration.driving; manager.driving.traffic=manager
		studio.citizen_tools.managers[mode].street_traffic=manager
	refresh_fields()

func refresh_fields() -> void:
	if studio.documents.is_empty(): return
	var config: Dictionary=Plan.settings(studio.current().data)
	enabled.set_pressed_no_signal(config["enabled"]); population.set_value_no_signal(config["population"]); seed.set_value_no_signal(config["seed"]); speed.set_value_no_signal(config["speed"]); dwell.set_value_no_signal(config["parking_seconds"])
	paused.set_pressed_no_signal(managers[studio.mode].paused if managers.has(studio.mode) else false)
	refresh_control()

func show() -> void:
	studio.workspace_presets.set_focus(false)
	if studio.walking: studio.set_walking(false)
	studio.workspace_layout.inspector_toggle.button_pressed=true; studio.workspace_layout.tabs.current_tab=panel.get_index(); refresh_fields()

func control_item() -> Dictionary:
	if studio.interior_tools.editing():
		return {}
	var selected: Array=studio.selection_items()
	return selected[0] if selected.size()==1 and not Plan.Signals.profile(selected[0]["asset"]).is_empty() else {}

func refresh_control() -> void:
	var item: Dictionary=control_item()
	var binding: Dictionary=item.get("traffic_control",{})
	var kind: String=Plan.Signals.profile(item.get("asset","")).get("kind","")
	var next: int=hash([studio.mode,item.get("uid",""),binding])
	if selection_stamp!=next:
		selection_stamp=next
		var timing: Dictionary=binding.get("timing",Plan.Signals.DEFAULT_TIMING)
		for key in timing_fields:
			timing_fields[key].set_value_no_signal(timing[key])
	binding_action.disabled=item.is_empty()
	unbind_action.disabled=binding.is_empty()
	control_timing.visible=kind=="signal"
	if item.is_empty():
		control_label.text="Select a placed traffic sign or signal in the exterior city."
		return
	if binding.is_empty():
		control_label.text="%s · no road binding"%kind.replace("_"," ").capitalize()
		return
	var manager: Node=managers.get(studio.mode)
	var issues: Dictionary=manager.plan.get("controls",{}).get("issues",{}) if manager else {}
	var issue: String=issues.get(item["uid"],"")
	control_label.text="%s at road %d, %d"%[kind.replace("_"," ").capitalize(),binding["cell"][0],binding["cell"][1]]
	if not issue.is_empty():
		control_label.text+=" · "+issue
	elif manager and kind=="signal" and manager.signal_views.heads.has(item["uid"]):
		var head: Dictionary=manager.signal_views.heads[item["uid"]]
		var phase: String=manager.gates.phase(manager.plan,Plan.Roads.key(Plan.Signals.road_cell(binding)),manager.junction_time)
		control_label.text+=" · "+("Pedestrian walk" if phase=="walk" else "All-red clearance" if phase=="red" else head["color"].capitalize())

func bind_control() -> void:
	var item: Dictionary=control_item()
	if item.is_empty(): return
	studio.finish_edit(studio.canvas_pointer())
	var doc: RefCounted=studio.current()
	var data: Dictionary=doc.data
	var network: Dictionary=Plan.build(data)
	var timing: Dictionary={}
	for key in timing_fields:
		timing[key]=timing_fields[key].value
	var proposal: Dictionary=Plan.Signals.nearest(item,network["sections"],studio.mode,Plan.metric(item["position"],studio.mode),timing)
	if not proposal.has("binding"):
		studio.status.text=proposal["reason"]
		return
	var binding: Dictionary=proposal["binding"]
	var candidate: Dictionary=data.duplicate(true)
	for sign in candidate["objects"]:
		var old: Dictionary=sign.get("traffic_control",{})
		if sign["uid"]==item["uid"]:
			sign["traffic_control"]=binding
		elif binding["kind"]=="signal" and old.get("kind","")=="signal" and Plan.Signals.road_cell(old)==Plan.Signals.road_cell(binding) and old["timing"]!=timing:
			if not studio.Layers.editable(data,sign,studio.library):
				studio.status.text="Unlock every signal at this junction before changing its timings."
				return
			sign["traffic_control"]["timing"]=timing.duplicate()
	var reviewed: Dictionary=Plan.build(candidate)["controls"]
	if reviewed["issues"].has(item["uid"]):
		studio.status.text=reviewed["issues"][item["uid"]]
		return
	if candidate==data:
		studio.status.text="The road binding and timings are unchanged."
		return
	doc.checkpoint()
	doc.data=candidate
	studio.changed()
	doc.finish_checkpoint()
	refresh_control()
	studio.status.text="Traffic control bound. Undo restores the previous setup."

func unbind_control() -> void:
	var item: Dictionary=control_item()
	if not item.has("traffic_control"): return
	studio.finish_edit(studio.canvas_pointer())
	var doc: RefCounted=studio.current()
	doc.checkpoint()
	item.erase("traffic_control")
	studio.changed()
	doc.finish_checkpoint()
	refresh_control()
	studio.status.text="Road binding removed. The sign or signal stays in place."

func apply_settings() -> void:
	if studio.interior_tools.editing(): studio.status.text="Configure traffic from the exterior city editor."; return
	studio.finish_edit(studio.canvas_pointer())
	var config: Dictionary={"enabled":enabled.button_pressed,"population":int(population.value),"seed":int(seed.value),"speed":speed.value,"parking_seconds":dwell.value}
	if config==Plan.settings(studio.current().data): studio.status.text="Traffic settings are unchanged."; return
	studio.current().checkpoint()
	var values: Dictionary=studio.current().data.get("traffic",{}).duplicate(true); values.merge(config,true); studio.current().data["traffic"]=values
	studio.changed(); dirty=true; studio.status.text="Traffic settings applied. Undo restores the previous settings."

func mark_parking(value: bool) -> void:
	if studio.interior_tools.editing(): studio.status.text="Mark parking in the exterior city editor."; return
	studio.finish_edit(studio.canvas_pointer())
	var items: Array=studio.selection_items().filter(func(item: Dictionary):return item.get("traffic_parking",false)!=value and (not value or Plan.parking_surface(item,studio.library)))
	if items.is_empty(): studio.status.text="Select editable ground surfaces whose parking designation should change."; return
	studio.current().checkpoint()
	for item in items:
		if value: item["traffic_parking"]=true
		else: item.erase("traffic_parking")
	studio.changed(); dirty=true; studio.status.text="Parking designation updated for %d objects. Nearby straight roads are required." % items.size()

func add_parking() -> void:
	if studio.interior_tools.editing(): studio.status.text="Add parking in the exterior city editor."; return
	if not preload("res://scripts/builder/layers.gd").shown(studio.current().data,"Ground") or preload("res://scripts/builder/layers.gd").locked(studio.current().data,"Ground"):
		studio.status.text="Show and unlock Ground before adding a parking surface."; return
	studio.finish_edit(studio.canvas_pointer())
	var mode: String=studio.mode; var world: Node=studio.worlds[mode]
	var location: Variant=world.camera.position if mode=="2d" else world.target
	var center: Vector2=Plan.metric([location.x,location.y,0] if mode=="2d" else [location.x,location.y,location.z],mode)
	var network: Dictionary=Plan.build(studio.current().data)
	var nearest: float=INF; var point:=Vector2.ZERO; var found: bool=false
	for edge in network["edges"].values():
		var section: Dictionary=network["sections"][edge["to"]]
		if section["neighbors"].size()!=2 or section["crossing"]: continue
		var a: Vector2i=network["sections"][section["neighbors"][0]]["cell"]-section["cell"]
		var b: Vector2i=network["sections"][section["neighbors"][1]]["cell"]-section["cell"]
		if a+b!=Vector2i.ZERO: continue
		var axis: Vector2=edge["axis"]
		var candidate: Vector2=Plan.center(section["cell"],mode)+Vector2(-axis.y,axis.x)*(section["width"]*.5+2.5)
		if managers[mode].bays.values().any(func(bay: Dictionary):return bay["point"].distance_to(candidate)<3): continue
		if candidate.distance_to(center)>=nearest: continue
		nearest=candidate.distance_to(center); point=candidate; found=true
	if not found: studio.status.text="Draw a straight road with at least three connected sections before adding parking."; return
	var asset: String="2d:Parking_Accessible" if mode=="2d" else "3d:HanX_Traffic/Road_Parking"
	var size: float=2 if mode=="2d" else .5
	var direction: String="SE" if mode=="2d" else "0"
	var correction: Vector2=preload("res://scripts/builder/roads.gd").center_offset(studio.library,asset,direction,size,mode)*(2 if mode=="2d" else 1)
	studio.current().checkpoint()
	var item: Dictionary=studio.current().add(asset,Plan.world(point-correction,mode),direction,size)
	item["traffic_parking"]=true; item["name"]="Parking space"
	studio.selected_uids.assign([item["uid"]]); studio.selected_uid=item["uid"]; studio.set_tool("select"); studio.changed(); dirty=true
	studio.status.text="Added a parking surface beside the nearest straight road. Select / move adjusts its position."

func restart() -> void:
	if managers.has(studio.mode): managers[studio.mode].restart_vehicles(); dirty=true

func reset() -> void:
	for manager in managers.values(): manager.reset()
	dirty=true

func tick(delta: float) -> void:
	if managers.is_empty(): return
	fleets.tick()
	for mode in managers:
		var manager: Node=managers[mode]
		manager.active=not studio.terrain_tools.drawing and mode==studio.mode and not studio.modal_visible() and not studio.interior_tools.editing() and studio.worlds[mode].exploration.interior==null
		if is_instance_valid(manager.container): manager.container.visible=mode==studio.mode and not studio.interior_tools.editing() and studio.worlds[mode].exploration.interior==null
		manager.pedestrians.assign([studio.worlds[mode].player])
		for resident in studio.citizen_tools.managers[mode].residents:
			if is_instance_valid(resident["actor"]): manager.pedestrians.append(resident["actor"])
	if dirty and not studio.interior_tools.editing() and studio.worlds[studio.mode].exploration.interior==null and not studio.stroke and not studio.ground_brush.drawing and not studio.transform_handles.dragging:
		managers[studio.mode].configure(studio.current().data,studio.library,studio.worlds[studio.mode].instances,studio.worlds[studio.mode].objects); dirty=false; refresh_fields()
	elapsed+=delta
	if elapsed<.4: return
	elapsed=0
	var manager: Node=managers[studio.mode]
	refresh_control()
	status.text=manager.summary(); notices.text="\n".join(manager.plan.get("notices",[]))
	var marked: int=studio.current().data["objects"].filter(func(item: Dictionary):return item.get("traffic_parking",false)).size()
	selection.text="%d marked objects · %d usable bays\n%d editable objects selected" % [marked,manager.bays.size(),studio.selection_items().size()]
	var selected: PackedInt32Array=list.get_selected_items(); var index: int=selected[0] if not selected.is_empty() else -1
	list.clear()
	for vehicle in manager.vehicles:
		list.add_item(vehicle["id"]+" · "+vehicle["status"]); list.set_item_tooltip(list.item_count-1,vehicle["status"])
	if index>=0 and index<list.item_count: list.select(index)

func locate() -> void:
	var selected: PackedInt32Array=list.get_selected_items()
	if selected.is_empty() or selected[0]>=managers[studio.mode].vehicles.size(): return
	var actor: Node=managers[studio.mode].vehicles[selected[0]]["actor"]
	if studio.mode=="2d": studio.worlds["2d"].camera.position=actor.position
	else: studio.worlds["3d"].target=actor.position; studio.worlds["3d"].update_camera()
