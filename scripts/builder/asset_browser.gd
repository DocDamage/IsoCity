extends RefCounted

var studio: Control
var pack: OptionButton
var sizes: OptionButton
var chips: HFlowContainer
var filter_scroll: ScrollContainer
var dialog: AcceptDialog
var preview_scroll: ScrollContainer
var title: Label
var details: Label
var picture: TextureRect
var model_container: SubViewportContainer
var viewport: SubViewport
var model_world: Node3D
var pivot: Node3D
var views: OptionButton
var views_label: Label
var play: CheckButton
var frame: HSlider
var frame_note: Label
var orbit_row: HBoxContainer
var selected_id: String = ""
var frames: int = 1
var fps: float = 8
var elapsed: float = 0
var atlas: AtlasTexture
var frame_size := Vector2.ZERO
var frame_origin := Vector2.ZERO
var group_variants: CheckBox
var appearance_row: HBoxContainer
var palette: OptionButton
var lighting: OptionButton
var replace_member: Button
var refreshing_appearance: bool = false
var matched_members: int = 0
var matched_designs: int = 0
var action_row: HBoxContainer
var preview_actions: OptionButton
var playback_speed: SpinBox
var playback_loop: bool = true
var ground_marker: Label
var ground_anchor := Vector2.ZERO
var character_picture: TextureRect
var character_bounds := Rect2()
const Content = preload("res://scripts/builder/asset_content.gd")
const CONTENT_SETTINGS = "user://studio_asset_content.json"
var content_scope: int = 0
var content_choice: OptionButton
var reviewed_parts: OptionButton
var original_source: Button
var content_settings_path: String = CONTENT_SETTINGS
var filter_refine: Button
var filters_expanded: bool = true
var filters_manual: bool = false
const Themes=preload("res://scripts/builder/asset_themes.gd")
var theme_choice: OptionButton
var theme_filter: String=""
var theme_settings_path: String="user://studio_asset_theme.json"
var clear_filters: Button
var canvas_return: Button
var scale_preview: RefCounted
var compatibility: RefCounted
var semantic_search: RefCounted
var health_tools: RefCounted
var task_collections: RefCounted
var recents: RefCounted
var collections: RefCounted

func _init(host: Control) -> void:
	studio = host
	var column: Node = studio.search.get_parent()
	if studio.storage_enabled:restore_theme()
	theme_choice=OptionButton.new();theme_choice.name="ThemeCollection"
	studio.library.themes.fill(theme_choice,studio.library);Themes.select(theme_choice,theme_filter)
	column.add_child(theme_choice);column.move_child(theme_choice,studio.asset_type.get_index())
	theme_choice.item_selected.connect(func(index: int):set_theme(str(theme_choice.get_item_metadata(index))))
	compatibility=preload("res://scripts/builder/style_suggestions.gd").new(studio,column,theme_choice)
	canvas_return=Button.new();canvas_return.text="Return to canvas";column.add_child(canvas_return);column.move_child(canvas_return,theme_choice.get_index()+1)
	canvas_return.pressed.connect(focus_canvas)
	pack = OptionButton.new()
	pack.fit_to_longest_item = false
	pack.clip_text = true
	pack.add_item("All packs")
	var names: Array[String] = []
	for asset in studio.library.assets.values():
		var name: String = studio.library.pack_name(asset)
		if not names.has(name): names.append(name)
	names.sort()
	for name in names: pack.add_item(name)
	column.add_child(pack)
	column.move_child(pack,studio.category.get_index()+1)
	pack.item_selected.connect(func(index: int): studio.pack_filter = "" if index==0 else pack.get_item_text(index); studio.page=0; studio.refresh_library())
	sizes = OptionButton.new()
	for text in ["Compact thumbnails","Standard thumbnails","Large thumbnails"]: sizes.add_item(text)
	sizes.select(1)
	sizes.fit_to_longest_item = false
	sizes.clip_text = true
	column.add_child(sizes)
	column.move_child(sizes,pack.get_index()+1)
	sizes.item_selected.connect(func(index: int): studio.thumbnail_size=[96,128,192][index]; studio.refresh_library())
	if studio.storage_enabled: restore_content_scope()
	content_choice = OptionButton.new(); content_choice.fit_to_longest_item = false; content_choice.clip_text = true
	for text in Content.LABELS: content_choice.add_item(text)
	content_choice.select(content_scope); content_choice.tooltip_text = "Choose objects, deliberate scenery, or original sheets/references. Existing placements and favorites remain available."
	column.add_child(content_choice); column.move_child(content_choice, sizes.get_index() + 1)
	content_choice.item_selected.connect(set_content_scope)
	group_variants = CheckBox.new(); group_variants.text = "Group appearance variants"; group_variants.button_pressed = true
	column.add_child(group_variants); column.move_child(group_variants, sizes.get_index() + 1)
	group_variants.toggled.connect(func(_value: bool): studio.page = 0; studio.refresh_library())
	chips = HFlowContainer.new()
	chips.name = "ActiveFilters"
	column.add_child(chips)
	column.move_child(chips,sizes.get_index()+1)
	var first: int=studio.search.get_index()
	var controls: Array[Node]=column.get_children().slice(first,studio.favorites_only.get_index()+1)
	controls.erase(studio.search); controls.erase(chips)
	var filter_header := HBoxContainer.new(); column.add_child(filter_header); column.move_child(filter_header,first)
	studio.search.reparent(filter_header); studio.search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_refine = Button.new(); filter_refine.text = "Refine"; filter_refine.toggle_mode = true; filter_header.add_child(filter_refine)
	filter_refine.tooltip_text = "Show or close type, pack, appearance, content and favorite filters. Search and active filters remain visible."
	filter_refine.toggled.connect(func(value: bool): filters_manual = true; filters_expanded = value; fit_filters())
	clear_filters=Button.new();clear_filters.text="Clear";clear_filters.custom_minimum_size=Vector2(44,36);filter_header.add_child(clear_filters)
	clear_filters.tooltip_text="Clear filters · show all themes, types, packs and content; clear search and favorites."
	clear_filters.pressed.connect(func():semantic_search.clear_or_restore())
	column.move_child(chips,filter_header.get_index()+1)
	filter_scroll=ScrollContainer.new()
	filter_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	filter_scroll.follow_focus = true
	column.add_child(filter_scroll)
	column.move_child(filter_scroll,filter_header.get_index()+2)
	var filter_box:=VBoxContainer.new()
	filter_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	filter_box.add_theme_constant_override("separation",8)
	filter_scroll.add_child(filter_box)
	for control in controls: control.reparent(filter_box)
	studio.resized.connect(fit_filters)
	fit_filters()
	make_dialog()
	semantic_search=preload("res://scripts/builder/semantic_search_tools.gd").new(studio,filter_box,column,filter_scroll)
	health_tools=preload("res://scripts/builder/asset_health_tools.gd").new(studio,filter_box)
	task_collections=preload("res://scripts/builder/task_collection_tools.gd").new(studio,filter_box)
	recents=preload("res://scripts/builder/recent_asset_tools.gd").new(studio,task_collections.controls[0]["flow"])
	collections=preload("res://scripts/builder/collection_tools.gd").new(studio,filter_box)

