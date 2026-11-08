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
	scene.player.set_physics_process(false); scene.player.teleport_to(Vector2(10000,10000) if scene.dimension=="2d" else Vector3(1000,0,1000)); var runtime: Node=scene.transit; runtime.set_physics_process(false)
	var before: Dictionary=scene.studio_data.duplicate(true)
	check(runtime.passengers.plan["lines"].size()==1 and runtime.passengers.plan["stops"].size()==2,"Relocated transit rebuilds the elevated line and platforms")
	var a: Dictionary=runtime.passengers.plan["stops"]["stop_0"]; var b: Dictionary=runtime.passengers.plan["stops"]["stop_1"]
	check(a["height"]==2 and runtime.supported_path(PackedVector2Array([a["platform"],a["platform"]+a["right"]*2])),"Relocated platforms and physical walking support retain terrain height")
	var request: Dictionary=runtime.request(a["platform"]+a["right"]*2,b["platform"]+b["right"]*2); check(request["ok"],"Relocated passengers request a real raised-terrain journey")
	if not request["ok"]: scene.free(); quit(1); return
	var job: Dictionary=request["job"]; var phases: Dictionary={}; var supported: bool=true
	for frame in 15000:
		await physics_frame; runtime.step(1.0/60); phases[job["state"]]=true
		var actor: Node=runtime.walkers[job["id"]]["actor"]
		if actor.visible:
			if scene.dimension=="3d": supported=supported and absf(actor.position.y-2)<.5
			else: scene.terrain_presentation.refresh(); supported=supported and float(actor.get_meta("terrain_height",0))==2
		if job["state"] in ["complete","blocked","cancelled"]: break
	check(job["state"]=="complete" and phases.has_all(["walking","waiting","boarding","onboard","alighting","complete"]),"Relocated buses and passengers complete every journey phase: "+job["reason"])
	check(supported and runtime.walkers[job["id"]]["actor"].recovery_count==0,"Relocated walking, boarding and alighting retain supported height without recovery teleportation")
	check(scene.studio_data==before,"Relocated terrain transit preserves authored data")
	scene.free(); print("TERRAIN TRANSIT EXPORT: %d checks, %d failures"%[checks,failures]); quit(1 if failures else 0)
