extends "res://tools/test_arcade.gd"

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
	tools = host.arcade_tools
	await setup("2d")
	var doc: RefCounted = host.current()
	var area: Rect2 = Protection.object_rect(doc.object(building),"2d",host.library).grow(2)
	doc.data["protected_areas"] = [{"uid":"arcade","name":"Host arcade","owner":"host",
		"rect":[area.position.x,area.position.y,area.size.x,area.size.y]}]
	host.changed()
	var first: RefCounted = host.cooperative_tools
	var second: RefCounted = guest.cooperative_tools
	first.name_field.text = "Arcade host"
	first.password.text = "arcade-fixture"
	first.port.value = 0
	first.host_game()
	check(first.session.server != null,"Host starts from a protected arcade.")
	if first.session.server == null: quit(1); return
	second.name_field.text = "Arcade guest"
	second.password.text = first.password.text
	second.address.text = "127.0.0.1"
	second.port.value = first.session.server.get_local_port()
	second.join_game()
	var ready: bool = await wait_for(synchronized)
	check(ready,"Both peers synchronize the cabinet assignments and room.")
	if not ready: second.leave(); first.leave(); quit(1); return
	studio = guest
	tools = guest.arcade_tools
	world = guest.worlds["2d"]
	arcade = world.exploration.arcade
	arcade.set_physics_process(false)
	guest._command("arcade",null)
	check(tools.apply_city.disabled,"The shared arcade switch belongs to the host.")
	var protected: Dictionary = first.session.data.duplicate(true)
	guest.interior_tools.start(building,"ground","empty")
	guest._command("arcade",null)
	author(cabinets["sprint"],"signals")
	check(tools.message.text.contains("Protected") and first.session.data == protected,
		"A guest cannot assign a game to a protected nested cabinet.")
	guest.interior_tools.leave()
	first.selected = "arcade"
	first.remove_area()
	check(await wait_for(func(): return synchronized() and host.current().data["protected_areas"].is_empty()),
		"Host releases the arcade for authoring.")
	var before: Dictionary = first.session.data.duplicate(true)
	guest.interior_tools.start(building,"ground","empty")
	guest._command("arcade",null)
	author(cabinets["sprint"],"signals")
	guest.interior_tools.leave()
	check(await wait_for(func(): return synchronized() and first.session.data != before),"Authorized game assignment converges.")
	var authored: Dictionary = first.session.data.duplicate(true)
	if await enter() and await open("sprint"):
		arcade.primary()
		check(arcade.session["game"]=="signals" and arcade.locks.size()==2,"The shared assignment opens Signal Sequence on the guest.")
		for index in Signals.PATTERNS.size():
			step(Signals.SLOT_TICKS*Signals.PATTERNS[index].size())
			for direction in Signals.PATTERNS[index]: arcade.command(Signals.ACTIONS[direction])
			step(1)
		check(arcade.session.get("phase")=="result" and arcade.boards.get("signals",[]).size()==1
			and host.worlds["2d"].exploration.arcade.boards.is_empty() and first.session.data == authored,
			"Guest sessions and scores remain local to that preview.")
	guest.set_walking(false)
	guest._command("undo",null)
	check(await wait_for(func(): return synchronized() and first.session.data == before),
		"Shared Undo restores the exact owned-room assignment.")
	second.leave()
	first.leave()
	check(arcade.boards.is_empty() and arcade.locks.is_empty(),"Leaving co-op clears the preview and releases locks.")
	guest.free()
	host.free()
	await settle()
	print("ARCADE COOPERATIVE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
