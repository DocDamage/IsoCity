extends RefCounted

var studio: Control
var tabs: TabContainer
var library_split: HSplitContainer
var inspector_split: HSplitContainer
var library_toggle: CheckButton
var inspector_toggle: CheckButton
var advanced_toggle: CheckButton
var advanced_controls: Array[Control] = []
var mapping_toggle: CheckButton
var library_open: bool = true
var inspector_open: bool = true
var library_width: float = 296
var inspector_width: float = 280
var applying: bool = false
var last_tool: String = ""
var placement_controls: Array[Control] = []
var compact_placement: VBoxContainer
var center_control: Control
var focus_mode: bool=false
var compact_tools: RefCounted

func _init(host: Control, inspector_tabs: TabContainer, center: Control) -> void:
	studio = host
	center_control = center
	compact_tools=preload("res://scripts/builder/workspace_compact_tools.gd").new(studio,center)
	studio.resized.connect(func():call_deferred("refresh"))
	tabs = inspector_tabs
	tabs.use_hidden_tabs_for_min_size = false
	var main: Control = studio.mode_library.get_parent()
	library_split = HSplitContainer.new()
	library_split.name = "LibraryDivider"
	library_split.add_theme_constant_override("autohide",0)
	library_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	library_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(library_split)
	inspector_split = HSplitContainer.new()
	inspector_split.name = "InspectorDivider"
	inspector_split.add_theme_constant_override("autohide",0)
	inspector_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	studio.mode_library.reparent(library_split)
	library_split.add_child(inspector_split)
	center.reparent(inspector_split)
	studio.mode_inspector.reparent(inspector_split)
	var inspector_shell := VBoxContainer.new()
	inspector_shell.name = "InspectorShell"
	studio.mode_inspector.add_child(inspector_shell)
	tabs.reparent(inspector_shell)
	studio.mode_library.custom_minimum_size.x = 220
	studio.mode_inspector.custom_minimum_size.x = 220
	center.custom_minimum_size.x = 240
	compact_placement=VBoxContainer.new()
	studio.height_input.get_parent().add_child(compact_placement)
	studio.label(compact_placement,"Placement options",12)
	for control in studio.mode_road_bar.get_children():
		if control!=studio.road_choice: placement_controls.append(control)
	center.resized.connect(func(): call_deferred("refresh_placement"))
	for control in center.get_children():
		if control is Label: control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	studio.save_badge.autowrap_mode=TextServer.AUTOWRAP_OFF
	studio.save_badge.clip_text=true
	var card_scroll: ScrollContainer = studio.cards.get_parent()
	card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	card_scroll.resized.connect(fit_cards)
	library_split.dragged.connect(func(_offset: int): call_deferred("remember_widths"))
	inspector_split.dragged.connect(func(_offset: int): call_deferred("remember_widths"))
	library_split.resized.connect(func(): call_deferred("fit_widths"))
	var row := HBoxContainer.new()
	row.name = "PanelControls"
	center.add_child(row)
	center.move_child(row,1)
	library_toggle = CheckButton.new()
	library_toggle.text = "Library"
	library_toggle.tooltip_text = "Show or collapse the asset library; drag its divider to resize"
	row.add_child(library_toggle)
	library_toggle.toggled.connect(func(value: bool): library_open = value; refresh())
	inspector_toggle = CheckButton.new()
	inspector_toggle.text = "Inspector"
	inspector_toggle.tooltip_text = "Show or collapse the inspector; drag its divider to resize"
	row.add_child(inspector_toggle)
	inspector_toggle.toggled.connect(func(value: bool): inspector_open = value; refresh())
	advanced_toggle = CheckButton.new()
	advanced_toggle.text = "Advanced"
	advanced_toggle.tooltip_text = "Show pitch, roll and detailed tile mapping; common transforms remain in Basic"
	inspector_shell.add_child(advanced_toggle)
	inspector_shell.move_child(advanced_toggle,0)
	advanced_toggle.toggled.connect(func(_value: bool): refresh_advanced())
	for field in [studio.pitch_input,studio.roll_input]:
		advanced_controls.append(field.get_parent())
	# Mapping stays next to the tile source, with a local expansion control too.
	var color: RefCounted = studio.color_editor
	var mapping := VBoxContainer.new()
	mapping.name = "AdvancedMapping"
	color.panel.add_child(mapping)
	var first: int = color.tile_angle.get_index() - 1
	var last: int = color.tile_projection.get_index()
	var controls: Array[Node] = color.panel.get_children().slice(first,last+1)
	mapping_toggle = CheckButton.new()
	mapping_toggle.text = "Advanced tile mapping"
	color.panel.add_child(mapping_toggle)
	color.panel.move_child(mapping_toggle,first)
	color.panel.move_child(mapping,first+1)
	for control in controls: control.reparent(mapping)
	advanced_controls.append(mapping)
	mapping_toggle.toggled.connect(func(value: bool): advanced_toggle.button_pressed = value)
	studio.ground_brush.enabled_input.toggled.connect(func(_value: bool):
		if studio.enhancements_ready: studio.refresh_controls()
	)
	# Long settings pages stay reachable when the window is short.
	for page in tabs.get_children():
		if page is ScrollContainer or page.name == "Scene": continue
		var index: int = page.get_index()
		var title: String = page.name
		tabs.remove_child(page)
		page.name = "Contents"
		var scroll := ScrollContainer.new()
		scroll.name = title
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		tabs.add_child(scroll)
		tabs.move_child(scroll,index)
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(page)
		page.show()
	# Text may shrink without forcing the entire window wider than its canvas.
	prepare_controls(studio.mode_inspector)
	library_split.call_deferred("queue_sort")
	call_deferred("fit_widths")
	refresh()

