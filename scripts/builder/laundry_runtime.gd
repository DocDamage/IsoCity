extends Node

const Plan = preload("res://scripts/builder/laundry_plan.gd")
const Props = preload("res://scripts/builder/prop_plan.gd")
const Utility = preload("res://scripts/builder/utility_profiles.gd")
const Floors = preload("res://scripts/builder/floor_plan.gd")
const Reservations = preload("res://scripts/builder/activity_reservations.gd")
const Stock = preload("res://scripts/builder/activity_stock.gd")
const View = preload("res://scripts/builder/laundry_view.gd")

var exploration: Node
var authored_root: Callable
var source: Dictionary = {}
var facilities: Dictionary = {}
var sequence: int = 0
var queue_sequence: int = 0
var elapsed: float = 0
var notice: String = ""
var notice_seconds: float = 0
var counter: Dictionary = {}
var view: RefCounted
var panel_area := Rect2()
var ui_scale: float = 1.0
var large_targets: bool = false
var high_contrast: bool = false
var effects = preload("res://scripts/builder/prop_effects.gd").new()

func root_data() -> Dictionary:
	return authored_root.call() if authored_root.is_valid() else source

func configure(data: Dictionary) -> void:
	source = data
	if not facilities.is_empty() and not Plan.enabled(root_data()): reset()

func active() -> bool:
	return Plan.enabled(root_data()) and exploration.enabled and not exploration.entering \
		and not exploration.photo.active

func manages(item: Dictionary) -> bool:
	return Plan.enabled(root_data()) and not Plan.station(item).is_empty()

