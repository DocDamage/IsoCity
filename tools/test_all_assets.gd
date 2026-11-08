extends SceneTree

const ModelBounds = preload("res://scripts/model_bounds.gd")
const Catalog = preload("res://scripts/catalog.gd")
var failures: int = 0
var total: int = 0

func _init() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: ", message)

func _scenes(directory: String) -> Array[String]:
	var paths: Array[String] = []
	for name in DirAccess.get_files_at(directory):
		if name.ends_with(".tscn"):
			paths.append(directory + "/" + name)
	for name in DirAccess.get_directories_at(directory):
		paths.append_array(_scenes(directory + "/" + name))
	return paths

func _run() -> void:
	for path in _scenes("res://scenes/items") + _scenes("res://scenes/items_3d"):
		var scene: PackedScene = load(path)
		check(scene != null, "Scene loads: " + path)
		if not scene:
			continue
		var node: Node = scene.instantiate()
		root.add_child(node)
		if node is Node2D:
			var sprite: Sprite2D = node.get_node_or_null("Sprite2D")
			check(sprite != null and sprite.texture != null, "Sprite texture exists: " + path)
			check(not Catalog.get_item(node.item_id).is_empty(), "Prefab is registered: " + path)
			if sprite and sprite.texture:
				check(int(sprite.texture.get_width()) % sprite.hframes == 0, "Sprite strip splits into whole frames: " + path)
			if node is IsoObject:
				check(node.has_node("StaticBody2D") == node.has_collision, "2D collision enabled correctly: " + path)
		else:
			var bounds: AABB = ModelBounds.get_bounds(node)
			var collision: CollisionShape3D = node.get_node("CollisionShape3D")
			check(bounds.size.length_squared() > 0.0, "3D mesh is present: " + path)
			if collision.shape is CylinderShape3D:
				check(node.has_meta("authored_footprint") and collision.shape.radius>0 and collision.shape.height<=bounds.size.y+.01,"Authored trunk collision fits below the canopy: "+path)
				check(absf(collision.position.y-collision.shape.height*.5)<.001,"Tree trunk collision meets ground: "+path)
			else:
				check(collision.shape.size.is_equal_approx(bounds.size.max(Vector3.ONE * 0.01)), "3D collision size matches model bounds: " + path)
				check(collision.position.is_equal_approx(bounds.get_center()), "3D collision center matches model bounds: " + path)
		node.free()
		total += 1
	# Exercise every palette category and validate the paths it actually gives Godot.
	var dock: Control = load("res://addons/isocity/palette_dock.tscn").instantiate()
	root.add_child(dock)
	for index in range(dock.category_option.item_count):
		var category: String = dock.category_option.get_item_text(index)
		dock._populate_items(category)
		await process_frame
		for button in dock.item_grid.get_children():
			check(ResourceLoader.exists(button.scene_path), "Palette drag target exists: " + button.scene_path)
		if category == "All Categories":
			check(dock.item_grid.get_child_count() == Catalog.get_registry()["items"].size() + _scenes("res://scenes/items_3d").size(), "All Categories includes registered sprites and all model prefabs")
	for path in _scenes("res://scenes/workspaces"):
		var workspace: Node = load(path).instantiate()
		root.add_child(workspace)
		workspace.free()
	dock.queue_free()
	await process_frame
	print("ASSETS: ", total, " prefabs checked; ", failures, " failures")
	quit(1 if failures > 0 else 0)
