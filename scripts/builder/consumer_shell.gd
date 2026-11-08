extends RefCounted

const Design=preload("res://scripts/builder/consumer_theme.gd")
const SETTINGS="user://studio_consumer.json"
const GROUPS=["Buildings","Nature","Interiors","Transport","People","Details","Everything"]
var studio: Control
var active: bool=false
var root: Control
var legacy_root: Control
var canvas_parent: Node
var cards_parent: Node
var inspector_parent: Node
var original_theme: Theme
var original_panel: StyleBox
var old_thumbnail: int
var header: PanelContainer
var header_actions: PanelContainer
var city_name: Button
var brand_symbol: TextureRect
var save_note: Label
var world_choice: OptionButton
var undo: Button
var redo: Button
var dock: PanelContainer
var dock_buttons: Dictionary={}
var hint_panel: PanelContainer
var hint: Label
var drawer: PanelContainer
var drawer_title: Label
var drawer_content: VBoxContainer
var build_box: VBoxContainer
var query: LineEdit
var result_note: Label
var page_note: Label
var empty_note: Label
var card_scroll: ScrollContainer
var refine: ScrollContainer
var refine_controls: HFlowContainer
var style_choice: OptionButton
var pack_choice: OptionButton
var variants: CheckBox
var cancel_buttons: Array[Button]=[]
var favorite: Button
var group_flow: HFlowContainer
var compact_groups: HBoxContainer
var group_choice: OptionButton
var pages_row: HBoxContainer
var filter_button: Button
var categories: Dictionary={}
var group: String="Buildings"
var catalog_scope: String=""
var drawer_kind: String=""
var details: PanelContainer
var details_slot: VBoxContainer
var details_open: bool=false
var detail_title: Label
var status_panel: PanelContainer
var status_column: VBoxContainer
var hidden_storage: Control
var status_sources: Array[Dictionary]=[]
var context: PanelContainer
var context_name: Label
var context_note: Label
var context_capabilities: Label
var context_picture: TextureRect
var context_repeat: CheckButton
var context_actions: HBoxContainer
var context_focus_actions: HFlowContainer
var edit_inside: Button
var room_navigation: HFlowContainer
var outside_button: Button
var edit_room: Button
var floor_choice: OptionButton
var floor_manage: Button
var room_layouts: Button
var floor_stamp: String=""
var original_handles: String="move"
var placement_actions: HBoxContainer
var backdrop: ColorRect
var sheet: PanelContainer
var sheet_title: Label
var sheet_note: Label
var sheet_contents: VBoxContainer
var sheet_kind: String=""
var welcome: PanelContainer
var welcome_seen: bool=false
var expert_return: Button
var focus_return: Button
var notice: PanelContainer
var notice_text: Label
var notice_seen: String=""
var notice_seconds: float=0
var hint_contrast: bool=false
var clock: float=0
var variant_expression:=RegEx.new()
var matched_member_count: int = 0
var matched_design_count: int = 0
var content_choice: OptionButton
var rename_dialog: ConfirmationDialog
var rename_field: LineEdit
var theme_choice: OptionButton
var theme_row: HFlowContainer
var clear_filters: Button
var theme_canvas: Button
var theme_caption: Label

func _init(host: Control) -> void:
	studio=host; original_theme=studio.accessibility_settings.original_theme.duplicate(true); original_handles=studio.transform_handles.mode
	legacy_root=studio.accessibility_settings.root_scroll
	canvas_parent=studio.canvas.get_parent(); cards_parent=studio.cards.get_parent(); inspector_parent=studio.mode_inspector.get_parent()
	original_panel=studio.mode_inspector.get_theme_stylebox("panel"); old_thumbnail=studio.thumbnail_size
	variant_expression.compile("_(?:16-?bit(?:_dither)?|24bit|nopalette|voyager(?:_dither)?)$")
	var saved: Dictionary=studio.Store.read_json(SETTINGS,{}) if studio.storage_enabled else {}
	welcome_seen=saved.get("welcome_seen",false)==true
	build()
	set_active(not saved.get("precision_workspace",false),false)
	studio.control_settings.refresh_button_hints(root)
	studio.resized.connect(layout)
	studio.tree_exiting.connect(shutdown)
	call_deferred("fit_initial_camera")

func fit_initial_camera() -> void:
	await studio.get_tree().process_frame; await studio.get_tree().process_frame
	if not is_instance_valid(studio) or not active: return
	for mode in studio.worlds:
		if not studio.workspace.has(mode): studio.worlds[mode].reset_camera(studio.documents[mode].data.get("template","city"))

func shutdown() -> void:
	if studio.resized.is_connected(layout): studio.resized.disconnect(layout)

func column(parent: Node) -> VBoxContainer:
	var box:=VBoxContainer.new(); box.add_theme_constant_override("separation",10); parent.add_child(box); return box

func row(parent: Node) -> HBoxContainer:
	var box:=HBoxContainer.new(); box.add_theme_constant_override("separation",8); parent.add_child(box); return box

func text(parent: Node,value: String,size: int=16) -> Label:
	var label:=Label.new(); label.text=value; label.add_theme_font_size_override("font_size",size); label.mouse_filter=Control.MOUSE_FILTER_IGNORE; parent.add_child(label); return label

func button(parent: Node,title: String,callback: Callable,icon_name: String="") -> Button:
	var result:=Button.new(); result.text=title; result.custom_minimum_size.y=44; result.focus_mode=Control.FOCUS_ALL; result.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	result.clip_text=true; result.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	if not icon_name.is_empty(): result.icon=Design.icon(icon_name); result.expand_icon=true; result.add_theme_constant_override("icon_max_width",24)
	result.custom_minimum_size.x=maxf(44,result.get_theme_font("font").get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,result.get_theme_font_size("font_size")).x+28+(32 if not icon_name.is_empty() else 0))
	result.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed: result.set_meta("pointer_activation",true)
		elif event is InputEventKey: result.set_meta("pointer_activation",false))
	result.pressed.connect(func():
		var pointer: bool=result.get_meta("pointer_activation",false); result.set_meta("pointer_activation",false); callback.call()
		if pointer and is_instance_valid(result) and result.is_inside_tree() and result.has_focus(): result.release_focus())
	parent.add_child(result); return result

func close_button(parent: Node,callback: Callable) -> Button:
	var result: Button=button(parent,"",callback,"close"); result.custom_minimum_size=Vector2(44,44); result.tooltip_text="Close · Esc"; cancel_buttons.append(result); return result

func panel(parent: Node) -> PanelContainer:
	var value:=PanelContainer.new(); value.mouse_filter=Control.MOUSE_FILTER_STOP; parent.add_child(value); return value

func spacer(parent: Node) -> void:
	var value:=Control.new(); value.size_flags_horizontal=Control.SIZE_EXPAND_FILL; value.mouse_filter=Control.MOUSE_FILTER_IGNORE; parent.add_child(value)

