extends SceneTree

const Templates = preload("res://scripts/builder/templates.gd")
const Document = preload("res://scripts/builder/document.gd")
const Factory = preload("res://scripts/builder/asset_instance.gd")
const Exporter = preload("res://scripts/builder/exporter.gd")
var checks: int = 0
var failures: int = 0

func _init() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ", message)

func run() -> void:
	root.size = Vector2i(1480, 900)
	var studio: Control = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	for i in 5: await process_frame
	var directory: String = "res://output/mixed_test_" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var library: RefCounted = studio.library
	check(library.find("all", "All assets", "", [], false).size() == Catalog.get_registry()["items"].size() + 386 + Catalog.get_registry().get("models",{}).size(), "Base and added asset libraries are searchable together")
	for mode in ["2d", "3d"]:
		studio.documents[mode].data = Templates.make(mode, "blank")
		studio.switch_mode(mode)
		studio.worlds[mode].reset_camera("room")
		studio.surface_input.button_pressed = false
		studio.lanes_input.button_pressed = false
		var foreign_id: String = "3d:HanX_City/Cafe_Small" if mode == "2d" else "2d:Coffee_Shop"
		studio.asset_type.select(2 if mode == "2d" else 1)
		studio._command("asset_type", null)
		check(studio.library_mode() != mode and studio.cards.get_child_count() > 0, "Foreign assets appear in library: " + mode)
		studio.select_asset(foreign_id)
		check(studio.asset_id == foreign_id, "Foreign asset can be selected: " + mode)
		var count_before: int = studio.current().data["objects"].size()
		studio.drop_asset(foreign_id, studio.canvas.size / 2)
		check(studio.current().data["objects"].size() == count_before + 1 and studio.asset_id.is_empty(), "Foreign drop places once and clears cursor: " + mode)
		var item: Dictionary = studio.current().data["objects"].back()
		var node: Node = studio.worlds[mode].instances[item["uid"]]
		check(node is Node2D if mode == "2d" else node is StaticBody3D, "Foreign asset uses destination coordinates and collision: " + mode)
		check(Document.valid(studio.current().data, mode, library), "Mixed document validates: " + mode)
		await physics_frame
		await process_frame
		var at: Vector2 = studio.screen_bounds(item["uid"]).get_center()
		if mode == "2d":
			check(node.get_node("Sprite2D").texture is ViewportTexture, "2D object renders the actual 3D model")
			check(node.ground_polygon().size() == 4, "Model gets a 2D footprint collider")
		else:
			check(node.mesh.mesh is QuadMesh and not node.source.visible, "3D object displays a sprite without leaking its source into the canvas")
			check(node.collision.shape.size.y > 0.1, "Sprite has a walkable-world collision volume")
		check(studio.worlds[mode].pick(at) == item["uid"], "Foreign asset can be picked: " + mode)
		studio.selected_uid = item["uid"]
		studio.selected_uids.assign([item["uid"]])
		var old_direction: String = item["direction"]
		studio.rotate_by(1)
		check(item["direction"] != old_direction and node.direction == item["direction"], "Foreign asset rotates using original directions: " + mode)
		studio.duplicate_selection()
		check(studio.current().data["objects"].size() == count_before + 2, "Foreign object duplicates: " + mode)
		studio._command("undo", null)
		check(studio.current().data["objects"].size() == count_before + 1, "Foreign duplicate is undoable: " + mode)
		studio._command("redo", null)
		check(studio.current().data["objects"].size() == count_before + 2, "Foreign duplicate is redoable: " + mode)
		studio.select_asset(foreign_id)
		studio.worlds[mode].preview(foreign_id, [0, 0, 0], studio.direction, 1, true)
		studio.update_overlay(true)
		check(studio.overlay.footprint.size() == 4, "Foreign preview has placement guides: " + mode)
		if mode == "3d": check(studio.worlds[mode].ghost.mesh.material_override.albedo_texture != null, "Sprite placement preview retains its artwork")
		var original: Dictionary = studio.current().data.duplicate(true)
		var bad: Dictionary = original.duplicate(true)
		bad["objects"][0]["direction"] = "invalid"
		check(not Document.valid(bad, mode, library), "Mixed layout still rejects invalid directions: " + mode)
		var export_path: String = directory + "/mixed_" + mode + ".tscn"
		check(Exporter.save_scene(studio.worlds[mode], studio.current().data, library, export_path) == OK, "Mixed scene exports: " + mode)
		var exported: Node = load(export_path).instantiate()
		root.add_child(exported)
		await process_frame
		check(exported.get_node("Objects").get_child_count() == original["objects"].size(), "Export restores mixed objects: " + mode)
		var exported_node: Node = exported.get_node("Objects").get_child(0)
		check(exported_node.asset_path == library.assets[foreign_id]["path"] and exported_node.direction == original["objects"][0]["direction"], "Export preserves source and rotation: " + mode)
		exported.free()
		# Restore after loading an export temporarily changes the current 2D camera.
		studio.worlds["2d"].camera.enabled = mode == "2d"
	var ground_id: String = "2d:Road_Arrow_X"
	studio.switch_mode("3d")
	var tile: Dictionary = studio.current().add(ground_id, [4, 0, 0], "SW")
	var animated: Dictionary = studio.current().add("2d:Office_Worker", [-4, 0, 0], "SE")
	studio.changed()
	var tile_node: Node = studio.worlds["3d"].instances[tile["uid"]]
	check(tile_node.ground_tile and is_equal_approx(tile_node.mesh.rotation_degrees.x, -90), "Pixel ground lies flat in 3D")
	check(tile_node.mesh.material_override.get_shader_parameter("turns") == 1, "3D ground preserves isometric quarter turns")
	var animated_node: Node = studio.worlds["3d"].instances[animated["uid"]]
	var sprite: Sprite2D = animated_node.source.get_node("Sprite2D")
	sprite.frame = mini(1, sprite.hframes - 1)
	animated_node.update_visual()
	var displayed: Image = animated_node.material.albedo_texture.get_image()
	var expected_frame: Image = sprite.texture.get_image().get_region(Rect2i(Vector2i(sprite.frame_coords) * Vector2i(sprite.get_rect().size), Vector2i(sprite.get_rect().size)))
	check(displayed.get_size() == expected_frame.get_size() and displayed.get_data() == expected_frame.get_data(), "Sprite animation displays exactly the current frame's pixels")
	var save_path: String = directory + "/mixed.isocity.json"
	check(studio.write_project(save_path), "Mixed project saves")
	var saved: Dictionary = studio.session_data().duplicate(true)
	check(studio.load_project(save_path), "Mixed project reloads")
	check(JSON.parse_string(JSON.stringify(studio.session_data()["documents"])) == JSON.parse_string(JSON.stringify(saved["documents"])), "Both mixed layouts survive save/load")
	check(studio.asset_type.selected == 1, "Workspace remembers the asset-type filter")
	if "--capture" in OS.get_cmdline_user_args():
		for mode in ["2d", "3d"]:
			studio.switch_mode(mode)
			studio.clear_placement()
			studio.worlds[mode].reset_camera("room")
			for i in 8: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://output/mixed_" + mode + ".png")
	studio.free()
	print("MIXED ASSETS: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
