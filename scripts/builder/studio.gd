extends "res://scripts/builder/studio_base.gd"

const Layers = preload("res://scripts/builder/layers.gd")
const Roads = preload("res://scripts/builder/roads.gd")
const Store = preload("res://scripts/builder/project_store.gd")
const Bounds = preload("res://scripts/model_bounds.gd")
const Rotation = preload("res://scripts/builder/rotation.gd")
const Factory = preload("res://scripts/builder/asset_instance.gd")
const GridFit = preload("res://scripts/builder/grid_fit.gd")
var command_palette: RefCounted
var scene_outliner: RefCounted
var arrange_tools: RefCounted
var connector_tools: RefCounted
var ground_brush: RefCounted
var road_settings: RefCounted
var placement_hint: Label
var angle_input: SpinBox
var pitch_input: SpinBox
var roll_input: SpinBox
var rotation_controls: RefCounted
var rotation_step: SpinBox
var view_choice: OptionButton
var compass_panel: VBoxContainer
var compass_buttons: Dictionary = {}
var compass_caption: Label
var compass_view_yaw: float = INF
var rotation_manual: bool = false
var color_editor: RefCounted
var appearance_tools: RefCounted
var entrance_tools: RefCounted
var interior_tools: RefCounted
var placement_angle: float = 0
var placement_tilt := Vector2.ZERO
var enhancements_ready: bool = false
var selected_uids: Array[String] = []
var clipboard: Array = []
var clipboard_connections: Array = []
var clipboard_utility: Dictionary = {}
var clipboard_mode: String = ""
var drag_origins: Dictionary = {}
var marquee_active: bool = false
var marquee_additive: bool = false
var road_last: Vector2i
var road_drawing: bool = false
var overlay: Control
var orientation: Control
var surface_input: CheckBox
var lanes_input: CheckBox
var road_choice: OptionButton
var mode_badge: Label
var mode_library: Control
var mode_inspector: Control
var mode_road_bar: Control
var mode_template_bar: Control
var mode_edit_controls: Array[Control] = []
var save_badge: Label
var layer_rows: Dictionary = {}
var assign_layer: OptionButton
var browser: AcceptDialog
var project_list: ItemList
var browser_entries: Array = []
var name_dialog: ConfirmationDialog
var name_field: LineEdit
var name_action: String = "snapshot"
var assembly_dialog: AcceptDialog
var assembly_list: ItemList
var assemblies: Array = []
var assembly_active: Dictionary = {}
var assembly_ghosts: Array[Node] = []
var workspace: Dictionary = {}
var pending_workspace: Dictionary = {}
var saved_digest: String = ""
var serializing_metadata: bool = false
var asset_bounds: Dictionary = {}
var recovery_elapsed: float = 0
var workspace_elapsed: float = 0
var recovery_digest: String = ""
var project_id: String = Store.new_id()
var project_origin_path: String = ""
var recovery_filter: OptionButton
var recovery_caption: Label
var recovery_details: Label
var repair_tools: RefCounted
var workspace_layout: RefCounted
var selection_inspector: RefCounted
var asset_browser: RefCounted
var overlap_picker: RefCounted
var small_prop_tools: RefCounted
var editor_feedback: RefCounted
var workspace_presets: RefCounted
var control_settings: RefCounted
var accessibility_settings: RefCounted
var first_build: RefCounted
var companion_tools: RefCounted
var palette_loading: bool=false
var project_palette_document=preload("res://scripts/builder/project_palette_document.gd").new()
var transform_handles: RefCounted
var citizen_tools: RefCounted
var school_tools: RefCounted
var traffic_tools: RefCounted
var business_tools: RefCounted
var service_tools: RefCounted
var economy_tools: RefCounted
var construction_cost_tools: RefCounted
var scenario_tools: RefCounted
var simulation_diagnostic_tools: RefCounted
var utility_tools: RefCounted
var power_tools: RefCounted
var zone_tools: RefCounted
var transit_tools: RefCounted
var terrain_tools: RefCounted
var modular_building_tools: RefCounted
var garden_tools: RefCounted
var cooking_tools: RefCounted
var laundry_tools: RefCounted
var fitness_tools: RefCounted
var arcade_tools: RefCounted
var camping_tools: RefCounted
var pet_tools: RefCounted
var cycling_tools: RefCounted
var harbor_tools: RefCounted
var outpost_tools: RefCounted
var village_tools: RefCounted
var neighborhood_tools: RefCounted
var ambience_tools: RefCounted
var weather_tools: RefCounted
var prop_tools: RefCounted
var driving_tools: RefCounted
var delivery_tools: RefCounted
var market_tools: RefCounted
var vehicle_service_tools: RefCounted
var cooperative_tools: RefCounted
var creation_tools: RefCounted
var asset_import_tools: RefCounted
var blueprint_tools: RefCounted
var photo_tools: RefCounted
var repair_report: Dictionary = {}
var pending_repair_report: bool = false
var consumer_shell: RefCounted
var capability_elapsed: float=0

func build_interface() -> void:
	super.build_interface()
	var header: Node = dimension.get_parent()
	button(header, "Portable ZIP", "export_portable", "Export the current layout as a complete Godot project, with source assets and playable interiors")
	for child in header.get_children():
		if child is Button and child.text == "Open":
			child.text = "Projects"
			child.tooltip_text = "Recent projects, Save As, snapshots and recovery"
	var center: Node = template_choice.get_parent().get_parent()
	mode_template_bar = template_choice.get_parent()
	mode_library = search.get_parent().get_parent()
	mode_badge = label(center, "BUILD MODE · Place / select · Tab to walk", 13)
	center.move_child(mode_badge, 0)
	var row := HFlowContainer.new()
	center.add_child(row)
	center.move_child(row, 2)
	road_choice = OptionButton.new()
	for title in ["Road tools…", "Draw roads", "Add / remove crossing", "Remove roads"]: road_choice.add_item(title)
	road_choice.item_selected.connect(func(index: int):
		if index > 0: _command("tool", ["select", "road", "crossing", "road_erase"][index])
	)
	mode_road_bar = row
	row.add_child(road_choice)
	surface_input = CheckBox.new()
	surface_input.text = "Surface snap"
	surface_input.tooltip_text = "Place 3D objects on floors and tabletops under the pointer"
	surface_input.button_pressed = true
	row.add_child(surface_input)
	lanes_input = CheckBox.new()
	lanes_input.text = "Car lane snap"
	lanes_input.tooltip_text = "Align cars with the nearest road lane, including starter roads"
	lanes_input.button_pressed = true
	row.add_child(lanes_input)
	button(row, "Align cars", "align_cars", "Center selected cars in road lanes; with no selection, align visible unlocked cars. Undo restores their positions.")
	button(row, "Align buildings", "align_buildings", "Align adjoining calibrated building rows. Select at least three buildings, or deselect to detect rows. Undo restores positions.")
	save_badge = label(center, "Autosave ready", 12)
	center.move_child(save_badge, center.get_child_count() - 2)
	save_badge.modulate = Color("8daabe")
	overlay = preload("res://scripts/builder/edit_overlay.gd").new()
	canvas.add_child(overlay)
	var inspector: Node = height_input.get_parent()
	placement_hint = label(inspector, "", 12)
	placement_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	placement_hint.modulate = Color("ffdf83")
	inspector.move_child(placement_hint, selection_note.get_index() + 1)
	var panel_node: Node = inspector.get_parent()
	mode_inspector = panel_node
	panel_node.custom_minimum_size.x = 242
	panel_node.remove_child(inspector)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_node.add_child(tabs)
	var scroll := ScrollContainer.new()
	scroll.name = "Selection"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inspector)
	button(inspector, "Snap chosen anchor to grid", "align_grid", "Choose a base, edge or corner under Arrange, then snap it to grid lines. With no selection, snap visible unlocked objects. Undo restores their positions.")
	orientation = preload("res://scripts/builder/orientation.gd").new()
	inspector.add_child(orientation)
	inspector.move_child(orientation, rotation_button.get_index())
	compass_panel = VBoxContainer.new()
	inspector.add_child(compass_panel)
	inspector.move_child(compass_panel, orientation.get_index())
	compass_caption = label(compass_panel, "Model facing · screen directions", 12)
	var compass_grid := GridContainer.new()
	compass_grid.columns = 3
	compass_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	compass_panel.add_child(compass_grid)
	for facing in ["NW", "N", "NE", "W", "", "E", "SW", "S", "SE"]:
		if facing.is_empty():
			var center_label: Label = label(compass_grid, "✥", 18)
			center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			center_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			continue
		var preset: Button = button(compass_grid, facing, "compass", "Face " + facing + " on screen; keep pitch and roll", facing)
		preset.toggle_mode = true
		preset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		preset.custom_minimum_size = Vector2(52, 30)
		compass_buttons[facing] = preset
	var rotation_row := HBoxContainer.new()
	inspector.add_child(rotation_row)
	inspector.move_child(rotation_row, rotation_button.get_index() + 1)
	button(rotation_row, "↶", "rotate_ccw", "Rotate counterclockwise · Shift+R").size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button(rotation_row, "Reset", "rotate_reset", "Reset to the first supplied direction · Alt+R").size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var angles := VBoxContainer.new()
	inspector.add_child(angles)
	inspector.move_child(angles, rotation_row.get_index() + 1)
	view_choice = OptionButton.new()
	view_choice.tooltip_text = "Choose one of the supplied sprite views; Angle rotates the chosen artwork."
	angles.add_child(view_choice)
	view_choice.item_selected.connect(func(index: int): _command("source_view", view_choice.get_item_text(index)))
	var angle_row := HBoxContainer.new()
	angles.add_child(angle_row)
	var angle_caption: Label = label(angle_row, "Angle / yaw")
	angle_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	angle_input = spin(angle_row, 0, 360, 0.1, 0)
	angle_input.suffix = "°"
	angle_input.custom_minimum_size.x = 108
	angle_input.value_changed.connect(func(value: float):
		if not updating_controls: rotation_controls.set_displayed(value)
	)
	for axis in ["Pitch", "Roll"]:
		var axis_row := HBoxContainer.new()
		angles.add_child(axis_row)
		label(axis_row, axis).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var control: SpinBox = spin(axis_row, -180, 180, 0.1, 0)
		control.custom_minimum_size.x = 108
		control.suffix = "°"
		if axis == "Pitch": pitch_input = control
		else: roll_input = control
		control.value_changed.connect(func(value: float): _command("pitch" if axis == "Pitch" else "roll", value))
	var step_row := HBoxContainer.new()
	angles.add_child(step_row)
	label(step_row, "Rotate step").size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rotation_step = spin(step_row, 0.1, 180, 0.1, 90)
	rotation_step.suffix = "°"
	rotation_step.custom_minimum_size.x = 108
	rotation_step.tooltip_text = "Angle added by Rotate / R. Try 15° for fine turns."
	rotation_step.value_changed.connect(func(_value: float): if enhancements_ready: refresh_controls())
	rotation_controls = preload("res://scripts/builder/rotation_controls.gd").new(self, angles, angle_caption)
	var groups := HBoxContainer.new()
	inspector.add_child(groups)
	inspector.move_child(groups, angles.get_index() + 1)
	button(groups, "Group", "group", "Group selected objects · Ctrl+G")
	button(groups, "Ungroup", "ungroup", "Ungroup · Ctrl+Shift+G")
	var assembly_button: Button = button(inspector, "Save as assembly", "assembly_save", "Save this selection as a reusable collection")
	inspector.move_child(assembly_button, groups.get_index() + 1)
	assign_layer = OptionButton.new()
	assign_layer.add_item("Move selection to layer…")
	for name in Layers.NAMES: assign_layer.add_item(name)
	assign_layer.item_selected.connect(func(index: int):
		if index > 0: _command("assign_layer", Layers.NAMES[index - 1]); assign_layer.select(0)
	)
	inspector.add_child(assign_layer)
	inspector.move_child(assign_layer, assembly_button.get_index() + 1)
	var layer_panel := VBoxContainer.new()
	layer_panel.name = "Layers"
	tabs.add_child(layer_panel)
	label(layer_panel, "Show or protect your work", 13)
	for name in Layers.NAMES:
		var layer_row := VBoxContainer.new()
		layer_panel.add_child(layer_row)
		label(layer_row, name, 14)
		var switches := HBoxContainer.new()
		layer_row.add_child(switches)
		var shown := CheckBox.new()
		shown.text = "Visible"
		shown.button_pressed = true
		switches.add_child(shown)
		shown.toggled.connect(func(value: bool): _command("layer", [name, "visible", value]))
		var locked := CheckBox.new()
		locked.text = "Locked"
		switches.add_child(locked)
		locked.toggled.connect(func(value: bool): _command("layer", [name, "locked", value]))
		layer_rows[name] = [shown, locked]
	var hint: Label = label(layer_panel, "Hidden and locked layers are skipped when selecting or erasing. Visibility affects this workspace; exported scenes include every layer.", 12)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	color_editor = preload("res://scripts/builder/color_tools.gd").new(self, tabs)
	appearance_tools = preload("res://scripts/builder/appearance_tools.gd").new(self, tabs)
	entrance_tools = preload("res://scripts/builder/entrance_tools.gd").new(self, tabs)
	interior_tools = preload("res://scripts/builder/interior_tools.gd").new(self, entrance_tools.note.get_parent(), center)
	repair_tools = preload("res://scripts/builder/repair_tools.gd").new(self,center)
	var toolbar: Node = tools["erase"].get_parent()
	var color_button: Button = button(toolbar, "Color / parts", "tool", "Select a connected piece or an individual face/pixel to recolor", "color")
	color_button.toggle_mode = true
	toolbar.move_child(color_button, tools["erase"].get_index() + 1)
	tools["color"] = color_button
	var library_column: Node = search.get_parent()
	var assemblies_button: Button = button(library_column, "My assemblies", "assemblies", "Place a saved furniture arrangement or building group")
	library_column.move_child(assemblies_button, 4)
	road_settings = preload("res://scripts/builder/road_settings.gd").new(self, tabs)
	ground_brush = preload("res://scripts/builder/ground_brush.gd").new(self, tabs)
	arrange_tools = preload("res://scripts/builder/arrange_tools.gd").new(self, tabs)
	connector_tools = preload("res://scripts/builder/connector_tools.gd").new(self, arrange_tools.panel)
	command_palette = preload("res://scripts/builder/command_palette.gd").new(self)
	scene_outliner = preload("res://scripts/builder/scene_outliner.gd").new(self, tabs)
	button(library_column, "Commands...", "commands", "Search actions - Ctrl+Shift+P")
	for control in center.get_children():
		if control is Label and control.text.begins_with("Drag an asset"): mode_edit_controls.append(control)
	for control in toolbar.get_children():
		if control is Button and control.text in ["Home", "Day / night", "Walk around"]: continue
		mode_edit_controls.append(control)
	create_project_dialogs()
	workspace_layout = preload("res://scripts/builder/workspace_layout.gd").new(self,tabs,center)
	selection_inspector = preload("res://scripts/builder/selection_inspector.gd").new(self,center)
	asset_browser = preload("res://scripts/builder/asset_browser.gd").new(self)
	overlap_picker = preload("res://scripts/builder/overlap_picker.gd").new(self)
	editor_feedback = preload("res://scripts/builder/editor_feedback.gd").new(self,center)
	workspace_presets = preload("res://scripts/builder/workspace_presets.gd").new(self,center)
	small_prop_tools=preload("res://scripts/builder/small_prop_tools.gd").new(self)
	control_settings = preload("res://scripts/builder/control_settings.gd").new(self)
	accessibility_settings = preload("res://scripts/builder/accessibility_settings.gd").new(self)
	first_build = preload("res://scripts/builder/first_build.gd").new(self)
	transform_handles = preload("res://scripts/builder/transform_handles.gd").new(self)
	citizen_tools = preload("res://scripts/builder/citizen_tools.gd").new(self)
	school_tools = preload("res://scripts/builder/school_tools.gd").new(self)
	traffic_tools = preload("res://scripts/builder/traffic_tools.gd").new(self)
	business_tools = preload("res://scripts/builder/business_tools.gd").new(self)
	service_tools = preload("res://scripts/builder/service_tools.gd").new(self)
	economy_tools = preload("res://scripts/builder/economy_tools.gd").new(self)
	construction_cost_tools = preload("res://scripts/builder/construction_cost_tools.gd").new(self)
	scenario_tools = preload("res://scripts/builder/scenario_tools.gd").new(self)
	zone_tools = preload("res://scripts/builder/zone_tools.gd").new(self)
	transit_tools = preload("res://scripts/builder/transit_tools.gd").new(self)
	terrain_tools = preload("res://scripts/builder/terrain_tools.gd").new(self)
	modular_building_tools = preload("res://scripts/builder/modular_building_tools.gd").new(self)
	garden_tools = preload("res://scripts/builder/garden_tools.gd").new(self)
	cooking_tools = preload("res://scripts/builder/cooking_tools.gd").new(self)
	laundry_tools = preload("res://scripts/builder/laundry_tools.gd").new(self)
	fitness_tools = preload("res://scripts/builder/fitness_tools.gd").new(self)
	arcade_tools = preload("res://scripts/builder/arcade_tools.gd").new(self)
	camping_tools = preload("res://scripts/builder/camping_tools.gd").new(self)
	pet_tools = preload("res://scripts/builder/pet_tools.gd").new(self)
	cycling_tools = preload("res://scripts/builder/cycling_tools.gd").new(self)
	harbor_tools = preload("res://scripts/builder/harbor_tools.gd").new(self)
	outpost_tools = preload("res://scripts/builder/space_outpost_tools.gd").new(self)
	village_tools = preload("res://scripts/builder/village_tools.gd").new(self)
	neighborhood_tools = preload("res://scripts/builder/neighborhood_tools.gd").new(self)
	ambience_tools = preload("res://scripts/builder/ambience_tools.gd").new(self)
	weather_tools = preload("res://scripts/builder/weather_tools.gd").new(self)
	prop_tools = preload("res://scripts/builder/prop_tools.gd").new(self)
	driving_tools = preload("res://scripts/builder/driving_tools.gd").new(self)
	delivery_tools = preload("res://scripts/builder/delivery_tools.gd").new(self)
	market_tools = preload("res://scripts/builder/market_tools.gd").new(self)
	vehicle_service_tools = preload("res://scripts/builder/vehicle_service_tools.gd").new(self)
	asset_import_tools = preload("res://scripts/builder/asset_import_tools.gd").new(self)
	blueprint_tools = preload("res://scripts/builder/blueprint_tools.gd").new(self)
	photo_tools = preload("res://scripts/builder/photo_tools.gd").new(self)
	cooperative_tools = preload("res://scripts/builder/cooperative_tools.gd").new(self)
	creation_tools = preload("res://scripts/builder/creation_tools.gd").new(self)
	companion_tools = preload("res://scripts/builder/companion_tools.gd").new(self)
	simulation_diagnostic_tools = preload("res://scripts/builder/simulation_diagnostic_tools.gd").new(self)
	utility_tools = preload("res://scripts/builder/utility_tools.gd").new(self)
	power_tools = preload("res://scripts/builder/utility_tools.gd").new(self,"power")

