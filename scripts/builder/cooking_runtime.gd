extends Node

signal menu_changed

const Plan = preload("res://scripts/builder/cooking_plan.gd")
const Props = preload("res://scripts/builder/prop_plan.gd")
const Utility = preload("res://scripts/builder/utility_profiles.gd")
const Traffic = preload("res://scripts/builder/traffic_plan.gd")
const Floors = preload("res://scripts/builder/floor_plan.gd")
const Reservations = preload("res://scripts/builder/activity_reservations.gd")
const MAX_KITCHENS = 64
const MAX_COOKS = 8
const WAIT_SECONDS = 24.0

var exploration: Node
var authored_root: Callable
var source: Dictionary = {}
var kitchens: Dictionary = {}
var jobs: Dictionary = {}
var sequence: int = 0
var notice: String = ""
var notice_time: float = 0.0
var effects = preload("res://scripts/builder/prop_effects.gd").new()

func root_data() -> Dictionary:
	return authored_root.call() if authored_root.is_valid() else source

func configure(data: Dictionary) -> void:
	source = data
	if not Plan.enabled(root_data()) and not jobs.is_empty(): cancel_all("Cooking was disabled.")
	if not kitchens.is_empty(): menu_changed.emit()

func active() -> bool:
	return exploration.enabled and not exploration.entering and not exploration.photo.active \
		and exploration.driving.active.is_empty() and Plan.enabled(root_data())

func manages(item: Dictionary) -> bool:
	return Plan.enabled(root_data()) and not Plan.station(item).is_empty() and Plan.profile(item)["role"] == "cook"

func station_list(context: Dictionary) -> Dictionary:
	var stations: Dictionary = {}
	for item in context["data"].get("objects",[]):
		var config: Dictionary = Plan.station(item)
		if config.is_empty(): continue
		var node: Node = context["instances"].get(item["uid"])
		if not is_instance_valid(node) or not node.is_visible_in_tree() or not Utility.availability(item,exploration.library,context["data"]).is_empty():
			continue
		var candidate: Dictionary = context.duplicate()
		candidate.merge({"item":item,"node":node,"setting":config,"role":Plan.profile(item)["role"],
			"bounds":Utility.footprint(item,exploration.library,exploration.dimension)})
		stations[item["uid"]] = candidate
		if stations.size() == Plan.MAX_STATIONS: break
	return stations

func approach(candidate: Dictionary, actor: Node) -> Dictionary:
	var node: Node = candidate["node"]
	var bounds: Rect2 = candidate["bounds"]
	var best: Dictionary = {}
	var distance: float = INF
	for side in Utility.SIDES:
		var edge: Vector2 = Utility.side_point(bounds,side,.65)
		var at: Array = Traffic.world(edge,exploration.dimension)
		var point: Variant = node.get_parent().to_global(Vector2(at[0],at[1])) if exploration.dimension == "2d" \
			else node.get_parent().to_global(Vector3(at[0],node.position.y,at[2]))
		var gap: Variant = point-actor.global_position
		var d: float = gap.length()
		if exploration.dimension == "2d":
			if Vector2(gap.x/8,gap.y/4).length() > 2.35: continue
		elif absf(gap.y) > 1.1 or Vector2(gap.x,gap.z).length() > 2.0:
			continue
		if d >= distance or not Props.reachable(exploration,node,point,actor): continue
		distance = d
		best = {"distance":d,"point":point}
	return best

func nearby() -> Dictionary:
	if not active(): return {}
	var context: Dictionary = Props.context(exploration)
	var stations: Dictionary = station_list(context)
	var best: Dictionary = {}
	var distance: float = INF
	for candidate in stations.values():
		if candidate["role"] == "utensil": continue
		var landing: Dictionary = approach(candidate,exploration.player)
		if landing.is_empty() or landing["distance"] >= distance: continue
		distance = landing["distance"]
		best = candidate
		best.merge(landing)
	return best

func player_job() -> Dictionary:
	return jobs.get(exploration.player.get_instance_id(),{}) if is_instance_valid(exploration.player) else {}

