extends "res://tools/test_zone_workflow.gd"

const Stages=preload("res://scripts/builder/zone_stage_plan.gd")
const Doc=preload("res://scripts/builder/document.gd")
const Templates=preload("res://scripts/builder/templates.gd")
const Repair=preload("res://scripts/builder/project_repair.gd")
const Portable=preload("res://scripts/builder/portable_export.gd")
const EXPECTED: Dictionary={
	Plan.Stage.FOUNDATION:["Foundation_Rebar","Rebar_Bundle","Gravel_Pile"],
	Plan.Stage.FRAMING:["Building_Frame","Scaffold_Module"],
	Plan.Stage.FINISHING:["Scaffold_Module_Ladder","Pallet_Bricks","Lumber_Stack"],
}
var studio: Control
var output: String="res://output/construction_stages_fixture"

func fixture(mode: String) -> Dictionary:
	studio.switch_mode(mode)
	var doc:=Doc.new()
	doc.data=Templates.make(mode,"blank")
	doc.data["zoning"]={"enabled":true,"stage_seconds":2,"seed":7}
	doc.data["economy"]={"enabled":true,"starting_cash":25000}
	doc.data["economy_account"]=Plan.Economy.fresh_account(doc.data,studio.library)
	doc.data["roads"]=[]
	for x in range(-4,6): doc.data["roads"].append({"cell":[x,0]})
	studio.documents[mode]=doc
	studio.economy_tools.pauses[mode]=true
	studio.changed()
	await settle()
	var tools: RefCounted=studio.zone_tools
	var manager: Node=tools.managers[mode]
	manager.paused=true
	manager.set_process(false)
	tools.show()
	tools.kind.select(0)
	tools.add_rect(Rect2(-16,8,32,26))
	var uid: String=tools.selected
	tools.add_rect(Rect2(16,8,20,26))
	var adjacent: String=tools.selected
	tools.selected=uid
	tools.tick(.4)
	await settle()
	return {"doc":doc,"tools":tools,"manager":manager,"world":studio.worlds[mode],"uid":uid,"adjacent":adjacent}

func scenery(marker: Node) -> Array[Node]:
	var group: Node=marker.get_node_or_null("ConstructionScenery")
	return group.get_children() if is_instance_valid(group) else []

func prop_names(marker: Node) -> Array:
	return scenery(marker).map(func(model: Node)->String:return str(model.get_meta("stage_asset")).get_file())

func collision_free(model: Node) -> bool:
	for node in [model]+model.find_children("*","CollisionObject2D",true,false)+model.find_children("*","CollisionObject3D",true,false):
		if (node is CollisionObject2D or node is CollisionObject3D) and (node.collision_layer!=0 or node.collision_mask!=0): return false
	return true

func phase_checks(data: Dictionary,phase: int,mode: String) -> void:
	var doc: RefCounted=data["doc"]
	var uid: String=data["uid"]
	var lot: Dictionary=get_lot(doc,uid)
	var marker: Node=data["manager"].visuals[uid]
	var named: Array=prop_names(marker)
	check(lot["stage"]==phase and named==EXPECTED[phase],"The real "+Plan.stage_name(lot)+" stage uses its exact supplied art: "+mode+" "+str(named))
	check(doc.data["objects"].is_empty() and doc.data["economy_account"]["cash"]==25000 and doc.data["economy_account"]["construction_total"]==0,"Staging leaves saved objects and construction totals exact: "+mode)
	var context: Dictionary=Plan.site_context(doc.data,studio.library)
	var access: Dictionary=Plan.site_check(doc.data,lot,studio.library,lot["proposal"],Plan.road_access(doc.data,lot),[],context)
	var pad: Rect2=Plan.footprint(lot["proposal"],mode,studio.library)
	var clear: bool=access["ok"] and scenery(marker).size()==EXPECTED[phase].size()
	for model in scenery(marker):
		var occupied: Rect2=model.get_meta("stage_bounds")
		clear=clear and pad.grow(.001).encloses(occupied) and collision_free(model)
		for point in access.get("path",[]): clear=clear and not occupied.grow(.05).has_point(point)
	check(clear,"Real scenery fits inside the building pad and keeps its verified road approach clear: "+mode+" "+Plan.stage_name(lot))
	var identity: int=marker.get_instance_id()
	var props: Array=scenery(marker).map(func(prop: Node)->int:return prop.get_instance_id())
	for redraw in 5:
		data["manager"].configure(doc.data,studio.library,data["world"].objects)
		marker=data["manager"].visuals[uid]
	check(marker.get_instance_id()==identity and scenery(marker).map(func(prop: Node)->int:return prop.get_instance_id())==props,"Repeated redraw retains exactly the original scenery instances: "+mode)

