extends SceneTree
const OUT="res://output/verification/asset_expansion/I13/"
const Kits=preload("res://scripts/builder/interior_kits.gd")
const Plan=preload("res://scripts/builder/prop_plan.gd")
const Grid=preload("res://scripts/builder/grid_fit.gd")
var studio: Control
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func settle() -> void:
	for frame in 6:await physics_frame
	await process_frame
func walking_point(point: Vector2,mode: String) -> Variant:
	return Grid.pixels(point) if mode=="2d" else Vector3(point.x,.2,point.y)
func capture(name: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args():return
	for frame in 12:await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUT+name+".png")==OK,"Rendered capture: "+name)
func metric(point: Variant,mode: String) -> Vector2:
	return Grid.grid(point) if mode=="2d" else Vector2(point.x,point.z)
func reachable_space(world: Node,mode: String) -> Dictionary:
	var start:=Vector2i((metric(world.player.global_position,mode)/.25).round());var visited: Dictionary={};var tested: Dictionary={};var pending: Array=[start];var cursor: int=0
	var limit: int=20 if mode=="2d" else 15
	while cursor<pending.size():
		var cell: Vector2i=pending[cursor];cursor+=1
		if tested.has(cell):continue
		tested[cell]=true
		if abs(cell.x)>limit or abs(cell.y)>limit:continue
		if not Plan.standing_clear(world.exploration,walking_point(Vector2(cell)*.25,mode)):continue
		visited[cell]=true
		for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			if not tested.has(cell+offset):pending.append(cell+offset)
	return visited
func select(uid: String) -> void:
	studio.selected_uids.assign([uid]);studio.selected_uid=uid
func financial(mode: String) -> void:
	studio.switch_mode(mode);var city=preload("res://scripts/builder/document.gd").new();city.data=preload("res://scripts/builder/templates.gd").make(mode,"blank");studio.documents[mode]=city
	var economy=preload("res://scripts/builder/economy_plan.gd");var host: Dictionary=city.add("3d:HanX_School/School_Building",[0,0,0],"0");var uid: String=host["uid"]
	city.data["economy"]={"enabled":true,"starting_cash":100000,"period_seconds":60,"refund_percent":25};city.data["economy_account"]=economy.fresh_account(city.data,studio.library);studio.changed();await settle()
	var before: Dictionary=city.data.duplicate(true);select(uid);studio.interior_tools.start(uid);await settle();studio.interior_tools.leave();await settle()
	check(city.data["economy_account"]["cash"]==100000 and city.data["economy_account"]["construction_total"]==0,"Automatic reviewed kit is complimentary through the actual editor: "+mode)
	var allowance: Dictionary=preload("res://scripts/builder/cooperative_plan.gd").complimentary_rooms(before,city.data,studio.library);var quote: Dictionary=economy.quote(before,city.data,studio.library,allowance)
	check(quote["ok"] and quote["construction"]==0,"Authoritative co-op allowance covers the same reviewed kit: "+mode)
	var extra: Dictionary=city.data.duplicate(true);var chair: Dictionary=extra["objects"][0]["interior"]["objects"].filter(func(item: Dictionary):return item["asset"]=="3d:HanX_School/Student_Chair")[0].duplicate(true);chair["uid"]="unapproved_extra";extra["objects"][0]["interior"]["objects"].append(chair)
	allowance=preload("res://scripts/builder/cooperative_plan.gd").complimentary_rooms(before,extra,studio.library);quote=economy.quote(before,extra,studio.library,allowance)
	check(quote["ok"] and quote["construction"]>0,"Co-op starter allowance does not grant extra furnishings: "+mode)
	before=city.data.duplicate(true);select(uid);studio.duplicate_selection();await settle();quote=economy.quote(before,city.data,studio.library)
	check(quote["ok"] and quote["construction"]>economy.profile(host["asset"],studio.library)["construction"] and city.data["economy_account"]["cash"]==100000-quote["net"],"Duplicated owner and furnishings are charged exactly once: "+mode)
	city.finish_checkpoint();studio.economy_tools.refresh_fields();studio.economy_tools.budget.value=0;studio.economy_tools.apply_settings();studio.economy_tools.restart();await settle()
	var accepted: Dictionary=city.data.duplicate(true);var history: int=city.undo_history.size();studio.duplicate_selection();await settle()
	var rejection: String=city.economy_error;city.finish_checkpoint()
	check(city.data==accepted and city.undo_history.size()==history and rejection.contains("Insufficient"),"Unaffordable furnished duplicate leaves no completed history step: "+mode)
