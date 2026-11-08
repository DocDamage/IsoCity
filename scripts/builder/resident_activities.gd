extends RefCounted

# Transient resident/job identities and station ownership. Room rendering and
# business accounting stay in their existing adapters; neither enters save data.
const Plan=preload("res://scripts/builder/resident_activity_plan.gd")
const Reservations=preload("res://scripts/builder/activity_reservations.gd")
const Lift=preload("res://scripts/builder/floor_elevator_plan.gd")
const ElevatorState=preload("res://scripts/builder/resident_elevator_state.gd")
const MAX_JOBS: int=128
const MAX_CARS: int=512
const MAX_CLASS_ROUTES: int=512
var reservations: RefCounted
var buildings: Dictionary={}
var jobs: Dictionary={}
var cars: Dictionary={}
var class_routes: Dictionary={}
var sequence: int=0
var service_request: Callable
var service_result: Callable
var service_cancel: Callable
var move_actor: Callable
var transition_ready: Callable
var transition_actor: Callable

func _init(shared_reservations: RefCounted=null) -> void:
	reservations=shared_reservations if shared_reservations else Reservations.new()

func key(building: String,floor_uid: String,station: String) -> String:
	return "room:"+building+":"+floor_uid+":"+station

func configure(compiled: Dictionary) -> void:
	if buildings!=compiled: class_routes.clear()
	buildings=compiled
	for identity in cars.keys():
		var car: Dictionary=cars[identity]
		if not buildings.has(car["building"]) or buildings[car["building"]]["semantic_revision"]!=car["revision"]:cars.erase(identity)
	for job in jobs.values():
		if job["state"] in ["complete","cancelled"]:continue
		if not buildings.has(job["building"]):cancel(job["resident"],"The occupied building or room was removed.");continue
		var plan: Dictionary=buildings[job["building"]]
		if job["revision"]==plan["signature"]:continue
		if job["semantic_revision"]!=plan["semantic_revision"]:
			cancel(job["resident"],"The room or its floor plan changed. A new safe itinerary is required.");continue
		if not job["station"].is_empty():
			var fresh: Dictionary={}
			for station in plan["stations"]:
				var same_identity: bool=station["uid"]==job["station"]["uid"] and station["floor"]==job["station"]["floor"]
				var materialized: bool=job["virtual"] and not plan.get("virtual",false) and station["semantic"]==job["station"]["semantic"]
				if station["reason"].is_empty() and accepts_station(job,station) and (same_identity or materialized):fresh=station;break
			if fresh.is_empty():cancel(job["resident"],"The occupied station was removed or replaced.");continue
			var fresh_key: String=key(job["building"],fresh["floor"],fresh["uid"])
			if job["station_token"] and fresh_key!=job["station_key"]:
				var token: int=reservations.acquire(fresh_key,job["owner"])
				if token==0:cancel(job["resident"],"The newly opened room's station is already occupied.");continue
				release_station(job);job["station_key"]=fresh_key;job["station_token"]=token
			job["station_key"]=fresh_key
			job["station"]=fresh
		job["revision"]=plan["signature"];job["semantic_revision"]=plan["semantic_revision"];job["virtual"]=plan.get("virtual",false)

func request(resident: String,building: String,entry_floor: String,entry: Vector3,action: String="",station_assets: Array=[],hold_station: bool=false) -> Dictionary:
	if resident.is_empty() or resident.length()>256 or not entry.is_finite():return {"ok":false,"reason":"Resident identity or entrance is unavailable."}
	if jobs.has(resident):return {"ok":jobs[resident]["building"]==building,"reason":"This resident already has an itinerary.","job":result(resident)}
	if jobs.size()>=MAX_JOBS:return {"ok":false,"reason":"Resident activity limit reached."}
	if not buildings.has(building) or not buildings[building]["floors"].has(entry_floor):return {"ok":false,"reason":"The furnished room or entrance floor is unavailable."}
	sequence+=1
	var job: Dictionary={"id":"activity_"+str(sequence),"sequence":sequence,"resident":resident,"building":building,"entry_floor":entry_floor,"entry":entry,"floor":entry_floor,"position":entry,"revision":buildings[building]["signature"],"semantic_revision":buildings[building]["semantic_revision"],"virtual":buildings[building].get("virtual",false),"state":"queued","reason":"Waiting for a usable station.","owner":RefCounted.new(),"station":{},"station_key":"","station_token":0,"link_key":"","link_token":0,"legs":[],"leg":0,"point":0,"link_elapsed":0.0,"remaining":0.0,"action":action,"service_started":false,"blocked_seconds":0.0}
	job["station_assets"]=station_assets.duplicate()
	job["hold_station"]=hold_station
	jobs[resident]=job;assign(job)
	return {"ok":true,"reason":job["reason"],"job":result(resident)}

