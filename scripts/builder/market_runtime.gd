extends RefCounted

const Plan=preload("res://scripts/builder/market_plan.gd")
const MAX_RECEIPTS: int=128
const MAX_SESSION_MARKETS: int=64
var sites: Dictionary={}
var active: Dictionary={}
var vendors: Dictionary={}
var targets: Dictionary={}
var assignments: Dictionary={}
var attendance: Dictionary={}
var inventory: Dictionary={}
var receipts: Dictionary={}
var supply_receipts: Dictionary={}
var revenue: int=0
var notices: Dictionary={}
var mode: String="2d"

func configure(data: Dictionary,library: RefCounted) -> void:
	mode=data["mode"]
	sites=Plan.compile(data,library)

func reconcile(hour: float,day: int,rain: bool,service: RefCounted) -> bool:
	var wanted: Dictionary={}
	var areas: Array[Rect2]=[]
	var ids: Array=sites.keys()
	ids.sort()
	notices.clear()
	for uid in ids:
		var site: Dictionary=sites[uid]
		var cycle: Variant=Plan.active_cycle(site,hour,day,rain)
		if cycle==null:
			notices[uid]=site["problem"] if not site["problem"].is_empty() else "Closed for rain" if rain and site["config"]["close_in_rain"] else "Outside the event window"
			continue
		if areas.any(func(area: Rect2)->bool:return area.intersects(site["area"])):
			notices[uid]="Another open market uses this space."
			continue
		wanted[uid]={"site":site,"cycle":cycle}
		areas.append(site["area"])
	var changed: bool=false
	for uid in active.keys():
		if wanted.get(uid,{})!=active[uid]:
			close(uid,service)
			changed=true
	for uid in wanted:
		if active.has(uid): continue
		open_site(uid,wanted[uid])
		changed=true
	return changed

func open_site(uid: String,window: Dictionary) -> void:
	var site: Dictionary=window["site"]
	var cycle: int=window["cycle"]
	var policy: String=site["config"]["stock_policy"]
	var ledger: Dictionary=inventory_for(uid,cycle,policy)
	if cycle>ledger["cycle"]:
		ledger["cycle"]=cycle
		if policy!="delivery": ledger["stock"].clear()
		ledger["seen"].clear()
	for id in site["vendors"]:
		var vendor: Dictionary=site["vendors"][id].duplicate(true)
		ensure_stock(ledger,id,vendor,policy)
		vendor["queue_ids"]=[]
		vendor["checkout"]=""
		vendors[id]=vendor
		register_target(id+"/checkout",vendor["point"],vendor)
		register_target(id+"/exit",vendor["exit"],vendor)
		for slot in vendor["queue"].size(): register_target(id+"/queue/"+str(slot),vendor["queue"][slot],vendor)
	active[uid]=window

func inventory_for(uid: String,cycle: int,policy: String) -> Dictionary:
	if inventory.has(uid) and inventory[uid]["policy"]!=policy: inventory.erase(uid)
	if not inventory.has(uid):
		if inventory.size()>=MAX_SESSION_MARKETS:
			for retired in inventory:
				if not active.has(retired):
					inventory.erase(retired)
					break
		inventory[uid]={"cycle":cycle,"policy":policy,"stock":{},"seen":{}}
	return inventory[uid]

func ensure_stock(ledger: Dictionary,id: String,vendor: Dictionary,policy: String) -> Dictionary:
	var saved: Dictionary=ledger["stock"].get(id,{})
	var units: int=0 if policy=="delivery" else vendor["stock"]
	if saved.get("item")==vendor["item"]: units=mini(vendor["stock"],int(saved["count"]))
	var stock: Dictionary={"item":vendor["item"],"count":units}
	ledger["stock"][id]=stock
	return stock

func receive_delivery(receipt: Dictionary,day: int) -> int:
	var host: String=receipt["destination"]
	var ticket: String=receipt["id"]
	if receipt["goods"]!="produce" or not sites.has(host) or sites[host]["config"]["stock_policy"]!="delivery" or supply_receipts.has(ticket): return 0
	var ledger: Dictionary=inventory_for(host,day,"delivery")
	var remaining: int=receipt["quantity"]
	for id in sites[host]["vendors"]:
		var vendor: Dictionary=sites[host]["vendors"][id]
		var stock: Dictionary=ensure_stock(ledger,id,vendor,"delivery")
		var units: int=mini(remaining,vendor["stock"]-stock["count"])
		stock["count"]+=units
		remaining-=units
		if remaining==0: break
	supply_receipts[ticket]=int(receipt["quantity"])-remaining
	if supply_receipts.size()>MAX_RECEIPTS: supply_receipts.erase(supply_receipts.keys()[0])
	return supply_receipts[ticket]