func empty_choice(mode: String) -> void:
	studio.switch_mode(mode);var city=preload("res://scripts/builder/document.gd").new();city.data=preload("res://scripts/builder/templates.gd").make(mode,"blank");studio.documents[mode]=city
	var host: Dictionary=city.add("3d:HanX_School/School_Building",[0,0,0],"0");select(host["uid"]);studio.changed();await settle();studio.interior_tools.refresh();var before: Dictionary=city.data.duplicate(true)
	# The previous fixture deliberately rejects a purchase. Finish its deferred
	# reconciliation before showing this separate blank-city choice.
	studio.status.text="Choose the default starter or start with an empty room.";await settle()
	check(studio.interior_tools.empty_button.visible and studio.interior_tools.starter_hint.text.contains("Classroom") and city.data==before and not host.has("interior"),"Inspecting the first-creation choice does not create a room: "+mode)
	if "--capture" in OS.get_cmdline_user_args():await review_choice(mode,city,before)
	if "--capture" in OS.get_cmdline_user_args():
		for pressed in [true,false]:
			var event:=InputEventKey.new();event.keycode=KEY_ENTER;event.pressed=pressed;Input.parse_input_event(event);await process_frame
	else:studio.interior_tools.empty_button.pressed.emit()
	await settle()
	check(studio.interior_tools.editing() and studio.current().data.get("starter_kit",{}).get("id")=="empty" and not studio.current().data["objects"].any(func(item: Dictionary):return item["asset"]=="3d:HanX_School/Student_Chair"),"Actual empty-room action preserves shell/exit without furnishings: "+mode)
	studio.interior_tools.leave();await settle()
	studio.accessibility_settings.restore({});root.size=Vector2i(1480,900);studio.consumer_shell.set_active(true,false)
func review_choice(mode: String,city: RefCounted,before: Dictionary) -> void:
	for dimensions in [Vector2i(1480,900),Vector2i(960,640)]:
		root.size=dimensions
		for simple in [true,false]:
			studio.consumer_shell.set_active(simple,false)
			if simple:studio.consumer_shell.open_details("Entrance")
			else:studio.workspace_layout.inspector_toggle.button_pressed=true;studio.workspace_presets.show_tab("Entrance")
			await settle();reveal(studio.interior_tools.empty_button);await capture("choice_"+("simple_" if simple else "precision_")+mode+"_"+str(dimensions.x))
	root.size=Vector2i(960,640);studio.consumer_shell.set_active(true,false);studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true});studio.consumer_shell.open_details("Entrance");await settle();reveal(studio.interior_tools.empty_button);await settle()
	check(Rect2(Vector2.ZERO,Vector2(root.size)).has_point(studio.interior_tools.empty_button.get_global_rect().get_center()),"Enlarged keyboard action remains reachable: "+mode);await capture("choice_accessible_"+mode+"_960")
	check(city.data==before,"Reviewing starter/empty choices still creates no room")
func reveal(control: Control) -> void:
	var parent: Node=control.get_parent()
	while not parent is ScrollContainer and parent.get_parent():parent=parent.get_parent()
	if parent is ScrollContainer:parent.ensure_control_visible(control)
	control.grab_focus()
func fixture(mode: String,key: String,asset: String) -> void:
	studio.status.text=""
	studio.switch_mode(mode);var city=preload("res://scripts/builder/document.gd").new();city.data=preload("res://scripts/builder/templates.gd").make(mode,"blank");studio.documents[mode]=city
	var host: Dictionary=city.add(asset,[0,0,0],studio.library.directions(asset)[0]);var uid: String=host["uid"];studio.changed();await settle();select(uid);studio.interior_tools.start(uid);await settle()
	check(studio.interior_tools.editing(),"Building opens its actual owned-room editor: "+mode+" "+key)
	if not studio.interior_tools.editing():return
	studio.consumer_shell.close_overlays();await capture("kit_"+key+"_"+mode)
	var doc: RefCounted=studio.current();check(doc.data.get("starter_kit",{}).get("id")==key,"Building chooses its reviewed kit: "+mode+" "+key)
	var before: Dictionary=doc.data.duplicate(true);var history: int=doc.undo_history.size();var world: Node=studio.worlds[mode]
	studio.set_walking(true);await settle();world.player.set_physics_process(false)
	check(Plan.standing_clear(world.exploration,world.player.global_position),"Default exit/spawn clears the actual walking shape: "+mode+" "+key)
	var reachable: Dictionary=reachable_space(world,mode);check(not reachable.is_empty(),"Exit has a connected clear walking region: "+mode+" "+key)
	for item in doc.data["objects"]:
		var profile: Dictionary=Plan.profile(item)
		if profile.is_empty():continue
		var candidate: Dictionary=Plan.context(world.exploration).duplicate(false);candidate["item"]=item;candidate["node"]=world.instances[item["uid"]];candidate["profile"]=profile
		var point: Variant=Plan.ground_point(candidate,world.exploration,"approach");var cell:=Vector2i((metric(point,mode)/.25).round())
		check(Plan.standing_clear(world.exploration,point),"Functional station approach clears actual geometry: "+mode+" "+key+" "+item["asset"])
		check(reachable.has(cell),"Station approach connects to the exit's clear region: "+mode+" "+key+" "+item["asset"])
		world.player.teleport_to(world.player.get_parent().to_local(point));check(world.exploration.props.interact(candidate),"Furnishing starts its actual existing interaction: "+mode+" "+key+" "+item["asset"])
		check(world.exploration.props.finish(),"Furnishing returns to clear standing space")
	check(doc.data==before and doc.undo_history.size()==history,"Ordinary room use changes no authored content or history: "+mode+" "+key)
	studio.set_walking(false);doc.checkpoint();doc.data["objects"][-1]["name"]="My retained furnishing";doc.finish_checkpoint();studio.changed()
	check(studio.write_project(OUT+key+"_"+mode+".isocity.json"),"Save from inside retains owned content: "+mode+" "+key)
	studio.interior_tools.leave();await settle();check(studio.load_project(OUT+key+"_"+mode+".isocity.json"),"Saved interior reopens: "+mode+" "+key)
	if studio.interior_tools.editing():studio.interior_tools.leave()
	city=studio.current();check(city.object(uid).get("interior",{}).get("objects",[]).any(func(item: Dictionary):return item.get("name")=="My retained furnishing"),"Reload preserves customized furnishings")
	select(uid);studio.duplicate_selection();await settle();var copied: Dictionary=city.object(studio.selected_uid);var original_ids: Array=city.object(uid)["interior"]["objects"].map(func(item: Dictionary):return item["uid"])
	check(copied.get("interior",{}).get("objects",[]).all(func(item: Dictionary):return not item["uid"] in original_ids),"Actual owner duplication renews interior object identities")
	studio.remove_selection();studio._command("undo",null);await settle();check(city.data["objects"].size()==2,"Delete/Undo restores duplicated owner and furnishings")
	studio._command("undo",null);await settle();check(city.data["objects"].size()==1,"Undo duplicate preserves the original room")
