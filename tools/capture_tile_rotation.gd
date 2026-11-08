extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1480, 900)
	var studio: Control = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	for frame in 5:
		await process_frame
	studio.documents["2d"].data = {"title": "Quarter-turn tile check", "mode": "2d", "objects": [], "tiles": [], "night": false}
	var names: Array[String] = ["2d:Road_Arrow_X", "2d:Floor_Wood_Oak", "2d:Water"]
	for row in 3:
		for column in 4:
			studio.documents["2d"].data["tiles"].append({"cell": [column * 3 - 4, row * 3 - 2], "asset": names[row], "direction": ["SE", "SW", "NW", "NE"][column]})
	studio.worlds["2d"].apply(studio.documents["2d"].data)
	studio.worlds["2d"].camera.position = Vector2(-8, 12)
	studio.worlds["2d"].camera.zoom = Vector2(3, 3)
	studio.select_asset("2d:Road_Arrow_X")
	studio.rotate_selection()
	for frame in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://output/tile_rotations.png")
	studio.free()
	quit()
