extends "res://tools/test_local_deliveries.gd"

var guest: Control

func synced() -> bool:
	var host: RefCounted=studio.cooperative_tools
	var peer: RefCounted=guest.cooperative_tools
	return host.participating and peer.participating and not host.dirty and not peer.dirty and peer.session.pending.is_empty() and host.session.data==peer.session.data and host.snapshot()==peer.snapshot()

func wait_for(test: Callable) -> bool:
	for frame in 900:
		if test.call(): return true
		await process_frame
	return false

func change_reward() -> void:
	guest.selected_uid="pickup"
	guest.selected_uids.assign(["pickup"])
	guest._command("deliveries",null)
	guest.delivery_tools.contract_fields["reward"].value=62
	guest.delivery_tools.apply_settings()

func workflow(mode: String) -> void:
	var data: Dictionary=await fixture(mode)
	guest.switch_mode(mode)
	guest.economy_tools.pauses[mode]=true
	var doc: RefCounted=data["doc"]
	var driver: Node=data["driver"]
	var point: Vector2=driver.delivery.sites["drop"]["point"]
	var area:=Rect2(point-Vector2.ONE,Vector2.ONE*2)
	var coop=preload("res://scripts/builder/cooperative_plan.gd")
	check(not coop.object_rect(doc.object("drop"),mode,studio.library).intersects(area),"The protected loading pad is separate from the destination art: "+mode)
	doc.data["protected_areas"]=[{"uid":"pad","name":"Protected receiving pad","owner":"host","rect":[area.position.x,area.position.y,2,2]}]
	studio.changed()
	await settle()
	var host: RefCounted=studio.cooperative_tools
	var peer: RefCounted=guest.cooperative_tools
	host.name_field.text="Delivery host"
	host.password.text="delivery-fixture"
	host.port.value=0
	host.host_game()
	check(host.session.server!=null,"The local delivery host starts: "+mode)
	if host.session.server==null: return
	peer.name_field.text="Delivery guest"
	peer.password.text="delivery-fixture"
	peer.address.text="127.0.0.1"
	peer.port.value=host.session.server.get_local_port()
	peer.join_game()
	check(await wait_for(synced),"Both peers converge on the same authored contract: "+mode)
	await settle()
	var original: Dictionary=host.session.data.duplicate(true)
	change_reward()
	check(await wait_for(func()->bool:return synced() and peer.session.notice.contains("Protected area")) and host.session.data==original,"A guest cannot edit a contract that uses the host's protected receiving pad: "+mode+" "+peer.session.notice)
	host.selected="pad"
	host.remove_area()
	check(await wait_for(func()->bool:return synced() and studio.current().data.get("protected_areas",[]).is_empty()),"The host can release the loading area: "+mode)
	var before: Dictionary=host.session.data.duplicate(true)
	change_reward()
	check(await wait_for(func()->bool:return synced() and studio.current().object("pickup")["delivery_contract"]["reward"]==62),"The guest inspector can edit the unlocked contract: "+mode)
	var accepted: Dictionary=host.session.data.duplicate(true)
	check(accepted[mode]["economy_account"]==before[mode]["economy_account"],"The shared price change leaves the exact treasury: "+mode)
	driver.business_clock.hour=12
	await enter_car("van")
	studio.control_settings.execute("delivery_cargo")
	tick(driver,16)
	var moved: bool=drive_to(driver,data["finish"])
	studio.control_settings.execute("delivery_cargo")
	tick(driver,16)
	var other=guest.worlds[mode].exploration.driving.delivery
	check(moved and driver.delivery.reward_total==62 and driver.delivery.receipts.size()==1 and other.reward_total==0 and other.receipts.is_empty() and synced() and host.session.data==accepted,"A real contract settles only in the driver's private preview: "+mode)
	studio.set_walking(false)
	guest._command("undo",null)
	check(await wait_for(func()->bool:return synced() and host.session.data==before),"Shared Undo restores the exact offer and treasury: "+mode)
	guest._command("redo",null)
	check(await wait_for(func()->bool:return synced() and host.session.data==accepted),"Shared Redo restores the authored offer alone: "+mode)
	peer.leave()
	host.leave()
	await settle()

func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate()
	guest=load("res://scenes/builder.tscn").instantiate()
	for editor in [studio,guest]:
		editor.storage_enabled=false
		root.add_child(editor)
	await settle()
	for editor in [studio,guest]:
		if editor.consumer_shell: editor.consumer_shell.dismiss_welcome()
	for mode in ["2d","3d"]: await workflow(mode)
	guest.free()
	studio.free()
	await settle()
	print("LOCAL DELIVERY COOPERATIVE: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
