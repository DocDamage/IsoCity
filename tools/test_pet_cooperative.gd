extends "res://tools/test_pet.gd"

var host: Control
var guest: Control

func synchronized() -> bool:
	var first: RefCounted = host.cooperative_tools
	var second: RefCounted = guest.cooperative_tools
	return first.participating and second.participating and not first.dirty and not second.dirty \
		and second.session.pending.is_empty() and first.snapshot() == second.snapshot()

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
	var first: RefCounted = host.cooperative_tools
	var second: RefCounted = guest.cooperative_tools
	first.name_field.text = "Companion host"
	first.password.text = "pet-fixture"
	first.port.value = 0
	first.host_game()
	if not check(first.session.server != null,"The host opens a real project session."): quit(1); return
	second.name_field.text = "Companion guest"
	second.password.text = first.password.text
	second.address.text = "127.0.0.1"
	second.port.value = first.session.server.get_local_port()
	second.join_game()
	if not check(await wait_for(synchronized),"Both peers receive the same disabled companion defaults."): quit(1); return
	var baseline: Dictionary = first.session.data.duplicate(true)
	guest._command("pet",null)
	check(guest.pet_tools.apply.disabled,"Guests cannot override shared companion ownership.")
	var proposed: Dictionary = baseline.duplicate(true)
	proposed["2d"]["pet"] = {"enabled":true,"asset":DOG,"home":ids["mat"]}
	var protection = preload("res://scripts/builder/cooperative_plan.gd")
	check(protection.allowed(baseline,proposed,second.session.local_id,guest.library).contains("host"),
		"Authority rejects a crafted guest ownership edit.")
	author(DOG,["","ground",ids["mat"]],ids["station"])
	var connected: bool = await wait_for(func()->bool: return synchronized() and Plan.settings(guest.current().data)["enabled"])
	if check(connected,"Host companion settings converge on both peers."):
		var shared: Dictionary = first.session.data.duplicate(true)
		var local: Node = pet
		var remote: Node = guest.worlds["2d"].exploration.pet
		remote.set_physics_process(false)
		await begin_walk()
		guest.set_walking(true)
		guest.worlds["2d"].player.set_physics_process(false)
		await settle()
		remote.step(.016)
		if check(is_instance_valid(local.actor.body) and is_instance_valid(remote.actor.body)
			and local.actor.body.get_meta("pet_owner") == first.session.local_id
			and remote.actor.body.get_meta("pet_owner") == second.session.local_id
			and local.actor.body.get_meta("pet_owner") != remote.actor.body.get_meta("pet_owner"),
			"Each peer owns its own transient actor for the same authored companion."):
			var original: Variant = local.actor.body.global_position
			var origin: Vector2 = remote.nav.metric(remote.actor.body.global_position)
			var player: Node = guest.worlds["2d"].player
			player.teleport_to(player.get_parent().to_local(remote.nav.position(origin+Vector2(0,3))))
			remote.command("come")
			for frame in 210: remote.step(1.0/60)
			check(remote.actor.body.global_position.distance_to(original) > 2
				and local.actor.body.global_position == original and first.session.data == shared and synchronized(),
				"A guest call moves only that peer's pet and changes no shared account or document.")
		guest.set_walking(false)
		host.set_walking(false)
		local.set_physics_process(true)
		remote.set_physics_process(true)
		host._command("undo",null)
		check(await wait_for(func()->bool: return synchronized() and first.session.data == baseline),
			"Shared Undo restores the exact disabled settings.")
		await settle()
		check(not is_instance_valid(local.actor.body) and not is_instance_valid(remote.actor.body),
			"Disabling clears both transient companions.")
		host._command("redo",null)
		check(await wait_for(func()->bool: return synchronized() and first.session.data == shared),
			"Shared Redo restores the authored companion settings.")
		guest.set_walking(true)
		await settle()
		remote.step(.016)
		check(remote.companion_owner == second.session.local_id,"The connected guest keeps its stable identity.")
		second.leave()
		await settle()
		remote.step(.016)
		check(is_instance_valid(remote.actor.body) and remote.actor.body.get_meta("pet_owner") == "local",
			"Disconnect releases the peer identity and starts a local preview.")
	second.leave()
	first.leave()
	guest.free()
	host.free()
	await settle()
	print("PET COOPERATIVE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
