extends SceneTree
const OUT="res://output/verification/asset_expansion/U02/"
var checks: int=0
var failures: int=0
var studio: Control
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func settle(frames: int=10) -> void:
	for frame in frames:await process_frame
func capture(name: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args():return
	await settle();await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUT+name+".png")==OK,"Actual collection capture: "+name)
func key(code: Key) -> void:
	for pressed in [true,false]:
		var event:=InputEventKey.new();event.keycode=code;event.pressed=pressed;Input.parse_input_event(event);await process_frame
func ids(found: Array) -> Array:
	var result: Array=[]
	for item in found:result.append(item["id"])
	result.sort();return result
func run() -> void:
	var library: RefCounted=preload("res://scripts/builder/asset_library.gd").new();var index: RefCounted=library.tasks
	check(index.tasks.size()==4,"Four reviewed furnishing tasks are indexed")
	for task in index.tasks:
		for style in index.tasks[task]["sets"]:
			var found: Dictionary=index.members(task,style)
			check(found["missing"].is_empty() and not found["ids"].is_empty(),"Each coordinated source set resolves actual prepared assets: "+task+" "+style)
			for id in found["ids"]:
				check(library.assets.has(id) and found["ids"][id]["part"] in ["essential","extra"],"Task references concrete art with an explicit furnishing role: "+id)
			var essentials: Dictionary=index.members(task,style,"essential");var extras: Dictionary=index.members(task,style,"extra")
			check(not essentials["ids"].is_empty() and not extras["ids"].is_empty() and essentials["ids"].size()+extras["ids"].size()==found["ids"].size(),"Essential/extra groups partition this set: "+task+" "+style)
	var camp: Dictionary=index.members("campsite","camping","",true)
	check(camp["ids"].is_empty() and camp["outdoor"].size()==8,"Outdoor campsite artwork cannot silently enter an interior collection")
	check(index.members("garage","hanx","",true)["outdoor"]==["3d:HanX_GasStation/Car_Coupe"],"Garage yard vehicle is explicitly outdoor")
	var chair: Dictionary=library.assets["3d:HanX_School/Student_Chair"];library.assets.erase(chair["id"]);index.build(library.assets)
	check(index.members("classroom","hanx")["missing"]==[chair["id"]] and index.members("classroom","classroom_sprites")["missing"].is_empty(),"Missing packs remain explained and alternative coordinated sets stay available")
	library.assets[chair["id"]]=chair;index.build(library.assets)
	check(index.members("classroom","hanx")["missing"].is_empty(),"Rebuilding after restored content clears stale missing states")
	studio=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio);await settle(20)
	if not studio.consumer_shell:check(false,"Consumer shell initialized");studio.free();quit(1);return
	var ui: RefCounted=studio.consumer_shell;var browser: RefCounted=studio.asset_browser;var tools: RefCounted=browser.task_collections
	ui.dismiss_welcome()
	for mode in ["2d","3d"]:
		studio.switch_mode(mode);studio.current().data=preload("res://scripts/builder/templates.gd").make(mode,"blank");studio.changed();await settle()
		var before: Dictionary=studio.current().data.duplicate(true);var history: int=studio.current().undo_history.size()
		ui.open_drawer("build");ui.query.text="spaceship";browser.set_theme("space");tools.choose("classroom");await settle()
		check(ui.query.text.is_empty() and browser.theme_filter.is_empty() and tools.style=="hanx" and ui.group=="Everything" and ui.matches().size()==8,"Choosing a task reveals its coordinated set despite conflicting old filters: "+mode)
		var availability: Dictionary=studio.library.tasks.available.duplicate()
		for id in studio.library.tasks.members("classroom","hanx")["ids"]:studio.library.tasks.available[id]=false
		studio.library.tasks.revision+=1;tools.commit();await settle()
		check(ui.matches().is_empty() and tools.controls[-1]["note"].is_visible_in_tree() and tools.controls[-1]["note"].text.contains("8 items unavailable"),"A completely missing coordinated pack has a visible explanation")
		tools.style="classroom_sprites";tools.commit();await settle();check(ui.matches().size()==5,"Alternative supplied style remains reachable when the preferred pack is missing")
		studio.library.tasks.available=availability;studio.library.tasks.revision+=1;tools.choose("classroom");await settle();check(ui.matches().size()==8,"Restored pack invalidates the visible collection cache")
		for task in ["classroom","cafe","campsite","garage"]:
			tools.choose(task);await settle();check(not ui.matches().is_empty() and ui.matches().all(func(asset: Dictionary):return tools.matches(asset)),"Actual Simple cards use the selected collection: "+mode+" "+task);await capture(task+"_"+mode)
		tools.choose("classroom");tools.part="essential";tools.commit();await settle();check(ui.matches().size()==3,"Essentials control filters the actual classroom cards")
		tools.style="";tools.part="";tools.commit();await settle();check(ui.matches().size()==13,"Explicit mixed-source choice exposes all reviewed classroom sets")
		ui.set_active(false,false);await settle();check(ids(studio.library_matches())==ids(ui.matches()) and browser.chips.has_node("task"),"Precision browsing shares collection and exposes a removable task chip")
		var saved: Dictionary=tools.state();browser.semantic_search.broaden();await settle();check(tools.task.is_empty(),"Broadening includes assets outside the selected task")
		browser.semantic_search.restore_filters();await settle();check(tools.state()==saved,"Restore filters restores task, coordinated set and part")
		check(studio.current().data==before and studio.current().undo_history.size()==history,"Collection browsing changes no document, history, economy or simulation configuration: "+mode)
		ui.set_active(true,false);tools.choose("classroom");ui.open_drawer("build");await settle()
		var card: Button=studio.cards.get_child(0);var picked: String=card.asset_id;studio.repeat_input.set_pressed_no_signal(false);card.pressed.emit();await settle()
		check(studio.asset_id==picked and tools.task=="classroom" and ui.drawer_kind.is_empty() and not studio.repeat_input.button_pressed,"Single-placement selection preserves task context: "+mode)
		studio.current().checkpoint();studio.stroke=true;studio.paint(studio.canvas.size*.5);studio.finish_stroke();studio.current().finish_checkpoint();await settle()
		check(studio.current().data["objects"].size()==1 and studio.asset_id.is_empty(),"Normal single placement completes once: "+mode)
		studio._command("undo",null);await settle();check(studio.current().data["objects"].is_empty(),"Ordinary Undo removes task-selected placement")
		ui.open_drawer("build");await settle();check(tools.task=="classroom" and not ui.matches().is_empty(),"Reopening after placement retains collection context")
		studio.repeat_input.set_pressed_no_signal(true);studio.cards.get_child(0).pressed.emit();await settle();picked=studio.asset_id
		studio.current().checkpoint();studio.stroke=true;studio.paint(studio.canvas.size*.5);studio.finish_stroke();studio.current().finish_checkpoint();await settle()
		check(studio.asset_id==picked and studio.tool=="place" and studio.current().data["objects"].size()==1 and tools.task=="classroom","Normal repeated placement retains the asset and collection")
		studio.clear_placement();studio.repeat_input.set_pressed_no_signal(false);studio._command("undo",null);await settle()
		var owner: Dictionary=studio.current().add("3d:HanX_School/School_Building",[0,0,0],"0");studio.changed();studio.interior_tools.start(owner["uid"]);await settle();ui.open_drawer("build");tools.choose("campsite");await settle()
		check(ui.matches().is_empty() and tools.controls[-1]["note"].text.contains("8 outdoor items hidden"),"Empty outdoor task inside a room explains its context restriction")
		studio.interior_tools.leave();await settle();ui.open_drawer("build");check(ui.matches().size()==8,"Returning outside restores the same campsite task")
		tools.choose("garage")
		for dimensions in [Vector2i(1480,900),Vector2i(960,640)]:
			root.size=dimensions;await settle()
			for simple in [true,false]:
				ui.set_active(simple,false)
				if simple:ui.open_drawer("build")
				else:browser.filters_manual=true;browser.filters_expanded=false;browser.fit_filters()
				await settle();check((ui.card_scroll if simple else studio.cards.get_parent()).size.y>=96,"Browsing retains a thumbnail viewport in both workspaces: "+mode+" "+str(dimensions));await capture(("simple_" if simple else "precision_")+mode+"_"+str(dimensions.x))
		ui.set_active(true,false);root.size=Vector2i(960,640);studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true});ui.open_drawer("build");await settle()
		var choice: OptionButton=tools.controls[-1]["task"];check(root.get_visible_rect().encloses(choice.get_global_rect()),"Enlarged task selector remains visible at 960×640")
		check(ui.card_scroll.is_visible_in_tree() and ui.card_scroll.size.y>=96,"Enlarged compact task browsing keeps a useful thumbnail viewport")
		tools.choose("");await settle();choice.grab_focus();await key(KEY_SPACE);await settle();check(choice.get_popup().visible,"Keyboard opens the task selector");await key(KEY_DOWN);await key(KEY_ENTER);await settle()
		check(tools.task=="classroom" and tools.controls[0]["task"].get_item_metadata(tools.controls[0]["task"].selected)=="classroom","Keyboard task choice synchronizes both workspaces")
		await capture("accessible_"+mode);ui.theme_canvas.grab_focus();await key(KEY_SPACE);await settle();check(root.gui_get_focus_owner()==studio.canvas and ui.drawer_kind.is_empty(),"Keyboard returns from collections to the canvas")
		studio.accessibility_settings.restore({});root.size=Vector2i(1480,900)
		tools.clear();ui.close_drawer()
		studio.current().data=preload("res://scripts/builder/templates.gd").make(mode,"blank")
		for entry in [["classroom","3d:HanX_School/Student_Chair"],["cafe","3d:HanX_Shop/Cafe_Table_Set"],["garage","3d:HanX_GasStation/Workbench"]]:
			tools.choose(entry[0]);check(tools.matches(studio.library.assets[entry[1]]),"Export fixture comes from its actual collection")
			var count: int=studio.current().data["objects"].size();var item: Dictionary=studio.current().add(entry[1],[count*120,0,0] if mode=="2d" else [count*4,0,0],"0");item["uid"]="task_"+entry[0]
		studio.changed();await settle();var authored: Dictionary=studio.current().data.duplicate(true)
		check(studio.write_project(OUT+"selected_"+mode+".isocity.json") and studio.load_project(OUT+"selected_"+mode+".isocity.json") and studio.current().data["objects"]==JSON.parse_string(JSON.stringify(authored["objects"])),"Task-selected assets save/reopen with exact identities and authored values: "+mode)
		check(studio.Store.write_json(OUT+"expected_"+mode+".json",studio.current().data),"Independent authored expectation saved")
		var exported: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(studio.worlds[mode],studio.current().data,studio.library,OUT+"selected_"+mode+".zip")
		check(exported["ok"],"Permitted task selections export through the existing dependency collector: "+mode)
	tools.settings_path=OUT+"preferences.json";tools.choose("classroom");tools.part="extra";tools.commit();var settings: Dictionary=tools.state();studio.storage_enabled=true;tools.persist();studio.storage_enabled=false;tools.clear();tools.restore(studio.Store.read_json(tools.settings_path,{}))
	check(tools.state()==settings,"Task/set/part preference persists separately from project data")
	for invalid in [true,[],{"task":[]},{"task":"unknown"},{"task":"classroom","style":false,"part":5}]:
		tools.restore(invalid);check(tools.task.is_empty() or (tools.task=="classroom" and tools.style=="hanx" and tools.part.is_empty()),"Malformed preferences fall back to validated collection state")
	FileAccess.open(OUT+"blocked_parent.txt",FileAccess.WRITE).store_string("not a directory");tools.settings_path=OUT+"blocked_parent.txt/preferences.json";studio.storage_enabled=true;tools.persist();studio.storage_enabled=false
	check(studio.status.text.contains("session"),"Failed preference writes retain usable session state")
	tools.clear()
	studio.free();await process_frame;print("TASK COLLECTIONS: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
