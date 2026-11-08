extends RefCounted

const ACTIONS: Array = [
	["Select / move objects", "tool", "select"], ["Place an asset", "tool", "place"],
	["Erase objects", "tool", "erase"], ["Paint colors and tiles", "tool", "color"],
	["Draw connected roads", "tool", "road"], ["Add or remove crossing", "tool", "crossing"],
	["Erase roads", "tool", "road_erase"], ["Align cars in lanes", "align_cars", null],
	["Align buildings", "align_buildings", null], ["Snap chosen anchors to grid", "align_grid", null],
	["Undo", "undo", null], ["Redo", "redo", null], ["Duplicate selection", "duplicate", null],
	["Remove selection", "remove", null], ["Group selection", "group", null],
	["Ungroup selection", "ungroup", null], ["Save assembly", "assembly_save", null],
	["Browse assemblies", "assemblies", null], ["Create snapshot", "snapshot", null],
	["Browse projects and recovery", "open", null], ["Open project file", "open_file", null],
	["Save project", "save", null], ["Save project as", "save_as", null],
	["Export runnable scene", "export", null], ["Export portable Godot project ZIP", "export_portable", null], ["Reset camera", "home", null],
	["Next overlapping object", "overlap_next", null], ["Choose object under pointer", "overlap_list", null],
	["Frame selected props", "small_props_focus", null], ["Magnify selected props", "small_props_magnify", null],
	["Isolate selection temporarily", "small_props_isolate", null], ["Return to previous editing view", "small_props_return", null],
	["Building workspace", "workspace_preset", "building"], ["Painting workspace", "workspace_preset", "painting"],
	["Exploring workspace", "workspace_preset", "exploring"], ["Custom workspace", "workspace_preset", "custom"],
	["Toggle canvas focus", "focus_canvas", null], ["Controls and shortcuts", "controls", null],
	["Search asset library", "asset_search", null],
	["Open supplemental asset showcase", "supplemental_showcase", null],
	["Open SWAT compound example", "swat_showcase", null],
	["Accessibility settings", "accessibility", null],
	["Guided first build", "first_build", null],
	["Citizens and daily routines", "citizens", null],
	["Schools and pupil schedules", "schools", null],
	["Resident interior activities and stations", "resident_activities", null],
	["Traffic signs, signals and parking", "traffic", null],
	["Vehicle fleets and weights", "vehicle_fleets", null],
	["Businesses and activities", "businesses", null],
	["City services and crews", "services", null],
	["Economy, budgets and treasury", "economy", null],
	["Construction costs and rendering comparison", "construction_costs", null],
	["Scenario challenges and goals", "challenges", null],
	["Emergency training, fire and medical drills", "challenges", "fire_drill"],
	["Cooperative building, sessions and protected areas", "cooperative", null],
	["Creation sharing, publish gallery and import downloads", "creation_sharing", null],
	["Import custom sprite or model asset", "import_asset", null],
	["Blueprint planning and deferred construction", "blueprints", null],
	["Modular socket snapping", "connectors", null],
	["Next connection target", "connector_next", null],
	["Previous connection target", "connector_previous", null],
	["Zoning and gradual development", "zoning", null],
	["Public transit routes and timetables", "transit", null],
	["Terrain and water sculpting", "terrain", null],
	["Modular rooms and openings", "modular_rooms", null],
	["Community gardens and greenhouses", "garden", null],
	["Kitchen recipes and stations", "cooking", null],
	["Laundry services and stations", "laundry", null],
	["Fitness and sports bookings", "fitness", null],
	["Playable arcade cabinets", "arcade", null],
	["Camping visits and shelters", "camping", null],
	["Village production, farms and markets", "village", null],
	["Pet companionship and dog stations", "pet", null],
	["Cycling, scooters and bicycle racks", "cycling", null],
	["Boating, harbors and docks", "harbors", null],
	["Space outpost and supply ships", "space_outpost", null],
	["Connected ground families", "ground_families", null],
	["Generate procedural neighborhood blocks", "neighborhood", null],
	["Environmental audio and localized sounds", "ambience", null],
	["Mute or unmute ambience", "ambience_mute", null],
	["Weather, seasons, rain, snow and wind", "weather", null],
	["Usable furniture, props, switches and appliances", "props", null],
	["Interaction setup diagnostics: approach, capacity, target and return", "interaction_setup", null],
	["Simulation diagnostics · routes, coverage and queues", "simulation_diagnostics", null],
	["Water network · pipes, storage and demand", "water", null],
	["Power network · generation, batteries and demand", "power", null],
	["Drive vehicles, steering and brakes", "driving", null],
	["Vehicle care · fuel, charging and repair", "vehicle_care", null],
	["Local deliveries · shops, contracts and cargo", "deliveries", null],
	["Market days · stalls, queues and stock", "markets", null],
	["Photo mode, camera bookmarks, depth of field and cinematic paths", "photo", null],
	["Move canvas handles", "handles_mode", "move"], ["Rotate canvas handles", "handles_mode", "rotate"],
	["Resize canvas handles", "handles_mode", "resize"], ["Hide canvas handles", "handles_mode", "off"],
	["Copy selection", "copy", null], ["Paste selection", "paste", null],
	["Rotate clockwise", "rotate", null], ["Rotate counterclockwise", "rotate_ccw", null],
	["Toggle keyboard canvas cursor", "cursor_toggle", null],
	["Use tool at canvas cursor", "cursor_click", null], ["Start or finish canvas drag", "cursor_drag", null],
	["Zoom in", "zoom_in", null], ["Zoom out", "zoom_out", null],
	["Orbit camera left", "orbit_left", null], ["Orbit camera right", "orbit_right", null],
	["Toggle day and night", "night", null], ["Walk / return to building", "walk", null],
	["Switch to 2D world", "dimension", 0], ["Switch to 3D world", "dimension", 1]
]
var studio: Control
var dialog: AcceptDialog
var query: LineEdit
var results: ItemList
var matches: Array = []