func build() -> void:
	root=Control.new(); root.name="CityExperience"; root.mouse_filter=Control.MOUSE_FILTER_IGNORE; root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); studio.add_child(root)
	header=panel(root); var city_row: HBoxContainer=row(header)
	var logo:=TextureRect.new(); brand_symbol=logo; logo.texture=Design.icon("city"); logo.modulate=Design.ACCENT; logo.custom_minimum_size=Vector2(36,40); logo.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; logo.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; logo.mouse_filter=Control.MOUSE_FILTER_IGNORE; city_row.add_child(logo)
	var title_box: VBoxContainer=column(city_row); title_box.add_theme_constant_override("separation",0); title_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	city_name=button(title_box,"Your place",rename_place); city_name.alignment=HORIZONTAL_ALIGNMENT_LEFT; city_name.custom_minimum_size.y=28; city_name.add_theme_font_size_override("font_size",20); city_name.add_theme_stylebox_override("normal",StyleBoxEmpty.new()); city_name.tooltip_text="Name your place"
	save_note=text(title_box,"A place of your own",12); save_note.clip_text=true
	header_actions=panel(root); var actions: HBoxContainer=row(header_actions)
	undo=button(actions,"",func(): run("undo"),"undo"); undo.custom_minimum_size.x=44; undo.tooltip_text="Undo · Ctrl+Z"; undo.set_meta("editor_action","undo")
	redo=button(actions,"",func(): run("redo"),"redo"); redo.custom_minimum_size.x=44; redo.tooltip_text="Redo · Ctrl+Y"; redo.set_meta("editor_action","redo")
	world_choice=OptionButton.new(); world_choice.add_item("Pixel world"); world_choice.add_item("3D world"); world_choice.custom_minimum_size=Vector2(136,44); world_choice.fit_to_longest_item=false; world_choice.clip_text=true; world_choice.tooltip_text="Two separate worlds, saved together in your project"; actions.add_child(world_choice)
	world_choice.item_selected.connect(func(index: int): close_overlays(); studio._command("dimension",index))
	var save: Button=button(actions,"",func(): run("save"),"save"); save.custom_minimum_size.x=44; save.tooltip_text="Save your place · Ctrl+S"; save.set_meta("editor_action","save")
	button(actions,"Menu",func(): open_sheet("menu"),"menu")
	room_navigation=HFlowContainer.new(); root.add_child(room_navigation)
	outside_button=button(room_navigation,"Back to city",func(): studio.interior_tools.return_button.pressed.emit(),"chevron")
	edit_room=button(room_navigation,"Edit this room",func(): studio.interior_tools.edit_button.pressed.emit(),"furniture")
	floor_choice=OptionButton.new(); floor_choice.custom_minimum_size=Vector2(170,44); floor_choice.fit_to_longest_item=false; floor_choice.clip_text=true; room_navigation.add_child(floor_choice)
	floor_choice.item_selected.connect(func(index: int): studio.interior_tools.floor_tools.choice.select(index); studio.interior_tools.floor_tools.choice.item_selected.emit(index))
	floor_manage=button(room_navigation,"Floors",func(): studio.interior_tools.floor_tools.manage.pressed.emit(),"layers")
	room_layouts=button(room_navigation,"Layouts",func(): studio.interior_tools.kit_chooser.show(),"furniture")
	dock=panel(root); var dock_row: HBoxContainer=row(dock)
	for spec in [["build","Build","build"],["roads","Roads","road"],["landscape","Nature","nature"],["life","City life","people"],["explore","Explore","walk"],["photo","Photo","camera"]]:
		var key: String=spec[0]; var item: Button=button(dock_row,"",func(): choose_dock(key)); item.custom_minimum_size=Vector2(86,66); item.toggle_mode=true; item.tooltip_text=spec[1]
		var content:=VBoxContainer.new(); content.mouse_filter=Control.MOUSE_FILTER_IGNORE; content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); content.offset_left=6; content.offset_right=-6; content.offset_top=7; content.offset_bottom=-5; content.alignment=BoxContainer.ALIGNMENT_CENTER; item.add_child(content)
		var image:=TextureRect.new(); image.texture=Design.icon(spec[2]); image.custom_minimum_size=Vector2(26,26); image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; image.mouse_filter=Control.MOUSE_FILTER_IGNORE; content.add_child(image)
		var caption: Label=text(content,spec[1],13); caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		item.set_meta("picture",image); item.set_meta("caption",caption); dock_buttons[key]=item
	hint_panel=panel(root); hint_panel.add_theme_stylebox_override("panel",Design.surface(Design.PAPER,14,8)); hint=text(hint_panel,"Choose Build to make something yours.",14); hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; hint.clip_text=true; hint.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	drawer=panel(root); var drawer_box: VBoxContainer=column(drawer); var drawer_header: HBoxContainer=row(drawer_box)
	drawer_title=text(drawer_header,"Build something lovely",20); spacer(drawer_header)
	query=LineEdit.new(); query.placeholder_text="Find something…"; query.clear_button_enabled=true; query.custom_minimum_size=Vector2(260,44); drawer_header.add_child(query)
	query.text_changed.connect(func(_value: String): refresh_catalog()); query.text_submitted.connect(func(_value: String): if studio.cards.get_child_count()>0: studio.cards.get_child(0).pressed.emit())
	filter_button=button(drawer_header,"Refine",func(): refine.visible=not refine.visible; layout(),"settings")
	close_button(drawer_header,close_drawer)
	drawer_content=column(drawer_box); drawer_content.size_flags_vertical=Control.SIZE_EXPAND_FILL
	build_box=column(drawer_content); build_box.size_flags_vertical=Control.SIZE_EXPAND_FILL
	theme_row=HFlowContainer.new();build_box.add_child(theme_row)
	studio.asset_browser.task_collections.add_controls(build_box)
	studio.asset_browser.recents.add_control(studio.asset_browser.task_collections.controls[-1]["flow"])
	theme_caption=text(theme_row,"Theme",14)
	theme_choice=OptionButton.new();theme_choice.custom_minimum_size=Vector2(210,44);studio.library.themes.fill(theme_choice,studio.library)
	preload("res://scripts/builder/asset_themes.gd").select(theme_choice,studio.asset_browser.theme_filter);theme_row.add_child(theme_choice)
	theme_choice.item_selected.connect(func(index: int):studio.asset_browser.set_theme(str(theme_choice.get_item_metadata(index))))
	clear_filters=button(theme_row,"Clear filters",studio.asset_browser.semantic_search.clear_or_restore)
	clear_filters.tooltip_text="Show all themes, types, packs and content; clear search and favorites."
	theme_canvas=button(theme_row,"Canvas",func():close_drawer();studio.asset_browser.focus_canvas())
	studio.asset_browser.compatibility.add_simple(theme_row,build_box)
	var groups:=HFlowContainer.new(); build_box.add_child(groups); group_flow=groups
	compact_groups=row(build_box); group_choice=OptionButton.new(); group_choice.custom_minimum_size=Vector2(150,44); group_choice.fit_to_longest_item=false; group_choice.clip_text=true
	for name in GROUPS: group_choice.add_item(name)
	compact_groups.add_child(group_choice); group_choice.item_selected.connect(func(index: int): group=GROUPS[index]; refresh_catalog())
	for name in GROUPS:
		var entry: Button=button(groups,name,func(): group=name; refresh_catalog()); entry.toggle_mode=true; entry.custom_minimum_size.y=38; categories[name]=entry
	favorite=button(groups,"Favorites",func(): studio.favorites_only.button_pressed=not studio.favorites_only.button_pressed; refresh_catalog(),"star"); favorite.toggle_mode=true
	refine=ScrollContainer.new();refine.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;refine.follow_focus=true;refine.custom_minimum_size.y=120;refine.hide();build_box.add_child(refine)
	refine_controls=HFlowContainer.new();refine_controls.size_flags_horizontal=Control.SIZE_EXPAND_FILL;refine.add_child(refine_controls)
	style_choice=OptionButton.new(); style_choice.fit_to_longest_item=false; style_choice.custom_minimum_size=Vector2(180,40)
	for title in ["Match this world","All styles","Pixel art","3D models"]: style_choice.add_item(title)
	refine_controls.add_child(style_choice); style_choice.item_selected.connect(func(_index: int): refresh_catalog())
	pack_choice=OptionButton.new(); pack_choice.fit_to_longest_item=false; pack_choice.clip_text=true; pack_choice.custom_minimum_size=Vector2(200,40); pack_choice.add_item("All source packs")
	var names: Array[String]=[]
	for asset in studio.library.assets.values():
		var name: String=studio.library.pack_name(asset)
		if not names.has(name): names.append(name)
	names.sort()
	for name in names: pack_choice.add_item(name)
	refine_controls.add_child(pack_choice); pack_choice.item_selected.connect(func(_index: int): refresh_catalog())
	variants=CheckBox.new(); variants.text="Show every variation"; refine_controls.add_child(variants); variants.toggled.connect(func(_value: bool): refresh_catalog())
	content_choice = OptionButton.new(); content_choice.fit_to_longest_item = false; content_choice.clip_text = true; content_choice.custom_minimum_size = Vector2(230,40)
	for text in preload("res://scripts/builder/asset_content.gd").LABELS: content_choice.add_item(text)
	content_choice.select(studio.asset_browser.content_scope); refine_controls.add_child(content_choice)
	content_choice.tooltip_text = "Objects excludes reviewed sheets and references. Include scenery or All content deliberately; favorites remain accessible."
	content_choice.item_selected.connect(func(index: int): studio.asset_browser.set_content_scope(index))
	var look_note: Label=text(refine_controls,"Any style can be placed in either world.",12); look_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; look_note.custom_minimum_size.x=260
	card_scroll=ScrollContainer.new(); card_scroll.follow_focus=true; card_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; card_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; build_box.add_child(card_scroll); card_scroll.resized.connect(func(): studio.workspace_layout.fit_cards())
	empty_note=text(build_box,"Nothing here yet. Try another collection, All styles, or All content in Refine."); empty_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; empty_note.hide()
	studio.asset_browser.semantic_search.add_simple(refine_controls,build_box,empty_note)
	studio.asset_browser.health_tools.add_simple(refine_controls)
	studio.asset_browser.collections.add_controls(refine_controls)
	var pages: HBoxContainer=row(build_box); pages_row=pages; pages.size_flags_horizontal=Control.SIZE_EXPAND_FILL; result_note=text(pages,"",12); spacer(pages); button(pages,"‹",func(): studio._command("page",-1)); page_note=text(pages,"1 / 1",13); button(pages,"›",func(): studio._command("page",1))
	result_note.clip_text=true;result_note.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;result_note.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	details=panel(root); var detail_box: VBoxContainer=column(details); var details_header: HBoxContainer=row(detail_box); detail_title=text(details_header,"More options",20); detail_title.clip_text=true; detail_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; close_button(details_header,func(): details_open=false; enforce_layout())
	details_slot=column(detail_box); details_slot.size_flags_vertical=Control.SIZE_EXPAND_FILL
	status_panel=panel(root); status_column=column(status_panel)
	hidden_storage=Control.new(); hidden_storage.name="PrecisionStatusStorage"; hidden_storage.hide(); studio.add_child(hidden_storage)
	for source in [studio.economy_tools.badge,studio.scenario_tools.badge,studio.cooperative_tools.badge]:
		var caption: Label=text(status_column,"",14); caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		status_sources.append({"source":source,"parent":source.get_parent(),"index":source.get_index(),"position":source.position,"caption":caption})
	context=panel(root); var context_box: VBoxContainer=column(context); var context_heading: HBoxContainer=row(context_box)
	context_picture=TextureRect.new(); context_picture.custom_minimum_size=Vector2(60,60); context_picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; context_picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; context_picture.mouse_filter=Control.MOUSE_FILTER_IGNORE; context_heading.add_child(context_picture)
	var context_words: VBoxContainer=column(context_heading); context_words.size_flags_horizontal=Control.SIZE_EXPAND_FILL; context_name=text(context_words,"",18); context_name.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; context_note=text(context_words,"",13); context_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	context_capabilities=text(context_box,"",12);context_capabilities.clip_text=true;context_capabilities.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	context_capabilities.mouse_filter=Control.MOUSE_FILTER_IGNORE
	context_actions=row(context_box)
	button(context_actions,"Move",func(): studio._command("tool","select"); studio._command("handles_mode","move"),"move")
	button(context_actions,"Copy",func(): run("duplicate"),"copy").set_meta("editor_action","duplicate")
	var remove: Button=button(context_actions,"",func(): run("remove"),"trash"); remove.tooltip_text="Remove · Delete"; remove.custom_minimum_size.x=44; remove.set_meta("editor_action","remove")
	placement_actions=row(context_box); button(placement_actions,"Rotate",func(): run("rotate"),"rotate").set_meta("editor_action","rotate")
	context_repeat=CheckButton.new(); context_repeat.text="Keep placing"; placement_actions.add_child(context_repeat); context_repeat.toggled.connect(func(value: bool): studio.repeat_input.button_pressed=value)
	var detail_actions: HBoxContainer=row(context_box); button(detail_actions,"More options",func(): open_details("Selection"),"settings"); button(detail_actions,"Paint",func(): studio._command("tool","color"); open_details("Colors"))
	context_focus_actions=HFlowContainer.new();context_box.add_child(context_focus_actions)
	button(context_focus_actions,"Magnify",func():studio._command("small_props_magnify",null))
	button(context_focus_actions,"Isolate",func():studio._command("small_props_isolate",null))
	edit_inside=button(context_box,"Edit inside",func(): studio.interior_tools.selected_edit.pressed.emit(),"furniture")
	backdrop=ColorRect.new(); backdrop.color=Color(0.03,.08,.12,.25); backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.add_child(backdrop); backdrop.gui_input.connect(func(event: InputEvent): if event is InputEventMouseButton and event.pressed: close_sheet(); backdrop.accept_event())
	sheet=panel(root); var sheet_box: VBoxContainer=column(sheet); var sheet_heading: HBoxContainer=row(sheet_box); sheet_title=text(sheet_heading,"Your place",22); spacer(sheet_heading); close_button(sheet_heading,close_sheet)
	sheet_note=text(sheet_box,"",14); sheet_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var sheet_scroll:=ScrollContainer.new(); sheet_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; sheet_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; sheet_box.add_child(sheet_scroll); sheet_contents=column(sheet_scroll); sheet_contents.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	welcome=panel(root); var invitation: VBoxContainer=column(welcome); var welcome_heading: HBoxContainer=row(invitation); text(welcome_heading,"A place of your own.",23); spacer(welcome_heading); close_button(welcome_heading,dismiss_welcome)
	var welcome_words: Label=text(invitation,"Build a neighborhood. Make a cozy room.\nOr step inside and see where it takes you.",16); welcome_words.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	button(invitation,"Let's build",func(): open_drawer("build"),"build"); button(invitation,"Take a walk",func(): dismiss_welcome(); studio.set_walking(true),"walk")
	notice=panel(root); notice_text=text(notice,"",14); notice_text.clip_text=true; notice_text.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	expert_return=button(studio,"Back to simple view",func(): set_active(true),"build"); expert_return.hide()
	focus_return=button(studio,"Return to city tools",func(): studio.workspace_presets.set_focus(false),"build"); focus_return.hide()
	rename_dialog=ConfirmationDialog.new(); rename_dialog.title="Name your place"; rename_dialog.min_size=Vector2i(360,150); studio.add_child(rename_dialog)
	rename_field=LineEdit.new(); rename_field.placeholder_text="Somewhere you love"; rename_dialog.add_child(rename_field)
	rename_dialog.confirmed.connect(func(): if not rename_field.text.strip_edges().is_empty(): studio._command("title",rename_field.text.strip_edges()))
	rename_field.text_submitted.connect(func(_value: String): rename_dialog.confirmed.emit(); rename_dialog.hide())

