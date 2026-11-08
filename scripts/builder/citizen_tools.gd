extends RefCounted

const Plan=preload("res://scripts/builder/citizen_plan.gd")
const Runtime=preload("res://scripts/builder/citizen_runtime.gd")
var studio: Control
var managers: Dictionary={}
var dirty: bool=true
var panel: ScrollContainer
var enabled: CheckButton
var interior_activities: CheckButton
var interior_help: Label
var activity_status: Label
var resident_detail: Label
var population: SpinBox
var seed: SpinBox
var length: SpinBox
var hour: SpinBox
var appearance: OptionButton
var appearance_label: Label
var role_choice: OptionButton
var role_context: Label
var selection_signature: int=-1
var status: Label
var destinations: Label
var residents: ItemList
var paused: CheckButton
var refresh_elapsed: float=0

func _init(host: Control) -> void:
	studio=host
	panel=ScrollContainer.new(); panel.name="Citizens"; panel.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; panel.follow_focus=true
	studio.workspace_layout.tabs.add_child(panel)
	var box:=VBoxContainer.new(); box.size_flags_horizontal=Control.SIZE_EXPAND_FILL; box.add_theme_constant_override("separation",8); panel.add_child(box)
	var title: Label=studio.label(box,"Residents and daily routines",17); title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	enabled=CheckButton.new(); enabled.text="Enable citizens"; enabled.accessibility_name="Enable citizens"; box.add_child(enabled)
	interior_activities=CheckButton.new(); interior_activities.name="InteriorActivities"; interior_activities.text="Interior activities"; interior_activities.accessibility_name="Resident interior activities"; interior_activities.tooltip_text="Let residents use furnished seats and appliances in workplaces and shops. Requires citizens and reachable stations. Off by default."; box.add_child(interior_activities)
	interior_help=studio.label(box,"Let residents use furnished seats and appliances in workplaces and shops. Requires citizens and reachable stations. Off by default. Activity progress resets when you reopen the project.",12); interior_help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	population=field(box,"Population",0,128,1)
	seed=field(box,"Routine seed",1,2147483647,1)
	length=field(box,"Seconds per day",30,3600,10)
	hour=field(box,"Start hour / jump to time",0,23.9,.5)
	appearance_label=studio.label(box,"Citizen appearance · 2D",12); appearance=OptionButton.new(); appearance.fit_to_longest_item=false; appearance.clip_text=true; box.add_child(appearance); appearance.add_item("Default office worker"); appearance.set_item_metadata(0,"")
	for id in studio.library.assets:
		if id.begins_with("2d:") and studio.library.assets[id]["data"].get("kind","")=="char":
			appearance.add_item(studio.library.assets[id]["name"]); appearance.set_item_metadata(appearance.item_count-1,id)
	button(box,"Apply simulation settings",apply_settings)
	var times:=HFlowContainer.new(); box.add_child(times)
	for activity in [["Commute",8.5],["Lunch",12.5],["Park",17.5],["Home",21.5]]:
		var jump:=Button.new(); jump.text=activity[0]; times.add_child(jump)
		jump.pressed.connect(func(): hour.set_value_no_signal(activity[1]); apply_settings())
	paused=CheckButton.new(); paused.text="Pause preview"; box.add_child(paused)
	paused.toggled.connect(func(on: bool):
		if managers.has(studio.mode): managers[studio.mode].paused=on)
	studio.label(box,"Destination override for selection",12)
	role_context=studio.label(box,"",12); role_context.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	role_choice=OptionButton.new(); role_choice.fit_to_longest_item=false; role_choice.clip_text=true
	for text in ["Catalog default","Home","Workplace","Shop / café","Park / public space","No destination"]: role_choice.add_item(text)
	role_choice.add_item("Mixed selection"); role_choice.set_item_disabled(6,true)
	box.add_child(role_choice)
	button(box,"Assign role to selection",assign_role)
	destinations=studio.label(box,"",12); destinations.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	status=studio.label(box,"",12); status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	activity_status=studio.label(box,"",12); activity_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; activity_status.accessibility_name="Interior activity status"
	box.move_child(status,1); box.move_child(destinations,2); box.move_child(activity_status,3)
	residents=ItemList.new(); residents.custom_minimum_size=Vector2(180,160); box.add_child(residents); residents.accessibility_name="Residents and their activities"
	resident_detail=studio.label(box,"Choose a resident to see their destination, activity and any blocked approach.",12); resident_detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; resident_detail.accessibility_name="Selected resident activity"; resident_detail.focus_mode=Control.FOCUS_ALL
	residents.item_selected.connect(func(_index: int):refresh_resident_detail())
	button(box,"Locate selected resident",follow)
	var help: Label=studio.label(box,"Assign homes, workplaces, shops and parks to placed objects. Residents use entrance approaches and walk around obstacles. Missing activities fall back to home. Start time and day length control the daily cycle. Preview positions are transient; loading starts at the saved hour.",12)
	help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART

