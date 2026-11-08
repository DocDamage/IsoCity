extends SceneTree
const Plan=preload("res://scripts/builder/zone_plan.gd")
const EXPECTATION_OUTPUT: String="res://output/verification/asset_expansion/I15"
static func fixture_output(default_path: String) -> String:
	var path: String=OS.get_environment("ISOCITY_ZONE_OUTPUT")
	if path.is_empty(): return default_path
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	return path
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
	root.get_texture().get_image().save_png(fixture_output("res://output").path_join(name+".png"))
func screen(studio: Control,point: Vector2) -> Vector2: return studio.overlay_position(Plan.Traffic.world(point,studio.mode))
func draw(studio: Control,bounds: Rect2) -> void:
	studio.zone_tools.draw_mode()
	var button:=InputEventMouseButton.new(); button.button_index=MOUSE_BUTTON_LEFT; button.pressed=true; button.position=screen(studio,bounds.position); studio._canvas_input(button)
	var motion:=InputEventMouseMotion.new(); motion.position=screen(studio,bounds.end); studio._canvas_input(motion)
	button.pressed=false; button.position=motion.position; studio._canvas_input(button)
func get_lot(doc: RefCounted,uid: String) -> Dictionary:
	for lot in doc.data.get("zones",[]):
		if lot["uid"]==uid: return lot
	return {}
