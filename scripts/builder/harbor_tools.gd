extends RefCounted

const Plan = preload("res://scripts/builder/harbor_plan.gd")
const Document = preload("res://scripts/builder/document.gd")
const Palette = preload("res://scripts/builder/asset_palette_policy.gd")
const Repair = preload("res://scripts/builder/repair_assets.gd")

var studio: Control
var panel := ScrollContainer.new()
var enabled := CheckButton.new()
var pilot := OptionButton.new()
var shuttle := OptionButton.new()
var origin := OptionButton.new()
var destination := OptionButton.new()
var interval: SpinBox
var apply: Button
var dock_apply: Button
var dock_remove: Button
var practice: Button
var dock_title: Label
var status: Label
var offsets: Array[SpinBox] = []
var dock_controls: Array[Control] = []
var signature: int = -1

func _init(host: Control) -> void:
	studio = host
	panel.name = "Harbors"
	panel.follow_focus = true
	panel.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	studio.workspace_layout.tabs.add_child(panel)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 7)
	panel.add_child(column)
	label(column, "Boating and harbors", 17)
	status = label(column, "", 13)
	status.focus_mode = Control.FOCUS_ALL
	status.accessibility_name = "Harbor validation"
	practice = button(column, "Build a practice harbor", build_practice)
	button(column, "Open Terrain tools", func(): studio._command("terrain", null))
	button(column, "Choose the trireme", func(): choose_asset(Plan.VESSEL))
	button(column, "Choose a pier", func(): choose_asset(Plan.PIER))
	label(column, "The practice harbor needs a blank city. It adds four docks, a boat you can steer, and a ferry between two docks.", 12)
	enabled.text = "Enable harbor preview"
	enabled.clip_text = true
	column.add_child(enabled)
	add_choice(column, pilot, "Pilot boat")
	add_choice(column, shuttle, "Scheduled ferry")
	add_choice(column, origin, "Ferry origin")
	add_choice(column, destination, "Ferry destination")
	interval = field(column, "Stop interval in seconds", 10, 300, 1, 30)
	apply = button(column, "Apply harbor settings", save)
	label(column, "In Walk, interact from the dry landing to board. Move to steer, jump to brake, and interact beside a free berth to go ashore. The trireme uses its supplied facing. The wake shows travel direction.", 12)
	dock_title = label(column, "Choose one visible pier in the city to define its dock.", 14)
	for name in ["Landing east offset", "Landing south offset", "Berth east offset", "Berth south offset"]:
		offsets.append(field(column, name, -Plan.MAX_DOCK_REACH, Plan.MAX_DOCK_REACH, .1, 0))
		dock_controls.append(offsets[-1])
	dock_controls.append(button(column, "Use view center for landing", func(): capture_center(0)))
	dock_controls.append(button(column, "Use view center for berth", func(): capture_center(2)))
	dock_apply = button(column, "Apply selected pier’s dock", save_dock)
	dock_remove = button(column, "Remove selected pier’s dock", remove_dock)
	dock_controls.append(dock_apply)
	dock_controls.append(dock_remove)
	label(column, "Offsets are in terrain metres from the pier’s placement point. The landing needs a dry, clear bank. The berth needs connected, deep water beside it. Park the assigned boat at its starting berth in Build.", 12)

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

func field(parent: Node, caption: String, low: float, high: float, step: float, value: float) -> SpinBox:
	label(parent, caption, 12)
	var result: SpinBox = studio.spin(parent, low, high, step, value)
	result.accessibility_name = caption
	return result

func add_choice(parent: Node, control: OptionButton, caption: String) -> void:
	label(parent, caption, 12)
	control.accessibility_name = caption
	control.fit_to_longest_item = false
	control.clip_text = true
	parent.add_child(control)

func show() -> void:
	studio.workspace_presets.set_focus(false)
	if studio.walking: studio.set_walking(false)
	if studio.get_viewport_rect().size.x < 1200 and not studio.consumer_shell.active:
		studio.workspace_layout.library_toggle.button_pressed = false
	studio.workspace_layout.inspector_toggle.button_pressed = true
	studio.workspace_layout.tabs.current_tab = panel.get_index()
	studio.workspace_layout.tabs.get_tab_bar().call_deferred("ensure_tab_visible", panel.get_index())
	signature = -1
	refresh()
	(practice if not practice.disabled else status).grab_focus()

