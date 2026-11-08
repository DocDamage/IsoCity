extends RefCounted

const Plan=preload("res://scripts/builder/school_plan.gd")
const Traffic=preload("res://scripts/builder/traffic_plan.gd")
var sites: Dictionary={}
var enrolled: Dictionary={}
var attendance: Dictionary={}
var last_hour: float=-1
var day: int=0
var trips: Dictionary={}
var rode: Dictionary={}
var arrived_at_school: Dictionary={}
var trip_budget: int=0

func configure(data: Dictionary,library: RefCounted,arrivals: Dictionary,lookup: Dictionary) -> void:
	var next: Dictionary={}
	var items: Dictionary={}
	for item in data["objects"]:
		if arrivals.has(item["uid"]) and not item.has("missing_asset") and library.assets.has(item["asset"]):
			items[item["uid"]]=item
	var ids: Array=items.keys()
	ids.sort()
	for uid in ids:
		if next.size()>=Plan.MAX_SCHOOLS: break
		var item: Dictionary=items[uid]
		if not Plan.enabled(item): continue
		var config: Dictionary=Plan.settings(item)
		var yard: String=config["playground"]
		if not items.has(yard) or not Plan.playground(items[yard]) or arrivals[uid].distance_to(arrivals[yard])>Plan.PLAYGROUND_RANGE:
			yard=uid
		var name: String=str(item.get("name",library.assets[item["asset"]]["name"]))
		next[uid]={"config":config,"point":arrivals[uid],"yard":yard,"name":name}
		if not lookup.has(uid):
			lookup[uid]={"uid":uid,"role":"school","name":name,"point":arrivals[uid]}
		if yard!=uid and not lookup.has(yard):
			lookup[yard]={"uid":yard,"role":"park","name":items[yard].get("name",library.assets[items[yard]["asset"]]["name"]),"point":arrivals[yard]}
	sites=next

func assign(residents: Array[Dictionary],lookup: Dictionary) -> void:
	var previous: Dictionary=enrolled
	enrolled=Plan.enroll(residents,sites,lookup)
	for id in attendance.keys():
		if not enrolled.has(id) or enrolled[id]!=previous.get(id): attendance.erase(id)

func phase(uid: String,hour: float) -> String:
	return Plan.phase(sites[uid]["config"],hour) if sites.has(uid) else "closed"

func desired(resident: Dictionary,hour: float,fallback: String) -> String:
	var uid: String=enrolled.get(resident["id"],"")
	if uid.is_empty(): return fallback
	match phase(uid,hour):
		"arrival","morning","afternoon": return uid
		"break":
			var site: Dictionary=sites[uid]
			if not site["config"]["bus_line"].is_empty() and not arrived_at_school.has(resident["id"]): return uid
			return site["yard"]
		_: return resident["home"]

func prepare(hour: float,hours_advanced: float,activities: RefCounted) -> void:
	trip_budget=2
	var continuous: bool=last_hour>=0 and hours_advanced>0 and absf(fposmod(last_hour+hours_advanced,24)-hour)<.0001
	if last_hour>=0 and hour<last_hour:
		attendance.clear()
		rode.clear()
		arrived_at_school.clear()
		if continuous: day+=1
	if activities:
		for id in activities.scheduler.jobs:
			var job: Dictionary=activities.scheduler.jobs[id]
			if not job.get("hold_station",false): continue
			var uid: String=enrolled.get(id,"")
			var now: String=phase(uid,hour)
			if uid!=job["building"]:
				activities.scheduler.cancel(id,"This pupil's school assignment changed.")
			elif not now in Plan.CLASS_PHASES or now!=phase(uid,last_hour) and last_hour>=0:
				activities.scheduler.leave_station(id)
			elif continuous and job["state"]=="service" and not job.get("leave_requested",false):
				var minutes: float=attendance.get(id,0.0)
				attendance[id]=minf(Plan.lesson_minutes(sites[uid]["config"]),minutes+hours_advanced*60)
	last_hour=hour

func arrived(manager: Node,resident: Dictionary,target: String) -> bool:
	var uid: String=enrolled.get(resident["id"],"")
	if uid.is_empty() or not sites.has(uid): return false
	var now: String=phase(uid,manager.hour)
	if target!=uid:
		if now=="break" and target==sites[uid]["yard"]:
			resident["status"]="At the school playground."
			return true
		return false
	arrived_at_school[resident["id"]]=true
	if now=="break" or now=="arrival":
		resident["status"]="School break outside." if now=="break" else "Waiting for the first bell."
		return true
	if not now in Plan.CLASS_PHASES: return false
	if resident["retry"]>0: return true
	var activity: RefCounted=manager.activities
	if not activity: return true
	var room: Dictionary=activity.ensure(uid)
	var allowed: Array=Plan.definitions().get("seats",[])
	if allowed.is_empty() or not room.get("floors",{}).has("ground") or not room.get("stations",[]).any(func(station: Dictionary)->bool:return station["item"]["asset"] in allowed and station["reason"].is_empty()):
		resident["status"]="The classroom has no usable student desks."
		resident["waiting"]=resident["status"]
		resident["retry"]=3.0
		return true
	return activity.begin_visit(resident,uid,room,"",allowed,true)

