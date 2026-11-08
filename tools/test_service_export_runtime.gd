extends SceneTree
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
func run() -> void:
	var scene: Node=load("res://city.tscn").instantiate(); root.add_child(scene); await settle()
	var manager: Node=scene.services; manager.set_physics_process(false); scene.player.set_physics_process(false); scene.traffic.set_physics_process(false)
	check(manager.dispatch.plan["stations"].size()==4,"Fresh portable project discovers all four service departments")
	var uid: String=""
	for key in manager.dispatch.plan["targets"]:
		if manager.dispatch.plan["targets"][key]["name"]=="Home 1": uid=key
	check(not uid.is_empty(),"Portable requests refer to an actual saved neighborhood building")
	scene.player.teleport_to(scene.exploration.entrance(scene.exploration.instances[uid])); await settle()
	for index in 4:
		var kind: String=Plan.KINDS[index]
		var key:=InputEventKey.new(); key.keycode=KEY_V; key.pressed=true
		if index>0: key.shift_pressed=true; scene._unhandled_input(key); key.shift_pressed=false
		scene._unhandled_input(key)
		var job: Dictionary=manager.dispatch.jobs.back()
		check(job["kind"]==kind and job["target"]==uid,"Portable exploration shortcuts request the correct service: "+kind)
		var visible_worker: bool=false
		for frame in 24000:
			manager.step(1.0/60)
			if manager.crews.has(job["id"]) and manager.crews[job["id"]]["worker"].visible: visible_worker=true
			if job["state"] in ["complete","blocked","cancelled"]: break
		check(job["state"]=="complete" and job["fulfilled"] and visible_worker,"Portable vehicles and workers physically serve and return: "+kind+" · "+job["reason"])
		if manager.crews.has(job["id"]):
			var crew: Dictionary=manager.crews[job["id"]]
			check(crew["vehicle"]["point"].distance_to(crew["home"])<.4 and manager.worker_point(crew["worker"]).distance_to(crew["home"])<.4,"Portable completion verifies actual vehicle and passenger return: "+kind)
	check(manager.dispatch.history.size()==4 and manager.dispatch.units.is_empty(),"Portable service results are counted once and crew capacity is released")
	scene.queue_free(); await process_frame
	print("SERVICE EXPORT: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
