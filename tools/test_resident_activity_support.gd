extends SceneTree
const Plan=preload("res://scripts/builder/resident_activity_plan.gd")
const Scheduler=preload("res://scripts/builder/resident_activities.gd")
const Doc=preload("res://scripts/builder/document.gd")
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;print("FAIL: "+message)
func room_at(height: float,terrain_height: float=0) -> Dictionary:
	var room: Dictionary=preload("res://scripts/builder/interiors.gd").make("3d","Support fixture");room["objects"]=[];var doc: RefCounted=Doc.new();doc.data=room
	for x in [-3,3]:doc.add("3d:HanX_School/Student_Chair",[x,height,-3],"0")
	if terrain_height!=0:
		room["terrain"]={"enabled":true,"bounds":[-8,-8,16,16]};room["terrain_vertices"]=[]
		for x in range(-8,9):
			for z in range(-8,9):room["terrain_vertices"].append({"cell":[x,z],"height":terrain_height})
	return room
func run() -> void:
	var library: RefCounted=preload("res://scripts/builder/asset_library.gd").new();var child_count: int=root.get_child_count()
	for height in [2.12,-1.88]:
		var room: Dictionary=room_at(height);var source: Dictionary=room.duplicate(true);var plan: Dictionary=Plan.compile(room,library);var scheduler: RefCounted=Scheduler.new();scheduler.configure({"host":plan})
		check(plan["stations"].size()==2 and plan["stations"].all(func(station: Dictionary):return station["reason"].contains("support")),"Floating or buried station approaches are diagnosed before logical admission: "+str(height))
		scheduler.request("resident","host","ground",plan["floors"]["ground"]["exit"])
		for frame in 600:scheduler.step(1.0/60)
		var waiting: Dictionary=scheduler.result("resident")
		check(waiting.get("state","")=="queued" and waiting.get("reason","").contains("support") and not waiting.get("service_started",false) and scheduler.reservations.entries.is_empty(),"An unrendered unsupported station waits outside with a support diagnosis and no ownership or activity grant: "+str(height))
		scheduler.reset()
		check(room==source and root.get_child_count()==child_count,"Unsupported source inspection creates no worlds or authored changes")
	var room: Dictionary=room_at(2.12,2);var source: Dictionary=room.duplicate(true);var plan: Dictionary=Plan.compile(room,library);var scheduler: RefCounted=Scheduler.new();scheduler.configure({"host":plan})
	check(plan["stations"].all(func(station: Dictionary):return station["reason"].is_empty()),"Furniture on an actually raised terrain surface remains usable")
	check(plan["floors"]["ground"]["exit"].y>1.9,"Logical entry is fitted to the raised source surface")
	check(scheduler.request("resident","host","ground",plan["floors"]["ground"]["exit"])["ok"],"A supported raised station has a complete logical return itinerary")
	var minimum: float=INF
	for frame in 1800:
		scheduler.step(1.0/60);var job: Dictionary=scheduler.result("resident")
		if job.get("state","")!="queued":minimum=minf(minimum,job.get("position",Vector3.ZERO).y)
		if job.get("state","")=="complete":break
	check(scheduler.result("resident").get("state","")=="complete" and minimum>1.9,"Entire unrendered activity and return stay on the actual raised surface")
	check(room==source and root.get_child_count()==child_count,"Raised logical simulation creates no room worlds or authored state")
	scheduler.reset();print("RESIDENT ACTIVITY SUPPORT: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
