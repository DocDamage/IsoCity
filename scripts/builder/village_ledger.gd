extends RefCounted

const Plan = preload("res://scripts/builder/village_plan.gd")
const WALK_SPEED = 3.2

var sites: Dictionary = {}
var account: Dictionary = {}
var batches: Dictionary = {}
var transfers: Dictionary = {}
var orders: Dictionary = {}
var states: Dictionary = {}
var wallet_enabled: bool = false
var sequence: int = 0
var latest: String = ""
var lost: Dictionary = {}

func reset(budget: bool = false) -> void:
	sites.clear()
	batches.clear()
	transfers.clear()
	orders.clear()
	states.clear()
	lost.clear()
	wallet_enabled = budget
	account = {"stock":{},"cash":30 if budget else -1,"receipts":{}}
	latest = ""

func ticket(kind: String) -> String:
	sequence += 1
	return "village/%d/%s/%d" % [get_instance_id(),kind,sequence]

func stock(uid: String, good: String) -> int:
	return int(account.get("stock",{}).get(Plan.key(uid,good),0))

func available(uid: String, good: String) -> int:
	var held: Dictionary = batches.get(uid,{}).get("inputs",{})
	return maxi(0,stock(uid,good)-int(held.get(good,0)))

func space(uid: String, stock_map: Dictionary, ignore: String = "") -> int:
	if not sites.has(uid): return 0
	var used: int = 0
	for good in Plan.goods(): used += int(stock_map.get(Plan.key(uid,good),0))
	for id in transfers:
		if id == ignore: continue
		var job: Dictionary = transfers[id]
		if job["source"] == uid or job["target"] == uid: used += job["quantity"]
	return int(sites[uid]["profile"]["capacity"])-used

func outbound(uid: String) -> Dictionary:
	for job in transfers.values():
		if job["source"] == uid: return job
	return {}

func capacity(key: String) -> int:
	var parts: Array = JSON.parse_string(key)
	return int(sites[parts[0]]["profile"]["capacity"]) if sites.has(parts[0]) else 0

func check_stock(values: Dictionary, ignore: String) -> String:
	for uid in sites:
		if space(uid,values,ignore) < 0: return "capacity"
	return ""

func exchange(id: String, changes: Dictionary, credits: int, details: Dictionary, ignore: String = "") -> Dictionary:
	return Plan.Stock.exchange(account,id,changes,credits,details,capacity,check_stock.bind(ignore),Plan.MAX_RECEIPTS)

func describe_error(update: Dictionary) -> String:
	return {"missing":"Required stock is missing.","capacity":"Storage is full.","balance":"The village preview wallet is short of credits."}.get(
		update.get("reason",""),"This transaction is unavailable.")

func configure(next: Dictionary, budget: bool) -> void:
	if account.is_empty(): reset(budget)
	if wallet_enabled != budget:
		wallet_enabled = budget
		account["cash"] = 30 if budget else -1
	var previous: Dictionary = sites
	sites = next
	for uid in previous:
		if sites.get(uid,{}).get("owner") == previous[uid]["owner"]: continue
		for good in Plan.goods():
			var amount: int = stock(uid,good)
			if amount > 0: note_loss(good,amount)
			account["stock"].erase(Plan.key(uid,good))
		batches.erase(uid)
		orders.erase(uid)
		states.erase(uid)
	for uid in batches.keys():
		var site: Dictionary = sites.get(uid,{})
		if site.is_empty() or not site["reason"].is_empty() or site["batch"] != batches[uid]["signature"]: batches.erase(uid)
	for id in transfers.keys():
		if not link_current(transfers[id]): cancel_transfer(id,"A facility or transfer route changed.")

func note_loss(good: String, amount: int) -> void:
	lost[good] = mini(Plan.Economy.LIMIT,int(lost.get(good,0))+amount)
	latest = "Removed facility stock was cleared."

func link_signature(source: Dictionary, target: Dictionary) -> Array:
	return [source["owner"],target["owner"],source["batch"],target["batch"],source["link"]]

