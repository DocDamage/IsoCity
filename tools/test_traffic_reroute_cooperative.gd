extends "res://tools/test_traffic_reroute.gd"

const Economy=preload("res://scripts/builder/economy_plan.gd")
var host: Control
var guest: Control

func synced() -> bool:
	var a: RefCounted=host.cooperative_tools
	var b: RefCounted=guest.cooperative_tools
	return a.participating and b.participating and not a.dirty and not b.dirty and b.session.pending.is_empty() and a.session.data==b.session.data and a.snapshot()==b.snapshot()

func wait_for(condition: Callable) -> bool:
	for frame in 900:
		if condition.call(): return true
		await process_frame
	return false

func shared_city(mode: String) -> void:
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
	a.name_field.text="Reroute host"
	a.password.text="reroute-local"
	a.port.value=0
	a.host_game()
	check(a.session.server!=null,"The shared road city starts on a local port: "+mode)
	if a.session.server==null: return
	b.name_field.text="Reroute guest"
	b.password.text="reroute-local"
	b.address.text="127.0.0.1"
	b.port.value=a.session.server.get_local_port()
	b.join_game()
	check(await wait_for(synced),"The two peers agree on the authored city and original ledger: "+mode)
	await settle()
	var before: Dictionary=a.session.data.duplicate(true)
	var managers: Array=[host.traffic_tools.managers[mode],guest.traffic_tools.managers[mode]]
	var states: Array[Dictionary]=[]
	for manager in managers:
		manager.set_physics_process(false)
		if manager.vehicles.is_empty(): continue
		var vehicle: Dictionary=manager.vehicles[0]
		position_car(manager,vehicle)
		states.append({"vehicle":vehicle,"actor":vehicle["actor"],"point":vehicle["point"],"revision":manager.route_queue.revision})
	check(states.size()==2 and states.all(func(state: Dictionary)->bool:return state["vehicle"]["bay"]=="bay"),"Both peers have independent actors heading to the same bay: "+mode+" "+str(managers.map(func(manager: Node)->Array:return [manager.active,manager.vehicles.size(),manager.bays.keys(),manager.plan.get("settings",{}),manager.plan.get("notices",[])])))
	if states.size()!=2:
		b.leave()
		a.leave()
		return
	studio=guest
	edit_road(guest.current(),Vector2i(2,0))
	var local_erased: bool=not Plan.Roads.lookup(guest.current().data).has("2,0")
	var converged: bool=await wait_for(func():return synced() and not Plan.Roads.lookup(host.current().data).has("2,0"))
	check(converged,"A guest road edit is accepted by the host and converges: "+mode+" "+str([local_erased,a.session.notice,b.session.notice,guest.current().economy_error,a.session.revision,b.session.revision,b.dirty]))
	await settle()
	var edited: Dictionary=a.session.data.duplicate(true)
	var quote: Dictionary=Economy.quote(before[mode],edited[mode],host.library)
	check(quote["ok"] and quote["construction"]==0 and Economy.normalized_account(edited[mode]["economy_account"])==quote["account"],"Host accounting applies exactly the authoritative road removal quote once: "+str([quote.get("construction"),quote.get("refund"),edited[mode]["economy_account"]["cash"]]))
	for index in managers.size():
		var state: Dictionary=states[index]
		var manager: Node=managers[index]
		check(manager.vehicles[0]["actor"]==state["actor"] and state["vehicle"]["point"]==state["point"] and manager.route_queue.revision==state["revision"]+1,"Shared authority preserves local pose and publishes one new revision.")
		var vehicle: Dictionary=state["vehicle"]
		var detour: Dictionary=drive_until(manager,vehicle,func():return "2,1" in vehicle["sections"])
		check(detour["arrived"] and detour["continuous"],"Each local actor physically drives the accepted shared detour.")
	check(a.session.data==edited and b.session.data==edited,"Local search, pose, route and claims stay outside the authored shared snapshot.")
	guest._command("undo",null)
	check(await wait_for(func():return synced() and a.session.data==before),"Shared Undo restores the exact previous city and ledger.")
	guest._command("redo",null)
	check(await wait_for(func():return synced() and a.session.data==edited),"Shared Redo restores the same removal and ledger.")
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
	print("REROUTE COOPERATIVE: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
