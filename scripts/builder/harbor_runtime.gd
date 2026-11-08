extends Node

const Plan = preload("res://scripts/builder/harbor_plan.gd")
const Factory = preload("res://scripts/builder/asset_instance.gd")
const Paint = preload("res://scripts/builder/part_colors.gd")
const Props = preload("res://scripts/builder/prop_plan.gd")
const BOARD_REACH = 1.7

var exploration: Node
var source: Dictionary = {}
var instances: Dictionary = {}
var config: Dictionary = {}
var network: Dictionary = {}
var signature: int = -1
var boats: Dictionary = {}
var claims: Dictionary = {}
var rider: Dictionary = {}
var route_points: Dictionary = {}
var shuttle_path: Array = []
var shuttle_target: String = ""
var waypoint: int = 0
var wait: float = 0.0
var crossings: int = 0
var notice: String = ""
var notice_time: float = 0.0
var pending_landing: bool = false
var prepared: bool = false
var recovery_wait: float = 0.0

func running() -> bool:
	return exploration.enabled and exploration.interior == null and signature != -1

func active() -> bool:
	return not rider.is_empty()

func configure(data: Dictionary, objects: Dictionary) -> void:
	source = data
	instances = objects
	if not Plan.enabled(data):
		signature = -1
		network = {}
		if not boats.is_empty(): invalidate()
		return
	var relevant: Array = []
	for item in data["objects"]:
		relevant.append([item["uid"], item["asset"], item["position"], item["scale"], item["direction"],
			item.get("visible", true), item.get("layer", ""), item.get("angle", 0), item.get("tilt", []), item.has("missing_asset")])
	var next: int = hash([data.get("harbor"), data.get("terrain"), data.get("water_cells"), data.get("terrain_vertices"),
		data.get("layers"), relevant])
	if next == signature: return
	signature = next
	config = Plan.settings(data)
	network = Plan.compile(data, exploration.library)
	invalidate()

func invalidate() -> void:
	if active():
		pending_landing = true
		recovery_wait = 0
		message("Harbor changed. Looking for a safe landing.")
	release_boats()

func reset() -> void:
	if active():
		recover_rider()
		# Build and shutdown release the rider even when every shore is flooded.
		# Entering Walk again runs the existing terrain start check.
		if active(): leave_at(rider["position"], rider["height"])
	release_boats()
	notice_time = 0
	crossings = 0

func release_boats() -> void:
	for boat in boats.values():
		var authored: Node = boat.get("original")
		if is_instance_valid(authored) and instances.get(boat["uid"]) == authored:
			var current: Dictionary = boat["item"]
			for item in source.get("objects", []):
				if item["uid"] == boat["uid"]:
					current = item
					break
			authored.visible = current.get("visible", true) and Plan.Layers.shown(source, Plan.Layers.layer(current, exploration.library))
			Plan.Layers.collision_visibility(authored, authored.visible)
		for node in [boat.get("visual"), boat.get("wake")]:
			if is_instance_valid(node):
				node.hide()
				node.queue_free()
	prepared = false
	boats.clear()
	claims.clear()
	route_points.clear()
	shuttle_path.clear()
	shuttle_target = ""
	waypoint = 0
	wait = 0

func socket_at(id: String, hull: Dictionary) -> Dictionary:
	for record in config.get("docks", []):
		if record["anchor"] == id: return Plan.socket(network, source, record, hull)
	return Plan.failure("Choose a defined dock.")

