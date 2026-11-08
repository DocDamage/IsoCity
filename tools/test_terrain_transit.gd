extends SceneTree
const Plan=preload("res://scripts/builder/transit_plan.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for frame in 6: await process_frame
	await physics_frame
func run() -> void:
	root.size=Vector2i(1480,900)
	var studio: Control=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio); await settle()
	for mode in ["2d","3d"]:
		studio.switch_mode(mode)
		for height in [2.0,-2.0]:
			var doc=preload("res://scripts/builder/document.gd").new(); doc.data=preload("res://scripts/builder/templates.gd").make(mode,"blank"); doc.data["objects"]=[]; doc.data["roads"]=[]; doc.data["terrain"]={"enabled":true,"bounds":[-20,-20,80,40]}; doc.data["terrain_vertices"]=[]; doc.data["water_cells"]=[]
			for x in range(-20,61):
				for z in range(-20,21): doc.data["terrain_vertices"].append({"cell":[x,z],"height":height})
			for x in range(-4,13): doc.data["roads"].append({"cell":[x,0]})
			for index in 2:
				var asset: String="2d:Bus_Stop_Sign" if mode=="2d" else "3d:HanX_Traffic/Bus_Stop"; var item: Dictionary=doc.add(asset,Plan.Traffic.world(Plan.Traffic.center(Vector2i(index*8,0),mode)+Vector2(0,8),mode,0 if mode=="2d" else height),studio.library.directions(asset)[0]); item["uid"]="stop_"+str(index)
			doc.data["transit"]={"enabled":true,"automatic":false}; doc.data["transit_lines"]=[{"uid":"connector","stops":["stop_0","stop_1"],"headway":180,"capacity":2}]
			studio.documents[mode]=doc; studio.changed(); await settle(); var world: Node=studio.worlds[mode]; var runtime: Node=studio.transit_tools.managers[mode]; runtime.set_physics_process(false); runtime.reset(); runtime.configure(doc.data,studio.library,world.instances,world.objects); studio.transit_tools.dirty=false
			var context: String=mode+" / height "+str(height); check(runtime.passengers.plan["lines"].size()==1,"Supported raised/depressed stops compile a real transit line: "+context)
			if runtime.passengers.plan["lines"].is_empty(): continue
			var a: Dictionary=runtime.passengers.plan["stops"]["stop_0"]; var b: Dictionary=runtime.passengers.plan["stops"]["stop_1"]; var before: Dictionary=doc.data.duplicate(true)
			check(absf(a["height"]-height)<.001 and runtime.supported_path(PackedVector2Array([a["platform"],a["platform"]+a["right"]*2])),"Platform and physical walking support use local ground height: "+context)
			var request: Dictionary=runtime.request(a["platform"]+a["right"]*2,b["platform"]+b["right"]*2); check(request["ok"],"Passengers can request terrain transit journeys: "+context)
			if not request["ok"]: continue
			var job: Dictionary=request["job"]; var phases: Dictionary={}; var supported: bool=true; var moved: bool=false; var origin: Vector2=a["dock"]; var captured: bool=false
			for frame in 15000:
				await physics_frame; runtime.step(1.0/60); phases[job["state"]]=true
				if not runtime.buses.is_empty(): moved=moved or runtime.buses.values()[0]["vehicle"]["point"].distance_to(origin)>10
				if runtime.walkers.has(job["id"]) and runtime.walkers[job["id"]]["actor"].visible:
					var actor: Node=runtime.walkers[job["id"]]["actor"]
					if mode=="3d": supported=supported and absf(actor.position.y-height)<.5
					else: world.terrain_presentation.refresh(); supported=supported and absf(float(actor.get_meta("terrain_height",0))-height)<.001
				if job["state"] in ["complete","blocked","cancelled"]: break
				if job["state"]=="boarding" and height==2 and not captured and "--capture" in OS.get_cmdline_user_args():
					captured=true; studio.transit_tools.show(); var bus: Node=runtime.buses.values()[0]["vehicle"]["actor"]
					if mode=="3d": world.target=bus.position; world.distance=22; world.yaw=225; world.update_camera()
					else: world.camera.position=bus.position-Vector2(0,height*8); world.camera.zoom=Vector2.ONE*2
					await settle(); RenderingServer.force_draw(false); RenderingServer.force_draw(false); root.get_texture().get_image().save_png("res://output/terrain_transit_"+mode+".png")
			check(job["state"]=="complete" and moved,"Actual buses carry passengers to the destination: "+context+" / "+job["reason"])
			check(runtime.walkers[job["id"]]["actor"].recovery_count==0,"Terrain journeys complete without recovery teleportation: "+context)
			check(phases.has_all(["walking","waiting","boarding","onboard","alighting","complete"]) and supported,"Walking, boarding, riding and alighting stay on supported terrain: "+context+str(phases))
			check(doc.data==before,"Terrain journeys preserve authored transit and terrain: "+context)
			if height==2:
				var portable: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(world,doc.data,studio.library,"res://output/terrain_transit_"+mode+".zip"); check(portable["ok"],"Terrain transit exports its raised platforms and passengers: "+context)
				var next: Dictionary=runtime.request(a["platform"]+a["right"]*2,b["platform"]+b["right"]*2)["job"]
				for vertex in doc.data["terrain_vertices"]: vertex["height"]+=1
				if mode=="3d":
					for item in doc.data["objects"]: item["position"][1]+=1
				studio.changed(); runtime.configure(doc.data,studio.library,world.instances,world.objects)
				check(next["state"]=="cancelled" and runtime.passengers.vehicles.values().all(func(bus: Dictionary):return bus["phase"]=="blocked"),"Changing platform height invalidates waiting journeys and bus route fingerprints: "+context)
				for vertex in doc.data["terrain_vertices"]: vertex["height"]-=1
				if mode=="3d":
					for item in doc.data["objects"]: item["position"][1]-=1
				studio.changed(); runtime.reset(); runtime.configure(doc.data,studio.library,world.instances,world.objects)
			var cell:=Vector2i((a["platform"]/2).floor()); doc.data["water_cells"]=[{"cell":[cell.x,cell.y],"level":height+2}]; studio.changed(); runtime.configure(doc.data,studio.library,world.instances,world.objects)
			check(not runtime.passengers.plan["stops"].has("stop_0") and "flooded" in " ".join(runtime.passengers.plan["notices"]),"Flooded platforms close with an explicit explanation: "+context)
			doc.data["water_cells"]=[]
			if mode=="3d":
				doc.data["objects"][0]["position"][1]+=3; studio.changed(); runtime.configure(doc.data,studio.library,world.instances,world.objects); check(not runtime.passengers.plan["stops"].has("stop_0"),"Unsupported floating transit platforms remain unavailable: "+context)
	studio.free(); print("TERRAIN TRANSIT: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