func refresh_library() -> void:
	super.refresh_library()
	if asset_browser: asset_browser.refresh()
	if consumer_shell and consumer_shell.active: consumer_shell.update_catalog_notes()

func library_matches() -> Array[Dictionary]:
	if consumer_shell and consumer_shell.active: return consumer_shell.matches()
	var found: Array[Dictionary] = super.library_matches()
	if asset_browser: found = found.filter(func(asset: Dictionary) -> bool: return library.themes.matches(asset, asset_browser.theme_filter))
	if asset_browser and asset_browser.semantic_search:found=found.filter(asset_browser.semantic_search.matches)
	if asset_browser and asset_browser.task_collections:found=found.filter(asset_browser.task_collections.matches)
	if asset_browser and asset_browser.recents:found=asset_browser.recents.filter(found)
	if asset_browser and asset_browser.collections:found=asset_browser.collections.filter(found)
	if asset_browser: found = found.filter(func(asset: Dictionary) -> bool: return preload("res://scripts/builder/asset_content.gd").visible(asset, asset_browser.content_scope, favorites_only.button_pressed))
	var result: Array[Dictionary] = library.families.collapse(found) if asset_browser and asset_browser.group_variants.button_pressed and search.text.strip_edges().is_empty() and not favorites_only.button_pressed and not asset_browser.recents.active() and not asset_browser.collections.active() else found
	if asset_browser: asset_browser.matched_members = found.size(); asset_browser.matched_designs = result.size()
	if asset_browser and asset_browser.recents.active():return result
	return asset_browser.compatibility.order(result,search.text) if asset_browser and asset_browser.compatibility else result

func card_name(asset: Dictionary) -> String:
	if consumer_shell and consumer_shell.active: return consumer_shell.card_name(asset)
	if asset_browser and (asset_browser.recents.active() or asset_browser.collections.active()):return asset["name"]
	if asset_browser and asset_browser.group_variants.button_pressed and search.text.strip_edges().is_empty() and not favorites_only.button_pressed and asset["data"].has("family_name"): return asset["data"]["family_name"]
	return super.card_name(asset)

func show_grid() -> bool:
	return super.show_grid() and (not consumer_shell or not consumer_shell.active or tool in ["road","road_erase","crossing","terrain","zone"])

func pointer_in_canvas() -> bool:
	return super.pointer_in_canvas() and (not small_prop_tools or not small_prop_tools.over_ui(get_global_mouse_position())) and (not companion_tools or not companion_tools.over_ui(get_global_mouse_position())) and (not consumer_shell or not consumer_shell.active or consumer_shell.over_canvas(get_global_mouse_position()))

func create_project_dialogs() -> void:
	browser = AcceptDialog.new()
	browser.title = "Projects, snapshots and recovery"
	browser.size = Vector2i(850, 570)
	add_child(browser)
	var box := VBoxContainer.new()
	browser.add_child(box)
	var actions := HBoxContainer.new()
	box.add_child(actions)
	button(actions, "Open file…", "open_file")
	button(actions, "Save As…", "save_as")
	button(actions, "Create snapshot…", "snapshot")
	button(actions, "Restore selected", "restore")
	recovery_filter = OptionButton.new()
	recovery_filter.item_selected.connect(func(_index:int): populate_projects())
	box.add_child(recovery_filter)
	recovery_caption = label(box,"",12)
	recovery_caption.clip_text = true
	recovery_caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	project_list = ItemList.new()
	project_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	project_list.custom_minimum_size = Vector2(760, 400)
	project_list.fixed_icon_size = Vector2i(120, 75)
	project_list.max_columns = 1
	project_list.max_text_lines = 1
	project_list.auto_height = false
	project_list.item_activated.connect(func(_index: int): _command("restore", null))
	project_list.item_selected.connect(show_recovery_details)
	box.add_child(project_list)
	recovery_details = label(box,"",12)
	recovery_details.custom_minimum_size.y = 64
	recovery_details.clip_text = true
	recovery_details.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_dialog = ConfirmationDialog.new()
	name_dialog.size = Vector2i(430, 160)
	name_field = LineEdit.new()
	name_field.placeholder_text = "Choose a name"
	name_dialog.add_child(name_field)
	name_dialog.confirmed.connect(confirm_name)
	name_field.text_submitted.connect(func(_text: String): name_dialog.hide(); confirm_name())
	add_child(name_dialog)
	assembly_dialog = AcceptDialog.new()
	assembly_dialog.title = "My reusable assemblies"
	assembly_dialog.size = Vector2i(560, 430)
	var collection := VBoxContainer.new()
	assembly_dialog.add_child(collection)
	assembly_list = ItemList.new()
	assembly_list.custom_minimum_size = Vector2(490, 300)
	assembly_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	collection.add_child(assembly_list)
	button(collection, "Place selected assembly", "assembly_place")
	assembly_list.item_activated.connect(func(_index: int): _command("assembly_place", null))
	add_child(assembly_dialog)

func _ready() -> void:
	await super._ready()
	enhancements_ready = true
	for world in worlds.values():
		world.player.control_input=control_settings.held
		world.exploration.driving.control_input=control_settings.driving_held
		world.exploration.photo.control_input=control_settings.driving_held
		world.exploration.photo.input_allowed=photo_tools.can_input
	control_settings.persist()
	accessibility_settings.apply()
	citizen_tools.start()
	traffic_tools.start()
	business_tools.start()
	service_tools.start()
	scenario_tools.start()
	zone_tools.start()
	utility_tools.start()
	power_tools.start()
	transit_tools.start()
	terrain_tools.start()
	ambience_tools.start()
	weather_tools.start()
	cooking_tools.start()
	laundry_tools.start()
	fitness_tools.start()
	arcade_tools.start()
	camping_tools.start()
	pet_tools.start()
	cycling_tools.start()
	village_tools.start()
	prop_tools.start()
	if storage_enabled:
		var value: Variant = Store.read_json("user://studio_assemblies.json", [])
		if value is Array: assemblies = value
		if pending_workspace.is_empty():
			var previous: Variant = Store.read_json("user://studio_workspace.json", {})
			if previous is Dictionary: pending_workspace = previous
	workspace = pending_workspace
	restore_workspace()
	for key in worlds:
		worlds[key].exploration.preview_finished.connect(func(floor_uid: String,point: Variant,notice: String): interior_tools.finish_walk(floor_uid,point,notice,key))
		worlds[key].exploration.preview_exit_requested.connect(func(entry: Dictionary): interior_tools.exit_preview(entry,key))
		worlds[key].exploration.interior_requested.connect(func(uid: String): interior_tools.prepare(uid,key))
		worlds[key].exploration.interior_door_changed.connect(func(host_uid: String, door_uid: String, opened: bool): interior_tools.set_door(host_uid,door_uid,opened,key))
		worlds[key].exploration.interior_floor_door_changed.connect(func(host_uid: String, floor_uid: String, door_uid: String, opened: bool): interior_tools.set_door(host_uid,door_uid,opened,key,floor_uid))
		worlds[key].exploration.door_changed.connect(func(uid: String, opened: bool):
			var doc: RefCounted = documents[key]
			if doc.object(uid).is_empty(): return
			doc.checkpoint()
			doc.object(uid)["open"] = opened
			changed()
		)
	if saved_digest.is_empty(): saved_digest = content_digest() if not dirty else ""
	recovery_digest = content_digest()
	refresh_controls()
	update_save_badge()
	if workspace_layout: workspace_layout.refresh()
	if pending_repair_report: pending_repair_report = false; repair_tools.call_deferred("show")
	if storage_enabled or "--consumer-ui" in OS.get_cmdline_user_args(): consumer_shell=preload("res://scripts/builder/consumer_shell.gd").new(self)
	if storage_enabled and (not consumer_shell or not consumer_shell.active): first_build.offer()

func selection_items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids: Array = selected_uids.duplicate()
	if not selected_uid.is_empty() and not ids.has(selected_uid): ids.append(selected_uid)
	for uid in ids:
		var item: Dictionary = current().object(uid)
		if not item.is_empty() and Layers.editable(current().data, item, library): result.append(item)
	return result

func refresh_worlds() -> void:
	if editor_feedback: editor_feedback.invalidate()
	# Default templates also refer to installed assets. Keep the editor usable
	# if a source pack disappeared before a project could even be opened.
	if not enhancements_ready:
		var startup_issues: Array = []
		for key in documents:
			var repair = preload("res://scripts/builder/project_repair.gd").new(library)
			var repaired: Dictionary = repair.world(documents[key].data,key,"documents/"+key,0)
			if not repair.issues.is_empty(): documents[key].data = repaired; startup_issues.append_array(repair.issues)
		if not startup_issues.is_empty():
			repair_report = {"source":"Startup templates","time":Time.get_datetime_string_from_system(true).replace("T"," ")+" UTC","issues":startup_issues}
			pending_repair_report = true
			dirty = true
			autosave_pending = true
	super.refresh_worlds()

func refresh_controls() -> void:
	if enhancements_ready and not selected_uid.is_empty():
		var record: Dictionary = current().object(selected_uid)
		if record.is_empty() or not Layers.editable(current().data, record, library): selected_uid = ""
	super.refresh_controls()
	if not enhancements_ready: return
	if scene_outliner: scene_outliner.refresh()
	if arrange_tools: arrange_tools.refresh()
	if ground_brush: ground_brush.refresh()
	brush_input.editable = mode == "2d" or ground_brush.active()
	brush_input.tooltip_text = "Ground brush width in either world: 1, 3 or 5 cells"
	var valid_ids: Array[String] = []
	for item in selection_items(): valid_ids.append(item["uid"])
	selected_uids = valid_ids
	if not selected_uid.is_empty() and not selected_uids.has(selected_uid): selected_uid = ""
	for name in layer_rows:
		layer_rows[name][0].set_pressed_no_signal(Layers.shown(current().data, name))
		layer_rows[name][1].set_pressed_no_signal(Layers.locked(current().data, name))
	orientation.direction = direction
	orientation.dimension = "3d" if direction.is_valid_float() else "2d"
	orientation.queue_redraw()
	var item: Dictionary = current().object(selected_uid)
	var id: String = item.get("asset", selected_tile().get("asset", asset_id))
	var rotation_record: Dictionary = item if not item.is_empty() else selected_tile()
	if rotation_record.is_empty(): rotation_record = placement_record()
	var has_asset: bool = library.assets.has(id)
	refresh_compass(id, rotation_record)
	view_choice.clear()
	if has_asset and id.begins_with("2d:") and not library.is_ground_tile(id):
		for view in library.directions(id): view_choice.add_item(str(view))
		for index in view_choice.item_count:
			if view_choice.get_item_text(index) == direction: view_choice.select(index)
	view_choice.visible = view_choice.item_count > 1
	angle_input.editable = has_asset
	angle_input.set_value_no_signal(Rotation.heading(rotation_record, library) if has_asset else 0)
	var tilt: Array = rotation_record.get("tilt", [0, 0])
	orientation.angle_offset = float(rotation_record.get("angle", 0))
	pitch_input.set_value_no_signal(tilt[0])
	roll_input.set_value_no_signal(tilt[1])
	pitch_input.editable = has_asset and (mode == "3d" or id.begins_with("3d:")) and selected_tile().is_empty()
	roll_input.editable = pitch_input.editable
	rotation_button.disabled = not has_asset
	if has_asset:
		rotation_button.text = "Rotate ↻ · " + str(rotation_step.value) + "°"
		rotation_button.tooltip_text = "Turn by Rotate step · R. Use Angle / yaw for an exact heading."
	rotation_controls.refresh(rotation_record)
	entrance_tools.refresh()
	interior_tools.refresh()
	repair_tools.refresh()
	if not id.is_empty(): asset_picture.texture = library.directional_icon(id, direction)
	if selected_uids.size() > 1:
		selected_name.text = "%d objects selected" % selected_uids.size()
		selection_note.text = "Drag to move together · Ctrl+C / V · Group to keep together"
	refresh_capabilities()
	surface_input.disabled = mode != "3d"
	if selection_inspector: selection_inspector.refresh()
	update_save_badge()
	if workspace_layout: workspace_layout.refresh()
	if small_prop_tools and not small_prop_tools.changing:small_prop_tools.synchronize()

