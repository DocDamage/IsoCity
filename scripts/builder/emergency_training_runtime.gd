extends Node

const Plan = preload("res://scripts/builder/emergency_training_plan.gd")
const Scenario = preload("res://scripts/builder/scenario_plan.gd")
const Props = preload("res://scripts/builder/prop_plan.gd")
const RESPONSE_LIMIT = 180.0
const BLOCK_LIMIT = 12.0
const RECEIPT_LIMIT = 64

var exploration: Node
var services: Node
var instances: Dictionary = {}
var config: Dictionary = {}
var plan: Dictionary = {}
var attempt: String = ""
var signature: int = 0
var job: Dictionary = {}
var phase: String = ""
var secured: int = 0
var kit_collected: bool = false
var assisted: bool = false
var dispatched: bool = false
var response_returned: bool = false
var time: float = 0.0
var obstruction: float = 0.0
var notice: String = ""
var receipts: Array[String] = []
var markers: Node

func configure(data: Dictionary, objects: Dictionary) -> void:
	instances = objects
	var scenario: Variant = data.get("scenario")
	if not scenario is Dictionary or not Plan.valid(scenario) or data.get("interior_room", false):
		if not attempt.is_empty(): clear_attempt("Drill stopped.")
		return
	var stamp: int = hash([data["mode"], scenario, data["objects"], data.get("services", {}),
		data.get("fleet", {}), data.get("roads", []), data.get("layers", {}),
		data.get("terrain", {}), data.get("terrain_vertices", []), data.get("water_cells", [])])
	if not attempt.is_empty() and stamp == signature: return
	signature = stamp
	var fresh: bool = attempt != scenario["attempt"]
	var before: Dictionary = plan
	if fresh: clear_attempt("Drill restarted.")
	config = scenario.duplicate(true)
	attempt = config["attempt"]
	signature = stamp
	plan = Plan.inspect(data, exploration.library)
	if not plan["ok"]:
		fail(plan["reason"])
	elif fresh:
		phase = "dispatch"
		notice = "Check in at the dispatch desk."
	elif phase != "dispatch" and phase != "failed" and changed_route(before, plan):
		fail("The drill placements or routes changed. Restart to use the new setup.")
	rebuild_markers()

func changed_route(old: Dictionary, next: Dictionary) -> bool:
	if not old.get("ok", false): return true
	if old["steps"] != next["steps"] or old["service_sites"] != next["service_sites"]: return true
	for field in ["route", "return_route", "fleet_profile"]:
		if old["trip"][field] != next["trip"][field]: return true
	return false

func clear_attempt(reason: String) -> void:
	cancel_job(reason)
	attempt = ""
	config = {}
	plan = {}
	phase = ""
	secured = 0
	kit_collected = false
	assisted = false
	dispatched = false
	response_returned = false
	signature = 0
	time = 0.0
	obstruction = 0.0
	notice = ""
	clear_markers()

func reset_session() -> void:
	clear_attempt("Drill session reset.")
	receipts.clear()

func walking_changed(value: bool) -> void:
	if not value and not job.is_empty() and phase not in ["complete", "failed"]:
		fail("Drill ended when you left Walk. Restart to dispatch again.")
	if is_instance_valid(markers): markers.visible = value

func cancel_job(reason: String) -> void:
	if not job.is_empty() and is_instance_valid(services) and services.dispatch.owns(job) and job.get("training") == attempt:
		services.dispatch.cancel(job, reason)
		if services.crews.has(job["id"]) and job["state"] in ["cancelled", "complete"]:
			services.remove_crew(job["id"])
	job = {}

func fail(reason: String) -> void:
	cancel_job(reason)
	phase = "failed"
	notice = reason
	dispatched = false
	response_returned = false
	kit_collected = false
	secured = 0
	assisted = false
	clear_markers()

func next_role() -> String:
	match phase:
		"dispatch", "return", "complete": return "desk"
		"kit", "subject": return phase
		"perimeter": return "perimeter_%d" % secured
	return ""

