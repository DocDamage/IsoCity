extends RefCounted

# Session state: callers supply verified arrivals; no city document is mutated.
const Plan=preload("res://scripts/builder/business_plan.gd")
const MAX_VISITORS=256
var businesses: Dictionary={}
var visits: Dictionary={}
var queues: Dictionary={}
var inventory: Dictionary={}
var history: Array[Dictionary]=[]
var sequence: int=0
var market_check: Callable
var market_complete: Callable
var supply_requirement: Callable
var dish_check: Callable
var dish_complete: Callable

func configure(values: Dictionary) -> void:
	businesses=values.duplicate(true)
	for id in queues.keys():
		if not businesses.has(id): queues.erase(id)
	for visit in visits.values():
		if not visit["state"] in ["queued","active"]: continue
		if not businesses.has(visit["business"]): cancel(visit["visitor"],"Business removed")
		elif Plan.action(businesses[visit["business"]]["config"],visit["action"] ).is_empty(): cancel(visit["visitor"],"Activity is no longer available")

func request(uid: String,visitor: String,action: String,hour: float) -> Dictionary:
	if not businesses.has(uid): return {"ok":false,"reason":"Business unavailable"}
	var supply: String=supply_reason(uid)
	if not supply.is_empty(): return {"ok":false,"reason":supply}
	if visitor.is_empty() or visitor.length()>256: return {"ok":false,"reason":"Visitor identity unavailable"}
	if visits.has(visitor):
		var existing: Dictionary=visits[visitor]
		if existing["state"] in ["active","queued"]:
			return {"ok":existing["business"]==uid and existing["action"]==action,"reason":"A visit is already in progress","visit":existing.duplicate(true)}
	var config: Dictionary=businesses[uid]["config"]
	if not Plan.open(config,hour): return {"ok":false,"reason":"Closed · opens at "+time_text(config["open_hour"])}
	var activity: Dictionary=Plan.action(config,action)
	if activity.is_empty(): return {"ok":false,"reason":"Activity unavailable"}
	if activity.has("result_id"):
		var queued: int = visits.values().filter(func(v: Dictionary) -> bool:
			return v["business"]==uid and v["action"]==action and v["state"] in ["queued","active"]).size()
		var reason: String = dish_check.call(uid,visitor,activity["result_id"],queued) if dish_check.is_valid() else "The kitchen is unavailable."
		if not reason.is_empty(): return {"ok":false,"reason":reason}
	if config["kind"]=="market" and market_check.is_valid():
		var reason: String=market_check.call(uid,visitor)
		if not reason.is_empty(): return {"ok":false,"reason":reason}
	if not visits.has(visitor) and visits.size()>=MAX_VISITORS: return {"ok":false,"reason":"Visitor limit reached"}
	sequence+=1
	var visit: Dictionary={"business":uid,"visitor":visitor,"action":action,"label":activity["label"],"progress":activity["progress"],"item":activity["item"],"remaining":activity["seconds"],"duration":activity["seconds"],"state":"queued","reason":"Waiting for service","sequence":sequence}
	if activity.has("result_id"): visit["result_id"]=activity["result_id"]
	visits[visitor]=visit
	if not queues.has(uid): queues[uid]=[]
	queues[uid].append(visitor)
	admit(uid,hour)
	return {"ok":true,"reason":"","visit":visit.duplicate(true)}

func admit(uid: String,hour: float) -> void:
	if not businesses.has(uid) or not Plan.open(businesses[uid]["config"],hour) or not supply_reason(uid).is_empty(): return
	var capacity: int=businesses[uid]["config"]["capacity"]
	var active: int=visits.values().filter(func(v: Dictionary):return v["business"]==uid and v["state"]=="active").size()
	var queue: Array=queues.get(uid,[])
	while active<capacity and not queue.is_empty():
		var visitor: String=queue.pop_front()
		if not visits.has(visitor) or visits[visitor]["state"]!="queued": continue
		visits[visitor]["state"]="active"; visits[visitor]["reason"]=visits[visitor]["progress"]; active+=1

func step(delta: float,hour: float,market_paused: bool=false,dishes_paused: bool=false) -> void:
	if not is_finite(delta) or delta<=0: return
	# Admission occurs after active work, so a queued visit never receives work
	# from time elapsed before its turn. Active services finish after closing.
	for visit in visits.values():
		if visit["state"] in ["queued","active"]:
			var supply: String=supply_reason(visit["business"])
			if not supply.is_empty():
				cancel(visit["visitor"],supply)
				continue
		var market: bool=businesses.get(visit["business"],{}).get("config",{}).get("kind","")=="market"
		if market and market_paused: continue
		if visit.has("result_id") and dishes_paused: continue
		if visit["state"]=="queued" and businesses.has(visit["business"]) and not Plan.open(businesses[visit["business"]]["config"],hour):
			cancel(visit["visitor"],"Business closed before service began")
		if visit["state"]!="active": continue
		visit["remaining"]=maxf(0,visit["remaining"]-delta)
		if visit["remaining"]>0: continue
		if market and (int(inventory.get(visit["visitor"],{}).get(visit["item"],0))>=999 or not market_complete.is_valid() or not market_complete.call(visit)):
			cancel(visit["visitor"],"The purchase could not settle.")
			continue
		if visit.has("result_id") and (int(inventory.get(visit["visitor"],{}).get(visit["item"],0))>=999 or not dish_complete.is_valid() or not dish_complete.call(visit)):
			cancel(visit["visitor"],"The prepared dish is unavailable.")
			continue
		visit["state"]="complete"; visit["reason"]=visit["item"]+" received"
		if not inventory.has(visit["visitor"]): inventory[visit["visitor"]]={}
		var items: Dictionary=inventory[visit["visitor"]]
		items[visit["item"]]=mini(999,int(items.get(visit["item"],0))+1)
		history.append({"visitor":visit["visitor"],"business":visit["business"],"activity":visit["label"],"item":visit["item"],"sequence":visit["sequence"]})
		if visit.has("result_id"): history[-1]["result_id"]=visit["result_id"]
		if history.size()>128: history.pop_front()
	for uid in queues:
		if not market_paused or businesses.get(uid,{}).get("config",{}).get("kind","")!="market": admit(uid,hour)

func cancel(visitor: String,reason: String="Visit cancelled") -> void:
	if not visits.has(visitor) or not visits[visitor]["state"] in ["active","queued"]: return
	var visit: Dictionary=visits[visitor]
	visit["state"]="cancelled"; visit["reason"]=reason
	if queues.has(visit["business"]): queues[visit["business"]].erase(visitor)

func depart(visitor: String) -> void:
	cancel(visitor,"Visitor left the business")
	visits.erase(visitor)

func forget(visitor: String) -> void:
	depart(visitor); inventory.erase(visitor)

func result(visitor: String) -> Dictionary:
	return visits.get(visitor,{}).duplicate(true)

func reset() -> void:
	businesses.clear(); visits.clear(); queues.clear(); inventory.clear(); history.clear(); sequence=0

func supply_reason(uid: String) -> String:
	return supply_requirement.call(uid) if supply_requirement.is_valid() else ""

static func time_text(hour: float) -> String:
	return "%02d:%02d" % [floori(hour),floori(fposmod(hour,1)*60)]
