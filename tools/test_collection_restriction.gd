extends SceneTree
const OUT="res://output/verification/asset_expansion/U15/"
const Collections=preload("res://scripts/builder/asset_collections.gd")
const Economy=preload("res://scripts/builder/economy_plan.gd")
var studio: Control
var tools: RefCounted
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func normalized(value: Dictionary) -> Dictionary:return JSON.parse_string(JSON.stringify(value))
func settle() -> void:
	for frame in 12:await process_frame
	await physics_frame
func config(ids: Array) -> Dictionary:
	var value: Dictionary=Collections.project_empty();value["restricted"]=true;value["collection"]["name"]="Reviewed construction palette"
	for id in ids:value["collection"]["entries"].append(Collections.asset_entry(id,studio.library)["entry"])
	return value
func review(value: Dictionary) -> void:
	tools.show_manager();tools.scope_choice.select(1);tools.load_draft();tools.draft=value["collection"].duplicate(true);tools.name_input.text=value["collection"]["name"];tools.restriction.button_pressed=value["restricted"];tools.save_button.pressed.emit();await settle()
func apply_review() -> void:tools.review_dialog.confirmed.emit();await settle();tools.dialog.hide()
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT);FileAccess.open(OUT+".gdignore",FileAccess.WRITE).close();root.size=Vector2i(1480,900);studio=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio);await settle();await settle();studio.consumer_shell.dismiss_welcome();tools=studio.asset_browser.collections
	for mode in ["2d","3d"]:
		studio.switch_mode(mode);studio.project_palette_document.restore({});studio.changed();var doc: RefCounted=preload("res://scripts/builder/document.gd").new();doc.data=preload("res://scripts/builder/templates.gd").make(mode,"blank")
		var home: String="2d:House_Blue" if mode=="2d" else "3d:HanX_City/Row_Houses_A";var allowed: String="3d:HanX_School/Student_Chair";var denied: String="3d:HanX_School/Teacher_Chair";var owner: Dictionary=doc.add(home,[-100,0,0] if mode=="2d" else [-10,0,-10],studio.library.directions(home)[0]);var uid: String=owner["uid"];var old_chair: Dictionary=doc.add(denied,[100,0,0] if mode=="2d" else [10,0,-10],studio.library.directions(denied)[0]);var old_uid: String=old_chair["uid"]
		studio.documents[mode]=doc;studio.changed();await settle();var economy: RefCounted=studio.economy_tools;economy.enabled.button_pressed=true;economy.budget.value=10000;economy.apply_settings();economy.paused.button_pressed=true;doc.finish_checkpoint();await settle()
		var original: Dictionary=doc.data.duplicate(true);var history: Array=doc.undo_history.duplicate(true);var personal: Dictionary=tools.local.state.duplicate(true);var policy: Dictionary=config([allowed]);await review(policy)
		check(tools.review_dialog.visible and tools.review_text.text.contains("Content restriction: ON") and studio.project_palette_document.data.is_empty() and doc.data==original and doc.undo_history==history,"Actual explicit restriction review is read-only and explains its scope: "+mode)
		await apply_review();check(studio.library.project_palette.get("restricted",false) and tools.local.state==personal and doc.data==original,"Reviewed Apply enables common restrictions without changing existing content or personal lists: "+mode)
		studio.drop_asset(denied,studio.canvas.size*.5);doc.finish_checkpoint();await settle();check(doc.data==original and doc.undo_history==history and studio.status.text.contains("restriction"),"Denied actual drop preserves geometry, treasury, history and a useful reason: "+mode)
		studio.selected_uid=old_uid;studio.selected_uids.assign([old_uid]);studio.duplicate_selection();doc.finish_checkpoint();await settle();check(doc.data==original and doc.undo_history==history,"Copying a grandfathered excluded object is denied atomically without history or spending: "+mode)
		studio.clear_placement();studio.drop_asset(allowed,studio.canvas.size*Vector2(.7,.7));doc.finish_checkpoint();await settle();var purchased: Dictionary=doc.data.duplicate(true);var bought_uid: String=doc.data["objects"].back()["uid"];var price: int=Economy.profile(allowed,studio.library)["construction"]
		check(doc.data["objects"].size()==3 and int(doc.data["economy_account"]["cash"])==10000-price and doc.undo_history.size()==history.size()+1,"Allowed actual drop spends its normal price exactly once: "+mode)
		studio._command("undo",null);await settle();check(doc.data==original,"Ordinary Undo restores prior data and treasury under the restriction: "+mode);studio._command("redo",null);await settle();check(doc.data==purchased,"Ordinary Redo restores exact identities and charge despite restriction: "+mode)
		studio.paste_objects([doc.object(bought_uid).duplicate(true),doc.object(old_uid).duplicate(true)],[200,0,200]);doc.finish_checkpoint();await settle();check(doc.data==purchased,"Mixed allowed/excluded paste rolls back as a whole without a partial charge: "+mode)
		var h: int=doc.undo_history.size();studio.interior_tools.start(uid);await settle();check(not studio.interior_tools.editing() and doc.data==purchased and doc.undo_history.size()==h and not doc.object(uid).has("interior"),"Denied editor room creation leaves no owned room, checkpoint or charge: "+mode)
		var path: String=OUT+"restricted_"+mode+".tscn";check(preload("res://scripts/builder/exporter.gd").save_scene(studio.worlds[mode],doc.data,studio.library,path)==OK,"Standalone scene carries explicit project restriction metadata: "+mode)
		var runtime: Node=load(path).instantiate();root.add_child(runtime);await settle();runtime.player.set_physics_process(false);var runtime_before: Dictionary=runtime.live_data.duplicate(true);var position: Variant=runtime.player.position;runtime.exploration.nearby={"item":runtime.live_data["objects"][0]};runtime.exploration.enter_interior();await settle()
		check(runtime.project_palette==studio.project_palette_document.data and runtime.exploration.library.project_palette==runtime.project_palette,"Fresh standalone runtime initializes the exact common policy: "+mode)
		check(runtime.exploration.interior==null and runtime.live_data==runtime_before and runtime.player.position==position and runtime.get_node("Objects").visible and runtime.exploration.entrance_notice.contains("restriction"),"Denied runtime lazy room preserves actor, exterior, saved data and visible reason: "+mode);runtime.free();await settle()
		var room: Dictionary=preload("res://scripts/builder/interiors.gd").make_for(doc.object(uid),mode,studio.library);var ids: Array=[allowed]
		for id in Collections.records(room).values():
			if not ids.has(id):ids.append(id)
		await review(config(ids));await apply_review();studio.interior_tools.start(uid);await settle();check(studio.interior_tools.editing() and not doc.object(uid).get("interior",{}).is_empty(),"Explicitly permitted full starter dependencies create the ordinary owned room: "+mode)
		if not studio.interior_tools.editing():continue
		studio.drop_asset(allowed,studio.canvas.size*.6);studio.current().finish_checkpoint();await settle();var owned: Dictionary=studio.current().canonical.data.duplicate(true);var root_before: Dictionary=doc.data.duplicate(true);await review(config([]));check(studio.current().canonical.data==owned and doc.data==root_before,"Narrowing restriction inside an owned room reviews without retroactive rollback: "+mode);await apply_review()
		check(studio.current().canonical.data==owned and doc.object(uid)["interior"]==owned,"Metadata boundary preserves all previously accepted owned edits when narrowing policy: "+mode)
		var canonical_history: Array=studio.current().canonical.undo_history.duplicate(true);var cash: int=doc.data["economy_account"]["cash"];studio.drop_asset(denied,studio.canvas.size*.5);studio.current().finish_checkpoint();await settle();check(studio.current().canonical.data==owned and studio.current().canonical.undo_history==canonical_history and doc.data["economy_account"]["cash"]==cash,"Denied furnishing preserves canonical floor history and the exterior treasury: "+mode)
		var before_failed_save: Dictionary=studio.session_data().duplicate(true);var saved_identity: Array=[studio.project_id,studio.project_path,studio.saved_digest];FileAccess.open(OUT+"blocked_palette_save_parent.txt",FileAccess.WRITE).store_string("not a directory")
		check(not studio.write_project(OUT+"blocked_palette_save_parent.txt/project.json") and studio.session_data()==before_failed_save and [studio.project_id,studio.project_path,studio.saved_digest]==saved_identity,"Failed ordinary save preserves common policy, owned contents and project identity: "+mode)
		var saved_path: String=OUT+"restriction_saved_"+mode+".isocity.json";check(studio.write_project(saved_path),"Restricted owned project saves through the ordinary path: "+mode);check(studio.load_project(saved_path),"Restricted project reopens while another restriction is active: "+mode);await settle();studio.Store.write_json(OUT+"restriction_expected_room_"+mode+".json",owned);studio.Store.write_json(OUT+"restriction_reopened_"+mode+".json",studio.session_data())
		check(studio.library.project_palette.get("restricted",false) and studio.project_palette_document.data["collection"]["entries"].is_empty(),"Normal load restores the exact common restriction: "+mode)
		check(studio.session_data()["documents"][mode]["objects"].any(func(item: Dictionary):return item["uid"]==uid and normalized(item.get("interior",{}))==normalized(owned)),"Normal load preserves excluded saved rooms exactly: "+mode)
		tools.show_manager();tools.scope_choice.select(1);tools.load_draft();var digest: String=studio.content_digest();tools.clear_project_button.pressed.emit();await settle();check(tools.review_dialog.visible and tools.review_text.text.contains("disable") and studio.content_digest()==digest,"Removing a project restriction requires a read-only review: "+mode);await apply_review();check(studio.project_palette_document.data.is_empty() and studio.library.project_palette.is_empty(),"Explicit removal restores absent metadata and unrestricted construction: "+mode)
		if studio.interior_tools.editing():studio.interior_tools.leave()
		studio.drop_asset(denied,studio.canvas.size*.5);await settle();check(studio.interior_tools.root_document(mode).data["objects"].size()==4,"Unrelated construction works again after reviewed removal: "+mode)
	studio.free();await process_frame;await process_frame;print("COLLECTION RESTRICTION: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
