extends Node

const Plan = preload("res://scripts/builder/pet_plan.gd")
const Props = Plan.Props
const Navigator = preload("res://scripts/builder/pet_navigation.gd")
const Actor = preload("res://scripts/builder/pet_actor.gd")
const View = preload("res://scripts/builder/pet_commands.gd")
const REPLAN = .55
const RETRY_LIMIT = 3

var exploration: Node
var ui_parent: Node
var authored_root: Callable
var owner_key: Callable
var interact_label: Callable
var source: Dictionary = {}
var config: Dictionary = {}
var companion_owner: String = ""
var nav := Navigator.new()
var actor := Actor.new()
var view: RefCounted
var motion: String = "stay"
var pose: String = "sit"
var status: String = ""
var last_scope: String = ""
var last_point: Variant
var navigation_scope: String = ""
var signature: int = -1
var nav_dirty: bool = true
var inspection: float = 0
var elapsed: float = 0
var retries: int = 0
var last_blocked_at: Vector2 = Vector2.INF
var stall: float = 0
var path := PackedVector2Array()
var index: int = 0
var destination: Vector2 = Vector2.INF
var spawn_wait: float = 0
var paused_for_owner: bool = false

func root_data() -> Dictionary:
	return authored_root.call() if authored_root.is_valid() else source

func configure(data: Dictionary) -> void:
	source = data
	nav_dirty = true
	if not Plan.settings(root_data())["enabled"]: reset()

func reset() -> void:
	close()
	if is_instance_valid(actor.body): actor.body.free()
	actor = Actor.new()
	config = {}
	companion_owner = ""
	last_scope = ""
	last_point = null
	navigation_scope = ""
	signature = -1
	status = ""
	spawn_wait = 0
	paused_for_owner = false
	motion = "stay"
	pose = "sit"
	clear_path()

func clear_path() -> void:
	path = PackedVector2Array()
	index = 0
	destination = Vector2.INF
	elapsed = 0
	retries = 0
	last_blocked_at = Vector2.INF
	stall = 0

func has_menu() -> bool:
	return view != null and view.overlay.visible

func close() -> bool:
	if not has_menu(): return false
	view.hide_panel()
	return true

func disable_walk() -> void:
	close()
	if is_instance_valid(actor.body): actor.body.hide()

func title() -> String:
	var id: String = config.get("asset","")
	return exploration.library.assets.get(id,{}).get("name",id.trim_prefix("2d:")).replace("_"," ") if not id.is_empty() else "Pet companion"

func prompt() -> String:
	if config.get("enabled",false) and not status.is_empty(): return title()+" · "+status
	return ""

func interaction(role: String) -> String:
	var key: String = interact_label.call() if interact_label.is_valid() else "E"
	return key+" · "+("Dog station" if role == "park" else title()+" commands")

func suspended(context: Dictionary) -> String:
	if not is_instance_valid(exploration.player): return "Waiting for its owner."
	if not exploration.driving.active.is_empty(): return "Waiting while you are in the vehicle."
	if exploration.entering: return "Waiting at its current floor or outdoor spot."
	if is_instance_valid(exploration.room_traversal) and exploration.room_traversal.travelling():
		return "Waiting while you change floors."
	if context["scope"] != Plan.home_scope(config):
		return "Waiting at home. Return to the assigned floor." if not config["building"].is_empty() else "Waiting outdoors."
	return ""

func refresh_navigation(context: Dictionary, delta: float) -> void:
	inspection -= delta
	var scope_changed: bool = context["scope"] != navigation_scope or context["world"] != nav.scope_world
	if not nav_dirty and not scope_changed and inspection > 0: return
	inspection = .5
	var data: Dictionary = context["data"]
	var passages: Array = Navigator.FloorTerrain.passages(exploration.owned_room,exploration.active_floor()) if exploration.interior else []
	var next: int = hash([context["world"].get_instance_id(),context["scope"],data.get("objects",[]),
		data.get("layers",{}),data.get("terrain",{}),data.get("terrain_vertices",[]),data.get("water_cells",[]),passages])
	if nav_dirty or scope_changed or next != signature:
		signature = next
		navigation_scope = context["scope"]
		nav_dirty = false
		context["passages"] = passages
		nav.configure(context,exploration.dimension)
		path = PackedVector2Array()
		index = 0
		destination = Vector2.INF

func fixture(context: Dictionary, role: String) -> Variant:
	var key: String = "home" if role == "rest" else "park"
	var record: Dictionary = Plan.object(context["data"],config.get(key,""))
	if not Plan.fixture(record,role) or not Plan.Utility.availability(record,exploration.library,context["data"]).is_empty(): return null
	for point in Plan.fixture_points(record,role,exploration.library,exploration.dimension):
		if nav.available(point) and (not is_instance_valid(actor.body) or fits(nav.position(point))): return point
	return null

