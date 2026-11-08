extends RefCounted

const Plan = preload("res://scripts/builder/space_outpost_plan.gd")

var studio: Control
var panel := ScrollContainer.new()
var status: Label
var practice: Button
var select_marker: Button
var enabled := CheckButton.new()
var orbital := CheckButton.new()
var interval: SpinBox
var heading := OptionButton.new()
var apply: Button
var save_dock: Button
var remove_dock: Button
var cached: Array = []

func _init(host: Control) -> void:
	studio = host
	panel.name = "Space Outpost"
	panel.follow_focus = true
	panel.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	studio.workspace_layout.tabs.add_child(panel)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 7)
	panel.add_child(column)
	label(column, "Space outpost", 17)
	status = label(column, "", 13)
	status.focus_mode = Control.FOCUS_ALL
	status.accessibility_name = "Space outpost validation"
	practice = button(column, "Build practice site", build_practice)
	label(column, "Start on a blank exterior. Walk from the cargo marker to watch scheduled supply ships land, unload and depart. Leave the approach clear.", 12)
	enabled.text = "Enable supply schedule"
	enabled.clip_text = true
	column.add_child(enabled)
	orbital.text = "Show a scenery satellite"
	orbital.clip_text = true
	column.add_child(orbital)
	label(column, "Seconds between shipments", 12)
	interval = studio.spin(column, 12, 180, 1, 24)
	interval.accessibility_name = "Seconds between shipments"
	apply = button(column, "Apply schedule", save)
	select_marker = button(column, "Choose cargo marker", func(): studio.select_asset(Plan.definitions()["dock"]))
	label(column, "Select a placed cargo marker and choose the direction of its approach strip.", 12)
	heading.accessibility_name = "Landing approach direction"
	heading.fit_to_longest_item = false
	heading.clip_text = true
	for caption in ["South (+Z)", "East (+X)", "North (−Z)", "West (−X)"]: heading.add_item(caption)
	column.add_child(heading)
	save_dock = button(column, "Assign dock", func(): edit_dock(true))
	remove_dock = button(column, "Remove dock", func(): edit_dock(false))
	for profile in Plan.definitions()["ships"]:
		var id: String = profile["asset"]
		if not studio.library.assets.has(id): continue
		var row := HBoxContainer.new()
		column.add_child(row)
		var picture := TextureRect.new()
		picture.texture = studio.library.icon(id)
		picture.custom_minimum_size = Vector2(48, 48)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(picture)
		label(row, studio.library.assets[id]["name"], 12).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label(column, "Supply ships are scripted exterior visits. The satellite is scenery. Walk around the outpost and watch from the dock’s clear observation point.", 12)

func label(parent: Node, text: String, size: int) -> Label:
	var result: Label = studio.label(parent, text, size)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return result

func button(parent: Node, text: String, callback: Callable) -> Button:
	var result := Button.new()
	result.text = text
	result.clip_text = true
	result.pressed.connect(callback)
	parent.add_child(result)
	return result

func show() -> void:
	studio.workspace_presets.set_focus(false)
	if studio.walking: studio.set_walking(false)
	if studio.get_viewport_rect().size.x < 1200 and (not studio.consumer_shell or not studio.consumer_shell.active):
		studio.workspace_layout.library_toggle.button_pressed = false
		studio.workspace_layout.inspector_toggle.button_pressed = true
	studio.workspace_layout.tabs.current_tab = panel.get_index()
	studio.workspace_layout.tabs.get_tab_bar().call_deferred("ensure_tab_visible", panel.get_index())
	cached.clear()
	refresh()
	(practice if not practice.disabled else status).grab_focus()

func can_edit() -> bool:
	return studio.shared_authority() and not studio.walking and not studio.interior_tools.editing() and not studio.current().data.get("interior_room", false)

func selected_marker() -> String:
	var items: Array = studio.selection_items()
	if items.size() != 1 or items[0]["asset"] != Plan.definitions()["dock"]: return ""
	return items[0]["uid"]

