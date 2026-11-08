extends "res://tools/test_vehicle_care.gd"

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

func change_price() -> void:
	guest.selected_uid="fuel"
	guest.selected_uids.assign(["fuel"])
	guest._command("vehicle_care",null)
	guest.vehicle_service_tools.bay_fields["price"].value=23
	guest.vehicle_service_tools.apply_settings()

func share(mode: String) -> void:
	var case: Dictionary=await fixture(mode)
	if case.is_empty(): return
	guest.switch_mode(mode)
	guest.economy_tools.pauses[mode]=true
	var doc: RefCounted=case["doc"]
	var driver: Node=case["driver"]
	var bay: Dictionary=driver.care.bays["fuel"]
	var point: Vector2=bay["center"]-bay["axis"]*9
	var area:=Rect2(point-Vector2.ONE,Vector2.ONE*2)
	var coop=preload("res://scripts/builder/cooperative_plan.gd")
	check(not coop.object_rect(doc.object("fuel"),mode,studio.library).intersects(area) and Care.protected_area(doc.object("fuel"),mode,studio.library).encloses(area),"Protection covers the marked approach outside the station's art: "+mode)
	doc.data["protected_areas"]=[{"uid":"approach","name":"Protected service approach","owner":"host","rect":[area.position.x,area.position.y,area.size.x,area.size.y]}]
	studio.changed()
	await settle()
	var host: RefCounted=studio.cooperative_tools
	var peer: RefCounted=guest.cooperative_tools
	host.name_field.text="Vehicle care host"
	host.password.text="care-fixture"
	host.port.value=0
	host.host_game()
	check(host.session.server!=null,"The vehicle care host starts: "+mode)
	if host.session.server==null: return
	peer.name_field.text="Vehicle care guest"
	peer.password.text="care-fixture"
	peer.address.text="127.0.0.1"
	peer.port.value=host.session.server.get_local_port()
	peer.join_game()
	check(await wait_for(synced),"The two peers converge on the same authored service bays: "+mode)
	await settle()
	var original: Dictionary=host.session.data.duplicate(true)
	change_price()
	check(await wait_for(func()->bool:return synced() and peer.session.notice.contains("Protected area")) and host.session.data==original,"The guest cannot change a bay whose approach overlaps host land: "+mode+" "+peer.session.notice)
	host.selected="approach"
	host.remove_area()
	check(await wait_for(func()->bool:return synced() and studio.current().data.get("protected_areas",[]).is_empty()),"The host can release the service approach: "+mode)
	var before: Dictionary=host.session.data.duplicate(true)
	change_price()
	check(await wait_for(func()->bool:return synced() and studio.current().object("fuel")["vehicle_bay"].get("price")==23),"The same inspector change succeeds after protection is lifted: "+mode+" "+peer.session.notice)
	var accepted: Dictionary=host.session.data.duplicate(true)
	check(accepted[mode]["economy_account"]==before[mode]["economy_account"],"A posted price change leaves both peers' treasury exact: "+mode)
	driver.set_physics_process(false)
	await enter_car("fuel_car")
	var started: bool=driver.request_vehicle_service() and drive_to(driver,bay["center"]) and driver.care.locked("fuel_car")
	finish_service(driver,"fuel_car")
	var other: Node=guest.worlds[mode].exploration.driving
	check(started and driver.care.wallet==977 and driver.care.receipts.size()==1 and other.care.receipts.is_empty() and other.care.wallet==-1 and synced() and host.session.data==accepted,"Actual fueling charges only the host's private Walk wallet: "+mode)
	studio.set_walking(false)
	guest._command("undo",null)
	check(await wait_for(func()->bool:return synced() and host.session.data==before),"Shared Undo restores the exact bay and treasury: "+mode)
	guest._command("redo",null)
	check(await wait_for(func()->bool:return synced() and host.session.data==accepted),"Shared Redo restores only the authored price: "+mode)
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
	for mode in ["2d","3d"]: await share(mode)
	guest.free()
	studio.free()
	await settle()
	print("VEHICLE CARE COOPERATIVE: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