func can_edit() -> bool:
	return studio.shared_authority() and not studio.walking and not studio.interior_tools.editing() 		and not studio.current().data.get("interior_room", false)

func selected_pier() -> Dictionary:
	var items: Array = studio.selection_items()
	return items[0] if items.size() == 1 and items[0]["asset"] == Plan.PIER else {}

func choose_asset(id: String) -> void:
	if not Repair.available(id, studio.library, {}):
		status.text = "This harbor asset is unavailable."
		return
	studio.select_asset(id)

func choice(control: OptionButton) -> String:
	return str(control.get_item_metadata(control.selected)) if control.selected >= 0 else ""

func item_name(item: Dictionary) -> String:
	var position: Vector2 = Plan.Traffic.metric(item["position"], studio.mode)
	return "%s · %.1f, %.1f" % [item.get("name", studio.library.assets[item["asset"]]["name"]), position.x, position.y]

func fill(control: OptionButton, entries: Array, selected: String) -> void:
	control.clear()
	control.add_item("None")
	control.set_item_metadata(0, "")
	for item in entries:
		control.add_item(item_name(item))
		control.set_item_metadata(control.item_count - 1, item["uid"])
		if item["uid"] == selected: control.select(control.item_count - 1)
	if control.selected < 0: control.select(0)

func blank(data: Dictionary) -> bool:
	for key in ["objects", "roads", "tiles", "terrain_vertices", "water_cells"]:
		if not data.get(key, []).is_empty(): return false
	return data.get("protected_areas", []).is_empty()

func refresh() -> void:
	var data: Dictionary = studio.current().data
	var config: Dictionary = Plan.settings(data)
	var pier: Dictionary = selected_pier()
	var allowed: bool = can_edit()
	var fingerprint: int = hash([studio.mode, config, data.get("objects", []), data.get("terrain", {}),
		data.get("water_cells", []), data.get("terrain_vertices", []), data.get("layers", {}), pier.get("uid"), allowed])
	if fingerprint == signature: return
	signature = fingerprint
	var by_uid: Dictionary = {}
	var vessels: Array = []
	for item in data["objects"]:
		if not studio.library.assets.has(item["asset"]): continue
		by_uid[item["uid"]] = item
		if not Plan.hull(item).is_empty(): vessels.append(item)
	var docks: Array = []
	var selected: Dictionary = {}
	for dock in config["docks"]:
		var anchor: Dictionary = by_uid.get(dock["anchor"], {})
		if not anchor.is_empty(): docks.append(anchor)
		if dock["anchor"] == pier.get("uid", ""): selected = dock
	fill(pilot, vessels, config["pilot"])
	fill(shuttle, vessels, config["shuttle"])
	fill(origin, docks, config["origin"])
	fill(destination, docks, config["destination"])
	enabled.set_pressed_no_signal(config["enabled"])
	interval.set_value_no_signal(config["interval"])
	for control in [enabled, pilot, shuttle, origin, destination, apply]: control.disabled = not allowed
	interval.editable = allowed
	practice.disabled = not allowed or not blank(data)
	dock_title.text = "Selected pier · " + item_name(pier) if not pier.is_empty() else "Choose one visible, unlocked pier to define its dock."
	var values: Array = selected.get("land", [0, 0]) + selected.get("water", [0, 0])
	for index in offsets.size(): offsets[index].set_value_no_signal(values[index])
	for control in dock_controls:
		if control is SpinBox: control.editable = allowed and not pier.is_empty()
		else: control.disabled = not allowed or pier.is_empty()
	dock_remove.disabled = dock_remove.disabled or selected.is_empty()
	status.text = describe(data, config) if allowed else "The host configures harbors in exterior Build."

