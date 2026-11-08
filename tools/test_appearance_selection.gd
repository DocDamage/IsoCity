extends SceneTree

const Parts = preload("res://scripts/builder/part_colors.gd")
const Selection = preload("res://scripts/builder/piece_selection.gd")
const Document = preload("res://scripts/builder/document.gd")
const Rotation = preload("res://scripts/builder/rotation.gd")
var checks: int = 0
var failures: int = 0
var studio: Control
const BLOCK: String = "3d:Probe/Piece_Block"
const SPRITE: String = "2d:Probe_White"

func _init() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func selected(items: Array) -> void:
	studio.selected_uids.clear()
	for item in items: studio.selected_uids.append(item["uid"])
	studio.selected_uid = studio.selected_uids[0] if not studio.selected_uids.is_empty() else ""
	studio.selected_cell = null
	studio.refresh_controls()

func fixtures() -> void:
	var body := StaticBody3D.new()
	var mesh := MeshInstance3D.new()
	mesh.name = "BlockMesh"
	var cube := BoxMesh.new()
	var geometry := ArrayMesh.new()
	geometry.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, cube.surface_get_arrays(0))
	geometry.surface_set_material(0, StandardMaterial3D.new())
	mesh.mesh = geometry
	body.add_child(mesh)
	mesh.owner = body
	var scene := PackedScene.new()
	scene.pack(body)
	ResourceSaver.save(scene, "res://output/piece_block_fixture.tscn")
	body.free()
	var picture := Image.create(5, 5, false, Image.FORMAT_RGBA8)
	picture.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(picture)
	ResourceSaver.save(texture, "res://output/piece_sprite_texture.tres")
	var node := IsoObject.new()
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.centered = false
	sprite.texture = load("res://output/piece_sprite_texture.tres")
	node.add_child(sprite)
	sprite.owner = node
	node.directions_data = {"SE": {"file": "../../../output/piece_sprite_texture.tres", "origin": [0, 0], "footprint": [1, 1], "frame_width": 5, "frame_height": 5}}
	scene = PackedScene.new()
	scene.pack(node)
	ResourceSaver.save(scene, "res://output/piece_sprite_fixture.tscn")
	node.free()
	studio.library.assets[BLOCK] = {"id": BLOCK, "mode": "3d", "name": "Piece block fixture", "category": "Decorations", "path": "res://output/piece_block_fixture.tscn", "data": {}, "behavior": {"layer": "Decorations", "ground": false}}
	studio.library.assets[SPRITE] = {"id": SPRITE, "mode": "2d", "name": "White sprite fixture", "category": "Decorations", "path": "res://output/piece_sprite_fixture.tscn", "data": {"directions": {"SE": {"file": "../../../output/piece_sprite_texture.tres", "frame_width": 5, "frame_height": 5, "footprint": [1, 1]}}}, "behavior": {"layer": "Decorations", "ground": false}}

func blank(mode: String) -> void:
	studio.switch_mode(mode)
	studio.current().data = {"title": "Appearance test", "mode": mode, "objects": [], "tiles": [], "night": false}
	studio.current().undo_history.clear()
	studio.current().redo_history.clear()
	studio.color_editor.selection = {}
	studio.color_editor.base_selection = {}
	studio.color_editor.expansion.set_value_no_signal(0)
	studio.color_editor.protect_visible.set_pressed_no_signal(true)
	studio.rotation_controls.choice.select(0)
	studio.arrange_tools.restore({})
	studio.changed()
	studio.worlds[mode].reset_camera("room")