func station_list(data: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for item in data.get("objects", []):
		var setting: Dictionary = Plan.station(item)
		if setting.is_empty() or not Utility.availability(item, exploration.library, data).is_empty(): continue
		result[item["uid"]] = {"item": item, "setting": setting, "identity": Plan.identity(item)}
		if result.size() == Plan.MAX_STATIONS: break
	return result

func local_candidate(station: Dictionary, context: Dictionary) -> Dictionary:
	var node: Node = context["instances"].get(station["item"]["uid"])
	if not is_instance_valid(node) or not node.is_visible_in_tree(): return {}
	var candidate: Dictionary = context.duplicate()
	candidate.merge(station)
	candidate["node"] = node
	var profile: Dictionary = Props.profile(station["item"])
	if profile.get("kind", "") != "appliance":
		profile = Props.definitions()["kinds"]["appliance"].duplicate()
		profile["kind"] = "appliance"
	candidate["profile"] = profile
	return candidate

func approach(candidate: Dictionary) -> Dictionary:
	var node: Node = candidate["node"]
	var player: Node = exploration.player
	var bounds: Rect2 = Utility.footprint(candidate["item"], exploration.library, exploration.dimension)
	var best: Dictionary = {}
	for side in Utility.SIDES:
		var edge: Vector2 = Utility.side_point(bounds, side, .65)
		var at: Array = Utility.Traffic.world(edge, exploration.dimension)
		var point: Variant = node.get_parent().to_global(Vector2(at[0], at[1])) if exploration.dimension == "2d" \
			else node.get_parent().to_global(Vector3(at[0], node.position.y, at[2]))
		var gap: Variant = point - player.global_position
		var distance: float = gap.length()
		if exploration.dimension == "2d":
			var height: float = candidate["item"]["position"][2] + node.get_meta("terrain_height", 0)
			if absf(height - float(player.get_meta("terrain_height", 0))) > 1.2 or Vector2(gap.x/8, gap.y/4).length() > 2.35: continue
		elif absf(gap.y) > 1.1 or Vector2(gap.x, gap.z).length() > 2.0:
			continue
		if distance >= best.get("distance", INF) or not Props.reachable(exploration, node, point): continue
		best = {"distance": distance, "point": point}
	return best

func can_interact() -> bool:
	return active() and is_instance_valid(exploration.player) and exploration.driving.active.is_empty()

func nearby() -> Dictionary:
	if not can_interact(): return {}
	var context: Dictionary = Props.context(exploration)
	var best: Dictionary = {}
	for station in station_list(context["data"]).values():
		if station["setting"]["role"] == "basket": continue
		var candidate: Dictionary = local_candidate(station, context)
		if candidate.is_empty(): continue
		var landing: Dictionary = approach(candidate)
		if landing.is_empty() or landing["distance"] >= best.get("distance", INF): continue
		best = candidate
		best.merge(landing)
	return best

func at_station(uid: String) -> Dictionary:
	if not can_interact(): return {}
	var context: Dictionary = Props.context(exploration)
	var station: Dictionary = station_list(context["data"]).get(uid, {})
	if station.is_empty(): return {}
	var candidate: Dictionary = local_candidate(station, context)
	if candidate.is_empty() or approach(candidate).is_empty(): return {}
	return candidate

func facility(context: Dictionary) -> Dictionary:
	var scope: String = context["scope"]
	if not facilities.has(scope):
		if facilities.size() >= Plan.MAX_FACILITIES: return {}
		facilities[scope] = {"scope": scope, "host": exploration.interior_uid,
			"floor": exploration.active_floor() if exploration.interior else "", "orders": {}, "off": {},
			"account": Plan.fresh_account(), "last_receipt": {}}
	return facilities[scope]

func get_facility(scope: String) -> Dictionary:
	return facilities.get(scope, {})

func facility_data(site: Dictionary) -> Dictionary:
	var data: Dictionary = root_data()
	if site["host"].is_empty(): return data
	for host in data.get("objects", []):
		if host["uid"] != site["host"]: continue
		if not Utility.availability(host, exploration.library, data).is_empty(): return {}
		return Floors.room(host.get("interior", {}), site["floor"])
	return {}

func say(text: String, ok: bool = true) -> Dictionary:
	notice = text
	notice_seconds = 5
	return {"ok": ok, "reason": text}

func prompt(candidate: Dictionary) -> String:
	var role: String = candidate["setting"]["role"]
	var site: Dictionary = get_facility(candidate["scope"])
	var title: String = {"counter": "Laundry orders", "fold": "Fold the next dry load", "supply": "Restock detergent"}.get(role, "")
	if role == "counter" and counter.get("uid") == candidate["item"]["uid"] and counter.get("scope") == candidate["scope"]:
		return "E · Close laundry counter"
	if role in Plan.MACHINES:
		var machine: String = "washer and dryer" if candidate["setting"]["dual"] else ("washer" if role == "wash" else "dryer")
		var running: String = "Switch on" if is_off(site, candidate) else "Switch off"
		title = "%s %s · %d items" % [running, machine, candidate["setting"]["capacity"]]
		for order in site.get("orders", {}).values():
			if order["station"] == candidate["item"]["uid"]:
				title += " · #%d %s %.0f s" % [order["number"], order["stage"].capitalize(), ceilf(order["remaining"])]
				break
	return "E · " + title + (" · " + notice if notice_seconds > 0 else "")

func interact(uid: String) -> Dictionary:
	var candidate: Dictionary = at_station(uid)
	if candidate.is_empty(): return say("Approach a laundry station first.", false)
	var site: Dictionary = facility(candidate)
	if site.is_empty(): return say("The laundry preview has reached its facility limit.", false)
	var role: String = candidate["setting"]["role"]
	match role:
		"counter":
			if counter.get("uid") == uid and counter.get("scope") == site["scope"]:
				close_counter()
				return {"ok": true}
			counter = {"uid": uid, "scope": site["scope"], "identity": candidate["identity"]}
			if view == null: view = View.new(self)
			view.refresh(true)
		"supply":
			site["account"]["stock"]["detergent"] = Plan.detergent_capacity("detergent")
			return say("Detergent restocked.")
		"fold":
			var queued: Array = queue(site, "fold")
			if queued.is_empty(): return say("No dry loads are waiting to be folded.", false)
			if not assign(site, queued[0], candidate): return say("This folding table is occupied.", false)
			return say("Folding order #%d. Stay at the table." % queued[0]["number"])
		_:
			if is_off(site, candidate):
				site["off"].erase(uid)
				return say("Machine switched on.")
			site["off"][uid] = candidate["identity"]
			for order in site["orders"].values():
				if order["station"] == uid: interrupt(order, "Machine switched off.")
			return say("Machine switched off.")
	return {"ok": true}

func counter_site() -> Dictionary:
	if counter.is_empty(): return {}
	var candidate: Dictionary = at_station(counter["uid"])
	if candidate.is_empty() or candidate["scope"] != counter["scope"] or candidate["identity"] != counter["identity"] \
		or candidate["setting"]["role"] != "counter": return {}
	return get_facility(counter["scope"])

func close_counter() -> void:
	counter.clear()
	if view: view.hide()

func has_role(stations: Dictionary, role: String, size: int = 1) -> bool:
	for station in stations.values():
		if Plan.accepts(station["setting"], role) and station["setting"]["capacity"] >= size: return true
	return false

func exchange(site: Dictionary, id: String, amount: int, details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = Stock.exchange(site["account"], id, {"detergent": amount} if amount else {}, 0,
		details, Plan.detergent_capacity, Callable(), Plan.RECEIPT_LIMIT)
	if result["ok"]: site["account"] = result["account"]
	return result

func receive(customer: String) -> Dictionary:
	var site: Dictionary = counter_site()
	if site.is_empty(): return say("Open the laundry counter while standing nearby.", false)
	var request: Dictionary = Plan.customers().get(customer, {})
	if request.is_empty(): return say("This customer has no laundry request.", false)
	if site["orders"].size() >= Plan.MAX_ORDERS: return say("The order queue is full.", false)
	for existing in site["orders"].values():
		if existing["customer"] == customer: return say("This customer already has a load here.", false)
	var stations: Dictionary = station_list(facility_data(site))
	if not has_role(stations, "basket") or not has_role(stations, "supply") or not has_role(stations, "fold"):
		return say("Set up a basket, detergent station and folding table on this floor.", false)
	var size: int = request["items"].size()
	if not has_role(stations, "wash", size) or not has_role(stations, "dry", size):
		return say("This %d-item load needs a washer and dryer that both fit it." % size, false)
	if site["account"]["stock"]["detergent"] <= reserved_detergent(site):
		return say("The detergent station needs a refill before accepting this order.", false)
	sequence += 1
	var id: String = "laundry/%d" % sequence
	var items: Array[Dictionary] = []
	for name_text in request["items"]:
		items.append({"id": "%s/item/%d" % [id, items.size()+1], "name": name_text})
	var order: Dictionary = {"id": id, "number": sequence, "customer": customer, "items": items, "stage": "wash",
		"station": "", "locks": [], "condition": "Dirty", "detergent_used": false, "wait": "", "remaining": 0.0}
	enqueue(order, "wash")
	site["orders"][id] = order
	return say("Received %s’s %d items · #%d." % [request["name"], size, sequence])

func reserved_detergent(site: Dictionary) -> int:
	var count: int = 0
	for order in site["orders"].values():
		if not order["detergent_used"]: count += 1
	return count

func return_load(id: String, customer: String, cancel: bool = false) -> Dictionary:
	var site: Dictionary = counter_site()
	if site.is_empty(): return say("Return loads at their laundry counter.", false)
	var order: Dictionary = site["orders"].get(id, {})
	if order.is_empty(): return say("That ticket is no longer active.", false)
	if order["customer"] != customer: return say("The claim ticket belongs to another customer.", false)
	if not cancel and order["stage"] != "return": return say("The load still needs to be washed, dried and folded.", false)
	var result: Dictionary = exchange(site, id, 0, {"customer": customer, "items": order["items"].duplicate(true),
		"condition": order["condition"], "state": "cancelled" if cancel else "completed"})
	if not result["ok"]: return say("This laundry return could not be recorded.", false)
	release(order)
	site["orders"].erase(id)
	var receipt: Dictionary = result["receipt"]
	site["last_receipt"] = receipt
	var who: String = Plan.customers()[customer]["name"]
	var response: Dictionary = say(("Cancelled #%d · returned %s items to %s." % [order["number"], order["condition"].to_lower(), who])
		if cancel else ("Receipt #%d · %s collected %d clean items." % [order["number"], who, order["items"].size()]))
	response["receipt"] = receipt.duplicate(true)
	return response

func enqueue(order: Dictionary, stage: String) -> void:
	queue_sequence += 1
	order["stage"] = stage
	order["queue"] = queue_sequence
	order["wait"] = ""

func queue(site: Dictionary, stage: String) -> Array:
	var result: Array = []
	for order in site["orders"].values():
		if order["stage"] == stage and order["station"].is_empty(): result.append(order)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["queue"] < b["queue"])
	return result

func is_off(site: Dictionary, station: Dictionary) -> bool:
	return site.get("off", {}).get(station["item"]["uid"], []) == station["identity"]

func utility_reason(site: Dictionary, station: Dictionary, stage: String) -> String:
	var uid: String = site["host"] if not site["host"].is_empty() else station["item"]["uid"]
	if station["setting"]["power"] and not supply_ready(exploration.power, uid):
		return "Waiting for electricity."
	if stage == "wash" and station["setting"]["water"] and not supply_ready(exploration.garden.water_network, uid):
		return "Waiting for water."
	return ""

func supply_ready(network: Node, uid: String) -> bool:
	if not is_instance_valid(network) or not network.graph.get("enabled", false): return true
	var load_node: Dictionary = network.graph["nodes"].get(uid, {})
	return load_node.get("role") == "consumer" and load_node.get("reason", "").is_empty() \
		and not network.forecast and network.served(uid) >= load_node["quantity"]

func assign(site: Dictionary, order: Dictionary, station: Dictionary) -> bool:
	if not order["station"].is_empty(): return false
	var uid: String = station["item"]["uid"]
	var key: String = site["scope"] + uid
	var world: Node = exploration.get_parent()
	var contexts: Array[Node] = [world]
	if Props.scope(exploration) == site["scope"]:
		var local: Node = Props.context(exploration)["world"]
		if local != world: contexts.append(local)
	for location in contexts:
		var registry: RefCounted = Reservations.for_world(location)
		var token: int = registry.acquire(key, self)
		if not token:
			release(order)
			return false
		order["locks"].append({"registry": registry, "key": key, "token": token})
	if order["stage"] == "wash" and not order["detergent_used"]:
		if not exchange(site, order["id"] + "/wash", -1)["ok"]:
			release(order)
			return false
		order["detergent_used"] = true
	order["station"] = uid
	order["identity"] = station["identity"]
	order["remaining"] = float(Plan.definitions()["seconds"][order["stage"]])
	order["wait"] = ""
	return true

func release(order: Dictionary) -> void:
	for lock in order["locks"]: lock["registry"].release(lock["key"], lock["token"])
	order["locks"].clear()
	effects.release(order["id"])
	order["station"] = ""
	order["remaining"] = 0.0

func interrupt(order: Dictionary, reason: String) -> void:
	release(order)
	order["wait"] = reason

func advance_site(site: Dictionary, delta: float) -> void:
	var stations: Dictionary = station_list(facility_data(site))
	for uid in site["off"].keys():
		if not stations.has(uid) or not is_off(site, stations[uid]): site["off"].erase(uid)
	for order in site["orders"].values():
		if order["station"].is_empty(): continue
		var stage: String = order["stage"]
		var station: Dictionary = stations.get(order["station"], {})
		var reason: String
		if station.is_empty() or station["identity"] != order["identity"] or not Plan.accepts(station["setting"], stage):
			reason = "Station moved or removed."
		elif stage in Plan.MACHINES and station["setting"]["capacity"] < order["items"].size():
			reason = "This machine no longer fits the load."
		elif stage == "fold" and (Props.scope(exploration) != site["scope"] or at_station(order["station"]).is_empty()):
			reason = "Return to the table to fold this load."
		else:
			reason = utility_reason(site, station, stage)
		if not reason.is_empty():
			interrupt(order, reason)
			continue
		order["remaining"] = maxf(0, order["remaining"] - delta)
		if order["remaining"] > 0: continue
		release(order)
		order["condition"] = {"wash": "Wet", "dry": "Dry", "fold": "Folded"}[stage]
		enqueue(order, {"wash": "dry", "dry": "fold", "fold": "return"}[stage])
	dispatch(site, stations)

func dispatch(site: Dictionary, stations: Dictionary) -> void:
	# First compatible load in each queue. Use the smallest fitting machine so
	# a small order leaves a larger machine available for the next large load.
	var sorted: Array = stations.values()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["setting"]["capacity"] == b["setting"]["capacity"]: return a["item"]["uid"] < b["item"]["uid"]
		return a["setting"]["capacity"] < b["setting"]["capacity"])
	var pending: Array = queue(site, "wash") + queue(site, "dry")
	pending.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["queue"] < b["queue"])
	for order in pending:
		var stage: String = order["stage"]
		var reason: String = "No %s fits this load." % ("washer" if stage == "wash" else "dryer")
		for station in sorted:
			if not Plan.accepts(station["setting"], stage) or station["setting"]["capacity"] < order["items"].size(): continue
			if is_off(site, station):
				reason = "Waiting for a machine to be switched on."
				continue
			var supply: String = utility_reason(site, station, stage)
			if not supply.is_empty():
				reason = supply
				continue
			if assign(site, order, station): break
			reason = "Waiting for an available machine."
		if order["station"].is_empty(): order["wait"] = reason

