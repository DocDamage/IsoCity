extends "res://tools/test_resident_activity_cooperative.gd"
func row(ui: RefCounted,code: String) -> Dictionary:
	for result in ui.active_report.get("records",[]):
		if result["code"]==code and result["object_uid"]=="chair":return result
	return {}
func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate();guest=load("res://scenes/builder.tscn").instantiate()
	for editor in [studio,guest]:editor.storage_enabled=false;root.add_child(editor)
	await settle()
	for editor in [studio,guest]:
		if editor.consumer_shell:editor.consumer_shell.dismiss_welcome()
	for mode in ["2d","3d"]:
		for editor in [studio,guest]:editor.switch_mode(mode);editor.economy_tools.pauses[mode]=true
		var doc:=Doc.new();doc.data=Templates.make(mode,"blank");studio.documents[mode]=doc
		var school: Dictionary=doc.add("3d:HanX_School/School_Building",[112,-32,0] if mode=="2d" else [7,0,-2],"0",.25);school["uid"]="school"
		var room: Dictionary=preload("res://scripts/builder/interiors.gd").make(mode,"Shared setup school");room["objects"]=[];var upper:=Doc.new();upper.data=room.duplicate(true)
		var chair: Dictionary=upper.add("3d:HanX_School/Student_Chair",[0,-32,0] if mode=="2d" else [-2,.12,-2],"0");chair["uid"]="chair"
		room["floors"]=[{"uid":"upper","name":"Classroom","height":3,"room":upper.data}];room["floor_links"]=[];school["interior"]=room
		var economy=preload("res://scripts/builder/economy_plan.gd");doc.data["economy"]={"enabled":true,"starting_cash":100000};doc.data["economy_account"]=economy.fresh_account(doc.data,studio.library);studio.changed();await settle()
		var a: RefCounted=studio.cooperative_tools;var b: RefCounted=guest.cooperative_tools
		a.name_field.text="Setup host";a.password.text="setup-pass";a.port.value=0;a.host_game()
		check(a.session.server!=null,"Shared setup fixture starts host authority: "+mode)
		if a.session.server==null:continue
		b.name_field.text="Setup guest";b.password.text="setup-pass";b.address.text="127.0.0.1";b.port.value=a.session.server.get_local_port();b.join_game()
		check(await wait_until(synced),"Actual host/guest sessions converge: "+mode)
		var before: Dictionary=a.session.data.duplicate(true);var city_before: Dictionary=studio.current().data.duplicate(true);studio.selected_uid="school";studio.selected_uids.assign(["school"]);studio._command("interaction_setup",null);await settle()
		var ui: RefCounted=studio.prop_tools.setup;var old: Dictionary=row(ui,"return_route")
		check(old.get("severity","")=="error" and a.session.data==before and not a.dirty,"Host checks a real unvisited room without sending a shared edit: "+mode)
		if old.is_empty():b.leave();a.leave();continue
		guest.interior_tools.start("school");await settle();var connections: RefCounted=guest.interior_tools.floor_tools.connections;connections.refresh();connections.new_record()
		connections.start_x.value=0;connections.start_z.value=0;connections.end_x.value=0;connections.end_z.value=6;connections.width.value=1.2;connections.apply_record()
		check(await wait_until(func():return synced() and studio.current().object("school")["interior"]["floor_links"].size()==1),"Guest repairs the actual floor route using existing shared connection controls: "+mode)
		studio.selected_uid="school";studio.selected_uids.assign(["school"]);ui.refresh()
		check(not ui.focus_record(old,true) and not studio.interior_tools.editing() and row(ui,"return_route").get("severity","")=="ok","Accepted shared edit retires the stale check and reports a usable route: "+mode)
		var accepted: Dictionary=a.session.data.duplicate(true);var city_after: Dictionary=studio.current().data.duplicate(true);var cost: Dictionary=economy.quote(city_before,city_after,studio.library)
		check(city_after["economy_account"]["cash"]==city_before["economy_account"]["cash"]-cost["net"] and not JSON.stringify(accepted).contains("message_key"),"Only the accepted repair quote affects the account; findings never enter the shared source: "+mode)
		guest._command("undo",null);check(await wait_until(func():return synced() and a.session.data==before),"Shared Undo restores the exact original room and account: "+mode)
		studio.selected_uid="school";studio.selected_uids.assign(["school"]);ui.refresh();check(row(ui,"return_route").get("severity","")=="error","Host checklist reflects the restored real problem: "+mode)
		guest._command("redo",null);check(await wait_until(func():return synced() and a.session.data==accepted),"Shared Redo restores the accepted repair and exact account: "+mode)
		studio.selected_uid="school";studio.selected_uids.assign(["school"]);ui.refresh();check(row(ui,"return_route").get("severity","")=="ok","Host checklist reflects the actual repaired plan after Redo: "+mode)
		b.leave();a.leave();guest.interior_tools.leave();await settle()
	guest.free();studio.free();await settle();print("INTERACTION SETUP COOPERATIVE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
