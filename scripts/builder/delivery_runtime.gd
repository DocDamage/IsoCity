extends RefCounted

signal cargo_delivered(receipt: Dictionary)
signal construction_haul_cancelled(attempt: String, reason: String)

const Plan=preload("res://scripts/builder/delivery_plan.gd")
const Routes=preload("res://scripts/builder/traffic_route_queue.gd")
const REQUEST: String="local_delivery"
var sites: Dictionary={}
var offers: Dictionary={}
var vehicles: Dictionary={}
var stock: Dictionary={}
var job: Dictionary={}
var receipts: Dictionary={}
var delivered: Dictionary={}
var completed_hauls: Dictionary={}
var reward_total: int=0
var sequence: int=0
var message: String=""
var last_pose: Dictionary={}
var road_input: Array=[]
var routes:=Routes.new()
var gate_section: String=""
var gate_driver: String=""
var village: Node
var village_receipts: Array[String]=[]

func configure(data: Dictionary,library: RefCounted,instances: Dictionary,construction: Dictionary={}) -> void:
	var next_sites: Dictionary={}
	var next_vehicles: Dictionary={}
	var next_offers: Dictionary={}
	var heights: Dictionary={}
	var waters: Dictionary={}
	var terrain_ready: bool=false
	for item in data.get("objects",[]):
		if not item.has("delivery_vehicle") and not item.has("delivery_site"): continue
		var uid: String=item["uid"]
		var node: Node=instances.get(uid)
		if not is_instance_valid(node) or not node.visible: continue
		if Plan.enabled(item,"delivery_vehicle") and not Plan.Drive.profile(item).is_empty():
			next_vehicles[uid]={"config":Plan.settings(item,"delivery_vehicle"),"placement":[item["asset"],item["position"].duplicate(),item["direction"],item["scale"]]}
		if next_sites.size()>=Plan.MAX_SITES or not Plan.enabled(item,"delivery_site"): continue
		if not terrain_ready:
			heights=Plan.Terrain.lookup(data)
			waters=Plan.Terrain.lookup(data,true)
			terrain_ready=true
		var place: Dictionary=Plan.site(item,data,library,heights,waters)
		if place.is_empty(): continue
		next_sites[uid]=place
		if Plan.enabled(item,"delivery_contract"): next_offers[uid]=Plan.settings(item,"delivery_contract")
	if not construction.is_empty():
		var pickup: String=construction["config"]["pickup_uid"]
		var offer: Dictionary=construction["offer"]
		if next_sites.has(pickup) and next_sites.has(offer["destination"]) and not next_offers.has(pickup):
			next_offers[pickup]=offer
	if is_instance_valid(village):
		var village_offers: Dictionary=village.truck_offers()
		for pickup in village_offers:
			var offer: Dictionary=village_offers[pickup]
			if next_sites.has(pickup) and next_sites.has(offer["destination"]) and not next_offers.has(pickup):
				next_offers[pickup]=offer
	if not job.is_empty():
		var source: String=job["pickup"]
		var target: String=job["destination"]
		var vehicle: String=job["vehicle"]
		if terms(next_sites.get(source,{}))!=terms(sites[source]) or terms(next_sites.get(target,{}))!=terms(sites[target]) or next_offers.get(source,{})!=offers[source] or next_vehicles.get(vehicle,{})!=vehicles[vehicle]:
			var seed: Dictionary=sites[source]["config"]
			var next_seed: Dictionary=next_sites.get(source,{}).get("config",{})
			var restore: bool=next_seed.get("stock") == seed["stock"] and next_seed.get("capacity") == seed["capacity"]
			cancel("A delivery site, contract or vehicle changed.",restore)
	for uid in stock.keys():
		if not next_sites.has(uid) or next_sites[uid]["config"]["stock"]!=sites[uid]["config"]["stock"] or next_sites[uid]["config"]["capacity"]!=sites[uid]["config"]["capacity"]:
			stock.erase(uid)
	sites=next_sites
	vehicles=next_vehicles
	offers=next_offers
	if offers.is_empty() and job.is_empty():
		road_input=[]
		return
	var inputs: Array=Plan.Traffic.road_inputs(data)
	if inputs==road_input: return
	road_input=inputs.duplicate(true)
	var boxes: Array[Rect2]=[]
	var graph: Dictionary=Plan.Traffic.build(data)
	if routes.configure(graph,boxes) and not job.is_empty():
		var phase: String=job["phase"]
		var next: String=job.get("resume","loading") if phase in ["routing","blocked"] else phase
		start_route(last_pose,next)