func link_current(job: Dictionary) -> bool:
	var from: Dictionary = sites.get(job["source"],{})
	var to: Dictionary = sites.get(job["target"],{})
	return not from.is_empty() and not to.is_empty() and from["link"]["reason"].is_empty() and link_signature(from,to) == job["signature"]

func failure(reason: String) -> Dictionary:
	return {"ok":false,"reason":reason}

func begin_transfer(id: String, uid: String, transport: String) -> Dictionary:
	var from: Dictionary = sites.get(uid,{})
	if from.is_empty(): return failure("The pickup facility is unavailable.")
	var link: Dictionary = from["link"]
	if not link["reason"].is_empty(): return failure(link["reason"])
	if transport != link["transport"]: return failure("Use the authored transfer method.")
	if transfers.has(id) or account["receipts"].has(id+"/depart"): return failure("This transfer was already dispatched.")
	if transfers.size() >= Plan.MAX_TRANSFERS or not outbound(uid).is_empty(): return failure("Transfer backlog is full.")
	var target: String = link["target"]
	var good: String = link["good"]
	if available(uid,good) < Plan.QUANTITY: return failure("Waiting for %d %s." % [Plan.QUANTITY,Plan.title(good).to_lower()])
	if space(target,account["stock"]) < Plan.QUANTITY: return failure("Destination storage is full.")
	var debit: Dictionary = exchange(id+"/depart",{Plan.key(uid,good):-Plan.QUANTITY},0,{"kind":"dispatch","site":uid})
	if not debit["ok"] or debit["replayed"]: return failure(describe_error(debit))
	account = debit["account"]
	var path: PackedVector2Array = link["path"]
	transfers[id] = {"id":id,"source":uid,"target":target,"good":good,"quantity":Plan.QUANTITY,"transport":transport,
		"source_owner":from["owner"],"signature":link_signature(from,sites[target]),"path":path,
		"length":Plan.Traffic.length(path),"distance":0.0}
	latest = "%s dispatched." % Plan.title(good)
	return {"ok":true,"reason":""}

func cancel_transfer(id: String, message: String) -> void:
	var job: Dictionary = transfers.get(id,{})
	if job.is_empty(): return
	var source: String = job["source"]
	transfers.erase(id)
	if sites.get(source,{}).get("owner") == job["source_owner"]:
		var returned: Dictionary = exchange(id+"/return",{Plan.key(source,job["good"]):job["quantity"]},0,
			{"kind":"return","site":source,"goods":job["good"]})
		if returned["ok"]:
			account = returned["account"]
			latest = message+" Cargo returned."
			return
	note_loss(job["good"],job["quantity"])
	latest = message+" Pickup stock was cleared."

func complete_transfer(id: String) -> Dictionary:
	var prior: Dictionary = account["receipts"].get(id+"/arrive",{})
	if not prior.is_empty(): return prior.duplicate(true)
	var job: Dictionary = transfers.get(id,{})
	if job.is_empty(): return failure("No active transfer.")
	if not link_current(job):
		cancel_transfer(id,"The destination changed.")
		return failure("The destination changed.")
	if job["transport"] == "porter" and job["distance"]+.001 < job["length"]: return failure("Cargo is still travelling.")
	var destination: String = job["target"]
	var good: String = job["good"]
	var update: Dictionary = exchange(id+"/arrive",{Plan.key(destination,good):job["quantity"]},0,
		{"kind":"delivery","site":destination,"source":job["source"],"goods":good,"quantity":job["quantity"]},id)
	if not update["ok"]: return failure(describe_error(update))
	account = update["account"]
	transfers.erase(id)
	if sites[destination]["profile"]["role"] == "market":
		if not orders.has(destination): orders[destination] = []
		orders[destination].append({"id":id+"/sale","goods":good,"quantity":job["quantity"]})
	latest = "%d %s delivered to %s." % [job["quantity"],Plan.title(good).to_lower(),sites[destination]["name"]]
	return update["receipt"]

func order(uid: String) -> Dictionary:
	var queue: Array = orders.get(uid,[])
	return queue.front() if not queue.is_empty() else {}

