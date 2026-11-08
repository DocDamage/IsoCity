extends SceneTree
const OUT="res://output/verification/asset_expansion/U15/"
const Plan=preload("res://scripts/builder/asset_collections.gd")
var studio: Control
var tools: RefCounted
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func settle() -> void:
	for frame in 14:await process_frame
func press(text: String) -> void:
	for button in tools.dialog.find_children("*","Button",true,false):
		if button.text==text:button.pressed.emit();await settle();return
	check(false,"Actual collection control exists: "+text)
func choose_asset(id: String) -> void:
	tools.query.text=id;tools.query.text_changed.emit(id);await settle()
	var item: TreeItem=tools.results.get_root().get_first_child()
	while item:
		if item.get_metadata(0)==id:item.select(0);return
		item=item.get_next()
	check(false,"Actual collection search finds concrete asset: "+id)
func choose_member(id: String) -> void:
	var item: TreeItem=tools.members.get_root().get_first_child()
	while item:
		if item.get_metadata(0)["id"]==id:item.select(0);return
		item=item.get_next()
	check(false,"Saved reference remains selectable: "+id)
func capture(name: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args():return
	await RenderingServer.frame_post_draw;check(root.get_texture().get_image().save_png(OUT+name+".png")==OK,"Actual collection workflow capture: "+name)
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT);FileAccess.open(OUT+".gdignore",FileAccess.WRITE).close();root.size=Vector2i(1480,900)
	studio=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio);await settle();await settle();studio.consumer_shell.dismiss_welcome();tools=studio.asset_browser.collections;tools.local.path=OUT+"workflow_preferences.json"
	for mode in ["2d","3d"]:
		studio.switch_mode(mode);tools.dialog.hide();tools.review_dialog.hide();tools.local.state=Plan.empty();tools.local.revision+=1;tools.override_filter=null;tools.sync_key="";studio.project_palette_document.restore({});studio.clear_placement();studio.current().data=preload("res://scripts/builder/templates.gd").make(mode,"blank");studio.asset_browser.clear_all_filters();studio.changed();await settle()
		studio.saved_digest=studio.content_digest();studio.dirty=false;var before: Dictionary=studio.session_data()["documents"].duplicate(true);var digest: String=studio.content_digest();var history: int=studio.current().undo_history.size()
		tools.show_manager();await settle();check(tools.dialog.visible and studio.modal_visible() and studio.content_digest()==digest and not studio.dirty,"Opening the actual manager is read-only: "+mode)
		tools.name_input.text="Workshop";await choose_asset("3d:HanX_School/Student_Chair");await press("Add exact asset")
		check(tools.draft["entries"].size()==1 and tools.local.state["collections"].is_empty() and studio.content_digest()==digest,"Adding to a draft never places an object or saves prematurely")
		await press("Save personal collection");var uid: String=tools.current_personal_uid();check(not uid.is_empty() and tools.local.state["collections"].size()==1 and studio.content_digest()==digest and not studio.dirty and studio.current().undo_history.size()==history,"Saving a personal list leaves project content, history and dirty state exact")
		await press("Use saved list in browser");await settle();check(not tools.dialog.visible and studio.library_matches().map(func(asset: Dictionary):return asset["id"])==["3d:HanX_School/Student_Chair"],"Using a saved list filters exact concrete members without construction")
		for simple in [true,false]:
			studio.consumer_shell.set_active(simple,false);await settle();check(studio.library_matches().map(func(asset: Dictionary):return asset["id"])==["3d:HanX_School/Student_Chair"],"Exact list identity survives both workspaces: "+str(simple))
		check(preload("res://scripts/builder/model_preview.gd").meaningful(studio.library.icon("3d:HanX_School/Student_Chair")),"Filtered native member retains recognizable source preview art")
		studio.asset_browser.semantic_search.broaden();await settle();check(tools.selection().is_empty() and studio.library_matches().size()>1,"Broader search temporarily clears the named-list restriction")
		studio.asset_browser.semantic_search.restore_filters();await settle();check(tools.selection()==uid and studio.library_matches().size()==1,"Restoring filters restores the exact personal list")
		studio.drop_asset("3d:HanX_School/Teacher_Chair",studio.canvas.size*.5);await settle();check(studio.current().data["objects"].any(func(item: Dictionary):return item["asset"]=="3d:HanX_School/Teacher_Chair"),"An advisory collection never rejects an unrelated explicit placement")
		studio._command("undo",null);await settle();check(studio.session_data()["documents"]==before,"Ordinary construction Undo remains independent from personal collection history")
		tools.show_manager();await settle();var family_source: String=""
		for id in studio.library.assets:
			if not studio.library.assets[id]["data"].get("family_id","").is_empty():family_source=id;break
		await choose_asset(family_source);await press("Add whole family snapshot");await press("Save personal collection");var saved: Dictionary=Plan.collection(tools.local.state,uid)
		if saved["entries"].size()<2:check(false,"Family draft saved before remaining delivery assertions");studio.free();quit(1);return
		var family_count: int=saved["entries"][1]["members"].size()
		check(saved["entries"].size()==2 and family_count>1 and saved["entries"][0]["kind"]=="asset","Manager distinguishes exact asset and explicit whole-family snapshots")
		await capture("manager_"+mode);await press("Use saved list in browser");check(studio.library_matches().size()==family_count+1,"Saved whole-family members remain exact choices instead of collapsed representatives")
		tools.show_manager();await settle();var incoming: Dictionary={"uid":"foreign_collection","name":"Workshop","entries":[{"kind":"asset","id":"2d:Uninstalled_Workbench_Fixture","name":"Remembered workbench"}]};studio.Store.write_json(OUT+"incoming_collection.json",Plan.package([incoming]));var source_hash: String=FileAccess.get_sha256(OUT+"incoming_collection.json");var local_before: Dictionary=tools.local.state.duplicate(true)
		await press("Import collection file…");check(tools.file_dialog.visible,"Actual import button opens the filesystem chooser");tools.file_dialog.file_selected.emit(ProjectSettings.globalize_path(OUT+"incoming_collection.json"));tools.file_dialog.hide();await settle()
		check(tools.review_dialog.visible and tools.review_text.text.contains("Workshop (2)") and tools.local.state==local_before,"Import previews collisions and missing references before changing personal lists")
		tools.review_dialog.hide();check(tools.local.state==local_before,"Canceling collection import preserves every current list")
		tools.file_action="import";tools.file_selected(OUT+"incoming_collection.json");tools.review_dialog.confirmed.emit();await settle();var imported: Dictionary=tools.local.state["collections"].back()
		check(imported["name"]=="Workshop (2)" and imported["uid"]!=incoming["uid"] and imported["entries"]==incoming["entries"],"Reviewed import keeps missing identities and allocates a fresh personal collection identity")
		tools.fill_collections(imported["uid"]);tools.load_draft();choose_member(incoming["entries"][0]["id"]);await choose_asset("3d:HanX_School/Teacher_Chair");await press("Replace selected reference")
		check(Plan.collection(tools.local.state,imported["uid"])["entries"][0]["id"]==incoming["entries"][0]["id"],"Unavailable-reference replacement remains a draft until saved")
		await press("Save personal collection");check(Plan.collection(tools.local.state,imported["uid"])["entries"][0]["id"]=="3d:HanX_School/Teacher_Chair" and FileAccess.get_sha256(OUT+"incoming_collection.json")==source_hash,"Explicit replacement keeps the original imported file intact")
		await press("Export saved collection…");check(tools.file_dialog.visible,"Actual collection export opens a destination chooser");tools.file_dialog.file_selected.emit(ProjectSettings.globalize_path(OUT+"exported_collection_"+mode+".json"));tools.file_dialog.hide();await settle();check(Plan.package_valid(studio.Store.read_json(OUT+"exported_collection_"+mode+".json",{})),"Saved list exports through the actual dialog callback as reference metadata")
		var personal: Dictionary=tools.local.state.duplicate(true);digest=studio.content_digest();await press("Review as project recommendation…");check(tools.review_dialog.visible and studio.project_palette_document.data.is_empty() and studio.content_digest()==digest,"Project recommendation copy is an exact read-only review before Apply")
		await capture("project_review_"+mode);tools.review_dialog.confirmed.emit();await settle();var palette: Dictionary=studio.project_palette_document.data.duplicate(true)
		check(not palette.is_empty() and not palette["restricted"] and studio.dirty and studio.project_palette_document.undo_history.size()==1 and tools.local.state==personal,"Project recommendation changes shared-save metadata only and keeps personal collections exact")
		await press("Undo palette edit");check(studio.project_palette_document.data.is_empty(),"Actual project metadata Undo restores absent recommendations")
		await press("Redo palette edit");check(studio.project_palette_document.data==palette,"Actual project metadata Redo restores the exact recommendation")
		tools.dialog.hide();check(studio.write_project(OUT+"palette_"+mode+".isocity.json"),"Project with common recommendation saves")
		var content: Dictionary=studio.Store.read_json(OUT+"palette_"+mode+".isocity.json",{});check(content.get("project_palette")==JSON.parse_string(JSON.stringify(palette)) and not JSON.stringify(content).contains("favorites_migrated"),"Project file includes common recommendations but excludes personal preference state")
		studio.project_palette_document.restore({});studio.changed();check(studio.load_project(OUT+"palette_"+mode+".isocity.json"),"Normal project reopening accepts common palette metadata");await settle();check(JSON.parse_string(JSON.stringify(studio.project_palette_document.data))==JSON.parse_string(JSON.stringify(palette)) and not studio.dirty,"Normal reopening restores recommendations without repairs or false dirty state")
		content.erase("project_palette");studio.Store.write_json(OUT+"legacy_"+mode+".isocity.json",content);check(studio.load_project(OUT+"legacy_"+mode+".isocity.json"),"Legacy project without a palette reopens");await settle();check(studio.project_palette_document.data.is_empty() and not studio.session_data().has("project_palette"),"Missing legacy metadata does not leak the previous project's recommendation")
	studio.free();await process_frame;await process_frame;print("COLLECTION WORKFLOW: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
