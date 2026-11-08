extends RefCounted
const Plan=preload("res://scripts/builder/ambience_plan.gd")
var studio: Control
var panel: VBoxContainer
var page: ScrollContainer
var enabled: CheckButton
var preview: CheckButton
var volume: SpinBox
var reach: SpinBox
var categories: Dictionary={}
var apply_mix: Button
var source_kind: OptionButton
var source_volume: SpinBox
var source_range: SpinBox
var apply_source: Button
var source_caption: Label
var status: Label
var mute_button: Button
var managers: Dictionary={}
var contexts: Dictionary={}
var muted: bool=false
var stamp: int=0
var source_stamp: int=0
var elapsed: float=0

func _init(owner_control: Control) -> void:
	studio=owner_control; page=ScrollContainer.new(); page.name="Audio"; page.follow_focus=true; page.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_SHOW_NEVER; studio.workspace_layout.tabs.add_child(page)
	panel=VBoxContainer.new(); panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL; page.add_child(panel)
	var title: Label=studio.label(panel,"Environmental audio",17); title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	mute_button=button("Mute ambience",toggle_mute); mute_button.set_meta("editor_action","ambience_mute")
	enabled=CheckButton.new(); enabled.text="Enable audio"; enabled.tooltip_text="Enable environmental ambience in this city."; panel.add_child(enabled)
	preview=CheckButton.new(); preview.text="Hear in Build"; preview.tooltip_text="Listen at the view centre while editing; otherwise audio plays during Walk mode."; panel.add_child(preview)
	volume=field("City volume (%)",0,100,1); reach=field("Sound range multiplier",.25,4,.05)
	for kind in Plan.KINDS:
		if kind == "school": studio.label(panel,"Place activity levels",15)
		categories[kind]=field(Plan.definitions()["kinds"][kind]["label"]+" (%)",0,100,1)
	apply_mix=button("Apply city mix",apply_settings)
	studio.label(panel,"Selected object sound",16)
	source_caption=studio.label(panel,"Select an object to author a localized sound.",12); source_caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	source_kind=OptionButton.new(); source_kind.fit_to_longest_item=false; source_kind.accessibility_name="Selected object sound type"; source_kind.add_item("Automatic from activity or object"); source_kind.set_item_metadata(0,"auto"); source_kind.add_item("Silent"); source_kind.set_item_metadata(1,"none")
	for kind in Plan.KINDS: source_kind.add_item(Plan.definitions()["kinds"][kind]["label"]); source_kind.set_item_metadata(source_kind.item_count-1,kind)
	panel.add_child(source_kind); source_volume=field("Source level (%)",0,200,1); source_range=field("Source range · ground units",1,128,.5)
	apply_source=button("Apply sound to selection",apply_selected); button("Restore automatic object sound",restore_selected)
	status=studio.label(panel,"Audio follows your character in Walk mode. Enable listening while building to hear the view centre.",12); status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var help: Label=studio.label(panel,"City controls apply outside the room editor. Selected-object controls also work inside rooms and share their Undo history. Fountains and trees use authored profiles; open businesses emit shop ambience. Moving traffic, transit and service vehicles follow their actual positions. Occupied schools, running arcade games, working village forges and operating markets have separate sounds. Piers or objects with a Harbor override need connected shoreline water. Activity audio follows the active floor. Hide a source or its layer to silence it. The mute shortcut silences ambience without editing the project; Controls can remap it.",12); help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	studio.workspace_layout.prepare_controls(panel)
	page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

func field(title: String,low: float,high: float,step: float) -> SpinBox:
	studio.label(panel,title,12); var value: SpinBox=studio.spin(panel,low,high,step,low); value.accessibility_name=title; value.get_line_edit().accessibility_name=title; return value
func button(title: String,callback: Callable) -> Button:
	var value:=Button.new(); value.text=title; value.clip_text=true; panel.add_child(value); value.pressed.connect(callback); return value
func start() -> void:
	for mode in ["2d","3d"]:
		var manager=preload("res://scripts/builder/ambience_runtime.gd").new(); studio.worlds[mode].add_child(manager); managers[mode]=manager; contexts[mode]=preload("res://scripts/builder/ambience_context.gd").new()
	refresh()
func show() -> void:
	studio.set_walking(false); studio.workspace_presets.set_focus(false)
	if studio.get_viewport_rect().size.x<1200: studio.workspace_layout.library_toggle.button_pressed=false
	studio.workspace_layout.inspector_toggle.button_pressed=true; studio.workspace_layout.tabs.current_tab=page.get_index(); stamp=0; source_stamp=0; refresh()