func sync_effects() -> void:
	var context: Dictionary = Props.context(exploration)
	var site: Dictionary = get_facility(context["scope"])
	var stations: Dictionary = station_list(context["data"])
	var shown: Dictionary = {}
	for order in site.get("orders", {}).values():
		if order["station"].is_empty() or not stations.has(order["station"]): continue
		var candidate: Dictionary = local_candidate(stations[order["station"]], context)
		if candidate.is_empty(): continue
		shown[order["id"]] = true
		effects.apply(order["id"], candidate, exploration, true, "#%d %s" % [order["number"], order["stage"].capitalize()])
	for key in effects.entries.keys():
		if not shown.has(key): effects.release(key)

func advance(delta: float) -> void:
	if not active():
		close_counter()
		effects.reset()
		return
	notice_seconds = maxf(0, notice_seconds - delta)
	for site in facilities.values(): advance_site(site, delta)
	if not facilities.is_empty(): sync_effects()
	if not counter.is_empty():
		if counter_site().is_empty(): close_counter()
		elif view: view.refresh()

func _physics_process(delta: float) -> void:
	if facilities.is_empty(): return
	elapsed += delta
	if elapsed < .15: return
	var step: float = minf(elapsed, .25)
	elapsed = 0.0
	advance(step)

func reset() -> void:
	close_counter()
	for site in facilities.values():
		for order in site["orders"].values(): release(order)
	facilities.clear()
	notice = ""
	notice_seconds = 0
	elapsed = 0
	effects.reset()