func capture_center(index: int) -> void:
	var pier: Dictionary = selected_pier()
	if pier.is_empty(): return
	var values: Array = studio.worlds[studio.mode].point(studio.canvas.size * .5, false, 0)
	var at: Vector2 = Plan.Traffic.metric(values, studio.mode) - Plan.Traffic.metric(pier["position"], studio.mode)
	if maxf(absf(at.x), absf(at.y)) > Plan.MAX_DOCK_REACH:
		status.text = "Move the view center within twelve metres of the pier."
		return
	offsets[index].value = at.x
	offsets[index + 1].value = at.y

func save() -> void:
	if not can_edit(): return
	var next: Dictionary = Plan.settings(studio.current().data).duplicate(true)
	next.merge({"enabled": enabled.button_pressed, "pilot": choice(pilot), "shuttle": choice(shuttle),
		"origin": choice(origin), "destination": choice(destination), "interval": int(interval.value)}, true)
	if not Plan.valid(next):
		status.text = "Assign different boats for piloting and ferry service."
		return
	commit_settings(next)

func save_dock() -> void:
	if not can_edit(): return
	var pier: Dictionary = selected_pier()
	if pier.is_empty(): return
	var next: Dictionary = Plan.settings(studio.current().data).duplicate(true)
	var docks: Array = next["docks"].filter(func(dock: Dictionary) -> bool: return dock["anchor"] != pier["uid"])
	docks.append({"anchor": pier["uid"], "land": [offsets[0].value, offsets[1].value], "water": [offsets[2].value, offsets[3].value]})
	next["docks"] = docks
	if not Plan.valid(next):
		status.text = "This city supports up to sixteen dock definitions."
		return
	if commit_settings(next):
		var data: Dictionary = studio.current().data
		var socket: Dictionary = Plan.socket(Plan.compile(data, studio.library), data, docks.back(),
			Plan.hull({"asset": Plan.VESSEL, "scale": .3}))
		status.text = "Dock saved · berth and landing clear for the practice trireme." if socket["ok"] else "Dock saved · " + socket["reason"]

func remove_dock() -> void:
	if not can_edit(): return
	var id: String = selected_pier().get("uid", "")
	if id.is_empty(): return
	var next: Dictionary = Plan.settings(studio.current().data).duplicate(true)
	next["docks"] = next["docks"].filter(func(dock: Dictionary) -> bool: return dock["anchor"] != id)
	for key in ["origin", "destination"]:
		if next[key] == id: next[key] = ""
	commit_settings(next)

func commit_settings(config: Dictionary) -> bool:
	var candidate: Dictionary = studio.current().data.duplicate(true)
	candidate["harbor"] = config
	return commit(candidate)

func commit(candidate: Dictionary) -> bool:
	studio.finish_edit(studio.canvas_pointer())
	var doc: RefCounted = studio.current()
	doc.finish_checkpoint()
	var before: Dictionary = doc.data.duplicate(true)
	var policy: Dictionary = Palette.check(before, candidate, studio.library)
	if not policy["ok"]:
		status.text = policy["reason"]
		return false
	doc.data = candidate
	var accepted: bool = doc.record_completed_change(before)
	if accepted: doc.economy_error = ""
	studio.changed()
	signature = -1
	refresh()
	if not accepted and not doc.economy_error.is_empty(): status.text = doc.economy_error
	return accepted