func terms(place: Dictionary) -> Array:
	return [place.get("point"),place.get("height"),place.get("safe"),place.get("config"),place.get("business")]

func inventory(uid: String) -> Dictionary:
	if not sites.has(uid): return {}
	if not stock.has(uid): stock[uid]=sites[uid]["config"]["stock"].duplicate(true)
	return stock[uid]

func available(uid: String) -> int:
	var used: int=0
	for count in inventory(uid).values(): used+=int(count)
	return int(sites[uid]["config"]["capacity"])-used

func at_site(pose: Dictionary,place: Dictionary) -> bool:
	return not pose.is_empty() and place["safe"] and absf(pose["speed"])<=.2 and absf(pose["height"]-place["height"])<=.65 and pose["point"].distance_to(place["point"])<=Plan.PAD_RADIUS

func nearest_offer(pose: Dictionary,limit: float=24) -> String:
	if pose.is_empty(): return ""
	var nearest: String=""
	var ids: Array=offers.keys()
	ids.sort()
	for uid in ids:
		if settled(uid,offers[uid]): continue
		var distance: float=pose["point"].distance_to(sites[uid]["point"])
		if distance<=limit:
			limit=distance
			nearest=uid
	return nearest

func settled(pickup: String,offer: Dictionary) -> bool:
	if offer.has("village_route"): return false
	return completed_hauls.has(offer["construction_attempt"]) if offer.has("construction_attempt") else delivered.has(pickup)

func fail(reason: String) -> bool:
	message=reason
	return false

func request(vehicle: String,pose: Dictionary,hour: float) -> bool:
	if not vehicles.has(vehicle): return fail("Enable local deliveries on a reviewed delivery vehicle.")
	if not job.is_empty():
		if job["vehicle"]!=vehicle: return fail("This contract belongs to the original delivery vehicle.")
		if job["phase"]=="blocked": return start_route(pose,job["resume"])
		if job["phase"]!="carrying": return fail("The delivery is already in progress.")
		var drop: Dictionary=sites[job["destination"]]
		if not Plan.is_open(drop,hour): return fail("The destination is closed. Wait for opening or cancel.")
		if not at_site(pose,drop): return fail("Stop the loaded vehicle on the marked drop-off pad.")
		job["phase"]="unloading"
		job["clock"]=0.0
		job["staged"]=0
		message="Unloading cargo."
		return true
	var pickup: String=nearest_offer(pose,Plan.PAD_RADIUS)
	if pickup.is_empty(): return fail("Stop on an enabled pickup pad to accept its contract.")
	var offer: Dictionary=offers[pickup]
	var target: String=offer["destination"]
	if not at_site(pose,sites[pickup]): return fail("Brake to a stop on the dry, level pickup pad.")
	if not sites.has(target) or not sites[target]["safe"]: return fail("The drop-off site is missing, disabled, or unsafe.")
	if sites[pickup]["point"].distance_to(sites[target]["point"])<8: return fail("Pickup and drop-off pads need at least 8 metres of separation.")
	if not Plan.is_open(sites[pickup],hour): return fail("The pickup shop is closed.")
	if not Plan.is_open(sites[target],hour): return fail("The destination shop is closed.")
	if offer["quantity"]>vehicles[vehicle]["config"]["capacity"]: return fail("This delivery exceeds the vehicle's cargo capacity.")
	var village_haul: bool=offer.has("village_route")
	if not village_haul:
		if int(inventory(pickup).get(offer["goods"],0))<offer["quantity"]: return fail("The pickup site has insufficient stock.")
		if available(target)<offer["quantity"]: return fail("The destination has insufficient storage space.")
	sequence+=1
	var id: String=pickup+":"+str(sequence)
	if village_haul:
		if not is_instance_valid(village): return fail("Village production is unavailable.")
		id="village-haul/%d/%d"%[get_instance_id(),sequence]
		var dispatched: Dictionary=village.book.begin_transfer(id,pickup,"truck")
		if not dispatched["ok"]: return fail(dispatched["reason"])
	job=offer.duplicate(true)
	job.merge({"id":id,"pickup":pickup,"vehicle":vehicle,"phase":"routing","loaded":0,
		"staged":0,"clock":0.0,"elapsed":0.0,"route":PackedStringArray()})
	last_pose=pose.duplicate()
	if start_route(pose,"loading"): return true
	if village_haul: village.book.cancel_transfer(id,message)
	job.clear()
	return false