func sockets(hull: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record in config.get("docks", []):
		var socket: Dictionary = Plan.socket(network, source, record, hull)
		if socket["ok"]: result.append(socket)
	return result

func message(text: String) -> void:
	notice = text
	notice_time = 4.0

func world() -> Node:
	return exploration.get_parent()

func world_point(point: Vector2, height: float = 0.0) -> Variant:
	var raw: Array = Plan.Traffic.world(point, exploration.dimension, height)
	return Vector2(raw[0], raw[1]) if exploration.dimension == "2d" else Vector3(raw[0], raw[1], raw[2])

func metric(global_point: Variant) -> Vector2:
	var local: Variant = world().to_local(global_point)
	return Plan.Traffic.metric([local.x, local.y, 0], "2d") if local is Vector2 else Vector2(local.x, local.z)

func draw_position(point: Vector2, height: float) -> Variant:
	var value: Variant = world_point(point, height)
	return value + Vector2(0, -height * 8.0) if value is Vector2 else value

func make_boat(role: String, item: Dictionary, hull: Dictionary, dock: Dictionary) -> void:
	var original: Node = instances.get(item["uid"])
	if not is_instance_valid(original) or not original.is_visible_in_tree(): return
	if not clear_boats(role, dock["water"], hull) or not claim(dock["anchor"], role): return
	var visual: Node = Factory.make(exploration.library, item["asset"], exploration.dimension, false)
	visual.name = "Harbor" + role.capitalize()
	world().get_node("Objects").add_child(visual)
	var pose: Dictionary = item.duplicate(false)
	pose.erase("angle")
	pose.erase("tilt")
	Factory.pose(visual, pose, source.get("night", false))
	Paint.apply(visual, item)
	var scale_value: float = float(item["scale"])
	visual.scale = Vector2.ONE * scale_value if exploration.dimension == "2d" else Vector3.ONE * scale_value
	original.hide()
	Plan.Layers.collision_visibility(original, false)
	var wake: Node = make_wake()
	var boat := {"uid": item["uid"], "item": item.duplicate(true), "original": original, "visual": visual,
		"wake": wake, "hull": hull, "point": dock["water"], "level": dock["level"],
		"dock": dock["anchor"], "berth": dock["water"],
		"velocity": Vector2.ZERO}
	boats[role] = boat
	pose_boat(boat, Vector2.ZERO)

func prepare() -> void:
	if not network.get("ok", false): return
	for role in ["pilot", "shuttle"]:
		if boats.has(role): continue
		var item: Dictionary = network["items"].get(config.get(role, ""), {})
		var hull: Dictionary = Plan.hull(item)
		if hull.is_empty(): continue
		var point: Vector2 = Plan.Traffic.metric(item["position"], exploration.dimension)
		if role == "shuttle":
			var origin: Dictionary = socket_at(config["origin"], hull)
			var destination: Dictionary = socket_at(config["destination"], hull)
			if not origin["ok"] or not destination["ok"] or origin["anchor"] == destination["anchor"]: continue
			if not Plan.moored_at(network, point, origin, hull): continue
			var route: Dictionary = Plan.route(network, origin, destination, hull)
			if not route["ok"]: continue
			make_boat(role, item, hull, origin)
			if boats.has(role):
				wait = float(config["interval"])
				var reverse: Array = route["points"].duplicate()
				reverse.reverse()
				route_points = {destination["anchor"]: route["points"], origin["anchor"]: reverse}
			continue
		var candidates: Array[Dictionary] = sockets(hull)
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return point.distance_squared_to(a["water"]) < point.distance_squared_to(b["water"]))
		for dock in candidates:
			if point.distance_to(dock["water"]) > Plan.BERTH_REACH: break
			if Plan.moored_at(network, point, dock, hull): make_boat(role, item, hull, dock)
			if boats.has(role): break

func claim(dock: String, role: String) -> bool:
	if claims.get(dock, role) != role: return false
	claims[dock] = role
	return true

func release(dock: String, role: String) -> void:
	if claims.get(dock) == role: claims.erase(dock)

func clear_boats(role: String, point: Vector2, hull: Dictionary, from: Variant = null) -> bool:
	for other in boats:
		if other == role: continue
		var vessel: Dictionary = boats[other]
		var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(vessel["point"], from, point) if from is Vector2 and from != point else point
		if nearest.distance_to(vessel["point"]) < float(hull["radius"]) + float(vessel["hull"]["radius"]) + .12:
			return false
	return true

func nearby() -> Dictionary:
	if not running() or active() or not boats.has("pilot"): return {}
	var boat: Dictionary = boats["pilot"]
	var dock: Dictionary = socket_at(boat["dock"], boat["hull"])
	if not dock["ok"]: return {}
	var player: Node = exploration.player
	if not is_instance_valid(player) or not player.is_visible_in_tree(): return {}
	var landing: Variant = world().to_global(world_point(dock["land"], dock["land_y"] + .025))
	var distance: float = metric(player.global_position).distance_to(dock["land"])
	if distance > BOARD_REACH: return {}
	if exploration.dimension == "3d" and absf(player.global_position.y - landing.y) > .8: return {}
	if not Props.standing_clear(exploration, landing) or not Props.reachable(exploration, boat["visual"], landing): return {}
	return {"distance": player.global_position.distance_to(landing), "dock": dock}

func board() -> bool:
	var candidate: Dictionary = nearby()
	if candidate.is_empty():
		message("Use the dry landing beside the moored pilot boat.")
		return false
	var player: Node = exploration.player
	rider = {"position": player.global_position, "visible": player.visible, "layer": player.collision_layer,
		"mask": player.collision_mask, "physics": player.is_physics_processing(),
		"height": player.get_meta("terrain_height", 0.0)}
	player.hide()
	player.collision_layer = 0
	player.collision_mask = 0
	player.set_physics_process(false)
	pose_rider(boats["pilot"])
	message("Aboard the trireme.")
	return true

func landing_at(dock: Dictionary) -> Variant:
	if not dock.get("ok", false): return null
	var point: Variant = world().to_global(world_point(dock["land"], dock["land_y"] + .025))
	return point if Props.standing_clear(exploration, point, rider["mask"]) else null

