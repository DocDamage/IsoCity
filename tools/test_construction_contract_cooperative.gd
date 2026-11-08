extends "res://tools/test_construction_contracts.gd"

var guest: Control

func synced() -> bool:
	var a: RefCounted=studio.cooperative_tools
	var b: RefCounted=guest.cooperative_tools
	return a.participating and b.participating and not a.dirty and not b.dirty and b.session.pending.is_empty() and a.session.data==b.session.data and a.snapshot()==b.snapshot()

func wait_for(predicate: Callable) -> bool:
	for frame in 900:
		if predicate.call(): return true
		await process_frame
	return false

func choose_contract(editor: Control) -> bool:
	var tools: RefCounted=editor.scenario_tools
	tools.show()
	return choose(tools.choice,"construction") and choose(tools.construction_supply,"supply") and choose(tools.construction_site,"site")

func shared_contract(mode: String) -> void:
	var fixture_data: Dictionary=await setup_site(mode)
	var driver: Node=fixture_data["driver"]
	var world: Node=fixture_data["world"]
	guest.switch_mode(mode)
	guest.economy_tools.pauses[mode]=true
	var a: RefCounted=studio.cooperative_tools
	var b: RefCounted=guest.cooperative_tools
	a.name_field.text="Construction host"
	a.password.text="contract-fixture"
	a.port.value=0
	a.host_game()
	check(a.session.server!=null,"The construction test starts a real host: "+mode)
	if a.session.server==null: return
	b.name_field.text="Construction guest"
	b.password.text="contract-fixture"
	b.address.text="127.0.0.1"
	b.port.value=a.session.server.get_local_port()
	b.join_game()
	check(await wait_for(synced),"Two connected editors share the site and exact treasury: "+mode)
	var before: Dictionary=a.session.data.duplicate(true)
	check(choose_contract(guest),"The guest sees the same actual construction station choices: "+mode)
	guest.scenario_tools.start_challenge()
	check(synced() and a.session.data==before and guest.status.text.contains("host"),"The guest cannot change the shared challenge: "+mode)
	check(choose_contract(studio),"The host selects both station identities from the shared city: "+mode)
	studio.scenario_tools.start_challenge()
	check(await wait_for(func()->bool:return synced() and Construction.enabled(a.session.data[mode])),"The authoritative setup converges on both peers: "+mode)
	if not Construction.enabled(a.session.data[mode]): return
	var accepted: Dictionary=a.session.data.duplicate(true)
	var manager: Node=driver.construction
	var other: Node=guest.worlds[mode].exploration.driving.construction
	check(is_instance_valid(other) and manager.attempt==other.attempt and accepted[mode]["economy_account"]==before[mode]["economy_account"],"Both peers compile the same setup without a treasury change: "+mode)
	await enter_car("van")
	studio.control_settings.execute("delivery_cargo")
	tick(driver,32)
	var moved: bool=drive_to(driver,fixture_data["finish"])
	studio.control_settings.execute("delivery_cargo")
	tick(driver,32)
	check(moved and manager.materials==4 and other.materials==0,"An actual shared-city van haul only changes the driver's preview: "+mode)
	driver.exit_vehicle()
	for index in 3:
		var task: Dictionary=manager.next_task()
		if task.is_empty(): break
		walk_to(world,task["approach"],task["height"])
		await settle()
		world.exploration.interact()
	check(manager.reward_total==150 and manager.receipts.size()==1 and other.receipts.is_empty() and not is_instance_valid(other.models) and synced() and a.session.data==accepted,"Construction, reward and equipment stay private while authoritative city history remains exact: "+mode)
	studio.set_walking(false)
	studio._command("undo",null)
	check(await wait_for(func()->bool:return synced() and a.session.data==before),"Shared Undo restores the city before the contract setup: "+mode)
	studio._command("redo",null)
	check(await wait_for(func()->bool:return synced() and a.session.data==accepted),"Shared Redo restores the authored setup and no private progress: "+mode)
	b.leave()
	a.leave()
	await settle()

func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate()
	guest=load("res://scenes/builder.tscn").instantiate()
	for editor in [studio,guest]:
		editor.storage_enabled=false
		root.add_child(editor)
	await settle()
	for editor in [studio,guest]: editor.consumer_shell.dismiss_welcome()
	for mode in ["2d","3d"]: await shared_contract(mode)
	guest.free()
	studio.free()
	await settle()
	print("CONSTRUCTION CONTRACT COOPERATIVE: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
