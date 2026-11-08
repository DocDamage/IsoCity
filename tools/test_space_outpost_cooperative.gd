extends "res://tools/test_space_outpost_workflow.gd"

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
	var doc := Document.new()
	doc.data = Templates.make("2d", "blank")
	studio.documents["2d"] = doc
	studio.changed()
	studio._command("space_outpost", null)
	studio.outpost_tools.build_practice()
	if not check(Plan.settings(doc.data)["enabled"], "Host builds the outpost through its normal inspector."):
		quit(1)
		return
	var a: RefCounted = studio.cooperative_tools
	var b: RefCounted = guest.cooperative_tools
	a.name_field.text = "Outpost host"
	a.password.text = "outpost-fixture"
	a.port.value = 0
	a.host_game()
	if not check(a.session.server != null, "Host opens a real TCP session."):
		quit(1)
		return
	b.name_field.text = "Outpost guest"
	b.password.text = a.password.text
	b.address.text = "127.0.0.1"
	b.port.value = a.session.server.get_local_port()
	b.join_game()
	if not check(await until(func() -> bool: return synced() and Plan.settings(guest.current().data)["enabled"]),
		"Guest receives the host's dock and schedule."):
		quit(1)
		return
	var before: Dictionary = a.session.data.duplicate(true)
	guest._command("space_outpost", null)
	check(guest.outpost_tools.apply.disabled and guest.outpost_tools.practice.disabled, "Guest settings and template controls are guarded.")
	guest.outpost_tools.enabled.set_pressed_no_signal(false)
	guest.outpost_tools.save()
	check(a.session.data == before and not b.dirty, "Guest cannot author a schedule update.")
	var world: Node = guest.worlds["2d"]
	var runtime: Node = world.exploration.outpost
	var dock: Dictionary = runtime.network["docks"]["outpost_dock"]
	world.player.teleport_to(runtime.draw_point(dock["stand"], dock["stand_height"]))
	guest.set_walking(true)
	if not check(await phase(runtime, "arrival", 240), "Guest launches a local ship from the shared schedule."):
		quit(1)
		return
	check(studio.worlds["2d"].exploration.outpost.job.is_empty() and a.session.data == before,
		"Guest arrival creates no host job or shared layout change.")
	doc.checkpoint()
	doc.object("outpost_dock")["visible"] = false
	studio.changed()
	doc.finish_checkpoint()
	check(await until(func() -> bool: return synced() and runtime.job.is_empty() and runtime.network["docks"].is_empty()),
		"Host changes invalidate the guest's in-flight arrival.")
	check(runtime.leases.current("space_outpost:outpost_dock").is_empty(), "Guest cancellation releases dock ownership.")
	studio._command("undo", null)
	check(await until(func() -> bool: return synced() and a.session.data == before and runtime.network["docks"].has("outpost_dock")),
		"Shared Undo restores the exact dock and ready approach.")
	guest.set_walking(false)
	b.leave()
	a.leave()
	guest.free()
	studio.free()
	await settle()
	print("SPACE OUTPOST COOPERATIVE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
