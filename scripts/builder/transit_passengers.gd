extends RefCounted
const Plan=preload("res://scripts/builder/transit_plan.gd")
const MAX_REQUESTS: int=128
const MAX_HISTORY: int=128
var plan: Dictionary={}
var jobs: Array[Dictionary]=[]
var vehicles: Dictionary={}
var stop_owners: Dictionary={}
var history: Array[Dictionary]=[]
var sequence: int=0
var completed: int=0
static func failure(reason: String) -> Dictionary: return {"ok":false,"reason":reason}
func owned(job: Dictionary) -> bool:
	return jobs.any(func(existing: Dictionary):return is_same(existing,job))
func fingerprint(line: Dictionary,current: Dictionary) -> int:
	var stops: Array=[]
	for uid in line["stops"]: stops.append([uid,current["stops"][uid]["platform"],current["stops"][uid]["dock"],current["stops"][uid].get("height",0)])
	return hash([stops,line["legs"].map(func(leg: Dictionary):return [leg["sections"],leg["segments"]]),line["headway"],line["dwell"],line["offset"],line["capacity"],line.get("school_bus",false),current["settings"]["speed"]])
func configure(current: Dictionary,managed: bool=false) -> void:
	if not current["settings"]["enabled"]: reset(); plan=current; return
	var previous: Dictionary=plan
	plan=current
	if not managed:
		for bus in vehicles.values():
			if not current["lines"].has(bus["line"]) or fingerprint(current["lines"][bus["line"]],current)!=bus["signature"]: block_vehicle(bus["id"],"Transit route changed; restart after restoring a safe route.")
	for job in jobs:
		if job["state"] in ["complete","cancelled","blocked"]: continue
		if managed:
			if job["state"] in ["onboard","alighting"]: continue
			for leg in job["legs"].slice(job["index"]):
				if leg["kind"]!="ride": continue
				var old_line: Dictionary=previous.get("lines",{}).get(leg["line"],{})
				var line: Dictionary=current["lines"].get(leg["line"],{})
				if not job["required_bus"].is_empty() and not line.get("school_bus",false):
					cancel(job,"The assigned school bus is no longer operating.")
					break
				if old_line.is_empty() or line.is_empty() or old_line["stops"]!=line["stops"] or [leg["from"],leg["to"]].any(func(uid: String)->bool:
					return not current["stops"].has(uid) or not previous["stops"].has(uid) or Plan.stop_layout(current["stops"][uid])!=Plan.stop_layout(previous["stops"][uid])
				):
					cancel(job,"Transit platforms changed before boarding.")
					break
			continue
		for uid in job["signatures"]:
			if not current["lines"].has(uid) or fingerprint(current["lines"][uid],current)!=job["signatures"][uid]:
				if job["state"] in ["onboard","alighting"]: block_vehicle(job["vehicle"],"Transit route changed; restart after restoring a safe route.")
				else: cancel(job,"Transit route changed before boarding.")
				break
func valid_itinerary(value: Variant) -> bool:
	if not value is Dictionary or not value.get("ok",false) or not value.get("legs") is Array or value["legs"].size()<3 or value["legs"].size()>Plan.MAX_LINES+2: return false
	var required: Variant=value.get("required_bus","")
	if not required is String or required.length()>512: return false
	var legs: Array=value["legs"]
	if not legs[0] is Dictionary or not legs[-1] is Dictionary: return false
	if legs[0].get("kind")!="walk" or legs[-1].get("kind")!="walk": return false
	var at: String=""; var rides: int=0
	for leg in legs:
		if not leg is Dictionary or leg.get("from")!=at: return false
		if leg.get("kind")=="walk":
			if not leg.get("path") is PackedVector2Array or leg["path"].is_empty(): return false
			for point in leg["path"]:
				if not point.is_finite(): return false
			if not Plan.number(leg.get("seconds"),0,1000000000): return false
		elif leg.get("kind")=="ride":
			if not plan.get("lines",{}).has(leg.get("line")): return false
			var line: Dictionary=plan["lines"][leg["line"]]
			if not leg.get("from") in line["stops"] or not leg.get("to") in line["stops"] or leg["from"]==leg["to"]: return false
			rides+=1
		else: return false
		if not leg.get("to") is String: return false
		at=leg["to"]
	return at.is_empty() and rides>0