func using_bus(manager: Node,resident: Dictionary,target: String) -> bool:
	var id: String=resident["id"]
	var uid: String=enrolled.get(id,"")
	var transit: Node=manager.transit
	if trips.has(id):
		var trip: Dictionary=trips[id]
		var job: Dictionary=trip["job"]
		var phase_now: String=phase(uid,manager.hour)
		if (uid!=trip["school"] or trip["inbound"] and phase_now in ["closed","before","dismissed"]) and job["state"] in ["walking","waiting","boarding"]:
			if is_instance_valid(transit): transit.passengers.cancel(job,"The school arrival window has ended.")
		if is_instance_valid(transit) and job["state"]=="blocked":
			var bus: Dictionary=transit.passengers.vehicles.get(job["vehicle"],{})
			if not job["id"] in bus.get("manifest",[]): transit.remove_walker(job["id"],true)
		if job["state"] in ["complete","cancelled"] or not is_instance_valid(transit):
			if is_instance_valid(transit): transit.remove_walker(job["id"])
			trips.erase(id)
			resident["target"]=""
			resident["path"]=PackedVector2Array()
			resident["index"]=0
			resident["retry"]=0.0 if job["state"]=="complete" else 3.0
			if job["state"]=="complete":
				if not rode.has(id): rode[id]={}
				rode[id][trip["inbound"]]=true
			return false
		resident["status"]=job["reason"]
		return true
	if uid.is_empty(): return false
	var site: Dictionary=sites[uid]
	var config: Dictionary=site["config"]
	if config["bus_line"].is_empty(): return false
	var phase_now: String=phase(uid,manager.hour)
	var inbound: bool=not arrived_at_school.has(id) and phase_now in ["arrival","morning","break","afternoon"] and target==uid
	var outbound: bool=arrived_at_school.has(id) and target==resident["home"] and phase_now in ["dismissed","closed"]
	if not (inbound or outbound) or rode.get(id,{}).has(inbound): return false
	if resident["retry"]>0 or trip_budget<=0: return true
	resident["status"]="Waiting for the assigned school bus."
	if not is_instance_valid(transit) or manager.exterior_suspended(): return true
	trip_budget-=1
	var from: String=config["home_stop"] if inbound else config["school_stop"]
	var to: String=config["school_stop"] if inbound else config["home_stop"]
	var position: Array=preload("res://scripts/builder/citizen_plan.gd").world(manager.plan["lookup"][target]["point"],manager.dimension)
	var result: Dictionary=transit.request_school(resident["actor"],Traffic.metric(position,manager.dimension),config["bus_line"],from,to)
	if not result["ok"]:
		resident["status"]=result["reason"]
		resident["retry"]=3.0
		return true
	trips[id]={"school":uid,"inbound":inbound,"job":result["job"]}
	return true

func forget(id: String,transit: Node) -> void:
	if trips.has(id) and is_instance_valid(transit):
		transit.remove_walker(trips[id]["job"]["id"],true)
	trips.erase(id)
	rode.erase(id)
	arrived_at_school.erase(id)

func summary(uid: String,hour: float,activities: RefCounted) -> String:
	if not sites.has(uid): return "Choose an enabled school."
	var pupils: Array=enrolled.keys().filter(func(id: String)->bool:return enrolled[id]==uid)
	var seated: int=0
	var waiting: int=0
	if activities:
		for id in pupils:
			var state: String=activities.scheduler.jobs.get(id,{}).get("state","")
			if state=="service": seated+=1
			if state=="queued": waiting+=1
	var minutes: float=0
	for id in pupils: minutes+=float(attendance.get(id,0.0))
	return "Day %d · %s · %d enrolled · %d in class · %d waiting for desks\n%d pupil-minutes present today" % [day+1,phase(uid,hour).capitalize(),pupils.size(),seated,waiting,floori(minutes)]

func reset(transit: Node=null) -> void:
	for id in trips.keys(): forget(id,transit)
	rode.clear()
	arrived_at_school.clear()
	sites.clear()
	enrolled.clear()
	attendance.clear()
	last_hour=-1
	day=0
