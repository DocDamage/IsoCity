extends SceneTree
const Plan=preload("res://scripts/builder/service_plan.gd")
const Traffic=preload("res://scripts/builder/traffic_plan.gd")
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
func choose_target(tools: RefCounted,uid: String) -> void:
	tools.tick(.5)
	for index in tools.targets.item_count:
		if tools.targets.get_item_metadata(index)==uid: tools.targets.select(index); return
func complete(manager: Node,requests: Array) -> bool:
	for frame in 24000:
		manager.step(1.0/60)
		if requests.all(func(job: Dictionary):return job["state"] in ["complete","blocked","cancelled"]): break
	return requests.all(func(job: Dictionary):return job["state"]=="complete" and job["fulfilled"])
func run() -> void:
	root.size=Vector2i(1480,900)
	var studio: Control=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio); await settle()
	for mode in ["2d","3d"]:
		studio.switch_mode(mode)
		var doc: RefCounted=preload("res://scripts/builder/document.gd").new(); doc.data=preload("res://scripts/builder/templates.gd").make(mode,"blank"); doc.data["roads"]=[]
		for x in range(-8,9): doc.data["roads"].append({"cell":[x,0],"crossing":x==0})
		var desired: Dictionary={}; var station_ids: Dictionary={}
		for index in 4:
			var kind: String=Plan.KINDS[index]
			var item: Dictionary=doc.add("2d:Office_Tower" if mode=="2d" else "3d:HanX_City/Office_Tower",Traffic.world(Vector2(-48+index*32,-20),mode),"SE" if mode=="2d" else "0")
			item["name"]=kind.capitalize()+" station"; item["city_service"]={"kind":kind,"radius":256,"units":1,"task_seconds":2,"extension":"keep"}
			station_ids[kind]=item["uid"]; desired[item["uid"]]=Vector2(-48+index*32,-10)
		var target_ids: Array[String]=[]
		for index in 2:
			var item: Dictionary=doc.add("2d:House_Blue" if mode=="2d" else "3d:HanX_City/Row_Houses_A",Traffic.world(Vector2(index*32,10),mode),"SE" if mode=="2d" else "180")
			item["name"]="Home "+str(index+1); target_ids.append(item["uid"]); desired[item["uid"]]=Vector2(index*32,10)
		studio.documents[mode]=doc; studio.changed(); await settle()
		for item in doc.data["objects"]:
			var point: Variant=studio.worlds[mode].exploration.entrance(studio.worlds[mode].instances[item["uid"]])
			var actual: Vector2=Traffic.metric([point.x,point.y,0] if mode=="2d" else [point.x,point.y,point.z],mode)
			item["position"]=Traffic.world(Traffic.metric(item["position"],mode)+desired[item["uid"]]-actual,mode)
		studio.changed(); await settle()
		var tools: RefCounted=studio.service_tools; var manager: Node=tools.managers[mode]; manager.set_physics_process(false); tools.show()
		tools.enabled.button_pressed=true; tools.automatic.button_pressed=false; tools.interval.value=30; tools.seed.value=5; tools.apply_settings(); await settle()
		check(manager.dispatch.plan["stations"].size()==4 and manager.dispatch.plan["targets"].size()==2,"Inspector enables a live four-department neighborhood: "+mode)
		var history: int=doc.undo_history.size(); tools.apply_settings()
		check(doc.undo_history.size()==history,"Unchanged service settings create no undo entry: "+mode)
		studio.selected_uids.assign([station_ids["fire"]]); studio.selected_uid=station_ids["fire"]; tools.refresh_selection(); tools.kind.select(1); tools.units.value=2; tools.radius.value=256; tools.duration.value=2; tools.apply_station(); await settle()
		check(doc.object(station_ids["fire"])["city_service"]["units"]==2 and doc.object(station_ids["fire"])["city_service"]["extension"]=="keep","Station inspector applies capacity while preserving extensions: "+mode)
		studio._command("undo",null); await settle()
		check(Plan.profile(doc.object(station_ids["fire"]))["units"]==1,"Station settings use normal Undo: "+mode)
		tools.refresh_selection(); tools.kind.select(1); tools.units.value=2; tools.apply_station(); await settle()
		doc.object(station_ids["fire"])["locked"]=true; tools.kind.select(5); tools.apply_station()
		check(Plan.profile(doc.object(station_ids["fire"]))["kind"]=="fire","Protected stations cannot be reassigned: "+mode)
		doc.object(station_ids["fire"]).erase("locked")
		studio.selected_uids.assign([station_ids["fire"],station_ids["medical"]]); tools.refresh_selection(); history=doc.undo_history.size(); tools.apply_station()
		check(tools.kind.selected==6 and doc.undo_history.size()==history,"Mixed station selections require an explicit type before applying: "+mode)
		tools.request_kind.select(0); choose_target(tools,target_ids[0]); tools.request_visit(); var first: Dictionary=manager.dispatch.jobs.back()
		choose_target(tools,target_ids[1]); tools.request_visit(); var second: Dictionary=manager.dispatch.jobs.back()
		check(first["target"]==target_ids[0] and second["target"]==target_ids[1],"Inspector requests visits for the actual selected neighborhood targets: "+mode)
		manager.step(1.0/60)
		var time: float=manager.elapsed; var point: Vector2=manager.crews[first["id"]]["vehicle"]["point"]
		tools.paused.button_pressed=true; manager.step(.25)
		check(manager.elapsed==time and manager.crews[first["id"]]["vehicle"]["point"]==point,"Service pause freezes the clock and physical crew: "+mode)
		tools.paused.button_pressed=false
		studio.switch_mode("3d" if mode=="2d" else "2d"); await settle(); manager.step(.25)
		check(manager.elapsed==time and not manager.helper.container.visible,"Inactive workspaces suspend and hide their service fleet: "+mode)
		studio.switch_mode(mode); await settle()
		check(complete(manager,[first,second]),"Two crews share a station driveway and independently return from different sites: "+mode+str([first["reason"],second["reason"]]))
		check(manager.crews.size()<=2 and manager.vehicle_states().is_empty(),"Returned crews enter the depot instead of obstructing its driveway: "+mode)
		var fire: Dictionary=manager.dispatch.request("fire",target_ids[0])["job"]; var medical: Dictionary=manager.dispatch.request("medical",target_ids[0])["job"]
		manager.step(.25)
		check(manager.crews.size()<=3 and "clear the site" in medical["reason"],"Different departments serialize use of a target driveway: "+mode)
		check(complete(manager,[fire,medical]),"Different departments complete consecutive visits to the same site without a driveway deadlock: "+mode+str([fire["reason"],medical["reason"]]))
		var saved: String="res://output/services_"+mode+".isocity.json"
		check(studio.write_project(saved),"Service settings and stations save with the city: "+mode)
		var stored: Dictionary=studio.Store.read_json(saved,{})["documents"][mode]
		check(stored["objects"].size()==6 and stored["services"]["enabled"] and not stored.has("service_jobs"),"Saves contain authored settings without transient requests or crew actors: "+mode)
		var walk: Node=studio.worlds[mode].exploration; var player: Node=studio.worlds[mode].player
		studio.set_walking(true); player.set_physics_process(false); player.teleport_to(walk.entrance(studio.worlds[mode].instances[target_ids[0]])); await settle()
		manager.request_kind="fire"; studio.control_settings.execute("service_type"); manager.update_ui()
		check(manager.request_kind=="medical" and manager.panel.visible,"Walking shortcut cycles the live nearby-service request panel: "+mode)
		studio.control_settings.execute("service_request"); var watched: Dictionary=manager.dispatch.jobs.back()
		check(watched["kind"]=="medical" and watched["target"]==target_ids[0],"Walking shortcut requests service for the actual nearby building: "+mode)
		var count: int=manager.dispatch.jobs.size()
		var pointer:=InputEventMouseMotion.new(); pointer.position=studio.canvas.get_global_rect().position+manager.request_button.get_global_rect().get_center(); root.push_input(pointer,true)
		var click:=InputEventMouseButton.new(); click.button_index=MOUSE_BUTTON_LEFT; click.pressed=true; click.position=pointer.position; root.push_input(click,true); click=click.duplicate(); click.pressed=false; root.push_input(click,true)
		check(manager.dispatch.jobs.size()==count and "requested" in manager.message,"Native request buttons accept mouse input and avoid duplicate calls: "+mode)
		studio.accessibility_settings.text_scale=1.5; studio.accessibility_settings.large_targets=true; studio.accessibility_settings.high_contrast=true; tools.tick(.5); manager.update_ui()
		check(manager.request_button.custom_minimum_size.y==44 and manager.request_button.get_theme_font_size("font_size")==21 and manager.panel.get_theme_stylebox("panel").border_width_left==2 and manager.panel.get_rect().end.x<=manager.get_viewport().get_visible_rect().size.x,"Service request HUD follows enlarged text, targets and contrast within its viewport: "+mode)
		studio.accessibility_settings.text_scale=1; studio.accessibility_settings.large_targets=false; studio.accessibility_settings.high_contrast=false; tools.tick(.5); manager.update_ui()
		await capture("services_request_"+mode)
		check(complete(manager,[watched]),"A crew can approach and serve while the player watches near the entrance: "+mode+watched["reason"])
		var obstacles: Array=manager.helper.obstacles.duplicate()
		var pending: Dictionary=manager.dispatch.request("police",target_ids[0])["job"]; manager.step(1.0/60)
		time=manager.elapsed; point=manager.crews[pending["id"]]["vehicle"]["point"]
		walk.interact(); await settle(); manager.step(.25)
		check(walk.interior!=null and manager.elapsed==time and manager.crews[pending["id"]]["vehicle"]["point"]==point,"Interior visits suspend service movement without teleporting crews: "+mode)
		check(manager.helper.obstacles==obstacles and tools.dirty,"Exterior collision snapshots remain intact while interior rendering suspends the exterior: "+mode)
		walk.leave_interior(); await settle()
		check(manager.helper.obstacles==obstacles and manager.crews.has(pending["id"]),"Returning outside restores the same obstacles and existing crew: "+mode)
		studio.set_walking(false); tools.show(); await settle()
		manager.reset(); tools.dirty=true; tools.tick(.5); await settle()
		check(manager.dispatch.jobs.is_empty() and manager.crews.is_empty(),"Restart clears transient service journeys: "+mode)
		tools.automatic.button_pressed=true; tools.apply_settings(); await settle(); manager.step(1.0/60)
		check(not manager.dispatch.jobs.is_empty(),"Automatic service visits generate a reachable seeded request: "+mode)
		tools.enabled.button_pressed=false; tools.apply_settings(); await settle()
		check(manager.crews.is_empty() and manager.helper.container==null and manager.dispatch.jobs.is_empty(),"Disabling services removes all transient crews and requests: "+mode)
		check(studio.load_project(saved),"Service-enabled projects reopen: "+mode); await settle(); doc=studio.current()
		check(manager.dispatch.plan["stations"].size()==4 and manager.crews.is_empty() and manager.dispatch.history.is_empty(),"Loading restores stations and clears live service results and positions: "+mode)
		var scene_path: String="res://output/services_play_"+mode+".tscn"
		check(preload("res://scripts/builder/exporter.gd").save_scene(studio.worlds[mode],doc.data,studio.library,scene_path)==OK,"Runnable service-enabled scenes export: "+mode)
		var viewport:=SubViewport.new(); viewport.size=Vector2i(640,480); viewport.own_world_3d=true; root.add_child(viewport)
		var exported: Node=load(scene_path).instantiate(); viewport.add_child(exported); await settle()
		exported.services.set_physics_process(false); exported.traffic.set_physics_process(false); exported.player.set_physics_process(false)
		exported.player.teleport_to(exported.exploration.entrance(exported.exploration.instances[target_ids[0]]))
		await settle()
		var key:=InputEventKey.new(); key.keycode=KEY_V; key.pressed=true; exported._unhandled_input(key)
		var exported_job: Dictionary=exported.services.dispatch.jobs.back()
		var export_ok: bool=complete(exported.services,[exported_job])
		check(export_ok,"Actual exported scenes accept exploration requests and complete physical service trips: "+mode+exported_job["reason"])
		viewport.free(); await settle()
		var portable: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(studio.worlds[mode],doc.data,studio.library,"res://output/services_"+mode+".zip")
		check(portable["ok"],"Four-department city services package as portable Godot projects: "+mode)
		var editing: Dictionary=manager.dispatch.request("fire",target_ids[0])["job"]; manager.step(.25)
		var actor: Node=manager.crews[editing["id"]]["vehicle"]["actor"]; var actor_id: int=actor.get_instance_id(); point=manager.crews[editing["id"]]["vehicle"]["point"]
		doc.object(station_ids["fire"])["name"]="Renamed fire station"; studio.changed(); await settle()
		check(manager.crews[editing["id"]]["vehicle"]["actor"].get_instance_id()==actor_id and manager.crews[editing["id"]]["vehicle"]["point"]==point and editing["state"]=="outbound","Ordinary city edits retain the current service vehicle and journey: "+mode)
		var removed: String=editing["route"][0]
		doc.data["roads"]=doc.data["roads"].filter(func(road: Dictionary):return preload("res://scripts/builder/roads.gd").key(Vector2i(road["cell"][0],road["cell"][1]))!=removed)
		studio.changed(); await settle(); manager.step(.25)
		check(editing["state"]=="blocked" and not editing["fulfilled"] and manager.crews[editing["id"]]["vehicle"]["point"]==point,"Editing an assigned road pauses its actual vehicle without teleporting or falsely fulfilling the visit: "+mode)
		check(studio.load_project(saved),"The saved service layout restores after road-edit testing: "+mode); await settle()
	root.size=Vector2i(960,640); studio.service_tools.show(); studio.service_tools.tick(.5); await settle()
	check(studio.service_tools.panel.get_child(0).size.x<=studio.service_tools.panel.size.x,"City service controls fit their scrolling inspector at 960×640")
	await capture("services_small_window")
	studio.queue_free(); await process_frame
	print("SERVICE WORKFLOW: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
