extends SceneTree
const OUT="res://output/verification/asset_expansion/U13/"
const Plan=preload("res://scripts/builder/interior_kit_plan.gd")
const Floors=preload("res://scripts/builder/floor_plan.gd")
const Economy=preload("res://scripts/builder/economy_plan.gd")
const Store=preload("res://scripts/builder/project_store.gd")
var studio: Control
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func settle() -> void:
	for frame in 10:await process_frame
func ready(tools: RefCounted) -> void:
	for frame in 600:
		if tools.proposal.has("ok") and (not tools.proposal["ok"] or tools.proposal.get("geometry_checked",false)):return
		await process_frame
	check(false,"Delivery preview finishes")
func choose(tools: RefCounted,key: String,action: String) -> void:
	tools.select(tools.kit,key);tools.select(tools.action,action);tools.refresh();await ready(tools)
func selected(uid: String) -> void:studio.selected_uid=uid;studio.selected_uids.assign([uid]);studio.refresh_controls()
func source_ids(room: Dictionary) -> Array:
	var result: Array=[]
	for item in room["objects"]:result.append(item["uid"])
	for floor in room.get("floors",[]):result.append(floor["uid"]);result.append_array(source_ids(floor["room"]))
	return result
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT);FileAccess.open(OUT+".gdignore",FileAccess.WRITE).close()
	Store.storage_root=OUT+"history";Store.legacy_autosave=OUT+"legacy.json"
	studio=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio);await settle();await settle()
	studio.consumer_shell.dismiss_welcome();var tools: RefCounted=studio.interior_tools.kit_chooser
	for mode in ["2d","3d"]:
		studio.switch_mode(mode);var city:=preload("res://scripts/builder/document.gd").new();city.data=preload("res://scripts/builder/templates.gd").make(mode,"blank");studio.documents[mode]=city
		var owner: Dictionary=city.add("3d:HanX_School/School_Building",[0,0,0],"0");var uid: String=owner["uid"];city.data["economy"]={"enabled":true,"starting_cash":0};city.data["economy_account"]=Economy.fresh_account(city.data,studio.library);selected(uid);studio.changed();await settle()
		var original: Dictionary=city.data.duplicate(true);var descriptor: Dictionary=studio.library.assets["3d:HanX_School/Student_Chair"].duplicate(true)
		studio.library.assets[descriptor["id"]]["path"]=OUT+"missing_scene.tscn";tools.show();await ready(tools)
		check(not tools.proposal["ok"] and not tools.message.text.is_empty() and tools.dialog.get_ok_button().disabled and city.data==original,"Missing prepared pack has a visible reason and creates no room")
		studio.library.assets[descriptor["id"]]=descriptor.duplicate(true);tools.refresh();await ready(tools);check(tools.proposal["ok"] and not tools.dialog.get_ok_button().disabled,"Restored source can be reviewed without stale failure state")
		var copy_path: String=OUT+"copied_chair.tscn";FileAccess.open(copy_path,FileAccess.WRITE).store_string(FileAccess.get_file_as_string(descriptor["path"]));studio.library.assets[descriptor["id"]]["path"]=copy_path;tools.refresh();await ready(tools)
		check(tools.proposal["ok"] and tools.proposal.get("geometry_checked",false),"A private prepared source participates in the actual rendered proposal")
		FileAccess.open(copy_path,FileAccess.WRITE).store_string(FileAccess.get_file_as_string(descriptor["path"])+"\n; Changed after review\n");var history: int=city.undo_history.size();tools.apply()
		check(city.data==original and city.undo_history.size()==history and tools.message.text.contains("dependency changed"),"Actual source-file changes invalidate the preview without history or partial creation")
		tools.dialog.hide();studio.library.assets[descriptor["id"]]=descriptor;tools.show();await ready(tools)
		check(tools.proposal["quote"]["ok"] and tools.proposal["quote"]["construction"]==0 and not tools.dialog.get_ok_button().disabled,"Default first layout is available with a zero-credit treasury")
		tools.dialog.get_ok_button().pressed.emit();await settle();check(city.object(uid).has("interior") and city.data["economy_account"]["cash"]==0 and city.data["economy_account"]["construction_total"]==0,"Actual default application receives the authoritative free-starter allowance")
		city.data["economy"]["starting_cash"]=100000;city.data["economy_account"]=Economy.fresh_account(city.data,studio.library);studio.changed();studio.interior_tools.start(uid);await settle()
		tools.show();await choose(tools,"empty","replace");tools.apply();await settle();var empty: Dictionary=studio.current().data.duplicate(true);var treasury: int=studio.interior_tools.outer.data["economy_account"]["cash"]
		tools.show();await choose(tools,"shop","add");check(tools.proposal["issues"].is_empty() and not tools.dialog.get_ok_button().disabled,"Positive Add case fits an existing empty room")
		var quote: Dictionary=tools.proposal["quote"].duplicate(true);tools.apply();await settle()
		check(studio.current().data["objects"].slice(0,empty["objects"].size())==empty["objects"] and studio.current().data["objects"].size()>empty["objects"].size(),"Applying Add retains the exact existing shell identities/settings")
		check(studio.interior_tools.outer.data["economy_account"]["cash"]==treasury-quote["net"],"Add charges precisely the quoted incremental price")
		var added: Dictionary=studio.current().data.duplicate(true);studio._command("undo",null);await settle();check(studio.current().data==empty and studio.interior_tools.outer.data["economy_account"]["cash"]==treasury,"Add Undo restores room contents and the exterior treasury")
		studio._command("redo",null);await settle();check(studio.current().data==added and studio.interior_tools.outer.data["economy_account"]["cash"]==treasury-quote["net"],"Add Redo retains identities and never charges twice")
		tools.show();await choose(tools,"apartment","floor");tools.apply();await settle();var upper: String=studio.current().floor_uid
		check(upper!="ground" and not source_ids(studio.current().canonical.data).any(func(id: String):return id.begins_with("preview_") or id=="kit_floor_preview"),"Saved room/floor records contain no temporary preview identities")
		# The native 2D shell exit projects to grid (3.75,3.75), while the
		# 3D shell exit is (0,2.5). Keep each cabin clear of furniture and exits.
		var center: Array=[0,1.5] if mode=="2d" else [3,2]
		var link: Dictionary={"uid":"kit_delivery_lift","kind":"elevator","lower":"ground","upper":upper,"start":center,"end":center.duplicate(),"width":1.2}
		var linked: Dictionary=Floors.put_record(studio.current().canonical.data,"floor_links",link);studio.interior_tools.floor_tools.commit(linked,upper);await settle()
		check(linked["ok"] and studio.current().canonical.data.get("floor_links",[]).size()==1,"Existing connection transaction connects the new furnished floor")
		var expected: Dictionary=studio.interior_tools.outer.data.duplicate(true);check(studio.write_project(OUT+"owned_"+mode+".isocity.json"),"Save from inside the applied upper floor succeeds")
		var repair=preload("res://scripts/builder/project_repair.gd").new(studio.library);var inspected: Dictionary=repair.read(OUT+"owned_"+mode+".isocity.json")
		check(inspected["ok"] and repair.issues.is_empty() and inspected["content"]["documents"][mode]==JSON.parse_string(JSON.stringify(expected)),"Saved applied layout, accounting and connections reopen without repairs")
		check(studio.autosave(),"Recovery writes while the applied upper floor is active")
		var recovery_path: String=Store.autosave_path(studio.project_id);var recovered: Dictionary=repair.read(recovery_path)
		check(recovered["ok"] and repair.issues.is_empty() and recovered["content"]["documents"][mode]==JSON.parse_string(JSON.stringify(expected)),"Scoped recovery retains the entire owning city and applied floor")
		FileAccess.open(OUT+"blocked_save_parent.txt",FileAccess.WRITE).store_string("not a directory");check(not studio.write_project(OUT+"blocked_save_parent.txt/project.json") and studio.interior_tools.outer.data==expected,"Failed save preserves the live applied layout and its owning city")
		studio.interior_tools.leave();await settle();check(studio.load_project(OUT+"owned_"+mode+".isocity.json"),"Normal project reopening succeeds");await settle()
		if studio.interior_tools.editing():studio.interior_tools.leave()
		# Loading normalizes account integers; compare both sides in the same JSON
		# numeric representation without weakening values, keys or identities.
		check(JSON.parse_string(JSON.stringify(studio.current().data))==JSON.parse_string(JSON.stringify(expected)),"Normal reopening preserves every saved applied source value")
		Store.write_json(OUT+"reopened_"+mode+".json",studio.current().data)
		studio.interior_tools.start(uid,upper);await settle();check(studio.current().floor_uid==upper and studio.current().data["starter_kit"]["id"]=="apartment","Saved upper-floor identity opens the independently editable applied apartment")
		studio.interior_tools.leave();await settle()
		var portable: Dictionary=studio.current().data.duplicate(true)
		check(Store.write_json(OUT+"expected_owned_"+mode+".json",portable),"Independent permitted fixture expectation saved")
		var exported: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(studio.worlds[mode],portable,studio.library,OUT+"owned_"+mode+".zip");check(exported["ok"],"Applied mixed-style owned floors export through ordinary source permissions")
		city=preload("res://scripts/builder/document.gd").new();city.data=preload("res://scripts/builder/templates.gd").make(mode,"room");studio.documents[mode]=city;studio.selected_uids.clear();studio.selected_uid="";studio.changed();await settle();tools.show();await choose(tools,"apartment","replace");tools.apply();await settle()
		check(Store.write_json(OUT+"expected_room_"+mode+".json",studio.current().data),"Standalone applied-room source expectation saved")
		exported=preload("res://scripts/builder/portable_export.gd").new().save(studio.worlds[mode],studio.current().data,studio.library,OUT+"room_"+mode+".zip");check(exported["ok"],"Standalone applied room exports independently")
	studio.free();await process_frame;await process_frame;print("INTERIOR KIT DELIVERY: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