func restore_theme() -> void:
	var value: Variant=studio.Store.read_json(theme_settings_path,{})
	var saved: Variant=value.get("theme","") if value is Dictionary else ""
	theme_filter=saved if saved is String and (Themes.KEYS.has(saved) or saved=="unclassified") else ""

func set_theme(value: String) -> void:
	theme_filter=value if Themes.KEYS.has(value) or value=="unclassified" else ""
	Themes.select(theme_choice,theme_filter)
	if studio.consumer_shell:Themes.select(studio.consumer_shell.theme_choice,theme_filter)
	if studio.storage_enabled and not studio.Store.write_json(theme_settings_path,{"theme":theme_filter}):studio.status.text="Theme applied for this session; preferences could not be saved."
	studio.page=0;studio.refresh_library()

func focus_canvas() -> void:
	studio.canvas.focus_mode=Control.FOCUS_ALL;studio.canvas.grab_focus()

func clear_all_filters(preserve_collection: bool=false) -> void:
	if collections and not preserve_collection:collections.select_filter("",false)
	if recents:recents.only=false
	if task_collections:task_collections.clear()
	if semantic_search:semantic_search.saved_filters={};semantic_search.set_use("")
	studio.pack_filter="";pack.select(0);studio.asset_type.select(0);studio.populate_categories();studio.category.select(0)
	studio.search.text="";studio.favorites_only.set_pressed_no_signal(false)
	if studio.consumer_shell:
		var ui: RefCounted=studio.consumer_shell;ui.query.text="";ui.pack_choice.select(0);ui.style_choice.select(1);ui.group="Everything"
	set_theme("");set_content_scope(2)
	if studio.consumer_shell and studio.consumer_shell.active:studio.consumer_shell.refresh_catalog()

func set_content_scope(value: int) -> void:
	content_scope = clampi(value, 0, 2); content_choice.select(content_scope)
	if studio.consumer_shell: studio.consumer_shell.content_choice.select(content_scope)
	if studio.storage_enabled and not studio.Store.write_json(content_settings_path, {"scope":content_scope}): studio.status.text = "Content filter applied for this session; preferences could not be saved."
	studio.page = 0; studio.refresh_library()
	if studio.consumer_shell and studio.consumer_shell.active: studio.consumer_shell.update_catalog_notes()

func restore_content_scope() -> void:
	var saved: Variant = studio.Store.read_json(content_settings_path, {})
	var value: Variant = saved.get("scope", 0) if saved is Dictionary else 0
	content_scope = 0
	if (value is int or value is float) and is_finite(float(value)) and value == roundf(value) and value >= 0 and value <= 2: content_scope = int(value)

func fit_filters() -> void:
	if not filters_manual: filters_expanded = studio.size.y >= 760
	filter_scroll.visible = filters_expanded
	filter_refine.set_pressed_no_signal(filters_expanded); filter_refine.text = "Done" if filters_expanded else "Refine"
	filter_scroll.custom_minimum_size.y=clampf(studio.size.y-700,140,240)

