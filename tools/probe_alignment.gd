extends SceneTree

func _init() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1480, 900)
	var studio: Control = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	for i in 5: await process_frame
	studio.load_project("res://output/alignment_preview.isocity.json" if "--preview" in OS.get_cmdline_user_args() else preload("res://scripts/builder/project_store.gd").resume_autosave())
	var world: Node2D = studio.worlds["2d"]
	for cell in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		print("CELL ", cell, " rendered center ", world.ground.map_to_local(cell) + world.ground.position, " footprint top ", IsoMath.tile_to_world(cell))
	var info: Dictionary = world.tile_lookup["2d:Road_Center_Dash_X"]
	var source: TileSetAtlasSource = world.ground.tile_set.get_source(info["source"])
	print("TILE ORIGIN ", source.get_tile_data(info["atlas"], 0).texture_origin)
	for item in studio.documents["2d"].data["objects"]:
		if not item["asset"].begins_with("3d:") or not "Car_" in item["asset"]: continue
		var instance: Node = world.instances[item["uid"]]
		var bounds: AABB = instance.model.transform * preload("res://scripts/model_bounds.gd").get_bounds(instance.model)
		var center: Vector3 = bounds.get_center()
		center.y = bounds.position.y
		var pixel: Vector2 = instance.camera.unproject_position(center)
		var sprite: Sprite2D = instance.get_node("Sprite2D")
		var projected: Vector2 = sprite.to_global(sprite.get_rect().position + pixel)
		print("CAR ROOT ", item["position"], " rendered ground center ", projected, " bounds ", bounds)
	if "--capture" in OS.get_cmdline_user_args():
		for i in 8: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://output/alignment_preview.png" if "--preview" in OS.get_cmdline_user_args() else "res://output/alignment_current.png")
	studio.free()
	quit()