func register_target(id: String,point: Vector2,vendor: Dictionary) -> void:
	var world: Array=Plan.Traffic.world(point,mode)
	var walk: Vector2=Vector2(world[0]/16,world[1]/8) if mode=="2d" else point
	targets[id]={"point":walk,"metric":point,"height":vendor.get("height",0),"name":vendor["name"],"role":"market","vendor":vendor["id"]}

func close(uid: String,service: RefCounted) -> void:
	var ids: Dictionary=active[uid]["site"]["vendors"]
	for visitor in service.visits.keys():
		if ids.has(service.visits[visitor]["business"]):
			service.cancel(visitor,"The market closed before this purchase settled.")
			service.depart(visitor)
	for visitor in assignments.keys():
		if ids.has(assignments[visitor]["vendor"]): assignments.erase(visitor)
	for id in targets.keys():
		if ids.has(targets[id]["vendor"]): targets.erase(id)
	for id in ids: vendors.erase(id)
	attendance.erase(uid)
	active.erase(uid)

func businesses() -> Dictionary:
	var result: Dictionary={}
	for vendor in vendors.values():
		var config: Dictionary={"kind":"market","open_hour":0.0,"close_hour":24.0,"capacity":1,"duration_scale":1.0,
			"market_action":{"id":"buy","label":"Buy · %d credits"%vendor["price"],"progress":"Checking out","item":vendor["item"],"seconds":2.0}}
		result[vendor["id"]]={"uid":vendor["id"],"name":vendor["name"],"config":config}
	return result

func count(id: String) -> int:
	var vendor: Dictionary=vendors[id]
	return -1 if vendor["creative"] else inventory.get(vendor["host"],{}).get("stock",{}).get(id,{}).get("count",0)

func people(host: String) -> int:
	return attendance.get(host,0)

func player_at_market(host: String,service: RefCounted) -> bool:
	var visit: Dictionary=service.visits.get("player",{})
	return visit.get("state","") in ["active","queued"] and vendors.get(visit.get("business",""),{}).get("host")==host

func before_purchase(id: String,visitor: String,service: RefCounted) -> String:
	if not vendors.has(id): return "Market is closed."
	if count(id)==0: return "Sold out for this market day."
	var vendor: Dictionary=vendors[id]
	if visitor=="player":
		if not vendor["checkout"].is_empty() or not vendor["queue_ids"].is_empty(): return "Wait for the resident queue to clear."
		if people(vendor["host"])>=active[vendor["host"]]["site"]["config"]["capacity"]: return "The market is at its visitor limit."
	elif vendor["checkout"]!=visitor:
		return "Wait for your turn at the marked checkout."
	return ""

func settle(visit: Dictionary) -> bool:
	var ticket: int=visit["sequence"]
	if receipts.has(ticket): return false
	var id: String=visit["business"]
	if not vendors.has(id) or count(id)==0: return false
	var vendor: Dictionary=vendors[id]
	if not vendor["creative"]: inventory[vendor["host"]]["stock"][id]["count"]-=1
	revenue+=int(vendor["price"])
	receipts[ticket]={"vendor":id,"visitor":visit["visitor"],"item":visit["item"],"paid":vendor["price"],"cycle":active[vendor["host"]]["cycle"]}
	if receipts.size()>MAX_RECEIPTS: receipts.erase(receipts.keys()[0])
	return true

func assign(visitor: String,point: Vector2,service: RefCounted) -> void:
	var best: float=64*64
	var choice: Dictionary={}
	for id in vendors:
		var vendor: Dictionary=vendors[id]
		var host: String=vendor["host"]
		if count(id)==0 or inventory[host]["seen"].has(visitor): continue
		if people(host)+int(player_at_market(host,service))>=active[host]["site"]["config"]["capacity"]: continue
		var visit: Dictionary=service.visits.get("player",{})
		var player_busy: bool=visit.get("business","")==id and visit.get("state","") in ["active","queued"]
		var direct: bool=not player_busy and vendor["checkout"].is_empty() and vendor["queue_ids"].is_empty()
		if not direct and vendor["queue_ids"].size()>=vendor["queue"].size(): continue
		var distance: float=point.distance_squared_to(vendor["point"])
		if distance>=best: continue
		best=distance
		choice={"vendor":id,"phase":"checkout" if direct else "queue"}
	if choice.is_empty(): return
	assignments[visitor]=choice
	var vendor: Dictionary=vendors[choice["vendor"]]
	attendance[vendor["host"]]=people(vendor["host"])+1
	if choice["phase"]=="checkout": vendor["checkout"]=visitor
	else: vendor["queue_ids"].append(visitor)

