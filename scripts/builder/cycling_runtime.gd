extends Node

const Plan = preload("res://scripts/builder/cycling_plan.gd")
const Drive = preload("res://scripts/builder/driving_plan.gd")
const Props = preload("res://scripts/builder/prop_plan.gd")
const Player3D = preload("res://scripts/builder/player_3d.gd")
const MAX_TRIPS = 4

var exploration: Node
var primary: Node
var runner: Node
var source: Dictionary = {}
var instances: Dictionary = {}
var plan: Dictionary = {}
var revision: int = 0
var stamp: int = -1
var routes: Dictionary = {}
var attempted: Dictionary = {}
var visitors: Array[Node] = []
var departure: Dictionary = {}
var time: float = 0
var next_visit: float = .8
var latest: String = ""
var guide_key: Callable

func configure(data: Dictionary, objects: Dictionary) -> void:
	source = data
	instances = objects
	var relevant: Array = []
	for item in data["objects"]:
		if item.has("cycling") or Plan.rack(item): relevant.append(item)
	var next: int = hash([Plan.enabled(data),Plan.Traffic.road_inputs(data),data.get("layers",{}),relevant])
	if next == stamp: return
	stamp = next
	revision += 1
	var tagged: bool = data.get("roads",[]).any(func(road: Dictionary)->bool: return road.get("cycle_access","none") != "none")
	plan = Plan.compile(data) if Plan.enabled(data) or tagged else {}
	if not Plan.enabled(data) and is_instance_valid(runner):
		reset()
	elif not attempted.is_empty():
		for id in attempted.keys():
			if attempted[id] == "unavailable": attempted.erase(id)

func guide_hint() -> String:
	if routes.has(primary.get_instance_id()): return " · Guiding to rack"
	var key: String = guide_key.call() if guide_key.is_valid() else "G"
	return " · "+key+" guide to rack"

func on_course(candidate: Dictionary, point: Vector2, yaw: float) -> bool:
	return not plan.is_empty() and Plan.allows(plan,candidate["profile"],candidate["extent"],candidate["point"],point,yaw)

func mount_reason(candidate: Dictionary) -> String:
	return "" if on_course(candidate,candidate["point"],candidate["yaw"]) else "Move this cycle onto a connected, tagged cycle route before mounting."

func motor_reason(point: Vector2) -> String:
	if plan.is_empty(): return ""
	var road: Dictionary = plan["roads"]["sections"].get(Plan.cell_key(point,plan),{})
	if road.get("cycle_access","none") != "cycle": return ""
	var center: Vector2 = Plan.Traffic.center(road["cell"],source["mode"])
	var offset: Vector2 = (point-center).abs()
	if maxf(offset.x,offset.y) <= road["width"]*.5: return "Cycle path · motor vehicles excluded."
	# A tagged connection extends between adjoining reserved sections.
	for neighbor in road["neighbors"]:
		var adjacent: Dictionary = plan["roads"]["sections"][neighbor]
		if adjacent.get("cycle_access") != "cycle": continue
		var axis: Vector2 = Vector2(adjacent["cell"]-road["cell"])
		if (point-center).dot(axis) >= 0 and absf((point-center).cross(axis)) <= road["width"]*.5: return "Cycle path · motor vehicles excluded."
	return ""

func reason(driver: Node, point: Vector2, yaw: float) -> String:
	if not driver.cycling(): return motor_reason(point)
	return "" if on_course(driver.active,point,yaw) else "Cycle route ends here · use a tagged path."