func prompt(candidate: Dictionary = {}) -> String:
	var job: Dictionary = player_job()
	if not job.is_empty():
		var name_text: String = Plan.recipes()[job["recipe"]]["name"]
		if job["phase"] in Plan.ACTIVE:
			var stage: String = {"preparing":"Preparing","cooking":"Cooking","plating":"Plating"}[job["phase"]]
			return "E · Cancel · %s %s · %.1f s" % [stage,name_text.to_lower(),job["remaining"]]
		var target: String = "stove" if job["phase"] == "prepared" else "serving counter"
		var next: String = "%s ready · go to the %s" % [name_text,target]
		if not candidate.is_empty():
			if candidate["role"] == "cook" and target == "stove": next = "E · Cook " + name_text.to_lower()
			if candidate["role"] == "serve" and target == "serving counter": next = "E · Plate " + name_text.to_lower()
		return next + (" · "+notice if notice_time > 0.0 else "")
	if candidate.is_empty(): return notice if notice_time > 0.0 else ""
	var role: String = candidate["role"]
	var name_text: String = Plan.recipes()[candidate["setting"].get("recipe",Plan.DEFAULT_RECIPE)]["name"]
	var action: String = {"prep":"Prepare "+name_text.to_lower(),"cook":"Start at the preparation station",
		"serve":"Plate a cooked batch here","pantry":"Restock kitchen ingredients"}.get(role,"Kitchen utensil")
	return "E · "+action+(" · "+notice if notice_time > 0.0 else "")

func report(text: String, ok: bool = true) -> Dictionary:
	notice = text
	notice_time = 4.0
	return {"ok":ok,"reason":text}

func ticket() -> String:
	sequence += 1
	return "kitchen/%d" % sequence

func kitchen(context: Dictionary) -> Dictionary:
	var scope: String = context["scope"]
	if not kitchens.has(scope):
		if kitchens.size() >= MAX_KITCHENS: return {}
		kitchens[scope] = {"account":Plan.fresh_stock(),"owner":exploration.interior_uid if exploration.interior else "",
			"floor":exploration.active_floor() if exploration.interior else "ground","counter":"","identity":""}
	return kitchens[scope]

func stock_for(scope: String) -> Dictionary:
	return kitchens.get(scope,{}).get("account",{}).get("stock",{}).duplicate()

func exchange(entry: Dictionary, id: String, changes: Dictionary, details: Dictionary, held: Dictionary = {}) -> Dictionary:
	var result: Dictionary = Plan.exchange(entry["account"],id,changes,details,held)
	if result["ok"]: entry["account"] = result["account"]
	return result

func tool_for(stove: Dictionary, stations: Dictionary, kind: String) -> String:
	if Plan.profile(stove["item"]).get("tool","") == kind: return stove["item"]["uid"]
	for candidate in stations.values():
		if candidate["role"] != "utensil" or Plan.profile(candidate["item"]).get("tool","") != kind: continue
		if candidate["bounds"].get_center().distance_to(stove["bounds"].get_center()) <= 5.0:
			return candidate["item"]["uid"]
	return ""

func power_reason(candidate: Dictionary) -> String:
	var network: Node = exploration.power
	if not candidate["setting"].get("power",false) or not is_instance_valid(network) or not network.graph.get("enabled",false): return ""
	var uid: String = exploration.interior_uid if exploration.interior else candidate["item"]["uid"]
	var consumer: Dictionary = network.graph["nodes"].get(uid,{})
	if consumer.get("role","") != "consumer": return "Connect the kitchen to the power network."
	if network.served(uid) < consumer["quantity"]: return "The stove has no electricity."
	return ""

func reserve(candidate: Dictionary) -> Array:
	var locks: Array = []
	var world: Node = candidate["world"]
	var root: Node = exploration.get_parent()
	var key: String = candidate["scope"]+candidate["item"]["uid"]
	for location in ([world] if world == root else [root,world]):
		var registry: RefCounted = Reservations.for_world(location)
		var token: int = registry.acquire(key,self)
		if token == 0:
			release(locks)
			return []
		locks.append({"registry":registry,"key":key,"token":token})
	return locks

func release(locks: Array) -> void:
	for lock in locks: lock["registry"].release(lock["key"],lock["token"])

func interact(uid: String) -> Dictionary:
	var job: Dictionary = player_job()
	if not job.is_empty() and job["phase"] in Plan.ACTIVE:
		cancel(exploration.player.get_instance_id(),"Cooking action cancelled.")
		return {"ok":true}
	return request(exploration.player,uid)

