extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1480, 900)
	var studio: Control = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	for index in 8:
		await process_frame
	studio.worlds["2d"].reset_camera()
	print("2D visible ", studio.worlds["2d"].visible, " camera ", studio.worlds["2d"].camera.enabled, " viewport ", studio.viewport.size, " size ", studio.canvas.size, " transform ", studio.viewport.canvas_transform, " object ", studio.worlds["2d"].instances.values()[0].position)
	for dimension in ["2d", "3d"]:
		studio.switch_mode(dimension)
		if dimension == "2d":
			for index in studio.category.item_count:
				if studio.category.get_item_text(index) == "Buildings":
					studio.category.select(index)
		else:
			for index in studio.category.item_count:
				if studio.category.get_item_text(index) == "City":
					studio.category.select(index)
		studio.refresh_library()
		for index in 5:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://output/studio_" + dimension + ".png")
		studio.template_choice.select(1)
		studio._command("template", null)
		for index in 5:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://output/studio_" + dimension + "_room.png")
	studio.free()
	quit()