func gate_reason(driver: Node, point: Vector2) -> String:
	var active: Dictionary = driver.active
	var traffic: Node = primary.traffic
	if not is_instance_valid(traffic): return ""
	var id: String = "cycle:"+active["item"]["uid"]
	var axis: Vector2 = (point-active["point"]).normalized()
	var incoming: String = Plan.cell_key(active["point"]-axis*.15,plan)
	var ahead: String = Plan.cell_key(point+axis*(active["extent"].y+.15),plan)
	var claimed: Dictionary = active.get("cycle_gates",{})
	var rear: String = Plan.cell_key(point-axis*(active["extent"].y+.2),plan)
	for held in claimed.keys():
		if rear == held or ahead == held or incoming == held: continue
		traffic.gates.release(id,held)
		claimed.erase(held)
	if ahead == incoming or not plan["sections"].has(ahead): return ""
	if not plan["edges"].has(Plan.Traffic.edge_id(incoming,ahead)): return "This cycle connection is one-way."
	var network: Dictionary = plan["roads"]
	var people: Array[Vector2] = traffic.pedestrian_points(active["world"])
	if driver != primary and is_instance_valid(exploration.player) and exploration.player.visible and not exploration.player.has_meta("cycling_rider"):
		var local: Variant = active["world"].to_local(exploration.player.global_position)
		var walker: Vector2 = Plan.Traffic.metric([local.x,local.y,0] if local is Vector2 else [local.x,local.y,local.z],exploration.dimension)
		if walker not in people: people.append(walker)
	var occupied: bool = Plan.Traffic.crossing_occupied(network,ahead,people)
	var verdict: Dictionary = traffic.gates.request(network,id,ahead,traffic.gate_time(ahead,time),occupied,incoming)
	claimed[ahead] = true
	active["cycle_gates"] = claimed
	return verdict["reason"]

func dismounted(driver: Node) -> void:
	var traffic: Node = primary.traffic
	if is_instance_valid(traffic) and not driver.active.is_empty():
		traffic.gates.release("cycle:"+driver.active["item"]["uid"])
	routes.erase(driver.get_instance_id())

func walking_surface(actor: Node3D, point: Vector3) -> Variant:
	var ray := PhysicsRayQueryParameters3D.create(point+Vector3.UP*.6,point-Vector3.UP*.45,2)
	var hit: Dictionary = actor.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or hit["normal"].y < Plan.Terrain.WALKABLE_NORMAL: return null
	return hit["position"]+Vector3.UP*.025

func exit_reachable(driver: Node, point: Variant) -> bool:
	var walker: Node = driver.operator()
	var local: Variant = driver.active["world"].to_local(point)
	var landing: Vector2 = Plan.Traffic.metric([local.x,local.y,0] if local is Vector2 else [local.x,local.y,local.z],exploration.dimension)
	var traffic: Node = primary.traffic
	var others: Array = occupants()
	if is_instance_valid(traffic): others.append_array(traffic.vehicles+traffic.external_vehicles)
	for vehicle in others:
		if vehicle.get("actor") == driver.active["node"]: continue
		var axis: Vector2 = vehicle.get("heading",Vector2.DOWN)
		var offset: Vector2 = landing-vehicle["point"]
		if absf(offset.dot(axis)) < vehicle.get("half_length",1.3)+.4 and absf(offset.cross(axis)) < vehicle.get("half_width",.6)+.4:
			return false
	var excluded: Array[RID] = driver.excluded()
	if exploration.dimension == "2d":
		var ray := PhysicsRayQueryParameters2D.create(walker.global_position,point,1,excluded)
		return walker.get_world_2d().direct_space_state.intersect_ray(ray).is_empty()
	var ray := PhysicsRayQueryParameters3D.create(walker.global_position+Vector3.UP*.85,point+Vector3.UP*.85,1,excluded)
	return walker.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func occupants() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for driver in [primary,runner]:
		if not is_instance_valid(driver) or not driver.cycling(): continue
		var active: Dictionary = driver.active
		result.append({"id":"cycle:"+active["item"]["uid"],"actor":active["node"],"point":active["point"],
			"heading":Drive.heading(active["yaw"]),"half_width":active["extent"].x,"half_length":active["extent"].y,
			"speed":absf(driver.speed),"phase":"cycle","asset":active["item"]["asset"],"status":"Cycling"})
	return result

func start_route(driver: Node) -> bool:
	if not driver.cycling() or plan.is_empty(): return false
	var active: Dictionary = driver.active
	var route: Dictionary = Plan.rack_route(source,plan,active["item"],active["profile"],active["extent"],active["point"],exploration.library)
	if not route["reason"].is_empty():
		driver.notice = route["reason"]
		driver.notice_time = 5
		return false
	route["index"] = 1
	route["revision"] = revision
	route["blocked_for"] = 0.0
	routes[driver.get_instance_id()] = route
	return true

func guide() -> bool:
	if not primary.cycling(): return false
	var key: int = primary.get_instance_id()
	if routes.has(key):
		routes.erase(key)
		primary.notice = "Rack guidance cancelled."
		primary.notice_time = 3
	else: start_route(primary)
	return true

