extends SceneTree

const Fleet=preload("res://scripts/builder/fleet_plan.gd")
const Doc=preload("res://scripts/builder/document.gd")
var checks: int=0
var failures: int=0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks+=1
	if not value:
		failures+=1
		print("FAIL: "+message)

func run() -> void:
	var city: Node=load("res://city.tscn").instantiate()
	root.add_child(city)
	for frame in 8: await physics_frame
	var source: Dictionary=city.studio_data
	var mode: String=source["mode"]
	var library: RefCounted=city.exploration.library
	var traffic: Node=city.traffic
	traffic.set_physics_process(false)
	check(Doc.valid(source,mode,library),"The independent document preserves valid fleet choices.")
	check(traffic.vehicles.size()==1 and source["fleet"]["traffic"].size()==3,"The independent city starts with one vehicle and three saved choices.")
	for id in Fleet.required(source):
		check(library.assets.has(id) and ResourceLoader.exists(library.assets[id]["path"]),"An unspawned or zero-weight choice can load its prepared scene independently: "+id)
	var bus: Array=Fleet.pool(source,"transit",library)
	check(bus.size()==1 and not city.transit.passengers.plan["settings"]["enabled"],"An unspawned bus stays available without starting transit.")
	var city_data: Dictionary=source.duplicate(true)
	city_data["traffic"]["population"]=2
	traffic.configure(city_data,library,city.city_instances,city.get_node("Objects"),false)
	check(traffic.vehicles.size()==2 and traffic.vehicles[0]["asset"]!=traffic.vehicles[1]["asset"],"The relocated runtime can spawn both configured positive-weight styles.")
	if traffic.vehicles.size()==2:
		var parked: Dictionary={}
		var intersected: Dictionary={}
		var overlap: bool=false
		for frame in 18000:
			traffic.step(1.0/60)
			var a: Dictionary=traffic.vehicles[0]
			var b: Dictionary=traffic.vehicles[1]
			overlap=overlap or Fleet.overlaps(a,a["point"],a["heading"],b)
			for vehicle in traffic.vehicles:
				if not vehicle["visits"].is_empty(): parked[vehicle["asset"]]=true
				if "0,0" in vehicle["sections"]: intersected[vehicle["asset"]]=true
			if parked.size()==2 and intersected.size()==2: break
		check(parked.size()==2 and intersected.size()==2 and not overlap,"Both independent vehicles use the intersection and parking without overlapping.")
	city.free()
	await process_frame
	print("PORTABLE FLEET: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
