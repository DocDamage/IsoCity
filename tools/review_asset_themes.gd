extends SceneTree
const OUT="res://output/verification/asset_expansion/U01"
var studio: Control
func _initialize() -> void:call_deferred("run")
func settle() -> void:
	for frame in 12:await process_frame
	await RenderingServer.frame_post_draw
func capture(name: String) -> void:
	await settle()
	if root.get_texture().get_image().save_png(OUT+"/"+name+".png")!=OK:printerr("Capture failed: "+name);quit(1)
func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio)
	while not studio.enhancements_ready:await process_frame
	var browser: RefCounted=studio.asset_browser;var ui: RefCounted=studio.consumer_shell;ui.dismiss_welcome()
	for size in [Vector2i(1480,900),Vector2i(960,640)]:
		root.size=size;ui.set_active(true,false);ui.open_drawer("build");browser.clear_all_filters();browser.set_content_scope(0)
		ui.theme_choice.show_popup();await capture("themes_menu_"+str(size.x));ui.theme_choice.get_popup().hide()
		browser.set_theme("industrial");ui.query.text="industrial";ui.refresh_catalog();await capture("simple_theme_"+str(size.x))
		if studio.cards.get_child_count()>0:
			browser.show_asset(studio.cards.get_child(0).asset_id);await capture("theme_details_"+str(size.x));browser.dialog.hide()
		ui.query.clear();browser.set_theme("unclassified");ui.refresh_catalog();await capture("unclassified_"+str(size.x))
		ui.set_active(false,false);studio.search.clear();studio.pack_filter="";browser.set_theme("industrial");browser.filters_manual=true;browser.filters_expanded=true;browser.fit_filters()
		await capture("precision_theme_"+str(size.x))
		if not root.get_visible_rect().encloses(browser.clear_filters.get_global_rect()):printerr("Precision Clear filters escaped viewport");quit(1);return
		browser.filters_expanded=false;browser.fit_filters();await capture("precision_theme_results_"+str(size.x))
	root.size=Vector2i(960,640);ui.set_active(true,false);ui.open_drawer("build");ui.query.clear();browser.set_theme("village")
	studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true});ui.layout();await capture("accessible_themes_960")
	if not root.get_visible_rect().encloses(ui.drawer.get_global_rect()) or not ui.drawer.get_global_rect().encloses(ui.clear_filters.get_global_rect()) or ui.clear_filters.get_global_rect().intersects(ui.theme_choice.get_global_rect()):printerr("Accessible drawer or Clear filters is clipped or overlapping");quit(1);return
	ui.theme_choice.show_popup();await capture("accessible_themes_menu_960");ui.theme_choice.get_popup().hide()
	studio.free();await process_frame;await process_frame
	print("Captured theme menus, source explanations, unclassified content and both layouts with enlarged text");quit()
