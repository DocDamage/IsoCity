extends "res://tools/test_fleet_profiles.gd"

const Economy=preload("res://scripts/builder/economy_plan.gd")
var host: Control
var guest: Control

func wait_for(condition: Callable) -> bool:
	for frame in 900:
		if condition.call(): return true
		await process_frame
	return false

func synced() -> bool:
	var a: RefCounted=host.cooperative_tools
	var b: RefCounted=guest.cooperative_tools
	return a.participating and b.participating and not a.dirty and not b.dirty and b.session.pending.is_empty() and a.session.data==b.session.data and a.snapshot()==b.snapshot()

func open_fleet(editor: Control, id: String) -> void:
	editor._command("vehicle_fleets",null)
	var ui: RefCounted=editor.traffic_tools.fleets
	ui.entries[id]["enabled"].button_pressed=true
	ui.apply_button.pressed.emit()

func run() -> void:
	host=load("res://scenes/builder.tscn").instantiate()
	guest=load("res://scenes/builder.tscn").instantiate()
	for editor in [host,guest]:
		editor.storage_enabled=false
		root.add_child(editor)
	await settle()
	studio=host
	for mode in ["2d","3d"]:
		for editor in [host,guest]:
			if editor.consumer_shell: editor.consumer_shell.dismiss_welcome()
			editor.switch_mode(mode)
			editor.economy_tools.pauses[mode]=true
		var doc:=Doc.new()
		doc.data=fixture(mode)
		doc.data["economy"]={"enabled":true,"starting_cash":15000,"period_seconds":60}
		doc.data["economy_account"]=Economy.fresh_account(doc.data,host.library)
		host.documents[mode]=doc
		host.changed()
		await settle()
		var a: RefCounted=host.cooperative_tools
		var b: RefCounted=guest.cooperative_tools
		a.name_field.text="Fleet host"
		a.password.text="fleet-pass"
		a.port.value=0
		a.host_game()
		check(a.session.server!=null,"The host starts the shared city with its legacy fleet: "+mode)
		if a.session.server==null: continue
		b.name_field.text="Fleet guest"
		b.password.text="fleet-pass"
		b.address.text="127.0.0.1"
		b.port.value=a.session.server.get_local_port()
		b.join_game()
		check(await wait_for(synced),"Both peers converge before changing the fleet: "+mode)
		var original: Dictionary=a.session.data.duplicate(true)
		var alternate: String=TYPES[mode][1]
		var installed: Dictionary=guest.library.assets[alternate]
		guest.library.assets.erase(alternate)
		guest.library.rebuild_indexes()
		b.session.refresh_assets()
		check(await wait_for(func():return not a.session.peers[b.session.local_id]["assets"].has(alternate)),"Host receives the changed local asset inventory.")
		open_fleet(host,alternate)
		check(await wait_for(func():return synced() and a.session.notice.contains("Install matching assets")),"Host authority rejects an unspawned choice a peer lacks.")
		check(a.session.data==original and not guest.current().data.has("fleet"),"Rejected fleet apply leaves both authored cities and accounts exact.")
		guest.library.assets[alternate]=installed
		guest.library.rebuild_indexes()
		b.session.refresh_assets()
		check(await wait_for(func():return a.session.peers[b.session.local_id]["assets"].has(alternate)),"Peer inventory again includes the reviewed model.")
		var host_asset: Dictionary=host.library.assets[alternate]
		host.library.assets.erase(alternate)
		host.library.rebuild_indexes()
		open_fleet(guest,alternate)
		check(await wait_for(func():return synced() and b.session.notice.contains("unavailable assets")),"The shared author also rejects a guest selection absent from the host's library.")
		check(a.session.data==original,"The host mismatch leaves the exact original shared city.")
		host.library.assets[alternate]=host_asset
		host.library.rebuild_indexes()
		open_fleet(guest,alternate)
		check(await wait_for(func():return synced() and host.current().data.has("fleet")),"The same choice is accepted after the required asset is present.")
		var accepted: Dictionary=a.session.data.duplicate(true)
		check(accepted[mode]["economy_account"]==original[mode]["economy_account"] and not Plan.settings(accepted[mode])["enabled"],"Roster configuration neither charges the treasury nor starts a simulation.")
		guest._command("undo",null)
		check(await wait_for(func():return synced() and a.session.data==original),"Shared Undo restores the exact previous fleet and economy.")
		guest._command("redo",null)
		check(await wait_for(func():return synced() and a.session.data==accepted),"Shared Redo restores the exact fleet identities and weights.")
		b.leave()
		a.leave()
		await settle()
	guest.free()
	host.free()
	await settle()
	print("FLEET COOPERATIVE: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
