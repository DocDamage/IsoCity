extends Node
const Plan=preload("res://scripts/builder/terrain_plan.gd")
const Traffic=preload("res://scripts/builder/traffic_plan.gd")
const MAX_DEPTH: float=Plan.WADING_DEPTH
const MAX_SLOPE: float=Plan.WALKABLE_NORMAL
var data: Dictionary={}
var heights: Dictionary={}
var waters: Dictionary={}
var world: Node
var objects: Node
var player: Node
var exploration: Node
var actors: Dictionary={}
var enabled: bool=false
var start_allowed: bool=true
var last_inside: bool=false
var exclusions: Array=[]

func sample_at(point: Vector2) -> Dictionary:
	return {"height":0.0,"normal":Vector3.UP,"inside":true} if preload("res://scripts/builder/floor_terrain_plan.gd").contains(exclusions,point) else Plan.sample(data,point,heights)
func _ready() -> void: get_tree().node_added.connect(added)
func configure(source: Dictionary,parent: Node,walker: Node,visit: Node) -> void:
	data=source; objects=parent; world=parent.get_parent(); player=walker; exploration=visit
	heights=Plan.lookup(source); waters=Plan.lookup(source,true); enabled=Plan.settings(source)["enabled"]
	for id in actors.keys():
		var actor: Node=actors[id].get_ref()
		if not is_instance_valid(actor): actors.erase(id)
		elif not enabled: actor.terrain_motion_filter=Callable(); actor.terrain_position_safe=Callable(); actor.set_meta("terrain_blocked","")
	if not enabled: actors.clear(); return
	added(player)
	for actor in objects.find_children("*","",true,false): added(actor)
func added(actor: Node) -> void:
	if not enabled or not is_instance_valid(objects) or not "terrain_motion_filter" in actor: return
	if actor!=player and not objects.is_ancestor_of(actor): return
	var id: int=actor.get_instance_id()
	if not actors.has(id): actor.tree_exiting.connect(func(): actors.erase(id),CONNECT_ONE_SHOT)
	actors[id]=weakref(actor)
	actor.terrain_motion_filter=filter_motion.bind(weakref(actor))
	actor.terrain_position_safe=safe_position
func active() -> bool:
	return enabled and Plan.Layers.shown(data,"Ground") and (not is_instance_valid(exploration) or exploration.interior==null)
func metric(point: Variant) -> Vector2:
	var local: Variant=world.to_local(point)
	return Traffic.metric([local.x,local.y,0],"2d") if point is Vector2 else Vector2(local.x,local.z)
func depth(point: Vector2) -> float:
	if preload("res://scripts/builder/floor_terrain_plan.gd").contains(exclusions,point): return 0
	var cell:=Vector2i((point/Plan.CELL_SIZE).floor()); var record: Dictionary=waters.get(Plan.key(cell),{})
	return maxf(0,float(record["level"])-Plan.sample(data,point,heights)["height"]) if not record.is_empty() else 0.0
func safe_position(point: Variant) -> bool:
	if not active(): return true
	var ground: Vector2=metric(point); var surface: Dictionary=sample_at(ground)
	return ground.is_finite() and depth(ground)<=MAX_DEPTH and surface["normal"].y>=MAX_SLOPE
func start_candidate(point: Vector2,original: Variant,keep_height: bool) -> Variant:
	var surface: Dictionary=sample_at(point)
	if depth(point)>MAX_DEPTH or surface["normal"].y<MAX_SLOPE: return null
	for offset in [Vector2(.4,0),Vector2(-.4,0),Vector2(0,.4),Vector2(0,-.4)]:
		var edge: Dictionary=sample_at(point+offset)
		if depth(point+offset)>MAX_DEPTH or edge["normal"].y<MAX_SLOPE or absf(edge["height"]-surface["height"])>.3: return null
	if original is Vector2:
		var raw: Array=Traffic.world(point,"2d"); var global: Vector2=world.to_global(Vector2(raw[0],raw[1]))
		return global if player.clear_at(global) else null
	var level: float=surface["height"]
	var query:=PhysicsRayQueryParameters3D.create(world.to_global(Vector3(point.x,level+2.2,point.y)),world.to_global(Vector3(point.x,level-1,point.y)),player.collision_mask,[player.get_rid()])
	var hit: Dictionary=player.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		if hit["normal"].dot(world.global_basis.y.normalized())<MAX_SLOPE: return null
		level=world.to_local(hit["position"]).y
	elif not surface["inside"] and not Rect2(-80,-80,160,160).has_point(point): return null
	# New terrain bodies may enter the physics broad phase on the first tick;
	# the analytical surface supplies the same supported height during startup.
	var y: float=maxf(world.to_local(original).y,level+.025) if keep_height else level+.025
	var global: Vector3=world.to_global(Vector3(point.x,y,point.y)); var pose: Transform3D=player.global_transform; pose.origin=global
	return global if player.clear_at(pose,true) else null
