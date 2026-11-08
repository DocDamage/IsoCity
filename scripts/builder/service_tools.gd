extends RefCounted
const Plan=preload("res://scripts/builder/service_plan.gd")
const Runtime=preload("res://scripts/builder/service_runtime.gd")
var studio: Control
var panel: ScrollContainer
var enabled: CheckButton
var automatic: CheckButton
var interval: SpinBox
var seed: SpinBox
var paused: CheckButton
var kind: OptionButton
var radius: SpinBox
var units: SpinBox
var duration: SpinBox
var request_kind: OptionButton
var context: Label
var status: Label
var coverage: Label
var targets: ItemList
var jobs: ItemList
var managers: Dictionary={}
var dirty: bool=true
var selection_signature: int=-1
var elapsed: float=0
var coverage_result: Dictionary={}

func _init(host: Control) -> void:
	studio=host
	panel=ScrollContainer.new(); panel.name="City services"; panel.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; panel.follow_focus=true; studio.workspace_layout.tabs.add_child(panel)
	var box:=VBoxContainer.new(); box.size_flags_horizontal=Control.SIZE_EXPAND_FILL; box.add_theme_constant_override("separation",8); panel.add_child(box)
	studio.label(box,"City services and crews",17)
	status=studio.label(box,"Services are off.",12); status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	enabled=CheckButton.new(); enabled.text="Enable city services"; box.add_child(enabled)
	automatic=CheckButton.new(); automatic.text="Automatic neighborhood visits"; box.add_child(automatic)
	interval=field(box,"Automatic visit interval (seconds)",5,600,1); seed=field(box,"Dispatch seed",1,2147483647,1)
	button(box,"Apply service settings",apply_settings)
	paused=CheckButton.new(); paused.text="Pause service preview"; box.add_child(paused); paused.toggled.connect(func(value: bool): managers[studio.mode].paused=value)
	button(box,"Restart service preview",func(): managers[studio.mode].reset(); dirty=true)
	studio.label(box,"Station settings for selection",14)
	context=studio.label(box,"",12); context.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	kind=OptionButton.new(); kind.fit_to_longest_item=false; kind.clip_text=true
	for title in ["Catalog defaults","Fire","Medical","Sanitation","Police","No station","Mixed selection"]: kind.add_item(title)
	kind.set_item_disabled(6,true); box.add_child(kind)
	radius=field(box,"Road/driveway coverage distance",16,512,8); units=field(box,"Available crews",1,8,1); duration=field(box,"Work duration (seconds)",2,60,1)
	button(box,"Apply to selected stations",apply_station)
	studio.label(box,"Neighborhood requests",14)
	request_kind=OptionButton.new()
	for type in Plan.KINDS.slice(0,4): request_kind.add_item(type.capitalize())
	box.add_child(request_kind)
	targets=ItemList.new(); targets.custom_minimum_size=Vector2(180,140); box.add_child(targets)
	coverage=studio.label(box,"Enable services to inspect coverage.",12); coverage.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	button(box,"Request visit for chosen target",request_visit)
	jobs=ItemList.new(); jobs.custom_minimum_size=Vector2(180,170); box.add_child(jobs)
	button(box,"Locate selected crew",locate)
	button(box,"Cancel selected waiting request",cancel_waiting)
	var help: Label=studio.label(box,"Use connected roads and ground-level entrances. Supplied stations have defaults; assign types to other objects as needed. Coverage includes road travel and driveway distance. Crews remain busy through their return trip. Mixed labels identify differing station settings; Apply replaces all displayed settings on the selected editable objects. Catalog defaults removes overrides. Crews reroute toward the assigned site or station when a safe lane is available. A disconnected crew waits at its current position. Requests, results and crew positions are temporary; loading restarts the preview. During Walk, use the service request panel or its shortcuts near an eligible target.",12); help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART

func field(parent: Node,title: String,low: float,high: float,step: float) -> SpinBox:
	studio.label(parent,title,12); return studio.spin(parent,low,high,step,low)
func button(parent: Node,title: String,callback: Callable) -> void:
	var control:=Button.new(); control.text=title; control.clip_text=true; parent.add_child(control); control.pressed.connect(callback)
func start() -> void:
	for mode in ["2d","3d"]:
		var manager:=Runtime.new(); manager.name="CityServices"; studio.worlds[mode].add_child(manager); managers[mode]=manager
		studio.traffic_tools.managers[mode].services=manager
		studio.worlds[mode].exploration.emergency.services = manager
	refresh_fields()
