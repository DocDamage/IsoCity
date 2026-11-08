extends RefCounted
const Plan=preload("res://scripts/builder/service_plan.gd")
const MAX_JOBS=256
var plan: Dictionary={}
var jobs: Array[Dictionary]=[]
var units: Dictionary={}
var history: Array[Dictionary]=[]
var sequence: int=0

func configure(value: Dictionary,managed: Dictionary={}) -> void:
	var previous: Dictionary=plan; plan=value
	for job in jobs:
		if managed.has(job["id"]) or job["state"] in ["complete","cancelled"]: continue
		if not plan["targets"].has(job["target"]) or not job["station"].is_empty() and not plan["stations"].has(job["station"]):
			cancel(job,"Station or target removed"); continue
		if not job["kind"] in plan["targets"][job["target"]]["kinds"] or not job["station"].is_empty() and plan["stations"][job["station"]]["config"]["kind"]!=job["kind"]:
			cancel(job,"Station or target service type changed"); continue
		if job["state"]=="waiting" or previous.is_empty(): continue
		var changed: bool=false
		for route in [job["route"],job.get("return_route",PackedStringArray())]:
			for key in route:
				if not plan["network"]["sections"].has(key) or previous["network"]["sections"].get(key)!=plan["network"]["sections"].get(key): changed=true
			if not route.is_empty() and not Plan.Traffic.Fleet.fit_route(plan["network"],route,job.get("fleet_profile",{})): changed=true
		if plan["targets"][job["target"]]["point"]!=previous["targets"][job["target"]]["point"] or plan["stations"][job["station"]]["point"]!=previous["stations"][job["station"]]["point"]: changed=true
		if plan["targets"][job["target"]].get("height",0)!=previous["targets"][job["target"]].get("height",0) or plan["stations"][job["station"]].get("height",0)!=previous["stations"][job["station"]].get("height",0): changed=true
		if changed: job["state"]="blocked"; job["reason"]="Road or approach changed; restart service preview"

func request(kind: String,target: String,required_station: String="",training: String="") -> Dictionary:
	if plan.is_empty() or not plan["settings"]["enabled"]: return {"ok":false,"reason":"Enable city services before requesting a visit"}
	if not kind in Plan.KINDS.slice(0,4) or not plan.get("targets",{}).has(target) or not kind in plan["targets"][target]["kinds"]: return {"ok":false,"reason":"Select an eligible service target"}
	if not required_station.is_empty() and (not plan["stations"].has(required_station) or plan["stations"][required_station]["config"]["kind"] != kind):
		return {"ok":false,"reason":"The selected station cannot dispatch this service"}
	for job in jobs:
		if job["target"]==target and job["kind"]==kind and job.get("training","")==training and not job["state"] in ["complete","cancelled"]:
			return {"ok":true,"job":job,"existing":true}
	if jobs.size()>=MAX_JOBS:
		var finished: Array=jobs.filter(func(job: Dictionary):return job["state"] in ["complete","cancelled"])
		if finished.is_empty(): return {"ok":false,"reason":"Service request limit reached"}
		jobs.erase(finished[0])
	sequence+=1
	var job: Dictionary={"id":"service_"+str(sequence),"kind":kind,"target":target,"station":"","unit":"","route":PackedStringArray(),"state":"waiting","reason":"Waiting for dispatch","remaining":0.0,"fulfilled":false}
	if not training.is_empty(): job["training"] = training
	if not required_station.is_empty(): job["required_station"] = required_station
	jobs.append(job); return {"ok":true,"job":job,"existing":false}

func dispatch(limit: int=4) -> void:
	if plan.is_empty() or not plan["settings"]["enabled"]: return
	var busy: Dictionary={}
	for uid in units.values(): busy[uid]=int(busy.get(uid,0))+1
	var assigned: int=0
	for job in jobs:
		if job["state"]!="waiting": continue
		var choice: Dictionary=Plan.choose(plan,job["kind"],job["target"],busy,job.get("training",job["id"]),job.get("required_station",""))
		if not choice["ok"]: job["reason"]=choice["reason"]; continue
		if assigned>=limit: break
		var station: String=choice["station"]; var unit: String=""
		for index in plan["stations"][station]["config"]["units"]:
			var id: String=station+"::"+str(index)
			if not units.has(id): unit=id; break
		if unit.is_empty(): continue
		units[unit]=station; busy[station]=int(busy.get(station,0))+1
		job.merge({"station":station,"unit":unit,"route":choice["route"],"return_route":choice["return_route"],"fleet_profile":choice["fleet_profile"],"remaining":choice["duration"],"state":"outbound","reason":"Crew dispatched"},true); assigned+=1

func arrive(job: Dictionary) -> bool:
	if not owns(job) or job["state"]!="outbound": return false
	job["state"]="working"; job["reason"]=Plan.unit(job["kind"])["activity"]; return true

func work(delta: float) -> void:
	if plan.is_empty() or not plan["settings"]["enabled"] or not is_finite(delta) or delta<=0: return
	for job in jobs:
		if job["state"]!="working": continue
		job["remaining"]=maxf(0,job["remaining"]-delta)
		if job["remaining"]>0: continue
		job["fulfilled"]=true; job["state"]="returning"; job["reason"]="Work complete; returning to station"
		history.append({"kind":job["kind"],"station":job["station"],"target":job["target"],"id":job["id"]})
		if history.size()>128: history.pop_front()

func returned(job: Dictionary) -> bool:
	if not owns(job) or job["state"]!="returning": return false
	job["state"]="complete"; job["reason"]="Crew back at station"; units.erase(job["unit"]); return true

func cancel(job: Dictionary,reason: String="Request cancelled") -> void:
	if not owns(job) or job["state"] in ["complete","cancelled"]: return
	job["state"]="cancelled"; job["reason"]=reason; units.erase(job["unit"])

func reset() -> void:
	plan={}; jobs.clear(); units.clear(); history.clear(); sequence=0

func owns(job: Dictionary) -> bool:
	return jobs.any(func(candidate: Dictionary):return is_same(candidate,job))
