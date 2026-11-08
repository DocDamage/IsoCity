extends SceneTree

const ModelBounds = preload("res://scripts/model_bounds.gd")

func _init() -> void:
	var changed: int = 0
	var failed: int = 0
	var size_regex := RegEx.new()
	size_regex.compile("size = Vector3\\([^\\n]+\\)")
	var transform_regex := RegEx.new()
	transform_regex.compile("transform = Transform3D\\([^\\n]+\\)")
	for pack in DirAccess.get_directories_at("res://scenes/items_3d"):
		for file in DirAccess.get_files_at("res://scenes/items_3d/" + pack):
			if not file.ends_with(".tscn"):
				continue
			var path: String = "res://scenes/items_3d/%s/%s" % [pack, file]
			var scene: PackedScene = load(path)
			var node: Node3D = scene.instantiate()
			var bounds: AABB = ModelBounds.get_bounds(node)
			if bounds.size.length_squared() == 0:
				printerr("No mesh bounds: ", path)
				failed += 1
			else:
				var size: Vector3 = bounds.size.max(Vector3.ONE * 0.01)
				var center: Vector3 = bounds.get_center()
				var original: String = FileAccess.get_file_as_string(path)
				var updated: String = size_regex.sub(original, "size = Vector3(%.9f, %.9f, %.9f)" % [size.x, size.y, size.z])
				updated = transform_regex.sub(updated, "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %.9f, %.9f, %.9f)" % [center.x, center.y, center.z])
				if original != updated:
					var output := FileAccess.open(path, FileAccess.WRITE)
					output.store_string(updated)
					changed += 1
			node.free()
	print("3D collision bounds fitted: ", changed, "; failures: ", failed)
	quit(1 if failed > 0 else 0)
