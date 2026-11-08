extends RefCounted

const Plan = preload("res://scripts/builder/garden_plan.gd")
const Layers = preload("res://scripts/builder/layers.gd")
const Protection = preload("res://scripts/builder/cooperative_plan.gd")
const Palette = preload("res://scripts/builder/asset_palette_policy.gd")

var studio: Control
var panel: ScrollContainer
var enabled: CheckButton
var site_enabled: CheckButton
var irrigation: CheckButton
var crop: OptionButton
var pause: CheckButton
var markers: CheckButton
var settings_button: Button
var site_button: Button
var site_name: Label
var readout: Label
var status: Label
var stamp: int = -1

func _init(host: Control) -> void:
	studio = host
	panel = ScrollContainer.new()
	panel.name = "Garden"
	panel.follow_focus = true
	panel.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	studio.workspace_layout.tabs.add_child(panel)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	panel.add_child(body)
	label(body, "Community garden", 17)
	enabled = toggle(body, "Enable garden preview")
	settings_button = button(body, "Apply city setting", apply_settings)
	site_name = label(body, "", 13)
	site_enabled = toggle(body, "Use as garden site")
	label(body, "Crop or seed type", 12)
	crop = OptionButton.new()
	crop.fit_to_longest_item = false
	crop.accessibility_name = "Garden crop or seed type"
	for key in Plan.crops():
		crop.add_item(Plan.crops()[key]["name"])
		crop.set_item_metadata(crop.item_count - 1, key)
	body.add_child(crop)
	irrigation = toggle(body, "Use connected water")
	irrigation.tooltip_text = "Assign this site a Water inlet and connect a supply in the Water panel."
	site_button = button(body, "Apply site setting", apply_site)
	status = label(body, "", 13)
	markers = toggle(body, "Show garden labels")
	markers.toggled.connect(func(value: bool):
		var preview: Node = runtime()
		preview.show_status = value
		preview.refresh_views())
	pause = toggle(body, "Pause garden preview")
	pause.toggled.connect(func(value: bool): runtime().paused = value)
	readout = label(body, "", 13)
	label(body, "In Walk, approach a configured site and press Interact to plant, water, add compost or harvest. Greenhouses grow in winter. Seed trays, water tools, soil bags and compost bins replenish the kit. A produce stand shares harvests to free basket space.", 12)
	label(body, "Garden inventory and any credits belong to this local preview. Build, Photo and interior visits pause growth. Reopening starts a fresh preview.", 12)

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

func runtime() -> Node:
	return studio.worlds[studio.mode].exploration.garden

func editable() -> bool:
	return not studio.walking and not studio.interior_tools.editing() and not studio.current().data.get("interior_room", false)

func selected() -> Dictionary:
	var items: Array = studio.selection_items()
	if not editable() or items.size() != 1 or Plan.profile(items[0]).is_empty(): return {}
	return items[0]

func show() -> void:
	studio.workspace_presets.set_focus(false)
	if studio.walking: studio.set_walking(false)
	if studio.get_viewport_rect().size.x < 1200: studio.workspace_layout.library_toggle.button_pressed = false
	studio.workspace_layout.inspector_toggle.button_pressed = true
	studio.workspace_layout.tabs.current_tab = panel.get_index()
	studio.workspace_layout.tabs.get_tab_bar().call_deferred("ensure_tab_visible", panel.get_index())
	stamp = -1
	refresh()

