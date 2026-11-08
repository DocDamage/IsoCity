extends RefCounted

const Plan=preload("res://scripts/builder/vehicle_service_plan.gd")
const WAIT_LIMIT: float=75
const RECEIPT_LIMIT: int=64
const JOB_LIMIT: int=128
var vehicles: Dictionary={}
var bays: Dictionary={}
var states: Dictionary={}
var jobs: Dictionary={}
var queues: Dictionary={}
var receipts: Dictionary={}
var feedback: Dictionary={}
var sequence: int=0
var wallet: int=-1
var wallet_open: bool=false
var source: Dictionary={}
var supply_requirement: Callable

func configure(data: Dictionary,library: RefCounted,instances: Dictionary,mode: String) -> void:
	source=data
	var new_vehicles: Dictionary={}
	var new_bays: Dictionary={}
	var heights: Dictionary=Plan.Terrain.lookup(data)
	var waters: Dictionary=Plan.Terrain.lookup(data,true)
	for item in data.get("objects",[]):
		var uid: String=item["uid"]
		var config: Dictionary=Plan.vehicle(item)
		if not config.is_empty():
			new_vehicles[uid]={"item":item,"config":config,"placement":[item["asset"],item["position"].duplicate(),item["direction"],item["scale"],item.get("visible",true)]}
		if new_bays.size()>=Plan.MAX_BAYS: continue
		var layout: Dictionary=Plan.layout(item,instances.get(uid),mode,library)
		if layout.is_empty(): continue
		layout["supported"]=Plan.support(layout,data,heights,waters)
		new_bays[uid]=layout
	for uid in vehicles:
		var next: Dictionary=new_vehicles.get(uid,{})
		if next.is_empty() or next["config"]!=vehicles[uid]["config"] or next["placement"]!=vehicles[uid]["placement"]:
			cancel(uid,"The vehicle settings or placement changed.")
			states.erase(uid)
			if next.is_empty(): feedback.erase(uid)
	for uid in jobs.keys():
		var bay_id: String=jobs[uid]["bay"]
		if not new_bays.has(bay_id) or terms(new_bays[bay_id])!=terms(bays[bay_id]):
			cancel(uid,"The service bay changed or was removed.")
	vehicles=new_vehicles
	bays=new_bays

func terms(value: Dictionary) -> Dictionary:
	var result: Dictionary=value.duplicate()
	result.erase("name")
	return result

func state(uid: String) -> Dictionary:
	if not vehicles.has(uid): return {}
	if not states.has(uid): states[uid]=Plan.initial(vehicles[uid]["config"])
	return states[uid]

func open_wallet() -> void:
	if wallet_open: return
	wallet_open=true
	if not Plan.Economy.settings(source)["enabled"]: return
	var account: Variant=source.get("economy_account")
	wallet=maxi(0,int(account["cash"])) if Plan.Economy.valid_account(account) else Plan.Economy.settings(source)["starting_cash"]

func energy_limit(uid: String) -> float:
	if not vehicles.has(uid): return INF
	return state(uid)["energy"]/vehicles[uid]["config"]["use_per_metre"]

func performance(uid: String) -> float:
	if not vehicles.has(uid): return 1.0
	return lerpf(.45,1.0,state(uid)["condition"]/100.0)

func travelled(uid: String,distance: float) -> void:
	if not vehicles.has(uid) or not is_finite(distance) or distance<=0: return
	var current: Dictionary=state(uid)
	current["energy"]=maxf(0,current["energy"]-vehicles[uid]["config"]["use_per_metre"]*distance)
	current["condition"]=maxf(0,current["condition"]-.05*distance)
	current["cleanliness"]=maxf(0,current["cleanliness"]-.3*distance)

func nearby(pose: Dictionary) -> Dictionary:
	if pose.is_empty(): return {}
	var nearest: Dictionary={}
	var distance: float=INF
	for bay in bays.values():
		if not Plan.geometry(pose,bay)["approach"]: continue
		var value: float=pose["point"].distance_squared_to(bay["center"])
		if value<distance:
			distance=value
			nearest=bay
	return nearest

func failure(uid: String,reason: String) -> Dictionary:
	if vehicles.has(uid): feedback[uid]=reason
	return {"ok":false,"reason":reason}

func supply_reason(bay_id: String) -> String:
	if not supply_requirement.is_valid() or bays.get(bay_id,{}).get("kind","")!="charge": return ""
	return supply_requirement.call(bay_id)