func refresh_capabilities() -> void:
	if not is_instance_valid(capability_note):return
	capability_note.text=library.capabilities.studio_text(self)
	capability_note.tooltip_text=capability_note.text
	capability_note.visible=not selected_uids.is_empty() or library.assets.has(selected_tile().get("asset",asset_id))

func select_asset(id: String) -> void:
	if not preload("res://scripts/builder/repair_assets.gd").available(id,library,{}):
		if editor_feedback: editor_feedback.reject("Cannot place · source asset is unavailable")
		if library.assets.has(id): library.assets[id]["unavailable"] = true
		clear_placement()
		status.text = "This asset's source is unavailable. Restore its files or choose another asset."
		return
	if ground_brush and ground_brush.drawing:
		ground_brush.finish(ground_brush.last_pointer)
		stroke = false
	rotation_manual = false
	if editor_feedback: editor_feedback.rejection_time=0
	placement_angle = 0
	placement_tilt = Vector2.ZERO
	selected_uids.clear()
	clear_assembly()
	super.select_asset(id)
	if companion_tools:companion_tools.chosen()
	if consumer_shell: consumer_shell.asset_picked()

func model_view_yaw() -> float:
	return 45.0 if mode == "2d" else float(worlds["3d"].yaw)

func refresh_compass(id: String, record: Dictionary) -> void:
	var supported: bool = id.begins_with("3d:") and library.assets.has(id)
	compass_panel.visible = supported
	compass_view_yaw = model_view_yaw()
	orientation.model_compass = supported
	orientation.view_yaw = compass_view_yaw
	orientation.vertical_scale = 0.5 if mode == "2d" else sin(deg_to_rad(worlds["3d"].pitch))
	orientation.queue_redraw()
	if not supported: return
	var facing: String = Rotation.compass_name(Rotation.heading(record, library), compass_view_yaw)
	compass_caption.text = "Facing " + facing + " · screen directions" if not facing.is_empty() else "Custom angle · screen directions"
	for name in compass_buttons: compass_buttons[name].set_pressed_no_signal(name == facing)

func clear_placement() -> void:
	if ground_brush and ground_brush.drawing:
		ground_brush.finish(ground_brush.last_pointer)
		stroke = false
	selected_uids.clear()
	clear_assembly()
	super.clear_placement()

func set_tool(value: String) -> void:
	if modular_building_tools and tool=="modular_room" and value!="modular_room":
		modular_building_tools.cancel()
	if small_prop_tools and value!="select":small_prop_tools.leave()
	if terrain_tools: terrain_tools.finish()
	if transform_handles: transform_handles.finish()
	if control_settings: control_settings.finish_drag()
	if walking: set_walking(false)
	if ground_brush and ground_brush.drawing:
		ground_brush.finish(ground_brush.last_pointer)
		stroke = false
	super.set_tool(value)
	if control_settings: control_settings.refresh_mode_hint()
	if value == "color" and color_editor:
		color_editor.tabs.current_tab = color_editor.page.get_index()
		status.text = "Click the piece to recolor, then choose a color and Apply in Colors."
	if not road_choice: return
	road_choice.select({"road": 1, "crossing": 2, "road_erase": 3}.get(value, 0))
	if value in ["road", "road_erase", "crossing"]:
		asset_id = ""
		clear_assembly()
		status.text = "Drag to draw connected roads. Corners, sidewalks and intersections update automatically." if value == "road" else ("Click a road section to toggle its crossing." if value == "crossing" else "Drag over road sections to remove them.")
	if workspace_layout: workspace_layout.tool_changed()

func set_walking(enabled: bool) -> void:
	if enabled and modular_building_tools and tool=="modular_room":
		set_tool("select")
	if enabled and small_prop_tools:small_prop_tools.leave()
	if photo_tools and worlds.has(mode) and worlds[mode].exploration and worlds[mode].exploration.photo.active: photo_tools.stop()
	if transform_handles: transform_handles.finish()
	if enabled:
		var focus: Control=get_viewport().gui_get_focus_owner()
		if focus: focus.release_focus()
	if control_settings: control_settings.finish_drag(); control_settings.marker.queue_redraw()
	if enabled and ground_brush and ground_brush.drawing: ground_brush.finish(ground_brush.last_pointer)
	super.set_walking(enabled)
	if enabled and interior_tools: interior_tools.begin_walk()
	viewport.gui_disable_input=not enabled
	if mode_badge:
		mode_badge.text = ("WALK MODE · WASD move · " + ("Space jump · " if mode == "3d" else "") + "E interact · X recover · Tab: Build") if enabled else "BUILD MODE · Place / select · Tab to walk"
		if control_settings: control_settings.refresh_mode_hint()
		mode_badge.modulate = Color("ffdf83") if enabled else Color("8fdccb")
	for control in [mode_library, mode_inspector, mode_road_bar, mode_template_bar]:
		if control: control.visible = not enabled
	for control in mode_edit_controls: control.visible = not enabled
	if overlay: overlay.visible = not enabled
	if workspace_layout: workspace_layout.refresh()
	if workspace_presets: workspace_presets.walking_changed(enabled)
	if enhancements_ready and first_build: first_build.on_walking(enabled)

func finish_palette_boundary() -> void:
	if interior_tools and interior_tools.editing():current().finish_checkpoint();interior_tools.flush()
	for key in documents:
		var doc: RefCounted=interior_tools.root_document(key) if interior_tools else documents[key]
		doc.finish_checkpoint()
	if interior_tools and interior_tools.editing():interior_tools.outer.checkpoint()

func changed() -> void:
	if simulation_diagnostic_tools and simulation_diagnostic_tools.kind!="off": simulation_diagnostic_tools.invalidate()
	if utility_tools: utility_tools.dirty=true
	if power_tools: power_tools.dirty=true
	if connector_tools and not documents.is_empty():
		connector_tools.invalidate()
		var source: Dictionary = current().data
		if source.has("connections"):
			source["connections"] = connector_tools.Plan.retained(source, source["connections"])
		preload("res://scripts/builder/utility_plan.gd").normalize(source,library)
	library.set_project_palette({} if palette_loading else project_palette_document.data)
	for key in documents:
		var doc: RefCounted=interior_tools.root_document(key) if interior_tools else documents[key]
		doc.content_library=library
	if interior_tools and interior_tools.editing():current().canonical.content_library=library
	if transit_tools: transit_tools.dirty=true
	if zone_tools: zone_tools.dirty=true
	if scenario_tools: scenario_tools.dirty=true
	if citizen_tools: citizen_tools.dirty=true
	if traffic_tools: traffic_tools.dirty=true
	if business_tools: business_tools.dirty=true
	if service_tools: service_tools.dirty=true
	if editor_feedback: editor_feedback.invalidate()
	if interior_tools: interior_tools.flush()
	if economy_tools: economy_tools.reconcile()
	super.changed()
	if enhancements_ready:
		dirty = content_digest() != saved_digest
		update_save_badge()
	if cooperative_tools: cooperative_tools.observe()
	if small_prop_tools and not small_prop_tools.changing:small_prop_tools.synchronize()

func shared_authority() -> bool:
	return not cooperative_tools or cooperative_tools.authority()

func content_digest() -> String:
	var content: Dictionary={"2d": (interior_tools.root_document("2d") if interior_tools else documents["2d"]).data, "3d": (interior_tools.root_document("3d") if interior_tools else documents["3d"]).data}
	if not project_palette_document.data.is_empty():content["project_palette"]=project_palette_document.data
	return JSON.stringify(content).sha256_text()

func update_save_badge() -> void:
	if not save_badge or documents.is_empty(): return
	var recovery: String="Recovery disabled" if not storage_enabled else "Autosave pending" if autosave_pending else "Autosaved" if FileAccess.file_exists(Store.autosave_path(project_id)) else "No autosave yet"
	save_badge.text = "Save state · " + ("Unsaved changes" if dirty else ("Saved · " + project_path.get_file() if not project_path.is_empty() else "Unsaved project · choose Save")) + " · " + recovery
	save_badge.tooltip_text=save_badge.text
	DisplayServer.window_set_title(("IsoCity · " if consumer_shell and consumer_shell.active else "IsoCity Studio v" + STUDIO_VERSION + " · ") + current().data["title"] + (" *" if dirty else ""))

func _command(action: String, value: Variant) -> void:
	if not enhancements_ready:
		super._command(action, value)
		return
	if action=="interaction_setup":
		if prop_tools.setup.blocked():status.text="Return to Build and finish the current edit before checking setup.";return
		if consumer_shell:consumer_shell.prepare_command(action)
		prop_tools.show();prop_tools.setup.open_review();return
	if action=="simulation_diagnostics":
		if simulation_diagnostic_tools.suspended():
			status.text="Finish the current edit or leave Photo mode to see simulation diagnostics."
			return
		if consumer_shell: consumer_shell.prepare_command(action)
		simulation_diagnostic_tools.show()
		return
	if not updating_controls and transform_handles: transform_handles.finish()
	if control_settings and control_settings.dragging: control_settings.finish_drag()
	if small_prop_tools and action in ["home","template","open","open_file","export","export_portable","photo","photo_capture","photo_record","supplemental_showcase","swat_showcase","neighborhood"]:small_prop_tools.leave()
	if tool=="modular_room" and action in ["template","open","open_file","photo","photo_capture","photo_record"]:
		set_tool("select")
	if walking and interior_tools and worlds[mode].exploration.preview:
		if action=="night": interior_tools.walk_night(); return
		if action=="home": interior_tools.walk_home(); return
	if walking and action in ["tool", "undo", "redo", "template", "remove", "duplicate", "height", "scale", "angle", "pitch", "roll", "rotate", "rotate_ccw", "rotate_reset", "source_view", "compass", "group", "ungroup", "layer", "assign_layer", "align_cars", "align_buildings", "align_grid"]: set_walking(false)
	if action in ["undo","redo"] and cooperative_tools and cooperative_tools.session.connected:
		cooperative_tools.history(action=="redo"); return
	if consumer_shell: consumer_shell.prepare_command(action)
	match action:
		"small_props_focus":small_prop_tools.begin(false)
		"small_props_magnify":small_prop_tools.begin(true)
		"small_props_isolate":small_prop_tools.toggle_isolation()
		"small_props_return":small_prop_tools.leave()
		"supplemental_showcase", "swat_showcase":
			if cooperative_tools and cooperative_tools.session.connected:
				status.text = "Leave the cooperative session before replacing the layout."; return
			set_walking(false)
			current().checkpoint()
			current().data = preload("res://scripts/builder/supplemental_showcase.gd").swat(mode, library) if action=="swat_showcase" else preload("res://scripts/builder/supplemental_showcase.gd").make(mode, library)
			selected_uids.clear(); selected_uid = ""; selected_cell = null; clear_assembly()
			changed(); worlds[mode].reset_camera("city")
			template_choice.select(2)
			var area := Rect2(Vector2(-32,-26),Vector2(64,52)) if action=="swat_showcase" else Rect2(Vector2(-48,-40),Vector2(96,96))
			neighborhood_tools.frame(worlds[mode],area,viewport.size)
			status.text = "Editable asset showcase opened. Undo restores your previous layout. Filter the library by Pack to explore each family."
		"cooperative": cooperative_tools.show()
		"creation_sharing": creation_tools.show()
		"citizens": citizen_tools.show()
		"schools": school_tools.show()
		"resident_activities": citizen_tools.show_interiors()
		"traffic": traffic_tools.show()
		"vehicle_fleets": traffic_tools.fleets.show()
		"businesses": business_tools.show()
		"services": service_tools.show()
		"water": utility_tools.show()
		"power": power_tools.show()
		"economy": economy_tools.show()
		"construction_costs": construction_cost_tools.show()
		"challenges": scenario_tools.show(str(value) if value is String else "")
		"zoning": zone_tools.show()
		"transit": transit_tools.show()
		"terrain": terrain_tools.show()
		"modular_rooms": modular_building_tools.show()
		"garden": garden_tools.show()
		"cooking": cooking_tools.show()
		"laundry": laundry_tools.show()
		"fitness": fitness_tools.show()
		"arcade": arcade_tools.show()
		"camping": camping_tools.show()
		"pet": pet_tools.show()
		"cycling": cycling_tools.show()
		"harbors": harbor_tools.show()
		"space_outpost": outpost_tools.show()
		"village": village_tools.show()
		"ground_families": ground_brush.show()
		"neighborhood": neighborhood_tools.show()
		"ambience": ambience_tools.show()
		"ambience_mute": ambience_tools.toggle_mute()
		"weather": weather_tools.show()
		"props": prop_tools.show()
		"driving": driving_tools.show()
		"vehicle_care": vehicle_service_tools.show()
		"deliveries": delivery_tools.show()
		"markets": market_tools.show()
		"import_asset": asset_import_tools.show()
		"blueprints": blueprint_tools.show()
		"connectors": connector_tools.show()
		"connector_next": cycle_connection(1)
		"connector_previous": cycle_connection(-1)
		"photo": photo_tools.show()
		"handles_mode": transform_handles.set_mode(str(value))
		"first_build":
			first_build.show()
			if consumer_shell and consumer_shell.active: consumer_shell.open_details(str(first_build.page.name))
		"accessibility": accessibility_settings.show()
		"controls": control_settings.show()
		"workspace_preset": workspace_presets.apply_preset(str(value))
		"focus_canvas":
			if small_prop_tools and small_prop_tools.active:small_prop_tools.leave()
			else:workspace_presets.set_focus(not workspace_presets.focused)
		"overlap_next": overlap_picker.cycle(overlap_picker.pointer())
		"overlap_list": overlap_picker.show(overlap_picker.pointer())
		"export_portable":
			file_action = action
			file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
			file_dialog.filters = PackedStringArray(["*.zip ; Portable Godot project"])
			file_dialog.title = "Export portable Godot project · city and owned interiors" if interior_tools.editing() else "Export portable Godot project · current layout"
			file_dialog.current_dir = ProjectSettings.globalize_path("res://creations")
			file_dialog.current_file = layout_for_export()["title"].validate_filename() + "_" + mode + ".zip"
			file_dialog.popup_centered()
		"commands": command_palette.show()
		"compass":
			if updating_controls or not Rotation.COMPASS.has(str(value)): return
			var items: Array[Dictionary] = selection_items()
			var active: Dictionary = items[0] if not items.is_empty() else placement_record()
			if not active.get("asset", "").begins_with("3d:"): return
			set_rotation_value("angle", Rotation.compass_yaw(str(value), model_view_yaw()))
			status.text = "Model faces " + str(value) + " on screen. Set Rotate step to 45° to cycle all eight directions with R."
		"source_view":
			if updating_controls: return
			if value == "Mixed": return
			var items: Array[Dictionary] = selection_items()
			if not items.is_empty():
				current().checkpoint()
				for item in items:
					if item["asset"].begins_with("2d:") and not library.is_ground_tile(item["asset"]) and library.directions(item["asset"]).has(value): item["direction"] = value
				changed()
			elif asset_id.begins_with("2d:") and not library.is_ground_tile(asset_id) and library.directions(asset_id).has(value): direction = value; refresh_controls()
		"align_cars": align_cars()
		"align_buildings": align_buildings()
		"align_grid": align_grid()
		"angle", "pitch", "roll":
			if not updating_controls: set_rotation_value(action, float(value))
		"open": show_projects()
		"open_file": browser.hide(); super.show_file_dialog("open")
		"save_as":
			browser.hide()
			file_action = "save"
			var previous: String = project_path
			project_path = ""
			super.show_file_dialog("save")
			project_path = previous
		"snapshot": ask_name("snapshot")
		"restore": restore_selected()
		"assembly_save":
			if selection_items().is_empty(): status.text = "Select objects first. Shift-click adds objects to the selection."
			else: ask_name("assembly")
		"assemblies": show_assemblies()
		"assembly_place": choose_assembly()
		"group", "ungroup": group_selection(action == "group")
		"assign_layer":
			var items: Array[Dictionary] = selection_items()
			if items.is_empty(): return
			current().checkpoint()
			for item in items: item["layer"] = value
			changed()
		"layer":
			if updating_controls: return
			current().checkpoint()
			Layers.set_state(current().data, value[0], value[1], value[2])
			changed()
		"rotate_ccw": rotate_by(-1)
		"rotate_reset": rotate_by(0, true)
		"rotate": rotate_by(1)
		"remove": remove_selection()
		"height", "scale":
			if updating_controls: return
			var items: Array[Dictionary] = selection_items()
			if items.is_empty(): return
			if action == "scale":
				arrange_tools.scale_selection(float(value))
				return
			current().checkpoint()
			for item in items:
				if action == "height": item["position"][2 if mode == "2d" else 1] = float(value)
				else: item["scale"] = float(value)
			changed()
		"undo", "redo", "template":
			if ground_brush.drawing:
				ground_brush.finish(ground_brush.last_pointer)
				stroke = false
			selected_uids.clear()
			clear_assembly()
			if action=="undo" and first_build: first_build.before_undo()
			if action=="template" and village_tools and not interior_tools.editing(): village_tools.reset()
			super._command(action, value)
			if action=="template" and garden_tools and not interior_tools.editing(): garden_tools.reset()
			if action=="template" and cooking_tools and not interior_tools.editing(): cooking_tools.reset()
			if action=="template" and laundry_tools and not interior_tools.editing(): laundry_tools.reset()
			if action=="template" and fitness_tools and not interior_tools.editing(): fitness_tools.reset()
			if action=="template" and arcade_tools and not interior_tools.editing(): arcade_tools.reset()
			if action=="template" and camping_tools and not interior_tools.editing(): camping_tools.reset()
			if action=="template" and pet_tools and not interior_tools.editing(): pet_tools.reset()
			if action=="undo" and first_build: first_build.on_undo()
		"title":
			super._command(action, value)
			update_save_badge()
		_: super._command(action, value)

