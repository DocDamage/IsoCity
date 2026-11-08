extends "res://tools/test_market_days.gd"

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
	guest.selected_uid="market"
	guest.selected_uids.assign(["market"])
	guest._command("markets",null)
	guest.market_tools.stalls[0]["price"].value=7
	guest.market_tools.apply_settings()

func workflow(mode: String) -> void:
	var data: Dictionary=await fixture(mode)
	guest.switch_mode(mode)
	guest.economy_tools.pauses[mode]=true
	var doc: RefCounted=data["doc"]
	var manager: Node=data["manager"]
	var fruit: String=Plan.market_id("market",0)
	var point: Vector2=manager.market.sites["market"]["vendors"][fruit]["point"]
	var area:=Rect2(point-Vector2.ONE,Vector2.ONE*2)
	var coop=preload("res://scripts/builder/cooperative_plan.gd")
	check(not coop.object_rect(doc.object("market"),mode,studio.library).intersects(area),"Protected space covers the temporary checkout outside host art: "+mode)
	doc.data["protected_areas"]=[{"uid":"aisle","name":"Protected market aisle","owner":"host","rect":[area.position.x,area.position.y,2,2]}]
	studio.changed()
	await settle()
	var host: RefCounted=studio.cooperative_tools
	var peer: RefCounted=guest.cooperative_tools
	host.name_field.text="Market host"
	host.password.text="market-fixture"
	host.port.value=0
	host.host_game()
	check(host.session.server!=null,"The local market host starts: "+mode)
	if host.session.server==null: return
	peer.name_field.text="Market guest"
	peer.password.text="market-fixture"
	peer.address.text="127.0.0.1"
	peer.port.value=host.session.server.get_local_port()
	peer.join_game()
	check(await wait_for(synced),"Both peers see the authored event: "+mode)
	await settle()
	var original: Dictionary=host.session.data.duplicate(true)
	change_price()
	check(await wait_for(func()->bool:return synced() and peer.session.notice.contains("Protected area")) and host.session.data==original,"A guest cannot edit the protected market aisle: "+mode+" "+peer.session.notice)
	host.selected="aisle"
	host.remove_area()
	check(await wait_for(func()->bool:return synced() and studio.current().data.get("protected_areas",[]).is_empty()),"The host can release the aisle: "+mode)
	var before: Dictionary=host.session.data.duplicate(true)
	change_price()
	check(await wait_for(func()->bool:return synced() and studio.current().object("market")["market"]["vendors"][0]["price"]==7),"The guest can edit the released market: "+mode)
	var accepted: Dictionary=host.session.data.duplicate(true)
	check(accepted[mode]["economy_account"]==before[mode]["economy_account"],"The contract edit leaves the authoritative treasury exact: "+mode)
	clock(manager,12)
	studio.set_walking(true)
	put_player(data["world"],manager.market.vendors[fruit]["point"],mode)
	await settle()
	buy(manager)
	var other: Node=guest.business_tools.managers[mode]
	check(manager.market.revenue==7 and other.market.revenue==0 and other.market.receipts.is_empty() and synced() and host.session.data==accepted,"The physical purchase only affects the active player's preview: "+mode)
	studio.set_walking(false)
	guest._command("undo",null)
	check(await wait_for(func()->bool:return synced() and host.session.data==before),"Shared Undo restores the authored market and exact treasury: "+mode)
	guest._command("redo",null)
	check(await wait_for(func()->bool:return synced() and host.session.data==accepted),"Shared Redo restores the authored price: "+mode)
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
	print("MARKET COOPERATIVE: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