func refresh() -> void:
	var data: Dictionary = studio.current().data
	var item: Dictionary = selected()
	var config: Dictionary = Plan.site_config(item)
	var preview: Node = runtime()
	var next: int = hash([studio.mode, data.get("garden", {}), item, editable(), studio.shared_authority()])
	if next != stamp:
		stamp = next
		enabled.set_pressed_no_signal(Plan.settings(data))
		settings_button.disabled = not editable() or not studio.shared_authority()
		var may_edit: bool = not item.is_empty() and Layers.editable(data, item, studio.library)
		var role: String = Plan.profile(item).get("role", "")
		site_name.text = "Select a planter, garden bed, greenhouse, or garden supply." if item.is_empty() \
			else studio.library.assets[item["asset"]]["name"] + " · " + role.capitalize()
		site_enabled.disabled = not may_edit
		site_button.disabled = not may_edit
		site_enabled.set_pressed_no_signal(config["enabled"])
		crop.disabled = not may_edit or not (Plan.growing_site(role) or role == "seeds")
		for index in crop.item_count:
			if crop.get_item_metadata(index) == config["crop"]: crop.select(index)
		irrigation.disabled = not may_edit or not Plan.growing_site(role)
		irrigation.set_pressed_no_signal(config["irrigation"])
		markers.set_pressed_no_signal(preview.show_status)
		pause.set_pressed_no_signal(preview.paused)
	var text: String = preview.kit_status()
	if not item.is_empty() and preview.sites.has(item["uid"]):
		text += "\n" + preview.status(item["uid"])
		if config["irrigation"]:
			var water: Node = preview.water_network
			var supplied: int = water.served(item["uid"]) if is_instance_valid(water) and water.graph.get("enabled", false) else 0
			text += "\nWater allocation %d units per tick." % supplied
	if not preview.notice.is_empty(): text += "\n" + preview.notice
	if readout.text != text: readout.text = text

func apply_settings() -> void:
	if not editable() or not studio.shared_authority():
		status.text = "Use the city editor or ask the co-op host to change the garden setting."
		return
	var doc: RefCounted = studio.current()
	var updated: Dictionary = doc.data.duplicate(true)
	var config: Dictionary = updated.get("garden", {})
	config["enabled"] = enabled.button_pressed
	updated["garden"] = config
	commit(doc, updated, "City garden setting saved.")

func apply_site() -> void:
	var item: Dictionary = selected()
	if item.is_empty(): return
	var doc: RefCounted = studio.current()
	if not Layers.editable(doc.data, item, studio.library): return
	var updated: Dictionary = doc.data.duplicate(true)
	for entry in updated["objects"]:
		if entry["uid"] != item["uid"]: continue
		var config: Dictionary = entry.get("garden", {})
		config.merge({"enabled":site_enabled.button_pressed, "crop":crop.get_item_metadata(crop.selected),
			"irrigation":not irrigation.disabled and irrigation.button_pressed}, true)
		entry["garden"] = config
	var sites: Dictionary = Plan.compile(updated, studio.library, true)
	if site_enabled.button_pressed:
		if not sites.has(item["uid"]) or Plan.selected_records(updated).size() > Plan.MAX_SITES:
			status.text = "The garden site limit has been reached."
			return
		if not sites[item["uid"]]["reason"].is_empty():
			status.text = sites[item["uid"]]["reason"]
			return
	commit(doc, updated, "Garden site saved. Undo restores the previous setting.")

func commit(doc: RefCounted, updated: Dictionary, message: String) -> void:
	var content: Dictionary = Palette.check(doc.data, updated, studio.library)
	if not content["ok"]:
		status.text = content["reason"]
		return
	var session: Node = studio.cooperative_tools.session
	if session.connected and session.role == "client":
		var before: Dictionary = studio.cooperative_tools.snapshot()
		var after: Dictionary = before.duplicate(true)
		after[studio.mode] = updated
		var reason: String = Protection.allowed(before, after, session.local_id, studio.library)
		if not reason.is_empty():
			status.text = reason
			return
	if doc.data == updated:
		status.text = "No garden setting changed."
		return
	studio.finish_edit(studio.canvas_pointer())
	doc.checkpoint()
	doc.data = updated
	studio.changed()
	doc.finish_checkpoint(true)
	status.text = message
	stamp = -1
	refresh()

func reset() -> void:
	for mode in studio.worlds:
		studio.worlds[mode].exploration.garden.reset()
	stamp = -1
