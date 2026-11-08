extends SceneTree

const Doc=preload("res://scripts/builder/document.gd")
const Plan=preload("res://scripts/builder/traffic_plan.gd")
var checks: int=0
var failures: int=0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:
		failures+=1
		print("FAIL: "+message)

func run() -> void:
	var city: Node=load("res://city.tscn").instantiate()
	root.add_child(city)
	for frame in 8: await physics_frame
	var data: Dictionary=city.studio_data
	var mode: String=data["mode"]
	var library: RefCounted=city.exploration.library
	var traffic: Node=city.traffic
	traffic.set_physics_process(false)
	city.player.set_physics_process(false)
	var off_road: Array=Plan.world(Vector2(-32,24),mode)
	city.player.teleport_to(Vector2(off_road[0],off_road[1]) if mode=="2d" else Vector3(off_road[0],0,off_road[2]))
	check(Doc.valid(data,mode,library) and traffic.vehicles.size()==1 and traffic.bays.has("bay"),"Independent source validation, initial car and original parking bay.")
	check(not city.transit.passengers.plan["settings"]["enabled"] and not city.services.dispatch.plan["settings"]["enabled"],"The portable city retains both simulation defaults.")
	if traffic.vehicles.size()!=1 or not traffic.bays.has("bay"):
		city.free()
		quit(1)
		return
	var original: Dictionary=data.duplicate(true)
	var vehicle: Dictionary=traffic.vehicles[0]
	var actor_id: int=vehicle["actor"].get_instance_id()
	traffic.release_bay(vehicle)
	vehicle["from"]="0,0"
	vehicle["to"]="1,0"
	var lane: Dictionary=traffic.plan["edges"]["0,0>1,0"]
	traffic.set_path(vehicle,lane["points"],"edge")
	vehicle["distance"]=lane["length"]*.3
	var sample: Dictionary=Plan.sample(vehicle["path"],vehicle["distance"])
	vehicle["point"]=sample["point"]
	vehicle["heading"]=sample["heading"]
	traffic.pose(vehicle)
	traffic.choose_bay(vehicle)
	check(vehicle["bay"]=="bay","The actual vehicle reserves the unchanged destination.")
	var position: Vector2=vehicle["point"]
	var revision: int=traffic.route_queue.revision
	var changed: Dictionary=data.duplicate(true)
	Plan.Roads.paint(changed,Vector2i(2,0),Vector2i(2,0),true)
	traffic.configure(changed,library,city.city_instances,city.get_node("Objects"),false)
	check(traffic.route_queue.revision==revision+1 and vehicle["point"]==position and vehicle.has("route_request"),"The relocated runtime queues the edit without moving or replacing the active vehicle.")
	var continuous: bool=true
	for frame in 9000:
		var last: Vector2=vehicle["point"]
		traffic.step(1.0/60)
		continuous=continuous and vehicle["point"].distance_to(last)<.09
		if vehicle["phase"]=="parked": break
	check(vehicle["phase"]=="parked" and "2,1" in vehicle["sections"] and not "2,0" in vehicle["sections"] and continuous and vehicle["actor"].get_instance_id()==actor_id,"The original car travels the actual alternate road and parks in the original bay: "+str([vehicle["phase"],vehicle["status"],vehicle["sections"],vehicle["point"],continuous]))
	check(data==original and not data.has("route_queue") and traffic.bay_owners.get("bay")==vehicle["id"],"Transient routing and the parking claim leave authored source exact.")
	city.free()
	await process_frame
	print("PORTABLE REROUTE: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