func action() -> String:
	match phase:
		"dispatch": return "Dispatch the " + ("fire crew" if plan["service"] == "fire" else "ambulance")
		"kit": return "Collect the training kit"
		"perimeter": return "Secure perimeter point %d" % (secured + 1)
		"subject": return plan["subject_action"]
		"return": return "Report back at the dispatch desk" if response_returned else "Check the returning crew"
		"complete": return "Review completed drill"
	return ""

func world() -> Node:
	return exploration.get_parent()

func world_point(point: Vector2, height: float) -> Variant:
	var value: Array = Plan.Service.Traffic.world(point, exploration.dimension, height)
	return Vector2(value[0], value[1]) if exploration.dimension == "2d" else Vector3(value[0], value[1], value[2])

func nearby_task() -> Dictionary:
	if not exploration.enabled or exploration.interior or exploration.entering or not plan.get("ok", false): return {}
	var role: String = next_role()
	if role.is_empty(): return {}
	var step: Dictionary = plan["steps"][role]
	var node: Node = instances.get(step["uid"])
	if not is_instance_valid(node) or not node.is_visible_in_tree(): return {}
	var player: Node = exploration.player
	var local: Variant = world().to_local(player.global_position)
	var raw: Array = [local.x, local.y, 0] if local is Vector2 else [local.x, local.y, local.z]
	var point: Vector2 = Plan.Service.Traffic.metric(raw, exploration.dimension)
	var height: float = player.get_meta("terrain_height", 0.0) if local is Vector2 else local.y
	if point.distance_to(step["point"]) > Plan.REACH or absf(height - float(step["height"])) > .75: return {}
	var standing: Variant = world().to_global(world_point(step["point"], step["height"] + .025))
	if not Props.standing_clear(exploration, standing) or not Props.reachable(exploration, node, standing): return {}
	return {"title": action(), "distance": player.global_position.distance_to(standing)}

func interact() -> bool:
	if nearby_task().is_empty(): return false
	match phase:
		"dispatch":
			if not is_instance_valid(services) or not services.dispatch.plan.get("settings", {}).get("enabled", false):
				notice = "The city service preview is unavailable."
				return false
			var coverage: Dictionary = Plan.Service.choose(services.dispatch.plan, plan["service"],
				config["incident"], {}, attempt, config["station"])
			if not coverage["ok"]:
				fail("Response route · " + coverage["reason"])
				return false
			var requested: Dictionary = services.dispatch.request(plan["service"], config["incident"], config["station"], attempt)
			if not requested["ok"]:
				fail(requested["reason"])
				return false
			job = requested["job"]
			dispatched = true
			time = 0.0
			phase = "kit" if config.has("kit") else "perimeter"
			notice = "Request queued. " + action() + "."
		"kit":
			kit_collected = true
			phase = "perimeter"
			notice = "Kit collected. Secure the intake point."
		"perimeter":
			secured += 1
			if secured == config["perimeter"].size():
				phase = "subject"
				notice = "Perimeter secured. " + action() + "."
			else:
				notice = "Perimeter point secured. Continue to the next marker."
		"subject":
			assisted = true
			phase = "return"
			notice = "Participant accounted for. Return to the desk." if not config.has("kit") else "Training assistance recorded. Return to the desk."
		"return":
			if not response_returned:
				notice = job.get("reason", "Wait for the assigned crew to return.")
				return false
			phase = "complete"
			notice = "Drill complete · training receipt recorded."
			if attempt not in receipts:
				receipts.append(attempt)
				if receipts.size() > RECEIPT_LIMIT: receipts.pop_front()
			cancel_job("Drill complete.")
		"complete": return true
		_: return false
	rebuild_markers()
	return true

