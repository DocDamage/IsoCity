extends "res://tools/test_laundry.gd"

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
	for editor in [host, guest]:
		editor.storage_enabled = false
		root.add_child(editor)
	while not host.enhancements_ready or not guest.enhancements_ready: await process_frame
	for editor in [host, guest]:
		editor.consumer_shell.dismiss_welcome()
		editor.switch_mode("2d")
		editor.economy_tools.pauses["2d"] = true
	studio = host
	tools = host.laundry_tools
	await setup("2d")
	var doc: RefCounted = host.current()
	for item in doc.object(host_uid)["interior"]["objects"]:
		if item["uid"] == stations["wash"]: item["laundry"]["capacity"] = 2
	var area: Rect2 = Protection.object_rect(doc.object(host_uid), "2d", host.library).grow(2)
	doc.data["protected_areas"] = [{"uid":"site","name":"Host laundry","owner":"host",
		"rect":[area.position.x,area.position.y,area.size.x,area.size.y]}]
	host.changed()
	var first: RefCounted = host.cooperative_tools
	var second: RefCounted = guest.cooperative_tools
	first.name_field.text = "Laundry host"
	first.password.text = "laundry-fixture"
	first.port.value = 0
	first.host_game()
	check(first.session.server != null, "Host starts from a protected laundry.")
	if first.session.server == null: quit(1); return
	second.name_field.text = "Laundry guest"
	second.password.text = first.password.text
	second.address.text = "127.0.0.1"
	second.port.value = first.session.server.get_local_port()
	second.join_game()
	var ready: bool = await wait_for(synchronized)
	check(ready, "Both peers synchronize the owned facility and capacity.")
	if not ready: second.leave(); first.leave(); quit(1); return
	studio = guest
	tools = guest.laundry_tools
	world = guest.worlds["2d"]
	laundry = world.exploration.laundry
	laundry.set_physics_process(false)
	guest._command("laundry", null)
	check(tools.apply_city.disabled, "The shared laundry switch belongs to the host.")
	var protected: Dictionary = first.session.data.duplicate(true)
	guest.interior_tools.start(host_uid,"ground","empty")
	guest._command("laundry", null)
	author(stations["wash"], 4)
	check(tools.message.text.contains("Protected") and first.session.data == protected,
		"A guest cannot change capacity in a protected owned room.")
	guest.interior_tools.leave()
	first.selected = "site"
	first.remove_area()
	check(await wait_for(func(): return synchronized() and host.current().data["protected_areas"].is_empty()),
		"The host releases the facility for authoring.")
	var before: Dictionary = first.session.data.duplicate(true)
	guest.interior_tools.start(host_uid,"ground","empty")
	guest._command("laundry", null)
	author(stations["wash"], 4)
	guest.interior_tools.leave()
	check(await wait_for(func(): return synchronized() and first.session.data != before), "Authorized capacity converges on both peers.")
	var authored: Dictionary = first.session.data.duplicate(true)
	if await enter():
		var site: Dictionary = await counter()
		if not site.is_empty():
			var load_received: Dictionary = receive_with_button("jules")
			advance(.25)
			check(not load_received.is_empty() and load_received.get("station") == stations["wash"]
				and host.worlds["2d"].exploration.laundry.facilities.is_empty() and first.session.data == authored,
				"The guest's order, dose and reservation remain local to that session.")
	guest.set_walking(false)
	guest._command("undo", null)
	check(await wait_for(func(): return synchronized() and first.session.data == before),
		"Shared Undo restores the exact authorized floor state.")
	second.leave()
	first.leave()
	check(laundry.facilities.is_empty(), "Leaving co-op releases transient orders and reservations.")
	guest.free()
	host.free()
	await settle()
	print("LAUNDRY COOPERATIVE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
