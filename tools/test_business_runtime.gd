extends SceneTree
const Plan=preload("res://scripts/builder/business_plan.gd")
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
func run() -> void:
	root.size=Vector2i(1480,900)
	var studio: Control=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio); await settle()
	for mode in ["2d","3d"]:
		studio.switch_mode(mode)
		var doc: RefCounted=preload("res://scripts/builder/document.gd").new()
		doc.data=preload("res://scripts/builder/templates.gd").make(mode,"blank")
		doc.add("2d:Apartment_Brick" if mode=="2d" else "3d:HanX_City/Apartment_4F_A",[-160,-96,0] if mode=="2d" else [-14,0,-12],"SW" if mode=="2d" else "90")
		var cafe: Dictionary=doc.add("2d:Coffee_Shop" if mode=="2d" else "3d:HanX_City/Cafe_Small",[160,96,0] if mode=="2d" else [14,0,12],"SE" if mode=="2d" else "0")
		var uid: String=cafe["uid"]
		doc.data["citizens"]={"enabled":true,"population":3,"seed":5,"day_length":3600,"start_hour":12.5}
		studio.documents[mode]=doc; studio.changed(); await settle()
		var tools: RefCounted=studio.business_tools; tools.show()
		studio.selected_uids.assign([uid]); studio.selected_uid=uid; tools.refresh_selection()
		tools.kind.select(1); tools.opening.value=0; tools.closing.value=24; tools.capacity.value=1; tools.duration.value=2; tools.apply_settings(); await settle()
		check(cafe["business"]["kind"]=="cafe" and cafe["business"]["capacity"]==1,"Business inspector configures activities and capacity: "+mode)
		var manager: Node=tools.managers[mode]; var citizens: Node=studio.citizen_tools.managers[mode]
		manager.set_physics_process(false); citizens.set_physics_process(false); manager.hour=12.5
		var before: Dictionary=doc.data.duplicate(true); var history: int=doc.undo_history.size()
		var queued: bool=false; var completed: bool=false
		for frame in 6000:
			citizens.step(1.0/60); manager.step(1.0/60,false)
			if manager.service.visits.values().any(func(v: Dictionary):return v["state"]=="queued"): queued=true
			if manager.service.inventory.size()==3 and manager.service.inventory.values().all(func(items: Dictionary):return items.get("Coffee",0)==1): completed=true; break
		check(completed,"Residents physically walk to the business and complete actual coffee activities: "+mode+str(citizens.residents.map(func(r: Dictionary):return r["status"])))
		check(queued,"Arriving residents queue outside when business capacity is full: "+mode)
		check(manager.service.history.size()==3,"Resident completions are recorded once per visit: "+mode)
		check(doc.data==before and doc.undo_history.size()==history,"Business visits and session rewards never edit the city or history: "+mode)
		studio.set_walking(true); studio.worlds[mode].player.set_physics_process(false)
		var walk: Node=studio.worlds[mode].exploration; var player: Node=studio.worlds[mode].player
		player.teleport_to(Vector2(10000,10000) if mode=="2d" else Vector3(1000,0,1000))
		check(not manager.request_player(uid,"coffee")["ok"],"Remote players cannot trigger business activities: "+mode)
		player.teleport_to(walk.entrance(studio.worlds[mode].instances[uid])); await settle()
		studio.control_settings.execute("business")
		check(manager.service.result("player").get("state","")=="active","The walking shortcut starts a nearby player's activity: "+mode)
		manager.step(2,false); manager.update_ui()
		check(manager.panel.visible and manager.progress.visible and manager.progress.value>0 and manager.progress.value<100 and "Preparing coffee" in manager.caption.text,"The exploration HUD shows live timed progress: "+mode)
		manager.ui_scale=1.5; manager.large_targets=true; manager.high_contrast=true; manager.update_ui()
		check(manager.cancel_button.custom_minimum_size.y==44 and manager.buttons.get_child(0).get_theme_font_size("font_size")==21 and manager.panel.get_theme_stylebox("panel").border_width_left==2,"Business activity controls support enlarged text, targets and contrast: "+mode)
		manager.ui_scale=1; manager.large_targets=false; manager.high_contrast=false
		await capture("business_player_activity_"+mode)
		manager.step(4,false); manager.update_ui()
		check(manager.service.inventory["player"]["Coffee"]==1 and "Coffee" in manager.items.text,"Player activity completion grants and displays an actual session item: "+mode)
		await settle()
		var pointer:=InputEventMouseMotion.new(); pointer.position=studio.canvas.get_global_rect().position+manager.buttons.get_child(1).get_global_rect().get_center(); root.push_input(pointer,true)
		var click:=InputEventMouseButton.new(); click.button_index=MOUSE_BUTTON_LEFT; click.pressed=true; click.position=pointer.position; root.push_input(click,true)
		click=click.duplicate(); click.pressed=false; root.push_input(click,true)
		check(manager.service.result("player")["action"]=="snack","A different activity can be chosen from its actual HUD button: "+mode)
		studio.control_settings.execute("business_cancel")
		check(manager.service.result("player")["state"]=="cancelled" and not manager.service.inventory["player"].has("Snack"),"Cancelled activities do not grant an item: "+mode)
		walk.interact(); await settle()
		check(walk.interior!=null and walk.interior_uid==uid,"The existing entrance opens this business's owned interior: "+mode)
		studio.control_settings.execute("business_secondary")
		check(manager.service.result("player")["state"]=="active" and manager.service.result("player")["action"]=="snack","The second activity shortcut works inside owned business interiors: "+mode)
		manager.step(8,false); manager.update_ui()
		check(manager.service.inventory["player"]["Snack"]==1 and manager.panel.visible,"Activities complete while exploring the business interior: "+mode)
		await capture("business_interior_activity_"+mode)
		walk.leave_interior(); await settle()
		manager.request_player(uid,"coffee")
		player.teleport_to(Vector2(10000,10000) if mode=="2d" else Vector3(1000,0,1000)); manager.step(1,false)
		check(manager.service.result("player")["state"]=="cancelled" and manager.service.inventory["player"]["Coffee"]==1,"Walking away cancels unfinished service without an extra reward: "+mode)
		studio.set_walking(false); tools.show(); await settle()
		var path: String="res://output/business_"+mode+".isocity.json"
		check(studio.write_project(path),"Business configuration saves with the city: "+mode)
		var stored: Dictionary=studio.Store.read_json(path,{})["documents"][mode]
		check(stored["objects"][1]["business"]["capacity"]==1 and not stored.has("business_visits"),"Saves retain authored settings without transient visits or items: "+mode)
		var scene_path: String="res://output/business_play_"+mode+".tscn"
		check(preload("res://scripts/builder/exporter.gd").save_scene(studio.worlds[mode],doc.data,studio.library,scene_path)==OK,"Interactive business scenes export: "+mode)
		var viewport:=SubViewport.new(); viewport.size=Vector2i(640,480); viewport.own_world_3d=true; root.add_child(viewport)
		var exported: Node=load(scene_path).instantiate(); viewport.add_child(exported); await settle()
		var sim: Node=exported.businesses; sim.set_physics_process(false); exported.citizens.set_physics_process(false); exported.player.set_physics_process(false)
		exported.player.teleport_to(exported.exploration.entrance(exported.exploration.instances[uid]))
		check(sim.request_player(uid,"coffee")["ok"],"Actual exported scenes offer player business activities: "+mode)
		sim.step(6,false)
		check(sim.service.inventory["player"]["Coffee"]==1,"Business activities grant items in the actual exported scene: "+mode)
		viewport.free(); await settle()
		var portable: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(studio.worlds[mode],doc.data,studio.library,"res://output/business_"+mode+".zip")
		check(portable["ok"],"Interactive businesses export as portable Godot projects: "+mode)
		tools.kind.select(1); tools.opening.value=20; tools.closing.value=21; tools.apply_settings(); await settle(); manager.hour=12.5
		check(not manager.available(uid),"Authored opening hours close the real runtime business: "+mode)
		for frame in 10: citizens.step(1.0/60)
		check(citizens.residents.all(func(r: Dictionary):return r["target"]==r["home"]),"Residents return home instead of visiting a closed business: "+mode)
		studio.set_walking(true); player.teleport_to(walk.entrance(studio.worlds[mode].instances[uid]))
		var closed: Dictionary=manager.request_player(uid,"coffee")
		check(not closed["ok"] and "Closed" in closed["reason"],"A nearby player receives an actual closed-business explanation: "+mode)
		studio.set_walking(false)
		studio._command("undo",null); await settle()
		check(Plan.profile(doc.object(uid))["open_hour"]==0,"Business configuration uses normal Undo: "+mode)
		doc.object(uid)["locked"]=true; tools.kind.select(4); tools.apply_settings()
		check(Plan.profile(doc.object(uid))["kind"]=="cafe","Business editing respects protected selections: "+mode)
		doc.object(uid).erase("locked")
		for activity in [[2,"browse","Shopping bag"],[3,"counter","Service receipt"]]:
			studio.selected_uids.assign([uid]); studio.selected_uid=uid; tools.refresh_selection(); tools.kind.select(activity[0]); tools.opening.value=0; tools.closing.value=24; tools.apply_settings(); await settle()
			studio.set_walking(true); player.teleport_to(walk.entrance(studio.worlds[mode].instances[uid]))
			check(manager.request_player(uid,activity[1])["ok"],"Configured shop and service-counter activities are available during real exploration: "+mode+activity[1])
			manager.step(6,false)
			check(manager.service.inventory["player"].get(activity[2],0)==1,"Shop and service activities grant their own actual items: "+mode+activity[1])
			studio.set_walking(false); studio._command("undo",null); await settle()
		check(studio.load_project(path),"Saved interactive-business projects reopen: "+mode); await settle()
		check(manager.service.inventory.is_empty() and manager.service.visits.is_empty() and manager.service.businesses.has(uid),"Loading restores businesses and clears transient activity results: "+mode)
	studio.queue_free(); await process_frame
	print("BUSINESS RUNTIME: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