func set_active(value: bool,persist: bool=true) -> void:
	if value==active and value: return
	if studio.small_prop_tools and studio.small_prop_tools.active:studio.small_prop_tools.leave()
	active=value; close_overlays(); root.visible=value; expert_return.visible=not value
	focus_return.hide()
	if value:
		studio.workspace_presets.set_focus(false)
		original_handles=studio.transform_handles.mode
		studio.transform_handles.set_mode("off")
		old_thumbnail=studio.thumbnail_size
		studio.canvas.reparent(studio); studio.move_child(studio.canvas,1); studio.canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		studio.cards.reparent(card_scroll); studio.cards.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
		studio.mode_inspector.reparent(details_slot); studio.mode_inspector.size_flags_vertical=Control.SIZE_EXPAND_FILL
		for entry in status_sources: entry["source"].reparent(hidden_storage)
		studio.thumbnail_size=132; studio.accessibility_settings.original_theme=Design.make(); studio.accessibility_settings.apply(); legacy_root.hide()
		var frame: StyleBoxFlat=Design.surface(Design.PAPER,12,4); frame.shadow_size=0; studio.mode_inspector.add_theme_stylebox_override("panel",frame)
	else:
		studio.transform_handles.set_mode(original_handles); studio.canvas.mouse_default_cursor_shape=Control.CURSOR_CROSS
		if studio.canvas.get_parent()!=canvas_parent: studio.canvas.reparent(canvas_parent); studio.canvas.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		if studio.cards.get_parent()!=cards_parent: studio.cards.reparent(cards_parent); studio.cards.size_flags_horizontal=Control.SIZE_FILL
		if studio.mode_inspector.get_parent()!=inspector_parent: studio.mode_inspector.reparent(inspector_parent)
		for entry in status_sources:
			if entry["source"].get_parent()!=entry["parent"]: entry["source"].reparent(entry["parent"]); entry["parent"].move_child(entry["source"],mini(entry["index"],entry["parent"].get_child_count()-1)); entry["source"].position=entry["position"]
		studio.workspace_layout.tabs.tabs_visible=true
		studio.mode_inspector.add_theme_stylebox_override("panel",original_panel); studio.thumbnail_size=old_thumbnail
		studio.accessibility_settings.original_theme=original_theme.duplicate(true); studio.accessibility_settings.apply(); legacy_root.show(); studio.workspace_layout.refresh()
		for world in studio.worlds.values(): world.grid.visible=true
	studio.refresh_library(); studio.update_save_badge(); layout(); enforce_layout()
	if persist: save_settings()

