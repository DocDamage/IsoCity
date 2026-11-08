extends SceneTree

const School=preload("res://scripts/builder/school_plan.gd")
const Traffic=preload("res://scripts/builder/traffic_plan.gd")
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
	city.citizens.set_physics_process(false)
	city.transit.set_physics_process(false)
	city.player.set_physics_process(false)
	for frame in 8: await physics_frame
	var manager: Node=city.citizens
	var bus: Node=city.transit
	var mode: String=city.studio_data["mode"]
	var point: Array=Traffic.world(Vector2(-16,30),mode)
	city.player.teleport_to(Vector2(point[0],point[1]) if mode=="2d" else Vector3(point[0],0,point[2]))
	check(manager.schools.sites.size()==1 and manager.schools.enrolled.size()==2,"Fresh package retains opt-in and original enrollment.")
	check(manager.schools.attendance.is_empty() and manager.schools.trips.is_empty() and manager.activities.scheduler.jobs.is_empty(),"Fresh package starts with no inherited attendance, trips, or desks.")
	check(bus.school_pool.size()==1 and bus.school_pool[0]["asset"]==School.bus_asset(mode),"The reviewed school bus is independently loadable.")
	var source: Dictionary=city.studio_data.duplicate(true)
	var ids: Array=manager.residents.map(func(pupil: Dictionary)->int:return pupil["actor"].get_instance_id())
	var onboard: bool=false
	var arrived: bool=false
	var capacity: bool=true
	for frame in 24000:
		await physics_frame
		manager.step(1.0/60)
		bus.step(1.0/60)
		for entry in bus.passengers.vehicles.values():
			capacity=capacity and entry["reserved"].size()+entry["manifest"].size()<=1
			onboard=onboard or not entry["manifest"].is_empty()
		arrived=manager.activities.scheduler.jobs.values().filter(func(job: Dictionary)->bool:return job["hold_station"] and job["state"]=="service").size()==2
		if arrived: break
	check(onboard and capacity and arrived and bus.passengers.completed==2,"Both pupils physically board, alight, and reach desks within the exact seat limit.")
	manager.hour=15
	for frame in 24000:
		await physics_frame
		manager.step(1.0/60)
		bus.step(1.0/60)
		if bus.passengers.completed==4 and manager.schools.trips.is_empty(): break
	check(bus.passengers.completed==4 and manager.schools.trips.is_empty() and manager.activities.scheduler.reservations.entries.is_empty(),"Dismissal returns both pupils and releases all classroom and bus claims.")
	check(manager.residents.map(func(pupil: Dictionary)->int:return pupil["actor"].get_instance_id())==ids and city.studio_data==source,"Independent school day preserves original bodies and authored source.")
	city.free()
	await process_frame
	print("PORTABLE SCHOOL: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
