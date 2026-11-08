extends RefCounted

const Plan = preload("res://scripts/builder/laundry_plan.gd")
const Floors = preload("res://scripts/builder/floor_plan.gd")
const Layers = preload("res://scripts/builder/layers.gd")
const Protection = preload("res://scripts/builder/cooperative_plan.gd")
const Palette = preload("res://scripts/builder/asset_palette_policy.gd")

var studio: Control
var panel := ScrollContainer.new()
var enabled: CheckButton
var apply_city: Button
var station_enabled: CheckButton
var capacity := SpinBox.new()
var capacity_label: Label
var require_power: CheckButton
var require_water: CheckButton
var apply_station: Button
var selected_label: Label
var message: Label
var signature: int = -1

func _init(host: Control) -> void:
	studio = host
	panel.name = "Laundry"
	panel.follow_focus = true
	panel.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	studio.workspace_layout.tabs.add_child(panel)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	panel.add_child(body)
	label(body, "Laundry services", 17)
	enabled = toggle(body, "Enable laundry preview")
	apply_city = button(body, "Apply city setting", save_city)
	selected_label = label(body, "", 13)
	station_enabled = toggle(body, "Use as laundry station")
	capacity_label = label(body, "Capacity in items", 12)
	capacity.min_value = 1
	capacity.max_value = Plan.MAX_LOAD
	capacity.accessibility_name = "Machine capacity in items"
	body.add_child(capacity)
	require_power = toggle(body, "Require connected electricity")
	require_water = toggle(body, "Require connected water")
	apply_station = button(body, "Apply station setting", save_station)
	message = label(body, "", 13)
	label(body, "On one floor, enable a checkout counter, a washer, a dryer, a folding table, a basket and a detergent supply. You can use a combined machine for washing and drying.", 12)
	label(body, "In Walk, use the counter to receive loads. Machines run in queue order even when you walk away. Fold each dry load at the table, then return it by its claim ticket. Build and Photo pause the preview.", 12)

func label(parent: Node, text: String, size: int) -> Label:
	var control: Label = studio.label(parent, text, size)
	control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return control

func toggle(parent: Node, text: String) -> CheckButton:
	var control := CheckButton.new()
	control.text = text
	control.clip_text = true
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
		studio.worlds[mode].exploration.laundry.authored_root = func() -> Dictionary:
			return studio.interior_tools.root_document(mode).data

func selected() -> Dictionary:
	var items: Array = studio.selection_items()
	return items[0] if items.size() == 1 and not Plan.profile(items[0]).is_empty() else {}

func show() -> void:
	studio.workspace_presets.set_focus(false)
	if studio.walking: studio.set_walking(false)
	if studio.get_viewport_rect().size.x < 1200: studio.workspace_layout.library_toggle.button_pressed = false
	studio.workspace_layout.inspector_toggle.button_pressed = true
	studio.workspace_layout.tabs.current_tab = panel.get_index()
	studio.workspace_layout.tabs.get_tab_bar().call_deferred("ensure_tab_visible", panel.get_index())
	signature = -1
	refresh()

func refresh() -> void:
	var item: Dictionary = selected()
	var data: Dictionary = studio.current().data
	var root: Dictionary = studio.interior_tools.root_document(studio.mode).data
	var may_city: bool = not studio.interior_tools.editing() and not studio.walking and studio.shared_authority()
	var can_edit: bool = not studio.walking and not item.is_empty() and Layers.editable(data, item, studio.library)
	var next: int = hash([studio.mode, item, may_city, can_edit, Plan.enabled(root)])
	if next == signature: return
	signature = next
	enabled.disabled = not may_city
	enabled.set_pressed_no_signal(Plan.enabled(root))
	apply_city.disabled = not may_city
	var profile: Dictionary = Plan.profile(item)
	var role: String = profile.get("role", "")
	var role_name: String = {"wash":"Washer", "dry":"Dryer", "fold":"Folding table", "counter":"Order counter",
		"basket":"Laundry basket", "supply":"Detergent supply"}.get(role, "")
	if profile.get("dual", false): role_name = "Washer and dryer"
	selected_label.text = "Select a reviewed laundry object." if item.is_empty() else "%s · %s" % [
		studio.library.assets[item["asset"]]["name"], role_name]
	station_enabled.disabled = not can_edit
	apply_station.disabled = not can_edit
	capacity_label.visible = role in Plan.MACHINES
	capacity.visible = capacity_label.visible
	capacity.editable = can_edit
	require_power.visible = capacity_label.visible
	require_power.disabled = not can_edit
	require_water.visible = role == "wash"
	require_water.disabled = not can_edit
	var raw: Dictionary = item.get("laundry", {})
	station_enabled.set_pressed_no_signal(not Plan.station(item).is_empty())
	require_power.set_pressed_no_signal(raw.get("power", false))
	require_water.set_pressed_no_signal(raw.get("water", false))
	capacity.max_value = profile.get("capacity", 1)
	capacity.set_value_no_signal(raw.get("capacity", capacity.max_value))

func save_city() -> void:
	if apply_city.disabled: return
	var data: Dictionary = studio.current().data.duplicate(true)
	var config: Dictionary = data.get("laundry", {})
	config["enabled"] = enabled.button_pressed
	data["laundry"] = config
	commit(data, "City laundry setting saved.")

func save_station() -> void:
	if apply_station.disabled: return
	var uid: String = selected().get("uid", "")
	if uid.is_empty(): return
	var data: Dictionary = studio.current().data.duplicate(true)
	for item in data["objects"]:
		if item["uid"] != uid: continue
		var config: Dictionary = item.get("laundry", {})
		config.merge({"enabled": station_enabled.button_pressed, "capacity": int(capacity.value),
			"power": require_power.visible and require_power.button_pressed,
			"water": require_water.visible and require_water.button_pressed}, true)
		item["laundry"] = config
	commit(data, "Laundry station saved. Undo restores the previous setting.")

func commit(updated: Dictionary, success: String) -> void:
	var doc: RefCounted = studio.current()
	if doc.data == updated:
		message.text = "No laundry setting changed."
		return
	var original: Dictionary = studio.interior_tools.root_document(studio.mode).data
	var after: Dictionary = updated
	if studio.interior_tools.editing():
		after = original.duplicate(true)
		for host in after["objects"]:
			if host["uid"] != studio.interior_tools.uid: continue
			var room: Dictionary = Floors.room(host["interior"], doc.floor_uid)
			room.assign(updated)
			break
	var content: Dictionary = Palette.check(original, after, studio.library)
	if not content["ok"]:
		message.text = content["reason"]
		return
	var session: Node = studio.cooperative_tools.session
	if session.connected and session.role == "client":
		var shared: Dictionary = studio.cooperative_tools.snapshot()
		var proposed: Dictionary = shared.duplicate(true)
		proposed[studio.mode] = after
		var reason: String = Protection.allowed(shared, proposed, session.local_id, studio.library)
		if not reason.is_empty():
			message.text = reason
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
	for mode in studio.worlds: studio.worlds[mode].exploration.laundry.reset()
	signature = -1
