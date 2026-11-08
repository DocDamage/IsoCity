extends SceneTree
const Scheduler=preload("res://scripts/builder/resident_activities.gd")
const Plan=preload("res://scripts/builder/resident_activity_plan.gd")
const Visits=preload("res://scripts/builder/business_visits.gd")
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;print("FAIL: "+message)
func run() -> void:
	var library: RefCounted=preload("res://scripts/builder/asset_library.gd").new()
	for mode in ["2d","3d"]:
		var room: Dictionary=preload("res://scripts/builder/interiors.gd").make(mode,"Resident activity");room["objects"]=[];var doc: RefCounted=preload("res://scripts/builder/document.gd").new();doc.data=room
		for x in [-2,2]:doc.add("3d:HanX_School/Student_Chair",[(x+2)*16,-32,0] if mode=="2d" else [x,.12,-2],"0")
		var original: Dictionary=room.duplicate(true);var plan: Dictionary=Plan.compile(room,library);var raw: Array=room["exit"];var entry:=Vector3(raw[0],raw[1],raw[2]);var registry: RefCounted=preload("res://scripts/builder/activity_reservations.gd").new();var scheduler: RefCounted=Scheduler.new(registry);scheduler.configure({"shop":plan})
		var a: Dictionary=scheduler.request("resident_a","shop","ground",entry);var b: Dictionary=scheduler.request("resident_b","shop","ground",entry);var first_id: String=a["job"]["id"]
		check(a["ok"] and b["ok"] and a["job"]["station"]["uid"]!=b["job"]["station"]["uid"],"Two residents reserve distinct furnished stations: "+mode)
		check(scheduler.request("resident_a","shop","ground",entry)["job"]["id"]==first_id and scheduler.jobs.size()==2,"Repeated arrival preserves job identity without a duplicate itinerary: "+mode)
		var player:=RefCounted.new();check(registry.acquire(a["job"]["station_key"],player)==0,"Player station use shares the reservation ledger: "+mode)
		var c: Dictionary=scheduler.request("resident_c","shop","ground",entry);check(c["job"]["state"]=="queued" and c["job"]["reason"].contains("occupied"),"Excess resident waits without sharing a chair: "+mode)
		scheduler.configure({"shop":Plan.compile(room,library)});check(scheduler.result("resident_a")["id"]==first_id and scheduler.result("resident_a")["state"]=="entering","Recompiling identical logical room preserves active identity: "+mode)
		for tick in 400:scheduler.step(.1)
		check(scheduler.result("resident_a")["state"]=="complete" and scheduler.result("resident_b")["state"]=="complete" and scheduler.result("resident_c")["state"]=="complete","All three take turns, finish and leave the room: "+mode)
		check(scheduler.jobs.values().all(func(job: Dictionary):return job["position"]==entry and job["floor"]=="ground") and registry.entries.is_empty(),"Completed residents return to their exact entrance and release stations: "+mode)
		check(room==original and doc.undo_history.is_empty(),"Transient queues/motion/service create no authored data/history: "+mode)
		scheduler.reset();scheduler.configure({"shop":plan});scheduler.request("resident_a","shop","ground",entry);scheduler.request("resident_b","shop","ground",entry);scheduler.cancel("resident_a","Explicit cancellation");check(scheduler.result("resident_a")["state"]=="cancelled" and registry.entries.size()==1,"Cancellation releases only its own station: "+mode)
		var moved_room: Dictionary=room.duplicate(true);moved_room["objects"][0]["position"][0]+=16 if mode=="2d" else 1;scheduler.configure({"shop":Plan.compile(moved_room,library)});check(scheduler.result("resident_b")["state"]=="cancelled" and registry.entries.is_empty(),"Actual furnishing movement invalidates old route and frees its reservation: "+mode)
		scheduler.reset();scheduler.configure({"shop":plan});scheduler.request("resident_a","shop","ground",entry);scheduler.configure({});check(scheduler.result("resident_a")["state"]=="cancelled" and registry.entries.is_empty(),"Deleting occupied building cancels safely without dangling station ownership: "+mode)
		scheduler.reset();scheduler.configure({"shop":plan,"copy":plan});scheduler.request("resident_a","shop","ground",entry);scheduler.request("resident_b","copy","ground",entry);check(registry.entries.size()==2 and scheduler.result("resident_a")["station"]["uid"]==scheduler.result("resident_b")["station"]["uid"],"Copied building reuses furniture IDs without sharing occupancy: "+mode);scheduler.reset()
		var service: RefCounted=Visits.new();var config: Dictionary=preload("res://scripts/builder/business_plan.gd").defaults("cafe");config["capacity"]=1;service.configure({"shop":{"config":config}});var requests: Dictionary={}
		scheduler.service_request=func(job: Dictionary):requests[job["resident"]]=requests.get(job["resident"],0)+1;return service.request(job["building"],job["resident"],job["action"],12)
		scheduler.service_result=func(job: Dictionary):return service.result(job["resident"])
		scheduler.service_cancel=func(job: Dictionary):service.cancel(job["resident"],"Station itinerary cancelled")
		scheduler.configure({"shop":plan});scheduler.request("resident_a","shop","ground",entry,"coffee");scheduler.request("resident_b","shop","ground",entry,"coffee")
		check(service.visits.is_empty(),"Business service does not start while residents are still walking to stations: "+mode)
		var queued: bool=false
		for tick in 500:
			scheduler.step(.1);service.step(.1,12)
			if service.visits.values().any(func(visit: Dictionary):return visit["state"]=="queued"):queued=true
		check(queued and service.history.size()==2 and requests=={"resident_a":1,"resident_b":1},"Existing capacity-one business queue serves each station visitor exactly once: "+mode)
		check(service.inventory["resident_a"]["Coffee"]==1 and service.inventory["resident_b"]["Coffee"]==1 and scheduler.jobs.values().all(func(job: Dictionary):return job["state"]=="complete"),"Service inventory is neither duplicated nor lost while residents return: "+mode)
		scheduler.reset();service.reset();service.configure({"shop":{"config":config}});scheduler.configure({"shop":plan});scheduler.request("resident_a","shop","ground",entry,"coffee")
		for tick in 300:
			scheduler.step(.1)
			if scheduler.result("resident_a")["service_started"]:break
		service.forget("resident_a");scheduler.step(.1);check(scheduler.result("resident_a")["state"]=="cancelled" and registry.entries.is_empty(),"Missing business progress cancels with a reason rather than waiting forever: "+mode);scheduler.reset()
		var upper: Dictionary=room.duplicate(true);room["floors"]=[{"uid":"upper","name":"Upper room","height":3,"room":upper}];room["objects"]=[];room["floor_links"]=[{"uid":"lift","kind":"elevator","lower":"ground","upper":"upper","start":[0,0],"end":[0,0],"width":1.2}];var linked: Dictionary=Plan.compile(room,library);scheduler.configure({"shop":linked});scheduler.request("resident_a","shop","ground",entry);scheduler.request("resident_b","shop","ground",entry)
		var lift_key: String="room:shop:link:lift";var player_token: int=registry.acquire(lift_key,player)
		for tick in 150:scheduler.step(.1)
		check(scheduler.result("resident_a")["floor"]=="ground" and scheduler.result("resident_b")["floor"]=="ground" and registry.current(lift_key)["token"]==player_token,"Occupied elevator blocks both resident itineraries at their current floor: "+mode)
		registry.release(lift_key,player_token);var saw_wait: bool=false
		for tick in 600:
			scheduler.step(.1)
			if scheduler.jobs.values().any(func(job: Dictionary):return job["reason"].contains("occupied floor link")):saw_wait=true
		check(saw_wait and scheduler.jobs.values().all(func(job: Dictionary):return job["state"]=="complete"),"Elevator capacity queues residents and supports both return trips: "+mode)
		check(registry.entries.is_empty(),"All elevator/station reservations release after completed round trips: "+mode);scheduler.reset()
		check(not scheduler.request("","shop","ground",entry)["ok"],"Invalid resident identities are refused")
	print("RESIDENT ACTIVITIES: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