func dock_and_exit() -> bool:
	if not active() or not boats.has("pilot"): return false
	var boat: Dictionary = boats["pilot"]
	if boat["velocity"].length() > .55:
		message("Brake before docking.")
		return false
	var candidates: Array[Dictionary] = sockets(boat["hull"])
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return boat["point"].distance_squared_to(a["water"]) < boat["point"].distance_squared_to(b["water"]))
	for dock in candidates:
		if boat["point"].distance_to(dock["water"]) > Plan.BERTH_REACH: break
		if claims.get(dock["anchor"], "pilot") != "pilot": continue
		if not clear_boats("pilot", dock["water"], boat["hull"], boat["point"]): continue
		if not Plan.travel(network, boat["point"], dock["water"], boat["level"], boat["hull"]): continue
		var landing: Variant = landing_at(dock)
		if landing == null: continue
		release(boat["dock"], "pilot")
		claim(dock["anchor"], "pilot")
		boat["dock"] = dock["anchor"]
		boat["berth"] = dock["water"]
		boat["point"] = dock["water"]
		boat["velocity"] = Vector2.ZERO
		pose_boat(boat, Vector2.ZERO)
		leave_at(landing, dock["land_y"])
		message("Moored · safely ashore.")
		return true
	message("Move beside a free dock with a clear dry landing.")
	return false

func leave_at(point: Variant, height: float) -> void:
	var player: Node = exploration.player
	if is_instance_valid(player):
		player.visible = rider["visible"]
		player.collision_layer = rider["layer"]
		player.collision_mask = rider["mask"]
		player.set_physics_process(rider["physics"])
		player.teleport_to(player.get_parent().to_local(point))
		if exploration.dimension == "2d":
			player.set_meta("terrain_height", height)
			player.terrain_visual_offset = Vector2(0, -height * 8.0)
	rider.clear()
	pending_landing = false

func recover_rider() -> void:
	if not active(): return
	var player: Node = exploration.player
	if not is_instance_valid(player):
		rider.clear()
		pending_landing = false
		return
	var saved: Variant = rider["position"]
	var point: Vector2 = metric(saved)
	var traversal: Node = world().get("terrain_traversal")
	if is_instance_valid(traversal) and traversal.active():
		var mask: int = player.collision_mask
		player.collision_mask = rider["mask"]
		var safe: Variant = traversal.start_candidate(point, saved, false)
		if safe == null:
			for radius in [1.0, 2.0, 4.0, 8.0, 16.0, 32.0]:
				for index in 16:
					point = metric(saved) + Vector2.RIGHT.rotated(index * TAU / 16) * radius
					if network.get("ok", false) and not Plan.shore_safe(network, point): continue
					safe = traversal.start_candidate(point, saved, false)
					if safe != null: break
				if safe != null: break
		player.collision_mask = mask
		if safe == null:
			pending_landing = true
			return
		leave_at(safe, float(traversal.sample_at(point)["height"]))
	else:
		leave_at(saved, rider["height"])
	message("Harbor reset · returned to shore.")

func pose_rider(boat: Dictionary) -> void:
	var player: Node = exploration.player
	player.global_position = world().to_global(world_point(boat["point"], boat["level"]))
	if exploration.dimension == "2d": player.set_meta("terrain_height", boat["level"])

func make_wake() -> Node:
	var wake: Node
	if exploration.dimension == "2d":
		wake = Line2D.new()
		wake.width = 1.4
		wake.default_color = Color(.75, .95, 1.0, .8)
		wake.antialiased = true
	else:
		wake = MeshInstance3D.new()
		wake.mesh = ImmediateMesh.new()
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(.75, .95, 1.0, .8)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		wake.material_override = material
		wake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wake.name = "HarborWake"
	world().get_node("Objects").add_child(wake)
	wake.hide()
	return wake

func pose_boat(boat: Dictionary, movement: Vector2) -> void:
	var visual: Node = boat["visual"]
	var point: Vector2 = boat["point"]
	var height: float = float(boat["level"])
	visual.position = draw_position(point, height)
	if visual is Node3D and visual.mesh:
		# Align the supplied card's hull to the actual water surface.
		var bottom: float = (visual.mesh.position.y - visual.mesh.mesh.size.y * .5) * visual.scale.y
		visual.position.y += maxf(0, .035 - bottom)
	if visual is Node2D and not movement.is_zero_approx():
		var sprite: Sprite2D = visual.get_node_or_null("Sprite2D")
		if sprite:
			var projected: Vector2 = world_point(movement, 0)
			if absf(projected.x) > .01: sprite.flip_h = projected.x < 0
	var wake: Node = boat["wake"]
	wake.visible = not movement.is_zero_approx()
	if not wake.visible: return
	var direction: Vector2 = movement.normalized()
	var side := Vector2(-direction.y, direction.x)
	var radius: float = boat["hull"]["radius"]
	var tail: Vector2 = point - direction * radius * .8
	var left: Variant = draw_position(tail - direction * radius + side * radius * .8, height + .025)
	var front: Variant = draw_position(tail, height + .025)
	var right: Variant = draw_position(tail - direction * radius - side * radius * .8, height + .025)
	if wake is Line2D:
		wake.points = PackedVector2Array([left, front, right])
	else:
		var mesh: ImmediateMesh = wake.mesh
		mesh.clear_surfaces()
		mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for vertex in [left, front, right]: mesh.surface_add_vertex(vertex)
		mesh.surface_end()

