extends "res://tools/test_water_network.gd"

var host: Control
var guest: Control

func wait_for(condition: Callable) -> bool:
	for frame in 1200:
		if condition.call(): return true
		await process_frame
	return false

func synced() -> bool:
	var first: RefCounted=host.cooperative_tools
	var second: RefCounted=guest.cooperative_tools
	return first.participating and second.participating and not first.dirty and not second.dirty and second.session.pending.is_empty() \
		and first.session.data==second.session.data and first.snapshot()==second.snapshot()

func shared(mode: String) -> void:
	for editor in [host,guest]:
		editor.switch_mode(mode)
		editor.economy_tools.pauses[mode]=true
	var source: Dictionary=authored(mode)
	source["economy"]={"enabled":true,"starting_cash":1000000,"period_seconds":60}
	source["economy_account"]=Economy.fresh_account(source,host.library)
	var bounds: Rect2=Protection.object_rect(source["objects"][2],mode,host.library).grow(1)
	source["protected_areas"]=[{"uid":"guarded_home","name":"Protected household","owner":"host",
		"rect":[bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y]}]
	host.current().data=source
	host.changed()
	await settle()
	var first: RefCounted=host.cooperative_tools
	var second: RefCounted=guest.cooperative_tools
	first.name_field.text="Water host"
	first.password.text="water-pass"
	first.port.value=0
	first.host_game()
	check(first.session.server!=null,"Host starts from a valid water city "+mode)
	if first.session.server==null: return
	second.name_field.text="Water guest"
	second.password.text="water-pass"
	second.address.text="127.0.0.1"
	second.port.value=first.session.server.get_local_port()
	second.join_game()
	var ready: bool=await wait_for(synced)
	check(ready,"Both peers converge on one authored water city "+mode)
	if not ready: second.leave(); first.leave(); return
	guest._command("water",null)
	var ui: RefCounted=guest.utility_tools
	var protected_state: Dictionary=first.session.data.duplicate(true)
	check(ui.apply_enabled.disabled and choose(ui.links,[false,"home_run"]),"Guest can see service but only host can enable it "+mode)
	ui.remove_link_button.pressed.emit()
	await settle()
	check(first.session.data==protected_state and second.session.pending.is_empty() and guest.status.text.contains("Protected household"),
		"Guest cannot disconnect a protected endpoint "+mode)
	first.selected="guarded_home"
	first.remove_area()
	check(await wait_for(func():return synced() and host.current().data["protected_areas"].is_empty()),"Host releases the endpoint "+mode)
	var before: Dictionary=first.session.data.duplicate(true)
	check(choose(ui.links,[false,"home_run"]),"Guest selects the released run "+mode)
	ui.remove_link_button.pressed.emit()
	check(await wait_for(func():return synced() and host.current().data["utility_edges"].size()==2),"Peer disconnect converges on the same two runs "+mode)
	check(host.utility_tools.manager().served("home")==0 and ui.manager().served("home")==0,"Both peers forecast the outage "+mode)
	check(first.session.data[mode]["economy_account"]==before[mode]["economy_account"] and not first.session.data[mode].has("stock"),
		"The accepted edit leaves treasury and private preview state separate "+mode)
	guest._command("undo",null)
	check(await wait_for(func():return synced() and first.session.data==before),"Shared Undo restores exact authored water records "+mode)
	check(host.utility_tools.manager().served("home")==5 and ui.manager().served("home")==5,"Both peers show recovered service "+mode)
	second.leave()
	first.leave()
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
	print("WATER NETWORK COOPERATIVE: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