func group_selection(grouped: bool) -> void:
	var items: Array[Dictionary] = selection_items()
	if items.is_empty() or (grouped and items.size() < 2):
		status.text = "Shift-click or drag a selection box around two or more objects first."
		return
	current().checkpoint()
	var id: String = str(Time.get_ticks_usec()) + "_group"
	for item in items:
		if grouped: item["group"] = id
		else: item.erase("group")
	changed()
	status.text = "Grouped %d objects. Clicking one selects the group." % items.size() if grouped else "Objects ungrouped."

func remove_selection() -> void:
	var items: Array[Dictionary] = selection_items()
	if items.is_empty():
		if not selected_tile().is_empty() and not Layers.locked(current().data, "Ground") and Layers.shown(current().data, "Ground"): super._command("remove", null)
		return
	current().checkpoint()
	for item in items: current().data["objects"].erase(item)
	selected_uids.clear()
	selected_uid = ""
	changed()

func copy_selection() -> void:
	clipboard = selection_items().duplicate(true)
	clipboard_connections = selection_connections(clipboard)
	clipboard_utility = preload("res://scripts/builder/utility_plan.gd").selection(current().data,clipboard)

	clipboard_mode = mode
	status.text = "Copied %d objects. Use Paste selection to paste them in this dimension." % clipboard.size()

func paste_objects(items: Array, offset: Array, grouped: bool = false, links: Array = [], utility: Dictionary = {}) -> void:
	if items.is_empty(): return
	for item in items:
		if not Layers.editable(current().data, item, library):
			status.text = "Show and unlock the assembly's layers before placing it."
			return
	current().checkpoint()
	selected_uids.clear()
	var groups: Dictionary = {}
	var copied_ids: Dictionary={}
	var copies: Array=[]
	var assembly_group: String = str(Time.get_ticks_usec()) + "_assembly"
	for item in items:
		var copy: Dictionary = offset_copy(item, Document.new_uid(), offset)
		current().data["objects"].append(copy)
		var copied: Dictionary = copy
		copied.erase("traffic_control")
		if copied.has("market"):
			if interior_tools.editing(): copied.erase("market")
			else: copied["market"]["enabled"]=false
		if interior_tools.editing():
			copied.erase("vehicle_care")
			copied.erase("vehicle_bay")
			for field in preload("res://scripts/builder/delivery_plan.gd").FIELDS: copied.erase(field)
		copied_ids[item["uid"]]=copy["uid"];copies.append(copy)
		if grouped: copy["group"] = assembly_group
		elif item.has("group"):
			if not groups.has(item["group"]): groups[item["group"]] = assembly_group + str(groups.size())
			copy["group"] = groups[item["group"]]
		selected_uids.append(copy["uid"])
	for copy in copies:
		preload("res://scripts/builder/owned_room_copy.gd").remap_target(copy,copied_ids)
		preload("res://scripts/builder/camping_plan.gd").copy_references(copy,copied_ids)
		preload("res://scripts/builder/cycling_plan.gd").copy_reference(copy,copied_ids)
		preload("res://scripts/builder/village_plan.gd").copy_link(copy,copied_ids)
		if copy.has("delivery_contract"):
			var contract: Dictionary=copy["delivery_contract"]
			contract["destination"]=copied_ids.get(contract.get("destination",""),"")
			if contract["destination"].is_empty(): contract["enabled"]=false
		if copy.has("school"):
			if interior_tools.editing():
				copy.erase("school")
			else:
				var settings: Dictionary=copy["school"]
				settings["enabled"]=false
				settings["playground"]=copied_ids.get(settings.get("playground",""),"")
				for key in ["bus_line","home_stop","school_stop"]: settings.erase(key)
	if not links.is_empty():
		var cloned: Array = connector_tools.Plan.copied_links(links, copied_ids, preload("res://scripts/builder/owned_room_copy.gd").identity)
		if not cloned.is_empty():
			if not current().data.has("connections"): current().data["connections"] = []
			current().data["connections"].append_array(cloned)
	if not interior_tools.editing():
		preload("res://scripts/builder/utility_plan.gd").copy_into(current().data,utility,copied_ids,preload("res://scripts/builder/owned_room_copy.gd").identity)

	selected_uid = selected_uids[0]
	selected_cell = null
	asset_id = ""
	set_tool("select")
	changed()

func duplicate_offset() -> Array:
	return [16, 8, 0] if mode == "2d" else [1, 0, 1]

static func offset_copy(item: Dictionary, uid: String, offset: Array, identity: Callable = Callable()) -> Dictionary:
	var position: Array = item["position"].duplicate()
	for index in 3: position[index] += offset[index]
	return preload("res://scripts/builder/owned_room_copy.gd").item(item, uid, position, identity)

func duplicate_selection() -> void:
	var items: Array = selection_items()
	var utility: Dictionary=preload("res://scripts/builder/utility_plan.gd").selection(current().data,items)
	paste_objects(items, duplicate_offset(), false, selection_connections(items), utility)

func selection_connections(items: Array) -> Array:
	var identities: Dictionary = {}
	for item in items: identities[item["uid"]] = true
	return current().data.get("connections", []).filter(func(link: Dictionary) -> bool:
		return identities.has(link["from"]["object_uid"]) and identities.has(link["to"]["object_uid"])
	).duplicate(true)

func rotate_selection() -> void:
	rotate_by(1)

func placement_record() -> Dictionary:
	return {"asset": asset_id, "direction": direction, "angle": placement_angle, "tilt": [placement_tilt.x, placement_tilt.y]}

func align_cars() -> void:
	var candidates: Array = selection_items()
	if candidates.is_empty(): candidates = current().data["objects"]
	var changes: Array = []
	for item in candidates:
		if not Layers.editable(current().data, item, library) or not preload("res://scripts/builder/asset_behavior.gd").for_asset(item["asset"], library).get("vehicle", false): continue
		var aligned: Dictionary = Roads.lane(current().data, item["position"], item["direction"], library, item["asset"], item["scale"])
		if aligned.get("snapped", false): changes.append([item, aligned])
	if changes.is_empty(): status.text = "No editable cars near a road were found."; return
	current().checkpoint()
	for pair in changes:
		pair[0]["position"] = pair[1]["position"]
		pair[0]["direction"] = pair[1]["direction"]
		pair[0].erase("angle")
		pair[0].erase("tilt")
	changed()
	status.text = "Aligned %d cars with the centers of their road lanes. Undo restores the previous positions." % changes.size()

func align_buildings() -> void:
	var allowed: Array = []
	for item in selection_items(): allowed.append(item["uid"])
	var plan: Dictionary = preload("res://scripts/builder/layout_alignment.gd").building_rows(current().data, library, allowed)
	if plan.is_empty(): status.text = "Select three or more adjoining, unlocked calibrated buildings first."; return
	current().checkpoint()
	for uid in plan: current().object(uid)["position"] = plan[uid]
	changed()
	status.text = "Aligned building bases and adjoining footprints. Undo restores previous positions."

func align_grid() -> void:
	var items: Array = selection_items()
	if items.is_empty(): items = current().data["objects"]
	var changes: Array = []
	for item in items:
		if not Layers.editable(current().data, item, library): continue
		var next: Array = GridFit.snap(item, mode, library, arrange_tools.target())
		if arrange_tools.target() == "base" and lanes_input.button_pressed and preload("res://scripts/builder/asset_behavior.gd").for_asset(item["asset"], library).get("vehicle", false):
			var lane: Dictionary = Roads.lane(current().data, next, item["direction"], library, item["asset"], item["scale"])
			if lane.get("snapped", false): next = lane["position"]
		if next != item["position"]: changes.append([item, next])
	if changes.is_empty(): status.text = "The chosen anchors are already on the grid."; return
	current().checkpoint()
	for pair in changes: pair[0]["position"] = pair[1]
	changed()
	status.text = "Snapped %d chosen anchors to the grid. Undo restores their positions." % changes.size()

func set_rotation_value(axis: String, value: float) -> void:
	var items: Array[Dictionary] = selection_items()
	if axis != "angle" and mode == "2d":
		items.assign(items.filter(func(item: Dictionary) -> bool: return item["asset"].begins_with("3d:")))
		if items.is_empty() and not selection_items().is_empty(): return
	var tile: Dictionary = selected_tile() if items.is_empty() else {}
	var active: Dictionary = items[0] if not items.is_empty() else (tile if not tile.is_empty() else placement_record())
	if not library.assets.has(active.get("asset", "")): return
	if axis != "angle" and not (mode == "3d" or active["asset"].begins_with("3d:")): return
	if not tile.is_empty() and not Layers.editable(current().data, {"asset": tile["asset"]}, library): return
	var targets: Array = items if not items.is_empty() else [active]
	if not items.is_empty() or not tile.is_empty(): current().checkpoint()
	if not tile.is_empty() and axis=="angle": tile.erase("family")
	var delta: float = value - Rotation.heading(active, library) if axis == "angle" else 0
	if axis != "angle": delta = value - float(active.get("tilt", [0, 0])[0 if axis == "pitch" else 1])
	var pivot: Vector3 = arrange_tools.pivot(items)
	for item in targets:
		if axis == "angle":
			Rotation.set_heading(item, Rotation.heading(item, library) + delta, library)
			if arrange_tools.orbit_enabled(items):
				# Positive 3D yaw turns opposite to a positive canvas rotation.
				var orbit_angle: float = -delta if mode == "2d" and active["asset"].begins_with("3d:") else delta
				item["position"] = Rotation.orbit_position(item["position"], pivot, orbit_angle, mode)
		else:
			var tilt: Array = item.get("tilt", [0, 0]).duplicate()
			tilt[0 if axis == "pitch" else 1] = value
			if is_zero_approx(tilt[0]) and is_zero_approx(tilt[1]): item.erase("tilt")
			else: item["tilt"] = tilt
			if arrange_tools.orbit_enabled(items) and mode == "3d":
				var offset := Vector3(item["position"][0], item["position"][1], item["position"][2]) - pivot
				offset = offset.rotated(Vector3.RIGHT if axis == "pitch" else Vector3.BACK, deg_to_rad(delta)) + pivot
				item["position"] = [offset.x, offset.y, offset.z]
	direction = active["direction"]
	if items.is_empty() and tile.is_empty():
		placement_angle = active.get("angle", 0)
		var tilt: Array = active.get("tilt", [0, 0])
		placement_tilt = Vector2(tilt[0], tilt[1])
		rotation_manual = true
		refresh_controls()
	else: changed()

func rotate_by(step: int, reset: bool = false) -> void:
	if companion_tools and companion_tools.rotate(step,reset):return
	if rotation_controls.rotate(step, reset): return
	var items: Array[Dictionary] = selection_items()
	var tile: Dictionary = selected_tile() if items.is_empty() else {}
	var active: Dictionary = items[0] if not items.is_empty() else (tile if not tile.is_empty() else placement_record())
	var id: String = active.get("asset", "")
	if not library.assets.has(id): return
	if not tile.is_empty() and not Layers.editable(current().data, {"asset": id}, library): return
	var choices: Array = library.directions(id)
	if reset:
		if not items.is_empty() or not tile.is_empty(): current().checkpoint()
		if not tile.is_empty(): tile.erase("family")
		var targets: Array = items if not items.is_empty() else [active]
		for item in targets:
			item["direction"] = str(library.directions(item["asset"])[0])
			item.erase("angle")
			item.erase("tilt")
		direction = active["direction"]
		placement_angle = 0
		placement_tilt = Vector2.ZERO
		if items.is_empty() and tile.is_empty(): refresh_controls()
		else: changed()
		return
	# The supplied sprite views remain available at the traditional 90-degree step.
	if id.begins_with("2d:") and not library.is_ground_tile(id) and choices.size() > 1 and is_equal_approx(rotation_step.value, 90) and is_zero_approx(active.get("angle", 0)):
		if not items.is_empty(): current().checkpoint()
		var targets: Array = items if not items.is_empty() else [active]
		var pivot: Vector3 = arrange_tools.pivot(items)
		for item in targets:
			var views: Array = library.directions(item["asset"])
			if item["asset"].begins_with("3d:") or library.is_ground_tile(item["asset"]): Rotation.set_heading(item, Rotation.heading(item, library) + 90 * step, library)
			elif views.size() > 1: item["direction"] = str(views[posmod(views.find(item["direction"]) + step, views.size())])
			else: Rotation.set_heading(item, Rotation.heading(item, library) + 90 * step, library)
			if arrange_tools.orbit_enabled(items): item["position"] = Rotation.orbit_position(item["position"], pivot, 90 * step, mode)
		direction = active["direction"]
		if items.is_empty(): refresh_controls()
		else: changed()
		rotation_manual = true
	else: set_rotation_value("angle", Rotation.heading(active, library) + rotation_step.value * step)

