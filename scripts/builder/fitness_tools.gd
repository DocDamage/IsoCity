extends RefCounted

const Plan = preload("res://scripts/builder/fitness_plan.gd")
const Floors = preload("res://scripts/builder/floor_plan.gd")
const Layers = preload("res://scripts/builder/layers.gd")
const Protection = preload("res://scripts/builder/cooperative_plan.gd")
const Palette = preload("res://scripts/builder/asset_palette_policy.gd")

var studio: Control
var panel := ScrollContainer.new()
var enabled: CheckButton
var apply_city: Button
var station_enabled: CheckButton
var opening: SpinBox
var closing: SpinBox
var apply_station: Button
var selected_label: Label
var message: Label
var signature: int = -1

func _init(host: Control) -> void:
	studio = host
	panel.name = "Sports"
	panel.follow_focus = true
	panel.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	studio.workspace_layout.tabs.add_child(panel)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",8)
	panel.add_child(body)
	label(body,"Fitness and sports",17)
	enabled = toggle(body,"Enable sports preview")
	apply_city = button(body,"Apply city setting",save_city)
	selected_label = label(body,"",13)
	station_enabled = toggle(body,"Use as a sports station")
	opening = hour_field(body,"Opening hour")
	closing = hour_field(body,"Closing hour")
	apply_station = button(body,"Apply station setting",save_station)
	message = label(body,"",13)
	label(body,"Select an exercise bike, treadmill, rowing machine or reviewed soccer goal. Matching opening and closing hours allow all-day bookings.",12)
	label(body,"In Walk, approach the equipment or stand about eight metres in front of a goal. Open booking with Interact, reserve one spot, then check in. The penalty drill has five shots and a three-goal target.",12)

func label(parent: Node, text: String, size: int) -> Label:
	var control: Label = studio.label(parent,text,size)
	control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return control

func toggle(parent: Node, text: String) -> CheckButton:
	var control := CheckButton.new()
	control.text = text
	control.clip_text = true
	parent.add_child(control)
	return control

func hour_field(parent: Node, text: String) -> SpinBox:
	label(parent,text,12)
	var control := SpinBox.new()
	control.max_value = 23.5
	control.step = .5
	control.accessibility_name = text
	parent.add_child(control)
	return control

func button(parent: Node, text: String, action: Callable) -> Button:
	var control := Button.new()
	control.text = text
	control.clip_text = true
	control.pressed.connect(action)
	parent.add_child(control)
	return control

func start() -> void:
	for mode in studio.worlds:
		studio.worlds[mode].exploration.fitness.authored_root = func() -> Dictionary:
			return studio.interior_tools.root_document(mode).data

func selected() -> Dictionary:
	var items: Array = studio.selection_items()
	return items[0] if items.size() == 1 and not Plan.profile(items[0],studio.mode).is_empty() else {}

func show() -> void:
	studio.workspace_presets.set_focus(false)
	if studio.walking: studio.set_walking(false)
	if studio.get_viewport_rect().size.x < 1200: studio.workspace_layout.library_toggle.button_pressed = false
	studio.workspace_layout.inspector_toggle.button_pressed = true
	studio.workspace_layout.tabs.current_tab = panel.get_index()
	studio.workspace_layout.tabs.get_tab_bar().call_deferred("ensure_tab_visible",panel.get_index())
	signature = -1
	refresh()

func refresh() -> void:
	var item: Dictionary = selected()
	var data: Dictionary = studio.current().data
	var root: Dictionary = studio.interior_tools.root_document(studio.mode).data
	var may_city: bool = not studio.interior_tools.editing() and not studio.walking and studio.shared_authority()
	var can_edit: bool = not studio.walking and not item.is_empty() and Layers.editable(data,item,studio.library)
	var next: int = hash([studio.mode,item,may_city,can_edit,Plan.enabled(root)])
	if next == signature: return
	signature = next
	enabled.disabled = not may_city
	enabled.set_pressed_no_signal(Plan.enabled(root))
	apply_city.disabled = not may_city
	var config: Dictionary = item.get("fitness",{})
	selected_label.text = "Select a reviewed sports object."
	if not item.is_empty():
		var kind: String = Plan.profile(item,studio.mode)["activity"]
		selected_label.text = Plan.definitions()["activities"][kind]["name"]
		var issue: String = Plan.equipment_reason(item,studio.library,studio.mode)
		if not issue.is_empty(): selected_label.text += "\n"+issue
	station_enabled.disabled = not can_edit
	station_enabled.set_pressed_no_signal(config.get("enabled",false))
	opening.editable = can_edit
	closing.editable = can_edit
	opening.set_value_no_signal(config.get("open_hour",0))
	closing.set_value_no_signal(config.get("close_hour",0))
	apply_station.disabled = not can_edit

func save_city() -> void:
	if apply_city.disabled: return
	var updated: Dictionary = studio.current().data.duplicate(true)
	var settings: Dictionary = updated.get("fitness",{})
	settings["enabled"] = enabled.button_pressed
	updated["fitness"] = settings
	commit(updated,"City sports setting saved.")

func save_station() -> void:
	if apply_station.disabled: return
	var uid: String = selected().get("uid","")
	if uid.is_empty(): return
	var updated: Dictionary = studio.current().data.duplicate(true)
	for item in updated["objects"]:
		if item["uid"] != uid: continue
		var config: Dictionary = item.get("fitness",{})
		config.merge({"enabled":station_enabled.button_pressed,"open_hour":opening.value,"close_hour":closing.value},true)
		item["fitness"] = config
		break
	commit(updated,"Sports station saved. Undo restores its previous setting.")

func commit(updated: Dictionary, success: String) -> void:
	var doc: RefCounted = studio.current()
	if doc.data == updated:
		message.text = "No sports setting changed."
		return
	var original: Dictionary = studio.interior_tools.root_document(studio.mode).data
	var after: Dictionary = updated
	if studio.interior_tools.editing():
		after = original.duplicate(true)
		for host in after["objects"]:
			if host["uid"] != studio.interior_tools.uid: continue
			Floors.room(host["interior"],doc.floor_uid).assign(updated)
			break
	var content: Dictionary = Palette.check(original,after,studio.library)
	if not content["ok"]:
		message.text = content["reason"]
		return
	var session: Node = studio.cooperative_tools.session
	if session.connected and session.role == "client":
		var shared: Dictionary = studio.cooperative_tools.snapshot()
		var proposed: Dictionary = shared.duplicate(true)
		proposed[studio.mode] = after
		var issue: String = Protection.allowed(shared,proposed,session.local_id,studio.library)
		if not issue.is_empty():
			message.text = issue
			return
	studio.finish_edit(studio.canvas_pointer())
	doc.checkpoint()
	doc.data = updated
	studio.changed()
	doc.finish_checkpoint(true)
	message.text = success
	signature = -1
	refresh()

func reset() -> void:
	for mode in studio.worlds: studio.worlds[mode].exploration.fitness.reset()
	signature = -1
