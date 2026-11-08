extends SceneTree
const Runtime=preload("res://scripts/builder/traffic_runtime.gd")
const Plan=preload("res://scripts/builder/traffic_plan.gd")
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
		doc.data["roads"]=[]
		for x in range(-3,4): doc.data["roads"].append({"cell":[x,0],"crossing":x==2})
		for y in [-2,-1,1,2]: doc.data["roads"].append({"cell":[0,y],"crossing":false})
		var asset: String="2d:Parking_Accessible" if mode=="2d" else "3d:HanX_Traffic/Road_Parking"
		var size: float=2 if mode=="2d" else .5
		var point: Vector2=Plan.center(Vector2i(1,0),mode)+Vector2(0,5.5)
		var correction: Vector2=preload("res://scripts/builder/roads.gd").center_offset(studio.library,asset,"SE" if mode=="2d" else "0",size,mode)*(2 if mode=="2d" else 1)
		var item: Dictionary=doc.add(asset,Plan.world(point-correction,mode),"SE" if mode=="2d" else "0")
		item["scale"]=size; item["traffic_parking"]=true
		doc.data["traffic"]={"enabled":true,"population":3,"seed":8,"speed":4,"parking_seconds":2}
		studio.documents[mode]=doc; studio.changed(); await settle()
		var tools: RefCounted=studio.traffic_tools; tools.show()
		await settle()
		var manager: Node=tools.managers[mode]; manager.set_physics_process(false)
		check(manager.vehicles.size()==3,"Configured live vehicle actors spawn on distinct lane positions: "+mode)
		check(manager.bays.size()==1,"A marked nearby parking surface produces one usable space: "+mode)
		var before: Dictionary=doc.data.duplicate(true); var history: int=doc.undo_history.size()
		var start: Vector2=manager.vehicles[0]["point"]
		var parked: bool=false; var exited: bool=false; var stopped: bool=false; var separated: bool=true
		if mode=="2d": studio.worlds[mode].camera.position=Vector2.ZERO; studio.worlds[mode].camera.zoom=Vector2.ONE*1.5
		else: studio.worlds[mode].target=Vector3.ZERO; studio.worlds[mode].distance=43; studio.worlds[mode].update_camera()
		var ids: Array=[]
		for vehicle in manager.vehicles: ids.append(vehicle["actor"].get_instance_id())
		for frame in 18000:
			manager.step(1.0/60)
			for a in manager.vehicles.size():
				for b in range(a+1,manager.vehicles.size()):
					if manager.vehicles[a]["point"].distance_to(manager.vehicles[b]["point"])<.89: separated=false
			if not parked and manager.vehicles.any(func(v: Dictionary):return v["phase"]=="parked"):
				parked=true; tools.tick(.5); await capture("traffic_parked_"+mode)
				var visitor: Dictionary=manager.vehicles.filter(func(v: Dictionary):return v["phase"]=="parked")[0]
				check(visitor["point"].distance_to(manager.bays[visitor["bay"]]["point"])<.01 and manager.bay_owners.get(visitor["bay"])==visitor["id"],"Parking arrival reaches the actual bay and retains exclusive ownership: "+mode)
			if manager.vehicles.any(func(v: Dictionary):return not v["visits"].is_empty() and v["phase"]=="edge" and v["bay"].is_empty()): exited=true
			if manager.vehicles.any(func(v: Dictionary):return v["stops"]>0): stopped=true
			if frame==500: tools.tick(.5); await capture("traffic_runtime_"+mode)
			if parked and exited and stopped: break
		check(manager.vehicles[0]["point"].distance_to(start)>1,"Actors physically move along the road network: "+mode)
		check(manager.vehicles.any(func(v: Dictionary):return v["sections"].size()>2),"Live vehicles traverse connected sections and turns: "+mode)
		check(stopped,"Live vehicles observe intersection and crossing stops: "+mode)
		check(parked,"A live vehicle enters and occupies a reserved parking space: "+mode+str(manager.vehicles.map(func(v: Dictionary):return [v["phase"],v["status"],v["bay"],v["from"],v["to"]])))
		check(exited,"Parked vehicles physically leave and rejoin the road: "+mode)
		check(separated,"Vehicle clearance checks prevent body-center overlaps throughout live journeys: "+mode)
		check(doc.data==before and doc.undo_history.size()==history,"Traffic movement does not edit the document or undo history: "+mode)
		var time: float=manager.elapsed; var position: Vector2=manager.vehicles[0]["point"]
		manager.paused=true; manager.step(4)
		check(manager.elapsed==time and manager.vehicles[0]["point"]==position,"Pause freezes traffic and its simulation clock: "+mode)
		manager.paused=false
		var original_history: int=doc.undo_history.size(); tools.apply_settings()
		check(doc.undo_history.size()==original_history,"Applying unchanged traffic settings creates no undo entry: "+mode)
		studio.selected_uids.assign([item["uid"]]); studio.selected_uid=item["uid"]
		tools.mark_parking(false); await settle()
		check(not doc.object(item["uid"]).has("traffic_parking"),"The inspector removes selected parking designations: "+mode)
		studio._command("undo",null); await settle()
		check(doc.object(item["uid"])["traffic_parking"],"Parking designation uses normal Undo: "+mode)
		item=doc.object(item["uid"]); item["locked"]=true; tools.mark_parking(false)
		check(item["traffic_parking"],"Protected selections cannot be reassigned as parking: "+mode)
		item.erase("locked")
		tools.seed.value=19; tools.apply_settings(); await settle()
		check(doc.data["traffic"]["seed"]==19,"The inspector applies traffic simulation settings: "+mode)
		studio._command("undo",null); await settle()
		check(doc.data["traffic"]["seed"]==8,"Traffic simulation settings use normal Undo: "+mode)
		tools.add_parking(); await settle()
		check(doc.data["objects"].size()==2 and doc.object(studio.selected_uid).get("traffic_parking",false),"The inspector creates a selectable roadside parking surface through the normal editor: "+mode)
		studio._command("undo",null); await settle()
		check(doc.data["objects"].size()==1,"Adding a parking surface is one undoable edit: "+mode)
		ids.clear()
		for v in manager.vehicles: ids.append(v["actor"].get_instance_id())
		var path: String="res://output/traffic_"+mode+".isocity.json"
		check(studio.write_project(path),"Traffic settings and marked parking save normally: "+mode)
		var stored: Dictionary=studio.Store.read_json(path,{})["documents"][mode]
		check(stored["objects"].size()==1 and stored["objects"][0]["traffic_parking"] and stored["traffic"]["population"]==3,"Saved projects contain settings and spaces without transient cars: "+mode)
		var scene_path: String="res://output/traffic_play_"+mode+".tscn"
		check(preload("res://scripts/builder/exporter.gd").save_scene(studio.worlds[mode],doc.data,studio.library,scene_path)==OK,"A runnable traffic scene exports: "+mode)
		var viewport:=SubViewport.new(); viewport.size=Vector2i(640,480); viewport.own_world_3d=true; root.add_child(viewport)
		var exported: Node=load(scene_path).instantiate(); viewport.add_child(exported); await settle()
		var sim: Node=exported.traffic; sim.set_physics_process(false); sim.pedestrians.clear()
		var parked_export: bool=false; var exited_export: bool=false
		for frame in 18000:
			sim.step(1.0/60)
			if sim.vehicles.any(func(v: Dictionary):return v["phase"]=="parked"): parked_export=true
			if sim.vehicles.any(func(v: Dictionary):return not v["visits"].is_empty() and v["phase"]=="edge" and v["bay"].is_empty()): exited_export=true
			if parked_export and exited_export: break
		check(sim.vehicles.size()==3 and parked_export and exited_export,"Actual exported scenes drive, park and rejoin traffic: "+mode)
		viewport.free(); await settle()
		var portable: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(studio.worlds[mode],doc.data,studio.library,"res://output/traffic_"+mode+".zip")
		check(portable["ok"],"Traffic exports as a portable Godot project: "+mode)
		var zip:=ZIPReader.new(); zip.open("res://output/traffic_"+mode+".zip")
		check(zip.file_exists("scripts/builder/traffic_runtime.gd") and zip.file_exists("scenes/items/Vehicles/Sedan_Blue.tscn" if mode=="2d" else "scenes/items_3d/HanX_Traffic/Car_Sedan.tscn"),"Portable projects include runtime and otherwise unplaced vehicle dependencies: "+mode)
		zip.close()
		doc.data["objects"][0]["name"]="Renamed parking surface"; manager.configure(doc.data,studio.library,studio.worlds[mode].instances,studio.worlds[mode].objects)
		check(manager.vehicles[0]["actor"].get_instance_id()==ids[0],"Ordinary edits preserve existing vehicle actors: "+mode)
		check(manager.vehicles.all(func(v: Dictionary):return v["phase"]!="blocked"),"Renaming parking surfaces preserves the ongoing journeys: "+mode)
		var vehicle: Dictionary=manager.vehicles[0]
		var person: Node=CharacterBody2D.new() if mode=="2d" else CharacterBody3D.new()
		studio.worlds[mode].objects.add_child(person)
		var next: Vector2=vehicle["point"]+vehicle["heading"]*.5
		var location: Array=Plan.world(next,mode)
		person.position=Vector2(location[0],location[1]) if mode=="2d" else Vector3(location[0],0,location[2])
		manager.pedestrians.assign([person])
		check(manager.obstructed(vehicle,vehicle["point"],vehicle["heading"],manager.pedestrian_points())=="Yielding to pedestrian","Real pedestrian positions stop traffic in its path: "+mode)
		person.free(); manager.pedestrians.clear()
		var removed: String=vehicle["from"]
		doc.data["roads"]=doc.data["roads"].filter(func(entry: Dictionary):return preload("res://scripts/builder/roads.gd").key(Vector2i(entry["cell"][0],entry["cell"][1]))!=removed)
		position=vehicle["point"]; manager.configure(doc.data,studio.library,studio.worlds[mode].instances,studio.worlds[mode].objects); manager.step(1)
		check(vehicle["phase"]=="blocked" and vehicle["point"]==position,"Removing an occupied road pauses the vehicle without teleporting it: "+mode)
		check(studio.load_project(path),"Saved traffic projects reopen: "+mode); await settle(); doc=studio.current()
		check(manager.vehicles.size()==3 and manager.elapsed<.5 and manager.bays.size()==1,"Loading restores configuration and restarts transient traffic: "+mode)
		var moving: Dictionary=manager.vehicles[0]
		var held_position: Vector2=moving["point"]
		var follower: Dictionary=manager.vehicles[1]
		var original_point: Vector2=follower["point"]
		follower["point"]=moving["point"]+moving["heading"]*2
		var no_people: Array[Vector2]=[]
		check(manager.obstructed(moving,moving["point"],moving["heading"],no_people)=="Following traffic","A vehicle holds a following gap behind traffic ahead: "+mode)
		follower["point"]=original_point
		manager.active=false; manager.step(.1)
		check(moving["point"]==held_position,"Inactive workspaces do not advance traffic: "+mode); manager.active=true
		var marked: Dictionary=doc.data["objects"][0]
		marked["position"][2 if mode=="2d" else 1]=4
		manager.configure(doc.data,studio.library,studio.worlds[mode].instances,studio.worlds[mode].objects)
		check(manager.bays.is_empty() and "level ground" in " ".join(manager.plan["notices"]),"Elevated parking spaces are rejected with an explanation: "+mode)
		doc.data["traffic"]["enabled"]=false; manager.configure(doc.data,studio.library,studio.worlds[mode].instances,studio.worlds[mode].objects)
		check(manager.vehicles.is_empty() and manager.container==null,"Disabling traffic removes transient actors and reservations: "+mode)
	root.size=Vector2i(960,640); studio.traffic_tools.show(); studio.traffic_tools.tick(.5); await settle()
	check(studio.traffic_tools.panel.size.x<=root.size.x and studio.traffic_tools.panel.get_child(0).size.x<=studio.traffic_tools.panel.size.x,"Traffic controls fit inside the scrollable inspector in a small window")
	await capture("traffic_small_window")
	var repair=preload("res://scripts/builder/project_repair.gd").new(studio.library)
	var damaged: Dictionary=studio.session_data().duplicate(true)
	damaged["documents"]["2d"]["traffic"]={"enabled":"yes","population":999,"speed":-4,"extension":"preserved"}
	damaged["documents"]["2d"]["objects"][0]["traffic_parking"]=5
	var fixed: Dictionary=repair.session(damaged)
	check(fixed["ok"] and fixed["changed"],"Damaged traffic settings and parking flags are repairable")
	var repaired: Dictionary=fixed["content"]["documents"]["2d"]
	check(Plan.valid_settings(repaired["traffic"]) and repaired["traffic"]["extension"]=="preserved" and repaired["objects"][0]["traffic_parking"]==false,"Repair preserves extensions and disables malformed parking designations")
	studio.queue_free(); await process_frame
	print("TRAFFIC RUNTIME: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
