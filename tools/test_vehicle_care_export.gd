extends SceneTree

const Drive=preload("res://scripts/builder/driving_plan.gd")
var checks: int=0
var failures: int=0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool,description: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		print("FAIL: "+description)

func run() -> void:
	var city: Node=load("res://city.tscn").instantiate()
	root.add_child(city)
	var driver: Node=city.exploration.driving
	driver.set_physics_process(false)
	city.economy.set_physics_process(false)
	city.player.set_physics_process(false)
	for frame in 8: await physics_frame
	var source: Dictionary=city.studio_data.duplicate(true)
	check(driver.care.vehicles.size()==5 and driver.care.bays.size()==4,"Fresh package reconstructs all opted-in cars and actual bays.")
	check(driver.care.states.is_empty() and driver.care.jobs.is_empty() and driver.care.wallet==-1,"Fresh package starts with no inherited condition, queues, or private balance.")
	for kind in ["fuel","charge","wash","repair"]:
		var uid: String=kind+"_car"
		var bay: Dictionary=driver.care.bays.get(kind,{})
		var pose: Dictionary=driver.care_snapshot(uid)
		if bay.is_empty() or pose.is_empty():
			check(false,"Missing live fixture for "+kind)
			continue
		var heading: Vector2=pose["heading"]
		var side:=Vector2(heading.y,-heading.x)
		var point: Vector2=pose["point"]+side*(pose["extent"].x+.9)
		city.player.teleport_to(city.player.get_parent().to_local(city.to_global(Drive.world(point,city.dimension,.05))))
		var entered: bool=driver.interact(driver.nearby(uid))
		var requested: bool=entered and driver.request_vehicle_service()
		var money: int=driver.care.wallet
		var served: bool=false
		for frame in 900:
			if not requested or driver.active.is_empty(): break
			var remaining: float=driver.active["point"].distance_to(bay["center"])
			driver.step(1.0/60,Vector2.DOWN if remaining>.7 else Vector2.ZERO,remaining<=.7)
			driver.step_services(1.0/60)
			served=served or driver.care.locked(uid)
			if not driver.care.jobs.has(uid): break
		var field: String="cleanliness" if kind=="wash" else "condition" if kind=="repair" else "energy"
		check(served and driver.care.state(uid).get(field)==100 and driver.care.wallet==money-int(bay["price"]),"The relocated player physically receives and pays for "+kind+" "+str([driver.notice,driver.care.feedback]))
		if not driver.active.is_empty(): driver.exit_vehicle(true)
		for frame in 3: await physics_frame
	check(city.studio_data==source and driver.care.receipts.size()==4 and driver.care.jobs.is_empty(),"The four independent services preserve the exact saved city and treasury.")
	city.free()
	await process_frame
	print("PORTABLE VEHICLE CARE: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
