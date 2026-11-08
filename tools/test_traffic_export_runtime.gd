extends SceneTree
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var scene: Node=load("res://city.tscn").instantiate(); root.add_child(scene)
	for i in 6: await process_frame
	await physics_frame
	var manager: Node=scene.traffic; manager.set_physics_process(false); manager.pedestrians.clear()
	check(manager.vehicles.size()==3,"A freshly imported portable project spawns the configured vehicles")
	check(manager.bays.size()==1,"Portable parking uses the saved surface designation and connected road")
	var parked: bool=false; var rejoined: bool=false; var stopped: bool=false
	for frame in 18000:
		manager.step(1.0/60)
		if manager.vehicles.any(func(v: Dictionary):return v["phase"]=="parked"): parked=true
		if manager.vehicles.any(func(v: Dictionary):return not v["visits"].is_empty() and v["phase"]=="edge" and v["bay"].is_empty()): rejoined=true
		if manager.vehicles.any(func(v: Dictionary):return v["stops"]>0): stopped=true
		if parked and rejoined and stopped: break
	check(manager.vehicles.any(func(v: Dictionary):return v["sections"].size()>2),"Portable traffic physically traverses road sections and turns")
	check(stopped,"Portable traffic obeys crossing and intersection admission")
	check(parked,"Portable vehicles enter their reserved parking space")
	check(rejoined,"Portable vehicles leave parking and resume driving")
	scene.queue_free(); await process_frame
	print("TRAFFIC EXPORT: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