func refresh_fields() -> void:
	var config: Dictionary=Plan.settings(studio.current().data)
	enabled.set_pressed_no_signal(config["enabled"]); automatic.set_pressed_no_signal(config["automatic"]); interval.set_value_no_signal(config["interval"]); seed.set_value_no_signal(config["seed"])
	paused.set_pressed_no_signal(managers[studio.mode].paused if managers.has(studio.mode) else false)
func show() -> void:
	studio.workspace_presets.set_focus(false)
	if studio.walking: studio.set_walking(false)
	studio.workspace_layout.inspector_toggle.button_pressed=true; studio.workspace_layout.tabs.current_tab=panel.get_index(); refresh_fields(); refresh_selection()
func apply_settings() -> void:
	if studio.interior_tools.editing(): studio.status.text="Configure services from the exterior city editor."; return
	studio.finish_edit(studio.canvas_pointer())
	var config: Dictionary={"enabled":enabled.button_pressed,"automatic":automatic.button_pressed,"interval":interval.value,"seed":int(seed.value)}
	if config==Plan.settings(studio.current().data): studio.status.text="Service settings are unchanged."; return
	studio.current().checkpoint()
	var values: Dictionary=studio.current().data.get("services",{}).duplicate(true); values.merge(config,true); studio.current().data["services"]=values; studio.changed(); dirty=true
	studio.status.text="City service settings applied. Undo restores previous settings."
func refresh_selection() -> void:
	var items: Array=studio.selection_items()
	var stamp: int=hash([studio.mode,items.map(func(item: Dictionary):return [item["uid"],item["asset"],item.get("city_service",{})])])
	if stamp==selection_signature: return
	selection_signature=stamp
	if items.is_empty(): context.text="Select editable objects to configure stations."; return
	var profiles: Array=items.map(func(item: Dictionary):return Plan.profile(item))
	var values: Array=items.map(func(item: Dictionary):return item.get("city_service",{}).get("kind",""))
	kind.select(["","fire","medical","sanitation","police","none"].find(values[0]) if values.all(func(value: String):return value==values[0]) else 6)
	var fields: Array=[radius,units,duration]; var keys: Array=["radius","units","task_seconds"]; var names: Array=["Road/driveway coverage distance","Available crews","Work duration (seconds)"]
	for index in 3:
		fields[index].set_value_no_signal(profiles[0][keys[index]])
		fields[index].get_parent().get_child(fields[index].get_index()-1).text=names[index]+(" · Mixed" if not profiles.all(func(p: Dictionary):return p[keys[index]]==profiles[0][keys[index]]) else "")
	context.text="%d editable objects · Apply replaces all displayed station settings." % items.size()
func apply_station() -> void:
	if studio.interior_tools.editing(): studio.status.text="Configure stations in the exterior city editor."; return
	if kind.selected>=6: studio.status.text="Choose a service type for the mixed selection."; return
	studio.finish_edit(studio.canvas_pointer())
	var changes: Dictionary={}; var items: Array=studio.selection_items()
	for item in items:
		var config: Dictionary=item.get("city_service",{}).duplicate(true)
		if kind.selected==0:
			for key in Plan.profile({}): config.erase(key)
		else: config.merge({"kind":["","fire","medical","sanitation","police","none"][kind.selected],"radius":radius.value,"units":int(units.value),"task_seconds":duration.value},true)
		if config!=item.get("city_service",{}): changes[item["uid"]]=config
	if changes.is_empty(): studio.status.text="Select editable objects whose station settings should change."; return
	studio.current().checkpoint()
	for item in items:
		if not changes.has(item["uid"]): continue
		if changes[item["uid"]].is_empty(): item.erase("city_service")
		else: item["city_service"]=changes[item["uid"]]
	studio.changed(); dirty=true; studio.status.text="Station settings applied to %d objects." % changes.size()
func request_visit() -> void:
	var selected: PackedInt32Array=targets.get_selected_items()
	if selected.is_empty(): studio.status.text="Choose a neighborhood target from the service list."; return
	var result: Dictionary=managers[studio.mode].dispatch.request(Plan.KINDS[request_kind.selected],targets.get_item_metadata(selected[0]))
	studio.status.text="Service visit requested." if result["ok"] else result["reason"]
func locate() -> void:
	var selected: PackedInt32Array=jobs.get_selected_items()
	if selected.is_empty(): return
	var manager: Node=managers[studio.mode]; var id: String=jobs.get_item_metadata(selected[0])
	if not manager.crews.has(id): studio.status.text="This request has no visible crew yet."; return
	var actor: Node=manager.crews[id]["vehicle"]["actor"]
	if studio.mode=="2d": studio.worlds["2d"].camera.position=actor.position
	else: studio.worlds["3d"].target=actor.position; studio.worlds["3d"].update_camera()