func save_settings() -> void:
	if studio.storage_enabled: studio.Store.write_json(SETTINGS,{"precision_workspace":not active,"welcome_seen":welcome_seen})

func dismiss_welcome() -> void:
	welcome_seen=true; welcome.hide(); save_settings()

func rename_place() -> void:
	rename_field.text=studio.current().data["title"]; rename_dialog.popup_centered(Vector2i(400,150)); rename_field.grab_focus(); rename_field.select_all()

func choose_dock(key: String) -> void:
	dismiss_welcome()
	match key:
		"build","roads":
			if drawer_kind==key: close_drawer()
			else: open_drawer(key)
		"landscape": open_sheet("landscape")
		"life": open_sheet("life")
		"explore": close_overlays(); studio.set_walking(not studio.walking)
		"photo": close_overlays(); run("photo")

func open_drawer(kind: String="build") -> void:
	if studio.walking: studio.set_walking(false)
	if kind=="build":
		var scope: String="room" if studio.interior_tools.editing() or studio.current().data.get("template","")=="room" or studio.current().data.get("interior_room",false) else "city"
		if scope!=catalog_scope: catalog_scope=scope; group="Interiors" if scope=="room" else "Buildings"; query.clear();studio.page=0
		if not studio.asset_browser.task_collections.task.is_empty():group="Everything"
	dismiss_welcome(); close_sheet(); details_open=false
	drawer_kind=kind; drawer_title.text="Make it yours" if kind=="build" else "Connect your city"
	build_box.visible=kind=="build"; query.visible=kind=="build"
	for child in drawer_content.get_children():
		if child!=build_box: child.queue_free(); drawer_content.remove_child(child)
	if kind=="roads":
		var choices: HBoxContainer=row(drawer_content)
		for spec in [["Draw roads","road"],["Add crossings","crossing"],["Remove roads","road_erase"]]:
			var choice: Button=button(choices,spec[0],func(): studio._command("tool",spec[1]),"road"); choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var options: HBoxContainer=row(drawer_content); text(options,"Road size",14)
		for spec in [["Quiet lane",0],["Main street",1]]: button(options,spec[0],func(): studio.road_settings.width.select(spec[1]))
		button(options,"Road details",func(): open_details("Roads"),"settings")
		button(drawer_content,"Cycling and scooters",func(): studio._command("cycling",null),"road")
		text(drawer_content,"Click and drag across the ground. Roads join automatically. Undo is always close by.",14).autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		studio._command("tool","road")
	else: refresh_catalog(false);studio.asset_browser.recents.restore_drawer()
	enforce_layout(); layout(); fade_in(drawer)

func close_drawer() -> void:
	studio.asset_browser.recents.capture_drawer()
	drawer_kind=""; drawer.hide(); enforce_layout()

func open_details(title: String="Selection") -> void:
	close_drawer(); close_sheet(); details_open=true; studio.workspace_layout.inspector_open=true; studio.workspace_layout.tabs.tabs_visible=true; studio.workspace_presets.show_tab(title); studio.mode_inspector.show(); enforce_layout(); fade_in(details)

func prepare_command(action: String) -> void:
	if not active: return
	if action in ["citizens","schools","resident_activities","traffic","cycling","harbors","space_outpost","vehicle_fleets","businesses","markets","services","water","power","economy","construction_costs","challenges","zoning","transit","terrain","ground_families","modular_rooms","garden","cooking","laundry","fitness","arcade","camping","pet","village","ambience","weather","props","interaction_setup","simulation_diagnostics","driving","vehicle_care","deliveries","import_asset","blueprints","connectors","cooperative","creation_sharing"]:
		close_drawer(); close_sheet(); details_open=true; studio.workspace_layout.tabs.tabs_visible=false; enforce_layout(); fade_in(details)

func close_overlays() -> void:
	drawer_kind=""; details_open=false; sheet_kind=""
	for control in [drawer,details,sheet,backdrop]:
		if is_instance_valid(control): control.hide()

func close_sheet() -> void:
	sheet_kind=""; sheet.hide(); backdrop.hide()

func run(action: String,value: Variant=null) -> void:
	close_sheet()
	if action in ["citizens","schools","resident_activities","traffic","cycling","harbors","space_outpost","vehicle_fleets","businesses","markets","services","water","power","economy","construction_costs","challenges","zoning","transit","terrain","ground_families","modular_rooms","garden","cooking","laundry","fitness","arcade","camping","pet","village","neighborhood","ambience","weather","props","interaction_setup","driving","vehicle_care","deliveries","photo","creation_sharing","import_asset"]: close_drawer()
	studio._command(action,value)