func accepts_station(job: Dictionary,station: Dictionary) -> bool:
	return job["station_assets"].is_empty() or station["item"]["asset"] in job["station_assets"]

func leave_station(resident: String) -> void:
	var job: Dictionary=jobs.get(resident,{})
	if job.is_empty(): return
	match job["state"]:
		"queued":
			job["state"]="complete"
			job["reason"]="Left the station queue."
		"entering":
			job["leave_requested"]=true
		"service":
			set_legs(job,job["stand_legs"],"standing")

func station_paths(job: Dictionary,plan: Dictionary,station: Dictionary) -> Dictionary:
	if not job["hold_station"]: return Plan.station_routes(plan,station,job["entry_floor"],job["entry"])
	var cache_key: String=JSON.stringify([job["building"],job["entry_floor"],Plan.vector_values(job["entry"]),station["floor"],station["uid"]])
	if class_routes.has(cache_key): return class_routes[cache_key]
	var paths: Dictionary=Plan.station_routes(plan,station,job["entry_floor"],job["entry"])
	if class_routes.size()<MAX_CLASS_ROUTES: class_routes[cache_key]=paths
	return paths

func assign(job: Dictionary) -> void:
	if job["state"]!="queued" or not buildings.has(job["building"]):return
	var plan: Dictionary=buildings[job["building"]];var usable: bool=false
	for station in plan["stations"]:
		if not station["reason"].is_empty() or not accepts_station(job,station):continue
		var station_key: String=key(job["building"],station["floor"],station["uid"])
		if job["hold_station"] and not reservations.current(station_key).is_empty():
			usable=true
			continue
		var routes: Dictionary=station_paths(job,plan,station)
		if not routes["ok"]:continue
		var outbound: Dictionary=routes["outbound"];var standing: Dictionary=routes["standing"];var returning: Dictionary=routes["returning"]
		usable=true;var token: int=reservations.acquire(station_key,job["owner"])
		if token==0:continue
		job["station"]=station;job["station_key"]=station_key;job["station_token"]=token;job["stand_legs"]=standing["legs"];job["return_legs"]=returning["legs"];job["remaining"]=station["duration"]
		set_legs(job,outbound["legs"],"entering");return
	job["reason"]="All usable stations are occupied." if usable else "No reachable station has a clear approach, floor link and return route."
	if not usable and not plan["stations"].is_empty() and plan["stations"].all(func(station: Dictionary):return not station["reason"].is_empty()):job["reason"]=plan["stations"][0]["reason"]

func set_legs(job: Dictionary,legs: Array,state: String) -> void:
	job["legs"]=legs;job["leg"]=0;job["point"]=0;job["state"]=state;job["link_elapsed"]=0.0;job["reason"]={"entering":"Walking to a reserved station.","standing":"Leaving the station safely.","returning":"Returning to the exterior entrance."}.get(state,"")

func release_station(job: Dictionary) -> void:
	if job["station_token"]:reservations.release(job["station_key"],job["station_token"])
	job["station_token"]=0

func release_link(job: Dictionary) -> void:
	if job["link_token"]:reservations.release(job["link_key"],job["link_token"])
	job["link_token"]=0;job["link_key"]=""
	job.erase("transport");job.erase("stair")

func cancel(resident: String,reason: String="Resident activity cancelled.") -> void:
	if not jobs.has(resident):return
	var job: Dictionary=jobs[resident]
	if job["service_started"] and service_cancel.is_valid():service_cancel.call(result(resident))
	release_station(job);release_link(job);job["state"]="cancelled";job["reason"]=reason

func depart(resident: String) -> void:
	if not jobs.has(resident):return
	if jobs[resident]["state"]!="complete":cancel(resident,"The resident's destination changed.")
	release_station(jobs[resident]);release_link(jobs[resident]);jobs.erase(resident)

func result(resident: String) -> Dictionary:
	if not jobs.has(resident):return {}
	var value: Dictionary=jobs[resident].duplicate(true);value.erase("owner");return value

func remember_car(job: Dictionary,state: Dictionary) -> void:
	var identity: String=job["link_key"]
	if not cars.has(identity) and cars.size()>=MAX_CARS:
		for candidate in cars.keys():
			if reservations.current(candidate).is_empty():cars.erase(candidate);break
	if cars.has(identity) or cars.size()<MAX_CARS:cars[identity]={"building":job["building"],"revision":buildings[job["building"]]["semantic_revision"],"height":state["height"],"last_stop":state["last_stop"]}

