extends SceneTree

const Doc=preload("res://scripts/builder/document.gd")
const Plan=preload("res://scripts/builder/traffic_plan.gd")
var checks: int=0
var failures: int=0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, description: String) -> void:
	checks+=1
	if not value:
		failures+=1
		print("FAIL: "+description)

func run() -> void:
	var city: Node=load("res://city.tscn").instantiate()
	root.add_child(city)
	for frame in 8: await physics_frame
	var manager: Node=city.traffic
	var library: RefCounted=city.exploration.library
	var source: Dictionary=city.studio_data
	var mode: String=source["mode"]
	check(Doc.valid(source,mode,library),"The independent source document validates with its authored traffic controls.")
	check(manager.plan["controls"]["active"].size()==2 and not manager.plan["settings"]["enabled"],"Both bindings compile in the playable scene without enabling ordinary traffic.")
	if manager.plan["controls"]["active"].size()==2:
		manager.set_physics_process(false)
		var epoch: float=manager.gates.phase_start["0,0"]
		for phase in [[0.1,"red","red"],[2.2,"green","red"],[6.2,"amber","red"],[9.2,"red","green"],[13.2,"red","amber"],[16.2,"red","red"]]:
			manager.junction_time=epoch+phase[0]
			manager.step(.01)
			check(manager.signal_views.heads["east"]["color"]==phase[1] and manager.signal_views.heads["south"]["color"]==phase[2],"Both native heads display the expected independent phase: "+str(phase))
		var from: Vector2=Plan.center(Vector2i.ZERO,mode)+Vector2(3.8,0)
		var to: Vector2=from-Vector2(.3,0)
		check(manager.pedestrian_can_enter(from,to),"The relocated scene admits pedestrians in its shared walk phase.")
		check(not manager.gates.request(manager.plan,"fixture","0,0",manager.junction_time,false,"1,0")["allowed"],"The same independent walk phase holds vehicles.")
	if mode=="3d":
		for id in Plan.Signals.definitions()["models"].values():
			check(library.assets.has(id) and ResourceLoader.exists(library.assets[id]["path"]),"The independent library loads the required signal color "+id)
	city.free()
	await process_frame
	print("PORTABLE TRAFFIC CONTROLS: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