func _init(owner_control: Control) -> void:
	studio = owner_control
	dialog = AcceptDialog.new()
	dialog.title = "Commands · Ctrl+Shift+P"
	dialog.min_size = Vector2i(550, 410)
	dialog.get_ok_button().text = "Run command"
	studio.add_child(dialog)
	var box := VBoxContainer.new()
	dialog.add_child(box)
	query = LineEdit.new()
	query.placeholder_text = "Search actions, e.g. align cars or create snapshot"
	query.clear_button_enabled = true
	box.add_child(query)
	results = ItemList.new()
	results.custom_minimum_size = Vector2(520, 300)
	results.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(results)
	query.text_changed.connect(func(_text: String): refresh())
	query.text_submitted.connect(func(_text: String): execute())
	query.gui_input.connect(navigate)
	results.item_activated.connect(func(_index: int): execute())
	dialog.confirmed.connect(execute)

func show() -> void:
	query.text = ""
	refresh()
	dialog.popup_centered()
	query.grab_focus()

func refresh() -> void:
	results.clear()
	matches.clear()
	var words: PackedStringArray = query.text.to_lower().split(" ", false)
	for action in ACTIONS:
		var included: bool = true
		for word in words:
			if not word in action[0].to_lower(): included = false; break
		if included:
			matches.append(action)
			results.add_item(action[0])
	if results.item_count: results.select(0)
	dialog.get_ok_button().disabled = matches.is_empty()

func navigate(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or not event.keycode in [KEY_UP, KEY_DOWN] or matches.is_empty(): return
	var selected: PackedInt32Array = results.get_selected_items()
	var index: int = selected[0] if not selected.is_empty() else 0
	results.select(clampi(index + (-1 if event.keycode == KEY_UP else 1), 0, matches.size() - 1))
	results.ensure_current_is_visible()
	query.accept_event()

func execute() -> void:
	var selected: PackedInt32Array = results.get_selected_items()
	if selected.is_empty(): return
	var action: Array = matches[selected[0]]
	dialog.hide()
	query.release_focus()
	if studio.control_settings and (str(action[1]).begins_with("cursor_") or action[1] in ["asset_search","copy","paste","zoom_in","zoom_out","orbit_left","orbit_right"]): studio.control_settings.execute(action[1])
	else: studio._command(action[1], action[2])