func utility_connection_panel() -> RefCounted:
	for tools in [utility_tools,power_tools]:
		if tools and tools.panel.is_visible_in_tree(): return tools
	return null

func cycle_connection(step: int) -> void:
	if walking or modal_visible() or worlds[mode].exploration.photo.active: return
	var tools: RefCounted=utility_connection_panel()
	if tools: tools.cycle(step)
	elif connector_tools: connector_tools.cycle(step)

func placement(at: Vector2) -> Dictionary:
	if ground_brush.active(): return ground_brush.preview_position(at)
	var values: Array = worlds[mode].point(at, snap_input.button_pressed, height_input.value)
	if mode == "2d" and worlds[mode].tile_lookup.has(asset_id): return {"position": values, "direction": direction, "tile_cell": true}
	if mode == "3d" and surface_input and surface_input.button_pressed:
		worlds[mode].surface_snapping = true
		values = worlds[mode].surface_point(at, snap_input.button_pressed, height_input.value)
		if not asset_id.is_empty() and not snap_input.button_pressed and arrange_tools.target() == "base":
			if not asset_bounds.has(asset_id):
				var sample: Node3D = preload("res://scripts/builder/asset_instance.gd").make(library, asset_id, mode)
				asset_bounds[asset_id] = Bounds.get_bounds(sample)
				sample.free()
			var rotated_bounds: AABB = Transform3D(Basis.from_euler(Rotation.euler(placement_record()) * (PI / 180.0)), Vector3.ZERO) * asset_bounds[asset_id]
			values[1] -= rotated_bounds.position.y * scale_input.value
	if (snap_input.button_pressed or arrange_tools.target() != "base") and library.assets.has(asset_id):
		var record: Dictionary = placement_record()
		record["scale"] = scale_input.value
		values = GridFit.place(values, record, mode, library, arrange_tools.target())
	if connector_tools and connector_tools.enabled.button_pressed and not asset_id.is_empty():
		var module: Dictionary = placement_record()
		module["position"] = values
		module["scale"] = scale_input.value
		var joint: Dictionary = connector_tools.choose(at, module, current().data)
		if not joint.is_empty():
			var pose: Dictionary = joint.get("pose", module)
			return {"position": pose["position"], "direction": pose["direction"], "angle": pose["angle"], "tilt": pose["tilt"], "socket": joint}
	if arrange_tools.target() == "base" and lanes_input and lanes_input.button_pressed and not asset_id.is_empty():
		var lane: Dictionary = Roads.lane(current().data, values, direction, library, asset_id, scale_input.value)
		if rotation_manual: lane["direction"] = direction
		return lane
	return {"position": values, "direction": direction}

func drop_asset(id: String,at: Vector2) -> void:
	if not preload("res://scripts/builder/asset_palette_policy.gd").allowed(id,library):status.text=preload("res://scripts/builder/asset_palette_policy.gd").excluded(id,library);return
	super.drop_asset(id,at)

func paint(at: Vector2) -> void:
	if not asset_id.is_empty() and not preload("res://scripts/builder/asset_palette_policy.gd").allowed(asset_id,library):status.text=preload("res://scripts/builder/asset_palette_policy.gd").excluded(asset_id,library);return
	if not assembly_active.is_empty():
		if assembly_active.get("companion",false) and companion_tools and not companion_tools.floating.is_empty():companion_tools.review_at(at);return
		var at_values: Array = worlds[mode].point(at, snap_input.button_pressed, height_input.value)
		paste_objects(assembly_active["objects"], at_values, true)
		clear_assembly()
		stroke = false
		return
	if asset_id.is_empty(): return
	if editor_feedback:
		var reason: String=editor_feedback.blocked_reason()
		if not reason.is_empty(): status.text=reason; return
	var layer_name: String = Layers.classify(asset_id, library)
	if Layers.locked(current().data, layer_name) or not Layers.shown(current().data, layer_name):
		status.text = layer_name + " is hidden or locked. Change it in Layers before placing."
		return
	if ground_brush.active():
		ground_brush.paint_once(at)
		return
	var info: Dictionary = placement(at)
	var socket: Dictionary=info.get("socket",{})
	var rejected: String=""
	if connector_tools and connector_tools.preview_changed(at,socket):
		rejected="Connection changed. Review the updated socket before placing."
	elif socket.get("blocked",false): rejected=socket["reason"]
	if not rejected.is_empty():
		status.text=rejected
		if stroke_cells.is_empty():
			stroke=false
			current().finish_checkpoint()
		return
	if editor_feedback:
		var diagnostic: Dictionary=editor_feedback.diagnostics(at,info)
		if diagnostic.get("blocked",false): status.text=diagnostic["text"]; return
	var key: String = str(info["position"]) + ":" + info["direction"] + ":" + str(placement_tilt) + ":" + str(placement_angle)
	if stroke_cells.has(key): return
	stroke_cells[key] = true
	var placed: Dictionary = proposed_placement(info, Document.new_uid())
	current().data["objects"].append(placed)
	if connector_tools: connector_tools.record(current().data, placed, info.get("socket", {}))
	changed()
	if first_build: first_build.on_placed(placed)
	if asset_browser and asset_browser.recents:asset_browser.recents.placed(placed["asset"],placed["uid"])
	if companion_tools and not current().object(placed["uid"]).is_empty():companion_tools.placed(placed["uid"])

func proposed_placement(info: Dictionary, uid: String) -> Dictionary:
	var item: Dictionary = Document.placement_item(uid, asset_id, info["position"], info["direction"], scale_input.value)
	var angle: float = info.get("angle", placement_angle)
	var tilt: Array = info.get("tilt", [placement_tilt.x, placement_tilt.y])
	if not is_zero_approx(angle): item["angle"] = angle
	if not Vector2(tilt[0], tilt[1]).is_zero_approx(): item["tilt"] = tilt
	return item

func erase(at: Vector2) -> void:
	var uid: String = worlds[mode].pick(at)
	if not uid.is_empty():
		current().data["objects"].erase(current().object(uid))
		selected_uids.erase(uid)
		selected_uid = ""
		changed()
	elif mode == "2d" and Layers.shown(current().data, "Ground") and not Layers.locked(current().data, "Ground"): super.erase(at)

func screen_bounds(uid: String) -> Rect2:
	if not worlds[mode].instances.has(uid): return Rect2()
	var instance: Node = worlds[mode].instances[uid]
	if mode == "2d":
		var sprite: Sprite2D = instance.get_node_or_null("Sprite2D")
		if not sprite: return Rect2()
		return viewport.get_canvas_transform() * (sprite.global_transform * sprite.get_rect())
	var bounds: AABB = instance.transform * Bounds.get_bounds(instance)
	var box := Rect2()
	for index in 8:
		var point: Vector3 = bounds.get_endpoint(index)
		if worlds[mode].camera.is_position_behind(point): return Rect2()
		var projected: Vector2 = worlds[mode].camera.unproject_position(point)
		box = Rect2(projected, Vector2.ZERO) if index == 0 else box.expand(projected)
	return box

func select_at(at: Vector2, additive: bool) -> void:
	var uid: String = worlds[mode].pick(at)
	selected_cell = null
	if uid.is_empty():
		if not additive: selected_uids.clear()
		selected_uid = ""
		marquee_active = true
		marquee_additive = additive
		if mode == "2d" and Layers.shown(current().data, "Ground") and not Layers.locked(current().data, "Ground"):
			var location: Array = worlds[mode].point(at, true, 0)
			selected_cell = IsoMath.world_to_tile(Vector2(location[0], location[1]))
	else:
		var item: Dictionary = current().object(uid)
		var ids: Array[String] = [uid]
		if item.has("group"):
			for member in current().data["objects"]:
				if member.get("group") == item["group"] and Layers.editable(current().data, member, library) and not ids.has(member["uid"]): ids.append(member["uid"])
		var remove: bool = additive and selected_uids.has(uid)
		if not additive and not selected_uids.has(uid): selected_uids.clear()
		for member in ids:
			if remove: selected_uids.erase(member)
			elif not selected_uids.has(member): selected_uids.append(member)
		selected_uid = selected_uids[0] if not selected_uids.is_empty() else ""
	drag_origins.clear()
	for item in selection_items(): drag_origins[item["uid"]] = item["position"].duplicate()
	refresh_controls()

func _canvas_input(event: InputEvent) -> void:
	if enhancements_ready and worlds[mode].exploration.photo.active:
		if event is InputEventMouseButton and event.pressed and photo_tools: photo_tools.release_focus()
		worlds[mode].exploration.photo.input(event); return
	if companion_tools and companion_tools.canvas_input(event):return
	if small_prop_tools and (event is InputEventMouseMotion or (event is InputEventMouseButton and event.pressed)) and small_prop_tools.over_ui(event.position+canvas.global_position):return
	if control_settings and not control_settings.synthetic_input and event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		control_settings.finish_drag()
		control_settings.cursor_active=false
		control_settings.marker.queue_redraw()
	if not enhancements_ready or walking:
		super._canvas_input(event)
		return
	if terrain_tools and terrain_tools.input(event): return
	if modular_building_tools and modular_building_tools.input(event): return
	if cooperative_tools and cooperative_tools.input(event): return
	if blueprint_tools and blueprint_tools.input(event): return
	if zone_tools and zone_tools.input(event): return
	if transform_handles and transform_handles.input(event): return
	if event is InputEventMouseButton and event.pressed and event.alt_pressed and overlap_picker.available():
		if event.button_index==MOUSE_BUTTON_LEFT: overlap_picker.cycle(event.position,-1 if event.shift_pressed else 1); return
		if event.button_index==MOUSE_BUTTON_RIGHT: overlap_picker.show(event.position); return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and arrange_tools.picking_pivot:
		arrange_tools.set_custom(worlds[mode].point(event.position, snap_input.button_pressed, height_input.value))
		status.text = "Custom pivot set. Rotate or resize the selection around the crosshair."
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			finish_edit(event.position)
			return
		var focus: Control = get_viewport().gui_get_focus_owner()
		if focus: focus.release_focus()
		if ground_brush.active():
			if Layers.locked(current().data, "Ground") or not Layers.shown(current().data, "Ground"):
				status.text = "Unlock and show Ground in Layers before painting."
				return
			current().checkpoint()
			stroke = true
			stroke_cells.clear()
			ground_brush.begin(event.position)
			return
		if tool == "color":
			color_editor.pick(event.position)
			return
		if tool in ["road", "road_erase", "crossing"]:
			if Layers.locked(current().data, "Ground") or not Layers.shown(current().data, "Ground"):
				status.text = "Unlock and show Ground in Layers to edit roads."
				return
			if tool=="crossing" and editor_feedback:
				var diagnostic: Dictionary=editor_feedback.diagnostics(event.position,{})
				if diagnostic.get("blocked",false): status.text=diagnostic["text"]; return
			current().checkpoint()
			var values: Array = worlds[mode].point(event.position, false, 0)
			road_last = Roads.cell_at(values, mode)
			if tool == "crossing":
				var network: Dictionary = Roads.lookup(current().data)
				if network.has(Roads.key(road_last)): network[Roads.key(road_last)]["crossing"] = not network[Roads.key(road_last)].get("crossing", false)
			else:
				road_drawing = true
				Roads.paint(current().data, road_last, road_last, tool == "road_erase", road_settings.settings())
			changed()
			return
		if tool == "select":
			stroke = true
			moved_selection = false
			selection_press = event.position
			select_at(event.position, event.shift_pressed)
			return
	if event is InputEventMouseMotion:
		if ground_brush.drawing:
			ground_brush.move(event.position)
			return
		if road_drawing:
			var cell: Vector2i = Roads.cell_at(worlds[mode].point(event.position, false, 0), mode)
			if cell != road_last:
				Roads.paint(current().data, road_last, cell, tool == "road_erase", road_settings.settings())
				road_last = cell
				changed()
			return
		if stroke and tool == "select" and not panning and not orbiting:
			if marquee_active:
				overlay.marquee = Rect2(selection_press, event.position - selection_press).abs()
				overlay.marquee_visible = event.position.distance_to(selection_press) > 6
				return
			if drag_origins.is_empty(): return
			if not moved_selection:
				if event.position.distance_to(selection_press) < 6: return
				current().checkpoint()
				moved_selection = true
			var start: Array = worlds[mode].point(selection_press, snap_input.button_pressed, height_input.value)
			var end: Array = worlds[mode].point(event.position, snap_input.button_pressed, height_input.value)
			for item in selection_items():
				var original: Array = drag_origins.get(item["uid"], item["position"])
				item["position"] = [original[0] + end[0] - start[0], original[1] + end[1] - start[1], original[2] + end[2] - start[2]]
				if drag_origins.size() == 1 and snap_input.button_pressed:
					item["position"] = GridFit.snap(item, mode, library, arrange_tools.target())
				if drag_origins.size() == 1 and arrange_tools.target() == "base" and lanes_input.button_pressed and preload("res://scripts/builder/asset_behavior.gd").for_asset(item["asset"], library).get("vehicle", false):
					var lane: Dictionary = Roads.lane(current().data, item["position"], item["direction"], library, item["asset"], item["scale"])
					if lane.get("snapped", false):
						item["position"] = lane["position"]
						item["direction"] = lane["direction"]
			changed()
			return
	super._canvas_input(event)

func finish_edit(at: Vector2) -> void:
	if cooperative_tools and cooperative_tools.drawing: cooperative_tools.cancel_draw()
	if blueprint_tools and blueprint_tools.dragging: blueprint_tools.cancel()
	if terrain_tools: terrain_tools.finish()
	if zone_tools and zone_tools.drawing: zone_tools.finish_draw(at)
	if transform_handles: transform_handles.finish()
	if control_settings:
		control_settings.dragging=false
		control_settings.marker.queue_redraw()
	if ground_brush and ground_brush.drawing: ground_brush.finish(at)
	road_drawing = false
	if marquee_active:
		if overlay.marquee_visible:
			var box := Rect2(selection_press, at - selection_press).abs()
			if not marquee_additive: selected_uids.clear()
			for item in current().data["objects"]:
				if Layers.editable(current().data, item, library) and box.intersects(screen_bounds(item["uid"])) and not selected_uids.has(item["uid"]): selected_uids.append(item["uid"])
			selected_uid = selected_uids[0] if not selected_uids.is_empty() else ""
			selected_cell = null
		marquee_active = false
		overlay.marquee_visible = false
		refresh_controls()
	finish_stroke()