func sheet_action(title: String,subtitle: String,action: String,value: Variant=null,icon_name: String="chevron") -> void:
	var item: Button=button(sheet_contents,title,func():
		if action.begins_with("sheet:"): open_sheet(action.trim_prefix("sheet:"))
		elif action=="precision": set_active(false)
		elif action=="catalog": group=str(value); open_drawer("build")
		elif action=="starter": close_sheet(); studio.template_choice.select(int(value)); studio._command("template",null)
		else: run(action,value)
	,icon_name)
	item.alignment=HORIZONTAL_ALIGNMENT_LEFT; item.custom_minimum_size.y=48; item.tooltip_text=subtitle
	var caption: Label=text(sheet_contents,subtitle,13); caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART

func open_sheet(kind: String) -> void:
	if sheet_kind==kind: close_sheet(); return
	close_drawer(); details_open=false; dismiss_welcome(); sheet_kind=kind
	for child in sheet_contents.get_children(): sheet_contents.remove_child(child); child.queue_free()
	match kind:
		"menu":
			sheet_title.text="Your place"; sheet_note.text="Pick up where you left off, or try something new."
			sheet_action("Saved places","Open, save a copy, or recover an earlier version.","open",null,"build")
			sheet_action("Share your creation","Make a preview and share a city or collection.","creation_sharing",null,"share")
			sheet_action("Starter scenes","Try a city block, a cozy room, or an open canvas.","sheet:starters",null,"nature")
			sheet_action("Settings & help","Comfort, controls, and a little guidance.","sheet:settings",null,"settings")
			sheet_action("More tools","Import, collaboration, precise editing, and exports.","sheet:more",null,"layers")
		"settings":
			sheet_title.text="Make yourself comfortable"; sheet_note.text="Your place, your pace."
			sheet_action("Comfort & accessibility","Text size, contrast, larger targets, and clear selection shapes.","accessibility",null,"people")
			sheet_action("Controls","Find a shortcut or change the way you play.","controls",null,"settings")
			sheet_action("Learn the basics","A short guided first build.","first_build",null,"build")
			sheet_action("Day & night","Change the mood of this world.","night",null,"sun")
			sheet_action("Bring the city into view","Return to the starting camera.","home",null,"camera")
		"more":
			sheet_title.text="A little more control"; sheet_note.text="Extra possibilities, when you need them."
			sheet_action("Precision workspace","The full editor, with detailed transforms, layers, and mapping.","precision",null,"settings")
			sheet_action("Import a creation asset","Add your own sprites and models.","import_asset",null,"build")
			sheet_action("Build together","Cooperative sessions and protected areas.","cooperative",null,"people")
			sheet_action("Reusable collections","Save and place your own assemblies.","assemblies",null,"layers")
			sheet_action("Modular rooms","Draw and fit Model world walls, doorways and windows.","modular_rooms",null,"build")
			sheet_action("Find an action","Search every command and tool.","commands",null,"menu")
			sheet_action("Export options","Runnable Godot scenes and portable source projects.","sheet:export",null,"share")
		"export":
			sheet_title.text="Take it with you"; sheet_note.text="These options are for working with Godot projects. Use Share for layout downloads and previews."
			sheet_action("Godot scene","Export the current layout as a runnable scene.","export",null,"share")
			sheet_action("Portable source project","Package dependencies where the supplied asset licenses permit it.","export_portable",null,"save")
		"starters":
			sheet_title.text="A little inspiration"; sheet_note.text="Replace this world's layout with a starter scene. Undo brings your previous layout back."
			for spec in [["A neighborhood","A small city block to make your own.",0],["A cozy room","Start indoors and add your own touches.",1],["A blank canvas","Space for whatever comes next.",2]]: sheet_action(spec[0],spec[1],"starter",spec[2],"build")
			sheet_action("SWAT compound","Explore the new buildings, vehicles, and equipment.","swat_showcase",null,"city")
			sheet_action("Space outpost","Build a practice outpost or set up cargo arrivals.","space_outpost",null,"star")
		"landscape":
			sheet_title.text="A little closer to nature"; sheet_note.text="Shape the ground and set the mood."
			sheet_action("Trees & gardens","Find trees, plants, and green details.","catalog","Nature","nature")
			sheet_action("Ground & water","Shape hills, riverbanks, ponds, and waterfronts.","terrain",null,"nature")
			sheet_action("Connected ground","Paint connected shores and stone paths in the Pixel world.","ground_families",null,"nature")
			sheet_action("Community gardens","Set up beds, greenhouses and supplies for a local harvest preview.","garden",null,"nature")
			sheet_action("Camping visits","Link park arrivals, shelters and camp activities.","camping",null,"nature")
			sheet_action("Village production","Connect farms, workshops and markets with local stock transfers.","village",null,"nature")
			sheet_action("Pet companionship","Choose a cat or dog and a home resting mat.","pet",null,"nature")
			sheet_action("Weather & seasons","Rain, snow, wind, and changing foliage.","weather",null,"sun")
			sheet_action("Soundscapes","Bring the outdoors and interiors to life.","ambience",null,"nature")
		"life":
			sheet_title.text="Bring your place to life"; sheet_note.text="Start with one system. Add more whenever you feel ready."
			for spec in [["Citizens","Residents and their daily routines.","citizens"],["Interior activities","Let residents use furnished rooms.","resident_activities"],["Schools","Set class, break and dismissal times.","schools"],["Traffic & transit","Moving vehicles, routes, and timetables.","sheet:travel"],["Services & businesses","Places that care for your neighborhood.","sheet:services"],["Budgets & challenges","Give your city a goal.","sheet:goals"],["Grow a neighborhood","Zoning and editable generated blocks.","sheet:growth"]]: sheet_action(spec[0],spec[1],spec[2],null,"people")
		"travel":
			sheet_title.text="Getting around"; sheet_note.text="Connect places and make room for movement."
			for spec in [["Traffic","Signs, signals, vehicles and parking.","traffic"],["Vehicle fleets","Choose models for traffic, transit and service crews.","vehicle_fleets"],["Public transit","Routes, stops, and timetables.","transit"],["Driving","Enter a vehicle and explore.","driving"],["Boating & harbors","Define docks, pilot a boat, and run a ferry.","harbors"],["Vehicle care","Fuel, charge, wash and repair.","vehicle_care"],["Local deliveries","Move cargo between shops.","deliveries"]]: sheet_action(spec[0],spec[1],spec[2],null,"road")
		"services":
			sheet_title.text="A neighborhood that works"; sheet_note.text="Give people places to go and services to rely on."
			for spec in [["City services","Fire, medical, sanitation, and police.","services"],["Businesses","Cafés, shops, and visitor activities.","businesses"],["Market days","Schedule temporary stalls and sales.","markets"],["Furniture & equipment","Seats, switches, and appliances.","props"],["Check interaction setup","Find blocked fixtures, missing links, and unusable targets.","interaction_setup"]]: sheet_action(spec[0],spec[1],spec[2],null,"city")
			sheet_action("Water network","Connect reviewed ports and inspect water delivery.","water",null,"city")
			sheet_action("Power network","Connect generators, batteries and electricity consumers.","power",null,"city")
			sheet_action("Kitchen recipes","Set up preparation, cooking and serving stations.","cooking",null,"furniture")
			sheet_action("Laundry services","Set up machines, folding tables and order counters.","laundry",null,"furniture")
			sheet_action("Fitness & sports","Book gym workouts and penalty practice.","fitness",null,"people")
			sheet_action("Arcade games","Assign playable games to reviewed cabinets.","arcade",null,"furniture")
		"goals":
			sheet_title.text="A sense of purpose"; sheet_note.text="Creative building is always available."
			sheet_action("City budget","Upkeep, income and treasury.","economy",null,"city"); sheet_action("Construction costs","Quote an edit and compare asset appearances.","construction_costs",null,"city"); sheet_action("Challenges","Small goals to build toward.","challenges",null,"star")
			sheet_action("Emergency training","Run fire evacuation and medical assistance drills.","challenges","fire_drill","city")
			sheet_action("Simulation diagnostics","Inspect verified routes, service coverage, and queues.","simulation_diagnostics",null,"settings")
		"growth":
			sheet_title.text="Room to grow"; sheet_note.text="Build a district, then make it your own."
			sheet_action("Generate a neighborhood","Editable blocks from a seed and architectural theme.","neighborhood",null,"build"); sheet_action("Zoning","Let vacant lots develop gradually.","zoning",null,"layers")
			sheet_action("Plan before you build","Try roads and building footprints as blueprints.","blueprints",null,"layers")
	enforce_layout(); layout(); fade_in(sheet)

