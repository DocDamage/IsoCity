extends SceneTree

const Parts = preload("res://scripts/builder/part_colors.gd")
const Patterns = preload("res://scripts/builder/tile_patterns.gd")
const Exporter = preload("res://scripts/builder/exporter.gd")
var checks: int = 0
var failures: int = 0
var studio: Control

func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL: ", message)

func run() -> void:
	root.size = Vector2i(1480, 900)
	studio = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	for i in 4: await process_frame
	var directory: String = "res://output/tile_paint_test_" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	for dimension in ["2d", "3d"]:
		studio.documents[dimension].data = {"title": "Tile painting", "mode": dimension, "objects": [], "tiles": [], "night": false}
		studio.switch_mode(dimension)
		var sprite_id: String = "2d:Coffee_Shop"
		var sprite_item: Dictionary = studio.current().add(sprite_id, [0, 0, 0], "SE", 1)
		var model_item: Dictionary = studio.current().add("3d:HanX_GasStation/Car_Coupe", [80, 40, 0] if dimension == "2d" else [4, 0, 0], "90", 0.5)
		var untouched: Dictionary = studio.current().add(sprite_id, [-80, 0, 0] if dimension == "2d" else [-4, 0, 0], "SE", 1)
		studio.changed()
		var instance: Node = studio.worlds[dimension].instances[sprite_item["uid"]]
		var sprite: Sprite2D = Parts.sprite_for(instance)
		var original: Image = Parts.base_texture(sprite).get_image()
		var chosen := Vector2i(-1, -1)
		for y in int(sprite.get_rect().size.y):
			for x in int(sprite.get_rect().size.x):
				if original.get_pixel(x, y).a > 0.95: chosen = Vector2i(x, y); break
			if chosen.x >= 0: break
		var edit: Dictionary = Parts.pixels(sprite, sprite.get_rect().position + Vector2(chosen) + Vector2.ONE * 0.1, 0, true)
		check(not edit.is_empty(), "Exact pixel piece can be selected: " + dimension)
		studio.color_editor.selected_mode = dimension
		studio.color_editor.selected_uid = sprite_item["uid"]
		studio.color_editor.selected_cell = null
		studio.color_editor.selection = edit
		studio.color_editor.set_tile_source("2d:Asphalt")
		studio.color_editor.tile_size.value = 0.5
		studio.color_editor.tile_angle.value = 37
		studio.color_editor.tile_x.value = 0.3
		studio.color_editor.tile_y.value = -0.2
		studio.color_editor.tile_projection.select(2)
		var history: int = studio.current().undo_history.size()
		studio.color_editor.apply_tile()
		check(studio.current().undo_history.size() == history + 1, "Tile application is one undo step: " + dimension)
		var painted: Image = sprite.texture.get_image()
		var selected_index: int = chosen.y * original.get_width() + chosen.x
		var changed_pixels: int = 0
		for y in original.get_height():
			for x in original.get_width():
				if not painted.get_pixel(x, y).is_equal_approx(original.get_pixel(x, y)):
					changed_pixels += 1
					check(y * original.get_width() + x == selected_index, "Only the chosen pixel is tile-painted")
		check(changed_pixels == 1 and is_equal_approx(painted.get_pixelv(chosen).a, original.get_pixelv(chosen).a), "Tile paint preserves alpha and changes the selected pixel: " + dimension)
		check(Parts.sprite_for(studio.worlds[dimension].instances[untouched["uid"]]).texture == Parts.base_texture(sprite), "Other instances retain the source texture: " + dimension)
		check(Parts.base_texture(sprite).get_image().get_pixelv(chosen).is_equal_approx(original.get_pixelv(chosen)), "Source pixels remain unchanged: " + dimension)
		studio._command("undo", null)
		check(not studio.current().object(sprite_item["uid"]).has("colors"), "Undo removes the tile paint: " + dimension)
		studio._command("redo", null)
		check(studio.current().object(sprite_item["uid"])["colors"][0]["pattern"]["angle"] == 37.0, "Redo restores exact texture mapping: " + dimension)
		var model: Node3D = Parts.model_root(studio.worlds[dimension].instances[model_item["uid"]])
		var mesh: MeshInstance3D = model.find_children("*", "MeshInstance3D", true, false)[0]
		var original_mesh: Mesh = Parts.original_mesh(mesh)
		var model_edit: Dictionary = {"kind": "faces", "mesh": str(model.get_path_to(mesh)), "surface": 0, "faces": [0], "color": [1.0, 1.0, 1.0, 1.0]}
		studio.color_editor.selected_uid = model_item["uid"]
		studio.color_editor.selection = model_edit
		studio.color_editor.apply_tile()
		var tiled_faces: int = 0
		for surface in mesh.mesh.get_surface_count():
			var material: Material = mesh.mesh.surface_get_material(surface)
			if material is BaseMaterial3D and material.albedo_texture and material.albedo_texture.resource_path.is_empty():
				tiled_faces += Parts.indices_for(mesh.mesh.surface_get_arrays(surface)).size() / 3
				check(mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_TEX_UV] != null, "Painted triangles get planar UVs even without source UVs: " + dimension)
		check(tiled_faces == 1, "Only the selected model triangle receives the tile: " + dimension)
		check(Parts.original_mesh(mesh) == original_mesh, "Original model resource is preserved: " + dimension)
		var save_path: String = directory + "/" + dimension + ".json"
		check(studio.write_project(save_path) and studio.load_project(save_path), "Tile paint saves and reopens: " + dimension)
		check(Exporter.save_scene(studio.worlds[dimension], studio.current().data, studio.library, directory + "/" + dimension + ".tscn") == OK, "Tile-painted objects export: " + dimension)
		var exported: Node = load(directory + "/" + dimension + ".tscn").instantiate()
		root.add_child(exported)
		await process_frame
		var painted_objects: int = 0
		for item in exported.studio_data["objects"]:
			if item.has("colors") and item["colors"][0].has("pattern"): painted_objects += 1
		check(painted_objects == 2, "Export restores sprite and model tile patterns: " + dimension)
		exported.free()
	var invalid: Dictionary = Patterns.from_asset(studio.library, "2d:Asphalt")
	invalid["scale"] = 0
	check(not Patterns.valid(invalid), "Reject zero texture scale")
	invalid["scale"] = 1
	invalid["texture"] = "res://assets/../project.godot"
	check(not Patterns.valid(invalid), "Reject non-asset texture paths")
	studio.free()
	print("TILE PAINT: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