func modal_visible() -> bool:
	if construction_cost_tools and construction_cost_tools.comparison.dialog.visible: return true
	if asset_browser and asset_browser.collections and asset_browser.collections.modal():return true
	if companion_tools and companion_tools.dialog.visible:return true
	if consumer_shell and consumer_shell.active and (not consumer_shell.sheet_kind.is_empty() or consumer_shell.rename_dialog.visible): return true
	if neighborhood_tools and neighborhood_tools.dialog.visible: return true
	if walking and worlds[mode].exploration.runtime_modal(): return true
	if interior_tools and interior_tools.floor_tools.dialog.visible: return true
	if interior_tools and interior_tools.kit_chooser and interior_tools.kit_chooser.dialog.visible:return true
	if interior_tools and interior_tools.floor_tools.connections.dialog.visible: return true
	if interior_tools and interior_tools.floor_tools.entrances.dialog.visible: return true
	if accessibility_settings and accessibility_settings.dialog.visible: return true
	if control_settings and control_settings.dialog.visible: return true
	if editor_feedback and editor_feedback.dialog.visible: return true
	if overlap_picker and overlap_picker.popup.visible: return true
	if asset_browser and asset_browser.dialog.visible: return true
	if asset_browser and asset_browser.health_tools and asset_browser.health_tools.modal_visible():return true
	return (repair_tools and (repair_tools.dialog.visible or repair_tools.report_file.visible)) or (command_palette and command_palette.dialog.visible) or file_dialog.visible or (browser and browser.visible) or (name_dialog and name_dialog.visible) or (assembly_dialog and assembly_dialog.visible) or (color_editor and color_editor.tile_dialog and color_editor.tile_dialog.visible)

func _input(event: InputEvent) -> void:
	if enhancements_ready and walking and worlds[mode].exploration.village.has_menu():
		if event is InputEventKey and event.pressed and not event.echo and control_settings.match_event(event) == "cancel":
			worlds[mode].exploration.village.close()
			get_viewport().set_input_as_handled()
		return
	if enhancements_ready and walking and worlds[mode].exploration.pet.has_menu():
		if event is InputEventKey and event.pressed and not event.echo and control_settings.match_event(event)=="cancel":
			worlds[mode].exploration.pet.close()
			get_viewport().set_input_as_handled()
		return
	if enhancements_ready and walking and worlds[mode].exploration.arcade.active():
		var action: String=control_settings.match_event(event) if event is InputEventKey else ""
		if action == "ambience_mute" and event.pressed and not event.echo:
			control_settings.execute(action)
			get_viewport().set_input_as_handled()
			return
		if worlds[mode].exploration.arcade.input(event,action): get_viewport().set_input_as_handled()
		return
	if consumer_shell and consumer_shell.input(event): get_viewport().set_input_as_handled(); return
	if enhancements_ready and control_settings and control_settings.input(event):
		get_viewport().set_input_as_handled()
		return
	if enhancements_ready and modal_visible(): return
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT and enhancements_ready: finish_edit(canvas_pointer())
	if not enhancements_ready or not event is InputEventKey: super._input(event)

func _unhandled_key_input(event: InputEvent) -> void:
	if enhancements_ready and walking and worlds[mode].exploration.arcade.active():
		get_viewport().set_input_as_handled()
		return
	if not enhancements_ready: super._unhandled_key_input(event); return
	if control_settings and control_settings.unhandled(event): get_viewport().set_input_as_handled()

func canvas_pointer() -> Vector2:
	return control_settings.pointer() if control_settings else canvas.get_local_mouse_position()

func camera_movement() -> Vector2:
	if transform_handles and transform_handles.dragging: return Vector2.ZERO
	if get_viewport().gui_get_focus_owner(): return Vector2.ZERO
	return control_settings.movement() if control_settings else super.camera_movement()

func _process(delta: float) -> void:
	capability_elapsed+=delta
	if consumer_shell: consumer_shell.tick(delta)
	if enhancements_ready and accessibility_settings: accessibility_settings.tick()
	if enhancements_ready: interior_tools.refresh()
	if enhancements_ready and selection_inspector: selection_inspector.tick_context()
	if enhancements_ready and small_prop_tools:small_prop_tools.tick()
	if not enhancements_ready:
		super._process(delta)
		return
	if modular_building_tools and modular_building_tools.panel.is_visible_in_tree():
		modular_building_tools.synchronize()
	elif tool=="modular_room" and not walking:
		set_tool("select")
	if asset_browser: asset_browser.tick(delta)
	placement_hint.visible = tool == "place" and not asset_id.is_empty() and not walking
	if placement_hint.visible: placement_hint.text = ("Repeat placement" if repeat_input.button_pressed else "Place once") + " · " + library.assets[asset_id]["name"]
	var modal: bool = modal_visible()
	if mode == "3d" and not is_equal_approx(compass_view_yaw, model_view_yaw()):
		var record: Dictionary = current().object(selected_uid)
		if record.is_empty(): record = placement_record()
		refresh_compass(record.get("asset", ""), record)
		if rotation_controls.choice.selected == 3 and not angle_input.get_line_edit().has_focus():
			rotation_controls.refresh(record)
			if selection_inspector: selection_inspector.refresh()
	if not modal: super._process(delta)
	else:
		if mode == "3d": worlds[mode].player.active = false
		else: worlds[mode].player.is_player_controlled = false
	var inside: bool = (control_settings.cursor_active or pointer_in_canvas()) and not modal and not walking and not worlds[mode].exploration.photo.active
	if mode == "3d": worlds[mode].surface_snapping = surface_input.button_pressed
	if not asset_id.is_empty() and inside and tool == "place":
		var info: Dictionary = placement(canvas_pointer())
		worlds[mode].preview(asset_id, info["position"], info["direction"], scale_input.value, true)
		var preview_record: Dictionary = placement_record()
		preview_record["direction"] = info["direction"]
		preview_record["angle"] = info.get("angle", placement_angle)
		preview_record["tilt"] = info.get("tilt", [placement_tilt.x, placement_tilt.y])
		Factory.pose(worlds[mode].ghost, preview_record, current().data["night"])
	update_overlay(inside)
	update_assembly_preview(inside)
	if editor_feedback:
		editor_feedback.walk_prompt.visible=walking
		if walking:
			editor_feedback.walk_prompt.text=interior_tools.walk_prompt() if interior_tools.editing() and worlds[mode].exploration.interior == null else worlds[mode].exploration.prompt()
			if control_settings: editor_feedback.walk_prompt.text=control_settings.walk_hint(editor_feedback.walk_prompt.text)
		editor_feedback.tick(delta)
	if first_build: first_build.tick()
	if transform_handles: transform_handles.tick()
	if citizen_tools: citizen_tools.tick(delta)
	if school_tools: school_tools.tick(delta)
	if traffic_tools: traffic_tools.tick(delta)
	if business_tools: business_tools.tick(delta)
	if service_tools: service_tools.tick(delta)
	if economy_tools: economy_tools.tick(delta)
	if construction_cost_tools: construction_cost_tools.tick(delta)
	if scenario_tools: scenario_tools.tick(delta)
	if zone_tools: zone_tools.tick(delta)
	if transit_tools: transit_tools.tick(delta)
	if terrain_tools: terrain_tools.tick(delta)
	if ambience_tools: ambience_tools.tick(delta)
	if weather_tools: weather_tools.tick(delta)
	if prop_tools: prop_tools.tick(delta)
	if driving_tools: driving_tools.tick(delta)
	if delivery_tools: delivery_tools.tick(delta)
	if market_tools: market_tools.tick(delta)
	if vehicle_service_tools: vehicle_service_tools.tick(delta)
	if cooperative_tools: cooperative_tools.tick(delta)
	if asset_browser and asset_browser.recents:asset_browser.recents.tick()
	if companion_tools:companion_tools.tick(delta)
	if asset_import_tools: asset_import_tools.tick(delta)
	if blueprint_tools: blueprint_tools.tick(delta)
	if photo_tools: photo_tools.tick(delta)
	if utility_tools: utility_tools.tick(delta)
	if garden_tools and garden_tools.panel.is_visible_in_tree(): garden_tools.refresh()
	if cooking_tools and cooking_tools.panel.is_visible_in_tree(): cooking_tools.refresh()
	if laundry_tools and laundry_tools.panel.is_visible_in_tree(): laundry_tools.refresh()
	if fitness_tools and fitness_tools.panel.is_visible_in_tree(): fitness_tools.refresh()
	if arcade_tools: arcade_tools.tick()
	if camping_tools and camping_tools.panel.is_visible_in_tree(): camping_tools.refresh()
	if pet_tools and pet_tools.panel.is_visible_in_tree(): pet_tools.refresh()
	if cycling_tools and cycling_tools.panel.is_visible_in_tree(): cycling_tools.refresh()
	if harbor_tools and harbor_tools.panel.is_visible_in_tree(): harbor_tools.refresh()
	if outpost_tools and outpost_tools.panel.is_visible_in_tree(): outpost_tools.refresh()
	if village_tools and village_tools.panel.is_visible_in_tree(): village_tools.refresh()
	if power_tools: power_tools.tick(delta)
	if simulation_diagnostic_tools: simulation_diagnostic_tools.tick(delta)
	if capability_elapsed>=.4:
		capability_elapsed=0;refresh_capabilities()
	if worlds[mode].exploration.photo.active:
		mode_badge.text="PHOTO MODE · "+control_settings.label_for("photo")+" returns · "+control_settings.label_for("move_up")+" move camera · "+control_settings.label_for("photo_capture")+" screenshot"; mode_badge.modulate=Color("e2b6ff")
		if worlds[mode].exploration.photo.recording: mode_badge.text+=" · REC %.1fs"%worlds[mode].exploration.photo.record_elapsed
	elif mode_badge.text.begins_with("PHOTO MODE"):
		control_settings.refresh_mode_hint(); mode_badge.modulate=Color("ffdf83") if walking else Color("8fdccb")
	workspace_elapsed += delta
	recovery_elapsed += delta
	if storage_enabled and workspace_elapsed >= 10:
		workspace_elapsed = 0
		capture_workspace()
		Store.write_json("user://studio_workspace.json", workspace)
		update_save_badge()
	if storage_enabled and recovery_elapsed >= 120:
		recovery_elapsed = 0
		if content_digest() != recovery_digest:
			Store.snapshot(session_data(), "Automatic recovery · " + current().data["title"], thumbnail(), true)
			recovery_digest = content_digest()

func terrain_height(values: Array) -> float:
	var world: Node=worlds[mode]
	if not world.terrain_traversal.active(): return 0.0
	var point: Vector2=preload("res://scripts/builder/traffic_plan.gd").metric(values,mode)
	return preload("res://scripts/builder/terrain_plan.gd").sample(current().data,point,world.terrain_traversal.heights)["height"]
func overlay_position(values: Array, fixed_height: Variant=null) -> Vector2:
	if mode == "2d": return viewport.get_canvas_transform() * Vector2(values[0], values[1] - (values[2] + (terrain_height(values) if fixed_height==null else float(fixed_height))) * 8)
	return worlds[mode].camera.unproject_position(Vector3(values[0], values[1], values[2]))

func connection_area() -> Rect2:
	if not consumer_shell or not consumer_shell.active: return Rect2(Vector2.ZERO,overlay.size)
	var origin: Vector2=overlay.global_position
	var top: float=maxf(consumer_shell.header.get_global_rect().end.y,consumer_shell.header_actions.get_global_rect().end.y)-origin.y
	var bottom: float=consumer_shell.hint_panel.global_position.y-origin.y
	var right: float=overlay.size.x
	if consumer_shell.details.is_visible_in_tree(): right=consumer_shell.details.global_position.x-origin.x
	return Rect2(0,top+8,maxf(0,right-8),maxf(0,bottom-top-16))

