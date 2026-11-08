extends RefCounted

const RenderingBudget = preload("res://scripts/builder/rendering_budget.gd")

static func make(library: RefCounted, id: String, world_mode: String, solid: bool=true,projection_pool: Node=null) -> Node:
	var asset: Dictionary = library.assets[id]
	if asset["mode"] == world_mode:
		var instance: Node=load(asset["path"]).instantiate()
		if not solid:
			var type: String="CollisionObject2D" if world_mode=="2d" else "CollisionObject3D"
			for body in [instance]+instance.find_children("*",type,true,false):
				if body is CollisionObject2D or body is CollisionObject3D:
					body.collision_layer=0
					body.collision_mask=0
		return instance
	var result: Node
	if world_mode == "2d":
		result = preload("res://scripts/builder/model_in_2d.gd").new()
		result.walk_collision = solid and asset.get("behavior", {}).get("collision", "box") == "mesh"
		if not solid: result.inherit_walk_profile=false
	else:
		result = preload("res://scripts/builder/sprite_in_3d.gd").new()
		result.walk_profile = asset.get("behavior", {}).get("walk", {}).duplicate(true)
		result.ground_tile = library.is_ground_tile(id)
		result.diamond_ground = asset["data"].get("ground_shape", "diamond") == "diamond"
	result.collidable=solid and asset.get("behavior",{}).get("collision","box")!="none"
	result.asset_path = asset["path"]
	RenderingBudget.prepare_projection(result,asset,projection_pool)
	return result

static func orient(instance: Node, direction: String, night: bool = false) -> void:
	if instance is Node2D or instance.has_method("mixed_bounds"):
		instance.direction = direction
		if instance is IsoObject or "night_mode" in instance: instance.night_mode = night
	else: instance.rotation_degrees.y = float(direction)

static func footprint(node: Node2D) -> PackedVector2Array:
	if node.has_method("ground_polygon"): return node.ground_polygon()
	return IsoMath.get_footprint_diamond(Vector2i.ZERO, node.footprint if node is IsoObject else Vector2i.ONE)

static func pose(instance: Node, item: Dictionary, night: bool = false) -> void:
	orient(instance, item["direction"], night)
	var angles: Vector3 = preload("res://scripts/builder/rotation.gd").euler(item)
	if instance.has_method("set_angles"): instance.set_angles(angles)
	elif instance is Node3D: instance.rotation_degrees = angles
	else: instance.rotation_degrees = float(item.get("angle", 0))
