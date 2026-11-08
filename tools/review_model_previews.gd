extends SceneTree
# Reproducible I05 visual evidence; never loads or saves user projects/settings.
const OUTPUT = "res://output/verification/asset_expansion/I05"
var studio: Control

func _initialize() -> void: call_deferred("run")

func settle() -> void:
	for frame in 12: await process_frame
	await RenderingServer.frame_post_draw

func capture(name: String) -> void:
	await settle()
	var result: Error = root.get_texture().get_image().save_png(OUTPUT + "/" + name + ".png")
	if result != OK: printerr("Capture failed: ", name); quit(1)

func run() -> void:
	studio = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false; root.add_child(studio)
	while not studio.enhancements_ready: await process_frame
	studio.switch_mode("3d"); await settle()
	var ui: RefCounted = studio.consumer_shell
	if ui == null: printerr("Run with --consumer-ui"); studio.free(); quit(1); return
	ui.dismiss_welcome()
	for size in [Vector2i(1480, 900), Vector2i(960, 640)]:
		root.size = size
		ui.set_active(true, false); ui.open_drawer("build")
		ui.group = "Everything"; ui.query.text = "Spaceships II"; ui.refresh_catalog()
		await settle()
		if studio.cards.get_child_count() == 0: printerr("Ship drawer is empty"); studio.free(); quit(1); return
		await capture("simple_" + str(size.x))
		ui.set_active(false, false)
		studio.asset_type.select(0); studio.populate_categories(); studio.category.select(0)
		studio.pack_filter = "Spaceships II"; studio.search.clear(); studio.favorites_only.button_pressed = false
		studio.refresh_library(); await settle()
		if studio.cards.get_child_count() == 0: printerr("Ship library is empty"); studio.free(); quit(1); return
		await capture("precision_" + str(size.x))
	studio.free(); await process_frame; await process_frame
	print("Captured simple and precision ship browsing at desktop and 960x640")
	quit()