func update_overlay(inside: bool) -> void:
	if walking: return
	var feedback_info: Dictionary={}
	var overlap_name: String=""
	overlay.caption_position = canvas_pointer() + Vector2(18, 22)
	overlay.caption_area = Rect2()
	overlay.snap_visible = false
	overlay.socket_markers = []
	overlay.socket_area = Rect2()
	overlay.socket_line = PackedVector2Array()
	overlay.brush_polygon = ground_brush.preview_polygon(canvas_pointer()) if ground_brush.drawing else PackedVector2Array()
	overlay.terrain_ring=terrain_tools.preview_circle(canvas_pointer()) if inside and tool=="terrain" else PackedVector2Array()
	overlay.terrain_markers=PackedVector2Array()
	overlay.modular_paths=modular_building_tools.overlay_paths(inside) if modular_building_tools else []
	overlay.pivot_visible = not walking and not selection_items().is_empty() and arrange_tools.pivot_mode.selected != 1
	if overlay.pivot_visible:
		var pivot: Vector3 = arrange_tools.pivot(selection_items())
		overlay.pivot_point = transform_handles.project(pivot) if transform_handles.eligible() else overlay_position([pivot.x, pivot.y, pivot.z])
	if color_editor: color_editor.draw_selection(overlay)
	overlay.boxes.clear()
	for item in selection_items(): overlay.boxes.append(screen_bounds(item["uid"]))
	overlay.tile_outline=PackedVector2Array()
	if mode=="2d" and selected_cell is Vector2i:
		for point in IsoMath.get_footprint_diamond(Vector2i.ZERO,Vector2i.ONE):
			var at: Vector2=IsoMath.tile_to_world(selected_cell)+point; overlay.tile_outline.append(overlay_position([at.x,at.y,0]))
	overlay.footprint = PackedVector2Array()
	overlay.warning = false
	overlay.caption = ""
	if inside and tool in ["road", "crossing", "road_erase"]: overlay.caption = "Roads · drag to connect sections" if tool == "road" else ("Crossings · click a road section" if tool == "crossing" else "Remove roads · original ground is preserved")
	var world: Node = worlds[mode]
	var socket: Dictionary={}
	if inside and tool == "place" and world.ghost and world.ghost.visible:
		if mode == "2d":
			var polygon: PackedVector2Array = preload("res://scripts/builder/asset_instance.gd").footprint(world.ghost)
			polygon = world.ghost.global_transform * polygon
			overlay.footprint = viewport.get_canvas_transform() * polygon
			var rise: Vector2=viewport.get_canvas_transform().basis_xform(Vector2(0,-float(world.ghost.get_meta("terrain_height",0))*8))
			for index in overlay.footprint.size(): overlay.footprint[index]+=rise
			for item in current().data["objects"]:
				if Layers.layer(item, library) == "Ground" or not world.instances[item["uid"]].visible: continue
				var node: Node2D = world.instances[item["uid"]]
				var other: PackedVector2Array = preload("res://scripts/builder/asset_instance.gd").footprint(node)
				if not Geometry2D.intersect_polygons(polygon, node.global_transform * other).is_empty():
					overlay.warning=true
					overlap_name=item.get("name",library.assets[item["asset"]]["name"])
					break
		else:
			var bounds: AABB = world.ghost.transform * Bounds.get_bounds(world.ghost)
			var points: Array[Vector2] = []
			for corner in [Vector3(bounds.position.x, bounds.position.y, bounds.position.z), Vector3(bounds.end.x, bounds.position.y, bounds.position.z), Vector3(bounds.end.x, bounds.position.y, bounds.end.z), Vector3(bounds.position.x, bounds.position.y, bounds.end.z)]: points.append(world.camera.unproject_position(corner))
			overlay.footprint = PackedVector2Array(points)
			# Clamp the warning clearance for thin props and flat sprite cards.
			var inset: Vector3=bounds.size.min(Vector3.ONE*.08)*.5
			var overlap_bounds:=AABB(bounds.position+inset,bounds.size-inset*2)
			for item in current().data["objects"]:
				if Layers.layer(item, library) == "Ground" or not world.instances[item["uid"]].visible: continue
				var other: Node3D = world.instances[item["uid"]]
				if overlap_bounds.intersects(other.transform * Bounds.get_bounds(other)):
					overlay.warning=true
					overlap_name=item.get("name",library.assets[item["asset"]]["name"])
					break
		var layer_name: String = Layers.classify(asset_id, library)
		if Layers.locked(current().data, layer_name) or not Layers.shown(current().data, layer_name):
			overlay.warning = true
			overlay.caption = layer_name + " layer is hidden or locked"
		else: overlay.caption = "Overlapping footprints · placement is allowed" if overlay.warning else "Footprint clear · click to place"
		if not overlap_name.is_empty(): overlay.caption="Overlaps "+overlap_name+" · placement is allowed"
		var info: Dictionary = placement(canvas_pointer())
		feedback_info=info
		socket=info.get("socket",{})
		var record: Dictionary = placement_record()
		record["position"] = info["position"]
		record["direction"] = info["direction"]
		record["scale"] = scale_input.value
		overlay.snap_visible = not info.get("socket", {}).get("ok", false)
		overlay.snap_point = overlay_position(info["position"] if info.get("tile_cell", false) else GridFit.anchor_position(record, mode, library, "base" if info.get("ground_cell", false) else arrange_tools.target()))
		var anchor_name: String = arrange_tools.snap_target.get_item_text(arrange_tools.snap_target.selected)
		if info.get("snapped", false): anchor_name = "Road lane center"
		if info.get("tile_cell", false): anchor_name = "Ground tile cell"
		elif info.get("ground_cell", false): anchor_name = "Ground brush cell"
		overlay.caption = ("Repeat placement" if repeat_input.button_pressed else "Place once") + " · " + anchor_name + "\n" + overlay.caption
	if ground_brush.drawing and inside: overlay.caption = ground_brush.operation.get_item_text(ground_brush.operation.selected) + (" · finish canvas drag to commit" if control_settings and control_settings.dragging else " · release to finish") + " · Undo reverses the gesture"
	if arrange_tools.picking_pivot and inside: overlay.caption = "Choose custom pivot · click to set · Escape cancels"
	if inside and tool=="terrain" and terrain_tools:
		overlay.caption="Terrain · "+terrain_tools.operation.get_item_text(terrain_tools.operation.selected)+" · drag to sculpt · right-click cancels"
	if inside and tool=="zone" and zone_tools:
		overlay.caption="Zoning · "+zone_tools.kind.get_item_text(zone_tools.kind.selected)+" · drag a ground rectangle"
		if zone_tools.drawing:
			var bounds: Rect2=zone_tools.drawn_rect()
			overlay.caption+="\n%.0f × %.0f units · release to designate" % [bounds.size.x,bounds.size.y]
			overlay.warning=bounds.size.x<4 or bounds.size.y<4 or bounds.size.x>64 or bounds.size.y>64
			if overlay.warning: overlay.caption+="\nLots must be 4–64 units wide and deep"
			elif current().data.get("zones",[]).any(func(lot: Dictionary):return preload("res://scripts/builder/zone_plan.gd").rectangle(lot).intersects(bounds)): overlay.caption+="\nOverlaps an existing lot"; overlay.warning=true
	if editor_feedback and inside and not arrange_tools.picking_pivot:
		var diagnostic: Dictionary=editor_feedback.diagnostics(canvas_pointer(),feedback_info)
		if not diagnostic.get("text","").is_empty():
			var prefix: String=""
			if socket.is_empty() or not socket.get("ok",false):
				prefix=overlay.caption.get_slice("\n",0) if diagnostic.get("blocked",false) and tool=="place" else overlay.caption if not diagnostic.get("blocked",false) else ""
			overlay.caption=(prefix+"\n" if not prefix.is_empty() else "")+diagnostic["text"]
			overlay.warning=overlay.warning or diagnostic.get("warning",false)
	var utilities: RefCounted=utility_connection_panel() if not modal_visible() else null
	if connector_tools:
		overlay.socket_markers=connector_tools.markers(socket)
		connector_tools.present(canvas_pointer(),socket)
	if overlay.socket_markers.is_empty() and utilities:
		overlay.socket_markers=utilities.markers()
		if overlay.socket_markers.size()==2:
			overlay.socket_line=PackedVector2Array([overlay.socket_markers[0]["at"],overlay.socket_markers[1]["at"]])
			var reason: String=utilities.preview()["reason"]
			if overlay.caption.is_empty() and not reason.is_empty():
				overlay.caption=utilities.title+" · "+reason
				overlay.caption_position=connection_area().position+Vector2(12,12)
	if not overlay.socket_markers.is_empty(): overlay.socket_area=connection_area()
	if inside and mode=="2d" and (tool=="terrain" or ground_brush.active()):
		show_terrain_warnings()
	overlay.queue_redraw()

func show_terrain_warnings() -> void:
	var world: Node=worlds["2d"]
	var warnings: Dictionary=world.family_warnings.duplicate()
	warnings.merge(world.terrain.family_warnings,true)
	var nearest: float=28.0
	var reason: String=""
	var area: Rect2=connection_area().grow(-12)
	for cell in warnings:
		var pixel: Vector2=GridFit.pixels(Vector2(cell)+Vector2.ONE*.5)
		var level: float=world.family_levels.get(cell,0.0) if world.terrain.visible else 0.0
		var at: Vector2=overlay_position([pixel.x,pixel.y,level],0.0)
		if not area.has_point(at): continue
		overlay.terrain_markers.append(at)
		var distance: float=at.distance_to(canvas_pointer())
		if distance<nearest:
			nearest=distance
			reason=warnings[cell]
		if overlay.terrain_markers.size()>=64: break
	if not reason.is_empty():
		overlay.caption=reason
		overlay.caption_area=area

func ask_name(action: String) -> void:
	name_action = action
	name_dialog.title = "Name this snapshot" if action == "snapshot" else "Name this reusable assembly"
	name_field.text = current().data["title"] if action == "snapshot" else "My assembly"
	name_dialog.popup_centered()
	name_field.grab_focus()
	name_field.select_all()

func confirm_name() -> void:
	var title: String = name_field.text.strip_edges()
	if title.is_empty(): return
	if name_action == "snapshot":
		if storage_enabled:
			var path: String = Store.snapshot(session_data(), title, thumbnail())
			status.text = "Snapshot saved: " + title if not path.is_empty() else "Snapshot could not be saved."
		show_projects()
	else:
		var items: Array = selection_items().duplicate(true)
		if items.is_empty(): return
		var origin: Array = items[0]["position"].duplicate()
		for item in items:
			for i in 3: item["position"][i] -= origin[i]
		assemblies.append({"name": title, "mode": mode, "objects": items})
		if storage_enabled: Store.write_json("user://studio_assemblies.json", assemblies)
		status.text = "Assembly saved. Find it under My assemblies."

func show_assemblies() -> void:
	assembly_list.clear()
	for index in assemblies.size():
		var entry: Variant = assemblies[index]
		if entry is Dictionary and entry.get("mode") == mode and entry.get("objects") is Array:
			assembly_list.add_item(str(entry.get("name", "Assembly")) + " · %d objects" % entry["objects"].size())
			assembly_list.set_item_metadata(assembly_list.item_count - 1, index)
	assembly_dialog.popup_centered()

func choose_assembly() -> void:
	if assembly_list.get_selected_items().is_empty(): return
	var entry: Dictionary = assemblies[assembly_list.get_item_metadata(assembly_list.get_selected_items()[0])]
	begin_assembly(entry)

func begin_assembly(entry: Dictionary) -> bool:
	var test: Dictionary = {"mode": mode, "title": "Assembly", "objects": entry["objects"], "tiles": [], "night": false}
	if not Document.valid(test, mode, library):
		status.text = "This assembly uses invalid or missing assets."
		return false
	clear_placement()
	assembly_active = entry.duplicate(true)
	set_tool("place")
	assembly_dialog.hide()
	for item in entry["objects"]:
		var node: Node = preload("res://scripts/builder/asset_instance.gd").make(library, item["asset"], mode)
		worlds[mode].add_child(node)
		Layers.collision_visibility(node, false)
		Factory.pose(node, item)
		preload("res://scripts/builder/part_colors.gd").apply(node, item)
		if mode == "2d": node.modulate.a = 0.45
		else:
			preload("res://scripts/builder/asset_instance.gd").orient(node, item["direction"])
			var material := StandardMaterial3D.new()
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.albedo_color = Color(0.3, 1, 0.8, 0.35)
			for mesh in node.find_children("*", "MeshInstance3D", true, false):
				if node.has_method("mixed_bounds"): mesh.transparency = 0.55
				else: mesh.material_override = material
		assembly_ghosts.append(node)
	status.text = "Click to place the whole assembly. Escape cancels."
	return true

func update_assembly_preview(inside: bool) -> void:
	if assembly_active.is_empty(): return
	var values: Array = companion_tools.anchor_at(canvas_pointer()) if assembly_active.get("companion",false) and companion_tools and not companion_tools.floating.is_empty() else worlds[mode].point(canvas_pointer(), snap_input.button_pressed, height_input.value)
	for i in assembly_ghosts.size():
		var node: Node = assembly_ghosts[i]
		var item: Dictionary = assembly_active["objects"][i]
		node.visible = inside and tool == "place"
		if mode == "2d":
			node.position = Vector2(values[0] + item["position"][0], values[1] + item["position"][1] - (values[2] + item["position"][2]) * 8)
			node.scale = Vector2.ONE * item["scale"]
			worlds[mode].terrain_presentation.present(node,float(values[2])+float(item["position"][2]))
		else:
			node.position = Vector3(values[0] + item["position"][0], values[1] + item["position"][1], values[2] + item["position"][2])
			node.scale = Vector3.ONE * item["scale"]

func clear_assembly() -> void:
	if companion_tools:companion_tools.cancel_floating()
	for node in assembly_ghosts:
		if is_instance_valid(node): node.free()
	assembly_ghosts.clear()
	assembly_active = {}

func thumbnail() -> Image:
	if DisplayServer.get_name() == "headless": return null
	return viewport.get_texture().get_image()

func show_projects() -> void:
	recovery_filter.clear()
	recovery_filter.add_item("This project · " + recovery_title())
	recovery_filter.set_item_metadata(0,project_id)
	recovery_filter.add_item("All projects")
	recovery_filter.set_item_metadata(1,"all")
	var seen: Dictionary = {project_id:true}
	if storage_enabled:
		for entry in Store.entries(true):
			var id: String = "legacy" if entry.get("legacy_unassigned",false) else entry.get("project_id","")
			if seen.has(id): continue
			seen[id] = true
			recovery_filter.add_item("Legacy copies · source unknown" if id == "legacy" else entry.get("project_title","Project") + " · " + id.substr(0,8))
			recovery_filter.set_item_metadata(recovery_filter.item_count-1,id)
	recovery_filter.select(0)
	populate_projects()
	browser.popup_centered(Vector2i(get_viewport().get_visible_rect().size - Vector2(64,64)).min(Vector2i(1000,650)))

func populate_projects() -> void:
	project_list.clear()
	browser_entries = []
	var filter: String = str(recovery_filter.get_item_metadata(maxi(0,recovery_filter.selected)))
	var all: Array = Store.entries(true) if storage_enabled else []
	for entry in all:
		var id: String = "legacy" if entry.get("legacy_unassigned",false) else entry.get("project_id","")
		if filter != "all" and id != filter: continue
		browser_entries.append(entry)
		var icon: Texture2D
		if FileAccess.file_exists(entry.get("thumbnail", "")):
			var picture := Image.load_from_file(entry["thumbnail"])
			if picture and not picture.is_empty(): icon = ImageTexture.create_from_image(picture)
		var origin: String = entry.get("project_path","")
		var association: String = "Legacy copy · source unknown" if entry.get("legacy_unassigned",false) else entry.get("project_title","Project") + " · " + id.substr(0,8)
		project_list.add_item("%s · %s · %s · %s" % [association,str(entry.get("kind","project")).capitalize(),entry["title"],entry.get("time","")],icon)
		project_list.set_item_tooltip(project_list.item_count-1,"Source: " + (origin if not origin.is_empty() else "Unsaved project") + "\nCopy: " + entry["path"])
	recovery_caption.text = ("History for " + recovery_title() + " · " + (project_origin_path if not project_origin_path.is_empty() else "Unsaved project") if filter == project_id else "Choose a copy by its project, source path and time.") + " · %d entries" % browser_entries.size()
	recovery_caption.tooltip_text = recovery_caption.text
	if not browser_entries.is_empty(): project_list.select(0); show_recovery_details(0)
	else: recovery_details.text = "No copies for this project yet. Autosaves are kept after changes and on close."

func show_recovery_details(index: int) -> void:
	if index < 0 or index >= browser_entries.size(): return
	var entry: Dictionary = browser_entries[index]
	var origin: String = entry.get("project_path","")
	recovery_details.text = "%s · %s · %s\nSource: %s\nCopy: %s" % [entry.get("project_title","Project"),entry.get("title",""),entry.get("time",""),origin if not origin.is_empty() else "Unsaved project / source unknown",entry["path"]]
	recovery_details.tooltip_text = recovery_details.text

func restore_selected() -> void:
	if project_list.get_selected_items().is_empty(): return
	var entry: Dictionary = browser_entries[project_list.get_selected_items()[0]]
	if storage_enabled: Store.snapshot(session_data(), "Before restoring · " + current().data["title"], thumbnail(), true)
	if load_project(entry["path"]):
		if entry.get("kind") != "project": project_path = ""; saved_digest = ""; dirty = true
		browser.hide()
		update_save_badge()

func capture_workspace() -> void:
	if not enhancements_ready: return
	if interior_tools and interior_tools.editing(): return
	var view: Dictionary = {"rotation_mode": rotation_controls.choice.selected, "piece_selection": {"expansion": color_editor.expansion.value, "protect_visible": color_editor.protect_visible.button_pressed}, "roads": road_settings.settings(), "ground_brush": ground_brush.settings(), "arrange": arrange_tools.settings(), "rotation_step": rotation_step.value, "asset_type": asset_type.selected, "category": category.get_item_text(maxi(0, category.selected)), "query": search.text, "page": page, "tool": tool,
		"snap": snap_input.button_pressed, "repeat": repeat_input.button_pressed, "surface": surface_input.button_pressed, "lanes": lanes_input.button_pressed, "favorites": favorites_only.button_pressed}
	if mode == "2d": view["camera"] = [worlds[mode].camera.position.x, worlds[mode].camera.position.y, worlds[mode].camera.zoom.x]
	else: view["camera"] = [worlds[mode].target.x, worlds[mode].target.y, worlds[mode].target.z, worlds[mode].yaw, worlds[mode].pitch, worlds[mode].distance]
	if small_prop_tools and small_prop_tools.active and small_prop_tools.scope==small_prop_tools.context():view["camera"]=small_prop_tools.stored_camera()
	workspace[mode] = view
	if workspace_layout: view["layout"] = workspace_layout.settings()
	if asset_browser: view["browser"] = asset_browser.settings()
	if workspace_presets: view["presets"] = workspace_presets.settings()
	if transform_handles: view["handles"] = transform_handles.settings()

