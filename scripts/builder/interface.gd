extends Control

const STUDIO_VERSION: String = "0.8.0"

signal command(name: String, value: Variant)

var category: OptionButton
var asset_type: OptionButton
var search: LineEdit
var favorites_only: CheckButton
var cards: GridContainer
var asset_count: Label
var page_label: Label
var canvas: SubViewportContainer
var viewport: SubViewport
var asset_picture: TextureRect
var selected_name: Label
var selection_note: Label
var capability_note: Label
var height_input: SpinBox
var scale_input: SpinBox
var snap_input: CheckBox
var repeat_input: CheckBox
var brush_input: SpinBox
var status: Label
var title_input: LineEdit
var dimension: OptionButton
var template_choice: OptionButton
var tools: Dictionary = {}
var undo_button: Button
var redo_button: Button
var walk_button: Button
var rotation_button: Button
var file_dialog: FileDialog

func build_interface() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var theme_resource := Theme.new()
	theme_resource.default_font_size = 14
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("26364a") if state != "pressed" else Color("287d78")
		if state == "hover":
			style.bg_color = Color("344c63")
		style.set_corner_radius_all(6)
		style.content_margin_left = 12
		style.content_margin_right = 12
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		if state == "focus":
			style.bg_color.a = 0
			style.set_border_width_all(1)
			style.border_color = Color("64d8c8")
		theme_resource.set_stylebox(state, "Button", style)
	theme = theme_resource
	var background := ColorRect.new()
	background.color = Color("111c29")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var header := HFlowContainer.new()
	header.add_theme_constant_override("separation", 10)
	column.add_child(header)
	var brand := VBoxContainer.new()
	header.add_child(brand)
	label(brand, "IsoCity Studio", 24)
	var subtitle: Label = label(brand, "MAKE A PLACE OF YOUR OWN · v" + STUDIO_VERSION, 10)
	subtitle.modulate = Color("80a2b6")
	spacer(header)
	dimension = OptionButton.new()
	dimension.add_item("2D · Pixel world")
	dimension.add_item("3D · Model world")
	dimension.item_selected.connect(func(index: int): command.emit("dimension", index))
	header.add_child(dimension)
	title_input = LineEdit.new()
	title_input.custom_minimum_size.x = 240
	title_input.placeholder_text = "Give your place a name"
	title_input.text_changed.connect(func(text: String): command.emit("title", text))
	header.add_child(title_input)
	button(header, "Open", "open", "Open a saved Studio project")
	button(header, "Save", "save", "Save both your 2D and 3D layouts")
	button(header, "Export scene", "export", "Save the current layout as a runnable Godot scene")
	var toolbar := HFlowContainer.new()
	toolbar.add_theme_constant_override("separation", 8)
	column.add_child(toolbar)
	for choice in [["Place", "place"], ["Select / move", "select"], ["Erase", "erase"]]:
		var tool_button: Button = button(toolbar, choice[0], "tool", "Choose how the mouse edits your layout", choice[1])
		tool_button.toggle_mode = true
		tools[choice[1]] = tool_button
	snap_input = CheckBox.new()
	snap_input.text = "Snap to grid"
	snap_input.button_pressed = true
	toolbar.add_child(snap_input)
	repeat_input = CheckBox.new()
	repeat_input.text = "Repeat placement"
	repeat_input.tooltip_text = "Keep the chosen asset active after placing. Off by default."
	toolbar.add_child(repeat_input)
	label(toolbar, "Brush")
	brush_input = spin(toolbar, 1, 5, 2, 1)
	brush_input.custom_minimum_size.x = 64
	brush_input.tooltip_text = "Brush width for 2D ground and floor tiles: 1, 3, or 5 tiles"
	undo_button = button(toolbar, "Undo", "undo", "Undo the last change · Ctrl+Z")
	redo_button = button(toolbar, "Redo", "redo", "Redo · Ctrl+Y")
	spacer(toolbar)
	button(toolbar, "Home", "home", "Return the camera to the starting view")
	button(toolbar, "Day / night", "night", "Change the lighting")
	walk_button = button(toolbar, "Walk around", "walk", "Switch between character control and the building camera · Tab")
	walk_button.toggle_mode = true
	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 12)
	column.add_child(main)
	var library_panel: VBoxContainer = panel(main, 296)
	label(library_panel, "YOUR ASSET LIBRARY", 13)
	search = LineEdit.new()
	search.placeholder_text = "Search buildings, chairs, trees…"
	search.clear_button_enabled = true
	search.text_changed.connect(func(_text: String): command.emit("filter", null))
	library_panel.add_child(search)
	asset_type = OptionButton.new()
	asset_type.fit_to_longest_item = false
	asset_type.clip_text = true
	for text in ["All asset types · 2D + 3D", "2D sprites", "3D models", "Added packs"]: asset_type.add_item(text)
	asset_type.tooltip_text = "Place either asset type in either world. Models become isometric objects in 2D; sprites become flat objects in 3D."
	asset_type.item_selected.connect(func(_index: int): command.emit("asset_type", null))
	library_panel.add_child(asset_type)
	category = OptionButton.new()
	category.fit_to_longest_item = false
	category.clip_text = true
	category.item_selected.connect(func(_index: int): command.emit("filter", null))
	library_panel.add_child(category)
	favorites_only = CheckButton.new()
	favorites_only.text = "Favorites only"
	favorites_only.toggled.connect(func(_enabled: bool): command.emit("filter", null))
	library_panel.add_child(favorites_only)
	asset_count = label(library_panel, "", 12)
	asset_count.modulate = Color("8daabe")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	library_panel.add_child(scroll)
	cards = GridContainer.new()
	cards.columns = 2
	cards.add_theme_constant_override("h_separation", 8)
	cards.add_theme_constant_override("v_separation", 8)
	scroll.add_child(cards)
	var pages := HBoxContainer.new()
	library_panel.add_child(pages)
	button(pages, "‹", "page", "Previous page", -1)
	page_label = label(pages, "1 / 1")
	page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button(pages, "›", "page", "Next page", 1)
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(center)
	var start_bar := HBoxContainer.new()
	center.add_child(start_bar)
	template_choice = OptionButton.new()
	template_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for text in ["Small city block", "Furnished room", "Blank template"]:
		template_choice.add_item(text)
	start_bar.add_child(template_choice)
	button(start_bar, "Start from template", "template", "Replace this layout; Undo can restore your previous work")
	canvas = SubViewportContainer.new()
	canvas.set_script(preload("res://scripts/builder/canvas.gd"))
	canvas.stretch = true
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.mouse_default_cursor_shape = Control.CURSOR_CROSS
	center.add_child(canvas)
	viewport = SubViewport.new()
	viewport.size = Vector2i(800, 600)
	viewport.own_world_3d = true
	viewport.gui_disable_input = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	canvas.add_child(viewport)
	var helper := Label.new()
	helper.text = "Drag an asset here, or choose one and click to place."
	helper.modulate = Color("8daabe")
	helper.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(helper)
	var inspector: VBoxContainer = panel(main, 218)
	label(inspector, "MAKE IT YOURS", 13)
	asset_picture = TextureRect.new()
	asset_picture.custom_minimum_size = Vector2(180, 150)
	asset_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	asset_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	inspector.add_child(asset_picture)
	selected_name = label(inspector, "Choose an asset", 19)
	selected_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	selection_note = label(inspector, "Click an asset card to see it here.", 12)
	selection_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	selection_note.modulate = Color("8daabe")
	capability_note=label(inspector,"",12)
	capability_note.name="Capabilities"
	capability_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	capability_note.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label(inspector, "Height")
	height_input = spin(inspector, -1000000, 1000000, 0.5, 0)
	height_input.value_changed.connect(func(value: float): command.emit("height", value))
	label(inspector, "Size")
	scale_input = spin(inspector, 0.1, 8, 0.05, 1)
	scale_input.value_changed.connect(func(value: float): command.emit("scale", value))
	rotation_button = button(inspector, "Rotate ↻", "rotate", "Cycle the available directions · R")
	button(inspector, "Duplicate", "duplicate", "Copy the selected object · Ctrl+D")
	button(inspector, "Remove selected", "remove", "Remove the selected object · Delete")
	spacer(inspector, false)
	var note: Label = label(inspector, "Place: click or paint\nSelect: click, then drag to move\nMiddle-drag: pan\nRight-drag: orbit in 3D\nWheel: zoom · Tab: walk", 12)
	note.modulate = Color("8daabe")
	status = label(column, "Welcome! Choose an asset, then click the canvas to place it.", 13)
	status.custom_minimum_size.y = 24
	status.modulate = Color("87e4cd")
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.size = Vector2i(900, 580)
	add_child(file_dialog)

func button(parent: Node, text: String, action: String, tooltip: String = "", value: Variant = null) -> Button:
	var result := Button.new()
	result.set_meta("editor_action",action)
	result.text = text
	result.tooltip_text = tooltip
	result.focus_mode = Control.FOCUS_NONE
	result.pressed.connect(func(): command.emit(action, value))
	parent.add_child(result)
	return result

func label(parent: Node, text: String, font_size: int = 14) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	parent.add_child(result)
	return result

func spacer(parent: Node, horizontal: bool = true) -> void:
	var control := Control.new()
	if horizontal:
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		control.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(control)

func spin(parent: Node, minimum: float, maximum: float, step_value: float, value: float) -> SpinBox:
	var result := SpinBox.new()
	result.min_value = minimum
	result.max_value = maximum
	result.step = step_value
	result.value = value
	parent.add_child(result)
	return result

func panel(parent: Node, width: float) -> VBoxContainer:
	var container := PanelContainer.new()
	container.custom_minimum_size.x = width
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1a293a")
	style.set_corner_radius_all(10)
	for side in ["left", "right", "top", "bottom"]:
		style.set("content_margin_" + side, 12)
	container.add_theme_stylebox_override("panel", style)
	parent.add_child(container)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	container.add_child(column)
	return column
