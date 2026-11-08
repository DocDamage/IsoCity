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
	scene.walking=false; scene._set_mode(); scene.player.set_physics_process(false); scene.transit.set_physics_process(false)
	var runtime: Node=scene.transit; var plan: Dictionary=runtime.passengers.plan
	check(plan["lines"].size()==2 and plan["stops"].size()==3,"Fresh portable city compiles both district lines and all stops")
	check(scene.traffic.transit==runtime and scene.services.helper.transit==runtime,"Portable traffic and services share the live transit fleet")
	var asset: String=load("res://scripts/builder/transit_plan.gd").definitions()["vehicles"][scene.dimension]
	check(scene.exploration.library.assets.has(asset) and ResourceLoader.exists(scene.exploration.library.assets[asset]["path"]),"Future buses have their packaged definition and source asset")
	var authored: Dictionary=scene.studio_data.duplicate(true)
	var from: String=scene.studio_data["transit_lines"][0]["stops"][0]; var to: String="portable_third"
	var result: Dictionary=runtime.request(plan["stops"][from]["platform"]+plan["stops"][from]["right"]*2,plan["stops"][to]["platform"]+plan["stops"][to]["right"]*2)
	check(result["ok"] and result["job"]["legs"].size()==4,"Portable district journey requires an actual two-bus transfer")
	if result["ok"]:
		var boarded: Dictionary={}; var job: Dictionary=result["job"]
		for frame in 30000:
			runtime.step(1.0/60)
			if job["state"]=="onboard": boarded[job["vehicle"]]=true
			if job["state"] in ["complete","blocked","cancelled"]: break
		check(job["state"]=="complete" and boarded.size()==2,"Relocated buses physically complete a transfer and the final walk: "+job["reason"])
		check(runtime.passengers.completed==1 and runtime.passengers.vehicles.values().all(func(bus: Dictionary):return bus["manifest"].is_empty() and bus["reserved"].is_empty()),"Portable transfer releases every seat and credits exactly one arrival")
	check(scene.studio_data==authored,"Transit simulation preserves exported source data")
	runtime.update_hud(); check(runtime.panel.visible,"Portable transit exposes its status and controls")
	runtime.pause_button.pressed.emit(); var clock: float=runtime.elapsed; runtime.step(.25)
	check(runtime.paused and runtime.elapsed==clock,"Portable pause control freezes buses and journey time")
	runtime.pause_button.pressed.emit()
	var home: Dictionary=scene.studio_data["objects"].filter(func(item: Dictionary):return item.has("interior"))[0]
	scene.walking=true; scene._set_mode(); scene.player.teleport_to(scene.exploration.entrance(scene.city_instances[home["uid"]])); scene.exploration.interact()
	for frame in 3: await process_frame
	scene._process(0); clock=runtime.elapsed; runtime.step(.25)
	check(scene.exploration.interior!=null and runtime.elapsed==clock and not runtime.helper.container.visible,"Portable interior visits suspend transit and hide exterior actors")
	scene.exploration.leave_interior(); scene._process(0)
	check(runtime.active and runtime.helper.container.visible and runtime.passengers.completed==1,"Returning outdoors preserves the portable fleet and journey history")
	scene.free(); print("TRANSIT EXPORT: %d checks, %d failures"%[checks,failures]); quit(1 if failures else 0)