func ensure_start() -> bool:
	last_inside=is_instance_valid(exploration) and exploration.interior!=null
	if enabled and not Plan.Layers.shown(data,"Ground") and (not is_instance_valid(exploration) or exploration.interior==null):
		start_allowed=false; player.set_meta("terrain_blocked","Show Ground before entering terrain walking mode."); return false
	if not active(): start_allowed=true; player.set_meta("terrain_blocked",""); return true
	var original: Variant=player.global_position; var center: Vector2=metric(original); var candidate: Variant=start_candidate(center,original,true)
	if candidate==null:
		for radius in [.5,1.0,2.0,4.0,8.0,16.0,32.0,64.0]:
			for turn in 32:
				candidate=start_candidate(center+Vector2.RIGHT.rotated(turn*TAU/32)*radius,original,false)
				if candidate!=null: break
			if candidate!=null: break
	if candidate==null:
		var area: Rect2i=Plan.bounds(data); var best: float=INF
		for x in range(area.position.x,area.end.x):
			for z in range(area.position.y,area.end.y):
				var point:=Vector2(x+.5,z+.5)*Plan.CELL_SIZE; var distance: float=center.distance_squared_to(point)
				if distance>=best: continue
				var found: Variant=start_candidate(point,original,false)
				if found!=null: candidate=found; best=distance
	if candidate==null:
		start_allowed=false; player.set_meta("terrain_blocked","No dry supported walking start nearby · return to Build and create a safe landing."); return false
	if candidate.distance_to(original)>.001: player.teleport_to(player.get_parent().to_local(candidate))
	start_allowed=true; player.set_meta("terrain_blocked",""); return true
func walk_allowed() -> bool:
	if not enabled: return true
	var inside: bool=is_instance_valid(exploration) and exploration.interior!=null
	if inside!=last_inside or not inside and not Plan.Layers.shown(data,"Ground"): return ensure_start()
	return start_allowed
func blocked(from: Variant,to: Variant) -> String:
	var a: Vector2=metric(from); var b: Vector2=metric(to)
	if not a.is_finite() or not b.is_finite(): return "Terrain position is invalid."
	var count: int=maxi(1,ceili(a.distance_to(b)/.25))
	if count>512: return "Movement exceeds the terrain sampling range."
	var previous: Dictionary=sample_at(a); var previous_depth: float=depth(a)
	for index in range(1,count+1):
		var point: Vector2=a.lerp(b,float(index)/count); var surface: Dictionary=sample_at(point); var wet: float=depth(point)
		# An actor already caught by imported/edited water can retreat to shore.
		if wet>MAX_DEPTH and (previous_depth<=MAX_DEPTH or wet>previous_depth+.00001): return "Deep water · choose a dry or shallow route."
		if from is Vector2:
			if absf(surface["height"]-previous["height"])>a.distance_to(b)/count*1.036+.35: return "Terrain edge is too high to cross."
			if surface["normal"].y<MAX_SLOPE and surface["height"]>previous["height"]+.00001: return "Slope is too steep · walk around or smooth the bank."
		previous=surface; previous_depth=wet
	return ""
func filter_motion(from: Variant,motion: Variant,reference: WeakRef) -> Variant:
	var actor: Node=reference.get_ref()
	if not is_instance_valid(actor): return motion
	if not active(): actor.set_meta("terrain_blocked",""); return motion
	var reason: String=blocked(from,from+motion)
	actor.set_meta("terrain_blocked",reason)
	if reason.is_empty(): return motion
	# Preserve movement along a shoreline or cliff rather than freezing both axes.
	var first: Variant=Vector2(motion.x,0) if motion is Vector2 else Vector3(motion.x,0,0)
	var second: Variant=Vector2(0,motion.y) if motion is Vector2 else Vector3(0,0,motion.z)
	for axis in [first,second]:
		if not axis.is_zero_approx() and blocked(from,from+axis).is_empty(): return axis
	return Vector2.ZERO if motion is Vector2 else Vector3.ZERO
