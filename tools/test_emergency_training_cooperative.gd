extends "res://tools/test_emergency_training_workflow.gd"

var guest: Control

func synced() -> bool:
	var a: RefCounted = studio.cooperative_tools
	var b: RefCounted = guest.cooperative_tools
	return a.participating and b.participating and not a.dirty and not b.dirty and b.session.pending.is_empty() and a.session.data == b.session.data

func until(condition: Callable) -> bool:
	for frame in 1100:
		if condition.call(): return true
		await process_frame
	return false

func run() -> void:
	studio = load("res://scenes/builder.tscn").instantiate()
	guest = load("res://scenes/builder.tscn").instantiate()
	for editor in [studio, guest]:
		editor.storage_enabled = false
		root.add_child(editor)
	while not studio.enhancements_ready or not guest.enhancements_ready: await process_frame
	for editor in [studio, guest]:
		editor.consumer_shell.dismiss_welcome()
		editor.switch_mode("2d")
	var doc: RefCounted = setup("2d")
	studio._command("challenges", "fire_drill")
	studio.scenario_tools.build_drill()
	if not check(Plan.recognized(doc.data.get("scenario", {}).get("id")), "Host creates the reviewed drill through Challenges."): quit(1); return
	var a: RefCounted = studio.cooperative_tools
	var b: RefCounted = guest.cooperative_tools
	a.name_field.text = "Training host"
	a.password.text = "training-fixture"
	a.port.value = 0
	a.host_game()
	if not check(a.session.server != null, "Training host opens a real session."): quit(1); return
	b.name_field.text = "Training guest"
	b.password.text = a.password.text
	b.address.text = "127.0.0.1"
	b.port.value = a.session.server.get_local_port()
	b.join_game()
	if not check(await until(func() -> bool: return synced() and guest.current().data.get("scenario", {}).get("id") == "fire_drill"),
		"Shared scenario, station and perimeter references reach the guest."): quit(1); return
	var before: Dictionary = a.session.data.duplicate(true)
	guest._command("challenges", "fire_drill")
	guest.scenario_tools.start_challenge()
	guest.scenario_tools.stop_challenge()
	check("host" in guest.status.text.to_lower() and a.session.data == before, "Guest cannot restart or stop the authored shared challenge.")
	var world: Node = guest.worlds["2d"]
	var runtime: Node = world.exploration.emergency
	guest.set_walking(true)
	move_to(runtime, "desk")
	await settle()
	guest.control_settings.execute("interact")
	if not check(runtime.dispatched and not studio.worlds["2d"].exploration.emergency.dispatched,
		"Guest dispatch is real and local to that peer."): quit(1); return
	var job: Dictionary = runtime.job
	runtime.services.step(.2)
	check(runtime.services.crews.has(job["id"]) and a.session.data == before and not b.dirty, "The guest crew spawns without changing shared city or treasury.")
	doc.checkpoint()
	doc.data["roads"] = []
	studio.changed()
	doc.finish_checkpoint()
	check(await until(func() -> bool: return synced() and runtime.phase == "failed" and job["state"] == "cancelled"),
		"A shared road edit invalidates the actual guest drill.")
	check(not runtime.services.crews.has(job["id"]) and runtime.services.dispatch.units.is_empty(), "The invalidated guest request releases crew and station ownership.")
	studio._command("undo", null)
	check(await until(func() -> bool: return synced() and a.session.data == before and runtime.plan.get("ok", false)),
		"Shared Undo restores the exact response layout.")
	studio._command("challenges", "fire_drill")
	studio.scenario_tools.start_challenge()
	check(await until(func() -> bool: return synced() and runtime.phase == "dispatch" and runtime.attempt != before["2d"]["scenario"]["attempt"]),
		"Host Restart creates a fresh attempt on the guest.")
	move_to(runtime, "desk")
	await settle()
	guest.control_settings.execute("interact")
	check(runtime.dispatched, "Guest can dispatch the restored route.")
	var stopped: Dictionary = runtime.job
	studio.scenario_tools.stop_challenge()
	check(await until(func() -> bool: return synced() and runtime.attempt.is_empty() and stopped.get("state") == "cancelled"),
		"Host Stop releases the active guest request and field markers.")
	guest.set_walking(false)
	b.leave()
	a.leave()
	guest.free()
	studio.free()
	await settle()
	print("EMERGENCY TRAINING COOPERATIVE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