func start_route(pose: Dictionary,resume: String) -> bool:
	job["resume"]=resume
	job["phase"]="blocked"
	job["route"]=PackedStringArray()
	if pose.is_empty() or routes.network.is_empty(): return fail("The delivery has no connected road approach.")
	var starts: Array=[]
	for entry in road_access(pose["point"]):
		starts.append(Plan.Traffic.edge_id("",entry["section"]))
	var goals: Dictionary={}
	for entry in road_access(sites[job["destination"]]["point"]): goals[entry["section"]]=[]
	var extent: Vector2=pose["extent"]
	var profile: Dictionary={"length":extent.y*2,"width":extent.x*2,"turn_road_width":maxf(4,extent.y*2+extent.x)}
	var ticket: int=routes.request_from(REQUEST,starts,goals,profile)
	if ticket==0: return fail("The delivery has no connected road approach.")
	job["route_ticket"]=ticket
	job["phase"]="routing"
	message="Checking a road route for this vehicle."
	return true

func road_access(point: Vector2) -> Array:
	var access: Array=Plan.Service.access(routes.network,point)
	access.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return a["section"]<b["section"] if is_equal_approx(a["distance"],b["distance"]) else a["distance"]<b["distance"])
	if access.is_empty(): return access
	var nearest: float=access[0]["distance"]
	return access.filter(func(entry: Dictionary)->bool:return entry["distance"]<=nearest+1.25)

func section_at(point: Vector2) -> String:
	var cell:=Vector2i(((point-Plan.Traffic.center(Vector2i.ZERO,routes.network["mode"]))/8).round())
	var uid: String=Plan.Traffic.Roads.key(cell)
	return uid if routes.network["sections"].has(uid) else ""

func release_gate(traffic: Node) -> void:
	if is_instance_valid(traffic) and not gate_driver.is_empty(): traffic.gates.release(gate_driver,gate_section)
	gate_driver=""
	gate_section=""

func clear_abandoned_gate(traffic: Node,point: Vector2) -> void:
	if gate_section.is_empty() or not routes.network["sections"].has(gate_section): return
	var center: Vector2=Plan.Traffic.center(routes.network["sections"][gate_section]["cell"],routes.network["mode"])
	if point.distance_to(center)>6: release_gate(traffic)

func gate_reason(traffic: Node,world: Node,vehicle: String,from_point: Vector2,to_point: Vector2) -> String:
	if not is_instance_valid(traffic) or job.get("vehicle","")!=vehicle or routes.network.is_empty(): return ""
	var from: String=section_at(from_point)
	var to: String=section_at(to_point)
	if from==to: return ""
	if not gate_section.is_empty() and gate_section!=to: release_gate(traffic)
	if to.is_empty(): return ""
	var graph: Dictionary=routes.network
	var section: Dictionary=graph["sections"][to]
	if from.is_empty() and not section["neighbors"].is_empty():
		from=Plan.Traffic.closest_approach(graph,to,from_point)
	var rule: Dictionary=graph["controls"]["sections"].get(to,{})
	if not from.is_empty() and not graph["edges"].has(Plan.Traffic.edge_id(from,to)):
		return "This delivery lane is one-way."
	if rule.is_empty() and not section["crossing"] and section["neighbors"].size()<3: return ""
	gate_driver="delivery:"+vehicle
	gate_section=to
	var occupied: bool=Plan.Traffic.crossing_occupied(graph,to,traffic.pedestrian_points(world))
	var permission: Dictionary=traffic.gates.request(graph,gate_driver,to,traffic.gate_time(to,job["elapsed"]),occupied,from)
	return str(permission["reason"]) if not permission["allowed"] else ""

func locked(vehicle: String) -> bool:
	return job.get("vehicle","")==vehicle and job.get("phase") in ["loading","unloading"]

