extends RefCounted

# Reuses the resident's original body. A room closing must detach these actors
# before Exploration frees its transient room tree.
var visit_ref: WeakRef
var reservations: RefCounted
var attached: Dictionary={}
var notice: String=""
var actors: Dictionary={}
var travel: RefCounted

func _init(visit: Node,shared_reservations: RefCounted) -> void:
	visit_ref=weakref(visit);reservations=shared_reservations
	travel=preload("res://scripts/builder/resident_floor_travel.gd").new(self)
	visit.interior_closing.connect(detach_all)

func room_for(floor_uid: String) -> Node:
	var visit: Node=visit_ref.get_ref()
	if not is_instance_valid(visit) or not is_instance_valid(visit.interior):return null
	if visit.dimension=="2d" and visit.active_floor()!=floor_uid:return null
	return visit.room_world(floor_uid)

func share_room(world: Node) -> bool:
	if not world.has_meta("activity_reservations"):world.set_meta("activity_reservations",reservations);return true
	var current: RefCounted=world.get_meta("activity_reservations")
	if current==reservations:return true
	# Never discard an existing player interaction to bind a room late.
	if not current.entries.is_empty():notice="Finish this room's current interaction before residents can share its stations.";return false
	world.set_meta("activity_reservations",reservations);return true

func restore_pose(entry: Dictionary) -> void:
	var actor: Node=entry["actor"].get_ref()
	if not is_instance_valid(actor):return
	if actor is CharacterBody2D:
		actor.interaction_visual_offset=entry["visual"];actor.action=entry["action"];actor.direction=entry["direction"]
	else:
		actor.body.transform=entry["body"]
		for index in mini(actor.limbs.size(),entry["limbs"].size()):actor.limbs[index].transform=entry["limbs"][index]

func attach(identity: String,actor: Node,world: Node) -> void:
	if not attached.has(identity):
		var entry: Dictionary={"actor":weakref(actor),"parent":weakref(actor.get_parent()),"position":actor.position,"transform":actor.transform,"physics":actor.is_physics_processing(),"mask":actor.collision_mask,"layer":actor.collision_layer,"visible":actor.visible,"phase":""}
		if actor is CharacterBody2D:entry.merge({"visual":actor.interaction_visual_offset,"terrain":actor.terrain_visual_offset,"action":actor.action,"direction":actor.direction})
		else:entry.merge({"body":actor.body.transform,"limbs":actor.limbs.map(func(limb: Node3D):return limb.transform)})
		attached[identity]=entry
	if actor.get_parent()!=world.objects:
		restore_pose(attached[identity]);actor.reparent(world.objects,false)
		if actor is CharacterBody2D:actor.terrain_visual_offset=Vector2.ZERO
	actor.set_physics_process(false)

func detach(identity: String) -> void:
	travel.cancel(identity)
	if not attached.has(identity):return
	var entry: Dictionary=attached[identity];var actor: Node=entry["actor"].get_ref();var parent: Node=entry["parent"].get_ref()
	if is_instance_valid(actor):
		restore_pose(entry)
		if is_instance_valid(parent):actor.reparent(parent,false);actor.transform=entry["transform"];actor.teleport_to(entry["position"])
		actor.collision_layer=entry["layer"];actor.collision_mask=entry["mask"];actor.set_physics_process(entry["physics"]);actor.visible=entry["visible"]
		if actor is CharacterBody2D:actor.terrain_visual_offset=entry["terrain"]
	attached.erase(identity)

func detach_all() -> void:
	for identity in attached.keys():detach(identity)

func synchronize(scheduler: RefCounted,residents: Array,delta: float=0) -> bool:
	notice="";var visit: Node=visit_ref.get_ref();var keep: Dictionary={}
	actors.clear()
	for resident in residents:
		if is_instance_valid(resident.get("actor")):actors[resident["id"]]=weakref(resident["actor"])
	if not is_instance_valid(visit):detach_all();return false
	if visit.interior:
		var world: Node=visit.room_world()
		if is_instance_valid(world) and not share_room(world):return false
	for resident in residents:
		var identity: String=resident["id"];var actor: Node=resident.get("actor");var job: Dictionary=scheduler.result(identity)
		if not is_instance_valid(actor) or job.is_empty() or job["state"] in ["queued","complete","cancelled"] or job["building"]!=visit.interior_uid:continue
		if travel.states.has(identity):keep[identity]=true;continue
		if job.has("transport") or job.has("stair"):
			if travel.materialize(job):keep[identity]=true
			continue
		var world: Node=room_for(job["floor"])
		if not is_instance_valid(world) or not share_room(world):continue
		keep[identity]=true;attach(identity,actor,world)
		if attached[identity]["phase"]!=job["state"]:restore_pose(attached[identity]);attached[identity]["phase"]=job["state"]
		var point: Vector3=job["position"];var position: Variant=Vector2(point.x,point.y) if visit.dimension=="2d" else point
		if not actor.position.is_equal_approx(position):actor.teleport_to(position)
		actor.visible=true
		if actor is CharacterBody2D:world.terrain_presentation.present(actor)
		if job["state"]=="service":pose(actor,job["station"],world,visit.dimension,delta)
	for identity in attached.keys():
		if not keep.has(identity):detach(identity)
	return true