func capture_phase(data: Dictionary,mode: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	var world: Node=data["world"]
	var tools: RefCounted=data["tools"]
	var manager: Node=data["manager"]
	var lot: Dictionary=get_lot(data["doc"],data["uid"])
	var pad: Rect2=Plan.footprint(lot["proposal"],mode,studio.library)
	var stage: String=Plan.stage_name(lot).to_lower()
	studio.set_process(false)
	for size in [Vector2i(1480,900),Vector2i(960,640)]:
		root.size=size
		studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true} if size.x==960 else {})
		if size.x==960: studio.workspace_layout.library_toggle.button_pressed=false
		var focus: Vector2=pad.get_center()
		if mode=="2d":
			var at: Array=Plan.Traffic.world(focus,mode)
			var zoom: float=clampf(28/maxf(4,pad.size.length()),1.8,4.1)
			var offset:=Vector2(45,-24) if studio.consumer_shell.active else Vector2(0,-24)
			if size.x==960:
				offset=Vector2(32,-8) if studio.consumer_shell.active else Vector2(0,10)
				if not studio.consumer_shell.active: zoom*=.78
			world.camera.zoom=Vector2.ONE*zoom
			world.camera.position=Vector2(at[0],at[1])+offset
		else:
			world.target=Vector3(focus.x,.7,focus.y)
			world.distance=maxf(9,pad.size.length()*1.85)
			world.yaw=34
			world.pitch=37
			world.update_camera()
		await settle()
		tools.tick(.4)
		await settle()
		check(tools.lots.get_item_text(0).contains(Plan.stage_name(lot)) and manager.visuals[data["uid"]].is_visible_in_tree() and (size.x!=960 or tools.detail.get_theme_font_size("font_size")==18),"Stage name and actual scene remain visible at the selected layout size: "+mode+" "+stage+" "+str(size))
		RenderingServer.force_draw(false)
		RenderingServer.force_draw(false)
		check(root.get_texture().get_image().save_png(output+"/%s_%s_%d.png"%[stage,mode,size.x])==OK,"Captured the actual "+stage+" stage: "+mode)
	root.size=Vector2i(1480,900)
	studio.accessibility_settings.restore({})
	studio.set_process(true)
	await settle()

func small_check(data: Dictionary,mode: String) -> void:
	var proposal: Dictionary=get_lot(data["doc"],data["uid"])["proposal"].duplicate(true)
	var lot: Dictionary={"uid":"small","kind":"residential","rect":[-56.0,8.0,4.0,4.0],"stage":Plan.Stage.FOUNDATION,"proposal":proposal}
	var footprint: Rect2=Plan.footprint(proposal,mode,studio.library)
	proposal["scale"]*=2.98/maxf(footprint.size.x,footprint.size.y)
	proposal["position"]=Plan.Traffic.world(Vector2.ZERO,mode)
	var origin: Vector2=Plan.rectangle(lot).get_center()-Plan.footprint(proposal,mode,studio.library).get_center()
	proposal["position"]=Plan.Traffic.world(origin,mode)
	var art: Dictionary=Stages.available(studio.library)
	var placement: Dictionary=Stages.layout(data["doc"].data,lot,studio.library,art,{})
	var fit: bool=not placement["props"].is_empty()
	for entry in placement["props"]: fit=fit and Plan.rectangle(lot).grow(-.5).encloses(entry["bounds"])
	check(fit,"A minimum-size lot scales supplied scenery inside its clearance margin: "+mode+" "+str(placement["props"]))