func export_fixture(mode: String) -> void:
	studio.switch_mode(mode);var city=preload("res://scripts/builder/document.gd").new();city.data=preload("res://scripts/builder/templates.gd").make(mode,"blank");studio.documents[mode]=city;var index: int=0
	for pair in [["classroom","3d:HanX_School/School_Building"],["cafe","3d:HanX_Shop/Shop_Cafe"],["shop","3d:HanX_Shop/Shop_Grocery"],["garage","3d:HanX_GasStation/Repair_Garage"],["station","2d:Police"]]:
		var position: Array=[index*480,-400,0] if mode=="2d" else [index*30,0,-30]
		var item: Dictionary=city.add(pair[1],position,studio.library.directions(pair[1])[0]);item["uid"]="kit_"+pair[0];preload("res://scripts/builder/interiors.gd").ensure(item,mode,studio.library);index+=1
	var lazy: Dictionary=city.add("3d:HanX_School/School_Building",[0,640,0] if mode=="2d" else [0,0,36],"0");lazy["uid"]="unvisited_school"
	studio.changed();await settle();check(studio.write_project(OUT+"kits_"+mode+".isocity.json"),"Aggregate owned/unvisited city saves: "+mode)
	var exported: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(studio.worlds[mode],city.data,studio.library,OUT+"kits_"+mode+".zip")
	check(exported["ok"],"Owned and lazy starter dependencies export: "+mode+" "+exported.get("message",""))
	check(preload("res://scripts/builder/project_store.gd").write_json(OUT+"expected_"+mode+".json",city.data),"Expected authored fixture saved")
	for kind in ["lazy","empty"]:
		var isolated: Dictionary=preload("res://scripts/builder/templates.gd").make(mode,"blank");var host: Dictionary={"uid":"only_school","asset":"3d:HanX_School/School_Building","position":[0,-400,0] if mode=="2d" else [0,0,-30],"direction":"0","scale":1.0};isolated["objects"]=[host]
		if kind=="empty":host["interior"]=preload("res://scripts/builder/interiors.gd").make_for(host,mode,studio.library,"empty")
		exported=preload("res://scripts/builder/portable_export.gd").new().save(studio.worlds[mode],isolated,studio.library,OUT+kind+"_"+mode+".zip")
		check(exported["ok"],"Isolated "+kind+" school exports independently: "+mode)
		check(preload("res://scripts/builder/project_store.gd").write_json(OUT+"expected_"+kind+"_"+mode+".json",isolated),"Isolated expected source saved")
func run() -> void:
	var store=preload("res://scripts/builder/project_store.gd");store.storage_root=OUT+"history";store.legacy_autosave=OUT+"legacy.json"
	studio=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio);await settle()
	for frame in 120:
		if studio.consumer_shell:break
		await process_frame
	if not studio.consumer_shell:check(false,"Consumer shell initialized");studio.free();quit(1);return
	studio.consumer_shell.dismiss_welcome()
	for mode in ["2d","3d"]:
		for pair in [["classroom","3d:HanX_School/School_Building"],["cafe","3d:HanX_Shop/Shop_Cafe"],["shop","3d:HanX_Shop/Shop_Grocery"],["garage","3d:HanX_GasStation/Repair_Garage"],["station","2d:Police"]]:await fixture(mode,pair[0],pair[1])
		await financial(mode);await empty_choice(mode);await export_fixture(mode)
	studio.free();await process_frame;print("INTERIOR KITS WORKFLOW: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