func refresh() -> void:
	if collections:collections.refresh()
	if recents:recents.refresh()
	if task_collections:task_collections.refresh()
	Themes.select(theme_choice,theme_filter)
	if matched_members > matched_designs and (not studio.consumer_shell or not studio.consumer_shell.active): studio.asset_count.text = "%d designs · %d members" % [matched_designs, matched_members]
	if recents and recents.only:studio.asset_count.text+=" · "+recents.note()
	if collections and not collections.selection().is_empty():studio.asset_count.text+=" · "+collections.note()
	pack.select(0)
	for index in range(1,pack.item_count):
		if pack.get_item_text(index)==studio.pack_filter: pack.select(index)
	for child in chips.get_children(): chips.remove_child(child); child.queue_free()
	if task_collections and not task_collections.task.is_empty():add_chip("task",studio.library.tasks.tasks[task_collections.task]["name"])
	if recents and recents.only:add_chip("recent","Recent placements")
	if collections and not collections.selection().is_empty():add_chip("collection",collections.selected_collection().get("name","Project recommendation"))
	if not theme_filter.is_empty():add_chip("theme",studio.library.themes.label(theme_filter))
	if semantic_search and not semantic_search.use_filter.is_empty():add_chip("use","Unreviewed" if semantic_search.use_filter=="unreviewed" else studio.library.search_index.groups[semantic_search.use_filter])
	if studio.asset_type.selected>0: add_chip("type",studio.asset_type.get_item_text(studio.asset_type.selected))
	if studio.category.selected>0: add_chip("category",studio.category.get_item_text(studio.category.selected))
	if not studio.pack_filter.is_empty(): add_chip("pack",studio.pack_filter)
	if studio.favorites_only.button_pressed: add_chip("favorites","Favorites")
	if not studio.search.text.is_empty(): add_chip("query",studio.search.text)
	chips.visible = chips.get_child_count()>0
	for card in studio.cards.get_children():
		var asset: Dictionary=studio.library.assets[card.asset_id]
		card.tooltip_text+="\nPack: "+studio.library.pack_name(asset)+"\n"+studio.library.themes.describe(asset)
		var inspect := Button.new()
		inspect.text = "⋯"
		inspect.tooltip_text = "Inspect asset · larger views, animation, dimensions and source pack"
		inspect.position = Vector2(2,2)
		inspect.size = Vector2(30,28)
		var family: String = studio.library.assets[card.asset_id]["data"].get("family_id", "")
		var count: int = studio.library.families.members.get(family, []).size()
		if count > 1:
			inspect.text = "Variants"; inspect.size.x = minf(70, studio.thumbnail_size - 40)
			inspect.add_theme_font_size_override("font_size", 10)
			inspect.tooltip_text = "%d appearance members · inspect palette, baked lighting and source angle" % count
		inspect.focus_mode = Control.FOCUS_ALL
		card.add_child(inspect)
		card.inspect_button = inspect
		card.reflow(studio.thumbnail_size,studio.accessibility_settings.text_scale)
		inspect.pressed.connect(func(): show_asset(card.asset_id))
		card.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT and event.pressed: show_asset(card.asset_id); card.accept_event()
		)
	studio.workspace_layout.fit_cards()
	compatibility.refresh()
	studio.workspace_layout.fit_cards()
	if semantic_search and (not studio.consumer_shell or not studio.consumer_shell.active):semantic_search.refresh()

func add_chip(key: String, text: String) -> void:
	var button := Button.new()
	button.name = key
	button.text = "× "+text
	button.clip_text = true
	button.tooltip_text = "Remove " + key + " filter: " + text
	chips.add_child(button)
	button.custom_minimum_size.x = clampf(button.get_theme_font("font").get_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,-1,button.get_theme_font_size("font_size")).x+26,80,180)
	button.pressed.connect(func(): clear_filter(key))

func clear_filter(key: String) -> void:
	match key:
		"collection":collections.select_filter("",false)
		"task":task_collections.clear()
		"recent":recents.only=false
		"use":semantic_search.set_use("")
		"theme":set_theme("")
		"type":
			var previous: String=studio.category.get_item_text(maxi(0,studio.category.selected))
			studio.asset_type.select(0)
			studio.populate_categories()
			for index in studio.category.item_count:
				if studio.category.get_item_text(index)==previous: studio.category.select(index)
		"category": studio.category.select(0)
		"pack": studio.pack_filter=""; pack.select(0)
		"favorites": studio.favorites_only.set_pressed_no_signal(false)
		"query": studio.search.text=""
	studio.page=0
	studio.refresh_library()

func settings() -> Dictionary:
	var saved_size: int=studio.consumer_shell.old_thumbnail if studio.consumer_shell and studio.consumer_shell.active else studio.thumbnail_size
	return {"pack":studio.pack_filter,"thumbnail_size":saved_size}

func restore(value: Variant) -> void:
	var data: Dictionary = value if value is Dictionary else {}
	studio.pack_filter=""
	pack.select(0)
	for index in range(1,pack.item_count):
		if pack.get_item_text(index)==data.get("pack",""): studio.pack_filter=pack.get_item_text(index); pack.select(index)
	var size_value: Variant=data.get("thumbnail_size",128)
	studio.thumbnail_size = int(size_value) if (size_value is int or size_value is float) and float(size_value) in [96.0,128.0,192.0] else 128
	if studio.consumer_shell and studio.consumer_shell.active:studio.consumer_shell.old_thumbnail=studio.thumbnail_size
	sizes.select([96,128,192].find(studio.thumbnail_size))

