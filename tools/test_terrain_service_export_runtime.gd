extends SceneTree
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var scene: Node=load("res://city.tscn").instantiate(); root.add_child(scene)
	for frame in 6: await process_frame
	await physics_frame
	var manager: Node=scene.services; manager.set_physics_process(false); scene.player.set_physics_process(false)
	var before: Dictionary=scene.studio_data.duplicate(true)
	check(manager.dispatch.plan["stations"].size()==1 and manager.dispatch.plan["targets"].size()==1,"Relocated services discover supported raised station and target")
	var uid: String=manager.dispatch.plan["targets"].keys()[0]
	scene.player.teleport_to(scene.exploration.entrance(scene.city_instances[uid])); await physics_frame
	check(manager.nearby_target()==uid,"Relocated service shortcut recognizes a nearby elevated entrance")
	manager.request_kind="medical"; var key:=InputEventKey.new(); key.keycode=KEY_V; key.pressed=true; scene._unhandled_input(key)
	check(manager.dispatch.jobs.size()==1,"Actual portable walking shortcut dispatches the raised-terrain visit")
	if manager.dispatch.jobs.is_empty(): scene.free(); quit(1); return
	var job: Dictionary=manager.dispatch.jobs[0]; scene.player.teleport_to(Vector2(10000,10000) if scene.dimension=="2d" else Vector3(1000,0,1000)); var walked: bool=false; var worked: bool=false; var supported: bool=true
	for frame in 18000:
		await physics_frame; manager.step(1.0/60)
		if manager.crews.has(job["id"]):
			var crew: Dictionary=manager.crews[job["id"]]
			if crew["worker"].visible:
				walked=true
				if scene.dimension=="3d": supported=supported and absf(crew["worker"].position.y-2)<.5
				else: scene.terrain_presentation.refresh(); supported=supported and absf(float(crew["worker"].get_meta("terrain_height",0))-2)<.001
			if job["state"]=="working": worked=worked or manager.at_site(crew)
		if job["state"] in ["complete","blocked","cancelled"]: break
	check(walked and worked and supported,"Relocated workers physically reach and serve the raised approach")
	check(job["state"]=="complete" and job["fulfilled"],"Relocated service vehicles and workers finish and return: "+job["reason"])
	check(scene.studio_data==before,"Relocated terrain visits preserve authored project data")
	scene.free(); print("TERRAIN SERVICE EXPORT: %d checks, %d failures"%[checks,failures]); quit(1 if failures else 0)
