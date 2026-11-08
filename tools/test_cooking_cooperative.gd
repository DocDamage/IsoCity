extends "res://tools/test_cooking.gd"

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
	tools = host.cooking_tools
	await setup("2d")
	var doc: RefCounted = host.current()
	for item in doc.object(cafe)["interior"]["objects"]:
		if item["uid"] == stations["prep"]: item["cooking"]["enabled"] = false
	var area: Rect2 = Protection.object_rect(doc.object(cafe),"2d",host.library).grow(2)
	doc.data["protected_areas"] = [{"uid":"site","name":"Host café","owner":"host",
		"rect":[area.position.x,area.position.y,area.size.x,area.size.y]}]
	host.changed()
	var first: RefCounted = host.cooperative_tools
	var second: RefCounted = guest.cooperative_tools
	first.name_field.text = "Kitchen host"
	first.password.text = "kitchen-fixture"
	first.port.value = 0
	first.host_game()
	check(first.session.server != null,"The host starts from the protected café.")
	if first.session.server == null: quit(1); return
	second.name_field.text = "Kitchen guest"
	second.password.text = first.password.text
	second.address.text = "127.0.0.1"
	second.port.value = first.session.server.get_local_port()
	second.join_game()
	var ready: bool = await wait_for(synchronized)
	check(ready,"Both peers synchronize the nested kitchen and its settings.")
	if not ready: second.leave(); first.leave(); quit(1); return
	studio = guest
	tools = guest.cooking_tools
	world = guest.worlds["2d"]
	cook = world.exploration.cooking
	cook.set_physics_process(false)
	business = guest.business_tools.managers["2d"]
	business.set_physics_process(false)
	guest._command("cooking",null)
	check(tools.apply_city.disabled,"The shared cooking switch belongs to the host.")
	var protected: Dictionary = first.session.data.duplicate(true)
	guest.interior_tools.start(cafe,"ground","empty")
	guest._command("cooking",null)
	author(stations["prep"])
	check(tools.message.text.contains("Protected") and first.session.data == protected,
		"Guest cannot configure a station inside the protected building.")
	guest.interior_tools.leave()
	first.selected = "site"
	first.remove_area()
	check(await wait_for(func(): return synchronized() and host.current().data["protected_areas"].is_empty()),
		"Host opens the café to editing.")
	var before: Dictionary = first.session.data.duplicate(true)
	guest.interior_tools.start(cafe,"ground","empty")
	guest._command("cooking",null)
	author(stations["prep"])
	guest.interior_tools.leave()
	check(await wait_for(func(): return synchronized() and first.session.data != before),"Authorized nested station converges on both peers.")
	var authored: Dictionary = first.session.data.duplicate(true)
	if await enter():
		await heat()
		seconds(5)
		await arrive("serve")
		world.exploration.interact()
		seconds(1)
		check(stock().get(DISH,0)==1 and host.worlds["2d"].exploration.cooking.kitchens.is_empty() and first.session.data==authored,
			"Guest cooks a local dish without changing the shared city or host pantry.")
	guest.set_walking(false)
	guest._command("undo",null)
	check(await wait_for(func(): return synchronized() and first.session.data == before),
		"Shared Undo restores the exact authored floor state.")
	second.leave()
	first.leave()
	guest.free()
	host.free()
	await settle()
	print("COOKING COOPERATIVE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