func fits(position: Variant) -> bool:
	var body: Node = actor.body
	var excluded: Array[RID] = [body.get_rid(),exploration.player.get_rid()]
	if exploration.dimension == "2d":
		var shape: CollisionShape2D = body.get_node("CollisionShape2D")
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = shape.shape
		query.transform = body.global_transform * shape.transform
		query.transform.origin += position-body.global_position
		query.collision_mask = body.collision_mask
		query.exclude = excluded
		return body.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty()
	var collider: CollisionShape3D = body.get_child(0)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collider.shape
	query.transform = body.global_transform * collider.transform
	query.transform.origin += position-body.global_position
	query.collision_mask = body.collision_mask
	query.exclude = excluded
	return body.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func place(context: Dictionary, home: Vector2) -> bool:
	var parent: Node = context["world"].get_node_or_null("Objects")
	if "objects" in context["world"]: parent = context["world"].objects
	if not is_instance_valid(parent): return false
	var body: Node = actor.create(exploration.library.assets[config["asset"]],parent,exploration.dimension)
	body.add_collision_exception_with(exploration.player)
	body.set_meta("pet_owner",companion_owner)
	body.set_meta("pet_asset",config["asset"])
	var options: Array = [last_point] if last_scope == context["scope"] and last_point != null else [home,home+Vector2(.5,0),home+Vector2(-.5,0),home+Vector2(0,.5),home+Vector2(0,-.5)]
	for point in options:
		if nav.safe(point) and fits(nav.position(point)):
			body.global_position = nav.position(point)
			last_scope = context["scope"]
			last_point = point
			actor.animate(pose,0)
			return true
	body.free()
	actor = Actor.new()
	return false

func owner_point() -> Vector2:
	return nav.metric(exploration.player.global_position)

func nearby() -> Dictionary:
	if (not exploration.enabled or exploration.entering or exploration.photo.active or not is_instance_valid(actor.body)
		or not actor.body.is_visible_in_tree() or not exploration.driving.active.is_empty()): return {}
	var context: Dictionary = Props.context(exploration)
	if not suspended(context).is_empty(): return {}
	var player_position: Variant = exploration.player.global_position
	var choices: Array = []
	for role in ["park","rest"]:
		var point: Variant = fixture(context,role)
		if point != null: choices.append([role,nav.position(point)])
	choices.append(["pet",actor.body.global_position])
	var best: Dictionary = {}
	for choice in choices:
		var difference: Variant = choice[1]-player_position
		var gap: float = Vector2(difference.x/16,difference.y/8).length() if exploration.dimension == "2d" else difference.length()
		if gap <= 2.1 and difference.length() < best.get("distance",INF) and (gap < .01 or Props.reachable(exploration,exploration.player,choice[1])):
			best = {"role":choice[0],"distance":difference.length()}
			if choice[0] == "park" and gap < .4: return best
	return best

func open(candidate: Dictionary) -> void:
	if candidate.is_empty(): return
	if view == null: view = View.new(self)
	view.open(candidate["role"] == "park")

func command(request: String) -> void:
	if request not in ["follow","come","stay","rest","home","practice"]: return
	if not is_instance_valid(actor.body) or not suspended(Props.context(exploration)).is_empty(): return
	if request == "practice" and fixture(Props.context(exploration),"park") == null: return
	motion = request
	pose = "idle"
	clear_path()
	close()
	status = "Waiting here." if request == "stay" else "Finding a safe route."

func plan_route(from: Vector2, desired: Vector2, moving: bool) -> bool:
	var targets: Array = [desired]
	if moving:
		var toward: Vector2 = (from-desired).normalized()
		if toward.is_zero_approx(): toward = Vector2.DOWN
		targets = []
		for angle in [0.0,.8,-.8,1.6,-1.6,PI]: targets.append(desired+toward.rotated(angle)*1.35)
	for point in targets:
		if not nav.safe(point) or not fits(nav.position(point)): continue
		var route: PackedVector2Array = nav.path(from,point)
		if route.is_empty(): continue
		path = route
		index = 0
		destination = desired
		return true
	return false

func arrived() -> void:
	match motion:
		"come","home": motion = "stay"; pose = "idle"; status = "Waiting here."
		"rest": motion = "stay"; pose = "sit"; status = "Resting at home."
		"practice": motion = "stay"; pose = "sit"; status = "Waiting at the dog station."
		"follow": status = "Following you."
	path = PackedVector2Array()

func blocked(at: Vector2) -> void:
	path = PackedVector2Array()
	last_blocked_at = at
	status = "Checking for a safe route."
	if retries >= RETRY_LIMIT:
		motion = "blocked"
		status = "Waiting for a clear route. Use Come here to retry."