func field(parent: Node,title: String,low: float,high: float,step: float) -> SpinBox:
	studio.label(parent,title,12)
	return studio.spin(parent,low,high,step,low)

func button(parent: Node,title: String,callback: Callable) -> void:
	var control:=Button.new(); control.text=title; control.clip_text=true; parent.add_child(control); control.pressed.connect(callback)

func start() -> void:
	for mode in ["2d","3d"]:
		var manager:=Runtime.new(); manager.name="Citizens"
		var host_ref: WeakRef=weakref(studio);var dimension_key: String=mode
		manager.city_data=func() -> Dictionary:
			var host: Control=host_ref.get_ref()
			if not is_instance_valid(host):return {}
			return host.interior_tools.root_document(dimension_key).data if host.interior_tools else host.documents[dimension_key].data
		studio.worlds[mode].add_child(manager); managers[mode]=manager
	refresh_fields(); dirty=true

func reset() -> void:
	for manager in managers.values(): manager.reset()
	dirty=true

func show() -> void:
	studio.workspace_presets.set_focus(false)
	if studio.walking: studio.set_walking(false)
	studio.workspace_layout.inspector_toggle.button_pressed=true
	studio.workspace_layout.tabs.current_tab=panel.get_index(); refresh_fields()

func refresh_fields() -> void:
	if studio.documents.is_empty(): return
	var config: Dictionary=Plan.settings(studio.current().data)
	enabled.set_pressed_no_signal(config["enabled"]); interior_activities.set_pressed_no_signal(config["interior_activities"]); population.set_value_no_signal(config["population"]); seed.set_value_no_signal(config["seed"])
	length.set_value_no_signal(config["day_length"]); hour.set_value_no_signal(config["start_hour"])
	appearance_label.visible=studio.mode=="2d"; appearance.visible=studio.mode=="2d"; appearance.select(0)
	for index in appearance.item_count:
		if appearance.get_item_metadata(index)==config.get("appearance",""): appearance.select(index); break
	paused.set_pressed_no_signal(managers.get(studio.mode).paused if managers.has(studio.mode) else false)

func apply_settings() -> void:
	if studio.interior_tools.editing(): studio.status.text="Configure city residents from the exterior city editor."; return
	studio.finish_edit(studio.canvas_pointer())
	var config: Dictionary={"enabled":enabled.button_pressed,"interior_activities":interior_activities.button_pressed,"population":int(population.value),"seed":int(seed.value),"day_length":length.value,"start_hour":hour.value}
	var selected_appearance: String=appearance.get_item_metadata(appearance.selected)
	if studio.mode=="2d" and not selected_appearance.is_empty(): config["appearance"]=selected_appearance
	if Plan.settings(studio.current().data)==config:
		if managers.has(studio.mode): managers[studio.mode].hour=config["start_hour"]
		studio.status.text="Citizen preview time reset. Simulation settings are unchanged."; return
	studio.current().checkpoint()
	var values: Dictionary=studio.current().data.get("citizens",{}).duplicate(true)
	if not config.has("appearance"): values.erase("appearance")
	var previous: Dictionary=Plan.settings(studio.current().data)
	for key in config:
		if not previous.has(key) or config[key]!=previous[key]:values[key]=config[key]
	studio.current().data["citizens"]=values
	studio.changed(); dirty=true
	studio.status.text="Citizen simulation settings applied. Undo restores the previous settings."

