extends "res://tools/test_camping.gd"

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
	host.consumer_shell.dismiss_welcome()
	guest.consumer_shell.dismiss_welcome()
	studio = host
	var ids: Array[Dictionary] = fixture("2d")
	host.current().data["camping"] = {"enabled":true}
	host.current().data["protected_areas"] = [{"uid":"camp-plot","name":"Protected campsite","owner":"host","rect":[-1000,-1000,2000,2000]}]
	host.changed()
	var first: RefCounted = host.cooperative_tools
	var second: RefCounted = guest.cooperative_tools
	first.name_field.text = "Camping host"
	first.password.text = "camping-fixture"
	first.port.value = 0
	first.host_game()
	if not check(first.session.server != null,"A real host opens the campsite project."): quit(1); return
	second.name_field.text = "Camping guest"
	second.password.text = first.password.text
	second.address.text = "127.0.0.1"
	second.port.value = first.session.server.get_local_port()
	second.join_game()
	if not check(await wait_for(synchronized),"The two peers share an identical campsite project."): quit(1); return
	studio = guest
	studio.switch_mode("2d")
	tools = guest.camping_tools
	world = guest.worlds["2d"]
	camp = world.exploration.camping
	clock = guest.business_tools.managers["2d"]
	camp.set_physics_process(false)
	clock.set_physics_process(false)
	guest._command("camping",null)
	var protected: Dictionary = first.session.data.duplicate(true)
	check(tools.apply_city.disabled,"The shared city setting belongs to the host.")
	author(ids[0])
	check(tools.message.text.contains("Protected") and first.session.data == protected and camp.sites(CITY).is_empty(),
		"A guest cannot configure a campsite in a host-protected plot.")
	first.selected = "camp-plot"
	first.remove_area()
	check(await wait_for(func()->bool: return synchronized() and host.current().data["protected_areas"].is_empty()),
		"The host opens the plot for editing.")
	var baseline: Dictionary = first.session.data.duplicate(true)
	author(ids[1],2,true)
	var remote: Node = host.worlds["2d"].exploration.camping
	var edited: bool = await wait_for(func()->bool: return synchronized() and remote.sites(CITY).has(ids[1]["site"]))
	if check(edited,"The authorized campsite edit reaches both peers."):
		var shared: Dictionary = first.session.data.duplicate(true)
		var site: Dictionary = camp.sites(CITY)[ids[1]["site"]]
		check(site["config"]["capacity"] == 2 and site["config"]["overnight"],"The shared campsite retains both sleeping spaces and overnight hours.")
		await begin_walk()
		clock.hour = 17
		await use(site["entry"],"Reserve")
		check(camp.jobs.has("player") and remote.jobs.is_empty() and first.session.data == shared and synchronized(),
			"A guest booking remains local to that preview.")
		remote.clock.hour = 17
		check(remote.book("host-local",remote.sites(CITY)[ids[1]["site"]],CITY,host.worlds["2d"].player)
			and remote.jobs["host-local"]["slot"] == camp.jobs["player"]["slot"],
			"Independent worlds can reserve the same slot at the same site UID.")
		remote.finish("host-local","Local verification visit ended.")
		guest.set_walking(false)
		guest._command("undo",null)
		var restored: bool = await wait_for(func()->bool:
			return synchronized() and first.session.data == baseline and camp.jobs.is_empty() and remote.sites(CITY).is_empty())
		check(restored,"Shared Undo restores exact authored state and releases the preview booking.")
	second.leave()
	first.leave()
	guest.free()
	host.free()
	await settle()
	print("CAMPING COOPERATIVE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