func refresh_catalog(reset_page: bool=true) -> void:
	if reset_page:studio.page=0
	studio.refresh_library(); studio.workspace_layout.fit_cards()
	for name in categories: categories[name].set_pressed_no_signal(name==group)
	favorite.set_pressed_no_signal(studio.favorites_only.button_pressed)
	update_catalog_notes()

func matches() -> Array[Dictionary]:
	var wanted: String="all"
	if query.text.strip_edges().is_empty(): wanted=studio.mode if style_choice.selected==0 else "all"
	if style_choice.selected==2: wanted="2d"
	if style_choice.selected==3: wanted="3d"
	var pack: String=pack_choice.get_item_text(pack_choice.selected) if pack_choice.selected>0 else ""
	var found: Array[Dictionary]=studio.library.find(wanted,"All assets",query.text,studio.favorites,studio.favorites_only.button_pressed,pack)
	found=studio.asset_browser.recents.filter(found)
	found=studio.asset_browser.collections.filter(found)
	var result: Array[Dictionary]=[]; var families: Dictionary={}
	for asset in found:
		if not studio.asset_browser.task_collections.matches(asset):continue
		if not studio.library.themes.matches(asset,studio.asset_browser.theme_filter):continue
		if not studio.asset_browser.semantic_search.matches(asset):continue
		if not preload("res://scripts/builder/asset_content.gd").visible(asset, studio.asset_browser.content_scope, studio.favorites_only.button_pressed): continue
		var layer: String=asset.get("behavior",{}).get("layer","Decorations")
		var source: String=asset["data"].get("source_name","")
		var belongs: bool=group=="Everything" or (group=="Buildings" and layer=="Buildings") or (group=="Nature" and layer=="Nature") or (group=="Interiors" and layer=="Furniture") or (group=="Transport" and (layer=="Vehicles" or source.begins_with("Vehicle_"))) or (group=="People" and (layer=="Characters" or (source.begins_with("SWAT_") and source!="SWAT_Display_Base"))) or (group=="Details" and layer in ["Decorations","Ground"])
		if not belongs: continue
		if not variants.button_pressed and query.text.strip_edges().is_empty() and not studio.favorites_only.button_pressed and not studio.asset_browser.recents.active() and not studio.asset_browser.collections.active():
			if asset["data"].get("source_pack","").begins_with("Characters") and asset["data"].get("kind","")!="char": continue
			if asset["data"].get("rigged",false): continue
		if not variants.button_pressed and query.text.strip_edges().is_empty() and not studio.favorites_only.button_pressed and not studio.asset_browser.recents.active() and not asset["data"].has("family_id") and asset["data"].get("source_pack","") in ["Village buildings","Bonsai trees","Water towers"]:
			var family: String=asset["data"]["source_pack"]+"/"+variant_expression.sub(source.get_slice("/",0),"",true)
			var score: int=(100 if source.contains("nopalette") else 0)+(10 if source.ends_with("/studio") else 0)
			if families.has(family):
				if score>families[family]["score"]: result[families[family]["index"]]=asset; families[family]["score"]=score
				continue
			families[family]={"index":result.size(),"score":score}
		result.append(asset)
	matched_member_count = result.size()
	if not variants.button_pressed and query.text.strip_edges().is_empty() and not studio.favorites_only.button_pressed and not studio.asset_browser.recents.active() and not studio.asset_browser.collections.active():
		result = studio.library.families.collapse(result)
	matched_design_count = result.size()
	return result if studio.asset_browser.recents.active() else studio.asset_browser.compatibility.order(result,query.text)

func card_name(asset: Dictionary) -> String:
	if studio.asset_browser.recents.active() or studio.asset_browser.collections.active():return asset["name"]
	if asset["data"].has("name_key"): return asset["name"]
	var source: String=asset["data"].get("source_name","")
	if not variants.button_pressed and query.text.strip_edges().is_empty() and not studio.favorites_only.button_pressed and asset["data"].get("source_pack","") in ["Village buildings","Bonsai trees","Water towers"]: return asset["data"].get("family_name", variant_expression.sub(source.get_slice("/",0),"",true).replace("_"," ").capitalize())
	var name: String=asset["name"]
	for prefix in ["Building ","Prop ","Vehicle ","Gear "]: name=name.trim_prefix(prefix)
	return name

func update_catalog_notes() -> void:
	studio.asset_browser.task_collections.refresh()
	preload("res://scripts/builder/asset_themes.gd").select(theme_choice,studio.asset_browser.theme_filter)
	var count: String=studio.asset_count.text.get_slice(" ",0)
	result_note.text=count+(" choice" if count=="1" else " choices")
	if matched_member_count > matched_design_count: result_note.text = "%d designs · %d members" % [matched_design_count, matched_member_count]
	if not studio.asset_browser.theme_filter.is_empty():result_note.text+=" · "+studio.library.themes.label(studio.asset_browser.theme_filter)
	result_note.tooltip_text=result_note.text
	page_note.text=studio.page_label.text; empty_note.visible=studio.cards.get_child_count()==0
	if studio.asset_browser.recents.only:
		result_note.text+=" · recent" if studio.asset_browser.recents.active() else " · library fallback"
		result_note.tooltip_text+="\n"+studio.asset_browser.recents.note()
	if empty_note.visible:
		empty_note.text="Nothing matches these filters. Theme: "+studio.library.themes.label(studio.asset_browser.theme_filter)+"; group: "+group+"; "+pack_choice.get_item_text(maxi(0,pack_choice.selected))+". Use Clear filters to browse everything."
	studio.asset_browser.semantic_search.refresh();empty_note.hide()

func asset_picked() -> void:
	if active: close_drawer(); dismiss_welcome()

func enforce_layout() -> void:
	if not active: return
	legacy_root.hide(); studio.mode_library.hide(); studio.mode_inspector.visible=details_open and not studio.walking
	drawer.visible=not drawer_kind.is_empty() and not studio.walking; details.visible=details_open and not studio.walking
	sheet.visible=not sheet_kind.is_empty(); backdrop.visible=sheet.visible
	welcome.visible=not welcome_seen and drawer_kind.is_empty() and sheet_kind.is_empty() and not studio.walking
	var precision_color: Color=Color("090d12") if studio.accessibility_settings.high_contrast else Design.PAPER
	var box: StyleBoxFlat=studio.mode_inspector.get_theme_stylebox("panel")
	if box.bg_color!=precision_color: box=box.duplicate(); box.bg_color=precision_color; studio.mode_inspector.add_theme_stylebox_override("panel",box)
	for world in studio.worlds.values(): world.grid.visible=studio.show_grid()

