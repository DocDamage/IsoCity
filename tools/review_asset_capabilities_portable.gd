extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	root.add_child(load(ProjectSettings.get_setting("application/run/main_scene")).instantiate())
	for frame in 60:await process_frame
	await RenderingServer.frame_post_draw
	var picture: Image=root.get_texture().get_image()
	if picture.is_empty() or picture.save_png("res://portable_capability_launch.png")!=OK:printerr("FAIL: portable rendered capture");quit(1);return
	print("Portable capability launch captured: ",RenderingServer.get_current_rendering_method());quit()
