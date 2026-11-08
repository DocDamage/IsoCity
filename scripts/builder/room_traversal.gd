extends Node

var visit: Node
var actor: Node
var saved_filter: Callable
var saved_safe: Callable
var world: Node
var floor_uid: String=""

func configure(owner_visit: Node,motion_filter: Callable,position_safe: Callable) -> void:
	visit=owner_visit; actor=visit.player; saved_filter=motion_filter; saved_safe=position_safe
	process_physics_priority=-100
	refresh()

func refresh() -> void:
	var uid: String=visit.active_floor(); var next: Node=visit.room_world(uid)
	if world!=next or floor_uid!=uid: actor.set_meta("terrain_blocked","")
	floor_uid=uid
	world=next
	actor.terrain_motion_filter=filter_motion; actor.terrain_position_safe=safe_position

func enabled() -> bool:
	return is_instance_valid(world) and world.terrain_traversal.enabled

func walk_allowed() -> bool:
	if is_instance_valid(world) and not preload("res://scripts/builder/layers.gd").shown(world.data_state,"Ground"):
		actor.set_meta("terrain_blocked","Show Ground on this floor before walking."); return false
	if not enabled(): actor.set_meta("terrain_blocked",""); return true
	return true

func safe_position(point: Variant) -> bool:
	if not walk_allowed() or (enabled() and not world.terrain_traversal.safe_position(point)): return false
	if not enabled() or not actor is CharacterBody3D: return true
	var local: Vector3=world.to_local(point); var metric:=Vector2(local.x,local.z)
	if absf(local.y-world.terrain_traversal.sample_at(metric)["height"])<=.4 or preload("res://scripts/builder/floor_terrain_plan.gd").contains(world.terrain_traversal.exclusions,metric): return true
	# A remembered point may belong to another storey. Raised props are valid
	# when their supporting collider belongs to this room, not a lower world.
	var query:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*.12,point-Vector3.UP*.45,actor.collision_mask,[actor.get_rid()])
	var hit: Dictionary=actor.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return false
	for owner_node in [world.objects,world.terrain,world.road_node,world.floor_surface]:
		if is_instance_valid(owner_node) and (owner_node==hit["collider"] or owner_node.is_ancestor_of(hit["collider"])): return true
	return false

func filter_motion(from: Variant,motion: Variant) -> Variant:
	if not walk_allowed(): return Vector2.ZERO if motion is Vector2 else Vector3.ZERO
	var filtered: Variant=world.terrain_traversal.filter_motion(from,motion,weakref(actor)) if enabled() else motion
	if actor is CharacterBody3D and is_instance_valid(visit.interior.floor_stack):filtered=visit.interior.floor_stack.filter_stair_motion(from,filtered)
	return filtered

func align_entry() -> bool:
	refresh()
	if not walk_allowed() or (enabled() and not world.terrain_traversal.safe_position(actor.global_position)): return false
	if enabled() and actor is CharacterBody3D:
		var local: Vector3=world.to_local(actor.global_position)
		var height: float=world.terrain_traversal.sample_at(Vector2(local.x,local.z))["height"]+.025
		local.y=height if absf(local.y)<=.25 else maxf(local.y,height)
		actor.teleport_to(actor.get_parent().to_local(world.to_global(local)))
	return true

func travelling() -> bool:
	var stack: Node=visit.interior.floor_stack
	if not stack: return false
	if visit.dimension=="2d" and not stack.travel.is_empty(): return true
	for lift in stack.lifts.values():
		if lift.rider: return true
	return false

func _physics_process(_delta: float) -> void:
	if is_instance_valid(visit) and visit.interior: refresh()

func _process(_delta: float) -> void:
	if not is_instance_valid(visit) or not visit.interior or not is_instance_valid(world): return
	if actor is CharacterBody2D and not travelling(): world.terrain_presentation.present(actor)

func release() -> void:
	if not is_instance_valid(actor): return
	if actor is CharacterBody2D and is_instance_valid(world): world.terrain_presentation.release_actor(actor)
	actor.terrain_motion_filter=saved_filter if saved_filter.is_valid() else Callable()
	actor.terrain_position_safe=saved_safe if saved_safe.is_valid() else Callable()
	actor.set_meta("terrain_blocked","")