func run() -> void:
	root.size=Vector2i(1480,900)
	var output_dir: String=fixture_output("res://output")
	var studio: Control=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio); await settle()
	for mode in ["2d","3d"]:
		studio.switch_mode(mode)
		var doc: RefCounted=preload("res://scripts/builder/document.gd").new(); doc.data=preload("res://scripts/builder/templates.gd").make(mode,"blank")
		doc.data["roads"]=[]
		for x in range(-12,17): doc.data["roads"].append({"cell":[x,0]})
		doc.data["economy"]={"enabled":true,"starting_cash":20000}; doc.data["economy_account"]=Plan.Economy.fresh_account(doc.data,studio.library)
		doc.data["citizens"]={"enabled":true,"population":2}; doc.data["traffic"]={"enabled":true,"population":2}
		studio.documents[mode]=doc; studio.changed(); await settle()
		var tools: RefCounted=studio.zone_tools; var manager: Node=tools.managers[mode]; manager.set_process(false); tools.show(); tools.enabled.button_pressed=true; tools.seconds.value=2; tools.seed.value=7; tools.apply_settings(); tools.paused.button_pressed=true; studio.economy_tools.paused.button_pressed=true; await settle()
		check(Plan.settings(doc.data)["enabled"] and Plan.settings(doc.data)["stage_seconds"]==2,"Inspector enables authored growth settings: "+mode)
		var history: int=doc.undo_history.size(); tools.apply_settings()
		check(doc.undo_history.size()==history,"Unchanged growth settings create no history entry: "+mode)
		if mode=="2d":
			var target: Array=Plan.Traffic.world(Vector2(32,0),mode); studio.worlds[mode].camera.position=Vector2(target[0],target[1]); studio.worlds[mode].camera.zoom=Vector2.ONE*.35
		else: studio.worlds[mode].target=Vector3(32,0,0); studio.worlds[mode].distance=145; studio.worlds[mode].update_camera()
		await settle()
		var rectangles: Array=[Rect2(-56,8,48,48),Rect2(8,8,48,48),Rect2(72,8,48,48),Rect2(-24,-56,48,48)]; var ids: Array[String]=[]
		for index in 4:
			tools.kind.select(0 if index<2 else index-1); draw(studio,rectangles[index]); tools.tick(.4); await settle()
			if doc.data.get("zones",[]).size()>index: ids.append(doc.data["zones"][index]["uid"])
		check(ids.size()==4 and doc.data["objects"].is_empty() and doc.data["economy_account"]["cash"]==20000,"Actual canvas drags designate four typed lots without constructing or charging buildings: "+mode)
		if ids.size()!=4: print(studio.status.text); continue
		check(manager.visuals.size()==4 and not tools.drawing and not studio.stroke,"Lots render as independent markers and release the drawing gesture: "+mode)
		tools.draw_mode(); var controls: RefCounted=studio.control_settings; controls.cursor_active=true; controls.cursor_position=screen(studio,Vector2(40,-56)); controls.execute("cursor_drag"); controls.cursor_position=screen(studio,Vector2(88,-8)); controls.execute("cursor_drag"); tools.tick(.4)
		check(doc.data["zones"].size()==5 and not tools.drawing and not controls.dragging,"Remappable keyboard canvas dragging can designate a lot: "+mode)
		studio._command("undo",null); await settle(); tools.tick(.4)
		check(doc.data["zones"].size()==4,"Keyboard-created lots use normal Undo: "+mode)
		var before: Dictionary=doc.data.duplicate(true); draw(studio,rectangles[0]); tools.tick(.4)
		check(doc.data==before and "Cannot add lot" in studio.status.text,"Overlapping designations are rejected without editing city content: "+mode)
		tools.selected=ids[0]; tools.fields_stamp=0; tools.refresh_lot(); tools.name_input.text="Residential west"; tools.apply_lot(); tools.tick(.4)
		check(get_lot(doc,ids[0])["name"]=="Residential west","Selected lot fields can be authored through the inspector: "+mode)
		tools.locked.button_pressed=true; tools.x_input.value=999; tools.apply_lot()
		check(get_lot(doc,ids[0])["rect"]==[-56.0,8.0,48.0,48.0] and get_lot(doc,ids[0])["locked"],"Locked lots reject geometry changes: "+mode)
		tools.locked.button_pressed=false; tools.shown.button_pressed=false; tools.tick(.4)
		check(not manager.visuals.has(ids[0]),"Hidden lot markers are removed: "+mode)
		tools.shown.button_pressed=true; tools.tick(.4); tools.refresh_lot()
		tools.advance_selected(); tools.tick(.4); await settle()
		check(get_lot(doc,ids[0])["stage"]==1 and doc.data["objects"].is_empty() and doc.data["economy_account"]["cash"]==20000,"Manual advancement creates the saved visible foundation before any building purchase: "+mode)
		check(manager.visuals.has(ids[0]) and manager.visuals[ids[0]].get_child_count()>=1 if mode=="3d" else manager.visuals[ids[0]].lot["stage"]==1,"The foundation visual matches the actual construction stage: "+mode)
		var old_target: Variant=studio.worlds[mode].camera.position if mode=="2d" else studio.worlds[mode].target
		var old_zoom: float=studio.worlds[mode].camera.zoom.x if mode=="2d" else studio.worlds[mode].distance
		tools.locate()
		if mode=="2d": studio.worlds[mode].camera.zoom=Vector2.ONE*1.1
		else: studio.worlds[mode].distance=32; studio.worlds[mode].update_camera()
		await capture("zoning_foundation_"+mode)
		var scene_path: String=output_dir.path_join("zoning_pending_"+mode+".tscn")
		check(studio.Exporter.save_scene(studio.worlds[mode],doc.data,studio.library,scene_path)==OK,"Unfinished lots export before their future buildings exist: "+mode)
		var viewport:=SubViewport.new(); viewport.size=Vector2i(800,600); viewport.own_world_3d=true; root.add_child(viewport)
		var exported: Node=load(scene_path).instantiate(); viewport.add_child(exported); await settle(); exported.zoning.set_process(false); exported.economy.set_process(false); exported.citizens.set_physics_process(false); exported.traffic.set_physics_process(false); exported.player.set_physics_process(false)
		exported.walking=false; exported._set_mode()
		var cars: Array=exported.traffic.vehicles.map(func(car: Dictionary):return car["actor"].get_instance_id())
		for frame in 1000:
			exported.zoning.people=exported.development_people(); exported.zoning.step(.25)
			if exported.live_data["zones"].all(func(lot: Dictionary):return lot["stage"]==3): break
		check(exported.live_data["zones"].all(func(lot: Dictionary):return lot["stage"]==3) and exported.city_instances.size()==4,"Actual playable exports grow all three lot types into real rendered buildings: "+mode)
		check(exported.studio_data["objects"].is_empty() and doc.data["objects"].is_empty() and get_lot(doc,ids[0])["stage"]==1,"Export development preserves the authored source and Studio preview: "+mode)
		check(exported.economy.data["objects"].size()==4 and exported.economy.data["economy_account"]["construction_total"]>0 and exported.economy.rates["income"]==exported.live_data["objects"].reduce(func(total: int,item: Dictionary):return total+Plan.Economy.profile(item["asset"],studio.library)["income"],0),"Exported growth shares construction funds and updates operating income with the new city: "+mode)
		check(exported.citizens.residents.size()==2 and exported.citizens.plan["destinations"]["home"].size()==2 and exported.businesses.service.businesses.size()==exported.live_data["objects"].filter(func(item: Dictionary):return preload("res://scripts/builder/business_plan.gd").profile(item)["kind"]!="none").size(),"New homes and commercial buildings join exported citizen routines and business activities: "+mode)
		check(cars.size()==2 and exported.traffic.vehicles.size()==2 and exported.traffic.vehicles.all(func(car: Dictionary):return car["actor"].get_instance_id() in cars),"Export growth retains the existing moving traffic actors: "+mode)
		var cash_before: int=exported.economy.data["economy_account"]["cash"]; var period_before: int=exported.economy.data["economy_account"]["period"]; var net: int=exported.economy.rates["net"]; exported.economy.elapsed=0
		for i in int(Plan.Economy.settings(exported.live_data)["period_seconds"])*4: exported.economy.step(.25)
		check(exported.economy.data["economy_account"]["cash"]==cash_before+net and exported.economy.data["economy_account"]["period"]==period_before+1,"A complete operating period settles income and upkeep from the newly developed city: "+mode)
		exported.zoning.update_hud(); check(exported.zoning.panel.visible,"Playable exports expose development counts and pause controls: "+mode)
		exported.zoning.pause_button.pressed.emit(); var frozen: Dictionary=exported.zoning.timers.duplicate(true); exported.zoning.step(.25)
		check(exported.zoning.paused and exported.zoning.timers==frozen,"The exported development pause control freezes its clocks: "+mode)
		viewport.free(); await settle()
		var portable: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(studio.worlds[mode],doc.data,studio.library,output_dir.path_join("zoning_"+mode+".zip"))
		check(portable["ok"],"Portable packages collect future zoning buildings before they are placed: "+mode)
		var expected_future: Dictionary={}
		for lot_value in doc.data.get("zones",[]):
			for ident in Plan.future_assets(lot_value,mode,studio.library):expected_future[ident]=studio.library.assets[ident]["path"]
		var expectation_dir: String=fixture_output(EXPECTATION_OUTPUT);DirAccess.make_dir_recursive_absolute(expectation_dir);FileAccess.open(expectation_dir.path_join("zone_expectation_"+mode+".json"),FileAccess.WRITE).store_string(JSON.stringify({"world":doc.data,"future":expected_future,"candidate_revision":Plan.Candidates.definitions()["revision"]},"\t"))
		tools.advance_selected(); tools.tick(.4); await settle()
		check(get_lot(doc,ids[0])["stage"]==2 and doc.data["objects"].is_empty(),"Framing is a separate visible authored stage: "+mode)
		await capture("zoning_framing_"+mode)
		tools.advance_selected(); tools.tick(.4); await settle()
		check(get_lot(doc,ids[0])["stage"]==Plan.Stage.FINISHING and doc.data["objects"].is_empty(),"Finishing is an authored stage with temporary material scenery: "+mode)
		if mode=="2d": studio.worlds[mode].camera.position=old_target; studio.worlds[mode].camera.zoom=Vector2.ONE*old_zoom
		else: studio.worlds[mode].target=old_target; studio.worlds[mode].distance=old_zoom; studio.worlds[mode].update_camera()
		var proposal: Dictionary=get_lot(doc,ids[0])["proposal"].duplicate(true);var selected_price: int=Plan.Economy.profile(proposal["asset"],studio.library)["construction"]
		studio.set_walking(true); studio.worlds[mode].player.set_physics_process(false)
		var center: Array=Plan.Traffic.world(Plan.footprint(proposal,mode,studio.library).get_center(),mode)
		studio.worlds[mode].player.teleport_to(Vector2(center[0],center[1]) if mode=="2d" else Vector3(center[0],.1,center[2])); await settle(); tools.tick(.4); tools.advance_selected()
		check(get_lot(doc,ids[0])["stage"]==Plan.Stage.FINISHING and doc.data["objects"].is_empty() and "people" in studio.status.text,"A real exploration player in the footprint prevents building completion: "+mode)
		studio.set_walking(false)
		var car: Dictionary=studio.traffic_tools.managers[mode].vehicles[0]; var old_point: Vector2=car["point"]; car["point"]=Plan.footprint(proposal,mode,studio.library).get_center(); studio.traffic_tools.managers[mode].pose(car); tools.advance_selected()
		check(get_lot(doc,ids[0])["stage"]==Plan.Stage.FINISHING and doc.data["objects"].is_empty(),"A live traffic vehicle in the footprint prevents construction through the car: "+mode)
		car["point"]=old_point; studio.traffic_tools.managers[mode].pose(car); tools.advance_selected(); tools.tick(.4); await settle()
		check(get_lot(doc,ids[0])["stage"]==3 and studio.worlds[mode].instances.has(proposal["uid"]) and doc.data["economy_account"]["cash"]==20000-selected_price,"Clearing the footprint creates the actual editable home and charges once: "+mode)
		studio._command("undo",null); await settle(); tools.tick(.4)
		check(get_lot(doc,ids[0])["stage"]==Plan.Stage.FINISHING and doc.data["objects"].is_empty() and doc.data["economy_account"]["cash"]==20000,"Undo restores the construction stage, real scene and funds together: "+mode)
		studio._command("redo",null); await settle(); tools.tick(.4)
		check(doc.data["objects"].size()==1 and doc.data["economy_account"]["cash"]==20000-selected_price,"Redo restores the exact completed home without a second charge: "+mode)
		tools.selected=ids[1]; tools.fields_stamp=0; tools.refresh_lot()
		var clocks: Dictionary=manager.timers.duplicate(true); manager.step(.25)
		check(manager.timers==clocks,"Pause freezes growth clocks: "+mode)
		studio.switch_mode("3d" if mode=="2d" else "2d"); tools.tick(.4); manager.step(.25)
		check(manager.timers==clocks and not manager.container.visible,"Inactive worlds suspend and hide their development preview: "+mode)
		studio.switch_mode(mode); await settle(); tools.tick(.4); tools.paused.button_pressed=false
		for i in 1000:
			tools.tick(.25); manager.step(.25)
			if doc.data["zones"].all(func(lot: Dictionary):return lot["stage"]==3): break
		check(doc.data["zones"].all(func(lot: Dictionary):return lot["stage"]==3) and doc.data["objects"].size()==4,"Timed development grows the second home, then commercial and civic lots as neighborhood demand becomes available: "+mode)
		var cost: int=0
		for item in doc.data["objects"]: cost+=Plan.Economy.profile(item["asset"],studio.library)["construction"]
		check(doc.data["economy_account"]["cash"]==20000-cost and doc.data["economy_account"]["construction_total"]==cost,"Automatic growth spends exactly the actual completed buildings' prices: "+mode)
		tools.paused.button_pressed=true; tools.show(); await capture("zoning_developed_"+mode)
		var visual_id: int=manager.visuals[ids[0]].get_instance_id(); doc.checkpoint(); doc.data["title"]="Zoned city"; studio.changed(); tools.tick(.4)
		check(manager.visuals[ids[0]].get_instance_id()==visual_id,"Ordinary city edits retain unchanged lot marker instances: "+mode)
		studio.set_walking(true); var walk: Node=studio.worlds[mode].exploration; var player: Node=studio.worlds[mode].player; player.teleport_to(walk.entrance(studio.worlds[mode].instances[proposal["uid"]])); await settle(); walk.interact(); await settle(); tools.tick(.4)
		clocks=manager.timers.duplicate(true); var stamp: int=manager.signature; manager.step(.25)
		check(walk.interior!=null and manager.timers==clocks and manager.signature==stamp and not manager.container.visible,"Interior visits suspend growth without rebuilding exterior plans from disabled collisions: "+mode)
		walk.leave_interior(); studio.set_walking(false); await settle(); tools.tick(.4)
		check(manager.visuals[ids[0]].get_instance_id()==visual_id and get_lot(doc,ids[0])["stage"]==3,"Returning outside preserves lot visuals and completed stages: "+mode)
		var saved: String=output_dir.path_join("zoning_"+mode+".isocity.json"); check(studio.write_project(saved),"Lot definitions and development stages save with the city: "+mode)
		tools.selected=ids[0]; tools.remove_lot(); tools.tick(.4)
		check(doc.data["zones"].size()==3 and doc.data["objects"].size()==4 and doc.object(proposal["uid"]).has("interior"),"Removing a lot preserves the editable building and its owned room: "+mode)
		check(studio.load_project(saved),"Saved zoned cities reopen: "+mode); await settle(); doc=studio.current(); tools.tick(.4)
		check(doc.data["zones"].size()==4 and manager.visuals.size()==4 and manager.timers.values().all(func(value: Variant):return value==0),"Reopening restores lot stages and starts fresh transient growth clocks: "+mode)
		studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true}); await settle(); tools.tick(.4)
		check(tools.enabled.custom_minimum_size.y>=44 and tools.detail.get_theme_font_size("font_size")==18,"Zoning controls follow enlarged text and click targets: "+mode)
		var marker: Node=manager.visuals.values()[0]
		check(is_equal_approx(marker.text_scale,1.5) if mode=="2d" else marker.find_children("*","Label3D",true,false)[0].font_size==36,"Lot annotations scale without recreating the construction geometry: "+mode)
		studio.accessibility_settings.restore({}); await settle(); tools.tick(.4)
	root.size=Vector2i(960,640); studio.zone_tools.show(); studio.zone_tools.refresh(); await settle()
	check(studio.zone_tools.panel.get_child(0).size.x<=studio.zone_tools.panel.size.x,"Zoning controls fit their scrolling inspector at 960×640")
	await capture("zoning_small_window")
	studio.queue_free(); await process_frame
	print("ZONE WORKFLOW: %d checks, %d failures" % [checks,failures]); quit(0 if failures==0 else 1)