func step(delta: float,vehicle: String,pose: Dictionary,hour: float) -> void:
	if job.is_empty() or not is_finite(delta) or delta<=0: return
	delta=minf(delta,.25)
	var same_vehicle: bool=job["vehicle"]==vehicle and not pose.is_empty()
	if same_vehicle: last_pose=pose.duplicate()
	job["elapsed"]+=delta
	if job["deadline"]>0 and job["elapsed"]>=job["deadline"]:
		cancel("The delivery deadline expired.")
		return
	if job["phase"]=="routing":
		routes.step()
		var result: Dictionary=routes.take(REQUEST,job["route_ticket"])
		if result.is_empty(): return
		job["route"]=result["route"]
		if result["route"].is_empty():
			job["phase"]="blocked"
			message="No directed route fits this vehicle. Restore the road or cancel."
			return
		job["phase"]=job["resume"]
		message="Road route ready."
	if not same_vehicle or not locked(vehicle): return
	var loading: bool=job["phase"]=="loading"
	var uid: String=job["pickup"] if loading else job["destination"]
	if not Plan.is_open(sites[uid],hour):
		if loading: cancel("The pickup shop closed during loading.")
		else:
			job["phase"]="carrying"
			job["staged"]=0
			message="The destination closed. The cargo stays in your vehicle."
		return
	if not at_site(pose,sites[uid]):
		if loading: cancel("The vehicle left the pickup pad during loading.")
		else:
			job["phase"]="carrying"
			job["staged"]=0
			message="Stop on the drop-off pad to resume unloading."
		return
	job["clock"]+=delta
	if job["clock"]+.000001<Plan.UNIT_SECONDS: return
	job["clock"]=maxf(0,job["clock"]-Plan.UNIT_SECONDS)
	if loading:
		if not job.has("village_route"):
			var inventory_at: Dictionary=inventory(uid)
			var goods: String=job["goods"]
			inventory_at[goods]=int(inventory_at.get(goods,0))-1
		job["loaded"]+=1
		if job["loaded"]>=job["quantity"]:
			job["phase"]="carrying"
			message="Cargo loaded. Drive to the marked destination."
	else:
		job["staged"]+=1
		if job["staged"]>=job["quantity"]: complete(job["id"],vehicle,pose,hour)

func complete(ticket: String,vehicle: String,pose: Dictionary,hour: float) -> Dictionary:
	if receipts.has(ticket):
		return receipts[ticket].duplicate(true) if receipts[ticket]["vehicle"]==vehicle else {}
	if job.get("id","")!=ticket or job.get("vehicle","")!=vehicle or job.get("phase")!="unloading" or job["staged"]!=job["quantity"] or job["loaded"]!=job["quantity"]: return {}
	var destination: String=job["destination"]
	var village_haul: bool=job.has("village_route")
	if (not at_site(pose,sites[destination]) or not Plan.is_open(sites[destination],hour)
		or (not village_haul and available(destination)<job["quantity"]) or settled(job["pickup"],job)):
		cancel("The drop-off could not accept this delivery.")
		return {}
	if village_haul:
		if not is_instance_valid(village):
			cancel("Village production is unavailable.")
			return {}
		var accepted: Dictionary=village.book.complete_transfer(ticket)
		if not accepted["ok"]:
			cancel(accepted["reason"])
			return {}
	else:
		var receiving: Dictionary=inventory(destination)
		var good: String=job["goods"]
		receiving[good]=int(receiving.get(good,0))+int(job["quantity"])
	var goods: String=job["goods"]
	var receipt: Dictionary={"id":ticket,"vehicle":vehicle,"pickup":job["pickup"],"destination":destination,
		"goods":goods,"quantity":job["quantity"],"reward":job["reward"]}
	reward_total+=int(receipt["reward"])
	receipts[ticket]=receipt
	if job.has("construction_attempt"):
		receipt["construction_attempt"]=job["construction_attempt"]
		completed_hauls[job["construction_attempt"]]=true
	elif village_haul:
		village_receipts.append(ticket)
		if village_receipts.size()>128: receipts.erase(village_receipts.pop_front())
	else: delivered[job["pickup"]]=true
	routes.cancel(REQUEST)
	job.clear()
	message="Delivered to village inventory." if village_haul else "Delivered · %d preview credits earned."%receipt["reward"]
	cargo_delivered.emit(receipt.duplicate(true))
	return receipt.duplicate(true)

func cancel(reason: String="Delivery cancelled.",restore: bool=true) -> void:
	if job.is_empty(): return
	var origin: String=job["pickup"]
	var construction_attempt: String=job.get("construction_attempt","")
	var count: int=job["loaded"]
	var village_haul: bool=job.has("village_route")
	if village_haul and is_instance_valid(village): village.book.cancel_transfer(job["id"],reason)
	if not village_haul and count>0 and restore:
		var returned: Dictionary=inventory(origin)
		returned[job["goods"]]=int(returned.get(job["goods"],0))+count
	message=reason
	if not village_haul and count>0:
		message+=" %d units returned to pickup stock."%count if restore else " %d units cleared with the replaced pickup inventory."%count
	routes.cancel(REQUEST)
	job.clear()
	if not construction_attempt.is_empty():
		completed_hauls[construction_attempt]=true
		construction_haul_cancelled.emit(construction_attempt,message)

func reset() -> void:
	if job.has("village_route"): cancel("The local delivery preview ended.")
	job.clear()
	routes.clear_requests()
	stock.clear()
	receipts.clear()
	village_receipts.clear()
	delivered.clear()
	completed_hauls.clear()
	last_pose.clear()
	reward_total=0
	message=""