func step_guide(driver: Node, delta: float, input: Vector2, brake: bool) -> bool:
	if not driver.cycling(): return false
	var key: int = driver.get_instance_id()
	if not routes.has(key): return false
	if not input.is_zero_approx() or brake:
		routes.erase(key)
		driver.notice = "Manual cycling."
		driver.notice_time = 2
		return false
	var journey: Dictionary = routes[key]
	if journey["revision"] != revision:
		routes.erase(key)
		if start_route(driver): journey = routes[key]
		else:
			driver.speed = 0
			if driver != primary: stop_npc(driver,"The rack or cycle route changed.")
			return true
	var points: PackedVector2Array = journey["path"]
	var active: Dictionary = driver.active
	while journey["index"] < points.size() and active["point"].distance_to(points[journey["index"]]) <= .04:
		journey["index"] += 1
	if journey["index"] == points.size():
		driver.speed = 0
		driver.preferred_landing = journey["point"]
		var identity: String = active["item"]["uid"]
		if driver.exit_vehicle():
			driver.notice = "Parked at the bicycle rack."
			driver.notice_time = 5
			if driver != primary:
				attempted[identity] = "completed"
				latest = "A rider parked at the rack and returned to walking."
				start_departure(driver,journey["point"])
		return true
	var difference: Vector2 = points[journey["index"]]-active["point"]
	var desired: float = atan2(difference.x,difference.y)
	var angle: float = rotate_toward(active["yaw"],desired,delta*active["profile"]["steering"])
	if not on_course(active,active["point"],angle) or not driver.clear_pose(active["point"],angle):
		driver.speed = 0
		driver.notice = "The cycle needs clear space to turn."
		driver.notice_time = 3
		return true
	var turn: float = absf(angle_difference(angle,desired))
	var speed: float = minf(active["profile"]["max_speed"],3.3)
	if turn > .03: speed = 0
	driver.speed = move_toward(driver.speed,speed,delta*(active["profile"]["acceleration"] if speed > 0 else active["profile"]["braking"]))
	var distance: float = minf(driver.speed*delta,difference.length()) if turn <= .03 else 0.0
	if distance > 0:
		var moved: bool = driver.advance_motion(distance,desired)
		journey["blocked_for"] = 0.0 if moved else journey["blocked_for"]+delta
		if driver != primary and journey["blocked_for"] > 28:
			stop_npc(driver,"The cycle route stayed blocked. The rider stopped.")
			return true
	else: driver.advance_motion(0.0,angle)
	driver.pose(delta)
	return true

func ensure_runner() -> void:
	if is_instance_valid(runner): return
	runner = load("res://scripts/builder/driving_runtime.gd").new()
	runner.exploration = exploration
	runner.course = self
	add_child(runner)
	runner.set_physics_process(false)

func make_visitor(world: Node, point: Vector2, yaw: float, extent: Vector2) -> Node:
	var parent: Node = world.objects if "objects" in world else world.get_node("Objects")
	var actor: Node = load("res://scenes/items/Characters/Office_Worker.tscn").instantiate() if exploration.dimension == "2d" else Player3D.new()
	actor.name = "RackVisitor"
	actor.collision_layer = 0
	actor.collision_mask = 1 if exploration.dimension == "2d" else 3
	parent.add_child(actor)
	actor.set_physics_process(false)
	var axis: Vector2 = Drive.heading(yaw)
	var right := Vector2(axis.y,-axis.x)
	var offsets: Array[Vector2] = []
	for margin in [.9,1.55,2.2]:
		offsets.append(right*(extent.x+margin))
		offsets.append(-right*(extent.x+margin))
		offsets.append(-axis*(extent.y+margin))
	for offset in offsets:
		var at: Vector2 = point+offset
		var ground: Dictionary = Plan.Terrain.sample(source,at) if Plan.Terrain.settings(source)["enabled"] else {"height":0.0}
		var position: Variant = world.to_global(Drive.world(at,exploration.dimension,ground["height"]+.135))
		if exploration.dimension == "2d":
			if not actor.clear_at(position): continue
		else:
			position = walking_surface(actor,position)
			if position == null: continue
			var pose: Transform3D = actor.global_transform
			pose.origin = position
			if not actor.clear_at(pose): continue
		if actor.terrain_position_safe.is_valid() and not actor.terrain_position_safe.call(position): continue
		actor.teleport_to(actor.get_parent().to_local(position))
		visitors.append(actor)
		return actor
	actor.free()
	return null