func request(itinerary: Dictionary) -> Dictionary:
	if plan.is_empty() or not plan["settings"]["enabled"]: return failure("Transit is disabled.")
	if not valid_itinerary(itinerary): return failure("The journey has no valid connected walking and riding itinerary.")
	if jobs.size()>=MAX_REQUESTS:
		var index: int=jobs.find_custom(func(job: Dictionary):return job["state"] in ["complete","cancelled"])
		if index<0: return failure("Passenger request limit reached (128).")
		jobs.remove_at(index)
	sequence+=1
	var job: Dictionary={"id":"passenger_"+str(sequence),"legs":itinerary["legs"].duplicate(true),"index":0,"state":"walking","vehicle":"","ready_at":0.0,"signatures":{},"reason":"Walking to the first platform","credited":false,"required_bus":itinerary.get("required_bus","")}
	for leg in job["legs"]:
		if leg["kind"]=="ride": job["signatures"][leg["line"]]=fingerprint(plan["lines"][leg["line"]],plan)
	jobs.append(job); return {"ok":true,"job":job}
func register_vehicle(id: String,line: String,slot: int=0,asset: String="") -> Dictionary:
	if not Plan.identifier(id) or vehicles.has(id) or not plan.get("lines",{}).has(line) or vehicles.size()>=Plan.MAX_FLEET: return failure("Bus identity, line or fleet capacity is invalid.")
	if slot<0 or slot>=plan["lines"][line]["fleet"]: return failure("Bus slot is outside the line's scheduled fleet.")
	for existing in vehicles.values():
		if existing["line"]==line and existing["slot"]==slot: return failure("A bus already serves this timetable slot.")
	vehicles[id]={"id":id,"line":line,"slot":slot,"asset":asset,"cycle":0,"started":false,"capacity":int(plan["lines"][line]["capacity"]),"manifest":[],"reserved":[],"phase":"moving","stop":"","next":plan["lines"][line]["stops"][0],"departure":0.0,"not_before":0.0,"signature":fingerprint(plan["lines"][line],plan)}
	return {"ok":true,"vehicle":vehicles[id]}
func dock(id: String,stop: String,position: Vector2,now: float,scheduled: Dictionary={}) -> Dictionary:
	if not vehicles.has(id) or not plan.get("stops",{}).has(stop) or not Plan.number(now,0,1000000000): return failure("Unknown bus, platform or arrival time.")
	var bus: Dictionary=vehicles[id]
	if not position.is_finite() or position.distance_to(plan["stops"][stop]["dock"])>.4 or now+.0001<bus["not_before"]: return failure("The bus has not physically arrived at its platform.")
	var line: Dictionary=plan["lines"].get(bus["line"],scheduled)
	if bus["phase"]=="blocked" or line.is_empty() or not stop in line["stops"]: return failure("This bus is blocked by an edited route.")
	if bus["phase"]=="dwell" and bus["stop"]==stop: return {"ok":true,"vehicle":bus}
	if bus["phase"]!="moving" or bus["next"]!=stop: return failure("The bus has not reached its next scheduled stop.")
	if stop_owners.has(stop) and stop_owners[stop]!=id: return failure("Waiting for the platform's previous bus to depart.")
	var index: int=line["stops"].find(stop)
	if index==0:
		if bus["started"]: bus["cycle"]+=1
		bus["started"]=true
	bus["phase"]="dwell"; bus["stop"]=stop; stop_owners[stop]=id
	bus["departure"]=maxf(now+line["dwell"],line["first_departure"]+bus["slot"]*line["headway"]+bus["cycle"]*line["cycle"]+line["departures"][index])
	for passenger in bus["manifest"]:
		var job: Dictionary=find(passenger)
		if job.get("state")=="onboard" and job["legs"][job["index"]]["to"]==stop: job["state"]="alighting"; job["reason"]="Walking off the bus to the platform"
	return {"ok":true,"vehicle":bus}
func find(id: String) -> Dictionary:
	for job in jobs:
		if job["id"]==id: return job
	return {}
func next_leg(job: Dictionary,now: float) -> void:
	job["index"]+=1; job["vehicle"]=""; job["ready_at"]=now
	if job["index"]>=job["legs"].size():
		job["state"]="complete"; job["reason"]="Reached the actual destination"
		if not job["credited"]:
			job["credited"]=true; completed+=1; history.append({"id":job["id"],"state":"complete","time":now})
			while history.size()>MAX_HISTORY: history.pop_front()
		return
	job["state"]="walking" if job["legs"][job["index"]]["kind"]=="walk" else "waiting"
	job["reason"]="Walking to the destination" if job["state"]=="walking" else "Waiting for the connecting bus"
func walk_arrived(job: Dictionary,position: Vector2,now: float) -> bool:
	if not owned(job) or job["state"]!="walking" or not position.is_finite() or not Plan.number(now,0,1000000000): return false
	var leg: Dictionary=job["legs"][job["index"]]
	if leg["kind"]!="walk" or position.distance_to(leg["path"][-1])>1.2: return false
	next_leg(job,now); return true