func pose(actor: Node,station: Dictionary,world: Node,dimension: String,delta: float) -> void:
	var seated: bool=station["kind"]=="seat";var raw: Vector3=station["point"];var facing_raw: Vector3=station["facing"]
	if dimension=="2d":
		var point: Vector2=world.objects.to_global(Vector2(raw.x,raw.y));var facing: Vector2=world.objects.to_global(Vector2(facing_raw.x,facing_raw.y))
		var prop: Node=world.instances.get(station["uid"]);var prop_sprite: Sprite2D=prop.get_node_or_null("Sprite2D") if is_instance_valid(prop) else null
		if prop_sprite and "terrain_visual_offset" in prop:
			world.terrain_presentation.present(prop,float(station["item"]["position"][2]))
			var elevation: Vector2=prop_sprite.global_transform.basis_xform(prop.terrain_visual_offset);point+=elevation;facing+=elevation
		var actor_sprite: Sprite2D=actor.get_node("Sprite2D");var ground: Vector2=actor_sprite.global_transform.basis_xform(actor.terrain_visual_offset)
		var heading: Vector2=facing-(point if seated else actor.global_position+ground)
		actor.action="sit" if seated else "wave"
		if heading.length_squared()>.0001:actor.direction=("NE" if heading.y<0 else "SE") if heading.x>=0 else ("NW" if heading.y<0 else "SW")
		if seated:
			var sprite: Sprite2D=actor.get_node("Sprite2D");actor.interaction_visual_offset=sprite.global_transform.affine_inverse().basis_xform(point+Vector2(0,.85*8)-actor.global_position)-actor.terrain_visual_offset
		actor._update_animation(delta)
	else:
		var point: Vector3=world.objects.to_global(raw);var facing: Vector3=world.objects.to_global(facing_raw)
		if seated:actor.body.global_position=point-Vector3.UP*.85
		var heading: Vector3=facing-(point if seated else actor.global_position)
		if Vector2(heading.x,heading.z).length()>.01:actor.body.global_rotation.y=atan2(-heading.x,-heading.z)
		for index in actor.limbs.size():actor.limbs[index].rotation.x=(.95 if index>=2 else .12) if seated else (.7 if index<2 else 0.0)

func move(job: Dictionary,proposal: Vector3,delta: float) -> Vector3:
	if not attached.has(job["resident"]):return proposal
	var actor: Node=attached[job["resident"]]["actor"].get_ref();var world: Node=room_for(job["floor"])
	if not is_instance_valid(actor) or not is_instance_valid(world) or delta<=0:return job["position"]
	if actor is CharacterBody2D:
		var shift: Vector2=Vector2(proposal.x,proposal.y)-actor.position;var factor: float=minf(1,shift.length()/maxf(.000001,actor.move_speed*delta));actor.move_character(delta,shift.normalized()*factor);actor._update_animation(delta)
		return Vector3(actor.position.x,actor.position.y,0)
	var shift: Vector3=world.objects.global_basis*(proposal-actor.position);shift.y=0;var factor: float=minf(1,shift.length()/maxf(.000001,actor.move_speed*delta))
	# The same physical walker accelerates and brakes. Reduce desired speed
	# before the exact waypoint so its inertia cannot oscillate past it forever.
	var goal: Vector3=job.get("waypoint",proposal);var remaining: Vector3=world.objects.global_basis*(goal-actor.position);remaining.y=0
	factor=minf(factor,remaining.length()*6/maxf(.000001,actor.move_speed));actor.move_character(delta,shift.normalized()*factor)
	return actor.position

func close() -> void:
	detach_all();actors.clear();var visit: Node=visit_ref.get_ref()
	if is_instance_valid(visit) and visit.interior_closing.is_connected(detach_all):visit.interior_closing.disconnect(detach_all)
