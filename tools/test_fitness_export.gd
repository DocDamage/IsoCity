extends SceneTree

const Plan = preload("res://scripts/builder/fitness_plan.gd")
const Court = preload("res://scripts/builder/fitness_court.gd")
var scene: Node
var checks: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + message)

func frames(count: int) -> void:
	for frame in count: await physics_frame

func finish() -> void:
	scene.free()
	await process_frame
	print("PORTABLE FITNESS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func run() -> void:
	scene = load("res://city.tscn").instantiate()
	root.add_child(scene)
	await frames(8)
	var walk: Node = scene.exploration
	var runtime: Node = walk.fitness
	var goal: String = scene.studio_data["objects"][0]["uid"]
	check(Plan.enabled(scene.studio_data) and runtime.history.is_empty() and runtime.booking.is_empty(),
		"The standalone layout has a saved schedule and a fresh sports preview.")
	check(Plan.definitions()["ball"] in Plan.required_art(scene.studio_data)
		and Court.ball_texture(walk.library,Plan.definitions()["ball"]) != null,
		"The exported court resolves its future supplied ball.")
	scene.businesses.hour = 22
	scene.walking = true
	scene._set_mode()
	scene.player.set_physics_process(false)
	var candidate: Dictionary = runtime.local_station(goal)
	check(not candidate.is_empty(),"The standalone court resolves its real placed goal.")
	if candidate.is_empty(): await finish(); return
	var frame: Dictionary = Court.frame_for(candidate,walk)
	var point: Variant = Court.world_point(frame,Vector3(0,0,Court.STANCE))
	scene.player.teleport_to(scene.player.get_parent().to_local(point))
	await frames(4)
	walk.interaction_prompt()
	check(walk.nearby.get("fitness") == goal,"Normal exploration reaches the launch mark.")
	walk.interact()
	check(runtime.menu.get("uid") == goal and runtime.view.primary.text == "Reserve slot",
		"Interact opens the scheduled booking UI.")
	if runtime.menu.is_empty(): await finish(); return
	runtime.view.primary.pressed.emit()
	check(runtime.view.primary.text == "Check in" and runtime.locks.size() == 1,
		"The booking holds one slot.")
	runtime.view.primary.pressed.emit()
	check(runtime.session.get("kind") == "penalty" and is_instance_valid(runtime.court.ball),
		"Check-in creates the actual ball at the launch mark.")
	if runtime.session.is_empty(): await finish(); return
	runtime.aim(99)
	walk.interact()
	await frames(95)
	check(runtime.session["score"] == 0 and runtime.session["shots"] == 1 and not runtime.court.flying,
		"An off-target shot travels on physics frames and misses.")
	runtime.aim(-runtime.session["aim"])
	for shot in 3:
		walk.interact()
		await frames(100)
	check(runtime.last_result.get("score") == 3 and runtime.last_result.get("shots") == 4
		and runtime.last_result.get("status") == "completed","Three physical goal crossings finish the drill.")
	check(runtime.session.is_empty() and runtime.locks.is_empty() and not is_instance_valid(runtime.court.ball),
		"The completed activity restores control and removes temporary state.")
	await finish()