func workflow(mode: String) -> void:
	var data: Dictionary=await fixture(mode)
	var doc: RefCounted=data["doc"]
	var tools: RefCounted=data["tools"]
	var manager: Node=data["manager"]
	var world: Node=data["world"]
	var uid: String=data["uid"]
	var adjacent: String=data["adjacent"]
	check(doc.data["zones"].size()==2 and uid!=adjacent and scenery(manager.visuals[uid]).is_empty(),"Vacant lots share a boundary with no stage props: "+mode)
	var preview: Node=manager.make_visual({"uid":"draft","kind":"residential","rect":[-5,8,12,12],"stage":Plan.Stage.VACANT})
	check(scenery(preview).is_empty() and doc.data["zones"].size()==2,"The drawing preview has no authored stage or temporary scenery: "+mode)
	preview.free()
	for phase in [Plan.Stage.FOUNDATION,Plan.Stage.FRAMING,Plan.Stage.FINISHING]:
		var old: Array=scenery(manager.visuals[uid]).duplicate()
		tools.advance_selected()
		tools.tick(.4)
		await settle()
		check(old.all(func(node: Variant)->bool:return not is_instance_valid(node)),"A stage change frees all previous temporary assets: "+mode)
		phase_checks(data,phase,mode)
		await capture_phase(data,mode)
		if phase==Plan.Stage.FOUNDATION:
			small_check(data,mode)
			if "--packages" in OS.get_cmdline_user_args():
				var package: Dictionary=Portable.new().save(world,doc.data,studio.library,output+"/construction_"+mode+".zip")
				check(package["ok"],"The portable foundation includes future framing and finishing assets: "+mode+" "+str(package))
	var finished_plan: Dictionary=doc.data.duplicate(true)
	var finished_id: int=manager.visuals[uid].get_instance_id()
	manager.timers[uid]=.7
	manager.step(.25)
	check(manager.paused and manager.timers[uid]==.7 and manager.visuals[uid].get_instance_id()==finished_id,"Pausing retains the active scenery and freezes its progress: "+mode)
	if studio.consumer_shell:
		var simple: bool=studio.consumer_shell.active
		studio.consumer_shell.set_active(not simple,false)
		await settle()
		studio.consumer_shell.set_active(simple,false)
		await settle()
		check(manager.visuals[uid].get_instance_id()==finished_id and doc.data==finished_plan,"Changing workspace retains the same live staging and saved city: "+mode)
	var unavailable: Dictionary={}
	for id in Stages.available(studio.library):
		unavailable[id]=studio.library.assets[id].get("unavailable")
		studio.library.assets[id]["unavailable"]=true
	manager.configure(doc.data,studio.library,world.objects)
	check(scenery(manager.visuals[uid]).is_empty() and manager.visuals[uid].get_meta("stage_scenery_missing") and manager.visuals[uid].get_meta("stage_scenery_fallback") and doc.data==finished_plan and Stages.required_assets(doc.data,studio.library).is_empty(),"Missing scenery falls back without altering the stage or blocking portable collection: "+mode)
	for id in unavailable:
		if unavailable[id]==null: studio.library.assets[id].erase("unavailable")
		else: studio.library.assets[id]["unavailable"]=unavailable[id]
	manager.configure(doc.data,studio.library,world.objects)
	check(prop_names(manager.visuals[uid])==EXPECTED[Plan.Stage.FINISHING],"Restoring the pack redraws the same saved finishing stage: "+mode)
	var save: String=output+"/finishing_"+mode+".isocity.json"
	check(studio.write_project(save,false) and studio.load_project(save),"The normal save and load reopen a finishing lot: "+mode)
	await settle()
	doc=studio.current()
	data["doc"]=doc
	manager.paused=true
	tools.tick(.4)
	tools.selected=uid
	check(get_lot(doc,uid)["stage"]==Plan.Stage.FINISHING and prop_names(manager.visuals[uid])==EXPECTED[Plan.Stage.FINISHING] and manager.timers[uid]==0,"Reload restores the exact phase with fresh transient clocks: "+mode)
	var current: Dictionary=doc.data.duplicate(true)
	var to_free: Array=scenery(manager.visuals[uid]).duplicate()
	var adjacent_id: int=manager.visuals[adjacent].get_instance_id()
	tools.restart_lot()
	tools.tick(.4)
	await settle()
	check(to_free.all(func(node: Variant)->bool:return not is_instance_valid(node)) and scenery(manager.visuals[uid]).is_empty() and get_lot(doc,uid)["stage"]==Plan.Stage.VACANT and manager.visuals[adjacent].get_instance_id()==adjacent_id,"Restart clears the lot once and leaves its shared boundary neighbor intact: "+mode)
	studio._command("undo",null)
	await settle()
	tools.tick(.4)
	check(doc.data==current and prop_names(manager.visuals[uid])==EXPECTED[Plan.Stage.FINISHING],"Undo restores the exact finishing stage and budget: "+mode)
	var building: Dictionary=get_lot(doc,uid)["proposal"].duplicate(true)
	var price: int=Plan.Economy.profile(building["asset"],studio.library)["construction"]
	to_free=scenery(manager.visuals[uid]).duplicate()
	tools.selected=uid
	tools.advance_selected()
	tools.tick(.4)
	await settle()
	check(get_lot(doc,uid)["stage"]==3 and to_free.all(func(node: Variant)->bool:return not is_instance_valid(node)) and scenery(manager.visuals[uid]).is_empty() and doc.data["objects"].size()==1 and world.instances.has(building["uid"]) and doc.data["economy_account"]["cash"]==25000-price,"Completion clears the scenery and places one ordinary paid building: "+mode)
	var repair:=Repair.new(studio.library)
	var legacy: Dictionary=repair.world(doc.data,mode,"test/legacy-completed",0)
	check(get_lot_data(legacy,uid).get("stage")==3 and Plan.evaluate(legacy,get_lot_data(legacy,uid),studio.library).get("complete",false) and repair.issues.is_empty(),"The older saved developed value still loads as completed: "+mode)

func get_lot_data(data: Dictionary,uid: String) -> Dictionary:
	for lot in data["zones"]:
		if lot["uid"]==uid: return lot
	return {}

func run() -> void:
	if OS.has_environment("ISOCITY_CONSTRUCTION_OUTPUT"): output=OS.get_environment("ISOCITY_CONSTRUCTION_OUTPUT")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size=Vector2i(1480,900)
	studio=load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled=false
	root.add_child(studio)
	await settle()
	if studio.consumer_shell:
		studio.consumer_shell.dismiss_welcome()
		studio.consumer_shell.set_active("--simple" in OS.get_cmdline_user_args(),false)
	for mode in ["2d","3d"]: await workflow(mode)
	studio.free()
	await settle()
	print("CONSTRUCTION STAGES: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