func make_dialog() -> void:
	dialog = AcceptDialog.new()
	dialog.title = "Inspect asset"
	dialog.size = Vector2i(740,650)
	studio.get_window().size_changed.connect(fit_preview_dialog)
	studio.add_child(dialog)
	preview_scroll = ScrollContainer.new()
	preview_scroll.custom_minimum_size = Vector2(360, 240)
	preview_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	preview_scroll.follow_focus = true
	dialog.add_child(preview_scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_scroll.add_child(box)
	title=studio.label(box,"",19)
	title.clip_text=true
	details=studio.label(box,"",12)
	details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	picture=TextureRect.new()
	picture.custom_minimum_size=Vector2(360,160)
	picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	picture.size_flags_vertical=Control.SIZE_EXPAND_FILL
	box.add_child(picture)
	ground_marker = Label.new(); ground_marker.text = "+"; ground_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ground_marker.add_theme_font_size_override("font_size", 20); ground_marker.add_theme_color_override("font_color", Color(.1, .65, .85))
	ground_marker.tooltip_text = "Authored ground contact"; ground_marker.hide(); picture.add_child(ground_marker)
	picture.clip_contents = true
	character_picture = TextureRect.new(); character_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	character_picture.stretch_mode = TextureRect.STRETCH_SCALE; character_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	character_picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; character_picture.hide(); picture.add_child(character_picture); picture.move_child(character_picture, 0)
	picture.resized.connect(update_frame)
	model_container=SubViewportContainer.new()
	model_container.custom_minimum_size=Vector2(360,160)
	model_container.size_flags_vertical=Control.SIZE_EXPAND_FILL
	model_container.stretch=true
	box.add_child(model_container)
	viewport=SubViewport.new()
	viewport.own_world_3d=true
	viewport.gui_disable_input=true
	viewport.size=Vector2i(640,360)
	viewport.render_target_update_mode=SubViewport.UPDATE_WHEN_VISIBLE
	model_container.add_child(viewport)
	scale_preview=preload("res://scripts/builder/asset_scale_preview.gd").new(self,box)
	box.move_child(scale_preview.toggle,picture.get_index());box.move_child(scale_preview.panel,scale_preview.toggle.get_index()+1)
	views_label = studio.label(box, "Source angle · supplied artwork", 12)
	views=OptionButton.new()
	box.add_child(views)
	views.item_selected.connect(func(_index: int): load_view())
	action_row = HBoxContainer.new(); box.add_child(action_row)
	studio.label(action_row, "Action · preview only", 12)
	preview_actions = OptionButton.new(); preview_actions.fit_to_longest_item = false; preview_actions.clip_text = true
	preview_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL; action_row.add_child(preview_actions)
	preview_actions.item_selected.connect(func(_index: int): refresh_preview_views())
	playback_speed = SpinBox.new(); playback_speed.min_value = .25; playback_speed.max_value = 2; playback_speed.step = .25; playback_speed.value = 1; playback_speed.suffix = "×"
	playback_speed.tooltip_text = "Preview playback speed"; action_row.add_child(playback_speed)
	appearance_row = HBoxContainer.new(); box.add_child(appearance_row)
	studio.label(appearance_row, "Palette", 12)
	palette = OptionButton.new(); palette.size_flags_horizontal = Control.SIZE_EXPAND_FILL; palette.fit_to_longest_item = false; palette.clip_text = true; appearance_row.add_child(palette)
	studio.label(appearance_row, "Baked lighting", 12)
	lighting = OptionButton.new(); lighting.size_flags_horizontal = Control.SIZE_EXPAND_FILL; lighting.fit_to_longest_item = false; lighting.clip_text = true; appearance_row.add_child(lighting)
	palette.item_selected.connect(func(_index: int): choose_appearance())
	lighting.item_selected.connect(func(_index: int): choose_appearance())
	play=CheckButton.new()
	play.text="Play animation"
	box.add_child(play)
	play.toggled.connect(func(value: bool): if value and frames > 1 and frame.value >= frames - 1: frame.set_value_no_signal(0); update_frame())
	frame=HSlider.new()
	frame.step=1
	box.add_child(frame)
	frame.value_changed.connect(func(_value: float): update_frame())
	frame_note=studio.label(box,"",12)
	orbit_row=HBoxContainer.new()
	box.add_child(orbit_row)
	for step in [-45,45]:
		var button:=Button.new()
		button.text="Turn left" if step<0 else "Turn right"
		orbit_row.add_child(button)
		button.pressed.connect(func(): if pivot: pivot.rotation_degrees.y+=step)
	var choose:=Button.new()
	choose.text="Choose for placement"
	box.add_child(choose)
	choose.pressed.connect(choose_for_placement)
	var suggest:=Button.new();suggest.text="Suggest this style";box.add_child(suggest)
	suggest.tooltip_text="Order existing search results using this source's style metadata. Does not place or replace an object."
	suggest.pressed.connect(func():compatibility.anchor(selected_id);dialog.hide())
	replace_member = Button.new(); replace_member.text = "Replace selected appearance"; box.add_child(replace_member)
	replace_member.pressed.connect(apply_appearance)
	reviewed_parts = OptionButton.new(); reviewed_parts.fit_to_longest_item = false; reviewed_parts.clip_text = true; box.add_child(reviewed_parts)
	reviewed_parts.item_selected.connect(func(index: int):
		if index > 0: show_asset(reviewed_parts.get_item_metadata(index)))
	original_source = Button.new(); original_source.text = "Inspect original source asset"; box.add_child(original_source)
	original_source.pressed.connect(func():
		if not selected_id.is_empty(): show_asset(studio.library.assets[selected_id]["data"].get("source_asset", "")))
	dialog.visibility_changed.connect(func():
		if not dialog.visible: clear_preview()
	)

func clear_preview() -> void:
	if scale_preview:scale_preview.clear();scale_preview.panel.hide()
	if is_instance_valid(model_world): model_world.free()
	model_world=null
	pivot=null
	picture.texture=null
	character_picture.texture = null; character_picture.hide(); ground_marker.hide()
	atlas=null
	selected_id=""

func show_asset(id: String) -> void:
	if not studio.library.assets.has(id): return
	if not preload("res://scripts/builder/repair_assets.gd").available(id,studio.library,{}): studio.status.text="This asset's source is unavailable."; return
	clear_preview()
	selected_id=id
	var asset: Dictionary=studio.library.assets[id]
	title.text=asset["name"]
	title.tooltip_text=title.text
	details.text="%s · %s · Pack: %s\n%s" % [asset["mode"].to_upper(),asset["category"],studio.library.pack_name(asset),id]
	details.text += "\n" + animation_text(asset)
	refresh_content(asset)
	var sprite: bool=asset["mode"]=="2d"
	picture.visible=sprite
	model_container.visible=not sprite
	views.visible=sprite
	views_label.visible = sprite
	orbit_row.visible=not sprite
	views.clear()
	refresh_actions(asset)
	if sprite:
		refresh_preview_views()
		var selected: Array=studio.selection_items()
		if selected.size()==1 and selected[0]["asset"]==id:
			for index in views.item_count:
				if views.get_item_text(index)==selected[0]["direction"]:views.select(index);load_view();break
	else:
		play.hide(); frame.hide(); frame_note.hide()
		load_model(asset)
	refresh_appearance()
	scale_preview.refresh(true)
	dialog.popup_centered(preview_dialog_size())

func preview_dialog_size() -> Vector2i:
	var window: Vector2i = studio.get_window().size
	return Vector2i(clampi(window.x-48,360,740),clampi(window.y-80,320,650))

func fit_preview_dialog() -> void:
	if not is_instance_valid(dialog) or not dialog.visible: return
	dialog.size = preview_dialog_size()
	dialog.position = (studio.get_window().size-dialog.size)/2

func load_view() -> void:
	if selected_id.is_empty() or views.item_count==0: return
	var asset: Dictionary=studio.library.assets[selected_id]
	var definition: Dictionary = preview_definition(asset)
	if not definition.get("directions") is Dictionary: unavailable_preview("This source clip has damaged direction metadata."); return
	var candidate: Variant = definition["directions"].get(views.get_item_text(views.selected))
	if not valid_preview_view(candidate, definition, asset["data"]): unavailable_preview("This source view has damaged frame metadata."); return
	var view: Dictionary=candidate
	var file: String=view["file"]
	var path: String="res://assets/"+file.trim_prefix("../../") if file.begins_with("../../") else "res://assets/pixel_isometric/"+file
	if file.begins_with("res://"): path = file
	if not ResourceLoader.exists(path):
		unavailable_preview("This source view is unavailable."); return
	var logging: bool = Engine.print_error_messages; Engine.print_error_messages = false
	var texture: Texture2D=load(path) as Texture2D
	Engine.print_error_messages = logging
	if not texture: unavailable_preview("This source image could not be read."); return
	var area: Rect2=preload("res://scripts/sprite_view.gd").region(view,texture); frame_origin=area.position
	frame_size=Vector2(view.get("frame_width",area.size.x),view.get("frame_height",area.size.y))
	frame_size = frame_size.max(Vector2.ONE)
	var available_frames: int = maxi(1, mini(int(view.get("frames",asset["data"].get("frames",area.size.x/frame_size.x))),int(area.size.x/frame_size.x)))
	var first_frame: int = clampi(int(definition.get("first_frame", 0)), 0, available_frames - 1)
	frame_origin.x += first_frame * frame_size.x
	frames = clampi(int(definition.get("frame_count", available_frames - first_frame)), 1, available_frames - first_frame)
	fps = clampf(float(definition.get("fps", asset["data"].get("fps", 8))), .1, 120)
	if not is_finite(fps): fps = 8
	playback_loop = definition.get("loop", true)
	atlas=AtlasTexture.new()
	atlas.atlas=texture
	ground_marker.visible = asset["data"].get("kind", "") in ["char", "pet"]
	character_picture.visible = ground_marker.visible
	if ground_marker.visible:
		var contact: Array = view.get("render_contact", view.get("grid_contact", view.get("actor_origin", view.get("origin", [0, 0]))))
		ground_anchor = Vector2(contact[0], contact[1])
		character_bounds = clip_bounds(texture)
		character_picture.texture = atlas; picture.texture = null
	else: picture.texture=atlas
	frame.max_value=frames-1
	frame.set_value_no_signal(0)
	elapsed=0
	play.visible=frames>1
	play.text="Cycle day / night" if asset["data"].get("kind","")=="build" and frames==2 else "Play animation"
	frame_note.tooltip_text=str(asset["data"].get("animation","Frames in the selected source view"))
	play.set_pressed_no_signal(frames>1)
	frame.visible=frames>1
	frame_note.show()
	update_frame()
	var footprint: Array=view.get("footprint",[1,1])
	details.text="%s · %s · Pack: %s\n%s\n%d × %d px per frame · footprint %s × %s cells" % [asset["mode"].to_upper(),asset["category"],studio.library.pack_name(asset),selected_id,frame_size.x,frame_size.y,footprint[0],footprint[1]]
	details.text += "\n" + animation_text(asset)
	details.text += content_text(asset)
	views_label.text = "Supplied opening state · no movement animation" if asset["data"].get("source_view_kind") == "state" else "Source angle · supplied artwork"
	views.tooltip_text = "Source angle changes supplied artwork for preview and new placement; world rotation is separate. Replacing an existing appearance preserves its placed source angle."
	if asset["data"].get("source_view_kind") == "state": views.tooltip_text = "Inspect or place a supplied door state. These choices do not operate a door or change an existing placement."
	details.tooltip_text = details.text
	if scale_preview:scale_preview.refresh()

func content_text(asset: Dictionary) -> String:
	var data: Dictionary = asset["data"]
	var result: String = "\n" + Content.kind(asset).capitalize() if data.has("content_kind") else ""
	if not str(data.get("content_note", "")).is_empty(): result += " · " + str(data["content_note"])
	if data.has("source_name"): result += "\nSource: " + str(data["source_name"])
	elif data.has("name_source"): result += "\nSource: " + str(data["name_source"])
	result+="\n"+studio.library.themes.describe(asset)
	result+="\n"+studio.library.capabilities.describe(asset["id"],studio.library)
	return result

func refresh_content(asset: Dictionary) -> void:
	details.text += content_text(asset)
	reviewed_parts.clear(); reviewed_parts.add_item("Inspect reviewed parts · keeps the original placement")
	var alternatives: Variant = asset["data"].get("replacement_ids", [])
	if not alternatives is Array: alternatives = []
	for id in alternatives:
		if not id is String: continue
		if not studio.library.assets.has(id): continue
		reviewed_parts.add_item(studio.library.assets[id]["name"]); reviewed_parts.set_item_metadata(reviewed_parts.item_count - 1, id)
	reviewed_parts.visible = reviewed_parts.item_count > 1
	original_source.visible = studio.library.assets.has(asset["data"].get("source_asset", ""))
	details.tooltip_text=details.text

func update_frame() -> void:
	if not atlas: return
	atlas.region=Rect2(frame_origin+Vector2(frame.value*frame_size.x,0),frame_size)
	frame_note.text="Single source frame" if frames <= 1 else "Frame %d / %d · %.1f fps" % [int(frame.value)+1,frames,fps]
	if ground_marker.visible and character_picture.texture:
		var baseline := Vector2(picture.size.x * .5, picture.size.y * .8)
		var above: float = maxf(1, ground_anchor.y - character_bounds.position.y)
		var below: float = maxf(1, character_bounds.end.y - ground_anchor.y)
		var side: float = maxf(1, maxf(ground_anchor.x - character_bounds.position.x, character_bounds.end.x - ground_anchor.x))
		var factor: float = minf((baseline.y - 8) / above, (picture.size.y - baseline.y - 6) / below)
		factor = maxf(.01, minf(factor, (picture.size.x * .5 - 12) / side))
		character_picture.position = baseline - ground_anchor * factor; character_picture.size = frame_size * factor
		ground_marker.position = baseline - Vector2(6, 12)

func clip_bounds(texture: Texture2D) -> Rect2:
	var image: Image = texture.get_image()
	if image.is_compressed(): image.decompress()
	var result: Rect2 = Rect2()
	var found: bool = false
	for index in frames:
		var source := Rect2i(Vector2i(frame_origin + Vector2(index * frame_size.x, 0)), Vector2i(frame_size))
		source = source.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
		if not source.has_area(): continue
		var used: Rect2i = image.get_region(source).get_used_rect()
		if not used.has_area(): continue
		result = result.merge(Rect2(used)) if found else Rect2(used); found = true
	return result if found else Rect2(Vector2.ZERO, frame_size)

func unavailable_preview(reason: String) -> void:
	picture.texture = null; character_picture.texture = null; atlas = null; frames = 1
	ground_marker.hide(); play.hide(); play.set_pressed_no_signal(false); frame.hide()
	frame_note.show(); frame_note.text = reason

func preview_number(value: Variant, low: float, high: float, integral: bool = false) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= low and value <= high and (not integral or float(value) == roundf(value))

func valid_preview_view(view: Variant, definition: Dictionary, data: Dictionary) -> bool:
	if not view is Dictionary or not view.get("file") is String or view["file"].is_empty(): return false
	for key in ["frame_width", "frame_height", "frames"]:
		if view.has(key) and not preview_number(view[key], 1, 32768, true): return false
	if not preview_number(definition.get("fps", data.get("fps", 8)), .01, 1000): return false
	if not preview_number(data.get("frames", 1), 1, 32768, true): return false
	for key in ["first_frame", "frame_count"]:
		if definition.has(key) and not preview_number(definition[key], 0 if key == "first_frame" else 1, 32768, true): return false
	if definition.has("loop") and not definition["loop"] is bool: return false
	if view.has("region"):
		if not view["region"] is Array or view["region"].size() != 4: return false
		for value in view["region"]:
			if not preview_number(value, 0, 32768, true): return false
		if view["region"][2] <= 0 or view["region"][3] <= 0: return false
	for key in ["render_contact", "grid_contact", "actor_origin", "origin"]:
		if not view.has(key): continue
		if not view[key] is Array or view[key].size() != 2: return false
		for value in view[key]:
			if not preview_number(value, -100000, 100000): return false
	return true

func animation_text(asset: Dictionary) -> String:
	var data: Dictionary = asset["data"]
	var labels: Dictionary = {"static_mesh": "Static mesh", "posed_mesh": "Posed mesh", "rigged_without_clips": "Rigged mesh · no supplied animation clips", "animated_mesh": "Animated mesh", "static_sprite": "Static sprite", "directional_sprite": "Directional sprite", "animated_sprite": "Animated sprite"}
	var result: String = labels.get(data.get("animation_status", ""), "Animation status not reviewed")
	if not data.get("animation_note", "").is_empty(): result += " · " + data["animation_note"]
	if not data.get("supplied_clips", []).is_empty(): result += " · supplied clips: " + ", ".join(data["supplied_clips"])
	var actions: Dictionary = data["runtime_actions"] if data.get("runtime_actions") is Dictionary else {}
	var names: PackedStringArray = []
	for key in ["idle", "walk", "run", "sit", "wave"]:
		if actions.get(key) is Dictionary: names.append(key.capitalize() + (" (" + str(actions[key]["fallback"]) + " fallback)" if actions[key].has("fallback") else ""))
	result += "\nSupported actions: " + (", ".join(names) if not names.is_empty() else "none configured")
	return result

func refresh_actions(asset: Dictionary) -> void:
	preview_actions.clear(); preview_actions.add_item("Source frames"); preview_actions.set_item_metadata(0, {"kind":"base"})
	var data: Dictionary = asset["data"]
	var actions: Dictionary = data["runtime_actions"] if data.get("runtime_actions") is Dictionary else {}
	var animations: Dictionary = data["animations"] if data.get("animations") is Dictionary else {}
	for key in ["idle", "walk", "run", "sit", "wave"]:
		if not actions.get(key) is Dictionary: continue
		var config: Dictionary = actions[key]
		preview_actions.add_item(key.capitalize() + (" · walk fallback" if config.has("fallback") else ""))
		preview_actions.set_item_metadata(preview_actions.item_count - 1, {"kind":"semantic", "action":key})
	var source_names: Array = animations.keys(); source_names.sort()
	for key in source_names:
		if not animations[key] is Dictionary: continue
		if key in ["idle", "walk"]: continue
		preview_actions.add_item("Source · " + str(key).replace("_", " ").capitalize())
		preview_actions.set_item_metadata(preview_actions.item_count - 1, {"kind":"source", "action":key})
	action_row.visible = asset["mode"] == "2d" and (preview_actions.item_count > 1 or data.get("animation_status", "") == "animated_sprite")
	preview_actions.disabled = preview_actions.item_count == 1
	playback_speed.set_value_no_signal(1)

func preview_definition(asset: Dictionary) -> Dictionary:
	var data: Dictionary = asset["data"]
	var animations: Dictionary = data["animations"] if data.get("animations") is Dictionary else {}
	var actions: Dictionary = data["runtime_actions"] if data.get("runtime_actions") is Dictionary else {}
	var choice: Dictionary = preview_actions.get_item_metadata(preview_actions.selected) if preview_actions.item_count > 0 else {}
	if choice.get("kind") == "source": return animations[choice["action"]] if animations.get(choice["action"]) is Dictionary else {}
	if choice.get("kind") == "semantic":
		if not actions.get(choice["action"]) is Dictionary: return {}
		var config: Dictionary = actions[choice["action"]]
		var source: Dictionary = animations[config.get("clip", "")] if animations.get(config.get("clip", "")) is Dictionary else {}
		var result: Dictionary = source.duplicate()
		result.merge(config, true)
		if not result.get("directions") is Dictionary: result["directions"] = source.get("directions", data.get("directions", {}))
		return result
	return {"directions":data.get("directions", {}), "fps":data.get("fps", 8), "loop":true}

func refresh_preview_views() -> void:
	if selected_id.is_empty(): return
	var previous: String = views.get_item_text(views.selected) if views.item_count > 0 else ""
	views.clear()
	var definition: Dictionary = preview_definition(studio.library.assets[selected_id])
	if not definition.get("directions") is Dictionary or definition["directions"].is_empty(): unavailable_preview("This source clip has no usable direction metadata."); return
	for key in definition["directions"]: views.add_item(str(key))
	for index in views.item_count:
		if views.get_item_text(index) == previous: views.select(index); break
	load_view()

func choose_for_placement() -> void:
	if selected_id.is_empty(): return
	var id: String = selected_id
	var source_view: String = views.get_item_text(views.selected) if studio.library.assets[id]["mode"] == "2d" and views.item_count > 0 else ""
	dialog.hide(); studio.select_asset(id)
	if not source_view.is_empty() and studio.library.valid_direction(id, source_view):
		studio.direction = source_view; studio.refresh_controls()

func refresh_appearance() -> void:
	refreshing_appearance = true
	var asset: Dictionary = studio.library.assets[selected_id]
	var options: Array[Dictionary] = studio.library.families.options(asset, studio.library.assets)
	appearance_row.visible = options.size() > 1
	replace_member.visible = appearance_row.visible
	palette.clear(); lighting.clear()
	var palettes: Array[String] = []; var lights: Array[String] = []
	for member in options:
		var data: Dictionary = member["data"]
		if not palettes.has(data["palette_id"]): palettes.append(data["palette_id"])
		if not lights.has(data["lighting_id"]): lights.append(data["lighting_id"])
	palettes.sort(); lights.sort()
	for value in palettes:
		palette.add_item(studio.library.families.palette_name(value)); palette.set_item_metadata(palette.item_count - 1, value)
		if value == asset["data"].get("palette_id", ""): palette.select(palette.item_count - 1)
	for value in lights:
		lighting.add_item(value.capitalize()); lighting.set_item_metadata(lighting.item_count - 1, value)
		var available: bool = options.any(func(member: Dictionary) -> bool: return member["data"]["palette_id"] == asset["data"].get("palette_id", "") and member["data"]["lighting_id"] == value)
		lighting.set_item_disabled(lighting.item_count - 1, not available)
		lighting.get_popup().set_item_tooltip(lighting.item_count - 1, "Supplied baked lighting" if available else "This palette has no supplied member with this lighting")
		if value == asset["data"].get("lighting_id", ""): lighting.select(lighting.item_count - 1)
	var targets: Array = studio.selection_items()
	var reason: String = replacement_reason(targets, selected_id)
	replace_member.disabled = not reason.is_empty()
	replace_member.tooltip_text = reason if not reason.is_empty() else "Replace the selected family member; preserve compatible transforms, custom fields and owned rooms. Undo restores it."
	refreshing_appearance = false

func choose_appearance() -> void:
	if refreshing_appearance or selected_id.is_empty(): return
	var asset: Dictionary = studio.library.assets[selected_id]
	var options: Array[Dictionary] = studio.library.families.options(asset, studio.library.assets)
	var wanted_palette: String = palette.get_item_metadata(palette.selected)
	var wanted_lighting: String = lighting.get_item_metadata(lighting.selected)
	var matching: Array[Dictionary] = options.filter(func(member: Dictionary) -> bool: return member["data"]["palette_id"] == wanted_palette)
	if matching.is_empty(): return
	var chosen: Dictionary = matching[0]
	for member in matching:
		if member["data"]["lighting_id"] == wanted_lighting: chosen = member; break
	# If a newly chosen palette lacks this lighting, show the real selected
	# member and explain the adjustment; never fabricate a combination.
	var source_view: String = views.get_item_text(views.selected) if views.item_count > 0 else ""
	show_asset(chosen["id"])
	for index in views.item_count:
		if views.get_item_text(index) == source_view: views.select(index); load_view(); break
	if chosen["data"]["lighting_id"] != wanted_lighting: details.text += "\nThat palette has no " + wanted_lighting + " lighting; showing supplied " + chosen["data"]["lighting_id"] + " lighting."

func replacement_reason(targets: Array, destination: String) -> String:
	if targets.size() != 1: return "Select one editable placed member of this family first. Mixed selections are not replaced."
	var item: Dictionary = targets[0]
	if item["asset"] == destination: return "This member is already placed."
	var source: Dictionary = studio.library.assets[item["asset"]]
	var target: Dictionary = studio.library.assets[destination]
	var family: String = source["data"].get("family_id", "")
	if family.is_empty() or family != target["data"].get("family_id", ""): return "Select a placed member of this same design."
	if not studio.library.valid_direction(destination, item["direction"]): return "This member lacks the current source angle. Choose a compatible source angle first."
	if source["mode"] == "2d":
		var direction: String = item["direction"]
		if source["data"]["directions"][direction].get("footprint", []) != target["data"]["directions"][direction].get("footprint", []): return "These supplied members use different footprints. Place the alternate member separately to review its size."
	if not item.get("colors", []).is_empty() and not studio.appearance_tools.compatible({"asset": item["asset"], "colors": item["colors"]}, {"asset": destination}): return "Custom paint uses different source pixels or geometry. Preserve it by keeping this member, or remove the paint explicitly first."
	return ""

func apply_appearance() -> void:
	if selected_id.is_empty(): return
	studio.finish_edit(studio.canvas_pointer())
	var targets: Array = studio.selection_items()
	var reason: String = replacement_reason(targets, selected_id)
	if not reason.is_empty(): studio.status.text = reason; return
	var uid: String = targets[0]["uid"]
	var destination: String = selected_id
	var doc: RefCounted = studio.current()
	doc.checkpoint(); doc.object(uid)["asset"] = destination
	studio.changed()
	var economy_error: String = doc.economy_error
	doc.finish_checkpoint()
	if not economy_error.is_empty(): studio.status.text = economy_error; return
	studio.library.families.remember(studio.library.assets[destination])
	studio.status.text = "Selected appearance replaced. Undo restores the previous member."
	dialog.hide()

func tick(delta: float) -> void:
	compatibility.tick(delta)
	if health_tools:health_tools.tick(delta)
	if not dialog.visible or not atlas or not play.button_pressed or frames<=1: return
	if not is_finite(delta) or delta <= 0: return
	elapsed+=minf(delta, .25)*fps*playback_speed.value
	if elapsed>=1:
		var next: int = int(frame.value) + int(elapsed)
		frame.set_value_no_signal(posmod(next,frames) if playback_loop else mini(next, frames - 1))
		if not playback_loop and next >= frames - 1: play.set_pressed_no_signal(false)
		elapsed=fmod(elapsed,1)
		update_frame()

func load_model(asset: Dictionary) -> void:
	model_world=Node3D.new()
	viewport.add_child(model_world)
	var environment_node:=WorldEnvironment.new()
	var environment:=Environment.new()
	environment.background_mode=Environment.BG_COLOR
	environment.background_color=Color("182838")
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_energy=0.7
	environment_node.environment=environment
	model_world.add_child(environment_node)
	var light:=DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-45,-30,0)
	model_world.add_child(light)
	pivot=Node3D.new()
	model_world.add_child(pivot)
	var sample: Node3D=load(asset["path"]).instantiate()
	pivot.add_child(sample)
	var bounds: AABB=preload("res://scripts/model_bounds.gd").get_bounds(sample)
	sample.position-=bounds.get_center()
	var camera:=Camera3D.new()
	model_world.add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=maxf(0.5,bounds.size.length()*1.1)
	camera.position=Vector3(1,0.8,1).normalized()*maxf(5,bounds.size.length()*2)
	camera.look_at(Vector3.ZERO)
	camera.current=true
	details.text+="\nDimensions: %.2f × %.2f × %.2f source units (X / height / Z)" % [bounds.size.x,bounds.size.y,bounds.size.z]
	var profile: Dictionary = preload("res://scripts/builder/rendering_budget.gd").profile(asset)
	if not profile.is_empty():
		var low: Dictionary = profile["low"]
		var full: Dictionary = profile["full"]
		details.text += "\nApproximate mesh cost · %d regular triangles / %d Photo triangles." % [low["triangles"],full["triangles"]]
		details.text += "\nSource materials %d / %d · source images %d / %d." % [low["materials"],full["materials"],low["images"],full["images"]]
		details.text += "\nFrame cost depends on scale, visibility, shadows and the device."
	details.tooltip_text=details.text

