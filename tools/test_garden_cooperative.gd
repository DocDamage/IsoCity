extends "res://tools/test_garden.gd"

const Economy = preload("res://scripts/builder/economy_plan.gd")
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
	var doc: RefCounted = host.current()
	doc.data = Templates.make("2d","blank")
	doc.data["garden"] = {"enabled":true}
	doc.data["economy"] = {"enabled":true,"starting_cash":50000}
	var bed: String = doc.add(BED["2d"],[0,0,0],"SE",1.0)["uid"]
	doc.data["protected_areas"] = [{"uid":"plot","name":"Protected garden","owner":"host","rect":[-2,-2,8,8]}]
	doc.data["economy_account"] = Economy.fresh_account(doc.data,host.library)
	host.changed()
	var first: RefCounted = host.cooperative_tools
	var second: RefCounted = guest.cooperative_tools
	first.name_field.text = "Garden host"
	first.password.text = "garden-fixture"
	first.port.value = 0
	first.host_game()
	check(first.session.server != null,"The host starts from the protected garden plot.")
	if first.session.server == null: quit(1); return
	second.name_field.text = "Garden guest"
	second.password.text = first.password.text
	second.address.text = "127.0.0.1"
	second.port.value = first.session.server.get_local_port()
	second.join_game()
	var connected: bool = await wait_for(synchronized)
	check(connected,"Two peers synchronize the authored garden settings.")
	if not connected: second.leave(); first.leave(); quit(1); return
	studio = guest
	tools = guest.garden_tools
	runtime = guest.worlds["2d"].exploration.garden
	runtime.set_process(false)
	guest._command("garden",null)
	var protected: Dictionary = first.session.data.duplicate(true)
	check(tools.settings_button.disabled,"Guests cannot alter the shared city garden switch.")
	author(bed)
	check(tools.status.text.contains("Protected") and first.session.data == protected and runtime.sites.is_empty(),
		"A guest cannot enable a host-protected site.")
	first.selected = "plot"
	first.remove_area()
	check(await wait_for(func(): return synchronized() and host.current().data["protected_areas"].is_empty()),
		"The host opens the garden plot for editing.")
	var baseline: Dictionary = first.session.data.duplicate(true)
	guest._command("garden",null)
	author(bed)
	check(await wait_for(func(): return synchronized() and host.worlds["2d"].exploration.garden.sites.has(bed)),
		"Authorized configuration converges on both peers.")
	var authored: Dictionary = first.session.data.duplicate(true)
	await begin_walk()
	await arrive(bed)
	use(bed,"Plant lettuce")
	use(bed,"Water lettuce")
	seconds(5)
	use(bed,"Water lettuce")
	seconds(3)
	use(bed,"Harvest lettuce")
	check(runtime.account["stock"].get("produce/lettuce",0) == 3 and runtime.account["cash"] == 46
		and host.worlds["2d"].exploration.garden.account["stock"].get("produce/lettuce",0) == 0
		and first.session.data == authored and synchronized(),
		"Guest harvest remains local and leaves the shared account and project unchanged.")
	use(bed,"Plant lettuce")
	studio.set_walking(false)
	guest._command("undo",null)
	check(await wait_for(func(): return synchronized() and first.session.data == baseline and runtime.crops.is_empty()),
		"Shared Undo invalidates the active crop together with its authored site.")
	second.leave()
	first.leave()
	guest.free()
	host.free()
	await settle()
	print("GARDEN COOPERATIVE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
