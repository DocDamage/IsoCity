extends SceneTree
const OUT="res://output/verification/asset_expansion/U15/"
const Plan=preload("res://scripts/builder/asset_collections.gd")
var host: Control
var guest: Control
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func wait_until(test: Callable) -> bool:
	for frame in 900:
		if test.call():return true
		await process_frame
	return false
func settle() -> void:
	for frame in 12:await process_frame
func normalized(value: Dictionary) -> Dictionary:return JSON.parse_string(JSON.stringify(value))
func synced() -> bool:
	var a: RefCounted=host.cooperative_tools;var b: RefCounted=guest.cooperative_tools
	return not a.dirty and not b.dirty and b.session.pending.is_empty() and a.snapshot()==b.snapshot() and a.snapshot()==a.session.data
func personal(studio: Control,name: String,id: String) -> String:
	var item: Dictionary=Plan.create(name)["data"];item["entries"]=[Plan.asset_entry(id,studio.library)["entry"]];studio.asset_browser.collections.local.put(item);return item["uid"]
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT);FileAccess.open(OUT+".gdignore",FileAccess.WRITE).close();host=load("res://scenes/builder.tscn").instantiate();guest=load("res://scenes/builder.tscn").instantiate()
	for studio in [host,guest]:studio.storage_enabled=false;root.add_child(studio)
	check(await wait_until(func():return host.enhancements_ready and guest.enhancements_ready and host.consumer_shell!=null and guest.consumer_shell!=null),"Actual editors finish initialization before collection sharing")
	for studio in [host,guest]:
		studio.consumer_shell.dismiss_welcome()
		for mode in ["2d","3d"]:studio.documents[mode].data=preload("res://scripts/builder/templates.gd").make(mode,"blank")
		studio.changed()
	var private_id: String="3d:Custom/Recommended_Host_Only_Chair";var private_asset: Dictionary=host.library.assets["3d:HanX_School/Student_Chair"].duplicate(true);private_asset["id"]=private_id;private_asset["name"]="Remembered host-only chair";private_asset["data"]["source_export_allowed"]=false;host.library.assets[private_id]=private_asset;host.library.rebuild_indexes()
	var h: RefCounted=host.asset_browser.collections;var g: RefCounted=guest.asset_browser.collections;var host_uid: String=personal(host,"Host selected list","3d:HanX_School/Student_Chair");var guest_uid: String=personal(guest,"Guest selected list","3d:HanX_School/Teacher_Chair");var secret_uid: String=personal(host,"Do not share this other personal list","3d:HanX_School/Teacher_Desk")
	h.select_filter(host_uid);g.select_filter(guest_uid)
	var recommended: Dictionary=Plan.project_empty();recommended["collection"]["name"]="Host recommendation";recommended["collection"]["entries"]=[Plan.asset_entry(private_id,host.library)["entry"]];host.project_palette_document.apply(host.project_palette_document.propose(recommended));host.changed()
	var old_guest: Dictionary=Plan.project_empty();old_guest["collection"]["name"]="Guest previous project";guest.project_palette_document.apply(guest.project_palette_document.propose(old_guest));guest.changed()
	var host_local: Dictionary=h.local.state.duplicate(true);var guest_local: Dictionary=g.local.state.duplicate(true);var a: RefCounted=host.cooperative_tools;var b: RefCounted=guest.cooperative_tools
	a.name_field.text="Collection host";a.password.text="collection-pass";a.port.value=0;a.host_game();b.name_field.text="Collection guest";b.password.text="collection-pass";b.address.text="127.0.0.1";b.port.value=a.session.server.get_local_port();b.join_game()
	check(await wait_until(func():return a.participating and b.participating and synced()),"Different catalogs connect when missing IDs are recommendations rather than constructed dependencies")
	check(normalized(guest.project_palette_document.data)==normalized(recommended) and normalized(b.backup.get("project_palette",{}))==normalized(old_guest),"Joining adopts the common recommendation and retains the guest's previous project metadata in its backup")
	check(h.local.state==host_local and g.local.state==guest_local and g.selection()==guest_uid,"Shared metadata never synchronizes personal lists or forces another author's browser filter")
	var missing: Dictionary=Plan.resolve(guest.project_palette_document.data["collection"],guest.library);check(missing["missing"].size()==1 and missing["missing"][0]["id"]==private_id and missing["missing"][0]["name"]=="Remembered host-only chair","Guest retains identifiable missing references from the host's different catalog")
	g.select_filter("project");g.show_manager();await settle();check(g.scope_choice.selected==1 and g.save_button.disabled and not g.project_authority(),"Guest can inspect actual shared recommendations with host-controlled editing")
	g.to_personal.pressed.emit();await settle();check(g.local.state["collections"].size()==guest_local["collections"].size()+1 and g.local.state["collections"].back()["entries"][0]["id"]==private_id and synced(),"Guest copies even an unavailable recommendation into its own personal list without a shared edit");g.dialog.hide()
	h.show_manager();await settle();h.to_project.pressed.emit();await settle();var before: Dictionary=a.session.data.duplicate(true);check(h.review_dialog.visible and a.session.data==before and synced(),"Host's actual recommendation review remains read-only before confirmation")
	h.review_dialog.confirmed.emit();check(await wait_until(synced),"Host recommendation Apply converges through the ordinary authoritative transaction");var updated: Dictionary=a.session.data.duplicate(true)
	check(updated["project_palette"]["collection"]["entries"][0]["id"]=="3d:HanX_School/Student_Chair" and updated["2d"]==before["2d"] and updated["3d"]==before["3d"],"Shared palette change preserves all world objects, budgets and simulation settings")
	check(h.local.state==host_local and not JSON.stringify(a.snapshot()).contains(secret_uid),"Unrelated personal collections and identities remain outside authoritative snapshots")
	h.dialog.hide();var accepted: Dictionary=a.session.data.duplicate(true);var illicit: Dictionary=guest.project_palette_document.data.duplicate(true);illicit["collection"]["name"]="Unauthorized guest recommendation";b.failed_edit=false;guest.project_palette_document.apply(guest.project_palette_document.propose(illicit));guest.changed()
	check(await wait_until(func():return b.failed_edit and synced()),"Host rejects a validly shaped unauthorized guest metadata transaction")
	check(a.session.data==accepted and b.draft.get("project_palette",{}).get("collection",{}).get("name")=="Unauthorized guest recommendation","Rejected palette mutation preserves accepted state and its common-metadata recovery draft")
	host._command("undo",null);check(await wait_until(func():return synced() and a.session.data==before),"Shared Undo restores exact former recommendation metadata without touching world content")
	host._command("redo",null);check(await wait_until(func():return synced() and a.session.data==updated),"Shared Redo restores the same reviewed recommendation")
	check(host.write_project(OUT+"shared_palette.isocity.json"),"Actual shared project saves common recommendation metadata")
	var source: Dictionary=host.Store.read_json(OUT+"shared_palette.isocity.json",{});check(source.get("project_palette")==updated["project_palette"] and not JSON.stringify(source).contains("Do not share this other personal list") and not JSON.stringify(source).contains("favorites_migrated"),"Shared source file keeps project metadata and excludes personal preferences")
	b.leave();a.leave();host.free();guest.free();await process_frame;await process_frame;print("COLLECTION COOPERATIVE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
