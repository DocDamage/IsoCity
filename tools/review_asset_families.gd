extends SceneTree
const OUTPUT = "res://output/verification/asset_expansion/I02"
var studio: Control

func _initialize() -> void: call_deferred("run")

func settle() -> void:
	for frame in 12: await process_frame
	await RenderingServer.frame_post_draw

func capture(name: String) -> void:
	await settle()
	if root.get_texture().get_image().save_png(OUTPUT + "/" + name + ".png") != OK: printerr("Capture failed"); quit(1)

func run() -> void:
	studio = load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled = false; root.add_child(studio)
	while not studio.enhancements_ready: await process_frame
	var ui: RefCounted = studio.consumer_shell
	if ui == null: printerr("Run with --consumer-ui"); studio.free(); quit(1); return
	studio.switch_mode("2d"); ui.dismiss_welcome()
	for size in [Vector2i(1480, 900), Vector2i(960, 640)]:
		root.size = size; ui.set_active(true, false); ui.open_drawer("build")
		ui.group = "Everything"; ui.query.clear(); ui.style_choice.select(2)
		for index in ui.pack_choice.item_count:
			if ui.pack_choice.get_item_text(index) == "Water towers": ui.pack_choice.select(index)
		ui.refresh_catalog(); await capture("families_simple_" + str(size.x))
		var member: String = studio.library.families.representatives["supplemental/village/apothecary"]
		studio.asset_browser.show_asset(member); await capture("appearance_" + str(size.x)); studio.asset_browser.dialog.hide()
		ui.set_active(false, false); studio.asset_type.select(0); studio.populate_categories(); studio.category.select(0)
		studio.pack_filter = "Village buildings"; studio.search.clear(); studio.favorites_only.button_pressed = false
		studio.refresh_library(); await capture("families_precision_" + str(size.x))
	studio.free(); await process_frame; await process_frame
	print("Reviewed family browser and appearance selectors at desktop and minimum sizes"); quit()