func request(uid: String,bay_id: String,pose: Dictionary) -> Dictionary:
	if not vehicles.has(uid): return failure(uid,"Enable vehicle care on this vehicle first.")
	if jobs.has(uid): return failure(uid,"This vehicle already has a service request.")
	if not bays.has(bay_id) or pose.is_empty(): return failure(uid,"Drive to an enabled vehicle-care bay.")
	var bay: Dictionary=bays[bay_id]
	var supply: String=supply_reason(bay_id)
	if not supply.is_empty(): return failure(uid,supply)
	var config: Dictionary=vehicles[uid]["config"]
	var reason: String=Plan.reason(config,pose,bay)
	if not reason.is_empty(): return failure(uid,reason)
	var current: Dictionary=state(uid)
	if current==Plan.result(current,config,bay["kind"]): return failure(uid,"This vehicle does not need that service.")
	open_wallet()
	if wallet>=0 and wallet<int(bay["price"]): return failure(uid,"Insufficient vehicle-care funds.")
	var queue: Array=queues.get(bay_id,[])
	var ready: bool=queue.is_empty() and Plan.geometry(pose,bay)["in_bay"] and absf(pose.get("speed",0.0))<=.2
	var waiting: int=queue.size()
	if not queue.is_empty() and jobs[queue[0]]["state"]=="servicing": waiting-=1
	if not ready and waiting>=int(bay["queue"]): return failure(uid,"This bay's waiting queue is full.")
	if jobs.size()>=JOB_LIMIT: return failure(uid,"The vehicle-care request limit has been reached.")
	sequence+=1
	var job: Dictionary={"id":"vehicle_service_"+str(sequence),"bay":bay_id,"state":"servicing" if ready else "queued","remaining":float(bay["seconds"]),"waited":0.0}
	jobs[uid]=job
	queue.append(uid)
	queues[bay_id]=queue
	feedback.erase(uid)
	return {"ok":true,"job":job}

func cancel(uid: String,reason: String="Vehicle service cancelled.") -> void:
	if not jobs.has(uid): return
	finish(uid,reason)

func finish(uid: String,reason: String) -> void:
	var bay_id: String=jobs[uid]["bay"]
	queues[bay_id].erase(uid)
	if queues[bay_id].is_empty(): queues.erase(bay_id)
	jobs.erase(uid)
	feedback[uid]=reason

func locked(uid: String) -> bool:
	return jobs.get(uid,{}).get("state","")=="servicing"

func complete(uid: String,ticket: String) -> Dictionary:
	if receipts.has(ticket) and receipts[ticket]["vehicle"]==uid: return receipts[ticket].duplicate(true)
	var job: Dictionary=jobs.get(uid,{})
	if job.get("id","")!=ticket or job.get("state","")!="servicing" or job["remaining"]>0:
		return {"ok":false,"reason":"The service request is no longer ready."}
	var bay: Dictionary=bays[job["bay"]]
	var supply: String=supply_reason(job["bay"])
	if not supply.is_empty():
		cancel(uid,supply)
		return {"ok":false,"reason":supply}
	var price: int=int(bay["price"]) if wallet>=0 else 0
	if wallet>=0 and wallet<price:
		cancel(uid,"Insufficient vehicle-care funds at completion.")
		return {"ok":false,"reason":"Insufficient vehicle-care funds at completion."}
	var result: Dictionary=Plan.result(states[uid],vehicles[uid]["config"],bay["kind"])
	var receipt: Dictionary={"ok":true,"ticket":ticket,"vehicle":uid,"bay":job["bay"],"kind":bay["kind"],"paid":price,"result":result.duplicate()}
	if wallet>=0: wallet-=price
	states[uid]=result
	receipts[ticket]=receipt
	if receipts.size()>RECEIPT_LIMIT: receipts.erase(receipts.keys()[0])
	finish(uid,"Service complete · %d credits paid."%price if price>0 else "Service complete.")
	return receipt.duplicate(true)

func step(delta: float,pose_for: Callable) -> void:
	if not is_finite(delta) or delta<=0: return
	delta=minf(delta,.25)
	for uid in jobs.keys():
		var job: Dictionary=jobs[uid]
		var bay: Dictionary=bays[job["bay"]]
		var supply: String=supply_reason(job["bay"])
		if not supply.is_empty():
			cancel(uid,supply)
			continue
		var pose: Dictionary=pose_for.call(uid)
		var location: Dictionary={} if pose.is_empty() else Plan.geometry(pose,bay)
		if not location.get("approach",false):
			cancel(uid,"The vehicle left the service approach.")
			continue
		var parked: bool=location["in_bay"] and absf(pose.get("speed",0.0))<=.2
		if job["state"]=="servicing":
			if not parked:
				cancel(uid,"The vehicle left the bay before service finished.")
				continue
			job["remaining"]=maxf(0,job["remaining"]-delta)
			if job["remaining"]<=0: complete(uid,job["id"])
		elif queues[job["bay"]][0]==uid and parked:
			if wallet>=0 and wallet<int(bay["price"]):
				cancel(uid,"Insufficient vehicle-care funds.")
				continue
			job["state"]="servicing"
		else:
			job["waited"]+=delta
			if job["waited"]>=WAIT_LIMIT: cancel(uid,"The service queue wait expired.")

func reset() -> void:
	states.clear()
	jobs.clear()
	queues.clear()
	receipts.clear()
	feedback.clear()
	wallet=-1
	wallet_open=false
