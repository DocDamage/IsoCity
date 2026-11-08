extends RefCounted
var studio: Control
var use_filter: String=""
var choice: OptionButton
var simple_choice: OptionButton
var precision_panel: VBoxContainer
var simple_panel: VBoxContainer
var panels: Array[VBoxContainer]=[]
var saved_filters: Dictionary={}
var settings_path: String="user://studio_asset_use.json"
var busy: bool=false

func _init(host: Control,filters: Node,column: Node,after: Node) -> void:
	studio=host
	if studio.storage_enabled:restore()
	choice=make_choice(filters)
	precision_panel=make_panel(column);column.move_child(precision_panel,after.get_index()+1)

func valid_use(value: Variant) -> bool:return value is String and (value in ["","unreviewed"] or studio.library.search_index.groups.has(value))

func restore() -> void:
	var saved: Variant=studio.Store.read_json(settings_path,{})
	use_filter=saved["use"] if saved is Dictionary and valid_use(saved.get("use")) else ""

func make_choice(parent: Node) -> OptionButton:
	var result:=OptionButton.new();result.fit_to_longest_item=false;result.clip_text=true
	result.add_item("Use · All uses");result.set_item_metadata(0,"")
	var keys: Array=studio.library.search_index.groups.keys();keys.sort_custom(func(a: String,b: String):return studio.library.search_index.groups[a].naturalnocasecmp_to(studio.library.search_index.groups[b])<0)
	for key in keys:
		result.add_item("Use · "+studio.library.search_index.groups[key]);result.set_item_metadata(result.item_count-1,key)
	result.add_item("Use · Unreviewed");result.set_item_metadata(result.item_count-1,"unreviewed")
	result.tooltip_text="Reviewed artwork and furnishing tasks. Use groups never grant interactions or simulation behavior. Other assets remain under All uses or Unreviewed."
	parent.add_child(result);result.item_selected.connect(func(index: int):set_use(result.get_item_metadata(index)))
	select_choice(result);return result

func select_choice(control: OptionButton) -> void:
	for index in control.item_count:
		if control.get_item_metadata(index)==use_filter:control.select(index);return

func set_use(value: String,persist: bool=true) -> void:
	use_filter=value if valid_use(value) else ""
	select_choice(choice)
	if simple_choice:select_choice(simple_choice)
	if persist and studio.storage_enabled and not studio.Store.write_json(settings_path,{"use":use_filter}):studio.status.text="Use group applied for this session; preferences could not be saved."
	studio.page=0;studio.refresh_library()

func make_panel(parent: Node) -> VBoxContainer:
	var box:=VBoxContainer.new();parent.add_child(box);box.hide();panels.append(box)
	var note:=Label.new();note.name="Explanation";note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;note.max_lines_visible=3;note.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;note.add_theme_font_size_override("font_size",12);box.add_child(note)
	var action:=Button.new();action.name="Broaden";action.text="Search all assets";box.add_child(action);action.pressed.connect(broaden)
	return box

func clear_or_restore() -> void:
	if not saved_filters.is_empty():restore_filters()
	else:studio.asset_browser.clear_all_filters()

func add_simple(filters: Node,parent: Node,after: Node) -> void:
	simple_choice=make_choice(filters);simple_choice.custom_minimum_size=Vector2(210,40)
	simple_panel=make_panel(parent);parent.move_child(simple_panel,after.get_index()+1)

func matches(asset: Dictionary) -> bool:return studio.library.search_index.use_matches(asset["id"],use_filter)

func description(id: String) -> String:
	var index: RefCounted=studio.library.search_index;var groups: Array=index.use_groups(id)
	if groups.is_empty():return "Intended use has not been reviewed; names, source files and existing aliases remain searchable."
	var names: Array=[]
	for key in groups:names.append(index.groups[key])
	return "Reviewed use: "+", ".join(names)+". Search tasks: "+", ".join(index.semantics[id].get("tasks",[]))+". Artwork grouping does not grant behavior."

func snapshot() -> Dictionary:
	var browser: RefCounted=studio.asset_browser;var ui: RefCounted=studio.consumer_shell
	return {"world":studio.mode,"type":studio.asset_type.selected,"category":studio.category.get_item_text(maxi(0,studio.category.selected)),"pack":studio.pack_filter,"theme":browser.theme_filter,"content":browser.content_scope,"favorite":studio.favorites_only.button_pressed,"use":use_filter,"task_collection":browser.task_collections.state() if browser.task_collections else {},"recent":browser.recents.only if browser.recents else false,"collection":browser.collections.selection() if browser.collections else "","page":studio.page,"query":ui.query.text if ui and ui.active else studio.search.text,"simple_style":ui.style_choice.selected if ui else 1,"simple_pack":ui.pack_choice.selected if ui else 0,"group":ui.group if ui else "Everything"}