func depart(visitor: String,service: RefCounted) -> void:
	if not assignments.has(visitor): return
	var id: String=assignments[visitor]["vendor"]
	if vendors.has(id):
		var vendor: Dictionary=vendors[id]
		attendance[vendor["host"]]=maxi(0,people(vendor["host"])-1)
		vendor["queue_ids"].erase(visitor)
		if vendor["checkout"]==visitor: vendor["checkout"]=""
	if service.visits.get(visitor,{}).get("business","")==id: service.depart(visitor)
	assignments.erase(visitor)

func shopper_target(visitor: String,point: Vector2,wants_shop: bool,service: RefCounted) -> String:
	if not wants_shop:
		depart(visitor,service)
		return ""
	if not assignments.has(visitor): assign(visitor,point,service)
	if not assignments.has(visitor): return ""
	var entry: Dictionary=assignments[visitor]
	var id: String=entry["vendor"]
	var vendor: Dictionary=vendors[id]
	var visit: Dictionary=service.visits.get(visitor,{})
	if entry["phase"]=="checkout" and visit.get("business")==id and visit.get("state") in ["complete","cancelled"]:
		if visit["state"]=="complete":
			var seen: Dictionary=inventory[vendor["host"]]["seen"]
			seen[visitor]=true
			if seen.size()>256: seen.erase(seen.keys()[0])
		entry["phase"]="exit"
	if count(id)==0 and entry["phase"]!="exit" and not (visit.get("business")==id and visit.get("state")=="active"):
		if entry["phase"]=="queue":
			depart(visitor,service)
			return ""
		entry["phase"]="exit"
	if entry["phase"]=="exit":
		if point.distance_to(vendor["exit"])<=Plan.ARRIVAL_RADIUS:
			depart(visitor,service)
			return ""
		return id+"/exit"
	if entry["phase"]=="queue":
		var slot: int=vendor["queue_ids"].find(visitor)
		var player: Dictionary=service.visits.get("player",{})
		var player_busy: bool=player.get("business")==id and player.get("state","") in ["active","queued"]
		if slot==0 and vendor["checkout"].is_empty() and not player_busy and point.distance_to(vendor["queue"][0])<=Plan.ARRIVAL_RADIUS:
			vendor["queue_ids"].pop_front()
			vendor["checkout"]=visitor
			entry["phase"]="checkout"
		else: return id+"/queue/"+str(slot)
	return id+"/checkout"

func arrive(target: String,visitor: String,point: Vector2,height: float,hour: float,service: RefCounted) -> Dictionary:
	var station: Dictionary=targets.get(target,{})
	if station.is_empty() or point.distance_to(station["metric"])>Plan.ARRIVAL_RADIUS or absf(height-station["height"])>.65: return {}
	var id: String=station["vendor"]
	if not target.ends_with("/checkout"): return {"state":"queued","reason":"Waiting for a stall"}
	var prior: Dictionary=service.result(visitor)
	if prior.get("business")==id: return prior
	return service.request(id,visitor,"buy",hour).get("visit",{})

func walk_obstacles() -> Array[Rect2]:
	var result: Array[Rect2]=[]
	for vendor in vendors.values():
		var box: Rect2=vendor["stall"]
		if mode=="3d":
			result.append(box)
			continue
		var points:=PackedVector2Array()
		for point in [box.position,Vector2(box.end.x,box.position.y),box.end,Vector2(box.position.x,box.end.y)]:
			var world: Array=Plan.Traffic.world(point,mode)
			points.append(Vector2(world[0]/16,world[1]/8))
		result.append_array(preload("res://scripts/builder/citizen_obstacles_2d.gd").polygon(points))
	return result

func reset(service: RefCounted) -> void:
	for uid in active.keys(): close(uid,service)
	assignments.clear()
	attendance.clear()
	inventory.clear()
	receipts.clear()
	supply_receipts.clear()
	notices.clear()
	revenue=0