func sell(uid: String, id: String) -> Dictionary:
	var prior: Dictionary = account["receipts"].get(id,{})
	if prior.get("site") == uid and prior.get("kind") == "sale": return prior.duplicate(true)
	var site: Dictionary = sites.get(uid,{})
	var offer: Dictionary = order(uid)
	if site.is_empty() or not site["reason"].is_empty() or offer.get("id","") != id or offer.is_empty():
		return failure("No sale is ready.")
	var good: String = offer["goods"]
	var quantity: int = offer["quantity"]
	var update: Dictionary = exchange(id,{Plan.key(uid,good):-quantity},quantity*int(Plan.goods()[good]["price"]),
		{"kind":"sale","site":uid,"goods":good,"quantity":quantity})
	if not update["ok"]: return failure(describe_error(update))
	account = update["account"]
	orders[uid].pop_front()
	latest = "Sold %d %s." % [quantity,Plan.title(good).to_lower()]
	return update["receipt"]

func supply(uid: String, goods: Dictionary, cost: int) -> Dictionary:
	var changes: Dictionary = {}
	for good in goods: changes[Plan.key(uid,good)] = goods[good]
	var update: Dictionary = exchange(ticket("supply"),changes,-cost,{"kind":"supply","site":uid})
	if not update["ok"]: return failure(describe_error(update))
	account = update["account"]
	return update["receipt"]

func tick(delta: float, season: String) -> void:
	for id in transfers.keys():
		var job: Dictionary = transfers[id]
		if job["transport"] != "porter": continue
		job["distance"] = minf(job["length"],job["distance"]+delta*WALK_SPEED)
		if job["distance"]+.0001 >= job["length"]: complete_transfer(id)
	for uid in sites:
		var site: Dictionary = sites[uid]
		var recipe: Dictionary = Plan.definitions()["recipes"].get(site["config"]["recipe"],{})
		states[uid] = batch_tick(uid,site,recipe,delta,season)
		var route: Dictionary = site["link"]
		if not route["reason"].is_empty() or route["transport"] != "porter" or not outbound(uid).is_empty(): continue
		if available(uid,route["good"]) >= Plan.QUANTITY and space(route["target"],account["stock"]) >= Plan.QUANTITY:
			begin_transfer(ticket("porter"),uid,"porter")

func batch_tick(uid: String, site: Dictionary, recipe: Dictionary, delta: float, season: String) -> String:
	if not site["reason"].is_empty(): return site["reason"]
	if recipe.is_empty(): return "Sale ready." if not order(uid).is_empty() else "Waiting for deliveries."
	if recipe.has("seasons") and season not in recipe["seasons"]: return "Farm dormant in "+season+"."
	for good in recipe["inputs"]:
		if stock(uid,good) < int(recipe["inputs"][good]): return "Needs "+Plan.title(good).to_lower()+"."
	var changes: Dictionary = {}
	var net: int = recipe["yield"]
	for good in recipe["inputs"]:
		changes[Plan.key(uid,good)] = -int(recipe["inputs"][good])
		net -= int(recipe["inputs"][good])
	if space(uid,account["stock"]) < net: return "Output storage is full."
	if not batches.has(uid):
		batches[uid] = {"id":ticket("batch"),"signature":site["batch"],"elapsed":0.0,"inputs":recipe["inputs"]}
	var batch: Dictionary = batches[uid]
	batch["elapsed"] += delta
	if batch["elapsed"]+.0001 < recipe["seconds"]:
		return "%s · %d%%" % [recipe["name"],int(100*batch["elapsed"]/recipe["seconds"])]
	var output: String = recipe["output"]
	changes[Plan.key(uid,output)] = int(recipe["yield"])
	var update: Dictionary = exchange(batch["id"],changes,0,{"kind":"batch","site":uid,"goods":output,"quantity":recipe["yield"]})
	if not update["ok"]: return describe_error(update)
	account = update["account"]
	batches.erase(uid)
	return "%d %s ready." % [recipe["yield"],Plan.title(output).to_lower()]