func restore_workspace() -> void:
	if not enhancements_ready: return
	if not workspace.get(mode) is Dictionary:
		if transform_handles: transform_handles.restore({})
		if workspace_presets: workspace_presets.restore({})
		if asset_browser: asset_browser.restore({}); refresh_library()
		if workspace_layout: workspace_layout.restore({})
		arrange_tools.restore({})
		ground_brush.restore({})
		road_settings.restore({})
		rotation_controls.choice.select(0)
		color_editor.expansion.set_value_no_signal(0)
		color_editor.protect_visible.set_pressed_no_signal(true)
		return
	var view: Dictionary = workspace[mode]
	if asset_browser: asset_browser.restore(view.get("browser",{}))
	rotation_controls.choice.select(clampi(int(view.get("rotation_mode", 0)), 0, 3))
	var selection_options: Dictionary = view.get("piece_selection", {}) if view.get("piece_selection", {}) is Dictionary else {}
	color_editor.expansion.set_value_no_signal(clampi(int(selection_options.get("expansion", 0)), -8, 8))
	color_editor.protect_visible.set_pressed_no_signal(bool(selection_options.get("protect_visible", true)))
	road_settings.restore(view.get("roads", {}) if view.get("roads", {}) is Dictionary else {})
	ground_brush.restore(view.get("ground_brush", {}) if view.get("ground_brush", {}) is Dictionary else {})
	arrange_tools.restore(view.get("arrange", {}) if view.get("arrange", {}) is Dictionary else {})
	rotation_step.value = clampf(float(view.get("rotation_step", 90)), 0.1, 180)
	asset_type.select(clampi(int(view.get("asset_type", 0)), 0, 3))
	populate_categories()
	for index in category.item_count:
		if category.get_item_text(index) == view.get("category"): category.select(index)
	search.text = str(view.get("query", ""))
	page = int(view.get("page", 0))
	favorites_only.set_pressed_no_signal(bool(view.get("favorites", false)))
	snap_input.button_pressed = bool(view.get("snap", true))
	repeat_input.button_pressed = bool(view.get("repeat", false))
	surface_input.button_pressed = bool(view.get("surface", true))
	lanes_input.button_pressed = bool(view.get("lanes", true))
	var choice: String = str(view.get("tool", "select"))
	set_tool(choice if choice in ["place", "select", "erase", "road", "crossing", "road_erase", "color", "zone"] else "select")
	var camera_values: Variant = view.get("camera", [])
	if mode == "2d" and Document.numbers(camera_values, 3):
		worlds[mode].camera.position = Vector2(camera_values[0], camera_values[1])
		worlds[mode].camera.zoom = Vector2.ONE * clampf(camera_values[2], 0.1, 7)
	elif mode == "3d" and Document.numbers(camera_values, 6):
		worlds[mode].target = Vector3(camera_values[0], camera_values[1], camera_values[2])
		worlds[mode].yaw = camera_values[3]
		worlds[mode].pitch = clampf(camera_values[4], 15, 80)
		worlds[mode].distance = clampf(camera_values[5], 5, 120)
		worlds[mode].update_camera()
	refresh_library()
	if workspace_layout: workspace_layout.restore(view.get("layout",{}))
	if workspace_presets: workspace_presets.restore(view.get("presets",{}))
	if transform_handles: transform_handles.restore(view.get("handles",{}))

func switch_mode(value: String) -> void:
	if simulation_diagnostic_tools and simulation_diagnostic_tools.kind!="off": simulation_diagnostic_tools.invalidate()
	if small_prop_tools:small_prop_tools.leave()
	if photo_tools and worlds.has(mode) and worlds[mode].exploration and worlds[mode].exploration.photo: photo_tools.stop()
	if ambience_tools: ambience_tools.reset()
	if weather_tools: weather_tools.reset()
	if neighborhood_tools: neighborhood_tools.cancel()
	if terrain_tools: terrain_tools.cancel()
	if transit_tools: transit_tools.dirty=true
	if zone_tools:
		zone_tools.cancel_draw(); zone_tools.dirty=true
	if scenario_tools: scenario_tools.dirty=true
	if citizen_tools: citizen_tools.dirty=true
	if traffic_tools: traffic_tools.dirty=true
	if business_tools: business_tools.dirty=true
	if service_tools: service_tools.dirty=true
	if transform_handles: transform_handles.finish()
	if control_settings: control_settings.finish_drag()
	if workspace_presets:
		if workspace_presets.focused: workspace_presets.set_focus(false)
		workspace_presets.suspended=true
	if interior_tools and interior_tools.editing(): interior_tools.leave()
	if enhancements_ready:
		if ground_brush.drawing: ground_brush.finish(canvas_pointer())
		capture_workspace()
	selected_uids.clear()
	clear_assembly()
	super.switch_mode(value)
	if enhancements_ready: restore_workspace()
	if workspace_presets: workspace_presets.suspended=false; workspace_presets.refresh()

func session_data() -> Dictionary:
	if enhancements_ready: capture_workspace()
	var data: Dictionary = super.session_data()
	if interior_tools and interior_tools.editing():
		interior_tools.flush()
		data["documents"][interior_tools.dimension] = interior_tools.outer.data
	data["workspace"] = workspace
	data["project_id"] = project_id
	if not project_palette_document.data.is_empty():data["project_palette"]=project_palette_document.data.duplicate(true)
	data["project_title"] = recovery_title()
	data["project_path"] = project_path
	data["project_origin_path"] = project_origin_path
	if not repair_report.is_empty(): data["repair_report"] = repair_report
	if serializing_metadata:
		data["project_path"] = project_path
		data["saved_digest"] = saved_digest
	return data

func write_project(path: String, report: bool = true) -> bool:
	if report: finish_edit(canvas_pointer())
	var was_dirty: bool = dirty
	if enhancements_ready and report and storage_enabled and FileAccess.file_exists(path):
		var previous: Variant = Store.read_json(path, {})
		if previous is Dictionary and previous.has("documents"):
			if Store.snapshot(previous, "Previous save · " + path.get_file(), null, true, path).is_empty():
				status.text = "Could not create the recovery copy. The existing saved file was preserved."
				return false
	var previous_path: String = project_path
	var previous_digest: String = saved_digest
	var previous_id: String = project_id
	var previous_origin: String = project_origin_path
	if report:
		var origin: String = project_path if not project_path.is_empty() else project_origin_path
		if not origin.is_empty() and Store.canonical(origin) != Store.canonical(path): project_id = Store.new_id()
		project_path = path
		project_origin_path = path
		saved_digest = content_digest()
	serializing_metadata = true
	var result: bool = super.write_project(path, report)
	serializing_metadata = false
	if not result:
		project_path = previous_path
		saved_digest = previous_digest
		project_id = previous_id
		project_origin_path = previous_origin
	if enhancements_ready and result:
		if report:
			saved_digest = content_digest()
			if storage_enabled:
				Store.remember(path, recovery_title(), thumbnail(),project_id)
				autosave_pending = true
				autosave()
		else: dirty = was_dirty
		update_save_badge()
		if report and first_build: first_build.on_saved(path)
	return result

func load_project(path: String, _prepared: Dictionary = {}) -> bool:
	if small_prop_tools:small_prop_tools.leave()
	if terrain_tools: terrain_tools.finish()
	if transform_handles: transform_handles.finish()
	var repair: Dictionary = preload("res://scripts/builder/project_repair.gd").new(library).read(path)
	if not repair.get("ok",false):
		status.text = repair.get("error","This project could not be repaired.") + " Current work was preserved."
		return false
	if cooperative_tools and cooperative_tools.session.role!="offline": cooperative_tools.leave()
	var content: Dictionary = repair["content"]
	if Store.in_history(path) and not Store.valid_id(content.get("project_id")):
		var folder_id: String = path.get_base_dir().get_file()
		if Store.valid_id(folder_id) and Store.canonical(path.get_base_dir()) == Store.canonical(Store.folder(folder_id)): content["project_id"] = folder_id
	var source_entry: Variant = Store.read_json(path+".entry.json",{})
	if Store.in_history(path) and source_entry is Dictionary and Store.valid_id(source_entry.get("project_id")) and Store.canonical(path.get_base_dir()) == Store.canonical(Store.folder(source_entry["project_id"])):
		if not Store.valid_id(content.get("project_id")): content["project_id"] = source_entry["project_id"]
		if not content.has("project_origin_path"): content["project_origin_path"] = source_entry.get("project_path","")
	if repair["changed"] and storage_enabled:
		var backup: String = Store.preserve_source(path,content,Store.identity(content,path))
		if backup.is_empty(): status.text = "Could not preserve the source before repair. Current work was preserved."; return false
		content["repair_report"]["source_backup"] = backup

	if content is Dictionary and content.get("version") == 1 and content.get("documents") is Dictionary:
		var valid: bool = true
		for key in ["2d","3d"]: valid = valid and Document.valid(content["documents"].get(key),key,library)
		if valid:
			if photo_tools and worlds[mode].exploration: photo_tools.stop()
			if interior_tools and interior_tools.editing(): interior_tools.leave()
			if walking: set_walking(false)
			if village_tools: village_tools.reset()
			for world in worlds.values():
				if world.exploration and world.exploration.props: world.exploration.props.reset()
				if world.exploration and world.exploration.driving: world.exploration.driving.reset()
				if world.exploration and world.exploration.photo: world.exploration.photo.reset()
	finish_palette_boundary()
	palette_loading=true;library.set_project_palette({})
	var result: bool = super.load_project(path,content)
	palette_loading=false
	if result:project_palette_document.restore(content.get("project_palette",{}))
	library.set_project_palette(project_palette_document.data)
	if not result: return false
	repair_report = content.get("repair_report",{})
	project_id = Store.identity(content,path)
	project_origin_path = str(content.get("project_origin_path",content.get("project_path",""))) if Store.in_history(path) or Store.canonical(path) == Store.canonical(Store.legacy_autosave) else path
	pending_workspace = content.get("workspace", {}) if content.get("workspace", {}) is Dictionary else {}
	if Store.canonical(path) == Store.canonical(Store.autosave_path(project_id)) or Store.canonical(path) == Store.canonical(Store.legacy_autosave):
		project_path = str(content.get("project_path", ""))
		saved_digest = str(content.get("saved_digest", ""))
		dirty = content_digest() != saved_digest
	else:
		if Store.in_history(path): project_path = ""; dirty = true
		saved_digest = content_digest() if not dirty else ""
		if storage_enabled and not path.begins_with(Store.storage_root + "/"): Store.remember(path, current().data["title"], thumbnail() if enhancements_ready else null)
	if not enhancements_ready:
		for doc in documents.values(): doc.undo_history.clear(); doc.redo_history.clear()
	else:
		selected_uids.clear()
		workspace = pending_workspace
		restore_workspace()
		refresh_controls()
	if repair["changed"]:
		project_path = ""
		saved_digest = ""
		dirty = true
		autosave_pending = true
		status.text = "Recovered project · %d repairs · original source preserved · Save As to keep this copy." % repair["report"].get("issues",[]).size()
		if enhancements_ready: repair_tools.call_deferred("show")
		else: pending_repair_report = true
	if storage_enabled and Store.canonical(path) == Store.canonical(Store.legacy_autosave): autosave()
	if first_build: first_build.project_loaded()
	if citizen_tools: citizen_tools.reset()
	if traffic_tools: traffic_tools.reset()
	if business_tools: business_tools.reset()
	if service_tools: service_tools.reset()
	if economy_tools: economy_tools.reset()
	if scenario_tools: scenario_tools.reset()
	if zone_tools: zone_tools.reset()
	if utility_tools: utility_tools.reset()
	if power_tools: power_tools.reset()
	if transit_tools: transit_tools.reset()
	if terrain_tools: terrain_tools.reset()
	if ambience_tools: ambience_tools.reset()
	if weather_tools: weather_tools.reset()
	if garden_tools: garden_tools.reset()
	if cooking_tools: cooking_tools.reset()
	if laundry_tools: laundry_tools.reset()
	if fitness_tools: fitness_tools.reset()
	if arcade_tools: arcade_tools.reset()
	if camping_tools: camping_tools.reset()
	if pet_tools: pet_tools.reset()
	if cycling_tools: cycling_tools.reset()
	return true

func recovery_title() -> String:
	var origin: String = project_path if not project_path.is_empty() else project_origin_path
	return origin.get_file().trim_suffix(".isocity.json").trim_suffix(".json") if not origin.is_empty() else (interior_tools.root_document(mode) if interior_tools else documents[mode]).data["title"]

func startup_recovery_path() -> String:
	return Store.resume_autosave()

func autosave() -> bool:
	var path: String = Store.autosave_path(project_id)
	if not Store.prepare_parent(path): return false
	var previous: Variant = Store.read_json(path,{})
	if previous is Dictionary and previous.get("documents") is Dictionary:
		var old_digest: String = JSON.stringify(previous["documents"]).sha256_text()
		if old_digest != content_digest() and (not dirty or previous.get("saved_digest","") != saved_digest):
			if Store.snapshot(previous,"Before replacing autosave",null,true).is_empty(): return false
	if not write_project(path,false): return false
	if not Store.register_autosave(session_data(),path): return false
	autosave_pending = false
	update_save_badge()
	return true

func _file_selected(path: String) -> void:
	if file_action == "export_portable":
		var result: Dictionary = preload("res://scripts/builder/portable_export.gd").new().save(worlds[mode],layout_for_export(),library,path,project_palette_document.data)
		status.text = result["message"]
		return
	if file_action=="export":
		var result: Error=preload("res://scripts/builder/exporter.gd").save_scene(worlds[mode],layout_for_export(),library,path if path.ends_with(".tscn") else path+".tscn")
		status.text="Scene exported. Open it in this Godot project and press F6. Tab switches walk / camera." if result==OK else "Export failed: "+error_string(result)
		return
	if file_action == "open" and storage_enabled:
		Store.snapshot(session_data(), "Before opening · " + current().data["title"], thumbnail(), true)
	super._file_selected(path)

func layout_for_export() -> Dictionary:
	if interior_tools and interior_tools.editing():
		current().finish_checkpoint(); interior_tools.flush()
		return interior_tools.outer.data
	return current().data

func show_file_dialog(action: String) -> void:
	super.show_file_dialog(action)
	if action=="export" and interior_tools and interior_tools.editing():
		file_dialog.title="Export city and owned interiors as a Godot scene"
		file_dialog.current_file=layout_for_export()["title"].validate_filename()+"_"+mode+".tscn"
