extends SceneTree
const OUTPUT="res://output/verification/asset_expansion/I04"
var studio: Control
func _initialize() -> void:call_deferred("run")
func capture(name: String) -> void:
	for frame in 12:await process_frame
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(OUTPUT+"/"+name+".png")!=OK:quit(1)
func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio)
	while not studio.enhancements_ready:await process_frame
	var ui: RefCounted=studio.consumer_shell;ui.dismiss_welcome()
	var fixtures: Array=JSON.parse_string(FileAccess.get_file_as_string("res://resources/catalog/reviewed_name_queries.json"))["queries"]
	for size in [Vector2i(1480,900),Vector2i(960,640)]:
		root.size=size;ui.set_active(true,false);ui.open_drawer("build");ui.group="Everything";ui.style_choice.select(1);ui.query.text="wooden barrel"
		for index in ui.pack_choice.item_count:
			if ui.pack_choice.get_item_text(index)=="MyPilesetProoject":ui.pack_choice.select(index)
		studio.asset_browser.set_content_scope(0);ui.refine.hide();ui.layout();ui.refresh_catalog()
		await capture("simple_names_"+str(size.x))
		ui.set_active(false,false);studio.asset_type.select(0);studio.populate_categories();studio.category.select(0);studio.pack_filter="isometricStrategy";studio.search.text="windmill";studio.refresh_library()
		await capture("precision_names_"+str(size.x))
		studio.asset_browser.show_asset(fixtures[1]["id"]);await capture("source_name_"+str(size.x));studio.asset_browser.dialog.hide()
		studio.asset_browser.show_asset("2d:t1");await capture("native_source_"+str(size.x));studio.asset_browser.dialog.hide()
	root.size=Vector2i(960,640);ui.set_active(true,false);ui.open_drawer("build");ui.query.text="wooden crate";ui.layout();ui.refresh_catalog()
	studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true});await capture("accessible_names_960")
	studio.asset_browser.show_asset(fixtures[3]["id"]);await capture("accessible_source_960");studio.asset_browser.dialog.hide()
	studio.free();await process_frame;await process_frame
	print("Captured reviewed names and original provenance in both interfaces and enlarged text");quit()
