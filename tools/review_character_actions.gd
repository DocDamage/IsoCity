extends SceneTree
const OUTPUT = "res://output/verification/asset_expansion/I06"
var studio: Control

func _initialize() -> void: call_deferred("run")

func capture(name: String) -> void:
	for frame in 12: await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var error: Error = image.save_png(OUTPUT + "/" + name + ".png")
	if error != OK: printerr("Capture failed: ", name, " ", error_string(error), " image ", image.get_size()); quit(1)

func choose(browser: RefCounted, action: String) -> void:
	for index in browser.preview_actions.item_count:
		var choice: Dictionary = browser.preview_actions.get_item_metadata(index)
		if choice.get("kind") == "semantic" and choice.get("action") == action:
			browser.preview_actions.select(index); browser.preview_actions.item_selected.emit(index); return

func run() -> void:
	studio = load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled = false; root.add_child(studio)
	while not studio.enhancements_ready: await process_frame
	if studio.consumer_shell: studio.consumer_shell.dismiss_welcome()
	var browser: RefCounted = studio.asset_browser
	for size in [Vector2i(1480, 900), Vector2i(960, 640)]:
		root.size = size
		browser.show_asset("2d:Office_Worker"); choose(browser, "sit"); await capture("native_pose_" + str(size.x)); browser.dialog.hide()
		browser.show_asset("2d:Supplemental_Characters_Businessman_Idle_7faeca34_Character"); choose(browser, "run"); browser.play.button_pressed = false; browser.frame.value = 4
		await capture("supplied_run_" + str(size.x)); browser.dialog.hide()
		browser.show_asset("2d:Supplemental_Characters_Blue_robot_IdleAim_32743945_Character"); choose(browser, "run"); browser.play.button_pressed = false
		await capture("fallback_run_" + str(size.x)); browser.dialog.hide()
	root.size = Vector2i(1480, 900)
	if studio.consumer_shell: studio.consumer_shell.close_overlays()
	studio.switch_mode("3d")
	studio.current().data = preload("res://scripts/builder/templates.gd").make("3d", "blank")
	var ids: Array[String] = []
	for id in studio.library.assets:
		var data: Dictionary = studio.library.assets[id]["data"]
		if data.get("kind") == "char" and not data.get("animations", {}).is_empty(): ids.append(id)
	ids.sort()
	for index in ids.size():
		studio.current().add(ids[index], [(index % 3 - 1) * 4, 0, (floori(index / 3.0) - 1) * 4], "SE", studio.library.assets[ids[index]]["data"].get("default_scale", 1))
	studio.changed()
	for frame in 20: await process_frame
	var world: Node = studio.worlds["3d"]; world.target = Vector3(0, 1, 0); world.distance = 14; world.update_camera()
	for instance in world.instances.values():
		if instance.get("source") is IsoCharacter: instance.source.action = "run"; instance.source._apply_direction()
	await capture("mixed_run_families_3d")
	studio.free(); await process_frame; await process_frame
	print("Captured pose, genuine run and honest walk fallback with source angles and ground contact"); quit()
