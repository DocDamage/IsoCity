extends Node

const Plan = preload("res://scripts/builder/space_outpost_plan.gd")
const Factory = preload("res://scripts/builder/asset_instance.gd")
const Reservations = preload("res://scripts/builder/activity_reservations.gd")
const FIRST_WAIT = 2.0
const CLEARANCE = 6.5
const BLOCKED_RETRY = 3.0

var exploration: Node
var config: Dictionary = {}
var network: Dictionary = {}
var signature: Array = []
var job: Dictionary = {}
var staged: Dictionary = {}
var guides: Node
var orbital: Node
var orbit_time: float = 0.0
var waiting: float = FIRST_WAIT
var schedule: int = 0
var completed: int = 0
var report: String = ""
var leases: RefCounted

func configure(data: Dictionary) -> void:
	config = Plan.settings(data)
	if not config["enabled"]:
		stop()
		signature.clear()
		network = {}
		set_physics_process(false)
		return
	set_physics_process(true)
	var current: Array = [config, data.get("terrain"), data.get("terrain_vertices"), data.get("water_cells"),
		data.get("layers"), data.get("roads"), data.get("objects")]
	if current == signature: return
	var next: Dictionary = Plan.inspect(data, exploration.library)
	if not job.is_empty():
		var dock: Dictionary = job["dock"]
		if next.get("docks", {}).get(dock["id"], {}) != dock:
			cancel()
			waiting = BLOCKED_RETRY
			report = "Supply approach interrupted. The dock has changed."
	for id in staged.keys():
		if next.get("docks", {}).get(id, {}) != network.get("docks", {}).get(id, {}):
			dispose(staged[id])
			staged.erase(id)
	if not next.get("orbital", false):
		dispose(orbital)
		orbital = null
	if network.get("docks", {}) != next.get("docks", {}):
		dispose(guides)
		guides = null
	network = next
	signature = current.duplicate(true)

func world() -> Node:
	return exploration.get_parent()

func draw_point(point: Vector2, height: float) -> Variant:
	var raw: Array = Plan.Zone.Traffic.world(point, exploration.dimension, height)
	if exploration.dimension == "2d": return Vector2(raw[0], raw[1] - height * 8.0)
	return Vector3(raw[0], raw[1], raw[2])

func on_site() -> bool:
	return exploration.enabled and not is_instance_valid(exploration.interior) and is_instance_valid(exploration.player)

func player_point() -> Vector2:
	var local: Variant = world().to_local(exploration.player.global_position)
	return Plan.Zone.Traffic.metric([local.x, local.y, 0], "2d") if local is Vector2 else Vector2(local.x, local.z)

func dispose(node: Node) -> void:
	if is_instance_valid(node):
		node.hide()
		node.queue_free()

func make_visual(id: String, name_value: String, scale_value: float, direction: String = "") -> Node:
	var facing: String = str(exploration.library.directions(id)[0]) if direction.is_empty() else direction
	var pool: Node = world().get("projection_pool") if exploration.dimension == "2d" else null
	var visual: Node = Factory.make(exploration.library, id, exploration.dimension, false, pool)
	Factory.orient(visual, facing)
	visual.name = name_value
	world().get_node("Objects").add_child(visual)
	visual.scale = Vector2.ONE * scale_value if visual is Node2D else Vector3.ONE * scale_value
	return visual

func begin() -> void:
	var docks: Dictionary = network.get("docks", {})
	if docks.is_empty(): return
	if not leases: leases = Reservations.for_world(world())
	var ids: Array = docks.keys()
	var start: int = schedule % ids.size()
	for offset in ids.size():
		var id: String = ids[(start + offset) % ids.size()]
		var dock: Dictionary = docks[id]
		if dock["corridor"].has_point(player_point()): continue
		var key: String = "space_outpost:" + id
		var token: int = leases.acquire(key, self)
		if token == 0: continue
		var ships: Array = Plan.definitions()["ships"]
		var profile: Dictionary = ships[schedule % ships.size()]
		var visual: Node = make_visual(profile["asset"], "SupplyShip", profile["scale"], dock["heading"])
		var height: float = dock["height"] - Plan.Fit.bounds_for(profile["asset"], exploration.library, false).position.y * profile["scale"]
		job = {"dock": dock, "token": token, "key": key, "ship": visual, "profile": profile,
			"phase": "arrival", "elapsed": 0.0, "blocked": 0.0, "height": height, "cargo": null, "contact": null}
		schedule += 1
		report = ""
		pose_ship(dock["entry"], CLEARANCE)
		return
	report = "Supply ship waiting for a clear dock."
	waiting = BLOCKED_RETRY

