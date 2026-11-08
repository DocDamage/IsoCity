extends SceneTree
const Plan=preload("res://scripts/builder/economy_plan.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for i in 6: await process_frame
	await physics_frame
func capture(name: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await settle(); await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://output/"+name+".png")
func cash(doc: RefCounted) -> int: return int(doc.data["economy_account"]["cash"])
func run() -> void:
	root.size=Vector2i(1480,900)
	var studio: Control=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio); await settle()
	for mode in ["2d","3d"]:
		studio.switch_mode(mode)
		var doc: RefCounted=preload("res://scripts/builder/document.gd").new(); doc.data=preload("res://scripts/builder/templates.gd").make(mode,"blank")
		var home: String="2d:House_Blue" if mode=="2d" else "3d:HanX_City/Row_Houses_A"
		var starter: Dictionary=doc.add(home,[-100,0,0] if mode=="2d" else [-10,0,-10],studio.library.directions(home)[0])
		var starter_uid: String=starter["uid"]
		studio.documents[mode]=doc; studio.changed(); await settle()
		var tools: RefCounted=studio.economy_tools; tools.show(); tools.enabled.button_pressed=true; tools.budget.value=4500; tools.period.value=10; tools.refund.value=25; tools.apply_settings(); await settle()
		check(Plan.settings(doc.data)["enabled"] and cash(doc)==4500 and doc.data["economy_account"]["holdings"].size()==1,"Inspector activates a chosen budget around the existing city: "+mode)
		var history: int=doc.undo_history.size(); tools.apply_settings()
		check(doc.undo_history.size()==history,"Unchanged economy settings do not create history entries: "+mode)
		tools.paused.button_pressed=true
		studio.drop_asset(home,studio.canvas.size*Vector2(.65,.7)); await settle()
		check(doc.data["objects"].size()==2 and cash(doc)==2500 and studio.worlds[mode].instances.size()==2,"Actual drag/drop construction spends the catalog price and renders the paid object: "+mode)
		var purchased_uid: String=doc.data["objects"].back()["uid"]
		studio.selected_uid=purchased_uid; studio.selected_uids.assign([purchased_uid]); studio.duplicate_selection(); await settle()
		check(doc.data["objects"].size()==3 and cash(doc)==500,"Duplicating an object consumes the same construction budget: "+mode)
		var accepted: Dictionary=doc.data.duplicate(true)
		studio.duplicate_selection(); await settle(); tools.refresh(); tools.refresh_badge()
		check(doc.data==accepted and "Insufficient" in doc.economy_error and studio.worlds[mode].instances.size()==3,"Unaffordable duplicates roll back before world rendering and explain the failure: "+mode)
		check(tools.badge.visible and "500 credits" in tools.badge.text and "Insufficient" in tools.notice.text,"The treasury and rejection remain visible independently of temporary action feedback: "+mode)
		studio._command("undo",null); await settle()
		check(doc.data["objects"].size()==2 and cash(doc)==2500,"A rejected edit adds no empty Undo step; Undo restores the previous purchase and cash: "+mode)
		studio._command("redo",null); await settle()
		check(doc.data["objects"].size()==3 and cash(doc)==500,"Redo restores the exact purchase once: "+mode)
		studio.paste_objects([doc.object(purchased_uid).duplicate(true),doc.object(purchased_uid).duplicate(true)],[40,0,40]); await settle()
		check(doc.data["objects"].size()==3 and cash(doc)==500,"Multi-object pastes and assemblies reject atomically when the whole operation is unaffordable: "+mode)
		# A road gesture may retain its already accepted prefix when a later
		# extension would exceed the budget, without stale stroke references.
		doc.checkpoint(); doc.data["roads"]=[{"cell":[0,0]}]; studio.changed()
		check(cash(doc)==260,"Road drawing spends construction funds: "+mode)
		doc.data["roads"].append({"cell":[1,0]}); studio.changed()
		check(cash(doc)==20 and doc.data["roads"].size()==2,"Successive updates of one gesture charge the cumulative difference exactly once: "+mode)
		studio.road_drawing=true; doc.data["roads"].append({"cell":[2,0]}); studio.changed()
		check(cash(doc)==20 and doc.data["roads"].size()==2 and not studio.road_drawing,"An over-budget road extension keeps accepted sections and stops the rejected gesture: "+mode)
		studio._command("undo",null); await settle()
		check(cash(doc)==500 and doc.data.get("roads",[]).is_empty(),"Undo reverses the entire accepted road gesture and its spending: "+mode)
		var ground: String=""
		for id in studio.library.assets:
			if studio.library.is_ground_tile(id) and Plan.profile(id,studio.library)["construction"]<=100: ground=id; break
		studio.select_asset(ground); doc.checkpoint(); studio.ground_brush.setup(studio.canvas.size*.5); studio.ground_brush.drawing=true
		var cells: Array[Vector2i]=[Vector2i(100,100),Vector2i(101,100)]
		studio.ground_brush.apply_cells(cells)
		var ground_cost: int=Plan.profile(ground,studio.library)["construction"]*2
		check(cash(doc)==500-ground_cost,"Actual ground painting charges each new tile or model surface: "+mode)
		cells.clear()
		for i in 510: cells.append(Vector2i(200+i,100))
		studio.ground_brush.apply_cells(cells)
		check(cash(doc)==500-ground_cost and not studio.ground_brush.drawing,"Over-budget brush batches retain prior accepted cells and release stale brush references: "+mode)
		studio._command("undo",null); await settle()
		check(cash(doc)==500 and doc.data["tiles"].is_empty() and doc.data["objects"].size()==3,"Ground Undo reverses accepted paint and spending as one gesture: "+mode)
		var before_template: Dictionary=doc.data.duplicate(true); studio.template_choice.select(0); studio._command("template",null); await settle()
		check(doc.data==before_template and Plan.settings(doc.data)["enabled"],"Applying an unaffordable template cannot erase the active budget or bypass construction costs: "+mode)
		# Starter rooms are supplied without a surprise charge on entry.
		studio.interior_tools.prepare(starter_uid,mode); await settle()
		check(doc.object(starter_uid).has("interior") and cash(doc)==500,"Generating the owned starter interior does not spend construction funds: "+mode)
		studio.interior_tools.start(starter_uid); await settle()
		check(studio.interior_tools.editing() and cash(doc)==500,"Entering the room editor retains the exterior treasury: "+mode)
		var room: RefCounted=studio.current(); var furniture: String=""
		for id in studio.library.assets:
			if studio.library.assets[id]["mode"]==mode and Plan.profile(id,studio.library)["construction"]==100 and not studio.library.is_ground_tile(id): furniture=id; break
		var count: int=room.data["objects"].size()
		room.checkpoint(); room.add(furniture,[80,40,0] if mode=="2d" else [5,0,5],studio.library.directions(furniture)[0]); studio.changed(); await settle()
		check(cash(doc)==400 and room.data["objects"].size()==count+1,"New room furniture spends the shared city treasury: "+mode)
		studio._command("undo",null); await settle()
		check(cash(doc)==500 and room.data["objects"].size()==count,"Room Undo restores furniture spending against the outer purchase book: "+mode)
		studio._command("redo",null); await settle()
		check(cash(doc)==400 and room.data["objects"].size()==count+1,"Room Redo restores its purchase exactly once: "+mode)
		room.checkpoint()
		for index in 5: room.add(furniture,[80+index*20,80,0] if mode=="2d" else [5+index,0,7],studio.library.directions(furniture)[0])
		studio.changed(); await settle()
		check(cash(doc)==400 and room.data["objects"].size()==count+1,"An unaffordable room batch restores the last accepted furnishing and treasury: "+mode)
		studio.interior_tools.leave(); await settle()
		check(studio.current()==doc and cash(doc)==400 and doc.object(starter_uid)["interior"]["objects"].size()==count+1,"Leaving the room retains the accepted budgeted furnishing: "+mode)
		studio._command("undo",null); await settle()
		check(cash(doc)==500 and doc.object(starter_uid)["interior"]["objects"].size()==count,"Exterior Undo restores a finished room edit and its treasury together: "+mode)
		studio._command("redo",null); await settle()
		check(cash(doc)==400 and doc.object(starter_uid)["interior"]["objects"].size()==count+1,"Exterior Redo restores a finished budgeted room edit exactly once: "+mode)
		studio.selected_uid=purchased_uid; studio.selected_uids.assign([purchased_uid]); studio._command("remove",null); await settle()
		check(cash(doc)==900 and doc.data["objects"].size()==2,"Editor demolition refunds the recorded paid basis: "+mode)
		var previous: int=cash(doc); var rates: Dictionary=Plan.forecast(doc.data,studio.library); var before_period: int=doc.data["economy_account"]["period"]
		tools.settle(); await settle()
		check(cash(doc)==previous+rates["net"] and doc.data["economy_account"]["period"]==before_period+1,"Manual accounting settles actual income minus upkeep: "+mode)
		studio._command("undo",null); await settle()
		check(cash(doc)==previous and doc.data["economy_account"]["period"]==before_period,"Accounting entries support Undo without losing or duplicating money: "+mode)
		tools.elapsed[mode]=9.75; tools.tick(.25)
		check(cash(doc)==previous and tools.elapsed[mode]==9.75,"Pause freezes the accounting clock: "+mode)
		tools.paused.button_pressed=false; tools.tick(.25)
		check(doc.data["economy_account"]["period"]==before_period+1 and cash(doc)==previous+rates["net"],"An active accounting period settles automatically: "+mode)
		tools.paused.button_pressed=true
		var frozen: float=tools.elapsed[mode]; studio.switch_mode("3d" if mode=="2d" else "2d"); tools.tick(.25)
		check(tools.elapsed[mode]==frozen,"Inactive worlds retain independent accounting clocks: "+mode)
		studio.switch_mode(mode); await settle(); tools.show()
		var saved_cash: int=cash(doc); var saved: String="res://output/economy_"+mode+".isocity.json"
		check(studio.write_project(saved),"Treasury and purchase history save with the project: "+mode)
		var saved_data: Dictionary=studio.Store.read_json(saved,{})["documents"][mode]
		check(Plan.normalized_account(saved_data["economy_account"])==doc.data["economy_account"] and Plan.valid_account(saved_data["economy_account"]),"Saved accounts include exact purchase bases and ledger totals: "+mode)
		tools.restart(); await settle()
		check(cash(doc)==4500 and doc.data["economy_account"]["construction_total"]==0 and doc.data["economy_account"]["holdings"].values().all(func(held: Dictionary):return held["paid"]==0),"An explicit new budget resets the starting city rather than retaining refundable free purchases: "+mode)
		studio._command("undo",null); await settle()
		check(cash(doc)==saved_cash,"Undo restores the previous treasury after an explicit reset: "+mode)
		tools.enabled.button_pressed=false; tools.apply_settings(); await settle()
		studio.selected_uid=doc.data["objects"].back()["uid"]; studio.selected_uids.assign([studio.selected_uid]); studio.duplicate_selection(); await settle()
		check(doc.data["objects"].size()==3 and cash(doc)==saved_cash,"Disabling economy permits unlimited creative construction without consuming the treasury: "+mode)
		check(studio.load_project(saved),"The saved economy city reopens: "+mode); await settle(); doc=studio.current(); tools.show(); tools.paused.button_pressed=true
		check(cash(doc)==saved_cash and tools.elapsed[mode]<1 and Plan.settings(doc.data)["enabled"],"Reopening restores funds and resets only preview time: "+mode)
		tools.refresh(); tools.refresh_badge(); await capture("economy_"+mode)
		var scene_path: String="res://output/economy_"+mode+".tscn"
		check(studio.Exporter.save_scene(studio.worlds[mode],doc.data,studio.library,scene_path)==OK,"Budgeted cities export as playable scenes: "+mode)
		var viewport:=SubViewport.new(); viewport.size=Vector2i(640,480); viewport.own_world_3d=true; root.add_child(viewport)
		var exported: Node=load(scene_path).instantiate(); viewport.add_child(exported); await settle(); exported.economy.set_process(false)
		check(exported.economy.panel.visible and exported.economy.data["economy_account"]["cash"]==saved_cash,"Playable scenes expose the exported treasury: "+mode)
		var original_period: int=exported.economy.data["economy_account"]["period"]; var export_rates: Dictionary=Plan.forecast(doc.data,studio.library)
		for i in 40: exported.economy.step(.25)
		check(exported.economy.data["economy_account"]["period"]==original_period+1 and exported.economy.data["economy_account"]["cash"]==saved_cash+export_rates["net"] and cash(doc)==saved_cash,"Exported accounting advances its own treasury without mutating the Studio document: "+mode)
		exported.economy.pause_button.pressed.emit(); var export_cash: int=exported.economy.data["economy_account"]["cash"]
		for i in 44: exported.economy.step(.25)
		check(exported.economy.paused and exported.economy.data["economy_account"]["cash"]==export_cash,"Exported accounting pause controls stop settlement: "+mode)
		viewport.free(); await settle()
		var portable: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(studio.worlds[mode],doc.data,studio.library,"res://output/economy_"+mode+".zip")
		check(portable["ok"],"Portable projects include the economy mode and authored treasury: "+mode)
	root.size=Vector2i(960,640); studio.economy_tools.show(); studio.economy_tools.refresh(); await settle()
	check(studio.economy_tools.panel.get_child(0).size.x<=studio.economy_tools.panel.size.x,"Economy controls fit the scrolling inspector at 960×640")
	await capture("economy_small_window")
	studio.queue_free(); await process_frame
	print("ECONOMY WORKFLOW: %d checks, %d failures" % [checks,failures]); quit(0 if failures==0 else 1)
