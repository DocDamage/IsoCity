extends "res://tools/test_fitness.gd"

const Protection = preload("res://scripts/builder/cooperative_plan.gd")
var host: Control
var guest: Control

func synchronized() -> bool:
	var first: RefCounted = host.cooperative_tools
	var second: RefCounted = guest.cooperative_tools
	return first.participating and second.participating and not first.dirty and not second.dirty \
		and second.session.pending.is_empty() and first.snapshot() == second.snapshot()

func wait_for(condition: Callable) -> bool:
	for frame in 1000:
		if condition.call(): return true
		await process_frame
	return false

func run() -> void:
	host = load("res://scenes/builder.tscn").instantiate()
	guest = load("res://scenes/builder.tscn").instantiate()
	for editor in [host,guest]:
		editor.storage_enabled = false
		root.add_child(editor)
	while not host.enhancements_ready or not guest.enhancements_ready: await process_frame
	for editor in [host,guest]:
		editor.consumer_shell.dismiss_welcome()
		editor.switch_mode("2d")
		editor.economy_tools.pauses["2d"] = true
	studio = host
	tools = host.fitness_tools
	await setup_gym("2d")
	var doc: RefCounted = host.current()
	var area: Rect2 = Protection.object_rect(doc.object(site),"2d",host.library).grow(2)
	doc.data["protected_areas"] = [{"uid":"gym","name":"Host gym","owner":"host",
		"rect":[area.position.x,area.position.y,area.size.x,area.size.y]}]
	host.changed()
	var first: RefCounted = host.cooperative_tools
	var second: RefCounted = guest.cooperative_tools
	first.name_field.text = "Gym host"
	first.password.text = "sports-fixture"
	first.port.value = 0
	first.host_game()
	check(first.session.server != null,"Host starts from a protected gym.")
	if first.session.server == null: quit(1); return
	second.name_field.text = "Gym guest"
	second.password.text = first.password.text
	second.address.text = "127.0.0.1"
	second.port.value = first.session.server.get_local_port()
	second.join_game()
	var ready: bool = await wait_for(synchronized)
	check(ready,"Both peers synchronize the nested gym and schedules.")
	if not ready: second.leave(); first.leave(); quit(1); return
	studio = guest
	tools = guest.fitness_tools
	world = guest.worlds["2d"]
	fitness = world.exploration.fitness
	fitness.set_physics_process(false)
	clock = guest.business_tools.managers["2d"]
	clock.set_physics_process(false)
	clock.hour = 10
	guest._command("fitness",null)
	check(tools.apply_city.disabled,"The shared sports switch belongs to the host.")
	var protected: Dictionary = first.session.data.duplicate(true)
	guest.interior_tools.start(site,"ground","empty")
	guest._command("fitness",null)
	author(stations["treadmill"],8,17)
	check(tools.message.text.contains("Protected") and first.session.data == protected,
		"Guest cannot edit a schedule inside the protected gym.")
	guest.interior_tools.leave()
	first.selected = "gym"
	first.remove_area()
	check(await wait_for(func(): return synchronized() and host.current().data["protected_areas"].is_empty()),
		"Host releases the gym for authoring.")
	var before: Dictionary = first.session.data.duplicate(true)
	guest.interior_tools.start(site,"ground","empty")
	guest._command("fitness",null)
	author(stations["treadmill"],8,17)
	guest.interior_tools.leave()
	check(await wait_for(func(): return synchronized() and first.session.data != before),"The authorized schedule converges.")
	var authored: Dictionary = first.session.data.duplicate(true)
	if await enter() and await menu("treadmill") and reserve_and_start():
		step(12.5)
		check(fitness.last_result.get("status") == "completed" and host.worlds["2d"].exploration.fitness.history.is_empty()
			and first.session.data == authored,"Guest workouts, reservations and results are local to that preview.")
	guest.set_walking(false)
	guest._command("undo",null)
	check(await wait_for(func(): return synchronized() and first.session.data == before),
		"Shared Undo restores the exact owned room state.")
	second.leave()
	first.leave()
	check(fitness.history.is_empty() and fitness.locks.is_empty(),"Leaving co-op clears the sports preview.")
	guest.free()
	host.free()
	await settle()
	print("FITNESS COOPERATIVE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