func dispatch() -> void:
	var world: Node = exploration.get_parent()
	for item in source.get("objects",[]):
		var uid: String = item["uid"]
		if attempted.has(uid) or not item.get("cycling",{}).get("npc",false): continue
		var profile: Dictionary = Plan.profile(item,source)
		var node: Node = instances.get(uid)
		if profile.is_empty() or not is_instance_valid(node) or not node.is_visible_in_tree(): continue
		var point: Vector2 = Drive.center(item,exploration.library,exploration.dimension)
		var yaw: float = Drive.yaw(item,profile)
		var extent: Vector2 = Drive.dimensions(item,exploration.library,exploration.dimension,profile)
		var candidate: Dictionary = {"item":item,"node":node,"profile":profile,"extent":extent,"point":point,"yaw":yaw,"world":world,"data":source}
		var route: Dictionary = Plan.rack_route(source,plan,item,profile,extent,point,exploration.library)
		if not mount_reason(candidate).is_empty() or not route["reason"].is_empty():
			attempted[uid] = "unavailable"
			latest = "A preview rider is waiting for a connected rack route."
			continue
		ensure_runner()
		var actor: Node = make_visitor(world,point,yaw,extent)
		if not is_instance_valid(actor):
			attempted[uid] = "unavailable"
			latest = "A preview rider needs clear mounting space."
			continue
		runner.rider = actor
		runner.traffic = primary.traffic
		if runner.interact(candidate) and start_route(runner):
			attempted[uid] = "riding"
			latest = "A preview rider is cycling to the rack."
			return
		runner.exit_vehicle(true)
		visitors.erase(actor)
		actor.free()
		attempted[uid] = "unavailable"

func start_departure(driver: Node, rack: Vector2) -> void:
	var actor: Node = driver.rider
	var world: Node = exploration.get_parent()
	var point: Variant = world.to_global(Drive.world(rack,exploration.dimension))
	var direction: Variant = point-actor.global_position
	if direction is Vector3: direction.y = 0
	departure = {"actor":actor,"direction":direction.normalized(),"seconds":.9}
	next_visit = time+1.2

func stop_npc(driver: Node, reason_text: String) -> void:
	var item: String = driver.active["item"]["uid"]
	driver.speed = 0
	latest = reason_text
	if driver.exit_vehicle():
		attempted[item] = "cancelled"
		next_visit = time+1.2

func step(delta: float) -> void:
	if not exploration.enabled or exploration.interior or exploration.photo.active or not Plan.enabled(source): return
	time += delta
	if not departure.is_empty():
		var walker: Node = departure["actor"]
		var direction: Variant = departure["direction"]
		if exploration.dimension == "2d":
			walker.move_character(delta,direction)
			walker._update_animation(delta)
		else: walker.move_character(delta,direction)
		departure["seconds"] -= delta
		if departure["seconds"] <= 0:
			walker.velocity = Vector2.ZERO if exploration.dimension == "2d" else Vector3.ZERO
			if walker is IsoCharacter: walker.action = "idle"; walker._update_frame()
			departure.clear()
	if is_instance_valid(runner) and runner.cycling():
		var active: Dictionary = runner.active
		var uid: String = active["item"]["uid"]
		if not is_instance_valid(active["node"]) or instances.get(uid) != active["node"]:
			runner.exit_vehicle(true)
			attempted[uid] = "cancelled"
			latest = "The assigned cycle was removed."
		elif not routes.has(runner.get_instance_id()):
			stop_npc(runner,"A preview rider lost the cycle route.")
		else:
			active["data"] = source
			step_guide(runner,delta,Vector2.ZERO,false)
	elif time >= next_visit and visitors.size() < MAX_TRIPS and not plan.is_empty():
		next_visit = time+.75
		dispatch()

func _physics_process(delta: float) -> void:
	step(minf(delta,.06))

func reset() -> void:
	if is_instance_valid(runner):
		runner.reset()
		runner.rider = null
	for visitor in visitors:
		if is_instance_valid(visitor): visitor.free()
	visitors.clear()
	routes.clear()
	attempted.clear()
	departure.clear()
	time = 0
	next_visit = .8
	latest = ""
