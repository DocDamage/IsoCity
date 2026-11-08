extends SceneTree
const Traffic=preload("res://scripts/builder/traffic_plan.gd")
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
			var doc=preload("res://scripts/builder/document.gd").new(); doc.data=preload("res://scripts/builder/templates.gd").make(mode,"blank"); doc.data["objects"]=[]; doc.data["roads"]=[]; doc.data["terrain"]={"enabled":true,"bounds":[-24,-24,48,48]}; doc.data["terrain_vertices"]=[]; doc.data["water_cells"]=[]
			for x in range(-24,25):
				for z in range(-24,25): doc.data["terrain_vertices"].append({"cell":[x,z],"height":height})
			for x in range(-4,5): doc.data["roads"].append({"cell":[x,0]})
			var station: Dictionary=doc.add("2d:Office_Tower" if mode=="2d" else "3d:HanX_City/Office_Tower",Traffic.world(Vector2(-24,-12),mode,0 if mode=="2d" else height),"SE" if mode=="2d" else "0")
			var target: Dictionary=doc.add("2d:House_Blue" if mode=="2d" else "3d:HanX_City/Row_Houses_A",Traffic.world(Vector2(24,12),mode,0 if mode=="2d" else height),"SE" if mode=="2d" else "180")
			station["city_service"]={"kind":"medical","radius":128,"units":1,"task_seconds":2}; doc.data["services"]={"enabled":true,"automatic":false,"interval":30,"seed":5}
			studio.documents[mode]=doc; studio.changed(); await settle(); var world: Node=studio.worlds[mode]; var manager: Node=studio.service_tools.managers[mode]; manager.set_physics_process(false)
			for desired in [[station,Vector2(-24,-10)],[target,Vector2(24,10)]]:
				var item: Dictionary=desired[0]; var entrance: Variant=world.exploration.entrance(world.instances[item["uid"]]); var actual: Vector2=Traffic.metric([entrance.x,entrance.y,0] if mode=="2d" else [entrance.x,entrance.y,entrance.z],mode)
				item["position"]=Traffic.world(Traffic.metric(item["position"],mode)+desired[1]-actual,mode,0 if mode=="2d" else height)
			studio.changed(); await settle(); manager.reset(); manager.configure(doc.data,studio.library,world.instances,world.objects,studio.traffic_tools.managers[mode]); studio.service_tools.dirty=false
			var context: String=mode+" / height "+str(height); check(manager.dispatch.plan["stations"].has(station["uid"]) and manager.dispatch.plan["targets"].has(target["uid"]),"Supported elevated/depressed service approaches remain available: "+context)
			studio.set_walking(true); world.player.set_physics_process(false); world.player.teleport_to(world.exploration.entrance(world.instances[target["uid"]])); await settle()
			check(manager.nearby_target()==target["uid"],"Nearby service requests use height relative to the terrain: "+context); studio.set_walking(false)
			var before: Dictionary=doc.data.duplicate(true); var request: Dictionary=manager.dispatch.request("medical",target["uid"]); check(request["ok"],"Medical service can dispatch on the sculpted neighborhood: "+context)
			if not request["ok"]: continue
			var job: Dictionary=request["job"]; var drove: bool=false; var walked: bool=false; var worked: bool=false; var supported: bool=true; var captured: bool=false
			for frame in 18000:
				await physics_frame; manager.step(1.0/60)
				if manager.crews.has(job["id"]):
					var crew: Dictionary=manager.crews[job["id"]]; drove=drove or crew["vehicle"]["point"].distance_to(crew["home"])>3
					if crew["worker"].visible:
						walked=true
						if mode=="3d": supported=supported and absf(crew["worker"].position.y-height)<.5
					if job["state"]=="working": worked=worked or manager.at_site(crew)
					if job["state"]=="working" and not captured and height==2 and "--capture" in OS.get_cmdline_user_args():
						captured=true; studio.service_tools.show()
						if mode=="3d": world.target=crew["worker"].position; world.distance=24; world.yaw=225; world.update_camera()
						else: world.camera.position=crew["worker"].position; world.camera.zoom=Vector2.ONE*1.7
						await settle(); await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png("res://output/terrain_service_"+mode+".png")
				if job["state"] in ["complete","blocked","cancelled"]: break
			check(drove and walked and worked and supported,"Vehicle and worker reach and serve the actual supported entrance: "+context)
			check(job["state"]=="complete","Service crew completes its task and returns to the station: "+context+" / "+job["reason"])
			check(doc.data==before,"Terrain service visits preserve the authored city: "+context)
			if height==2:
				var portable: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(world,doc.data,studio.library,"res://output/terrain_services_"+mode+".zip"); check(portable["ok"],"Raised services export with terrain and walking dependencies: "+context)
				if mode=="3d":
					var next: Dictionary=manager.dispatch.request("medical",target["uid"])["job"]; manager.step(.05)
					for vertex in doc.data["terrain_vertices"]: vertex["height"]+=1
					station["position"][1]+=1; target["position"][1]+=1; studio.changed(); manager.configure(doc.data,studio.library,world.instances,world.objects,studio.traffic_tools.managers[mode])
					check(next["state"]=="blocked" and "approach changed" in next["reason"],"Moving terrain and buildings together invalidates an active crew's old vertical approach")
					for vertex in doc.data["terrain_vertices"]: vertex["height"]-=1
					station["position"][1]-=1; target["position"][1]-=1; studio.changed(); manager.reset(); manager.configure(doc.data,studio.library,world.instances,world.objects,studio.traffic_tools.managers[mode])
			var approach: Vector2=manager.dispatch.plan["targets"][target["uid"]]["point"]; var cell:=Vector2i((approach/2).floor()); doc.data["water_cells"]=[{"cell":[cell.x,cell.y],"level":height+2}]; studio.changed(); manager.configure(doc.data,studio.library,world.instances,world.objects,studio.traffic_tools.managers[mode]); check(not manager.dispatch.plan["targets"].has(target["uid"]),"Submerged service entrances are excluded from coverage: "+context)
			doc.data["water_cells"]=[]; studio.changed()
			if mode=="3d":
				station["position"][1]+=3; studio.changed(); manager.configure(doc.data,studio.library,world.instances,world.objects,studio.traffic_tools.managers[mode]); check(not manager.dispatch.plan["stations"].has(station["uid"]),"Floating service approaches remain unavailable: "+context)
	studio.free(); print("TERRAIN SERVICES: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