func step(delta: float) -> void:
	var data: Dictionary = root_data()
	var next: Dictionary = Plan.settings(data)
	if not next["enabled"]:
		if not config.is_empty() or is_instance_valid(actor.body): reset()
		return
	if not exploration.enabled:
		disable_walk()
		return
	var identity: String = owner_key.call() if owner_key.is_valid() else "local"
	if next != config or identity != companion_owner:
		reset()
		config = next
		companion_owner = identity
	if companion_owner.is_empty() or not is_instance_valid(exploration.player):
		status = "Waiting for its owner."
		close()
		return
	var issue: String = Plan.eligible(config,data,exploration.library)
	if not issue.is_empty():
		status = issue
		if is_instance_valid(actor.body): actor.body.hide()
		return
	var context: Dictionary = Props.context(exploration)
	if context["world"] == null: return
	var pause: String = suspended(context)
	if not pause.is_empty():
		status = pause
		paused_for_owner = true
		if is_instance_valid(actor.body):
			actor.body.visible = context["scope"] == last_scope
			actor.animate("idle",delta)
		close()
		clear_path()
		return
	if paused_for_owner:
		paused_for_owner = false
		status = "Waiting here." if motion == "stay" else "Finding a safe route."
	if exploration.photo.active:
		close()
		return
	refresh_navigation(context,delta)
	var home: Variant = fixture(context,"rest")
	if home == null:
		status = "Show the home resting mat and clear its approach."
		if is_instance_valid(actor.body): actor.body.hide()
		return
	if not is_instance_valid(actor.body):
		spawn_wait = maxf(0,spawn_wait-delta)
		if spawn_wait > 0: return
		if not place(context,home):
			spawn_wait = .75
			status = "The resting spot is obstructed or flooded."
			return
		status = "Resting at home." if pose == "sit" else "Waiting here."
	actor.body.show()
	var at: Vector2 = nav.metric(actor.body.global_position)
	if not nav.safe(at):
		actor.animate("idle",delta)
		status = "Waiting for dry, level ground."
		path = PackedVector2Array()
		return
	if has_menu() or motion in ["stay","blocked"]:
		actor.animate(pose,delta)
		return
	var target: Vector2 = owner_point()
	var moving: bool = motion in ["come","follow"]
	var gap: float = target.distance_to(at)
	if moving and gap > config["leash"]:
		clear_path()
		status = "Out of range. Come closer to your pet."
		actor.animate("idle",delta)
		return
	if moving and exploration.dimension == "3d" and absf(exploration.player.global_position.y-nav.position(target).y) > .85:
		status = "Waiting on this walking surface."
		actor.animate("idle",delta)
		return
	if not moving:
		var point: Variant = fixture(context,"park" if motion == "practice" else "rest")
		if point == null:
			motion = "blocked"
			status = "The destination is no longer available."
			return
		target = point
	if (moving and gap < 1.55) or (not moving and at.distance_to(target) < Plan.ARRIVAL):
		arrived()
		actor.animate(pose,delta)
		return
	elapsed = maxf(0,elapsed-delta)
	if elapsed <= 0 and (path.is_empty() or destination.distance_to(target) > .75):
		elapsed = REPLAN
		if not plan_route(at,target,moving):
			retries += 1
			blocked(at)
			actor.animate("idle",delta)
			return
	if path.is_empty():
		actor.animate("idle",delta)
		return
	while index < path.size() and at.distance_to(path[index]) < .12: index += 1
	if index == path.size():
		arrived()
		return
	var speed: float = 3.35
	if moving and gap > 4.5: speed = 5.5
	var step_to: Vector2 = at.move_toward(path[index],speed*delta)
	if nav.safe(step_to): actor.body.move_and_collide(nav.position(step_to)-actor.body.global_position)
	var current: Vector2 = nav.metric(actor.body.global_position)
	var change: Vector2 = current-at
	if change.length() < .001:
		stall += delta
		if stall > .5:
			retries += 1
			stall = 0
			nav_dirty = retries < RETRY_LIMIT
			blocked(current)
	else:
		stall = 0
		if retries > 0 and current.distance_to(last_blocked_at) > .8:
			retries = 0
			last_blocked_at = Vector2.INF
		last_point = current
		actor.animate("walk",delta,change)
		status = "Walking. Animation unavailable." if actor.missing else ("Catching up." if speed > 3.35 else "Walking.")
		if exploration.dimension == "2d" and "terrain_presentation" in context["world"] and is_instance_valid(context["world"].terrain_presentation):
			context["world"].terrain_presentation.present(actor.body)

func _physics_process(delta: float) -> void:
	step(minf(delta,.08))