func refresh() -> void:
	var data: Dictionary = studio.current().data
	var config: Dictionary = Plan.settings(data)
	var marker: String = selected_marker()
	var editable: bool = can_edit()
	var current: Array = [studio.mode, config, marker, editable, data.get("objects"), data.get("roads"), data.get("tiles"),
		data.get("protected_areas"), data.get("terrain"), data.get("terrain_vertices"), data.get("water_cells"), data.get("layers")]
	if current == cached: return
	cached = current.duplicate(true)
	enabled.set_pressed_no_signal(config["enabled"])
	orbital.set_pressed_no_signal(config["orbital"])
	interval.set_value_no_signal(config["interval"])
	var selected: int = 0
	var assigned: bool = false
	for dock in config["docks"]:
		if dock["anchor"] == marker:
			selected = int(dock["heading"])
			assigned = true
			break
	heading.select(selected)
	for control in [enabled, orbital, apply, select_marker]: control.disabled = not editable
	interval.editable = editable
	heading.disabled = not editable or marker.is_empty()
	save_dock.disabled = heading.disabled
	remove_dock.disabled = heading.disabled or not assigned
	practice.disabled = not editable or not Plan.blank(data)
	if not editable: status.text = "The host configures the outpost in exterior Build."
	elif not config["enabled"]: status.text = "Supply schedule is off."
	else:
		var plan: Dictionary = Plan.inspect(data, studio.library)
		var rejected: Array = plan.get("rejected", {}).values()
		var valid_count: int = plan.get("docks", {}).size()
		if not plan["ok"]: status.text = plan["reason"]
		elif not rejected.is_empty(): status.text = "%d ready · %s" % [valid_count, rejected[0]]
		elif valid_count == 1: status.text = "One landing approach is clear. Enter Walk to start shipments."
		elif valid_count > 1: status.text = "%d landing approaches are clear. Enter Walk to start shipments." % valid_count
		else: status.text = "Choose and assign a cargo marker to receive ships."

func save() -> void:
	if not can_edit(): return
	var candidate: Dictionary = studio.current().data.duplicate(true)
	var config: Dictionary = Plan.settings(candidate).duplicate(true)
	config.merge({"enabled": enabled.button_pressed, "orbital": orbital.button_pressed, "interval": int(interval.value)}, true)
	candidate["space_outpost"] = config
	commit(candidate)

func edit_dock(add: bool) -> void:
	var marker: String = selected_marker()
	if not can_edit() or marker.is_empty(): return
	var candidate: Dictionary = studio.current().data.duplicate(true)
	var config: Dictionary = Plan.settings(candidate).duplicate(true)
	var docks: Array = config["docks"].filter(func(dock: Dictionary) -> bool: return dock["anchor"] != marker)
	if add: docks.append({"anchor": marker, "heading": heading.selected})
	config["docks"] = docks
	if not Plan.valid(config):
		status.text = "Up to four cargo markers can be assigned as docks."
		return
	candidate["space_outpost"] = config
	commit(candidate)

func commit(candidate: Dictionary) -> bool:
	studio.finish_edit(studio.canvas_pointer())
	var doc: RefCounted = studio.current()
	doc.finish_checkpoint()
	var before: Dictionary = doc.data.duplicate(true)
	doc.data = candidate
	var accepted: bool = doc.record_completed_change(before)
	if accepted: doc.economy_error = ""
	studio.changed()
	cached.clear()
	refresh()
	if not accepted and not doc.economy_error.is_empty(): status.text = doc.economy_error
	return accepted

func build_practice() -> void:
	if not can_edit(): return
	var draft: Dictionary = Plan.practice(studio.current().data, studio.library)
	if not draft["ok"]:
		status.text = draft["reason"]
		return
	if not commit(draft["data"]): return
	var world: Node = studio.worlds[studio.mode]
	var spawn: Array = draft["data"]["spawn"]
	world.player.teleport_to(Vector2(spawn[0], spawn[1]) if studio.mode == "2d" else Vector3(spawn[0], spawn[1], spawn[2]))
	studio.neighborhood_tools.frame(world, Rect2(-16, -14, 28, 46), Vector2i(studio.canvas.size))
	status.text = "Outpost ready. Enter Walk to watch the first shipment."