func request(actor: Node, uid: String) -> Dictionary:
	if not active() or not is_instance_valid(actor): return report("Enter Walk to use the kitchen.",false)
	var context: Dictionary = Props.context(exploration)
	var stations: Dictionary = station_list(context)
	var candidate: Dictionary = stations.get(uid,{})
	if candidate.is_empty() or approach(candidate,actor).is_empty(): return report("Move to the station's accessible side.",false)
	var key: int = actor.get_instance_id()
	var job: Dictionary = jobs.get(key,{})
	var role: String = candidate["role"]
	if role == "pantry": return restock(context)
	if role == "utensil": return report("Keep this pan beside the stove.",false)
	if job.is_empty():
		if role != "prep": return report("Start at a preparation station.",false)
		if jobs.size() >= MAX_COOKS: return report("The kitchen has reached its cook limit.",false)
		return start_prep(actor,candidate,stations)
	if job["scope"] != context["scope"]: return report("Return to the original kitchen.",false)
	if (job["phase"] != "prepared" or role != "cook") and (job["phase"] != "cooked" or role != "serve"):
		return report("Finish the current recipe stage first.",false)
	var recipe: Dictionary = Plan.recipes()[job["recipe"]]
	var utensil: String = ""
	if role == "cook":
		utensil = tool_for(candidate,stations,recipe["tool"])
		if utensil.is_empty(): return report("Set a reviewed pan near the stove.",false)
		var power: String = power_reason(candidate)
		if not power.is_empty(): return report(power,false)
	else:
		var entry: Dictionary = kitchens[job["scope"]]
		if int(entry["account"]["stock"].get("dish/"+job["recipe"],0)) >= Plan.MAX_PLATES:
			return report("The counter shelf is full.",false)
		if has_plates(entry) and entry["counter"] != uid and counter_valid(entry):
			return report("Plate this batch at the existing serving counter.",false)
	var locks: Array = reserve(candidate)
	if locks.is_empty(): return report("This station is already in use.",false)
	start_stage(job,candidate,locks)
	job["utensil"] = utensil
	job["utensil_identity"] = Plan.identity(stations[utensil]["item"]) if not utensil.is_empty() else ""
	return report("")

func start_prep(actor: Node, candidate: Dictionary, stations: Dictionary) -> Dictionary:
	var id: String = candidate["setting"].get("recipe",Plan.DEFAULT_RECIPE)
	var recipe: Dictionary = Plan.recipes()[id]
	var stove: bool = false
	var pan: bool = false
	var counter: bool = false
	for site in stations.values():
		if site["role"] == "serve": counter = true
		if site["role"] == "cook":
			stove = true
			pan = pan or not tool_for(site,stations,recipe["tool"]).is_empty()
	if not stove or not counter: return report("Enable a stove and serving counter on this floor.",false)
	if not pan: return report("Set a reviewed pan near a stove.",false)
	var entry: Dictionary = kitchen(candidate)
	if entry.is_empty(): return report("The preview kitchen limit has been reached.",false)
	var missing: String = Plan.ingredients_available(entry["account"]["stock"],recipe["inputs"])
	if not missing.is_empty(): return report("Missing %s. Restock at a pantry." % missing,false)
	var locks: Array = reserve(candidate)
	if locks.is_empty(): return report("This station is already in use.",false)
	var token: String = ticket()
	var debit: Dictionary = exchange(entry,token+"/inputs",Plan.inputs_for(recipe,-1),{"kind":"reserve","recipe":id})
	if not debit["ok"]:
		release(locks)
		return report("Ingredients could not be reserved.",false)
	var job: Dictionary = {"id":token,"actor":weakref(actor),"scope":candidate["scope"],"recipe":id,
		"prep":candidate["item"]["uid"],"prep_identity":Plan.identity(candidate["item"]),"inputs":Plan.inputs_for(recipe,1),
		"utensil":"","utensil_identity":""}
	start_stage(job,candidate,locks)
	jobs[actor.get_instance_id()] = job
	return report("")

func start_stage(job: Dictionary, candidate: Dictionary, locks: Array) -> void:
	var role: String = candidate["role"]
	job["phase"] = Plan.TRANSITIONS[role][0]
	job["remaining"] = float(Plan.recipes()[job["recipe"]]["seconds"][role])
	job["station"] = candidate["item"]["uid"]
	job["station_identity"] = Plan.identity(candidate["item"])
	job["locks"] = locks

func reserved_ingredients(scope: String) -> Dictionary:
	var held: Dictionary = {}
	for job in jobs.values():
		if job["scope"] != scope or job["phase"] not in ["preparing","prepared"]: continue
		for key in job["inputs"]: held[key] = int(held.get(key,0)) + int(job["inputs"][key])
	return held