func prepare_controls(node: Node) -> void:
	if node is ScrollContainer: node.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	if node is Button:
		node.clip_text = true
		node.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if node is OptionButton: node.fit_to_longest_item = false
	if node is Label and node.get_parent() is VBoxContainer and node.text.length() > 22:
		node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for child in node.get_children(): prepare_controls(child)

func remember_widths() -> void:
	if applying or studio.walking or focus_mode: return
	if library_open: library_width = clampf(studio.mode_library.size.x,220,600)
	if inspector_open: inspector_width = clampf(studio.mode_inspector.size.x,220,600)

func fit_widths() -> void:
	if not is_instance_valid(library_split): return
	if studio.consumer_shell and studio.consumer_shell.active: fit_cards(); return
	applying = true
	var available: float = library_split.size.x
	var left_min: float = studio.mode_library.get_combined_minimum_size().x if studio.mode_library.visible else 0
	var right_min: float = studio.mode_inspector.get_combined_minimum_size().x if studio.mode_inspector.visible else 0
	var left: float = maxf(left_min,library_width) if left_min>0 else 0
	var right: float = maxf(right_min,inspector_width) if right_min>0 else 0
	var center_min: float = studio.canvas.get_parent().get_combined_minimum_size().x
	var dividers: float = (library_split.get_theme_constant("separation") if left>0 else 0) + (inspector_split.get_theme_constant("separation") if right>0 else 0)
	var extra: float = left-left_min + right-right_min
	var room: float = maxf(0,available-center_min-dividers-left_min-right_min)
	if extra>room and extra>0:
		left = left_min + (left-left_min) * room / extra
		right = right_min + (right-right_min) * room / extra
	# Godot 4.7 positions a split at the beginning/end when only one child
	# expands. These offsets specify the two fixed side widths directly.
	if studio.mode_library.visible:
		library_split.split_offsets = PackedInt32Array([roundi(left)])
	if studio.mode_inspector.visible:
		inspector_split.split_offsets = PackedInt32Array([-roundi(right)])
	applying = false
	fit_cards()

func fit_cards() -> void:
	var scroll: Control = studio.cards.get_parent()
	var consumer: bool=studio.consumer_shell!=null and studio.consumer_shell.active
	var available: float=minf(scroll.size.x,studio.size.x-88) if consumer else scroll.size.x
	var cell_width: float=studio.thumbnail_size
	for card in studio.cards.get_children():
		if card is Control: cell_width=maxf(cell_width,card.get_combined_minimum_size().x)
	studio.cards.columns = clampi(floori((available + 8) / (cell_width+8)),1,10 if consumer else 6)