func cancel_waiting() -> void:
	var selected: PackedInt32Array=jobs.get_selected_items()
	if selected.is_empty(): return
	for job in managers[studio.mode].dispatch.jobs:
		if job["id"]==jobs.get_item_metadata(selected[0]):
			if job["state"]=="waiting": managers[studio.mode].dispatch.cancel(job,"Waiting request cancelled")
			else: studio.status.text="Only waiting requests can be cancelled here. Active crews finish their trip."
func tick(delta: float) -> void:
	if managers.is_empty(): return
	for mode in managers:
		var manager: Node=managers[mode]
		manager.active=not studio.terrain_tools.drawing and mode==studio.mode and not studio.modal_visible() and not studio.interior_tools.editing() and studio.worlds[mode].exploration.interior==null
		if is_instance_valid(manager.helper.container): manager.helper.container.visible=mode==studio.mode and not studio.interior_tools.editing() and studio.worlds[mode].exploration.interior==null
		manager.request_label=studio.control_settings.label_for("service_request"); manager.cycle_label=studio.control_settings.label_for("service_type")
		manager.ui_scale=studio.accessibility_settings.text_scale; manager.large_targets=studio.accessibility_settings.large_targets; manager.high_contrast=studio.accessibility_settings.high_contrast
		manager.refresh_links()
	var current_manager: Node = managers[studio.mode]
	# Moving the viewport between workspaces exits and re-enters its runtime.
	if (dirty or current_manager.dispatch.plan.is_empty()) and not studio.interior_tools.editing() and studio.worlds[studio.mode].exploration.interior==null and not studio.stroke and not studio.ground_brush.drawing and not studio.transform_handles.dragging:
		current_manager.configure(studio.current().data,studio.library,studio.worlds[studio.mode].instances,studio.worlds[studio.mode].objects,studio.traffic_tools.managers[studio.mode],true,studio.worlds[studio.mode].exploration); dirty=false; refresh_fields()
	if panel.is_visible_in_tree(): refresh_selection()
	elapsed+=delta
	if elapsed<.4: return
	elapsed=0
	var manager: Node=managers[studio.mode]; var plan: Dictionary=manager.dispatch.plan
	status.text="Services are off." if plan.is_empty() or not plan["settings"]["enabled"] else "%d stations · %d busy crews · %d recent completed tasks" % [plan["stations"].size(),manager.dispatch.units.size(),manager.dispatch.history.size()]
	for crew in manager.crews.values():
		if crew["job"]["state"]=="blocked":
			status.text+="\n"+crew["job"]["reason"]
			break
	if not plan.get("notices",[]).is_empty(): status.text+="\n"+"\n".join(plan["notices"])
	if not manager.automatic_notice.is_empty(): status.text+="\n"+manager.automatic_notice
	var selection: PackedInt32Array=targets.get_selected_items(); var uid: String=targets.get_item_metadata(selection[0]) if not selection.is_empty() else studio.selected_uid
	targets.clear()
	for key in plan.get("targets",{}):
		targets.add_item(plan["targets"][key]["name"]); targets.set_item_metadata(targets.item_count-1,key)
		if key==uid: targets.select(targets.item_count-1)
	coverage.text="Choose a target to inspect this service's road coverage."
	coverage_result={}
	if plan.get("targets",{}).has(uid):
		var chosen_kind: String=Plan.KINDS[request_kind.selected]
		var choice: Dictionary=Plan.choose(plan,chosen_kind,uid)
		coverage_result={"signature":manager.signature,"mode":studio.mode,"target":uid,"kind":chosen_kind,"result":choice}
		coverage.text=(plan["stations"][choice["station"]]["name"]+" · %.1f road/driveway units" % choice["distance"]) if choice["ok"] else choice["reason"]
	selection=jobs.get_selected_items(); var job_id: String=jobs.get_item_metadata(selection[0]) if not selection.is_empty() else ""
	jobs.clear()
	for job in manager.dispatch.jobs:
		jobs.add_item(job["kind"].capitalize()+" · "+job["reason"]); jobs.set_item_metadata(jobs.item_count-1,job["id"]); jobs.set_item_tooltip(jobs.item_count-1,job["id"]+" · "+job["state"]+" · "+job["reason"])
		if job["id"]==job_id: jobs.select(jobs.item_count-1)
func reset() -> void:
	coverage_result={}
	for manager in managers.values(): manager.reset()
	dirty=true; selection_signature=-1
