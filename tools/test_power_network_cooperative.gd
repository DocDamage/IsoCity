extends "res://tools/test_power_network.gd"

var host: Control
var guest: Control

func wait_for(condition: Callable) -> bool:
	for frame in 1200:
		if condition.call(): return true
		await process_frame
	return false

func synced() -> bool:
	var a: RefCounted=host.cooperative_tools
	var b: RefCounted=guest.cooperative_tools
	return a.participating and b.participating and not a.dirty and not b.dirty and b.session.pending.is_empty() and a.session.data==b.session.data and a.snapshot()==b.snapshot()

func shared(mode: String) -> void:
	for editor in [host,guest]:
		editor.switch_mode(mode)
		editor.economy_tools.pauses[mode]=true
	var source: Dictionary=authored_power(mode)
	source["economy"]={"enabled":true,"starting_cash":1000000,"period_seconds":60}
	source["economy_account"]=Economy.fresh_account(source,host.library)
	var bounds: Rect2=Protection.object_rect(source["objects"][6],mode,host.library).grow(1)
	source["protected_areas"]=[{"uid":"guarded_charger","name":"Protected charger","owner":"host",
		"rect":[bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y]}]
	host.current().data=source
	host.changed()
	await settle()
	var a: RefCounted=host.cooperative_tools
	var b: RefCounted=guest.cooperative_tools
	a.name_field.text="Power host"
	a.password.text="power-pass"
	a.port.value=0
	a.host_game()
	check(a.session.server!=null,"Host starts with the prepared power city "+mode)
	if a.session.server==null: return
	b.name_field.text="Power guest"
	b.password.text="power-pass"
	b.address.text="127.0.0.1"
	b.port.value=a.session.server.get_local_port()
	b.join_game()
	var ready: bool=await wait_for(synced)
	check(ready,"Peers synchronize the exact cable and equipment IDs "+mode)
	if not ready: b.leave(); a.leave(); return
	guest._command("power",null)
	var ui: RefCounted=guest.power_tools
	var protected_state: Dictionary=a.session.data.duplicate(true)
	check(ui.apply_enabled.disabled and choose(ui.links,[false,"charger_run"]),"Only the host controls shared enablement "+mode)
	ui.remove_link_button.pressed.emit()
	await settle()
	check(a.session.data==protected_state and b.session.pending.is_empty() and guest.status.text.contains("Protected charger"),"Guest cannot disconnect the protected charger "+mode)
	a.selected="guarded_charger"
	a.remove_area()
	check(await wait_for(func():return synced() and host.current().data["protected_areas"].is_empty()),"Host releases charger protection "+mode)
	var before: Dictionary=a.session.data.duplicate(true)
	check(choose(ui.links,[false,"charger_run"]),"Guest selects the released cable "+mode)
	ui.remove_link_button.pressed.emit()
	check(await wait_for(func():return synced() and host.current().data["utility_edges"].size()==5),"Guest cable edit converges on both peers "+mode)
	var host_power: Node=host.power_tools.manager()
	var guest_power: Node=ui.manager()
	check(not host_power.requirement("charger","charger").is_empty() and not guest_power.requirement("charger","charger").is_empty(),
		"Both charge stations lose service after the accepted edit "+mode)
	guest._command("undo",null)
	check(await wait_for(func():return synced() and a.session.data==before),"Shared Undo restores the exact electrical network and treasury "+mode)
	check(host_power.requirement("charger","charger").is_empty() and guest_power.requirement("charger","charger").is_empty(),
		"Both charge stations recover after Undo "+mode)
	host_power.reset_preview()
	guest_power.reset_preview()
	guest_power.paused=true
	for tick in 8: host_power.step(.25)
	check(host_power.stored()==8 and guest_power.stored()==0 and a.session.data==before,"Battery state is private and does not author a shared update "+mode)
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
	for editor in [host,guest]:
		if editor.consumer_shell: editor.consumer_shell.dismiss_welcome()
	studio=host
	for mode in ["2d","3d"]: await shared(mode)
	guest.free()
	host.free()
	await settle()
	print("POWER NETWORK COOPERATIVE: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
