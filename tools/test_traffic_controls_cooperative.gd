extends "res://tools/test_traffic_controls.gd"

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

func run() -> void:
	host=load("res://scenes/builder.tscn").instantiate()
	guest=load("res://scenes/builder.tscn").instantiate()
	for editor in [host,guest]:
		editor.storage_enabled=false
		root.add_child(editor)
	await settle()
	for mode in ["2d","3d"]:
		for editor in [host,guest]:
			if editor.consumer_shell: editor.consumer_shell.dismiss_welcome()
			editor.switch_mode(mode)
			editor.economy_tools.pauses[mode]=true
		var doc:=Doc.new()
		doc.data=fixture(mode)
		for item in doc.data["objects"]: item.erase("traffic_control")
		doc.data["economy"]={"enabled":true,"starting_cash":15000,"period_seconds":60}
		doc.data["economy_account"]=Economy.fresh_account(doc.data,host.library)
		doc.data["protected_areas"]=[{"uid":"lane","name":"Protected approach","owner":"host","rect":[8,-1,1,2]}]
		host.documents[mode]=doc
		host.changed()
		await settle()
		var a: RefCounted=host.cooperative_tools
		var b: RefCounted=guest.cooperative_tools
		a.name_field.text="Traffic host"
		a.password.text="traffic-pass"
		a.port.value=0
		a.host_game()
		check(a.session.server!=null,"The host starts with an unbound signal and protected lane: "+mode)
		if a.session.server==null: continue
		b.name_field.text="Traffic guest"
		b.password.text="traffic-pass"
		b.address.text="127.0.0.1"
		b.port.value=a.session.server.get_local_port()
		b.join_game()
		check(await wait_for(synced),"Peers join the authored four-way road fixture: "+mode)
		var protected: Dictionary=a.session.data.duplicate(true)
		var ui: RefCounted=guest.traffic_tools
		guest.selected_uid="east"
		guest.selected_uids.assign(["east"])
		guest._command("traffic",null)
		await settle()
		ui.refresh_control()
		ui.binding_action.pressed.emit()
		check(await wait_for(func():return synced() and b.session.notice.contains("Protected area")),"Host refuses a binding from outside the protected approach: "+mode)
		check(a.session.data==protected and not guest.current().object("east").has("traffic_control"),"Rejected editing restores the source on both peers: "+mode)
		a.selected="lane"
		a.remove_area()
		check(await wait_for(func():return synced() and host.current().data.get("protected_areas",[]).is_empty()),"The host releases the lane using the existing area action: "+mode)
		var before: Dictionary=a.session.data.duplicate(true)
		guest.selected_uid="east"
		guest.selected_uids.assign(["east"])
		ui.refresh_control()
		for key in TIMING: ui.timing_fields[key].set_value_no_signal(TIMING[key])
		ui.binding_action.pressed.emit()
		check(await wait_for(func():return synced() and host.current().object("east").has("traffic_control")),"The accepted rule and timing converge on both editors: "+mode)
		var accepted: Dictionary=a.session.data.duplicate(true)
		check(accepted[mode]["economy_account"]==before[mode]["economy_account"] and not accepted[mode].get("traffic",{}).get("enabled",false),"Binding a placed signal costs nothing and leaves ordinary traffic opt-in: "+mode)
		guest._command("undo",null)
		check(await wait_for(func():return synced() and a.session.data==before),"One shared Undo removes the authored timing and binding: "+mode)
		guest._command("redo",null)
		check(await wait_for(func():return synced() and a.session.data==accepted),"One shared Redo restores the authored signal without serializing its phase: "+mode)
		b.leave()
		a.leave()
		await settle()
	guest.free()
	host.free()
	await settle()
	print("TRAFFIC CONTROLS COOPERATIVE: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
