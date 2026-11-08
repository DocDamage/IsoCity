extends SceneTree

const Parts = preload("res://scripts/builder/part_colors.gd")
const Patterns = preload("res://scripts/builder/tile_patterns.gd")
var studio: Control

func _init() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1480, 900)
	studio = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	for i in 4: await process_frame
	for dimension in ["2d", "3d"]:
		studio.documents[dimension].data = {"title": "Tile paint preview · original / painted", "mode": dimension, "objects": [], "tiles": [], "night": false}
		studio.switch_mode(dimension)
		var id: String = "2d:Coffee_Shop" if dimension == "2d" else "3d:HanX_GasStation/Car_Coupe"
		studio.current().add(id, [-80, 0, 0] if dimension == "2d" else [-3.5, 0, 0], "SE" if dimension == "2d" else "90")
		var item: Dictionary = studio.current().add(id, [70, 0, 0] if dimension == "2d" else [3.5, 0, 0], "SE" if dimension == "2d" else "90")
		studio.changed()
		var instance: Node = studio.worlds[dimension].instances[item["uid"]]
		var edit: Dictionary
		if dimension == "2d":
			var sprite: Sprite2D = instance.get_node("Sprite2D")
			edit = Parts.pixels(sprite, sprite.get_rect().position + Vector2(45, 22), 0.04, false)
		else:
			var model: Node3D = Parts.model_root(instance)
			var mesh: MeshInstance3D = model.find_children("*", "MeshInstance3D", true, false)[0]
			var arrays: Array = Parts.original_mesh(mesh).surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = Parts.indices_for(arrays)
			var faces: Array[int] = []
			var transform: Transform3D = model.global_transform.affine_inverse() * mesh.global_transform
			for face in indices.size() / 3:
				var a: Vector3 = transform * vertices[indices[face * 3]]
				var b: Vector3 = transform * vertices[indices[face * 3 + 1]]
				var c: Vector3 = transform * vertices[indices[face * 3 + 2]]
				if absf((b - a).cross(c - a).normalized().y) > 0.8 and (a.y + b.y + c.y) / 3 > 0.55: faces.append(face)
			print("PREVIEW MODEL: ", mesh.name, " surfaces ", mesh.mesh.get_surface_count(), " top faces ", faces.size(), " override ", mesh.material_override)
			edit = {"kind": "faces", "mesh": str(model.get_path_to(mesh)), "surface": 0, "faces": faces, "color": [1.0, 1.0, 1.0, 1.0]}
		studio.color_editor.selected_mode = dimension
		studio.color_editor.selected_uid = item["uid"]
		studio.color_editor.selected_cell = null
		studio.color_editor.selection = edit
		studio.color_editor.set_tile_source("2d:Floor_Brick_Red" if studio.library.assets.has("2d:Floor_Brick_Red") else "2d:Floor_Wood_Oak")
		studio.color_editor.tile_projection.select(1)
		studio.color_editor.apply_tile()
		studio.clear_placement()
		studio.tool = "select"
		studio.color_editor.note.text = "Original on the left · tile-painted piece on the right"
		studio.color_editor.page.scroll_vertical = 270
		if dimension == "2d":
			studio.worlds[dimension].camera.position = Vector2(0, 5)
			studio.worlds[dimension].camera.zoom = Vector2.ONE * 2.6
		else:
			studio.worlds[dimension].distance = 13
			studio.worlds[dimension].target = Vector3(0, 0.4, 0)
			studio.worlds[dimension].update_camera()
		for i in 12: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://output/tile_paint_" + dimension + ".png")
	studio.free()
	quit()