func run() -> void:
	studio = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	for i in 6: await process_frame
	fixtures()
	for mode in ["2d", "3d"]:
		blank(mode)
		test_appearance(mode)
		blank(mode)
		test_selection(mode)
		blank(mode)
		test_rotation(mode)
	if "--capture" in OS.get_cmdline_user_args(): await capture()
	studio.free()
	print("APPEARANCE / SELECTION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func test_appearance(mode: String) -> void:
	var appearance: RefCounted = studio.appearance_tools
	appearance.presets = []
	appearance.refresh()
	var a: Dictionary = studio.current().add("2d:Coffee_Shop", [0, 0, 0] if mode == "2d" else [0, 1, 0], "SE")
	var b: Dictionary = studio.current().add(a["asset"], [100, 0, 0] if mode == "2d" else [4, 1, 0], "SE")
	var c: Dictionary = studio.current().add("3d:HanX_GasStation/Car_Coupe", [180, 0, 0] if mode == "2d" else [8, 1, 0], "0", 0.5)
	studio.changed()
	var sprite: Sprite2D = Parts.sprite_for(studio.worlds[mode].instances[a["uid"]])
	var edit: Dictionary = {}
	var image: Image = Parts.base_texture(sprite).get_image()
	for y in int(sprite.get_rect().size.y):
		for x in int(sprite.get_rect().size.x):
			if image.get_pixel(x, y).a > 0.9: edit = Parts.pixels(sprite, sprite.get_rect().position + Vector2(x + 0.1, y + 0.1), 0, true); break
		if not edit.is_empty(): break
	edit["color"] = [0.1, 0.6, 0.9, 1.0]
	a["colors"] = [edit]
	studio.changed()
	selected([a])
	appearance.copy_appearance()
	selected([b, c])
	var position: Array = b["position"].duplicate()
	appearance.paste_appearance(appearance.copied)
	check(b.get("colors") == a["colors"] and not c.has("colors"), "Appearance paste applies to compatible objects and skips incompatible ones: " + mode)
	check(b["position"] == position and image.get_data() == Parts.base_texture(sprite).get_image().get_data(), "Copying appearance preserves placement and original pixels: " + mode)
	var b_uid: String = b["uid"]
	studio._command("undo", null)
	check(not studio.current().object(b_uid).has("colors"), "Appearance paste is one undo action: " + mode)
	studio._command("redo", null)
	check(studio.current().object(b_uid).get("colors") == a["colors"], "Appearance paste supports redo: " + mode)
	selected([a])
	appearance.name_input.text = "Blue object"
	appearance.save_preset("object")
	studio.color_editor.picker.color = Color(0.2, 0.8, 0.3)
	appearance.name_input.text = "Green material"
	appearance.save_preset("color")
	studio.color_editor.set_tile_source("2d:Brick_Pavers")
	studio.color_editor.tile_size.value = 0.75
	studio.color_editor.tile_angle.value = 27
	studio.color_editor.tile_x.value = 0.3
	appearance.name_input.text = "Brick material"
	appearance.save_preset("tile")
	check(appearance.presets.size() == 3, "Object, color and tile presets can be saved: " + mode)
	studio.color_editor.selected_mode = mode
	studio.color_editor.selected_uid = c["uid"]
	studio.color_editor.selected_cell = null
	var model: Node3D = Parts.model_root(studio.worlds[mode].instances[c["uid"]])
	var mesh: MeshInstance3D = model.find_children("*", "MeshInstance3D", true, false)[0]
	studio.color_editor.selection = {"kind": "faces", "mesh": str(model.get_path_to(mesh)), "surface": 0, "faces": [0], "color": [1.0, 1.0, 1.0, 1.0]}
	appearance.preset_list.select(1)
	appearance.apply_selected()
	check(Color(c["colors"][0]["color"][0], c["colors"][0]["color"][1], c["colors"][0]["color"][2]).is_equal_approx(Color(0.2, 0.8, 0.3)), "A saved color applies to a different asset's picked piece: " + mode)
	appearance.preset_list.select(2)
	appearance.apply_selected()
	check(c["colors"][-1]["pattern"]["scale"] == 0.75 and c["colors"][-1]["pattern"]["angle"] == 27, "Saved tile materials preserve mapping settings: " + mode)
	check(Parts.valid(c["colors"]), "Reusable material edits retain valid masks: " + mode)
	appearance.storage_path = "user://test_material_presets.json"
	appearance.name_input.text = "Persistent color"
	studio.storage_enabled = true
	appearance.save_preset("color")
	studio.storage_enabled = false
	appearance.presets = []
	appearance.reload_presets()
	check(appearance.presets.size() == 4, "Presets persist across library reloads: " + mode)
	appearance.preset_list.select(3)
	studio.storage_enabled = true
	appearance.remove_selected()
	studio.storage_enabled = false
	appearance.reload_presets()
	check(appearance.presets.size() == 3, "Removing a preset persists: " + mode)
	DirAccess.remove_absolute(appearance.storage_path)
	check(Document.valid(studio.current().data, mode, studio.library), "Appearance edits validate for project saves: " + mode)
	var save_path: String = "user://appearance_edits_roundtrip.json"
	check(studio.write_project(save_path) and studio.load_project(save_path), "Color and tile appearance edits save and reopen: " + mode)
	check(studio.current().object(c["uid"])["colors"][-1]["pattern"]["angle"] == 27, "Saved tile appearance retains mapping: " + mode)
	DirAccess.remove_absolute(save_path)
	var alias: String = "3d:Probe/Piece_Block_Alias"
	studio.library.assets[alias] = studio.library.assets[BLOCK].duplicate(true)
	studio.library.assets[alias]["id"] = alias
	check(appearance.compatible({"asset": BLOCK, "colors": []}, {"asset": alias}), "Identical model topology is compatible across different catalog IDs")
	check(not preload("res://scripts/builder/appearance_tools.gd").valid_preset({"name": "Bad", "kind": "color", "payload": {"color": [NAN, 0, 0, 1]}}), "Malformed material presets are rejected")

func model_screen(instance: Node, point: Vector3, mode: String) -> Vector2:
	if mode == "3d": return studio.worlds[mode].camera.unproject_position(point)
	var sprite: Sprite2D = instance.get_node("Sprite2D")
	return studio.viewport.canvas_transform * sprite.to_global(sprite.get_rect().position + instance.camera.unproject_position(point) / Vector2(instance.viewport.size) * sprite.get_rect().size)

func test_selection(mode: String) -> void:
	var editor: RefCounted = studio.color_editor
	var a: Dictionary = studio.current().add(BLOCK, [0, 0, 0] if mode == "2d" else [0, 1, 0], "0")
	studio.changed()
	var instance: Node = studio.worlds[mode].instances[a["uid"]]
	var model: Node3D = Parts.model_root(instance)
	var camera: Camera3D = studio.worlds[mode].camera if mode == "3d" else instance.camera
	var center: Vector3 = model.global_position
	var screen: Vector2 = model_screen(instance, center, mode)
	editor.pick(screen)
	check(not editor.selection.is_empty() and editor.selection.get("faces", []).size() > 0 and editor.selection["faces"].size() < 12, "Protected connected selection excludes hidden cube faces: " + mode)
	var hit: Dictionary = Parts.ray_pick(model, camera.project_ray_origin(camera.unproject_position(center)), camera.project_ray_normal(camera.unproject_position(center)))
	var seed: Dictionary = Parts.connected_faces(model, hit, 0, true)
	check(Selection.grow_faces(seed, model, 1)["faces"].size() > 1, "Mesh selection expands by adjacent face rings: " + mode)
	check(Selection.grow_faces(seed, model, -1)["faces"].is_empty(), "Mesh selection can shrink to empty: " + mode)
	var position: Vector3 = Vector3(0, 1, 0) + camera.global_basis.z * 2 if mode == "3d" else Vector3.ZERO
	var front: Dictionary = studio.current().add(BLOCK, [position.x, position.y, position.z], "0")
	front["locked"] = true
	studio.changed()
	editor.pick(screen)
	check(editor.selection.is_empty(), "A visible locked object blocks picking the object behind it: " + mode)
	editor.protect_visible.set_pressed_no_signal(false)
	editor.pick(screen)
	check(editor.selected_uid == a["uid"] and not editor.selection.is_empty(), "Explicitly disabling protection permits picking through a locked object: " + mode)
	front["visible"] = false
	studio.changed()
	editor.protect_visible.set_pressed_no_signal(true)
	editor.pick(screen)
	check(editor.selected_uid == a["uid"] and not editor.selection.is_empty(), "A hidden object does not block piece picking: " + mode)
	# Partly overlapping sprites must clip the selection mask, not just the initial click.
	studio.current().data["objects"] = []
	studio.changed()
	a = studio.current().add(SPRITE, [0, 0, 0] if mode == "2d" else [0, 1, 0], "SE")
	var offset := Vector3(2, 0, 0)
	if mode == "3d": offset = studio.worlds[mode].camera.global_basis.z * 2 + studio.worlds[mode].camera.global_basis.x * (2.0 / 32.0) + Vector3(0, 1, 0)
	front = studio.current().add(SPRITE, [offset.x, offset.y, offset.z], "SE")
	front["locked"] = true
	studio.changed()
	instance = studio.worlds[mode].instances[a["uid"]]
	var sprite: Sprite2D = Parts.sprite_for(instance)
	var all_pixels: Dictionary = Parts.pixels(sprite, sprite.get_rect().position + Vector2(2.5, 2.5), 0, false)
	var pixel: Dictionary = Parts.pixels(sprite, sprite.get_rect().position + Vector2(2.5, 2.5), 0, true)
	check(Selection.grow_pixels(pixel, sprite, 1)["pixels"].size() == 5, "Pixel selection expands by one ring: " + mode)
	check(Selection.grow_pixels(all_pixels, sprite, -1)["pixels"].size() == 9, "Pixel selection erodes its outer boundary: " + mode)
	editor.selected_mode = mode
	editor.selected_uid = a["uid"]
	editor.selected_cell = null
	var clipped: Dictionary = editor.visible_mask(all_pixels)
	check(clipped["pixels"].size() == 10, "Opaque overlapping artwork is excluded from a selected pixel region: " + mode)
	check(clipped["pixels"].all(func(index: int) -> bool: return index % 5 < 2), "Only the exposed sprite columns remain paintable: " + mode)
	var at: Vector2 = studio.viewport.canvas_transform * sprite.to_global(Vector2(0.5, 2.5)) if mode == "2d" else studio.worlds[mode].camera.unproject_position(editor.sprite_pixel_point(instance, Vector2(0.5, 2.5), all_pixels))
	editor.pick(at)
	check(editor.selected_uid == a["uid"] and editor.selection.get("pixels", []).size() == 10, "Actual pointer picking applies the visibility mask: " + mode)
	var shift: Vector3 = Vector3(1, 0, 0) if mode == "2d" else studio.worlds[mode].camera.global_basis.x / 32.0
	front["position"] = [front["position"][0] - shift.x, front["position"][1] - shift.y, front["position"][2] - shift.z]
	studio.changed()
	editor.picker.color = Color.RED
	editor.apply_color()
	check(a.get("colors", [])[0]["pixels"].size() == 5, "Applying color revalidates the visible pixel mask: " + mode)
	front["position"] = [front["position"][0] - shift.x, front["position"][1] - shift.y, front["position"][2] - shift.z]
	studio.changed()
	var history: int = studio.current().undo_history.size()
	editor.apply_color()
	check(a["colors"].size() == 1 and studio.current().undo_history.size() == history, "A fully occluded selection cannot paint or create an empty undo step: " + mode)
	var picture := Image.create(10, 5, false, Image.FORMAT_RGBA8)
	picture.fill(Color.WHITE)
	picture.set_pixel(3, 2, Color(1, 1, 1, 0))
	var framed := Sprite2D.new()
	framed.centered = false
	framed.texture = ImageTexture.create_from_image(picture)
	framed.hframes = 2
	var seed_pixel: Dictionary = Parts.pixels(framed, Vector2(4.5, 2.5), 0, true)
	var expanded: Dictionary = Selection.grow_pixels(seed_pixel, framed, 2)
	check(expanded["pixels"].all(func(index: int) -> bool: return index % 10 < 5 and index != 23), "Pixel growth stays inside its frame and excludes transparent pixels: " + mode)
	framed.free()

func test_rotation(mode: String) -> void:
	var item: Dictionary = studio.current().add("2d:Coffee_Shop", [0, 0, 0] if mode == "2d" else [0, 1, 0], "SE")
	item["angle"] = 17.0
	item["tilt"] = [12.0, 3.0]
	studio.changed()
	selected([item])
	studio.rotation_controls.choice.select(1)
	studio.rotation_step.value = 15
	studio.rotate_by(1)
	check(item["direction"] == "SW" and item["angle"] == 17 and item["tilt"] == [12.0, 3.0], "Explicit source-view rotation preserves world angles: " + mode)
	studio.rotation_controls.choice.select(2)
	studio.rotate_by(1)
	check(item["direction"] == "SW" and item["angle"] == 32, "Explicit world rotation preserves supplied artwork: " + mode)
	studio.rotation_controls.choice.select(3)
	studio.refresh_controls()
	studio.angle_input.value = 30
	check(is_equal_approx(studio.rotation_controls.displayed(item), 30), "Camera-relative angle field sets the displayed angle: " + mode)
	var before: float = Rotation.heading(item, studio.library)
	studio.rotate_by(1)
	check(is_equal_approx(studio.rotation_controls.displayed(item), 45), "Camera-relative R advances clockwise by Rotate step: " + mode)
	studio._command("undo", null)
	item = studio.current().object(item["uid"])
	check(is_equal_approx(Rotation.heading(item, studio.library), before), "Explicit rotation is undoable: " + mode)
	selected([item])
	if mode == "3d":
		studio.worlds[mode].yaw += 30
		studio.worlds[mode].update_camera()
		check(not is_equal_approx(studio.rotation_controls.displayed(item), 30), "Camera-relative angle responds to orbiting the camera")
	var model: Dictionary = studio.current().add("3d:HanX_GasStation/Car_Coupe", [80, 0, 0] if mode == "2d" else [4, 1, 0], "0")
	studio.changed()
	selected([model])
	studio.angle_input.value = 0
	check(is_equal_approx(Rotation.heading(model, studio.library), Rotation.compass_yaw("N", studio.model_view_yaw())), "Camera angle zero faces screen north for models: " + mode)
	selected([item, model])
	var first_angle: float = studio.rotation_controls.displayed(item)
	var second_angle: float = studio.rotation_controls.displayed(model)
	studio.rotate_by(1)
	check(is_equal_approx(studio.rotation_controls.displayed(item), wrapf(first_angle + 15, 0, 360)) and is_equal_approx(studio.rotation_controls.displayed(model), wrapf(second_angle + 15, 0, 360)), "Mixed sprite/model camera rotation advances both in the same screen direction: " + mode)
	studio.color_editor.expansion.set_value_no_signal(2)
	studio.capture_workspace()
	var path: String = "user://appearance_rotation_roundtrip.json"
	check(studio.write_project(path) and studio.load_project(path) and studio.rotation_controls.choice.selected == 3 and studio.color_editor.expansion.value == 2, "Rotation and selection modes persist in projects: " + mode)
	DirAccess.remove_absolute(path)
	var ground: Dictionary = studio.current().add("2d:Grass", [0, 0, 0], "SW")
	studio.changed()
	selected([ground])
	studio.rotation_controls.choice.select(1)
	studio.rotate_by(1)
	check(ground["direction"] == "SW", "Source-view mode does not silently rotate a ground tile: " + mode)
	studio.rotation_controls.choice.select(3)
	studio.refresh_controls()
	studio.angle_input.value = 0
	var before_heading: float = Rotation.heading(ground, studio.library)
	studio.rotate_by(1)
	check(is_equal_approx(Rotation.heading(ground, studio.library), wrapf(before_heading + 15, 0, 360)), "Ground artwork rotates clockwise in camera mode: " + mode)
	if mode == "3d":
		var shader: ShaderMaterial = studio.worlds[mode].instances[ground["uid"]].mesh.material_override
		check(is_equal_approx(shader.get_shader_parameter("angle_radians"), deg_to_rad(Rotation.heading(ground, studio.library))), "Camera rotation reaches the actual ground shader")

func capture() -> void:
	studio.switch_mode("2d")
	studio.current().data = preload("res://scripts/builder/templates.gd").make("2d", "city")
	studio.changed()
	studio.worlds["2d"].reset_camera()
	studio.appearance_tools.page.get_parent().current_tab = studio.appearance_tools.page.get_index()
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://output/editor_appearance_presets.png")
	var item: Dictionary = studio.current().data["objects"][0]
	var sprite: Sprite2D = Parts.sprite_for(studio.worlds["2d"].instances[item["uid"]])
	studio.color_editor.expansion.set_value_no_signal(1)
	studio.color_editor.protect_visible.set_pressed_no_signal(true)
	var at: Vector2 = studio.viewport.canvas_transform * sprite.to_global(sprite.get_rect().position + Vector2(44, 25))
	studio.color_editor.pick(at)
	studio.set_tool("color")
	studio.color_editor.tabs.current_tab = studio.color_editor.page.get_index()
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://output/editor_safe_piece_selection.png")
	studio.color_editor.tabs.current_tab = 0
	studio.rotation_controls.choice.select(3)
	studio.refresh_controls()
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://output/editor_rotation_modes.png")