func receive_village_flour(uid: String, id: String) -> Dictionary:
	var root: Dictionary = root_data()
	if not Plan.enabled(root): return report("Enable cooking and set up a ground-floor pantry.",false)
	var room: Dictionary = {}
	for item in root.get("objects",[]):
		if item["uid"] == uid:
			room = item.get("interior",{})
			break
	for item in room.get("objects",[]):
		if Plan.station(item).is_empty() or Plan.profile(item)["role"] != "pantry": continue
		if not Utility.availability(item,exploration.library,room).is_empty(): continue
		var scope: String = "room:"+uid+":ground:"
		if not kitchens.has(scope) and kitchens.size() >= MAX_KITCHENS:
			return report("The preview kitchen limit has been reached.",false)
		var entry: Dictionary = kitchens.get(scope,{"account":Plan.fresh_stock(),"owner":uid,"floor":"ground","counter":"","identity":""})
		var result: Dictionary = exchange(entry,id,{"flour":1},{"kind":"village_flour"},reserved_ingredients(scope))
		if not result["ok"] or result["replayed"]: return report("The kitchen pantry cannot accept more flour.",false)
		kitchens[scope] = entry
		menu_changed.emit()
		return report("Village flour delivered to the kitchen.")
	return report("Set up an enabled pantry on the bakery's ground floor.",false)

func restock(context: Dictionary) -> Dictionary:
	var entry: Dictionary = kitchen(context)
	if entry.is_empty(): return report("The preview kitchen limit has been reached.",false)
	var held: Dictionary = reserved_ingredients(context["scope"])
	var stock: Dictionary = entry["account"]["stock"]
	var added: Dictionary = {}
	for key in Plan.definitions()["starter_stock"]:
		var units: int = mini(3,Plan.MAX_STOCK-int(stock.get(key,0))-int(held.get(key,0)))
		if units > 0: added[key] = units
	if added.is_empty(): return report("The pantry already has full stock.",false)
	var result: Dictionary = exchange(entry,ticket()+"/restock",added,{"kind":"restock"},held)
	return report("Kitchen ingredients restocked." if result["ok"] else "There is no room in the pantry.",result["ok"])

func cancel(key: int, reason: String) -> void:
	var job: Dictionary = jobs.get(key,{})
	if job.is_empty(): return
	release(job["locks"])
	effects.release(job["id"])
	var refundable: bool = job["phase"] in ["preparing","prepared"]
	if refundable:
		var refund: Dictionary = exchange(kitchens[job["scope"]],job["id"]+"/refund",job["inputs"],{"kind":"refund","recipe":job["recipe"]})
		assert(refund["ok"],"Refund space is reserved while a batch is unheated.")
	jobs.erase(key)
	report(reason+(" Ingredients returned." if refundable else " Heated ingredients discarded."))

func cancel_player() -> bool:
	if player_job().is_empty(): return false
	cancel(exploration.player.get_instance_id(),"Batch cancelled.")
	return true

func cancel_all(reason: String) -> void:
	for key in jobs.keys(): cancel(key,reason)

func complete_stage(key: int, job: Dictionary, candidate: Dictionary) -> void:
	release(job["locks"])
	job["locks"] = []
	effects.release(job["id"])
	var role: String = candidate["role"]
	if role != "serve":
		job["phase"] = Plan.TRANSITIONS[role][1]
		job["remaining"] = WAIT_SECONDS
		report("")
		return
	var entry: Dictionary = kitchens[job["scope"]]
	if has_plates(entry) and not counter_valid(entry): discard_plates(entry)
	var receipt: Dictionary = exchange(entry,job["id"]+"/plate",{"dish/"+job["recipe"]:1},{"kind":"plate","result_id":job["recipe"]})
	jobs.erase(key)
	if not receipt["ok"]:
		report("Serving shelf full. This cooked batch was discarded.",false)
		return
	entry["counter"] = candidate["item"]["uid"]
	entry["identity"] = Plan.identity(candidate["item"])
	report(Plan.recipes()[job["recipe"]]["name"]+" plated.")
	menu_changed.emit()

