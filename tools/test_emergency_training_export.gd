extends SceneTree

const Training = preload("res://scripts/builder/emergency_training_plan.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, text: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + text)
	return ok

func frame() -> void:
	for index in 4: await physics_frame
	await RenderingServer.frame_post_draw

func use_step(city: Node, runtime: Node, role: String) -> void:
	var target: Dictionary = runtime.plan["steps"][role]
	var player: Node = city.player
	player.teleport_to(runtime.world_point(target["point"], target["height"] + .025))
	await frame()
	var key := InputEventKey.new()
	key.keycode = KEY_E
	key.pressed = true
	city._unhandled_input(key)

func run() -> void:
	var city: Node = load("res://city.tscn").instantiate()
	root.add_child(city)
	await frame()
	city.walking = true
	city._set_mode()
	var runtime: Node = city.exploration.emergency
	var service: Node = city.services
	service.set_physics_process(false)
	runtime.set_process(false)
	city.player.set_physics_process(false)
	await frame()
	var original: Dictionary = city.studio_data.duplicate(true)
	if not check(Training.valid(original["scenario"]) and runtime.plan.get("ok", false) and city.scenario.panel.visible,
		"Exported drill setup and goals load independently."): quit(1); return
	var recipe: String = original["scenario"]["id"]
	await use_step(city, runtime, "desk")
	if not check(runtime.dispatched and runtime.job.get("training") == original["scenario"]["attempt"],
		"The portable Interact key dispatches the owned request."): quit(1); return
	service.step(.2)
	check(service.crews.has(runtime.job["id"]) and runtime.job["station"] == original["scenario"]["station"],
		"Independent service preview spawns the assigned vehicle.")
	if recipe == "medical_drill":
		await use_step(city, runtime, "kit")
	for index in original["scenario"]["perimeter"].size(): await use_step(city, runtime, "perimeter_%d" % index)
	check(runtime.secured == original["scenario"]["perimeter"].size() and runtime.kit_collected == (recipe == "medical_drill"),
		"Perimeter and scenario-specific kit actions use their physical placements.")
	await use_step(city, runtime, "subject")
	check(runtime.assisted and runtime.phase == "return", "The supplied participant has an observable assistance step.")
	await use_step(city, runtime, "desk")
	check(runtime.phase == "return" and runtime.receipts.is_empty(), "The report waits for the real crew to return.")
	for index in 12000:
		service.step(1.0 / 60)
		runtime._process(1.0 / 60)
		if runtime.response_returned or runtime.phase == "failed": break
	check(runtime.response_returned, "Independent service road and walking route finishes: " + runtime.notice)
	await use_step(city, runtime, "desk")
	check(runtime.phase == "complete" and runtime.receipts.size() == 1, "Report back records one local receipt.")
	await use_step(city, runtime, "desk")
	check(runtime.receipts.size() == 1 and original == city.studio_data, "Reviewing completion leaves saved layout and treasury exact.")
	city.free()
	await process_frame
	print("PORTABLE EMERGENCY TRAINING: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