func assign_role() -> void:
	var items: Array=studio.selection_items()
	if items.is_empty(): studio.status.text="Select editable destination objects first."; return
	if role_choice.selected>=6: studio.status.text="Choose a destination role to apply to the selection."; return
	studio.finish_edit(studio.canvas_pointer())
	var value: String=["","home","work","shop","park","none"][role_choice.selected]
	items=items.filter(func(item: Dictionary):return item.get("citizen_role","")!=value)
	if items.is_empty(): studio.status.text="The selected destinations already use this role."; return
	studio.current().checkpoint()
	for item in items:
		if value.is_empty(): item.erase("citizen_role")
		else: item["citizen_role"]=value
	studio.changed(); dirty=true
	studio.status.text="Assigned destination role to %d objects." % items.size()

func tick(delta: float) -> void:
	if managers.is_empty(): return
	if panel.is_visible_in_tree(): refresh_role()
	for mode in managers:
		var active: bool=not studio.terrain_tools.drawing and mode==studio.mode and not studio.modal_visible() and not studio.interior_tools.editing() and (studio.worlds[mode].exploration.interior==null or managers[mode].interior_activities_enabled())
		managers[mode].active=active
		if is_instance_valid(managers[mode].container): managers[mode].container.visible=mode==studio.mode and not studio.interior_tools.editing() and studio.worlds[mode].exploration.interior==null
	if dirty and not studio.interior_tools.editing() and (studio.worlds[studio.mode].exploration.interior==null or managers[studio.mode].interior_activities_enabled() or Plan.settings(studio.current().data)["interior_activities"]) and not studio.stroke and not studio.ground_brush.drawing and not studio.transform_handles.dragging:
		var mode: String=studio.mode
		managers[mode].configure(studio.current().data,studio.library,studio.worlds[mode].instances,studio.worlds[mode].objects)
		dirty=false; refresh_fields()
	refresh_elapsed+=delta
	if refresh_elapsed<.4: return
	refresh_elapsed=0
	var manager: Node=managers[studio.mode]
	status.text=manager.summary();activity_status.text=interior_summary(manager)
	var counts: PackedStringArray=[]
	if manager.plan.has("destinations"):
		for use in Plan.ROLES: counts.append("%s: %d" % [use,manager.plan["destinations"][use].size()])
	destinations.text=" · ".join(counts)
	if manager.plan.has("notices"): destinations.text+="\n"+"\n".join(manager.plan["notices"])
	var selected: PackedInt32Array=residents.get_selected_items()
	var index: int=selected[0] if not selected.is_empty() else -1
	residents.clear()
	for resident in manager.residents:
		residents.add_item("Resident %d · %s"%[residents.item_count+1,resident["status"]])
		residents.set_item_tooltip(residents.item_count-1,resident["id"]+"\n"+resident["status"])
	if index>=0 and index<residents.item_count: residents.select(index)
	refresh_resident_detail()

func show_interiors() -> void:
	studio._command("citizens",null)
	interior_activities.grab_focus()
	panel.ensure_control_visible(interior_activities)
	# Tab changes and text scaling settle after the command's initial focus.
	# Reveal the same focused control in both its page and the outer editor scroll.
	for frame in 2:
		await studio.get_tree().process_frame
		if not is_instance_valid(panel) or not interior_activities.has_focus():return
		panel.ensure_control_visible(interior_activities)
		if is_instance_valid(studio.accessibility_settings.root_scroll) and not (studio.consumer_shell and studio.consumer_shell.active):studio.accessibility_settings.root_scroll.ensure_control_visible(interior_activities)

