extends "res://tools/test_collection_cooperative.gd"
const Economy=preload("res://scripts/builder/economy_plan.gd")
func policy(ids: Array) -> Dictionary:
	var value: Dictionary=Plan.project_empty();value["restricted"]=true
	for id in ids:value["collection"]["entries"].append(Plan.asset_entry(id,host.library)["entry"])
	return value
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT);FileAccess.open(OUT+".gdignore",FileAccess.WRITE).close();host=load("res://scenes/builder.tscn").instantiate();guest=load("res://scenes/builder.tscn").instantiate()
	for studio in [host,guest]:studio.storage_enabled=false;root.add_child(studio)
	check(await wait_until(func():return host.enhancements_ready and guest.enhancements_ready and host.consumer_shell!=null and guest.consumer_shell!=null),"Both actual editors initialize for authoritative policy verification")
	var allowed: String="3d:HanX_School/Student_Chair";var excluded: String="3d:HanX_School/Teacher_Chair"
	for studio in [host,guest]:
		studio.consumer_shell.dismiss_welcome()
		for mode in ["2d","3d"]:
			var data: Dictionary=preload("res://scripts/builder/templates.gd").make(mode,"blank");data["objects"]=[{"uid":"existing_"+mode,"asset":excluded,"position":[0,0,0],"direction":studio.library.directions(excluded)[0],"scale":1.0}];data["economy"]={"enabled":true,"starting_cash":10000};data["economy_account"]=Economy.fresh_account(data,studio.library);studio.documents[mode].data=data;studio.economy_tools.pauses[mode]=true
		studio.changed()
	host.project_palette_document.apply(host.project_palette_document.propose(policy([allowed])));host.changed();var a: RefCounted=host.cooperative_tools;var b: RefCounted=guest.cooperative_tools
	a.name_field.text="Restriction host";a.password.text="palette-policy";a.port.value=0;a.host_game();b.name_field.text="Restriction guest";b.password.text="palette-policy";b.address.text="127.0.0.1";b.port.value=a.session.server.get_local_port();b.join_game()
	check(await wait_until(func():return a.participating and b.participating and synced()),"Actual Host and Join accept a restricted project containing grandfathered excluded objects")
	check(guest.library.project_palette.get("restricted",false) and guest.library.project_palette_ids.has(allowed),"Guest initializes the host's common policy independently of its personal filters")
	for mode in ["2d","3d"]:
		guest.switch_mode(mode);host.switch_mode(mode);await settle();var accepted: Dictionary=a.session.data.duplicate(true);guest.drop_asset(excluded,guest.canvas.size*.6);await settle()
		check(synced() and a.session.data==accepted and guest.status.text.contains("restriction"),"Actual guest drop is denied locally without optimistic spending or shared history: "+mode)
		guest.drop_asset(allowed,guest.canvas.size*.7);check(await wait_until(synced),"Allowed guest construction converges through ordinary host validation: "+mode);var purchased: Dictionary=a.session.data.duplicate(true)
		check(purchased[mode]["objects"].size()==2 and int(purchased[mode]["economy_account"]["cash"])==10000-Economy.profile(allowed,host.library)["construction"],"Host charges an allowed guest construction exactly once: "+mode)
		guest.current().checkpoint();guest.current().object("existing_"+mode)["position"][0]=5;guest.changed();check(await wait_until(synced),"Moving a grandfathered excluded object remains a valid shared edit: "+mode)
		check(a.session.data[mode]["objects"][0]["position"][0]==5 and a.session.data[mode]["economy_account"]==purchased[mode]["economy_account"],"Accepted excluded-object movement preserves identity and treasury: "+mode)
		var h: RefCounted=host.asset_browser.collections;h.show_manager();h.scope_choice.select(1);h.load_draft();h.draft=policy([])["collection"];h.restriction.button_pressed=true;h.save_button.pressed.emit();await settle();var before: Dictionary=a.session.data.duplicate(true)
		check(h.review_dialog.visible and synced() and a.session.data==before,"Host's explicit palette narrowing is read-only until reviewed Apply: "+mode)
		h.review_dialog.confirmed.emit();h.dialog.hide();check(await wait_until(synced),"Host's narrower restriction converges without removing accepted guest objects: "+mode)
		check(a.session.data[mode]==before[mode] and guest.library.project_palette_ids.is_empty(),"Both peers retain accepted objects and money under the newly empty allowed set: "+mode)
		guest._command("undo",null);check(await wait_until(synced),"Shared Undo restores the guest's earlier movement after palette narrowing: "+mode);guest._command("undo",null);check(await wait_until(synced),"Shared Undo restores the guest's earlier purchase and cash after narrowing: "+mode)
		check(a.session.data[mode]==accepted[mode],"Shared historical removal exactly restores the former world and treasury: "+mode)
		guest._command("redo",null);check(await wait_until(synced),"Shared Redo can restore an earlier authorized purchase even after its asset is excluded: "+mode)
		host.Store.write_json(OUT+"restriction_redo_expected_"+mode+".json",purchased[mode]);host.Store.write_json(OUT+"restriction_redo_actual_"+mode+".json",a.session.data[mode]);check(normalized(a.session.data[mode])==normalized(purchased[mode]),"Shared Redo restores the exact accepted identities and charge without repricing: "+mode)
		guest._command("redo",null);check(await wait_until(synced),"Second shared Redo restores the later move in chronological order: "+mode)
		check(a.session.data[mode]["objects"][0]["position"][0]==5 and a.session.data[mode]["objects"].size()==2,"Later move restoration retains the restored purchase and identities: "+mode)
		accepted=a.session.data.duplicate(true);b.failed_edit=false;guest.current().finish_checkpoint();guest.current().data["objects"].append({"uid":"bypass_"+mode,"asset":excluded,"position":[20,0,0],"direction":guest.library.directions(excluded)[0],"scale":1.0});guest.changed()
		check(await wait_until(func():return b.failed_edit and synced()),"Authoritative host rejects a deliberately forged excluded construction that bypasses local UI guards: "+mode)
		check(a.session.data==accepted and b.draft.get(mode,{}).get("objects",[]).any(func(item: Dictionary):return item["uid"]=="bypass_"+mode),"Rejected wire edit preserves accepted state and a local recovery draft: "+mode)
		h.show_manager();h.scope_choice.select(1);h.load_draft();h.draft=policy([allowed])["collection"];h.restriction.button_pressed=true;h.save_button.pressed.emit();h.review_dialog.confirmed.emit();h.dialog.hide();check(await wait_until(synced),"Host can explicitly reopen allowed references before the next world: "+mode)
	b.leave();a.leave();host.free();guest.free();await process_frame;await process_frame;print("COLLECTION RESTRICTION COOPERATIVE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