func movement(job: Dictionary,delta: float,speed_scale: float) -> bool:
	if job["leg"]>=job["legs"].size():return true
	var leg: Dictionary=job["legs"][job["leg"]];var mode: String=buildings[job["building"]]["mode"]
	if leg["kind"]!="walk":
		if transition_ready.is_valid() and not transition_ready.call(result(job["resident"]),leg):job["reason"]="Waiting for the floor link to become available.";return false
		if job["link_token"]==0:
			job["link_key"]="room:"+job["building"]+":link:"+leg["link"];job["link_token"]=reservations.acquire(job["link_key"],job["owner"])
			if job["link_token"]==0:job["reason"]="Waiting for the occupied floor link.";return false
		if transition_actor.is_valid():
			var travel: Dictionary=transition_actor.call(result(job["resident"]),leg,delta,speed_scale)
			if travel.get("handled",false):
				if not travel.get("error","").is_empty():cancel(job["resident"],travel["error"]);return false
				if travel.get("position") is Vector3 and travel["position"].is_finite():job["position"]=travel["position"]
				if travel.get("snapshot") is Dictionary and ElevatorState.valid(travel["snapshot"]):job["transport"]=travel["snapshot"];remember_car(job,job["transport"])
				if travel.get("stair") is Dictionary:job["stair"]=travel["stair"]
				job["floor"]=travel.get("floor",job["floor"]);job["reason"]=travel.get("reason","Using the floor link.");job["link_elapsed"]+=delta
				if travel.get("done",false):job["floor"]=leg["next_floor"];job["leg"]+=1;job["point"]=0;job["link_elapsed"]=0.0;release_link(job)
				return false
		if leg["kind"]=="elevator":
			var link: Dictionary={}
			for candidate in buildings[job["building"]]["links"]:
				if candidate["uid"]==leg["link"]:link=candidate;break
			if link.is_empty():cancel(job["resident"],"The occupied elevator was removed.");return false
			if not job.has("transport"):
				var floors: Dictionary=buildings[job["building"]]["floors"];var car: Dictionary=cars.get(job["link_key"],{"height":floors[link["lower"]]["height"],"last_stop":link["lower"]})
				job["transport"]=ElevatorState.initial(link,leg,mode,floors[leg["floor"]]["height"],floors[leg["next_floor"]]["height"],car,job["position"])
			var state: Dictionary=ElevatorState.advance(job["transport"],delta,speed_scale);job["transport"]=state;job["link_elapsed"]+=delta;job["reason"]="Travelling by elevator."
			if state["phase"]=="calling":job["reason"]="Waiting for the elevator car."
			elif state["phase"]=="boarding":job["reason"]="Boarding the elevator."
			elif state["phase"] in ["blocked","waiting"]:job["reason"]=state.get("notice","") if not state.get("notice","").is_empty() else "Waiting for a clear elevator route."
			remember_car(job,state)
			if state["phase"]=="idle":state["phase"]="alighting";state["point"]=ElevatorState.landing_start(state,link,mode)
			if state["phase"]=="alighting":
				state["point"]=state["point"].move_toward(leg["to"],delta*(48 if mode=="2d" else 1.8)*speed_scale);job["position"]=state["point"];job["floor"]=leg["next_floor"]
				if Plan.metric(job["position"],mode).distance_to(Plan.metric(leg["to"],mode))<.005:job["leg"]+=1;job["point"]=0;job["link_elapsed"]=0.0;release_link(job)
			else:job["position"]=ElevatorState.point(state,link,mode)
			return false
		var floors: Dictionary=buildings[job["building"]]["floors"]
		var stair=preload("res://scripts/builder/resident_stair_state.gd")
		if not job.has("stair"):job["stair"]=stair.initial(leg,floors[leg["floor"]]["height"],floors[leg["next_floor"]]["height"],job["position"])
		stair.advance(job["stair"],leg,mode,delta,speed_scale);job["position"]=job["stair"]["point"];job["link_elapsed"]+=delta;job["reason"]="The resident's stair flight is obstructed. Revisit and clear the flight to resume." if job["stair"].get("blocked",false) else "Walking the stairs."
		if job["stair"]["progress"]>=1:
			job["floor"]=leg["next_floor"];job["position"]=leg["to"];job["leg"]+=1;job["point"]=0;job["link_elapsed"]=0.0;release_link(job)
		return false
	var path: PackedVector2Array=leg["path"]
	while job["point"]<path.size():
		var at: Vector2=Plan.metric(job["position"],mode);var distance: float=at.distance_to(path[job["point"]])
		var can_pass: bool=distance<.12 and job["point"]+1<path.size() and Plan.segment_clear(at,path[job["point"]+1],buildings[job["building"]]["floors"][job["floor"]]["obstacles"])
		if distance<.005 or can_pass:job["point"]+=1
		else:break
	if job["point"]>=path.size():
		# The native capsule may already stand on the first tread. Retain its
		# supported height instead of embedding it by snapping to the floor datum.
		if mode=="3d" and move_actor.is_valid():
			if absf(job["position"].y-leg["to"].y)>.4:job["reason"]="Waiting for a supported walking approach.";return false
		else:job["position"]=leg["to"]
		job["leg"]+=1;job["point"]=0;return job["leg"]>=job["legs"].size()
	var next: Vector3=Plan.native(path[job["point"]],mode,leg["to"].y if mode=="3d" else 0);var previous: Vector3=job["position"]
	var floor: Dictionary=buildings[job["building"]]["floors"][job["floor"]];next=Plan.walking_point(floor,next,mode)
	var proposal: Vector3=Plan.walking_point(floor,previous.move_toward(next,delta*(48 if mode=="2d" else 1.8)*speed_scale),mode)
	if move_actor.is_valid():
		var moving: Dictionary=result(job["resident"]);moving["waypoint"]=next;proposal=move_actor.call(moving,proposal,delta)
	if not proposal.is_finite():proposal=previous
	job["position"]=proposal;job["blocked_seconds"]=job["blocked_seconds"]+delta if Plan.metric(proposal,mode).distance_to(Plan.metric(previous,mode))<.001 else 0.0
	if job["blocked_seconds"]>3:job["reason"]="The resident's walking route is obstructed. Clear the approach to resume."
	return false

