extends "res://tools/test_cycling.gd"

var host: Control
var guest: Control

func synchronized() -> bool:
	var a: RefCounted = host.cooperative_tools
	var b: RefCounted = guest.cooperative_tools
	return a.participating and b.participating and not a.dirty and not b.dirty and b.session.pending.is_empty() and a.snapshot() == b.snapshot()

func wait_for(predicate: Callable) -> bool:
	for frame in 1000:
		if predicate.call(): return true
		await process_frame
	return false

func run() -> void:
	host = load("res://scenes/builder.tscn").instantiate()
	guest = load("res://scenes/builder.tscn").instantiate()
	for editor in [host,guest]:
		editor.storage_enabled = false
		root.add_child(editor)
	while not host.enhancements_ready or not guest.enhancements_ready: await process_frame
	host.consumer_shell.dismiss_welcome()
	guest.consumer_shell.dismiss_welcome()
	studio = host
	var ids: Dictionary = setup("2d")
	host.current().data["cycling"] = {"enabled":true}
	host.current().data["protected_areas"] = [{"uid":"route_plot","name":"Protected cycle route","owner":"host","rect":[-160,-160,320,320]}]
	host.changed()
	var a: RefCounted = host.cooperative_tools
	var b: RefCounted = guest.cooperative_tools
	a.name_field.text = "Cycle host"
	a.password.text = "cycle-fixture"
	a.port.value = 0
	a.host_game()
	if not check(a.session.server != null,"The host opens a real session."): quit(1); return
	b.name_field.text = "Cycle guest"
	b.password.text = a.password.text
	b.address.text = "127.0.0.1"
	b.port.value = a.session.server.get_local_port()
	b.join_game()
	if not check(await wait_for(synchronized),"Both peers converge on the tagged roads."): quit(1); return
	studio = guest
	studio.switch_mode("2d")
	tools = guest.cycling_tools
	world = guest.worlds["2d"]
	driver = world.exploration.driving
	course = world.exploration.cycling
	driver.set_physics_process(false)
	course.set_physics_process(false)
	guest._command("cycling",null)
	var protected: Dictionary = a.session.data.duplicate(true)
	check(tools.city.disabled,"Guests cannot change the shared cycling setting.")
	author(ids["bike"],ids["rack"])
	check(tools.notice.text.contains("Protected") and a.session.data == protected
		and not guest.current().object(ids["bike"]).has("cycling"),"The protected plot rejects a guest rack assignment.")
	a.selected = "route_plot"
	a.remove_area()
	check(await wait_for(func()->bool: return synchronized() and host.current().data["protected_areas"].is_empty()),"The host opens the route for editing.")
	var baseline: Dictionary = a.session.data.duplicate(true)
	author(ids["bike"],ids["rack"])
	var accepted: bool = await wait_for(func()->bool: return synchronized() and host.current().object(ids["bike"]).has("cycling"))
	if check(accepted,"The guest rack assignment synchronizes after access is granted."):
		var shared: Dictionary = a.session.data.duplicate(true)
		await walk()
		if await board(ids["bike"]):
			drive_frames(100,Vector2.DOWN)
			var local: Node = host.worlds["2d"].exploration.driving
			check(local.active.is_empty() and local.parked.is_empty() and a.session.data == shared and synchronized(),
				"The guest ride moves no shared authored position and leaves the host preview separate.")
		guest.set_walking(false)
		guest._command("undo",null)
		check(await wait_for(func()->bool: return synchronized() and a.session.data == baseline)
			and driver.active.is_empty() and driver.parked.is_empty(),"Shared Undo restores exact authored data and releases the local ride.")
		guest._command("redo",null)
		check(await wait_for(func()->bool: return synchronized() and a.session.data == shared),"Shared Redo restores the linked route.")
		var doc: RefCounted = guest.current()
		guest.cycling_tools.brush(1)
		doc.checkpoint()
		Plan.Roads.paint(doc.data,Vector2i(2,0),Vector2i(2,0),false,guest.road_settings.settings())
		guest.changed()
		doc.finish_checkpoint(true)
		check(await wait_for(func()->bool: return synchronized() and Plan.Roads.lookup(host.current().data)["2,0"]["cycle_access"] == "none"),
			"The shared road brush updates the actual route access on both peers.")
		guest._command("undo",null)
		check(await wait_for(func()->bool: return synchronized() and a.session.data == shared),"Shared Undo restores the cycle connection.")
	b.leave()
	a.leave()
	guest.free()
	host.free()
	await settle()
	print("CYCLING COOPERATIVE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