func pose_ship(point: Vector2, lift: float) -> void:
	job["point"] = point
	job["lift"] = lift
	job["ship"].position = draw_point(point, job["height"] + lift)

func next_phase(value: String) -> void:
	job["phase"] = value
	job["elapsed"] = 0.0

func make_contact() -> Node:
	var dock: Dictionary = job["dock"]
	var profile: Dictionary = job["profile"]
	var heading: float = deg_to_rad(float(dock["heading"]))
	var model: AABB = Plan.Fit.bounds_for(profile["asset"], exploration.library, false)
	var shape_bounds: AABB = Transform3D(Basis(Vector3.UP, heading).scaled(Vector3.ONE * float(profile["scale"])), Vector3.ZERO) * model
	var berth: Vector2 = dock["berth"]
	var body: Node
	if exploration.dimension == "2d":
		body = StaticBody2D.new()
		body.collision_mask = 0
		var outline := CollisionPolygon2D.new()
		var outline_points := PackedVector2Array()
		for corner in [
			Vector2(shape_bounds.position.x, shape_bounds.position.z),
			Vector2(shape_bounds.end.x, shape_bounds.position.z),
			Vector2(shape_bounds.end.x, shape_bounds.end.z),
			Vector2(shape_bounds.position.x, shape_bounds.end.z),
		]:
			outline_points.append(draw_point(berth + corner * 2.0, 0))
		outline.polygon = outline_points
		body.add_child(outline)
	else:
		body = StaticBody3D.new()
		body.collision_mask = 0
		var outline := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = shape_bounds.size
		outline.shape = box
		outline.position = shape_bounds.get_center()
		body.position = draw_point(berth, job["height"])
		body.add_child(outline)
	body.name = "SupplyShipContact"
	world().get_node("Objects").add_child(body)
	return body

func start_unload() -> void:
	var dock: Dictionary = job["dock"]
	var id: String = dock["id"]
	dispose(staged.get(id))
	staged.erase(id)
	job["cargo"] = make_visual(Plan.definitions()["cargo"], "SupplyCrate", Plan.CRATE_SCALE)
	job["cargo"].position = draw_point(dock["berth"], job["height"] + .45)
	next_phase("unloading")

func cancel() -> void:
	if job.is_empty(): return
	if leases: leases.release(job["key"], job["token"])
	dispose(job["cargo"])
	dispose(job["contact"])
	dispose(job["ship"])
	job = {}

func stop() -> void:
	cancel()
	for crate in staged.values(): dispose(crate)
	staged.clear()
	dispose(guides)
	guides = null
	dispose(orbital)
	orbital = null
	orbit_time = 0.0
	waiting = FIRST_WAIT
	report = ""

func advance(delta: float) -> void:
	var dock: Dictionary = job["dock"]
	var phase: String = job["phase"]
	if phase == "arrival" and dock["corridor"].has_point(player_point()):
		job["blocked"] += delta
		if job["blocked"] >= BLOCKED_RETRY:
			job["abort_point"] = job["point"]
			job["abort_lift"] = job["lift"]
			next_phase("abort")
		return
	job["elapsed"] += delta
	var elapsed: float = job["elapsed"]
	match phase:
		"arrival":
			job["blocked"] = 0.0
			var progress: float = minf(elapsed / float(job["profile"]["arrival_seconds"]), 1.0)
			var glide: float = minf(progress / .68, 1.0)
			var descend: float = maxf((progress - .50) / .50, 0.0)
			pose_ship((dock["entry"] as Vector2).lerp(dock["berth"], smoothstep(0, 1, glide)), CLEARANCE * (1.0 - descend))
			if progress == 1.0:
				job["contact"] = make_contact()
				next_phase("docked")
		"docked":
			if elapsed >= 1.5: start_unload()
		"unloading":
			var progress: float = minf(elapsed / float(job["profile"]["unload_seconds"]), 1.0)
			var point: Vector2 = (dock["berth"] as Vector2).lerp(dock["cargo"], smoothstep(0, 1, progress))
			var height: float = lerpf(job["height"] + .45, dock["cargo_height"] + .03, progress)
			job["cargo"].position = draw_point(point, height)
			if progress == 1.0:
				staged[dock["id"]] = job["cargo"]
				job["cargo"] = null
				next_phase("departure")
		"departure":
			var progress: float = minf(elapsed / 4.0, 1.0)
			var travel: float = maxf((progress - .40) / .60, 0.0)
			pose_ship((dock["berth"] as Vector2).lerp(dock["entry"], smoothstep(0, 1, travel)), CLEARANCE * minf(progress / .55, 1.0))
			if job["lift"] > 2.0 and is_instance_valid(job["contact"]):
				dispose(job["contact"])
				job["contact"] = null
			if progress == 1.0:
				completed += 1
				cancel()
				waiting = config["interval"]
				report = "Supplies delivered. The next ship is scheduled."
		"abort":
			var progress: float = minf(elapsed / 3.0, 1.0)
			var travel: float = maxf((progress - .40) / .60, 0.0)
			pose_ship((job["abort_point"] as Vector2).lerp(dock["entry"], travel), lerpf(job["abort_lift"], CLEARANCE, minf(progress / .40, 1.0)))
			if progress == 1.0:
				cancel()
				waiting = BLOCKED_RETRY
				report = "Ship went around. Clear the approach for the next arrival."

