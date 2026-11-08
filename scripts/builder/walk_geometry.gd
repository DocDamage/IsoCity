extends RefCounted

static var shapes: Dictionary = {}
static var sections: Dictionary = {}

# Architectural collision follows the model instead of sealing every doorway with a box.
static func prepare(instance: Node3D, asset: String, library: RefCounted = null) -> void:
	if instance.has_method("mixed_bounds"):
		if instance.inherit_walk_profile:
			var profile: Dictionary = preload("res://scripts/builder/asset_behavior.gd").for_asset(asset, library).get("walk", {})
			if profile != instance.walk_profile:
				instance.walk_profile = profile.duplicate(true)
				instance.last_frame = ""
				instance.update_visual()
		return
	if not instance is StaticBody3D or instance.has_meta("precise_collision"): return
	if preload("res://scripts/builder/asset_behavior.gd").for_asset(asset, library).get("collision", "box") != "mesh": return
	var meshes: Array = instance.find_children("*", "MeshInstance3D", true, false)
	var additions: int = 0
	for mesh in meshes:
		if not mesh.mesh: continue
		var resource: Mesh = mesh.mesh
		var id: int = resource.get_instance_id()
		if not shapes.get(id) is Dictionary:
			if shapes.size() >= 256: shapes.erase(shapes.keys()[0])
			shapes[id] = {"mesh": resource, "shape": resource.create_trimesh_shape()}
		if not shapes[id]["shape"]: continue
		var collision := CollisionShape3D.new()
		collision.name = "WalkSurface"
		collision.set_meta("walk_surface", true)
		collision.shape = shapes[id]["shape"]
		var transform_value: Transform3D = mesh.transform
		var ancestor: Node = mesh.get_parent()
		while ancestor != instance and ancestor is Node3D:
			transform_value = ancestor.transform * transform_value
			ancestor = ancestor.get_parent()
		collision.transform = transform_value
		instance.add_child(collision, true)
		additions += 1
	if additions:
		for child in instance.get_children():
			if child is CollisionShape3D and not child.get_meta("walk_surface", false): child.disabled = true
	instance.set_meta("precise_collision", true)

static func prepare_2d(instance: Node2D, asset: String, library: RefCounted = null) -> void:
	if instance.has_method("configure_walk_collision") and instance.inherit_walk_profile:
		instance.configure_walk_collision(preload("res://scripts/builder/asset_behavior.gd").for_asset(asset, library).get("collision", "box") == "mesh")

static func clip_height(polygon: Array[Vector3], height: float, above: bool) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if polygon.is_empty(): return result
	for i in polygon.size():
		var a: Vector3 = polygon[i]
		var b: Vector3 = polygon[(i + 1) % polygon.size()]
		var inside_a: bool = a.y >= height if above else a.y <= height
		var inside_b: bool = b.y >= height if above else b.y <= height
		if inside_a: result.append(a)
		if inside_a != inside_b and not is_zero_approx(b.y - a.y): result.append(a.lerp(b, (height - a.y) / (b.y - a.y)))
	return result

static func projected_segments(root: Node3D, low: float, high: float, view_basis: Basis, pixels_per_unit: float) -> PackedVector2Array:
	var output := PackedVector2Array()
	var edges: Dictionary = {}
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = preload("res://scripts/builder/part_colors.gd").original_mesh(node)
		if not mesh: continue
		var pose: Transform3D = root.transform * root.global_transform.affine_inverse() * node.global_transform
		for surface in mesh.get_surface_count():
			if mesh is ArrayMesh and mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES: continue
			var arrays: Array = mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = preload("res://scripts/builder/part_colors.gd").indices_for(arrays)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for face in indices.size() / 3:
				var polygon: Array[Vector3] = []
				for corner in 3: polygon.append(pose * vertices[indices[face * 3 + corner]])
				polygon = clip_height(clip_height(polygon, low, true), high, false)
				var flat := PackedVector2Array()
				for point in polygon:
					var projected: Vector3 = view_basis.inverse() * Vector3(point.x, 0, point.z)
					flat.append(Vector2(projected.x, -projected.y) * pixels_per_unit)
				if flat.size() < 2: continue
				for i in flat.size():
					var a: Vector2 = flat[i].snapped(Vector2.ONE * 0.001)
					var b: Vector2 = flat[(i + 1) % flat.size()].snapped(Vector2.ONE * 0.001)
					if a.distance_to(b) < 0.001: continue
					var key: String = str(a) + ":" + str(b) if a.x < b.x or (is_equal_approx(a.x, b.x) and a.y < b.y) else str(b) + ":" + str(a)
					if edges.has(key): continue
					edges[key] = true
					output.append(a)
					output.append(b)
	return output