func refresh_advanced() -> void:
	for control in advanced_controls: control.visible = advanced_toggle.button_pressed
	mapping_toggle.set_pressed_no_signal(advanced_toggle.button_pressed)

func refresh() -> void:
	compact_tools.refresh()
	if studio.consumer_shell and studio.consumer_shell.active:
		refresh_advanced(); studio.consumer_shell.enforce_layout(); return
	library_toggle.set_pressed_no_signal(library_open)
	inspector_toggle.set_pressed_no_signal(inspector_open)
	studio.mode_library.visible = library_open and not studio.walking and not focus_mode
	studio.mode_inspector.visible = inspector_open and not studio.walking and not focus_mode
	library_toggle.get_parent().visible = not studio.walking and not focus_mode
	refresh_advanced()
	var road: bool = studio.tool in ["road","crossing","road_erase"]
	var painting: bool = studio.tool == "color"
	var brushing: bool = studio.ground_brush.active()
	var ground_selected: bool = studio.tool == "place" and studio.library.is_ground_tile(studio.asset_id)
	var building: bool = false
	for item in studio.selection_items():
		if studio.library.assets.get(item["asset"],{}).get("behavior",{}).get("building",false) or item.has("interior"): building = true
	var visible_pages: Dictionary = {"Roads":road,"Colors":painting,"Appearance":painting,"Ground":ground_selected,"Entrance":building}
	for page in tabs.get_children():
		if visible_pages.has(str(page.name)): tabs.set_tab_hidden(page.get_index(),not visible_pages[str(page.name)])
	if tabs.is_tab_hidden(tabs.current_tab): tabs.current_tab = 0
	refresh_placement()
	studio.brush_input.visible = brushing
	var brush_parent: Node = studio.brush_input.get_parent()
	for control in brush_parent.get_children():
		if control is Label and control.text == "Brush": control.visible = brushing
	call_deferred("fit_widths")

func refresh_placement() -> void:
	var compact: bool=center_control.size.x<600
	var destination: Node=compact_placement if compact else studio.mode_road_bar
	for control in placement_controls:
		if control.get_parent()!=destination: control.reparent(destination)
		control.visible=studio.tool in ["place","select"]
	compact_placement.visible=compact and studio.tool in ["place","select"]
	for control in center_control.get_children():
		if control is Label and control.text.begins_with("Drag an asset"): control.visible=not compact and not studio.walking and not focus_mode

func tool_changed() -> void:
	refresh()
	var ground_selected: bool = studio.tool == "place" and studio.library.is_ground_tile(studio.asset_id)
	var context: String = studio.tool + (":ground" if ground_selected else "")
	if context == last_tool: return
	last_tool = context
	var page: String = "Terrain" if studio.tool=="terrain" else "Zoning" if studio.tool=="zone" else "Roads" if studio.tool in ["road","crossing","road_erase"] else "Colors" if studio.tool == "color" else "Ground" if ground_selected else "Selection"
	for index in tabs.get_tab_count():
		if tabs.get_tab_title(index) == page:
			tabs.current_tab = index
			if page != "Selection": inspector_open = true
	refresh()

func settings() -> Dictionary:
	return {"library_open":library_open,"inspector_open":inspector_open,"library_width":library_width,"inspector_width":inspector_width,"advanced":advanced_toggle.button_pressed}

func restore(value: Variant) -> void:
	var data: Dictionary = value if value is Dictionary else {}
	library_open = data.get("library_open",true) if data.get("library_open",true) is bool else true
	inspector_open = data.get("inspector_open",true) if data.get("inspector_open",true) is bool else true
	for key in ["library_width","inspector_width"]:
		var number: Variant = data.get(key,296 if key == "library_width" else 280)
		if not (number is int or number is float) or not is_finite(number): number = 296 if key == "library_width" else 280
		set(key,clampf(number,220,600))
	advanced_toggle.set_pressed_no_signal(data.get("advanced",false) if data.get("advanced",false) is bool else false)
	refresh()
