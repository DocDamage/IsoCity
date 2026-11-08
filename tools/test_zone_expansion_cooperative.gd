extends "res://tools/test_collection_cooperative.gd"
const Zone=preload("res://scripts/builder/zone_plan.gd")
const ZoneWorkflow=preload("res://tools/test_zone_workflow.gd")
func select(choice: OptionButton,value: String) -> void:
	for index in choice.item_count:
		if choice.get_item_metadata(index)==value:choice.select(index);choice.item_selected.emit(index);return
	check(false,"Actual zoning choice exists: "+value)
func run() -> void:
	var zone_out: String=ZoneWorkflow.fixture_output(ZoneWorkflow.EXPECTATION_OUTPUT)
	DirAccess.make_dir_recursive_absolute(zone_out);host=load("res://scenes/builder.tscn").instantiate();guest=load("res://scenes/builder.tscn").instantiate()
	for studio in [host,guest]:studio.storage_enabled=false;root.add_child(studio)
	check(await wait_until(func():return host.enhancements_ready and guest.enhancements_ready and host.consumer_shell!=null and guest.consumer_shell!=null),"Both actual editors initialize for expanded shared zoning")
	for studio in [host,guest]:
		studio.consumer_shell.dismiss_welcome()
		for mode in ["2d","3d"]:
			var data: Dictionary=preload("res://scripts/builder/templates.gd").make(mode,"blank");data["roads"]=[]
			for x in range(-10,11):data["roads"].append({"cell":[x,0]})
			data["zoning"]={"enabled":true,"stage_seconds":60,"seed":27};data["economy"]={"enabled":true,"starting_cash":10000};data["economy_account"]=Zone.Economy.fresh_account(data,studio.library);studio.documents[mode].data=data;studio.zone_tools.managers[mode].paused=true;studio.zone_tools.managers[mode].set_process(false);studio.economy_tools.pauses[mode]=true
		studio.changed()
	guest.library.assets.erase("2d:House_Yellow");guest.library.rebuild_indexes();var a: RefCounted=host.cooperative_tools;var b: RefCounted=guest.cooperative_tools
	a.name_field.text="Zoning host";a.password.text="zoning-test";a.port.value=0;a.host_game();b.name_field.text="Zoning guest";b.password.text="zoning-test";b.address.text="127.0.0.1";b.port.value=a.session.server.get_local_port();b.join_game()
	check(await wait_until(func():return a.participating and b.participating and synced()),"Different catalogs connect when the absent member is merely a possible unselected future design")
	for mode in ["2d","3d"]:
		host.switch_mode(mode);guest.switch_mode(mode);await settle();var h: RefCounted=host.zone_tools;var g: RefCounted=guest.zone_tools;h.show();select(h.kind,"residential");select(h.theme_choice,"village");select(h.density,"low");h.max_price.value=2000;h.add_rect(Rect2(-24,8,48,48));check(await wait_until(synced),"Host's actual themed lot designation converges without construction or charge: "+mode)
		var uid: String=a.session.data[mode]["zones"].back()["uid"];g.selected=uid;g.fields_stamp=0;g.refresh_lot();check(g.chosen_filters()=={"theme":"village","density":"low","max_price":2000} and a.session.data[mode]["objects"].is_empty(),"Guest's inspector restores the exact shared filters before growth: "+mode)
		g.advance_selected();check(await wait_until(synced),"Guest's chosen foundation is validated by the actual host: "+mode);var lot: Dictionary=a.session.data[mode]["zones"].back();var selected: Dictionary=lot["proposal"].duplicate(true);var notes: Dictionary=lot["selection"].duplicate(true)
		check(lot["stage"]==1 and notes["family"].begins_with("supplemental/village/") and selected["asset"] in host.library.families.members[notes["family"]] and a.session.data[mode]["economy_account"]["cash"]==10000,"Shared foundation retains exact design/member provenance and consumes no premature price: "+mode)
		var peer: Dictionary=a.session.peers[b.session.local_id];peer["assets"].erase(selected["asset"]);var accepted: Dictionary=a.session.data.duplicate(true);b.failed_edit=false;g.advance_selected()
		check(await wait_until(func():return b.failed_edit and synced()),"Authority refuses construction when the peer advertises the selected source as uninstalled: "+mode)
		check(a.session.data==accepted and b.draft.get(mode,{}).get("zones",[]).back()["stage"]==2 and b.session.notice.contains("Install matching"),"Missing selected dependency preserves the accepted foundation and a local framing draft: "+mode);peer["assets"][selected["asset"]]=true
		var host_source: Dictionary=host.library.assets[selected["asset"]];var replacement: Dictionary=host_source.duplicate(true);var child_path: String=zone_out.path_join("shared_dependency_"+mode+".tscn");var root_path: String=zone_out.path_join("shared_root_"+mode+".tscn");var child_text: String='[gd_scene format=3]\n[node name="PrivateDependency" type="Node3D"]\n'
		FileAccess.open(child_path,FileAccess.WRITE).store_string(child_text);FileAccess.open(root_path,FileAccess.WRITE).store_string('[gd_scene load_steps=2 format=3]\n[ext_resource type="PackedScene" path="'+child_path+'" id="1"]\n[node name="PrivateRoot" instance=ExtResource("1")]\n');replacement["path"]=root_path;host.library.assets[selected["asset"]]=replacement
		check(Zone.Candidates.source_ready(root_path),"Host dependency graph is good immediately before the source disappears: "+mode);DirAccess.remove_absolute(ProjectSettings.globalize_path(child_path));accepted=a.session.data.duplicate(true);b.failed_edit=false;g.advance_selected()
		check(await wait_until(func():return b.failed_edit and synced()),"Host forces source-file validation inside the advisory cache window: "+mode)
		check(a.session.data==accepted and b.draft.get(mode,{}).get("zones",[]).back()["stage"]==2 and b.session.notice.contains("prepared dependencies"),"Host-side physical dependency failure preserves accepted history, money and a recoverable guest draft: "+mode)
		FileAccess.open(child_path,FileAccess.WRITE).store_string(child_text);host.library.assets[selected["asset"]]=host_source
		a.select_owner("host");a.area_name.text="Protected zoning site";a.add_bounds(Rect2(-24,8,48,48));check(await wait_until(synced),"Host assigns actual ownership protection to the lot: "+mode);accepted=a.session.data.duplicate(true);b.failed_edit=false;g.advance_selected()
		check(await wait_until(func():return b.failed_edit and synced()),"Authority rejects a guest growth transition inside protected land: "+mode)
		check(a.session.data==accepted and a.session.data[mode]["economy_account"]["cash"]==10000,"Rejected protected growth preserves selected member, notes, stage and money: "+mode)
		a.remove_area();check(await wait_until(synced),"Host explicitly removes the protection before further construction: "+mode);g.advance_selected();check(await wait_until(synced),"Authorized framing converges after the missing source/protection are restored: "+mode)
		check(a.session.data[mode]["zones"].back()["stage"]==2 and a.session.data[mode]["zones"].back()["proposal"]==selected and a.session.data[mode]["zones"].back()["selection"]==notes,"Retries keep the original exact selection instead of drawing another palette or family: "+mode)
		g.advance_selected()
		check(await wait_until(synced) and a.session.data[mode]["zones"].back()["stage"]==Zone.Stage.FINISHING and a.session.data[mode]["economy_account"]["cash"]==10000,"Both peers share the finishing stage without paying for temporary scenery: "+mode)
		var finishing: Dictionary=a.session.data.duplicate(true)
		host.library.assets[selected["asset"]]=replacement
		check(Zone.Candidates.source_ready(root_path,true),"The synthetic prepared dependency is available before completion: "+mode)
		DirAccess.remove_absolute(child_path)
		b.failed_edit=false
		g.advance_selected()
		check(await wait_until(func():return b.failed_edit and synced()) and a.session.data==finishing and b.session.notice.contains("prepared dependencies"),"Host verifies dependencies during finishing-to-complete even though the saved numeric stage decreases: "+mode)
		FileAccess.open(child_path,FileAccess.WRITE).store_string(child_text)
		host.library.assets[selected["asset"]]=host_source
		g.advance_selected();check(await wait_until(synced),"Shared completion creates the chosen supplied building: "+mode);var complete: Dictionary=a.session.data.duplicate(true);var cost: int=Zone.Economy.profile(selected["asset"],host.library)["construction"]
		check(complete[mode]["objects"].size()==1 and complete[mode]["objects"][0]==selected and complete[mode]["economy_account"]["cash"]==10000-cost and host.worlds[mode].instances.has(selected["uid"]) and guest.worlds[mode].instances.has(selected["uid"]),"Both peers render the same identity/appearance and the host charges exactly once: "+mode)
		guest._command("undo",null);check(await wait_until(func():return synced() and a.session.data==finishing),"Shared Undo restores finishing and the complete treasury exactly: "+mode);guest._command("redo",null);check(await wait_until(func():return synced() and a.session.data==complete),"Shared Redo restores the same chosen appearance and original charge: "+mode)
		check(not Zone.Citizen.settings(complete[mode])["enabled"] and not Zone.Traffic.settings(complete[mode])["enabled"],"Zoning never enables unrelated resident or traffic simulations: "+mode)
		check(host.write_project(zone_out.path_join("shared_zoning_"+mode+".isocity.json")),"Shared expanded zoning persists through the ordinary project save: "+mode)
	b.leave();a.leave();host.free();guest.free();await process_frame;await process_frame;print("ZONE EXPANSION COOPERATIVE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
