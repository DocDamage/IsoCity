extends RefCounted

const Raster = preload("res://scripts/builder/citizen_obstacles_2d.gd")

static func append(node: Node, obstacles: Array[Rect2], layer: Callable, ground: Callable, relative: Variant = null, clearance: float = .4) -> void:
	if node is CharacterBody2D or node is CharacterBody3D: return
	if node is CollisionShape2D and node.shape and not node.disabled and node.get_parent() is StaticBody2D and layer.call(node.get_parent()):
		var shape: Shape2D = node.shape
		var pose: Transform2D = node.global_transform if relative == null else relative * node.global_transform
		if shape is ConcavePolygonShape2D:
			obstacles.append_array(Raster.segments(Raster.metric(shape.segments,pose)))
		elif shape is ConvexPolygonShape2D:
			obstacles.append_array(Raster.polygon(Raster.metric(shape.points,pose)))
		else:
			var rect: Rect2 = pose * shape.get_rect()
			obstacles.append(Rect2(rect.position/Vector2(16,8),rect.size/Vector2(16,8)))
	elif node is CollisionPolygon2D and not node.disabled and node.get_parent() is StaticBody2D and layer.call(node.get_parent()) and node.polygon.size() > 2:
		var pose: Transform2D = node.global_transform if relative == null else relative * node.global_transform
		var points: PackedVector2Array = Raster.metric(node.polygon,pose)
		if node.build_mode == CollisionPolygon2D.BUILD_SEGMENTS:
			var edges := PackedVector2Array()
			for index in points.size():
				edges.append(points[index])
				edges.append(points[(index+1)%points.size()])
			obstacles.append_array(Raster.segments(edges))
		else:
			obstacles.append_array(Raster.polygon(points))
	elif node is CollisionShape3D and node.shape and not node.disabled and node.get_parent() is StaticBody3D and layer.call(node.get_parent()):
		var pose: Transform3D = node.global_transform if relative == null else relative * node.global_transform
		var bounds: AABB = pose * node.shape.get_debug_mesh().get_aabb()
		var level: float = ground.call(Vector2(bounds.get_center().x,bounds.get_center().z))
		if bounds.end.y > level+clearance and bounds.position.y < level+1.8:
			obstacles.append(Rect2(bounds.position.x,bounds.position.z,bounds.size.x,bounds.size.z))
	for child in node.get_children(): append(child,obstacles,layer,ground,relative,clearance)