func service(job: Dictionary,delta: float) -> void:
	if job["hold_station"]:
		if job.get("leave_requested",false): leave_station(job["resident"])
		else: job["reason"]="In class."
		return
	if not job["action"].is_empty():
		if not job["service_started"]:
			if not service_request.is_valid():cancel(job["resident"],"The business activity is unavailable.");return
			var requested: Dictionary=service_request.call(result(job["resident"]))
			if not requested.get("ok",false):cancel(job["resident"],requested.get("reason","The business could not admit this resident."));return
			job["service_started"]=true
		if not service_result.is_valid():cancel(job["resident"],"The business service is unavailable.");return
		var value: Dictionary=service_result.call(result(job["resident"]))
		if value.is_empty():cancel(job["resident"],"The business visit is no longer available.");return
		job["reason"]=value.get("reason","Waiting for business service.")
		if value.get("state","")=="complete":set_legs(job,job["stand_legs"],"standing")
		elif value.get("state","")=="cancelled":cancel(job["resident"],value.get("reason","Business service cancelled."))
		return
	job["remaining"]=maxf(0,job["remaining"]-delta);job["reason"]="Using "+job["station"]["name"]+"."
	if job["remaining"]<=0:set_legs(job,job["stand_legs"],"standing")

func step(delta: float,speed_scale: float=1) -> void:
	if not is_finite(delta) or delta<=0 or not is_finite(speed_scale) or speed_scale<=0:return
	var ordered: Array=jobs.values();ordered.sort_custom(func(a: Dictionary,b: Dictionary):return a["sequence"]<b["sequence"])
	for job in ordered:
		if job["state"] in ["complete","cancelled"]:continue
		if not buildings.has(job["building"]):cancel(job["resident"],"The occupied building or room was removed.");continue
		if job["station_token"] and reservations.current(job["station_key"]).get("token",0)!=job["station_token"]:cancel(job["resident"],"The reserved station is no longer owned by this activity.");continue
		match job["state"]:
			"queued":assign(job)
			"entering":
				if movement(job,delta,speed_scale):job["state"]="service";job["reason"]="Arrived at the reserved station."
			"service":service(job,delta)
			"standing":
				if movement(job,delta,speed_scale):release_station(job);set_legs(job,job["return_legs"],"returning")
			"returning":
				if movement(job,delta,speed_scale):job["state"]="complete";job["reason"]="Activity complete; returned to the exterior entrance."

func reset() -> void:
	for resident in jobs.keys():depart(resident)
	buildings.clear();cars.clear();class_routes.clear()
