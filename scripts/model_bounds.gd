extends RefCounted

## Bounds in the prefab root's coordinate system, including nested model transforms.
static func get_bounds(root: Node3D) -> AABB:
	if root.has_method("mixed_bounds"): return root.mixed_bounds()
	var boxes: Array[AABB] = []
	for child in root.get_children():
		if child is Node3D:
			_collect(child, Transform3D.IDENTITY, boxes)
	var bounds: AABB = AABB()
	for index in boxes.size():
		bounds = boxes[index] if index == 0 else bounds.merge(boxes[index])
	return bounds

static func contact_bounds(root: Node3D) -> AABB:
	var authored: Array=root.get_meta("authored_footprint",[])
	if authored.size()==6: return AABB(Vector3(authored[0],authored[1],authored[2]),Vector3(authored[3],authored[4],authored[5]))
	var whole: AABB = get_bounds(root)
	var vertices: Array[Vector3] = []
	for child in root.get_children():
		if child is Node3D: _contact_vertices(child, Transform3D.IDENTITY, vertices)
	var low := Vector3(INF, whole.position.y, INF)
	var high := Vector3(-INF, whole.position.y, -INF)
	var band: float = maxf(0.015, whole.size.y * 0.015)
	for point in vertices:
		if point.y > whole.position.y + band: continue
		low.x = minf(low.x, point.x); low.z = minf(low.z, point.z)
		high.x = maxf(high.x, point.x); high.z = maxf(high.z, point.z)
	if not low.is_finite() or high.x - low.x < 0.001 or high.z - low.z < 0.001: return whole
	return AABB(low, Vector3(high.x - low.x, 0, high.z - low.z))

static func _contact_vertices(node: Node3D, parent_transform: Transform3D, vertices: Array[Vector3]) -> void:
	var transform: Transform3D = parent_transform * node.transform
	if node is MeshInstance3D and node.mesh:
		for surface in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			if arrays[Mesh.ARRAY_VERTEX] != null:
				for point in arrays[Mesh.ARRAY_VERTEX]: vertices.append(transform * point)
	for child in node.get_children():
		if child is Node3D: _contact_vertices(child, transform, vertices)

static func _collect(node: Node3D, parent_transform: Transform3D, boxes: Array[AABB]) -> void:
	var local_transform: Transform3D = parent_transform * node.transform
	if node is MeshInstance3D and node.mesh:
		boxes.append(local_transform * node.mesh.get_aabb())
	for child in node.get_children():
		if child is Node3D:
			_collect(child, local_transform, boxes)