func tick(delta: float) -> void:
	if not active: return
	clock+=delta; notice_seconds=maxf(0,notice_seconds-delta)
	if clock<.08: return
	clock=0; enforce_layout()
	var photo: bool=studio.worlds[studio.mode].exploration.photo.active
	studio.canvas.mouse_default_cursor_shape=Control.CURSOR_CROSS if studio.tool in ["place","road","road_erase","crossing","terrain","zone","color","modular_room"] and not studio.walking else Control.CURSOR_ARROW
	if photo and (details_open or not drawer_kind.is_empty() or not sheet_kind.is_empty()): close_overlays()
	if studio.walking and not welcome_seen: dismiss_welcome()
	root.visible=not photo and not studio.workspace_presets.focused
	focus_return.visible=studio.workspace_presets.focused and not photo and not studio.small_prop_tools.active
	focus_return.tooltip_text="Return to city tools · "+studio.control_settings.label_for("focus_canvas")
	city_name.text=studio.current().data["title"]; city_name.tooltip_text=city_name.text+" · Click to rename"
	city_name.disabled=not studio.title_input.editable
	world_choice.select(0 if studio.mode=="2d" else 1)
	save_note.text="Saving a recovery copy…" if studio.autosave_pending and studio.storage_enabled else "Changes kept in recovery" if studio.dirty and studio.storage_enabled else "Unsaved changes" if studio.dirty else "Saved" if not studio.project_path.is_empty() else "Creative world · Save when you're ready"
	brand_symbol.modulate=Color.WHITE if studio.accessibility_settings.high_contrast else Design.ACCENT
	save_note.tooltip_text=studio.save_badge.text
	undo.disabled=studio.undo_button.disabled; redo.disabled=studio.redo_button.disabled
	var items: Array[Dictionary]=studio.selection_items(); var item: Dictionary=items[0] if not items.is_empty() else {}
	var id: String=item.get("asset",studio.selected_tile().get("asset",studio.asset_id))
	context.visible=studio.library.assets.has(id) and not studio.walking and not details_open and drawer_kind.is_empty() and sheet_kind.is_empty()
	if context.visible:
		context_name.text="%d selected"%items.size() if items.size()>1 else card_name(studio.library.assets[id]); context_picture.texture=studio.library.icon(id)
		context_note.text="Make it yours." if not item.is_empty() else "Choose a spot for this."
		if item.is_empty() and studio.economy_tools.Plan.settings(studio.current().data)["enabled"]: context_note.text="Build cost · %d credits"%studio.economy_tools.Plan.profile(id,studio.library)["construction"]
		context_capabilities.text=studio.library.capabilities.studio_summary(studio)
		context_capabilities.tooltip_text=studio.capability_note.text+"\nMore options → Selection shows every capability and its availability."
		context_actions.visible=not item.is_empty(); placement_actions.visible=item.is_empty(); context_repeat.set_pressed_no_signal(studio.repeat_input.button_pressed)
		context_focus_actions.visible=not item.is_empty()
		edit_inside.visible=not item.is_empty() and items.size()==1 and studio.library.assets[id].get("behavior",{}).get("building",false) and not studio.interior_tools.editing()
		edit_inside.disabled=studio.interior_tools.selected_edit.disabled
	var floors: RefCounted=studio.interior_tools.floor_tools
	room_navigation.visible=studio.interior_tools.bar.visible or floors.row.visible
	outside_button.visible=studio.interior_tools.bar.visible and studio.interior_tools.return_button.visible; edit_room.visible=studio.interior_tools.edit_button.visible
	room_layouts.visible=studio.interior_tools.room_kit_button.visible
	floor_choice.visible=floors.row.visible; floor_manage.visible=floors.row.visible
	if floor_choice.visible:
		var next: String=str(floors.choice.item_count)
		for index in floors.choice.item_count: next+="|"+floors.choice.get_item_text(index)
		if next!=floor_stamp:
			floor_stamp=next; floor_choice.clear()
			for index in floors.choice.item_count: floor_choice.add_item(floors.choice.get_item_text(index).get_slice(" · ",0))
		floor_choice.select(floors.choice.selected)
	var prompt: String=studio.worlds[studio.mode].exploration.prompt() if studio.walking else ""
	var blocked: String=studio.editor_feedback.blocked_reason() if not studio.walking else ""
	var keys: RefCounted=studio.control_settings
	var has_status: bool=false
	for entry in status_sources:
		var source: Label=entry["source"]; var caption: Label=entry["caption"]
		caption.visible=source.visible; caption.text=source.text; caption.tooltip_text=source.text
		if source==studio.cooperative_tools.badge and source.visible:
			var count: int=studio.cooperative_tools.session.roster.size(); caption.text="Building together · %d %s"%[count,"builder" if count==1 else "builders"]
		has_status=has_status or caption.visible
	status_panel.visible=has_status and not (studio.size.y<760 and not drawer_kind.is_empty())
	if details_open and studio.workspace_layout.tabs.current_tab>=0:
		var title: String=studio.workspace_layout.tabs.get_tab_title(studio.workspace_layout.tabs.current_tab); detail_title.text="Make it yours" if title=="Selection" else title
	var movement: PackedStringArray=[]
	for action in ["move_up","move_left","move_down","move_right"]: movement.append(keys.label_for(action).get_slice(" / ",0))
	hint.text=keys.walk_hint(prompt) if not prompt.is_empty() else "%s to move · %s to interact · %s to return"%[" ".join(movement),keys.label_for("interact"),keys.label_for("walk")] if studio.walking else blocked if not blocked.is_empty() else "Click to place · %s to rotate · %s to cancel"%[keys.label_for("rotate"),keys.label_for("cancel")] if not studio.asset_id.is_empty() else "Drag to connect · %s to finish"%keys.label_for("cancel") if studio.tool in ["road","crossing","road_erase"] else "Click to select · Drag to move · Scroll to zoom"
	undo.tooltip_text="Undo · "+keys.label_for("undo"); redo.tooltip_text="Redo · "+keys.label_for("redo")
	for entry in cancel_buttons: entry.tooltip_text="Close · "+keys.label_for("cancel")
	if studio.first_build.phase>=0 and studio.first_build.banner.visible: hint.text=studio.first_build.banner_text.text
	hint.tooltip_text=hint.text
	for key in dock_buttons:
		var selected: bool=(key=="build" and (drawer_kind=="build" or not studio.asset_id.is_empty())) or (key=="roads" and studio.tool in ["road","crossing","road_erase"]) or (key=="explore" and studio.walking) or (key=="life" and sheet_kind in ["life","travel","services","goals","growth"]) or (key=="landscape" and sheet_kind=="landscape")
		var entry: Button=dock_buttons[key]; var color: Color=Color.WHITE if selected or studio.accessibility_settings.high_contrast else Design.INK; entry.set_pressed_no_signal(selected); entry.get_meta("picture").modulate=color; entry.get_meta("caption").add_theme_color_override("font_color",color)
		if key=="explore": entry.get_meta("caption").text="Return" if studio.walking else "Explore"
	if studio.status.text!=notice_seen:
		notice_seen=studio.status.text
		if not notice_seen.is_empty() and not notice_seen.begins_with("Ready to place") and not notice_seen.begins_with("Welcome!") and not notice_seen.begins_with("Building camera") and not notice_seen.begins_with("Workspace ·") and not notice_seen.begins_with("WASD"): notice_text.text=notice_seen; notice_text.tooltip_text=notice_seen; notice_seconds=6
	notice.visible=notice_seconds>0 and sheet_kind.is_empty() and drawer_kind.is_empty() and not studio.walking
	update_catalog_notes()
	layout()

