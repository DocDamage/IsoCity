extends RefCounted

const Parts = preload("res://scripts/builder/part_colors.gd")

static func grow_pixels(edit: Dictionary, sprite: Sprite2D, rings: int) -> Dictionary:
	var result: Dictionary = edit.duplicate(true)
	if rings == 0: return result
	var image: Image = Parts.base_texture(sprite).get_image()
	var width: int = image.get_width()
	var size := Vector2i(width / sprite.hframes, image.get_height() / sprite.vframes)
	var frame: int = int(edit.get("frame", sprite.frame))
	var area := Rect2i(Vector2i(frame % sprite.hframes, frame / sprite.hframes) * size, size)
	var selected: Dictionary = {}
	for index in edit["pixels"]: selected[int(index)] = true
	for ring in absi(rings):
		var next: Dictionary = selected.duplicate()
		for index in selected:
			var point := Vector2i(index % width, index / width)
			for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var neighbor: Vector2i = point + step
				var key: int = neighbor.y * width + neighbor.x
				if rings < 0 and (not area.has_point(neighbor) or not selected.has(key)): next.erase(index)
				elif rings > 0 and area.has_point(neighbor) and image.get_pixelv(neighbor).a >= 0.05 and next.size() < 262144: next[key] = true
		selected = next
	result["pixels"] = selected.keys()
	return result

static func grow_faces(edit: Dictionary, root: Node3D, rings: int) -> Dictionary:
	var result: Dictionary = edit.duplicate(true)
	if rings == 0: return result
	var node: MeshInstance3D = root.get_node_or_null(edit["mesh"])
	if not node: return {}
	var mesh: Mesh = Parts.original_mesh(node)
	var surface: int = int(edit["surface"])
	if surface >= mesh.get_surface_count(): return {}
	var arrays: Array = mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = Parts.indices_for(arrays)
	var edges: Dictionary = {}
	var face_edges: Array = []
	for face in indices.size() / 3:
		var keys: Array[String] = []
		for corner in 3:
			var a: String = str(vertices[indices[face * 3 + corner]].snapped(Vector3.ONE * 0.0001))
			var b: String = str(vertices[indices[face * 3 + (corner + 1) % 3]].snapped(Vector3.ONE * 0.0001))
			var key: String = a + ":" + b if a < b else b + ":" + a
			keys.append(key)
			if not edges.has(key): edges[key] = []
			edges[key].append(face)
		face_edges.append(keys)
	var selected: Dictionary = {}
	for face in edit["faces"]:
		if int(face) < face_edges.size(): selected[int(face)] = true
	for ring in absi(rings):
		var next: Dictionary = selected.duplicate()
		for face in selected:
			for key in face_edges[face]:
				if rings < 0 and edges[key].size() == 1: next.erase(face)
				for neighbor in edges[key]:
					if rings > 0: next[neighbor] = true
					elif not selected.has(neighbor): next.erase(face)
		selected = next
	result["faces"] = selected.keys()
	return result

static func nonempty(edit: Dictionary) -> bool:
	return not edit.is_empty() and not edit.get("pixels", edit.get("faces", [])).is_empty()
