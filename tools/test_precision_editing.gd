extends SceneTree

const Templates = preload("res://scripts/builder/templates.gd")
const Parts = preload("res://scripts/builder/part_colors.gd")
const Rotation = preload("res://scripts/builder/rotation.gd")
const Bounds = preload("res://scripts/model_bounds.gd")
const Exporter = preload("res://scripts/builder/exporter.gd")
const Document = preload("res://scripts/builder/document.gd")
var checks: int = 0
var failures: int = 0
var studio: Control
var directory: String

func _init() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ", message)

func choose(item: Dictionary) -> void:
	studio.selected_uid = item["uid"]
	studio.selected_uids.assign([item["uid"]])
	studio.selected_cell = null
	studio.refresh_controls()

func run() -> void:
	root.size = Vector2i(1480, 900)
	studio = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	for i in 5: await process_frame
	directory = "res://output/precision_test_" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	for world_mode in ["2d", "3d"]:
		studio.documents[world_mode].data = Templates.make(world_mode, "blank")
		studio.switch_mode(world_mode)
		studio.changed()
		studio.worlds[world_mode].reset_camera("room")
		await rotation_checks(world_mode)
		await color_checks(world_mode)
	await tile_checks()
	lane_checks()
	var path: String = directory + "/precision.isocity.json"
	check(studio.write_project(path) and studio.load_project(path), "Precision edits save and reopen")
	for world_mode in ["2d", "3d"]: check(Document.valid(studio.documents[world_mode].data, world_mode, studio.library), "New fields validate in saved layout: " + world_mode)
	var bad: Dictionary = studio.current().data.duplicate(true)
	bad["objects"][0]["tilt"] = [NAN, 1]
	check(not Document.valid(bad, studio.mode, studio.library), "Nonfinite tilt is rejected")
	bad = studio.current().data.duplicate(true)
	bad["objects"][0]["colors"] = [{"kind": "pixels", "texture": "x", "pixels": [-1], "color": [1, 0, 0, 1]}]
	check(not Document.valid(bad, studio.mode, studio.library), "Malformed color masks are rejected")
	if "--capture" in OS.get_cmdline_user_args():
		for world_mode in ["2d", "3d"]:
			studio.switch_mode(world_mode)
			studio.worlds[world_mode].reset_camera("room")
			for i in 8: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://output/precision_" + world_mode + ".png")
	studio.free()
	print("PRECISION EDITING: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func rotation_checks(world_mode: String) -> void:
	var item: Dictionary = studio.current().add("3d:HanX_GasStation/Car_Coupe", [0, 0, 0], "0", 0.5)
	studio.changed()
	choose(item)
	studio.angle_input.value = 37.5
	studio.pitch_input.value = 21
	studio.roll_input.value = -13
	check(item["direction"] == "37.5" and item.get("tilt") == [21.0, -13.0], "Angle, pitch and roll fields edit the selected model: " + world_mode)
	var node: Node = studio.worlds[world_mode].instances[item["uid"]]
	var model: Node3D = node.model if world_mode == "2d" else node
	check(model.rotation_degrees.is_equal_approx(Vector3(21, 37.5, -13)), "Actual model rotates on all axes: " + world_mode)
	studio.rotation_step.value = 15
	studio.rotate_by(1)
	check(item["direction"] == "52.5", "Rotate adds the requested fine step: " + world_mode)
	studio.rotate_by(-1)
	check(item["direction"] == "37.5", "Counterclockwise subtracts the fine step: " + world_mode)
	studio._command("undo", null)
	check(studio.current().object(item["uid"])["direction"] == "52.5", "Fine rotation is undoable: " + world_mode)
	studio._command("redo", null)
	choose(studio.current().object(item["uid"]))
	studio.duplicate_selection()
	var copy: Dictionary = studio.selection_items()[0]
	check(copy.get("tilt") == [21.0, -13.0] and copy["direction"] == "37.5", "Duplicate preserves all rotation axes: " + world_mode)
	studio.rotate_by(0, true)
	check(copy["direction"] == "0" and not copy.has("tilt"), "Reset clears heading, pitch and roll: " + world_mode)
	choose(studio.current().object(item["uid"]))
	studio.angle_input.value = 359
	studio.rotate_by(1)
	check(is_equal_approx(float(studio.current().object(item["uid"])["direction"]), 14), "Rotation wraps cleanly through 360 degrees: " + world_mode)
	studio.angle_input.value = 37.5
	var export_path: String = directory + "/rotation_" + world_mode + ".tscn"
	check(Exporter.save_scene(studio.worlds[world_mode], studio.current().data, studio.library, export_path) == OK, "Full rotation exports: " + world_mode)
	var exported: Node = load(export_path).instantiate()
	root.add_child(exported)
	await process_frame
	var exported_node: Node = exported.get_node("Objects").get_child(0)
	var exported_model: Node3D = exported_node.model if world_mode == "2d" else exported_node
	check(exported_model.rotation_degrees.is_equal_approx(Vector3(21, 37.5, -13)), "Export restores all rotation axes: " + world_mode)
	exported.free()
	studio.worlds["2d"].camera.enabled = world_mode == "2d"
	studio.rotation_step.value = 90

func color_checks(world_mode: String) -> void:
	var data: Dictionary = studio.current().data
	var model_item: Dictionary = data["objects"][0]
	var instance: Node = studio.worlds[world_mode].instances[model_item["uid"]]
	var model: Node3D = Parts.model_root(instance)
	var mesh: MeshInstance3D = model.find_children("*", "MeshInstance3D", true, false)[0]
	var path: String = str(model.get_path_to(mesh))
	var original: Mesh = Parts.original_mesh(mesh)
	var world_center: Vector3 = mesh.global_transform * original.get_aabb().get_center()
	var ray_hit: Dictionary = Parts.ray_pick(model, world_center + Vector3.UP * 30, Vector3.DOWN)
	check(not ray_hit.is_empty(), "Actual triangle ray picking finds the model: " + world_mode)
	var hit: Dictionary = {"mesh": path, "surface": 0, "face": 0}
	var edit: Dictionary = Parts.connected_faces(model, hit, 0.08, false)
	var single: Dictionary = Parts.connected_faces(model, hit, 0.08, true)
	check(single["faces"].size() == 1, "Single-face selection is exact: " + world_mode)
	check(edit["faces"].size() >= 1 and edit["faces"].size() < Parts.indices_for(original.surface_get_arrays(0)).size() / 3, "Connected selection isolates part of a model: " + world_mode)
	edit["color"] = [0.1, 0.2, 0.95, 1.0]
	model_item["colors"] = [edit]
	studio.changed()
	check(mesh.mesh != original and mesh.mesh.get_surface_count() >= 2, "Recolor splits selected faces from untouched geometry: " + world_mode)
	var blue: bool = false
	var unchanged: bool = false
	for surface in mesh.mesh.get_surface_count():
		var material: Material = mesh.mesh.surface_get_material(surface)
		if material is StandardMaterial3D and material.albedo_color.is_equal_approx(Color(0.1, 0.2, 0.95)): blue = true
		else: unchanged = true
	check(blue and unchanged, "Selected faces get an exact color while other materials remain: " + world_mode)
	check(original == Parts.original_mesh(mesh), "Shared source model remains intact: " + world_mode)
	var sprite_item: Dictionary = studio.current().add("2d:Coffee_Shop", [100, 30, 0] if world_mode == "2d" else [4, 0, 0], "SE")
	studio.changed()
	var sprite_instance: Node = studio.worlds[world_mode].instances[sprite_item["uid"]]
	var sprite: Sprite2D = Parts.sprite_for(sprite_instance)
	var base: Texture2D = Parts.base_texture(sprite)
	var image: Image = base.get_image()
	var start := Vector2i.ZERO
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.9: start = Vector2i(x, y); break
		if start != Vector2i.ZERO: break
	var pixel_edit: Dictionary = Parts.pixels(sprite, sprite.get_rect().position + Vector2(start) + Vector2.ONE * 0.1, 0.08, false)
	var screen: Vector2
	if world_mode == "2d": screen = studio.viewport.canvas_transform * sprite.to_global(sprite.get_rect().position + Vector2(start) + Vector2.ONE * 0.1)
	else:
		var camera: Camera3D = studio.worlds["3d"].camera
		var uv: Vector2 = (Vector2(start) + Vector2.ONE * 0.1) / sprite.get_rect().size
		var mesh_node: MeshInstance3D = sprite_instance.mesh
		var point: Vector3 = mesh_node.global_position + camera.global_basis.x * (uv.x - 0.5) * mesh_node.mesh.size.x + Vector3.UP * (0.5 - uv.y) * mesh_node.mesh.size.y
		screen = camera.unproject_position(point)
	studio.set_tool("color")
	studio.color_editor.pick(screen)
	check(studio.color_editor.selected_uid == sprite_item["uid"] and studio.color_editor.selection.get("kind") == "pixels", "Canvas color picking selects the sprite's pixel region: " + world_mode)
	var one_pixel: Dictionary = Parts.pixels(sprite, sprite.get_rect().position + Vector2(start) + Vector2.ONE * 0.1, 0.08, true)
	check(one_pixel["pixels"].size() == 1, "Single-pixel selection is exact: " + world_mode)
	check(pixel_edit["pixels"].size() < image.get_width() * image.get_height(), "Sprite region is smaller than the whole image: " + world_mode)
	pixel_edit["color"] = [0.95, 0.1, 0.3, 1.0]
	sprite_item["colors"] = [pixel_edit]
	studio.changed()
	var painted: Image = sprite.texture.get_image()
	check(Parts.color_distance(painted.get_pixelv(start), Color(0.95, 0.1, 0.3)) <= 1.0 / 255, "Selected sprite pixels change to the requested color: " + world_mode)
	check(not image.get_pixelv(start).is_equal_approx(painted.get_pixelv(start)), "Recolor leaves the original sprite texture unchanged: " + world_mode)
	var outside: int = -1
	for index in image.get_width() * image.get_height():
		if not pixel_edit["pixels"].has(index) and image.get_pixel(index % image.get_width(), index / image.get_width()).a > 0.9: outside = index; break
	check(outside >= 0 and image.get_pixel(outside % image.get_width(), outside / image.get_width()).is_equal_approx(painted.get_pixel(outside % image.get_width(), outside / image.get_width())), "Pixels outside the selected region stay unchanged: " + world_mode)
	studio.color_editor.selected_mode = world_mode
	studio.color_editor.selected_uid = sprite_item["uid"]
	studio.color_editor.selected_cell = null
	studio.color_editor.selection = one_pixel
	studio.color_editor.picker.color = Color.GREEN
	var history: int = studio.current().undo_history.size()
	studio.color_editor.apply_color()
	check(studio.current().undo_history.size() == history + 1, "Applying a color records one undo step: " + world_mode)
	studio._command("undo", null)
	check(studio.current().object(sprite_item["uid"])["colors"].size() == 1, "Undo restores the previous piece colors: " + world_mode)
	studio._command("redo", null)
	check(studio.current().object(sprite_item["uid"])["colors"].size() == 2, "Redo restores the edited piece colors: " + world_mode)
	var export_path: String = directory + "/colors_" + world_mode + ".tscn"
	check(Exporter.save_scene(studio.worlds[world_mode], studio.current().data, studio.library, export_path) == OK, "Piece colors export: " + world_mode)
	var exported: Node = load(export_path).instantiate()
	root.add_child(exported)
	await process_frame
	var exported_sprite: Sprite2D = Parts.sprite_for(exported.get_node("Objects").get_child(2))
	check(exported_sprite.texture.get_image().get_pixelv(start).is_equal_approx(Color.GREEN), "Export restores sprite region colors: " + world_mode)
	var exported_mesh: MeshInstance3D = Parts.model_root(exported.get_node("Objects").get_child(0)).get_node(path)
	check(exported_mesh.mesh.get_surface_count() >= 2, "Export restores the model's painted pieces: " + world_mode)
	exported.free()
	studio.worlds["2d"].camera.enabled = world_mode == "2d"
	if world_mode == "3d":
		choose(studio.current().object(sprite_item["uid"]))
		studio.angle_input.value = 22
		studio.pitch_input.value = 15
		studio.roll_input.value = -8
		check(sprite_instance.material.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED and sprite_instance.rotation_degrees.is_equal_approx(Vector3(15, 67, -8)), "Sprite cards rotate physically in 3D")
	else:
		choose(studio.current().object(sprite_item["uid"]))
		studio.angle_input.value = 33
		check(is_equal_approx(sprite_instance.rotation_degrees, 33), "Native 2D artwork supports arbitrary angles")

func tile_checks() -> void:
	studio.switch_mode("2d")
	studio.select_asset("2d:Road_Arrow_X")
	studio.angle_input.value = 37
	studio.paint(studio.canvas.size / 2 + Vector2(-200, 160))
	var tile: Dictionary = studio.current().data["tiles"][0]
	var cell := Vector2i(tile["cell"][0], tile["cell"][1])
	var world: Node = studio.worlds["2d"]
	var source_id: int = world.ground.get_cell_source_id(cell)
	var material: ShaderMaterial = world.ground.tile_set.get_source(source_id).get_tile_data(world.ground.get_cell_atlas_coords(cell), world.ground.get_cell_alternative_tile(cell)).material
	check(tile["direction"] == "37" and is_equal_approx(material.get_shader_parameter("angle_radians"), deg_to_rad(37)), "Pixel ground supports arbitrary isometric angles")
	studio.set_tool("color")
	studio.color_editor.pick(studio.viewport.canvas_transform * (IsoMath.tile_to_world(cell) + Vector2(0, 8)))
	check(not studio.color_editor.selection.is_empty(), "Ground tile pixel regions can be picked")
	if not studio.color_editor.selection.is_empty():
		studio.color_editor.picker.color = Color.YELLOW
		studio.color_editor.apply_color()
		check(not tile.get("colors", []).is_empty() and world.ground.get_cell_source_id(cell) >= 3, "Painted ground uses its own texture without changing neighboring tiles")
		var path: String = directory + "/painted_ground.tscn"
		check(Exporter.save_scene(world, studio.current().data, studio.library, path) == OK, "Painted and rotated ground exports")
		var exported: Node = load(path).instantiate()
		root.add_child(exported)
		var ground: TileMapLayer = exported.get_node("Ground")
		check(ground.get_cell_source_id(cell) >= 3 and ground.tile_set.get_source(ground.get_cell_source_id(cell)).texture.get_image() != null, "Export restores a painted ground texture")
		exported.free()
		world.camera.enabled = true

func lane_checks() -> void:
	studio.documents["2d"].data = Templates.make("2d", "city")
	studio.switch_mode("2d")
	var a: Dictionary = studio.current().add("3d:HanX_GasStation/Car_Coupe", [96, 64, 0], "90", 0.5)
	var b: Dictionary = studio.current().add("3d:HanX_GasStation/Car_Coupe", [208, 88, 0], "270", 0.5)
	studio.changed()
	studio.selected_uids.assign([a["uid"], b["uid"]])
	studio.selected_uid = a["uid"]
	studio.align_cars()
	check(a["position"] == [92.0, 66.0, 0.0], "Forward car centers between the dashed marking and the road edge")
	check(b["position"] == [196.0, 94.0, 0.0], "Opposite car centers between the dashed marking and the road edge")
	studio._command("undo", null)
	check(studio.current().object(a["uid"])["position"] == [96.0, 64.0, 0.0], "Align cars can be undone")
	studio._command("redo", null)
	check(studio.current().object(a["uid"])["position"] == [92.0, 66.0, 0.0], "Align cars can be redone")
