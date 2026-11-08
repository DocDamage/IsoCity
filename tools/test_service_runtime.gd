extends SceneTree
const Runtime=preload("res://scripts/builder/service_runtime.gd")
const Traffic=preload("res://scripts/builder/traffic_plan.gd")
const Plan=preload("res://scripts/builder/service_plan.gd")
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
	Plan.load_catalog()
	root.size=Vector2i(1480,900)
	var studio: Control=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio); await settle()
	for mode in ["2d","3d"]:
		studio.switch_mode(mode)
		var doc: RefCounted=preload("res://scripts/builder/document.gd").new()
		doc.data=preload("res://scripts/builder/templates.gd").make(mode,"blank"); doc.data["roads"]=[]
		for x in range(-4,5): doc.data["roads"].append({"cell":[x,0],"crossing":x==0})
		var station: Dictionary=doc.add("2d:Office_Tower" if mode=="2d" else "3d:HanX_City/Office_Tower",Traffic.world(Vector2(-24,-12),mode),"SE" if mode=="2d" else "0")
		var target: Dictionary=doc.add("2d:House_Blue" if mode=="2d" else "3d:HanX_City/Row_Houses_A",Traffic.world(Vector2(24,12),mode),"SE" if mode=="2d" else "180")
		doc.data["services"]={"enabled":true,"automatic":false,"interval":30,"seed":5}
		studio.documents[mode]=doc; studio.changed(); await settle()
		var manager: Node=studio.service_tools.managers[mode]; manager.set_physics_process(false)
		if mode=="2d": studio.worlds[mode].camera.position=Vector2.ZERO; studio.worlds[mode].camera.zoom=Vector2.ONE*1.3
		else: studio.worlds[mode].target=Vector3.ZERO; studio.worlds[mode].distance=76; studio.worlds[mode].update_camera()
		for kind in Plan.KINDS.slice(0,4):
			manager.reset()
			for id in Plan.catalog["stations"]:
				if Plan.catalog["stations"][id]==kind: station["asset"]=id; break
			station["direction"]=studio.library.directions(station["asset"])[0]; station["scale"]=studio.library.assets[station["asset"]]["data"].get("default_scale",1.0)
			station["city_service"]={"kind":kind,"radius":128,"units":1,"task_seconds":2}; studio.changed(); await settle()
			for desired in [[station,Vector2(-24,-10)],[target,Vector2(24,10)]]:
				var item: Dictionary=desired[0]
				var entrance: Variant=studio.worlds[mode].exploration.entrance(studio.worlds[mode].instances[item["uid"]])
				var actual: Vector2=Traffic.metric([entrance.x,entrance.y,0] if mode=="2d" else [entrance.x,entrance.y,entrance.z],mode)
				item["position"]=Traffic.world(Traffic.metric(item["position"],mode)+desired[1]-actual,mode)
			studio.changed(); await settle()
			manager.configure(doc.data,studio.library,studio.worlds[mode].instances,studio.worlds[mode].objects,studio.traffic_tools.managers[mode])
			var before: Dictionary=doc.data.duplicate(true); var history: int=doc.undo_history.size()
			var request: Dictionary=manager.dispatch.request(kind,target["uid"])
			check(request["ok"],"City service requests identify a real neighborhood target: "+mode+kind)
			var job: Dictionary=request["job"]
			var moved: bool=false; var walked: bool=false; var worked: bool=false; var origin:=Vector2.ZERO; var captured: bool=false
			for frame in 18000:
				manager.step(1.0/60)
				if manager.crews.has(job["id"]):
					var crew: Dictionary=manager.crews[job["id"]]
					origin=crew["home"]
					if crew["vehicle"]["point"].distance_to(origin)>3: moved=true
					if crew["worker"].visible and crew["stage"].begins_with("walking"): walked=true
					if job["state"]=="working":
						worked=manager.at_site(crew)
						if not captured:
							captured=true; manager.step(.1)
							if mode=="2d": studio.worlds[mode].camera.position=crew["worker"].position; studio.worlds[mode].camera.zoom=Vector2.ONE*1.7
							else: studio.worlds[mode].target=crew["worker"].position; studio.worlds[mode].distance=30; studio.worlds[mode].yaw=225; studio.worlds[mode].update_camera()
							await capture("service_"+kind+"_"+mode)
				if job["state"] in ["complete","blocked","cancelled"]: break
			check(moved,"An actual service vehicle drives away from the station: "+mode+kind)
			check(walked and worked,"A visible worker leaves the vehicle, reaches the actual site and performs work: "+mode+kind)
			check(job["state"]=="complete" and job["fulfilled"] and manager.dispatch.history.size()==1,"Service fulfills once and returns its crew to the station: "+mode+kind+" · "+job["reason"])
			if manager.crews.has(job["id"]):
				var crew: Dictionary=manager.crews[job["id"]]
				check(crew["vehicle"]["point"].distance_to(origin)<.4 and manager.worker_point(crew["worker"]).distance_to(origin)<.4 and not crew["worker"].visible and manager.dispatch.units.is_empty(),"Completion requires the actual vehicle and worker to be back at the depot: "+mode+kind)
			check(doc.data==before and doc.undo_history.size()==history,"Dispatch and service work do not mutate the city or undo history: "+mode+kind)
	studio.queue_free(); await process_frame
	print("SERVICE RUNTIME: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
