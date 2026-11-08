extends SceneTree
const OUT="res://output/verification/asset_expansion/U14/"
const Economy=preload("res://scripts/builder/economy_plan.gd")
var checks: int=0
var failures: int=0
var studio: Control
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func settle() -> void:
	for frame in 12:await process_frame
func capture(name: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args():return
	await settle();await RenderingServer.frame_post_draw;check(root.get_texture().get_image().save_png(OUT+name+".png")==OK,"Actual recent-assets capture: "+name)
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT);FileAccess.open(OUT+".gdignore",FileAccess.WRITE).close()
	studio=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio);await settle();await settle()
	var recent: RefCounted=studio.asset_browser.recents;var tasks: RefCounted=studio.asset_browser.task_collections;var ui: RefCounted=studio.consumer_shell;ui.dismiss_welcome()
	for mode in ["2d","3d"]:
		studio.switch_mode(mode);studio.current().data=preload("res://scripts/builder/templates.gd").make(mode,"blank");studio.changed();await settle();tasks.choose("classroom");ui.open_drawer();await settle()
		studio.saved_digest=studio.content_digest();studio.dirty=false;studio.update_save_badge()
		var authored: String=studio.content_digest();var history_size: int=studio.current().undo_history.size();var before: Dictionary=recent.history.state();var dirty: bool=studio.dirty
		studio.select_asset("3d:HanX_School/Student_Chair");await settle();studio.clear_placement();ui.open_drawer();await settle()
		check(recent.history.state()==before and studio.content_digest()==authored and studio.current().undo_history.size()==history_size and studio.dirty==dirty,"Hover/selection/cancel and reopening never record or author a placement: "+mode)
		studio.drop_asset("3d:HanX_School/Student_Chair",studio.canvas.size*.5);await settle()
		check(recent.history.ids("classroom").has("3d:HanX_School/Student_Chair") and recent.history.ids("").has("3d:HanX_School/Student_Chair"),"Actual successful placement records its concrete ID in the task and global histories: "+mode)
		var placed_source: Dictionary=studio.current().data.duplicate(true);var placed_recents: Dictionary=recent.history.state();studio._command("undo",null);await settle()
		check(studio.current().data["objects"].is_empty() and recent.history.state()==placed_recents,"Ordinary construction Undo restores the city while retaining successful-placement preferences: "+mode)
		studio._command("redo",null);await settle();check(studio.current().data==placed_source and recent.history.state()==placed_recents,"Redo restores the same construction without duplicating recent entries: "+mode)
		var saved_history: Dictionary=recent.history.state();var doc: RefCounted=studio.current();doc.data["layers"]={"Furniture":{"visible":true,"locked":true}};studio.changed();studio.drop_asset("3d:HanX_School/Teacher_Chair",studio.canvas.size*.7);await settle()
		check(recent.history.state()==saved_history and not doc.data["objects"].any(func(item: Dictionary):return item["asset"]=="3d:HanX_School/Teacher_Chair"),"Layer-rejected placement never reaches recent history: "+mode)
		doc.data.erase("layers");doc.data["economy"]={"enabled":true,"starting_cash":0};doc.data["economy_account"]=Economy.fresh_account(doc.data,studio.library);studio.changed();var objects: Array=doc.data["objects"].duplicate(true)
		studio.drop_asset("3d:HanX_School/Student_Desk",studio.canvas.size*.7);await settle()
		check(recent.history.state()==saved_history and doc.data["objects"]==objects and doc.data["economy_account"]["cash"]==0,"Unaffordable rollback never records an optimistic placement: "+mode)
		doc.data["economy"]["enabled"]=false;studio.changed();ui.open_drawer();recent.set_only(true);await settle()
		var ids: Array=studio.library_matches().map(func(asset: Dictionary):return asset["id"])
		check(ids==["3d:HanX_School/Student_Chair"],"Both native model artwork and its exact recent identity remain browsable in either world: "+mode)
		ui.query.text="chair";await settle();var task_state: Dictionary=tasks.state();ui.close_drawer();ui.open_drawer();await settle()
		check(ui.query.text=="chair" and tasks.state()==task_state and recent.only and studio.page==0,"Reopening retains task, query and recent filter: "+mode)
		await capture("recent_"+mode)
		var descriptor: Dictionary=studio.library.assets["3d:HanX_School/Student_Chair"].duplicate(true);studio.library.assets.erase(descriptor["id"]);studio.refresh_library();await settle()
		check(not recent.active() and studio.library_matches().size()>0 and recent.note().contains("showing") and recent.history.ids("classroom").has(descriptor["id"]),"A removed source retains its ID and falls back to the matching current library: "+mode)
		studio.library.assets[descriptor["id"]]=descriptor;studio.refresh_library();await settle();check(recent.active() and studio.library_matches().size()==1,"Restoring an asset re-enables its exact recent card: "+mode)
		studio.asset_browser.semantic_search.broaden();check(not recent.only,"Broader search clears recent restriction reversibly: "+mode);studio.asset_browser.semantic_search.restore_filters();check(recent.only,"Restore filters restores the recent/task context: "+mode)
		tasks.choose("garage");recent.set_only(true);await settle();check(not recent.active() and studio.library_matches().size()>0 and recent.history.ids("classroom")==saved_history["histories"]["classroom"],"New activity uses its own empty fallback without deleting another task's history: "+mode)
		tasks.choose("");studio.brush_input.value=1;studio.drop_asset("3d:HanX_Shop/Floor_Tile_Store",studio.canvas.size*.5);await settle()
		check(recent.history.ids("")[0]=="3d:HanX_Shop/Floor_Tile_Store","Actual model-surface ground painting records a successful asset: "+mode)
		if mode=="2d":
			doc.data["tiles"]=[];studio.changed();var tile_id: String=studio.worlds[mode].tile_lookup.keys()[0];studio.drop_asset(tile_id,studio.canvas.size*.5);await settle()
			check(not doc.data["tiles"].is_empty() and recent.history.ids("")[0]==tile_id,"Actual native tile-cell painting records only an applied ground change")
		# Exercise a session-private descriptor using real prepared art, without
		# changing the custom registry or any supplied source files.
		var custom_id: String="3d:Custom/Recent_Local_"+mode;var custom: Dictionary=descriptor.duplicate(true);custom["id"]=custom_id;custom["name"]="Private recent fixture";custom["data"]["source_export_allowed"]=false;custom["data"]["preview_path"]="res://resources/previews_3d/HanX_School/Student_Chair.png";studio.library.assets[custom_id]=custom
		studio.drop_asset(custom_id,studio.canvas.size*.65);await settle()
		check(recent.history.ids("")[0]==custom_id and not JSON.stringify(recent.history.state()).contains(".tscn") and not JSON.stringify(recent.history.state()).contains(custom["name"]),"Actual private/custom placement stores its local concrete ID without descriptors, names or source paths: "+mode)
		tasks.choose("");ui.query.text="a";ui.refresh_catalog();await settle();check(studio.library_matches().size()>60,"Long browser fixture genuinely spans multiple pages")
		studio.page=2;studio.refresh_library();await settle();ui.card_scroll.scroll_vertical=120;await settle();var scroll: int=ui.card_scroll.scroll_vertical
		check(scroll>0,"Long browser fixture has actual scrollable cards")
		ui.close_drawer();ui.open_drawer();await settle();check(studio.page==2 and ui.query.text=="a" and ui.card_scroll.scroll_vertical==scroll,"Reopening restores the exact page and scroll after card/container layout: "+mode)
		var selection_history: Dictionary=recent.history.state();studio.cards.get_child(0).pressed.emit();await settle();check(ui.drawer_kind.is_empty(),"A real asset-card activation closes the drawer for placement")
		ui.open_drawer();await settle();check(studio.page==2 and ui.query.text=="a" and ui.card_scroll.scroll_vertical==scroll and recent.history.state()==selection_history,"Real selection/cancel reopening retains page/scroll without recording a placement: "+mode)
		ui.close_drawer();ui.query.text="desk";ui.open_drawer();await settle();check(ui.query.text=="desk","An older scroll restoration cannot overwrite a newer query")
		# An exact placed appearance remains distinct even with normal family grouping on.
		studio.asset_browser.clear_all_filters();var family: Array=[]
		for members in studio.library.families.members.values():
			if members.size()>1:family=members;break
		check(family.size()>1,"Concrete family fixture exists")
		if family.size()>1:
			recent.history.remember(family[-1],"",studio.library.tasks.tasks);recent.set_only(true);await settle();check(studio.library_matches().any(func(asset: Dictionary):return asset["id"]==family[-1]),"Recent cards retain the exact member when normal families are collapsed")
		ui.close_drawer();ui.set_active(false,false);studio.asset_browser.clear_all_filters();recent.set_only(true);await settle()
		check(studio.library_matches().any(func(asset: Dictionary):return asset["id"]==family[-1]),"Precision also preserves concrete recent appearances")
		for size in [Vector2i(1480,900),Vector2i(960,640)]:
			root.size=size;await settle();await capture("precision_"+mode+"_"+str(size.x));ui.set_active(true,false);ui.open_drawer();await settle();await capture("simple_"+mode+"_"+str(size.x));ui.close_drawer();ui.set_active(false,false)
		ui.set_active(true,false);root.size=Vector2i(960,640);studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true});ui.open_drawer();await settle()
		var button: Button=recent.controls[-1];check(button.is_visible_in_tree() and button.size.y>=44 and ui.card_scroll.size.y>=96,"Enlarged compact task/recent controls retain useful artwork and large targets")
		var only_before: bool=recent.only;var keyboard_source: String=studio.content_digest();button.grab_focus()
		for pressed in [true,false]:
			var event:=InputEventKey.new();event.keycode=KEY_SPACE;event.pressed=pressed;Input.parse_input_event(event);await process_frame
		await settle();check(recent.only!=only_before and studio.content_digest()==keyboard_source,"Keyboard toggles the actual compact Recent control without authoring content: "+mode);recent.set_only(only_before);await settle()
		await capture("accessible_"+mode);ui.close_drawer();studio.accessibility_settings.restore({});root.size=Vector2i(1480,900)
		# Portable fixtures contain permitted applied content, never local history.
		recent.only=false;tasks.choose("");studio.current().data=preload("res://scripts/builder/templates.gd").make(mode,"blank");studio.library.assets.erase(custom_id);studio.changed();studio.drop_asset("3d:HanX_School/Student_Chair",studio.canvas.size*.5);await settle()
		check(studio.Store.write_json(OUT+"expected_"+mode+".json",studio.current().data),"Independent expected source saved")
		check(studio.write_project(OUT+"recent_"+mode+".isocity.json") and not JSON.stringify(studio.session_data()).contains("histories"),"Project saving excludes local recent preferences")
		var local_history: Dictionary=recent.history.state();check(studio.load_project(OUT+"recent_"+mode+".isocity.json") and recent.history.state()==local_history,"Normal project reopening preserves the user's separate local histories")
		var exported: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(studio.worlds[mode],studio.current().data,studio.library,OUT+"recent_"+mode+".zip");check(exported["ok"],"Permitted successful placements export ordinarily")
	var snapshot: Dictionary=recent.history.state();var previous_project: String=studio.project_id;var independent: Dictionary=studio.session_data().duplicate(true);independent["project_id"]=studio.Store.new_id();independent["project_path"]="";independent["project_origin_path"]="";studio.Store.write_json(OUT+"independent.isocity.json",independent)
	check(studio.load_project(OUT+"independent.isocity.json") and studio.project_id!=previous_project and recent.history.state()==snapshot,"Opening an independent project retains personal IDs without importing them into the new document")
	recent.settings_path=OUT+"preferences.json";studio.storage_enabled=true;recent.persist();studio.storage_enabled=false;recent.history.histories={};recent.restore();check(recent.history.state()==snapshot,"Local recent IDs reopen separately from saved project data")
	var good_hash: String=FileAccess.get_sha256(recent.settings_path)
	for content in ["not JSON","true",'{"version":false,"histories":{}}'," ".repeat(262145)+JSON.stringify(snapshot)]:
		FileAccess.open(OUT+"invalid_preferences.json",FileAccess.WRITE).store_string(content);recent.settings_path=OUT+"invalid_preferences.json";recent.restore();check(recent.history.histories.is_empty(),"Malformed or oversized local preference files produce a safe empty fallback")
	recent.settings_path=OUT+"preferences.json";recent.restore()
	FileAccess.open(OUT+"blocked_parent.txt",FileAccess.WRITE).store_string("not a directory");recent.settings_path=OUT+"blocked_parent.txt/preferences.json";studio.storage_enabled=true;recent.persist();studio.storage_enabled=false;check(recent.history.state()==snapshot and studio.status.text.contains("session") and FileAccess.get_sha256(OUT+"preferences.json")==good_hash,"Failed preference writes retain the complete usable session history and previous good file")
	studio.free();await process_frame;await process_frame;print("RECENT ASSET WORKFLOW: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