func interior_summary(manager: Node) -> String:
	var config: Dictionary=Plan.settings(studio.current().data)
	if not config["interior_activities"]:return "Interior activities are off."
	if not config["enabled"]:return "Enable citizens to start interior activities."
	if manager.activities==null:return "Interior activities will start when the simulation resumes."
	var inside: int=0;var waiting: int=0
	for job in manager.activities.scheduler.jobs.values():
		if job["state"]=="queued":waiting+=1
		elif job["state"] not in ["complete","cancelled"]:inside+=1
	return "Interior activities · %d indoors · %d waiting outside%s"%[inside,waiting," · Preview paused" if manager.paused else ""]

func floor_name(item: Dictionary,uid: String) -> String:
	return preload("res://scripts/builder/floor_entrances.gd").name_for(item["interior"],uid) if item.get("interior") is Dictionary else "Ground floor"

func refresh_resident_detail() -> void:
	var selected: PackedInt32Array=residents.get_selected_items();var manager: Node=managers.get(studio.mode)
	if selected.is_empty() or not is_instance_valid(manager) or selected[0]>=manager.residents.size():resident_detail.text="Choose a resident to see their destination, activity and any blocked approach.";return
	var resident: Dictionary=manager.residents[selected[0]];var job: Dictionary=manager.activities.scheduler.result(resident["id"]) if manager.activities else {}
	if job.is_empty():resident_detail.text="Resident %d\n%s"%[selected[0]+1,resident["status"]];return
	var item: Dictionary=manager.activities.items.get(job["building"],{});var destination: String=manager.plan.get("lookup",{}).get(job["building"],{}).get("name",item.get("name","Workplace or shop"));var floor: String=floor_name(item,job["floor"])
	if job["link_token"]!=0 and job["leg"]<job["legs"].size():floor+=" → "+floor_name(item,job["legs"][job["leg"]].get("next_floor",job["floor"]))
	var state: String={"queued":"Waiting outside","entering":"Going to a station","service":"Using a reserved station","standing":"Leaving the station","returning":"Returning outside"}.get(job["state"],job["state"])
	resident_detail.text="Resident %d · %s\n%s · %s\n%s"%[selected[0]+1,state,destination,floor,job["reason"]]

func refresh_role() -> void:
	var items: Array=studio.selection_items()
	var signature: int=hash([studio.mode,items.map(func(item: Dictionary):return [item["uid"],item["asset"],item.get("citizen_role","")])])
	if signature==selection_signature: return
	selection_signature=signature
	if items.is_empty(): role_context.text="Select editable objects to assign a destination."; role_choice.select(0); return
	var values: Array=[]; var effective: PackedStringArray=[]
	for item in items:
		var value: String=item.get("citizen_role","")
		if not value in values: values.append(value)
		var resolved: String=Plan.role(item)
		resolved=resolved if not resolved.is_empty() else "no destination"
		if not resolved in effective: effective.append(resolved)
	role_choice.select(6 if values.size()>1 else maxi(0,["","home","work","shop","park","none"].find(values[0])))
	role_context.text="%d editable · Effective: %s" % [items.size(),", ".join(effective)]

func follow() -> void:
	var selected: PackedInt32Array=residents.get_selected_items()
	if selected.is_empty(): return
	var population: Array=managers[studio.mode].residents
	if selected[0]>=population.size(): return
	var actor: Node=population[selected[0]]["actor"]
	if not is_instance_valid(actor): return
	var world: Node=studio.worlds[studio.mode];var manager: Node=managers[studio.mode];var job: Dictionary=manager.activities.scheduler.result(population[selected[0]]["id"]) if manager.activities else {};var point: Variant=world.to_local(actor.global_position)
	if not job.is_empty() and not manager.activities.view.attached.has(population[selected[0]]["id"]) and world.instances.has(job["building"]):
		point=world.exploration.entrance(world.instances[job["building"]]);studio.status.text="This resident is inside. Walk to the building's entrance to visit."
	if studio.mode=="2d":world.camera.position=point
	else:world.target=point;world.update_camera()
