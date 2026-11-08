extends SceneTree
const OUT="res://output/verification/asset_expansion/U16"
var studio: Control
var count: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func settle() -> void:
	for frame in 12:await process_frame
	await RenderingServer.frame_post_draw
func check(value: bool,message: String) -> void:
	if not value:failures+=1;printerr("FAIL: "+message)
func capture(name: String) -> void:
	await settle();count+=1
	if root.get_texture().get_image().save_png(OUT+"/"+name+".png")!=OK:failures+=1;printerr("FAIL: capture "+name)
func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio)
	while not studio.enhancements_ready:await process_frame
	var browser: RefCounted=studio.asset_browser;var tools: RefCounted=browser.semantic_search;var ui: RefCounted=studio.consumer_shell;ui.dismiss_welcome()
	for dimensions in [Vector2i(1480,900),Vector2i(960,640)]:
		root.size=dimensions;ui.set_active(true,false);ui.open_drawer("build");browser.clear_all_filters();ui.group="Everything";ui.query.text="chair school";tools.set_use("classroom");ui.refresh_catalog();await settle()
		if studio.cards.get_child_count()>0:ui.card_scroll.ensure_control_visible(studio.cards.get_child(0).caption)
		await capture("simple_search_"+str(dimensions.x))
		ui.refine.show();ui.layout();tools.simple_choice.grab_focus();await capture("simple_use_"+str(dimensions.x))
		check(root.get_visible_rect().encloses(tools.simple_choice.get_global_rect()),"Simple use selector fits the viewport")
		ui.refine.hide();browser.set_theme("space");ui.layout();await capture("simple_empty_"+str(dimensions.x))
		check(tools.simple_panel.visible and root.get_visible_rect().encloses(tools.simple_panel.get_global_rect()),"Simple empty-result explanation and actions fit")
		tools.simple_panel.get_node("Broaden").pressed.emit();await capture("simple_broadened_"+str(dimensions.x));ui.clear_filters.pressed.emit()
		browser.set_theme("");ui.set_active(false,false);studio.search.text="classroom seating";browser.filters_manual=true;browser.filters_expanded=false;browser.fit_filters();studio.refresh_library();await capture("precision_search_"+str(dimensions.x))
		browser.filters_expanded=true;browser.fit_filters();browser.filter_scroll.ensure_control_visible(tools.choice);await capture("precision_use_"+str(dimensions.x))
		browser.filters_expanded=false;browser.fit_filters();browser.set_theme("space");await capture("precision_empty_"+str(dimensions.x))
		check(tools.precision_panel.visible and root.get_visible_rect().encloses(tools.precision_panel.get_global_rect()),"Precision empty-result explanation and actions fit")
	root.size=Vector2i(960,640);ui.set_active(true,false);studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true});ui.open_drawer("build");ui.group="Everything";ui.query.text="school chair";tools.set_use("classroom");browser.set_theme("space");ui.layout();await capture("accessible_empty_960")
	check(root.get_visible_rect().encloses(tools.simple_panel.get_global_rect()) and ui.drawer.position.y>=ui.header_actions.get_global_rect().end.y,"Enlarged empty-result actions fit 960×640 below the header")
	tools.simple_panel.get_node("Broaden").pressed.emit();await capture("accessible_broadened_960")
	if studio.cards.get_child_count()>0:
		ui.card_scroll.ensure_control_visible(studio.cards.get_child(0).artwork);await capture("accessible_art_960")
	ui.refine.show();ui.layout();await settle();tools.simple_choice.grab_focus();ui.refine.ensure_control_visible(tools.simple_choice);await capture("accessible_refine_960")
	check(ui.refine.get_global_rect().encloses(tools.simple_choice.get_global_rect()) and ui.drawer.position.y>=ui.header_actions.get_global_rect().end.y,"Enlarged use filters scroll fully into view below the header")
	studio.free();await process_frame;await process_frame
	print("Rendered semantic search: %d captures, %d failures"%[count,failures]);quit(1 if failures else 0)