func input(event: InputEvent) -> bool:
	if not active or not event is InputEventKey or not event.pressed or event.echo: return false
	if studio.worlds[studio.mode].exploration.photo.active: return false
	for child in studio.get_children():
		if child is Window and child.visible: return false
	if studio.control_settings.match_event(event)!="cancel": return false
	if studio.small_prop_tools.active:return false
	if studio.workspace_presets.focused: studio.workspace_presets.set_focus(false); return true
	if not sheet_kind.is_empty(): close_sheet(); return true
	if details_open: details_open=false; enforce_layout(); return true
	if not drawer_kind.is_empty(): close_drawer(); return true
	return false

func over_canvas(at: Vector2) -> bool:
	if not sheet_kind.is_empty(): return false
	for control in [header,header_actions,dock,hint_panel,drawer,details,context,welcome,notice,status_panel,room_navigation,focus_return]:
		if control.is_visible_in_tree() and control.get_global_rect().has_point(at): return false
	return true

func layout() -> void:
	if not is_instance_valid(root): return
	var size: Vector2=studio.size; var width: float=size.x; var height: float=size.y
	header.position=Vector2(22,20); header.size=Vector2(clampf(width*.28,250,380),70)
	var action_size: Vector2=header_actions.get_combined_minimum_size(); header_actions.size=Vector2(maxf(420,action_size.x),70); header_actions.position=Vector2(width-header_actions.size.x-22,20)
	dock.size=dock.get_combined_minimum_size(); dock.position=Vector2((width-dock.size.x)*.5,height-dock.size.y-20)
	if hint_contrast!=studio.accessibility_settings.high_contrast:
		hint_contrast=studio.accessibility_settings.high_contrast; hint_panel.add_theme_stylebox_override("panel",Design.surface(Color("090d12") if hint_contrast else Design.PAPER,14,8))
	hint_panel.size=Vector2(minf(width-44,660),maxf(38,hint_panel.get_combined_minimum_size().y)); hint_panel.position=Vector2((width-hint_panel.size.x)*.5,dock.position.y-hint_panel.size.y-10)
	var floor_y: float=hint_panel.position.y
	var compact: bool=width<1100 or studio.accessibility_settings.text_scale>1.3
	group_flow.visible=not compact; compact_groups.visible=compact
	group_choice.select(maxi(0,GROUPS.find(group)))
	var group_parent: Node=compact_groups if compact else group_flow
	if favorite.get_parent()!=group_parent: favorite.reparent(group_parent)
	var page_parent: Node=compact_groups if compact else build_box
	if pages_row.get_parent()!=page_parent: pages_row.reparent(page_parent)
	var style_order: OptionButton=studio.asset_browser.compatibility.simple_choice
	var style_parent: Node=refine_controls if refine.visible or compact else theme_row
	if style_order.get_parent()!=style_parent:style_order.reparent(style_parent)
	studio.asset_browser.compatibility.simple_note.visible=not refine.visible and not compact and studio.cards.get_child_count()>0
	# Compact browsing keeps a complete card row available. Less frequent theme,
	# coordinated-set and part refinements share the existing scrollable Refine.
	var collection: RefCounted=studio.asset_browser.task_collections
	var task_controls: Dictionary=collection.controls[-1]
	var task_choice: OptionButton=task_controls["task"]
	var theme_parent: Node=refine_controls if compact else theme_row
	for control in [theme_caption,theme_choice]:
		if control.get_parent()!=theme_parent:control.reparent(theme_parent)
	var task_parent: Node=theme_row if compact else task_controls["flow"]
	if task_choice.get_parent()!=task_parent:task_choice.reparent(task_parent)
	var recent_choice: Button=studio.asset_browser.recents.controls[-1]
	if recent_choice.get_parent()!=task_parent:recent_choice.reparent(task_parent)
	if compact:theme_row.move_child(task_choice,0)
	if compact:theme_row.move_child(recent_choice,1)
	else:
		task_controls["flow"].move_child(task_choice,0);theme_row.move_child(theme_caption,0);theme_row.move_child(theme_choice,1)
	for control in [task_controls["sets"],task_controls["parts"]]:
		var destination: Node=refine_controls if compact else task_controls["flow"]
		if control.get_parent()!=destination:control.reparent(destination)
	var selected_task: Dictionary=collection.selection()
	var task_warning: bool=not collection.task.is_empty() and (not selected_task["missing"].is_empty() or not selected_task["outdoor"].is_empty())
	task_controls["panel"].visible=not compact or task_warning
	task_controls["note"].visible=not collection.task.is_empty() and (not compact or task_warning)
	refine.custom_minimum_size.y=64 if height<760 and studio.accessibility_settings.text_scale>1.3 else (120 if height<760 else 160)
	filter_button.text="Done" if refine.visible else "Refine"
	card_scroll.visible=not (refine.visible and height<760)
	var wanted_thumbnail: int=92 if height<760 else 132
	if active and studio.thumbnail_size!=wanted_thumbnail: studio.thumbnail_size=wanted_thumbnail; studio.call_deferred("refresh_library")
	var top: float=maxf(header.position.y+header.size.y,header_actions.position.y+header_actions.size.y)+12
	var wanted_height: float=390+refine.get_combined_minimum_size().y+10 if refine.visible else 390
	if drawer_kind=="build" and card_scroll.visible and studio.cards.get_child_count()>0:
		wanted_height=maxf(wanted_height,drawer.get_combined_minimum_size().y+studio.cards.get_child(0).get_combined_minimum_size().y+12)
	var drawer_height: float=minf(wanted_height,floor_y-top-12)
	if drawer_kind=="roads": drawer_height=200
	drawer.size=Vector2(minf(width-44,1240),drawer_height); drawer.position=Vector2((width-drawer.size.x)*.5,floor_y-drawer.size.y-12)
	details.size=Vector2(minf(410,width-44),maxf(240,height-250)); details.position=Vector2(width-details.size.x-22,104)
	context.size=Vector2(maxf(324,context.get_combined_minimum_size().x),0); context.position=Vector2(width-context.size.x-22,maxf(104,top))
	var nav_width: float=minf(width-44,650)
	if context.visible: nav_width=minf(nav_width,context.position.x-44)
	if details.visible: nav_width=minf(nav_width,details.position.x-44)
	room_navigation.size=Vector2(maxf(230,nav_width),0); room_navigation.position=Vector2(22,top)
	status_panel.size=Vector2(minf(380,width-44),0); status_panel.position=Vector2(22,room_navigation.position.y+room_navigation.size.y+12 if room_navigation.visible else top)
	sheet.size=Vector2(minf(width-60,500),minf(height-130,650)); sheet.position=(size-sheet.size)*.5
	welcome.size=Vector2(370,0); welcome.position=Vector2(22,maxf(132,status_panel.position.y+status_panel.size.y+14) if status_panel.visible else 132)
	var notice_width: float=minf(620,width-44)
	if details.visible:notice_width=minf(notice_width,maxf(1,details.position.x-34))
	notice.size=Vector2(notice_width,42); notice.position=Vector2(22,height-210)
	expert_return.size=Vector2(216,46); expert_return.position=Vector2((width-216)*.5,height-62)
	focus_return.size=Vector2(220,46); focus_return.position=Vector2((width-220)*.5,height-62)
	studio.workspace_layout.fit_cards()

func fade_in(control: Control) -> void:
	control.modulate.a=0; var tween:=studio.create_tween(); tween.tween_property(control,"modulate:a",1.0,.14)