func describe(data: Dictionary, config: Dictionary) -> String:
	if not config["enabled"]: return "Harbor preview is off."
	var network: Dictionary = Plan.compile(data, studio.library)
	if not network["ok"]: return network["reason"]
	var notes := PackedStringArray()
	var boat: Dictionary = network["items"].get(config["pilot"], {})
	var hull: Dictionary = Plan.hull(boat)
	if not hull.is_empty():
		var point: Vector2 = Plan.Traffic.metric(boat["position"], studio.mode)
		for record in config["docks"]:
			var dock: Dictionary = Plan.socket(network, data, record, hull)
			if Plan.moored_at(network, point, dock, hull):
				notes.append("Pilot boat ready at a dock.")
				break
		if notes.is_empty(): notes.append("Place the pilot boat beside a clear berth.")
	var ferry: Dictionary = network["items"].get(config["shuttle"], {})
	hull = Plan.hull(ferry)
	if not hull.is_empty():
		var from: Dictionary = {}
		var to: Dictionary = {}
		for record in config["docks"]:
			if record["anchor"] == config["origin"]: from = Plan.socket(network, data, record, hull)
			if record["anchor"] == config["destination"]: to = Plan.socket(network, data, record, hull)
		if config["origin"] == config["destination"] or from.is_empty() or to.is_empty():
			notes.append("Choose two different ferry docks.")
		elif not from["ok"] or not to["ok"]:
			notes.append(from["reason"] if not from["ok"] else to["reason"])
		else:
			var point: Vector2 = Plan.Traffic.metric(ferry["position"], studio.mode)
			if not Plan.moored_at(network, point, from, hull):
				notes.append("Place the ferry beside its origin berth.")
			else:
				var route: Dictionary = Plan.route(network, from, to, hull)
				notes.append("Ferry route ready." if route["ok"] else route["reason"])
	return "Assign a trireme to pilot or to a ferry route." if notes.is_empty() else " ".join(notes)

static func practice_layout(source: Dictionary) -> Dictionary:
	var result: Dictionary = source.duplicate(true)
	var mode: String = result["mode"]
	var terrain: Dictionary = result.get("terrain", {}).duplicate(true)
	terrain.merge({"enabled": true, "bounds": [-7, -7, 24, 20]}, true)
	result["terrain"] = terrain
	var water: Array = []
	for x in 10:
		for z in 6:
			if x in [4, 5] and z in [2, 3]: continue
			water.append({"cell": [x, z], "level": 1.25})
	result["water_cells"] = water
	var config: Dictionary = Plan.settings({})
	config.merge({"enabled": true, "pilot": "harbor_pilot", "shuttle": "harbor_ferry",
		"origin": "harbor_east", "destination": "harbor_north", "interval": 10}, true)
	for spec in [["west", 3, -1.35, 1], ["east", 17, -1.35, 1], ["north", 11, 13.35, 11], ["south", 11, -1.35, 1]]:
		var id: String = "harbor_" + spec[0]
		var anchor := Vector2(spec[1] + 1.6, spec[2])
		var item: Dictionary = Document.placement_item(id, Plan.PIER, Plan.Traffic.world(anchor, mode), "View_01", .55)
		item["name"] = spec[0].capitalize() + " Pier"
		result["objects"].append(item)
		config["docks"].append({"anchor": id, "land": [-1.6, 0], "water": [-1.6, float(spec[3]) - anchor.y]})
	for spec in [["harbor_pilot", 3, "Pilot trireme"], ["harbor_ferry", 17, "Harbor ferry"]]:
		var item: Dictionary = Document.placement_item(spec[0], Plan.VESSEL,
			Plan.Traffic.world(Vector2(spec[1], 1), mode, 1.25), "SE", .3)
		item["name"] = spec[2]
		result["objects"].append(item)
	result["spawn"] = Plan.Traffic.world(Vector2(2.7, -1.35), mode, .025 if mode == "3d" else 0.0)
	result["harbor"] = config
	return result

func build_practice() -> void:
	if not can_edit() or not blank(studio.current().data): return
	for id in [Plan.VESSEL, Plan.PIER]:
		if not Repair.available(id, studio.library, {}):
			status.text = "The practice harbor needs the supplied transparent trireme and pier."
			return
	var draft: Dictionary = practice_layout(studio.current().data)
	var summary: String = describe(draft, draft["harbor"])
	if not "Pilot boat ready" in summary or not "Ferry route ready" in summary:
		status.text = summary
		return
	if not commit(draft): return
	var world: Node = studio.worlds[studio.mode]
	var spawn: Array = draft["spawn"]
	world.player.teleport_to(Vector2(spawn[0], spawn[1]) if studio.mode == "2d" else Vector3(spawn[0], spawn[1], spawn[2]))
	studio.neighborhood_tools.frame(studio.worlds[studio.mode], Rect2(-2, -4, 24, 21), Vector2i(studio.canvas.size))
	status.text = "Practice harbor ready. Enter Walk and use the west landing to board. The ferry runs between east and north."