func advance(boat: Dictionary, role: String, target: Vector2) -> bool:
	var point: Vector2 = boat["point"]
	if not Plan.travel(network, point, target, boat["level"], boat["hull"]) or not clear_boats(role, target, boat["hull"], point):
		pose_boat(boat, Vector2.ZERO)
		return false
	boat["point"] = target
	var dock: String = boat["dock"]
	if not dock.is_empty() and target.distance_to(boat["berth"]) > float(boat["hull"]["radius"]) + Plan.BERTH_REACH:
		release(dock, role)
		boat["dock"] = ""
	pose_boat(boat, target - point)
	return true

func steer(delta: float, direction: Vector2, brake: bool = false) -> void:
	if not active() or not boats.has("pilot"): return
	var boat: Dictionary = boats["pilot"]
	delta = clampf(delta, 0, .1)
	var target: Vector2 = direction.limit_length(1.0) * float(boat["hull"]["speed"]) if not brake else Vector2.ZERO
	boat["velocity"] = boat["velocity"].move_toward(target, (7.0 if brake else 3.5) * delta)
	if not advance(boat, "pilot", boat["point"] + boat["velocity"] * delta):
		boat["velocity"] = Vector2.ZERO
		message("Waterway blocked · check depth, clearance or another vessel.")
	pose_rider(boat)

func service(delta: float) -> void:
	if not boats.has("shuttle"): return
	var boat: Dictionary = boats["shuttle"]
	if shuttle_path.is_empty():
		wait = maxf(0, wait - delta)
		if wait > 0: return
		var target: String = config["destination"] if boat["dock"] == config["origin"] else config["origin"]
		if not route_points.has(target) or not claim(target, "shuttle"): return
		shuttle_path = route_points[target].duplicate()
		shuttle_target = target
		waypoint = 0
	var point: Vector2 = boat["point"]
	var next: Vector2 = point.move_toward(shuttle_path[waypoint], float(boat["hull"]["speed"]) * .75 * delta)
	if not advance(boat, "shuttle", next): return
	if next.distance_to(shuttle_path[waypoint]) > .002: return
	waypoint += 1
	if waypoint < shuttle_path.size(): return
	if boat["dock"] != shuttle_target: release(boat["dock"], "shuttle")
	boat["dock"] = shuttle_target
	boat["berth"] = next
	shuttle_path.clear()
	shuttle_target = ""
	crossings += 1
	wait = float(config["interval"])
	pose_boat(boat, Vector2.ZERO)

func _physics_process(delta: float) -> void:
	notice_time = maxf(0, notice_time - delta)
	if pending_landing:
		recovery_wait -= delta
		if recovery_wait <= 0:
			recover_rider()
			recovery_wait = .5
		if pending_landing: return
	if not running() or (exploration.photo and exploration.photo.active): return
	if not prepared:
		prepared = true
		prepare()
	service(delta)
	if not active(): return
	var drive: Node = exploration.driving
	var motion := Vector2(float(drive.held("move_right")) - float(drive.held("move_left")),
		float(drive.held("move_down")) - float(drive.held("move_up")))
	var course: Vector2
	if exploration.dimension == "2d":
		course = Plan.Traffic.metric([motion.x * 16, motion.y * 16, 0], "2d").normalized() * motion.length()
	else:
		var camera: Camera3D = exploration.player.get_viewport().get_camera_3d()
		var right: Vector3 = camera.global_basis.x if camera else Vector3.RIGHT
		var back: Vector3 = camera.global_basis.z if camera else Vector3.BACK
		course = Vector2(right.x, right.z).normalized() * motion.x + Vector2(back.x, back.z).normalized() * motion.y
	steer(delta, course, drive.held("jump"))

func prompt() -> String:
	if pending_landing: return "Harbor closed · waiting for a dry landing. Tab to Build."
	if active():
		var text: String = "Trireme · WASD steer · Space brakes · E · Dock and disembark"
		return text + (" · " + notice if notice_time > 0 else "")
	return notice if notice_time > 0 else ""

func _exit_tree() -> void:
	reset()