func reserve(job: Dictionary,id: String,now: float) -> Dictionary:
	if not owned(job) or job["state"]!="waiting" or not vehicles.has(id) or not Plan.number(now,0,1000000000): return failure("The passenger is not ready at a platform.")
	var bus: Dictionary=vehicles[id]; var leg: Dictionary=job["legs"][job["index"]]
	if bus["phase"]!="dwell" or bus["stop"]!=leg["from"] or bus["line"]!=leg["line"] or now<job["ready_at"]: return failure("This bus is not boarding the requested connection.")
	if bus.get("retiring",false) or not job["required_bus"].is_empty() and job["required_bus"]!=bus["asset"]:
		return failure("Waiting for the assigned school bus.")
	if bus["manifest"].size()+bus["reserved"].size()>=bus["capacity"]: return failure("Bus is full; wait for the next departure.")
	for other in jobs:
		if other["state"]!="waiting": continue
		var next: Dictionary=other["legs"][other["index"]]
		if next["line"]==leg["line"] and next["from"]==leg["from"] and (other["ready_at"]<job["ready_at"] or is_equal_approx(other["ready_at"],job["ready_at"]) and jobs.find(other)<jobs.find(job)): return failure("An earlier passenger is waiting first.")
	bus["reserved"].append(job["id"]); job["vehicle"]=id; job["state"]="boarding"; job["reason"]="Walking to the bus door"; return {"ok":true}
func board(job: Dictionary,position: Vector2) -> bool:
	if not owned(job) or job["state"]!="boarding" or not position.is_finite() or not vehicles.has(job["vehicle"]): return false
	var bus: Dictionary=vehicles[job["vehicle"]]
	if bus["phase"]!="dwell" or not job["id"] in bus["reserved"]: return false
	var stop: Dictionary=plan["stops"][bus["stop"]]; var door: Vector2=stop["dock"]+stop["right"]*1.2
	if position.distance_to(door)>.8: return false
	bus["reserved"].erase(job["id"]); bus["manifest"].append(job["id"]); job["state"]="onboard"; job["reason"]="Riding the bus"; return true
func depart(id: String,now: float) -> Dictionary:
	if not vehicles.has(id) or not Plan.number(now,0,1000000000): return failure("Unknown bus or departure time.")
	var bus: Dictionary=vehicles[id]
	if bus["phase"]!="dwell" or now+.0000001<bus["departure"]: return failure("Waiting for the scheduled departure and minimum dwell.")
	if not bus["reserved"].is_empty() or bus["manifest"].any(func(uid: String):return find(uid).get("state")=="alighting"): return failure("Passengers are still boarding or alighting.")
	var line: Dictionary=plan["lines"][bus["line"]]; var index: int=line["stops"].find(bus["stop"])
	bus["not_before"]=now+line["legs"][index]["seconds"]
	stop_owners.erase(bus["stop"]); bus["next"]=line["stops"][(index+1)%line["stops"].size()]; bus["stop"]=""; bus["phase"]="moving"; return {"ok":true}
func alight(job: Dictionary,position: Vector2,now: float) -> bool:
	if not owned(job) or job["state"]!="alighting" or not position.is_finite() or not vehicles.has(job["vehicle"]) or not Plan.number(now,0,1000000000): return false
	var bus: Dictionary=vehicles[job["vehicle"]]; var leg: Dictionary=job["legs"][job["index"]]
	if bus["phase"]!="dwell" or bus["stop"]!=leg["to"] or position.distance_to(plan["stops"][leg["to"]]["platform"])>1.2: return false
	bus["manifest"].erase(job["id"]); next_leg(job,now); return true
func cancel(job: Dictionary,reason: String="Passenger request cancelled") -> bool:
	if not owned(job) or job["state"] in ["complete","cancelled","onboard","alighting"]: return false
	if vehicles.has(job["vehicle"]): vehicles[job["vehicle"]]["reserved"].erase(job["id"])
	job["vehicle"]=""; job["state"]="cancelled"; job["reason"]=reason; return true
func abandon(job: Dictionary,reason: String) -> void:
	if not owned(job) or job["state"] in ["complete","cancelled"]: return
	var bus: Dictionary=vehicles.get(job["vehicle"],{})
	if not bus.is_empty():
		bus["reserved"].erase(job["id"])
		bus["manifest"].erase(job["id"])
	job["vehicle"]=""
	job["state"]="cancelled"
	job["reason"]=reason

func block_vehicle(id: String,reason: String) -> void:
	if not vehicles.has(id): return
	var bus: Dictionary=vehicles[id]; bus["phase"]="blocked"
	for uid in bus["manifest"]+bus["reserved"]:
		var job: Dictionary=find(uid)
		if not job.is_empty(): job["state"]="blocked"; job["reason"]=reason
func reset() -> void:
	jobs.clear(); vehicles.clear(); stop_owners.clear(); history.clear(); sequence=0; completed=0; plan={}
