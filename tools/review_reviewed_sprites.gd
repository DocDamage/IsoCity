extends SceneTree
const OUTPUT="res://output/verification/asset_expansion/I03"
var studio: Control
func _initialize() -> void:call_deferred("run")
func settle() -> void:
	for frame in 12:await process_frame
	await RenderingServer.frame_post_draw
func capture(name: String) -> void:
	await settle()
	var error: Error=root.get_texture().get_image().save_png(OUTPUT+"/"+name+".png")
	if error!=OK:printerr("Capture failed: ",name);quit(1)
func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio)
	while not studio.enhancements_ready:await process_frame
	if studio.consumer_shell==null:printerr("Run with --consumer-ui");quit(1);return
	var ui: RefCounted=studio.consumer_shell;var browser: RefCounted=studio.asset_browser
	ui.dismiss_welcome();studio.switch_mode("2d")
	for size in [Vector2i(1480,900),Vector2i(960,640)]:
		root.size=size;ui.set_active(true,false);ui.open_drawer("build");ui.group="Everything";ui.style_choice.select(1);ui.query.clear()
		for index in ui.pack_choice.item_count:
			if ui.pack_choice.get_item_text(index)=="MyArt":ui.pack_choice.select(index)
		browser.set_content_scope(0);ui.refine.show();ui.layout();ui.refresh_catalog()
		await capture("simple_filters_"+str(size.x))
		ui.refine.hide();ui.layout();ui.refresh_catalog()
		await capture("simple_objects_"+str(size.x))
		browser.set_content_scope(2);await capture("simple_all_"+str(size.x))
		ui.set_active(false,false);studio.asset_type.select(0);studio.populate_categories();studio.category.select(0);studio.pack_filter="MyArt";studio.search.clear();studio.favorites_only.button_pressed=false
		browser.set_content_scope(0);studio.refresh_library();await capture("precision_objects_"+str(size.x))
		browser.show_asset("2d:Added_MyArt_MyArt_things_3_1_2e92f7dc");await capture("legacy_parts_"+str(size.x));browser.dialog.hide()
		browser.show_asset("2d:Reviewed_rodwan_flag_0");browser.play.set_pressed_no_signal(false);await capture("flag_"+str(size.x));browser.dialog.hide()
		browser.show_asset("2d:Reviewed_village_coffee_door");browser.views.select(1);browser.views.item_selected.emit(1);await capture("door_state_"+str(size.x));browser.dialog.hide()
	root.size=Vector2i(1480,900);ui.set_active(true,false);ui.close_overlays()
	for mode in ["2d","3d"]:
		studio.switch_mode(mode);studio.current().data=preload("res://scripts/builder/templates.gd").make(mode,"blank")
		var ids: Array=["2d:Reviewed_myart_campfire","2d:Reviewed_myart_leafy_tree_cutout","2d:Reviewed_sailing_ship_turntable","2d:Reviewed_village_bench_0","2d:Reviewed_rodwan_flag_0"]
		for index in ids.size():
			var id: String=ids[index];studio.current().add(id,[(index-2)*110,0,0] if mode=="2d" else [(index-2)*3,0,0],str(studio.library.directions(id)[0]),studio.library.assets[id]["data"].get("default_scale",1))
		studio.changed();await settle()
		if mode=="2d":studio.worlds[mode].camera.position=Vector2.ZERO;studio.worlds[mode].camera.zoom=Vector2.ONE*1.6
		else:studio.worlds[mode].target=Vector3(0,1,0);studio.worlds[mode].distance=14;studio.worlds[mode].update_camera()
		await capture("placed_parts_"+mode)
	root.size=Vector2i(960,640);studio.switch_mode("2d");ui.open_drawer("build");ui.group="Everything";ui.style_choice.select(1);ui.query.clear()
	studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true})
	ui.refine.show();ui.layout();ui.content_choice.grab_focus();await capture("content_accessible_960")
	var inside: Rect2=ui.content_choice.get_global_rect()
	if not ui.drawer.get_global_rect().encloses(inside):printerr("Content filter escaped the compact drawer");quit(1);return
	ui.refine.hide();ui.layout();await capture("objects_accessible_960")
	studio.free();await process_frame;await process_frame
	print("Captured reviewed/legacy browsing, source states, flag animation and mixed-world placements");quit()