func _process(delta: float) -> void:
	if job.is_empty() or not exploration.enabled or exploration.interior: return
	if not is_instance_valid(services) or not services.dispatch.owns(job):
		fail("The assigned service preview was reset. Restart the drill.")
		return
	if job["state"] == "complete":
		response_returned = true
		return
	if job["state"] == "cancelled":
		fail(job["reason"])
		return
	if services.paused or not services.active: return
	time += delta
	obstruction = obstruction + delta if job["state"] == "blocked" else 0.0
	if obstruction >= BLOCK_LIMIT or time >= RESPONSE_LIMIT:
		fail("Response did not finish · " + job["reason"] + ". Restart after clearing the route.")

func progress() -> Dictionary:
	if attempt.is_empty(): return Scenario.result([])
	var rows: Array = [Scenario.goal("dispatch", "Dispatch the assigned crew", int(dispatched), 1)]
	if config.has("kit"): rows.append(Scenario.goal("kit", "Collect the training kit", int(kit_collected), 1))
	rows.append(Scenario.goal("perimeter", "Secure the training perimeter", secured, config["perimeter"].size()))
	rows.append(Scenario.goal("subject", Plan.definitions()[config["id"]]["subject_action"], int(assisted), 1))
	rows.append(Scenario.goal("crew", "Crew returns to its station", int(response_returned), 1))
	rows.append(Scenario.goal("return", "Report back at the dispatch desk", int(phase == "complete"), 1))
	var detail: Array = [] if notice.is_empty() else [notice]
	if not job.is_empty() and not job.get("reason", "").is_empty(): detail.append(job["reason"])
	var result: Dictionary = Scenario.result(rows, detail)
	result["state"] = phase
	return result

func prompt() -> String:
	if not exploration.enabled or exploration.interior or attempt.is_empty(): return ""
	if phase in ["failed", "complete"]: return notice
	return action() + (" · " + job["reason"] if not job.is_empty() and not response_returned else "")

func clear_markers() -> void:
	if is_instance_valid(markers):
		markers.hide()
		markers.queue_free()
	markers = null

func rebuild_markers() -> void:
	clear_markers()
	if not is_inside_tree() or not plan.get("ok", false) or phase in ["", "failed"]: return
	markers = Node2D.new() if exploration.dimension == "2d" else Node3D.new()
	markers.name = "TrainingFieldMarkers"
	world().get_node("Objects").add_child(markers)
	markers.visible = exploration.enabled
	for index in secured:
		mark(plan["steps"]["perimeter_%d" % index], Color("3cdbc4"), true)
	if assisted: mark(plan["steps"]["subject"], Color("3cdbc4"), true)
	var role: String = next_role()
	if not role.is_empty() and phase != "complete": mark(plan["steps"][role], Color("ffca6c"))

func mark(step: Dictionary, tint: Color, confirmed: bool = false) -> void:
	if exploration.dimension == "2d":
		var ring := Line2D.new()
		ring.position = world_point(step["point"], step["height"]) + Vector2(0, -float(step["height"]) * 8.0)
		ring.points = PackedVector2Array([Vector2(-8, -1), Vector2(-2, 4), Vector2(9, -6)]) if confirmed else PackedVector2Array(
			[Vector2(-12, 0), Vector2(0, -6), Vector2(12, 0), Vector2(0, 6), Vector2(-12, 0)])
		ring.width = 2
		ring.default_color = tint
		ring.z_index = 2
		markers.add_child(ring)
	else:
		var marker := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = .33 if confirmed else .42
		mesh.bottom_radius = mesh.top_radius
		mesh.height = .035
		mesh.radial_segments = 16 if confirmed else 4
		marker.mesh = mesh
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = tint
		marker.material_override = material
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker.position = world_point(step["point"], step["height"] + .035)
		markers.add_child(marker)

func _enter_tree() -> void:
	if plan.get("ok", false): rebuild_markers.call_deferred()

func _exit_tree() -> void:
	if not job.is_empty(): fail("The drill preview closed during the response. Restart to dispatch again.")
	clear_markers()