func prepare_guides() -> void:
	var docks: Dictionary = network.get("docks", {})
	if docks.is_empty() or is_instance_valid(guides): return
	guides = Node2D.new() if exploration.dimension == "2d" else Node3D.new()
	guides.name = "OutpostGroundGuides"
	world().get_node("Objects").add_child(guides)
	for dock in docks.values():
		var landing: Rect2 = dock["landing"].grow(-.65)
		var corners: Array[Vector2] = [
			landing.position, Vector2(landing.end.x, landing.position.y),
			landing.end, Vector2(landing.position.x, landing.end.y)
		]
		for index in corners.size():
			var corner: Vector2 = corners[index]
			var previous: Vector2 = corners[posmod(index - 1, corners.size())]
			var next: Vector2 = corners[(index + 1) % corners.size()]
			guide_line([corner.move_toward(previous, .9), corner, corner.move_toward(next, .9)],
				dock["height"], Color("#ffc264"))
		var stand: Vector2 = dock["stand"]
		guide_line([stand + Vector2.UP * .65, stand + Vector2.RIGHT * .65, stand + Vector2.DOWN * .65,
			stand + Vector2.LEFT * .65, stand + Vector2.UP * .65], dock["stand_height"], Color("#ecfcff"))

func guide_line(points: Array[Vector2], height: float, color: Color) -> void:
	if exploration.dimension == "2d":
		var line := Line2D.new()
		line.z_index = -1
		line.width = 2.0
		line.default_color = color
		line.antialiased = true
		for point in points: line.add_point(draw_point(point, height))
		guides.add_child(line)
		return
	var visual := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
	for point in points: mesh.surface_add_vertex(draw_point(point, height + .045))
	mesh.surface_end()
	visual.mesh = mesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	guides.add_child(visual)

func update_orbit(delta: float) -> void:
	if not network.get("orbital", false): return
	if not is_instance_valid(orbital):
		var id: String = Plan.definitions()["satellite"]
		if exploration.dimension == "2d":
			var icon: Texture2D = exploration.library.icon(id)
			if not is_instance_valid(icon) or icon == exploration.library.MISSING_ICON: return
			var sprite := Sprite2D.new()
			sprite.name = "OrbitalSatellite"
			sprite.texture = icon
			sprite.scale = Vector2.ONE * (34.0 / maxf(icon.get_width(), icon.get_height()))
			world().get_node("Objects").add_child(sprite)
			orbital = sprite
		else:
			orbital = make_visual(id, "OrbitalSatellite", .25)
			for mesh in orbital.find_children("*", "GeometryInstance3D", true, false):
				mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	orbit_time = fposmod(orbit_time + delta * .2, TAU)
	var docks: Dictionary = network.get("docks", {})
	var center: Vector2 = docks.values()[0]["stand"] if not docks.is_empty() else Vector2.ZERO
	orbital.position = draw_point(center + Vector2(cos(orbit_time) * 13, sin(orbit_time) * 7), 11)
	if orbital is Node3D: orbital.rotation.y = orbit_time

func _physics_process(delta: float) -> void:
	if not on_site():
		if not job.is_empty() or not staged.is_empty() or is_instance_valid(orbital) or is_instance_valid(guides): stop()
		return
	prepare_guides()
	update_orbit(delta)
	if not job.is_empty():
		advance(delta)
		return
	waiting = maxf(0, waiting - delta)
	if waiting == 0.0: begin()

func prompt() -> String:
	if not config.get("enabled", false) or not on_site(): return ""
	if not job.is_empty():
		var asset: String = job["profile"]["asset"]
		var title: String = exploration.library.assets[asset]["name"]
		var stage: String = {
			"arrival": "Arriving · Keep the approach clear", "docked": "Docked",
			"unloading": "Unloading supplies", "departure": "Departing", "abort": "Going around",
		}[job["phase"]]
		return "%s · %s" % [title, stage]
	return report

func _exit_tree() -> void:
	stop()
	leases = null
