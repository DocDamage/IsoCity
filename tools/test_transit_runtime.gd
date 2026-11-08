extends SceneTree
const Runtime=preload("res://scripts/builder/transit_runtime.gd")
const Plan=preload("res://scripts/builder/transit_plan.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for frame in 5: await process_frame
	await physics_frame
func capture(world: Node,entry: Dictionary,name: String,mode: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	if mode=="2d": world.camera.position=entry["vehicle"]["actor"].position; world.camera.zoom=Vector2.ONE*2
	else: world.target=entry["vehicle"]["actor"].position; world.distance=25; world.yaw=225; world.update_camera()
	await settle(); await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://output/"+name+".png")
func run() -> void:
	var studio: Control=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio); await settle()
	root.size=Vector2i(1480,900)
	# This probe drives its own runtime; the normal Studio fleet is covered by
	# test_transit_workflow and must not create a second fleet in the same view.
	for manager in studio.transit_tools.managers.values(): manager.set_physics_process(false); manager.reset()
	for mode in ["2d","3d"]:
		studio.switch_mode(mode)
		var doc=preload("res://scripts/builder/document.gd").new(); doc.data=preload("res://scripts/builder/templates.gd").make(mode,"blank"); doc.data["objects"]=[]; doc.data["roads"]=[]
		for x in range(-4,13): doc.data["roads"].append({"cell":[x,0]})
		for index in 2:
			var asset: String="2d:Bus_Stop_Sign" if mode=="2d" else "3d:HanX_Traffic/Bus_Stop"
			var item: Dictionary=doc.add(asset,Plan.Traffic.world(Plan.Traffic.center(Vector2i(index*8,0),mode)+Vector2(0,8),mode),studio.library.directions(asset)[0]); item["uid"]="stop_"+str(index)
		doc.data["transit"]={"enabled":true,"automatic":false}; doc.data["transit_lines"]=[{"uid":"connector","stops":["stop_0","stop_1"],"headway":180,"capacity":2}]
		studio.documents[mode]=doc; studio.changed(); await settle()
		var world: Node=studio.worlds[mode]
		var runtime=Runtime.new(); studio.add_child(runtime); runtime.set_physics_process(false)
		runtime.configure(doc.data,studio.library,world.instances,world.objects)
		check(runtime.passengers.plan["lines"].size()==1,"Actual stop collision geometry compiles a route: "+mode+str(runtime.passengers.plan["notices"]))
		if runtime.passengers.plan["lines"].is_empty(): runtime.free(); continue
		var before: Dictionary=doc.data.duplicate(true)
		var a: Dictionary=runtime.passengers.plan["stops"]["stop_0"]; var b: Dictionary=runtime.passengers.plan["stops"]["stop_1"]
		var static_boxes: Array[Rect2]=runtime.helper.obstacles.duplicate()
		runtime.helper.obstacles.append(Rect2(a["dock"]+a["axis"]*.9-Vector2.ONE*.05,Vector2.ONE*.1))
		check(not runtime.vehicle_clear(a["dock"],a["axis"]),"Bus footprint detects thin obstacles between its corners: "+mode)
		runtime.helper.obstacles=static_boxes
		var result: Dictionary=runtime.request(a["platform"]+a["right"]*2,b["platform"]+b["right"]*2)
		check(result["ok"],"A passenger requests a real walking and riding journey: "+mode+str(result))
		if not result["ok"]: runtime.free(); continue
		await settle()
		var job: Dictionary=result["job"]; var phases: Dictionary={}; var moved: bool=false; var start: Vector2=a["dock"]; var tested_clearance: bool=false; var captured: bool=false
		for frame in 15000:
			runtime.step(1.0/60); phases[job["state"]]=true
			if not runtime.buses.is_empty() and runtime.buses.values()[0]["vehicle"]["point"].distance_to(start)>10: moved=true
			if moved and not tested_clearance and runtime.buses.values()[0]["status"]=="Driving":
				tested_clearance=true
				var bus: Dictionary=runtime.buses.values()[0]["vehicle"]; var point: Vector2=bus["point"]
				var shared=preload("res://scripts/builder/traffic_runtime.gd").new(); studio.add_child(shared); shared.set_physics_process(false); shared.plan={"settings":{"enabled":false}}
				runtime.traffic=shared; shared.vehicles.append({"id":"probe_car","point":point+bus["heading"]*2.4})
				runtime.step(.25); check(bus["point"].distance_to(point)<.001,"Bus yields to an actual shared traffic state ahead of its nose: "+mode)
				shared.vehicles.clear()
				var person: Node=Node2D.new() if mode=="2d" else Node3D.new(); world.objects.add_child(person)
				var raw: Array=Plan.Traffic.world(point+bus["heading"]*2.6,mode)
				person.position=Vector2(raw[0],raw[1]) if mode=="2d" else Vector3(raw[0],0,raw[2]); shared.pedestrians.append(person)
				runtime.step(.25); check(bus["point"].distance_to(point)<.001,"Bus yields to a visible pedestrian ahead: "+mode)
				person.free(); shared.pedestrians.clear(); runtime.traffic=null; shared.free()
				var car: Dictionary={"id":"following_car","point":point-bus["heading"]*2.8}
				runtime.helper.external_vehicles.assign([bus])
				var nobody: Array[Vector2]=[]
				check(runtime.helper.obstructed(car,car["point"],bus["heading"],nobody)=="Waiting for bus clearance","Following cars respect the bus's full rear extent: "+mode)
			if job["state"]=="onboard" and moved and not captured:
				captured=true; await capture(world,runtime.buses.values()[0],"transit_bus_"+mode,mode)
			if job["state"] in ["complete","blocked","cancelled"]: break
		check(job["state"]=="complete","Actual passenger reaches the destination after riding: "+mode+str(job["state"])+str(job["reason"])+str(runtime.buses.values().map(func(entry: Dictionary):return [entry["status"],entry["vehicle"]["point"],entry["segment"]])))
		check(moved and phases.has("boarding") and phases.has("onboard") and phases.has("alighting"),"Real bus movement and every boarding/riding/alighting phase were observed: "+mode+str(phases))
		check(not runtime.buses.values()[0]["label"].text.is_empty() and runtime.buses.values()[0]["label"].modulate==Color("77b8ff"),"Buses show their route name and authored line color: "+mode)
		runtime.set_text_scale(1.5)
		check(runtime.buses.values()[0]["label"].get_theme_font_size("font_size")==15 if mode=="2d" else runtime.buses.values()[0]["label"].font_size==42,"Bus annotations support scaled text: "+mode); runtime.set_text_scale(1)
		check(runtime.passengers.completed==1 and runtime.actor_point(runtime.walkers[job["id"]]["actor"]).distance_to(b["platform"]+b["right"]*2)<1.2,"Completion requires physical final destination arrival: "+mode)
		check(doc.data==before,"Live transit never edits the authored document: "+mode)
		var time: float=runtime.elapsed; var position: Vector2=runtime.buses.values()[0]["vehicle"]["point"]
		runtime.paused=true; runtime.step(.25); runtime.paused=false; runtime.active=false; runtime.step(.25); runtime.active=true
		check(runtime.elapsed==time and runtime.buses.values()[0]["vehicle"]["point"]==position,"Pause and inactive world freeze buses, passengers and the transit clock: "+mode)
		var actor: Node=runtime.buses.values()[0]["vehicle"]["actor"]
		var renamed: Dictionary=doc.data.duplicate(true); renamed["transit_lines"][0]["name"]="Renamed shuttle"; renamed["transit_lines"][0]["color"]="e8ac42"; renamed["transit"]["seed"]=8
		runtime.configure(renamed,studio.library,world.instances,world.objects)
		check(runtime.buses.values()[0]["label"].text=="Renamed shuttle" and runtime.buses.values()[0]["label"].modulate==Color("e8ac42") and runtime.buses.values()[0]["vehicle"]["actor"]==actor,"Renaming or recoloring a route updates annotations while retaining the bus: "+mode)
		check(runtime.random.seed==8,"Applying a new passenger seed reseeds future requests: "+mode)
		runtime.configure(doc.data,studio.library,world.instances,world.objects)
		check(runtime.buses.values()[0]["vehicle"]["actor"]==actor,"Unchanged city configuration retains bus actors: "+mode)
		check(runtime.supported_path(PackedVector2Array([Vector2(128,8)]))==(mode=="2d"),"Model walking connections require an actual supporting surface: "+mode)
		runtime.reset(); check(runtime.buses.is_empty() and runtime.walkers.is_empty() and not is_instance_valid(actor),"Restart frees bus and passenger actors: "+mode)
		for x in range(-12,-4): doc.data["roads"].append({"cell":[x,0]})
		var third: Dictionary=doc.add("2d:Bus_Stop_Sign" if mode=="2d" else "3d:HanX_Traffic/Bus_Stop",Plan.Traffic.world(Plan.Traffic.center(Vector2i(-8,0),mode)+Vector2(0,8),mode),studio.library.directions(doc.data["objects"][0]["asset"])[0]); third["uid"]="stop_2"
		doc.data["transit_lines"].append({"uid":"second","stops":["stop_1","stop_2"],"headway":180,"offset":30})
		studio.changed(); await settle(); runtime.configure(doc.data,studio.library,world.instances,world.objects)
		var plan: Dictionary=runtime.passengers.plan
		result=runtime.request(plan["stops"]["stop_0"]["platform"]+Vector2(0,2),plan["stops"]["stop_2"]["platform"]+Vector2(0,2))
		check(result["ok"] and result["job"]["legs"].size()==4,"Actual district journey plans a two-bus transfer: "+mode)
		if result["ok"]:
			job=result["job"]; var boarded: Dictionary={}; var changed_bus: bool=false; var capture_transfer: bool=false
			for frame in 30000:
				runtime.step(1.0/60)
				if job["state"]=="onboard": boarded[job["vehicle"]]=true
				if job["index"]==2 and job["state"]=="onboard":
					changed_bus=runtime.passengers.vehicles.values().all(func(bus: Dictionary):return bus["id"]==job["vehicle"] or not job["id"] in bus["manifest"])
				if job["state"]=="alighting" and not capture_transfer:
					capture_transfer=true; runtime.step(1.0/60); await capture(world,runtime.buses[job["vehicle"]],"transit_transfer_"+mode,mode)
				if job["state"] in ["complete","blocked","cancelled"]: break
			check(job["state"]=="complete" and boarded.size()==2 and changed_bus,"Passenger physically alights, transfers onto a different bus, and completes the destination walk: "+mode+str(job["reason"])+str(boarded)+str([runtime.actor_point(runtime.walkers[job["id"]]["actor"]),runtime.walkers[job["id"]]["path"],plan["stops"]["stop_2"]["platform"],job["state"],runtime.walkers[job["id"]]["index"]]))
			check(runtime.passengers.vehicles.values().all(func(bus: Dictionary):return bus["manifest"].is_empty() and bus["reserved"].is_empty()),"Both vehicles release seats after the completed transfer: "+mode)
		doc.data["transit"]["automatic"]=true; doc.data["transit"]["population"]=1; doc.data["transit"]["interval"]=5
		runtime.configure(doc.data,studio.library,world.instances,world.objects); runtime.auto_time=0
		for frame in 40: runtime.step(.25)
		check(runtime.passengers.jobs.filter(func(value: Dictionary):return not value["state"] in ["complete","cancelled"]).size()==1,"Automatic journeys respect the configured active passenger limit: "+mode)
		check(not runtime.request(plan["stops"]["stop_0"]["platform"],plan["stops"]["stop_1"]["platform"])["ok"],"Manual requests also respect the configured passenger limit: "+mode)
		var active_vehicle: Dictionary=runtime.buses.values()[0]["vehicle"]
		var active_actor: Node=active_vehicle["actor"]
		var active_point: Vector2=active_vehicle["point"]
		doc.data["roads"][8]["width"]=2; runtime.configure(doc.data,studio.library,world.instances,world.objects)
		var no_jump: bool=active_vehicle["point"]==active_point
		for frame in 1200:
			var last: Vector2=active_vehicle["point"]
			runtime.step(1.0/60)
			no_jump=no_jump and active_vehicle["point"].distance_to(last)<.16
			if runtime.passengers.vehicles.values().all(func(bus: Dictionary):return bus["phase"]=="blocked"): break
		check(no_jump and runtime.buses.values()[0]["vehicle"]["actor"]==active_actor and runtime.passengers.vehicles.values().all(func(bus: Dictionary):return bus["phase"]=="blocked"),"A narrowed road lets existing buses finish a safe segment and wait without replacing actors: "+mode)
		runtime.free()
	studio.free(); print("TRANSIT RUNTIME: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