func apply_filters(value: Dictionary) -> void:
	busy=true
	var browser: RefCounted=studio.asset_browser;var ui: RefCounted=studio.consumer_shell
	studio.asset_type.select(value["type"]);studio.populate_categories();studio.category.select(0)
	for index in studio.category.item_count:
		if studio.category.get_item_text(index)==value["category"]:studio.category.select(index)
	studio.pack_filter=value["pack"];browser.theme_filter=value["theme"];browser.content_scope=value["content"];browser.content_choice.select(browser.content_scope)
	studio.favorites_only.set_pressed_no_signal(value["favorite"]);use_filter=value["use"];select_choice(choice)
	if browser.task_collections:browser.task_collections.restore(value.get("task_collection",{}))
	if browser.recents:browser.recents.only=value.get("recent",false)
	if browser.collections:browser.collections.temporary_filter(value.get("collection",""))
	if ui:
		ui.style_choice.select(value["simple_style"]);ui.pack_choice.select(value["simple_pack"]);ui.group=value["group"];ui.content_choice.select(browser.content_scope);select_choice(simple_choice)
		for name in ui.categories:ui.categories[name].set_pressed_no_signal(name==ui.group)
		ui.favorite.set_pressed_no_signal(studio.favorites_only.button_pressed)
	studio.page=value["page"];busy=false;studio.refresh_library()
	if ui and ui.active:ui.layout()

func broaden() -> void:
	if saved_filters.is_empty():saved_filters=snapshot()
	var broad: Dictionary=snapshot()
	broad.merge({"type":0,"category":"All assets","pack":"","theme":"","content":2,"favorite":false,"use":"","task_collection":{},"recent":false,"collection":"","page":0,"simple_style":1,"simple_pack":0,"group":"Everything"},true)
	apply_filters(broad)
	studio.status.text="Searching all available assets with the same words. Restore filters returns to the previous view."

func restore_filters() -> void:
	if saved_filters.is_empty():return
	var saved: Dictionary=saved_filters;saved_filters={}
	if saved["world"]!=studio.mode:return
	var ui: RefCounted=studio.consumer_shell
	if saved["query"]!=(ui.query.text if ui and ui.active else studio.search.text):saved["page"]=0
	apply_filters(saved)

func refresh() -> void:
	if busy:return
	select_choice(choice)
	if simple_choice:select_choice(simple_choice)
	if not saved_filters.is_empty() and saved_filters["world"]!=studio.mode:saved_filters={}
	var ui: RefCounted=studio.consumer_shell;var simple: bool=ui!=null and ui.active
	var empty: bool=studio.cards.get_child_count()==0
	precision_panel.visible=not simple and empty
	if simple_panel:simple_panel.visible=simple and empty
	var has_saved: bool=not saved_filters.is_empty()
	studio.asset_browser.clear_filters.text="Restore" if has_saved else "Clear"
	studio.asset_browser.clear_filters.tooltip_text="Restore the previous filters; keep the current search words." if has_saved else "Clear all filters and search."
	if ui:
		ui.clear_filters.text="Restore filters" if has_saved else "Clear filters"
		ui.clear_filters.tooltip_text=studio.asset_browser.clear_filters.tooltip_text
		studio.asset_browser.compatibility.simple_choice.visible=not empty
		studio.asset_browser.compatibility.simple_note.visible=not empty
	var text: String="Broader search · your previous filters are saved."
	var broader_count: int=0
	if empty:
		var state: Dictionary=snapshot();var filters: Array=[]
		if not state["theme"].is_empty():filters.append("theme "+studio.library.themes.label(state["theme"]))
		if not use_filter.is_empty():filters.append("use "+("Unreviewed" if use_filter=="unreviewed" else studio.library.search_index.groups[use_filter]))
		if studio.asset_browser.task_collections and not studio.asset_browser.task_collections.task.is_empty():filters.append("task "+studio.library.tasks.tasks[studio.asset_browser.task_collections.task]["name"])
		if state["favorite"]:filters.append("favorites")
		if studio.asset_browser.recents.active():filters.append("recent placements")
		if state["content"]<2:filters.append(preload("res://scripts/builder/asset_content.gd").LABELS[state["content"]])
		if simple:
			if ui.group!="Everything":filters.append("group "+ui.group)
			if ui.style_choice.selected in [2,3] or (ui.style_choice.selected==0 and state["query"].strip_edges().is_empty()):filters.append(ui.style_choice.get_item_text(ui.style_choice.selected))
			if ui.pack_choice.selected>0:filters.append(ui.pack_choice.get_item_text(ui.pack_choice.selected))
		else:
			if studio.asset_type.selected>0:filters.append(studio.asset_type.get_item_text(studio.asset_type.selected))
			if state["category"]!="All assets":filters.append(state["category"])
			if not state["pack"].is_empty():filters.append(state["pack"])
		broader_count=studio.library.find("all","All assets",state["query"],[],false).size() if not filters.is_empty() else 0
		text="No matches"+(" for “"+state["query"]+"”" if not state["query"].is_empty() else "")+". "+("Filters: "+", ".join(filters)+". " if not filters.is_empty() else "")
		text+=("%d matches across all assets; broaden without changing your words."%broader_count) if broader_count>0 else "Try fewer words, another alias, or the source filename. Reviewed use tags cover part of the library."
	for panel in panels:
		var note: Label=panel.get_node("Explanation");note.text=text;note.tooltip_text=text;note.visible=empty
		panel.get_node("Broaden").visible=empty and broader_count>0
	for card in studio.cards.get_children():
		var hint: String="\n"+description(card.asset_id)
		if not card.tooltip_text.ends_with(hint):card.tooltip_text+=hint
