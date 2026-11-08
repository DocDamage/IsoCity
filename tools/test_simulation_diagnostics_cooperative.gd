extends "res://tools/test_traffic_reroute_cooperative.gd"

func lane_row(ui: RefCounted) -> Dictionary:
	for row in ui.snapshot.get("rows",[]):
		if row["code"]=="traffic_lane": return row
	return {}

func shared_city(mode: String) -> void:
	for editor in [host,guest]:
		editor.consumer_shell.dismiss_welcome()
		editor.switch_mode(mode)
		editor.economy_tools.pauses[mode]=true
	var doc:=Doc.new()
	doc.data=fixture(mode)
	doc.data["economy"]={"enabled":true,"starting_cash":15000}
	doc.data["economy_account"]=Economy.fresh_account(doc.data,host.library)
	host.documents[mode]=doc
	host.changed()
	await settle()
	var a: RefCounted=host.cooperative_tools
	var b: RefCounted=guest.cooperative_tools
	a.name_field.text="Diagnostic host"
	a.password.text="diagnostics"
	a.port.value=0
	a.host_game()
	if a.session.server==null: check(false,"The real shared session starts: "+mode); return
	b.name_field.text="Diagnostic guest"
	b.password.text="diagnostics"
	b.address.text="127.0.0.1"
	b.port.value=a.session.server.get_local_port()
	b.join_game()
	check(await wait_for(synced),"Both live peers share the same source and ledger: "+mode)
	await settle()
	var initial: Dictionary=a.session.data.duplicate(true)
	var manager: Node=host.traffic_tools.managers[mode]
	manager.set_physics_process(false)
	if manager.vehicles.is_empty(): check(false,"The shared city has a real traffic actor: "+mode); return
	var ui: RefCounted=host.simulation_diagnostic_tools
	var peer: RefCounted=guest.simulation_diagnostic_tools
	ui.choose("traffic")
	ui.tick(.3)
	var row: Dictionary=lane_row(ui)
	check(not row.is_empty() and ui.overlay.visible and peer.kind=="off" and not peer.overlay.visible and a.session.data==initial and b.session.data==initial,"A local overlay never edits history or activates for another peer: "+mode)
	var lane: String=manager.vehicles[0]["to"]
	var cell:=Vector2i(int(lane.get_slice(",",0)),int(lane.get_slice(",",1)))
	studio=guest
	edit_road(guest.current(),cell)
	check(await wait_for(func():return synced() and not Plan.Roads.lookup(host.current().data).has(lane)),"The actual peer road edit reaches the host: "+mode)
	await settle()
	ui.tick(.3)
	check(not ui.current_row(row) and not ui.navigate(row,true) and peer.kind=="off","The remote edit invalidates the host finding without sharing overlay preferences: "+mode)
	var edited: Dictionary=a.session.data.duplicate(true)
	var quote: Dictionary=Economy.quote(initial[mode],edited[mode],host.library)
	check(quote["ok"] and Economy.normalized_account(edited[mode]["economy_account"])==quote["account"],"The normal shared road quote is the only accounting change: "+mode)
	guest._command("undo",null)
	check(await wait_for(func():return synced() and a.session.data==initial),"Shared Undo restores the exact route data and ledger without reviving old findings: "+mode)
	ui.choose("off")
	b.leave()
	a.leave()
	await settle()

func run() -> void:
	host=load("res://scenes/builder.tscn").instantiate()
	guest=load("res://scenes/builder.tscn").instantiate()
	for editor in [host,guest]:
		editor.storage_enabled=false
		root.add_child(editor)
	await settle()
	for mode in ["2d","3d"]:
		studio=host
		await shared_city(mode)
	guest.free()
	host.free()
	await settle()
	print("SIMULATION DIAGNOSTICS COOPERATIVE: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
