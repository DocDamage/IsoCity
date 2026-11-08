extends "res://tools/test_village_production.gd"

var host: Control
var guest: Control

func synchronized() -> bool:
	var first: RefCounted = host.cooperative_tools
	var second: RefCounted = guest.cooperative_tools
	return first.participating and second.participating and not first.dirty and not second.dirty and second.session.pending.is_empty() and first.snapshot() == second.snapshot()

func wait_for(condition: Callable) -> bool:
	for frame in 1200:
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
		if editor.consumer_shell: editor.consumer_shell.dismiss_welcome()
	studio = host
	setup("3d")
	host.current().data["village"] = {"enabled":true}
	host.current().data["protected_areas"] = [{"uid":"farm_plot","name":"Protected farm","owner":"host","rect":[-31,-6,12,12]}]
	host.changed()
	author("granary")
	var first: RefCounted = host.cooperative_tools
	var second: RefCounted = guest.cooperative_tools
	first.name_field.text = "Village host"
	first.password.text = "village-fixture"
	first.port.value = 0
	first.host_game()
	if not check(first.session.server != null,"Open a real village host session."): quit(1); return
	second.name_field.text = "Village guest"
	second.password.text = first.password.text
	second.address.text = "127.0.0.1"
	second.port.value = first.session.server.get_local_port()
	second.join_game()
	if not check(await wait_for(synchronized),"Peers share the authored village and protected farm."): quit(1); return
	studio = guest
	guest.switch_mode("3d")
	check(host.worlds["3d"].exploration.village.book.sites.has("granary") and guest.worlds["3d"].exploration.village.book.sites.has("granary"),
		"New sessions immediately compile the shared facility and start with fresh stock.")
	world = guest.worlds["3d"]
	runtime = world.exploration.village
	runtime.set_physics_process(false)
	tools = guest.village_tools
	guest._command("village",null)
	check(tools.apply_city.disabled,"Guests cannot enable or disable shared village production.")
	var protected: Dictionary = first.session.data.duplicate(true)
	author("farm")
	check(tools.notice.text.contains("Protected") and first.session.data == protected and not guest.current().object("farm").has("village"),
		"Guest facility edits respect the protected plot. "+tools.notice.text)
	first.selected = "farm_plot"
	first.remove_area()
	check(await wait_for(func()->bool: return synchronized() and host.current().data["protected_areas"].is_empty()),"The host opens the farm for editing.")
	var baseline: Dictionary = first.session.data.duplicate(true)
	author("farm")
	if check(await wait_for(func()->bool: return synchronized() and host.current().object("farm").has("village")),"The allowed guest facility link synchronizes."):
		var shared: Dictionary = first.session.data.duplicate(true)
		await walk()
		for frame in 140:
			runtime.step(.25)
			if runtime.book.stock("granary","grain") >= 2: break
		var local: RefCounted = host.worlds["3d"].exploration.village.book
		check(runtime.book.stock("granary","grain") >= 2 and local.stock("granary","grain") == 0 and first.session.data == shared and synchronized(),
			"Guest production and stock transfers remain local and preserve the shared ledger. "+str([runtime.book.states,runtime.book.stock("granary","grain"),local.stock("granary","grain"),first.session.data == shared]))
		guest.set_walking(false)
		guest._command("undo",null)
		check(await wait_for(func()->bool: return synchronized() and first.session.data == baseline),"Shared Undo restores the exact previous city.")
		guest._command("redo",null)
		check(await wait_for(func()->bool: return synchronized() and first.session.data == shared),"Shared Redo restores the village link.")
	second.leave()
	first.leave()
	guest.free()
	host.free()
	await settle()
	print("VILLAGE COOPERATIVE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