func root_document() -> RefCounted: return studio.interior_tools.root_document(studio.mode)
func refresh() -> void:
	if studio.documents.is_empty(): return
	var config: Dictionary=Plan.settings(root_document().data); var next: int=hash([studio.mode,config,studio.interior_tools.editing()])
	if next!=stamp:
		stamp=next; enabled.set_pressed_no_signal(config["enabled"]); preview.set_pressed_no_signal(config["preview_in_build"]); volume.set_value_no_signal(config["volume"]*100); reach.set_value_no_signal(config["range_scale"])
		for kind in categories: categories[kind].set_value_no_signal(config[kind]*100)
	apply_mix.disabled=studio.interior_tools.editing()
	var items: Array=studio.selection_items(); var item: Dictionary=items[0] if not items.is_empty() else {}; var next_source: int=hash([studio.mode,studio.selected_uids,item.get("audio",{}),item.get("asset","")])
	if next_source!=source_stamp:
		source_stamp=next_source; apply_source.disabled=items.is_empty(); source_caption.text=("%d selected · source controls apply to all editable selected objects."%items.size()) if not items.is_empty() else "Select an object to author a localized sound."
		var raw: Dictionary=item.get("audio",{}); var profile: Dictionary=Plan.profile(item) if not item.is_empty() else {}
		for index in source_kind.item_count:
			if source_kind.get_item_metadata(index)==raw.get("kind","auto"): source_kind.select(index)
		source_volume.set_value_no_signal(float(raw.get("volume",1))*100); source_range.set_value_no_signal(float(raw.get("range",profile.get("range",24))))
	mute_button.text="Unmute ambience" if muted else "Mute ambience"; mute_button.tooltip_text="Mute / unmute ambience · "+studio.control_settings.label_for("ambience_mute")
func apply_settings() -> void:
	if studio.interior_tools.editing(): studio.status.text="Return to the city to change its ambience mix."; return
	studio.finish_edit(studio.canvas_pointer()); var doc: RefCounted=studio.current(); doc.finish_checkpoint(); var before: Dictionary=doc.data.duplicate(true)
	var value: Dictionary=doc.data.get("ambience",{}).duplicate(true); value.merge({"enabled":enabled.button_pressed,"preview_in_build":preview.button_pressed,"volume":volume.value/100,"range_scale":reach.value},true)
	for kind in categories: value[kind]=categories[kind].value/100
	doc.data["ambience"]=value
	if doc.record_completed_change(before): studio.changed(); studio.status.text="Saved city ambience mix. Undo restores the previous settings."
	stamp=0; refresh()
func apply_selected() -> void: change_selected(false)
func restore_selected() -> void: change_selected(true)
func change_selected(automatic: bool) -> void:
	studio.finish_edit(studio.canvas_pointer())
	var items: Array=studio.selection_items()
	if items.is_empty(): return
	var doc: RefCounted=studio.current(); doc.checkpoint()
	for item in items:
		if automatic: item.erase("audio")
		else:
			var value: Dictionary=item.get("audio",{}).duplicate(true); value.merge({"kind":source_kind.get_item_metadata(source_kind.selected),"enabled":true,"volume":source_volume.value/100,"range":source_range.value},true); item["audio"]=value
	doc.finish_checkpoint(); studio.changed(); source_stamp=0; refresh(); studio.status.text="Saved localized sound controls for %d objects."%items.size()
func toggle_mute() -> void:
	muted=not muted
	for manager in managers.values(): manager.muted=muted
	refresh(); studio.status.text="Ambience muted for this session." if muted else "Ambience unmuted."
func tick(delta: float) -> void:
	if managers.is_empty(): return
	for mode in managers:
		if mode!=studio.mode:
			if not managers[mode].voices.is_empty(): managers[mode].reset(); contexts[mode].reset()
			continue
		var vehicles: Array=[]; vehicles.append_array(studio.traffic_tools.managers[mode].vehicles); vehicles.append_array(studio.service_tools.managers[mode].vehicle_states()); vehicles.append_array(studio.transit_tools.managers[mode].vehicle_states())
		vehicles.append_array(studio.worlds[mode].exploration.driving.vehicle_states())
		var editing: Dictionary={}; var scope: String=""; var height: float=0
		if studio.interior_tools.editing():
			editing=studio.current().data; scope=studio.interior_tools.uid+":"+studio.current().floor_uid
			for floor in preload("res://scripts/builder/floor_plan.gd").definitions(studio.current().canonical.data):
				if floor["uid"]==studio.current().floor_uid: height=float(floor["height"])
		var context: Dictionary=contexts[mode].collect(studio.interior_tools.root_document(mode).data,studio.worlds[mode],studio.walking,studio.library,vehicles,studio.business_tools.managers[mode].hour,editing,scope,height,studio.citizen_tools.managers[mode],studio.business_tools.managers[mode])
		managers[mode].step(delta,context["sources"],context["listener"],context["config"],context["right"])
	elapsed+=delta
	if elapsed>=.3:
		elapsed=0; refresh()
		if muted: status.text="Ambience muted for this session."
		elif not Plan.settings(root_document().data)["enabled"]: status.text="City ambience is disabled."
		else: status.text="Ambience follows the active room or city view." if not managers[studio.mode].selected.is_empty() else "No audible sources nearby. Audio normally plays in Walk mode."
func reset() -> void:
	for manager in managers.values(): manager.reset()
	for context in contexts.values(): context.reset()
	stamp=0; source_stamp=0