func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0: return
	var step: float = minf(delta,.25)
	notice_time = maxf(0.0,notice_time-step)
	if jobs.is_empty(): return
	if exploration.photo.active: return
	if not active():
		cancel_all("Left kitchen activity.")
		return
	var context: Dictionary = Props.context(exploration)
	var stations: Dictionary = station_list(context)
	for key in jobs.keys():
		var job: Dictionary = jobs[key]
		var prep: Dictionary = stations.get(job["prep"],{})
		var actor: Node = job["actor"].get_ref()
		if not is_instance_valid(actor) or job["scope"] != context["scope"] or prep.is_empty() or Plan.identity(prep["item"]) != job["prep_identity"]:
			cancel(key,"The kitchen, recipe or cook changed.")
			continue
		if job["phase"] not in Plan.ACTIVE:
			job["remaining"] -= step
			if job["remaining"] <= 0: cancel(key,"The batch was left between stages.")
			continue
		var station: Dictionary = stations.get(job["station"],{})
		if station.is_empty() or Plan.identity(station["item"]) != job["station_identity"] or approach(station,actor).is_empty():
			cancel(key,"The cook left or the station changed.")
			continue
		if job["locks"].any(func(lock: Dictionary) -> bool: return lock["registry"].current(lock["key"]).get("token") != lock["token"]):
			cancel(key,"The station reservation ended.")
			continue
		if job["phase"] == "cooking":
			var power: String = power_reason(station)
			var utensil: Dictionary = stations.get(job["utensil"],{})
			if not power.is_empty() or utensil.is_empty() or Plan.identity(utensil["item"]) != job["utensil_identity"]:
				cancel(key,power if not power.is_empty() else "The pan moved or was removed.")
				continue
			var visual: Dictionary = station.duplicate()
			visual["profile"] = {"kind":"appliance","effect":"heat","point":[0,.8,0]}
			effects.apply(job["id"],visual,exploration,true,"Cooking · %.1f s" % job["remaining"])
		job["remaining"] -= step
		if job["remaining"] <= 0.0001: complete_stage(key,job,station)

func _physics_process(delta: float) -> void:
	advance(delta)

func counter_valid(entry: Dictionary) -> bool:
	var data: Dictionary = root_data()
	if not Plan.enabled(data): return false
	if not entry["owner"].is_empty():
		var room: Dictionary = {}
		for host in data.get("objects",[]):
			if host["uid"] == entry["owner"] and Utility.availability(host,exploration.library,data).is_empty():
				room = Floors.room(host.get("interior",{}),entry["floor"])
				break
		data = room
	for item in data.get("objects",[]):
		if item["uid"] == entry["counter"]:
			return not Plan.station(item).is_empty() and Plan.profile(item)["role"] == "serve" \
				and Plan.identity(item) == entry["identity"] and Utility.availability(item,exploration.library,data).is_empty()
	return false

func has_plates(entry: Dictionary) -> bool:
	for key in entry["account"]["stock"]:
		if key.begins_with("dish/") and int(entry["account"]["stock"][key]) > 0: return true
	return false

func discard_plates(entry: Dictionary) -> void:
	var removed: Dictionary = {}
	for key in entry["account"]["stock"]:
		if key.begins_with("dish/") and int(entry["account"]["stock"][key]) > 0:
			removed[key] = -int(entry["account"]["stock"][key])
	if not removed.is_empty(): exchange(entry,ticket()+"/discard",removed,{"kind":"discard"})

func supply(host: String, result_id: String) -> int:
	var total: int = 0
	for entry in kitchens.values():
		if entry["owner"] == host and has_plates(entry) and counter_valid(entry):
			total += int(entry["account"]["stock"].get("dish/"+result_id,0))
	return total

func menu(host: String) -> Array:
	var result: Array = []
	for id in Plan.recipes():
		if supply(host,id) > 0: result.append(Plan.activity(id))
	return result

func near_counter(host: String, result_id: String) -> bool:
	if not active() or exploration.interior_uid != host: return false
	var context: Dictionary = Props.context(exploration)
	var entry: Dictionary = kitchens.get(context["scope"],{})
	if entry.is_empty() or not counter_valid(entry) or int(entry["account"]["stock"].get("dish/"+result_id,0)) <= 0:
		return false
	var candidate: Dictionary = station_list(context).get(entry["counter"],{})
	return not candidate.is_empty() and not approach(candidate,exploration.player).is_empty()

func serve_visit(visit: Dictionary) -> bool:
	var id: String = visit.get("result_id","")
	if not Plan.recipes().has(id): return false
	var token: String = "served/%s/%s/%d" % [visit["business"],visit["visitor"],visit["sequence"]]
	for entry in kitchens.values():
		if entry["owner"] != visit["business"]: continue
		if entry["account"]["receipts"].get(token,{}).get("result_id") == id: return true
	for entry in kitchens.values():
		if entry["owner"] != visit["business"] or int(entry["account"]["stock"].get("dish/"+id,0)) <= 0 or not counter_valid(entry): continue
		var accepted: Dictionary = exchange(entry,token,{"dish/"+id:-1},{"kind":"served","result_id":id})
		if accepted["ok"]:
			menu_changed.emit()
			return true
	return false

func reset() -> void:
	cancel_all("Kitchen preview reset.")
	kitchens.clear()
	effects.reset()
	notice = ""
	notice_time = 0.0
	menu_changed.emit()
