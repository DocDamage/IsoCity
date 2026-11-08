extends "res://tools/test_harbor_workflow.gd"

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
	var host_panel: RefCounted = studio.harbor_tools
	host_panel.build_practice()
	if not check(Plan.enabled(doc.data), "The host authors a real harbor in Studio."): quit(1); return
	var a: RefCounted = studio.cooperative_tools
	var b: RefCounted = guest.cooperative_tools
	a.name_field.text = "Harbor host"
	a.password.text = "harbor-fixture"
	a.port.value = 0
	a.host_game()
	if not check(a.session.server != null, "A real harbor host starts."): quit(1); return
	b.name_field.text = "Harbor guest"
	b.password.text = a.password.text
	b.address.text = "127.0.0.1"
	b.port.value = a.session.server.get_local_port()
	b.join_game()
	if not check(await until(func() -> bool: return synced() and Plan.enabled(guest.current().data)),
		"Dock and ferry definitions reach the guest."): quit(1); return
	var before: Dictionary = a.session.data.duplicate(true)
	var panel: RefCounted = guest.harbor_tools
	guest._command("harbors", null)
	panel.enabled.set_pressed_no_signal(false)
	panel.save()
	check(panel.apply.disabled and a.session.data == before and Plan.enabled(guest.current().data),
		"The guest cannot change the shared harbor configuration.")
	var world: Node = guest.worlds["2d"]
	var source_spawn: Array = guest.current().data["spawn"]
	world.player.teleport_to(Vector2(source_spawn[0], source_spawn[1]))
	guest.set_walking(true)
	var harbor: Node = world.exploration.harbor
	if not check(await until(func() -> bool: return harbor.boats.has("pilot")), "Guest sees the shared trireme."): quit(1); return
	world.exploration.interact()
	check(harbor.active() and not studio.worlds["2d"].exploration.harbor.active(), "Boarding is local to the guest.")
	for frame in 25: harbor.steer(.05, Vector2.RIGHT)
	check(harbor.boats["pilot"]["point"].x > 4 and a.session.data == before and not a.dirty and not b.dirty,
		"Pilot position, wake and dock claims remain local.")
	studio._command("harbors", null)
	host_panel.enabled.set_pressed_no_signal(false)
	host_panel.save()
	check(await until(func() -> bool: return synced() and not Plan.enabled(guest.current().data) and harbor.claims.is_empty() and not harbor.active()),
		"Host shutdown invalidates the trip and safely clears guest claims.")
	check(world.player.visible and world.terrain_traversal.safe_position(world.player.global_position),
		"The guest returns to dry land after the shared shutdown.")
	studio._command("undo", null)
	check(await until(func() -> bool: return synced() and a.session.data == before and harbor.boats.has("pilot")),
		"Shared Undo restores the harbor and respawns both assigned boats.")
	studio._command("redo", null)
	check(await until(func() -> bool: return synced() and not Plan.enabled(guest.current().data) and harbor.boats.is_empty()),
		"Shared Redo stops the harbor again.")
	guest.set_walking(false)
	b.leave()
	a.leave()
	guest.free()
	studio.free()
	await settle()
	print("HARBOR COOPERATIVE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
