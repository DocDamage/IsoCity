extends Node

const Plan = preload("res://scripts/builder/camping_plan.gd")
const Props = preload("res://scripts/builder/prop_plan.gd")
const Weather = preload("res://scripts/builder/weather_plan.gd")
const Reservations = preload("res://scripts/builder/activity_reservations.gd")
const View = preload("res://scripts/builder/camping_view.gd")
const Visits = preload("res://scripts/builder/business_visits.gd")
const PLAYER = "player"
const CITY = "city:"

var exploration: Node
var clock: Node
var authored_root: Callable
var audio_allowed: Callable
var source: Dictionary = {}
var compiled: Dictionary = {}
var jobs: Dictionary = {}
var served_day: Dictionary = {}
var history: Array[Dictionary] = []
var view := View.new()
var sequence: int = 0
var last_time: float = -1
var elapsed: float = 0
var notice: String = ""
var notice_time: float = 0
var request_budget: int = 2

func root_data() -> Dictionary:
	return authored_root.call() if authored_root.is_valid() else source

func configure(data: Dictionary) -> void:
	source = data
	compiled.clear()
	if not Plan.enabled(root_data()): reset()

func time() -> float:
	if not is_instance_valid(clock): return 9.0
	var residents: Node = clock.citizens
	if is_instance_valid(residents) and residents.plan.get("settings",{}).get("enabled",false):
		return residents.preview_day*24.0+residents.hour
	return clock.preview_day*24.0+clock.hour

func weather() -> Dictionary:
	return Weather.state(root_data())

func show_notice(text: String) -> void:
	notice = text
	notice_time = 6

func scope() -> String:
	return Props.scope(exploration)

func sites(key: String) -> Dictionary:
	if not Plan.enabled(root_data()): return {}
	if compiled.has(key): return compiled[key]
	if key != CITY and key != scope(): return {}
	var data: Dictionary = root_data() if key == CITY else Props.context(exploration)["data"]
	if compiled.size() >= 8:
		var exterior: Dictionary = compiled.get(CITY,{})
		compiled = {CITY:exterior} if compiled.has(CITY) else {}
	var result: Dictionary = Plan.compile(data,exploration.library,key == CITY)
	compiled[key] = result
	return result

func occupied(key: String, uid: String) -> int:
	var count: int = 0
	for job in jobs.values():
		if job["scope"] == key and job["site"] == uid: count += 1
	return count

func usable(site: Dictionary, key: String) -> String:
	if site.is_empty(): return "This campsite is unavailable."
	if not site["reason"].is_empty(): return site["reason"]
	if key == CITY and Plan.storm(weather()): return "The campsite is closed for severe weather."
	if site["kind"] == "fire" and not Plan.fire_safe(weather()): return "The weather is unsafe for a campfire."
	if not Plan.open(site,time()): return "Check-in is closed."
	if occupied(key,site["uid"]) >= site["config"]["capacity"]: return "This campsite is full."
	return ""

func book(id: String, site: Dictionary, key: String, actor: Node) -> bool:
	if jobs.has(id) or not is_instance_valid(actor): return false
	var issue: String = usable(site,key)
	if not issue.is_empty():
		if id == PLAYER: show_notice(issue)
		return false
	var root: Node = exploration.get_parent()
	var world: Node = Props.context(exploration)["world"] if key == scope() else root
	for slot in site["points"].size():
		var locks: Array[Dictionary] = []
		var lock_key: String = key+site["uid"]+":camp:"+str(slot)
		for location in ([root] if world == root else [root,world]):
			var registry: RefCounted = Reservations.for_world(location)
			var token: int = registry.acquire(lock_key,self)
			if not token: break
			locks.append({"registry":registry,"key":lock_key,"token":token})
		if locks.size() < (1 if world == root else 2):
			release(locks)
			continue
		sequence += 1
		jobs[id] = {"id":"camp/%d" % sequence,"guest":id,"actor":weakref(actor),"scope":key,"site":site["uid"],
			"identity":site["identity"],"slot":slot,"locks":locks,"phase":"reserved","seconds":0.0,
			"arrived":false,"due":Plan.due(site["config"],time()),"overnight":site["config"]["overnight"]}
		if id == PLAYER: show_notice("Site reserved. Check in at the shelter.")
		return true
	if id == PLAYER: show_notice("All sleeping spaces are reserved.")
	return false

func release(locks: Array) -> void:
	for lock in locks: lock["registry"].release(lock["key"],lock["token"])

func valid(job: Dictionary, site: Dictionary) -> bool:
	if not is_instance_valid(job["actor"].get_ref()) or site.is_empty() or not site["reason"].is_empty() \
		or site.get("identity") != job["identity"] or site["points"].size() <= job["slot"]: return false
	for lock in job["locks"]:
		if lock["registry"].current(lock["key"]).get("token") != lock["token"]: return false
	return true

func transition(job: Dictionary, phase: String) -> void:
	job["phase"] = phase
	job["seconds"] = 0.0
	job["arrived"] = false

func finish(id: String, reason: String, completed: bool = false) -> void:
	if not jobs.has(id): return
	var job: Dictionary = jobs[id]
	view.wake(id)
	release(job["locks"])
	jobs.erase(id)
	history.append({"id":job["id"],"guest":id,"site":job["site"],"scope":job["scope"],
		"state":"completed" if completed else "cancelled","reason":reason})
	if history.size() > Plan.HISTORY_LIMIT: history.pop_front()
	if id == PLAYER: show_notice(reason)
	sync_views()

func cancel_player(reason: String = "Camping visit cancelled.") -> bool:
	if not jobs.has(PLAYER): return false
	finish(PLAYER,reason)
	return true

func resting() -> bool:
	return jobs.get(PLAYER,{}).get("phase") == "resting"

func can_player_use() -> bool:
	return exploration.enabled and not exploration.entering and not exploration.photo.active \
		and exploration.driving.active.is_empty() and Plan.enabled(root_data()) and is_instance_valid(exploration.player)

func world_point(point: Vector2, context: Dictionary) -> Variant:
	var world: Node = context["world"]
	if exploration.dimension == "2d":
		return exploration.player.get_parent().to_global(Vector2(point.x*16,point.y*8))
	var height: float = 0.0
	var data: Dictionary = context["data"]
	if Plan.Terrain.settings(data)["enabled"]:
		height = Plan.Terrain.sample(data,point,Plan.Terrain.lookup(data))["height"]
	return world.to_global(Vector3(point.x,height+.05,point.y)) if world is Node3D else Vector3(point.x,height+.05,point.y)

func landing(point: Vector2, context: Dictionary) -> Dictionary:
	var position: Variant = world_point(point,context)
	var actor: Node = exploration.player
	var gap: Variant = position-actor.global_position
	var in_range: bool = Vector2(gap.x/8,gap.y/4).length() <= 2.8 if exploration.dimension == "2d" \
		else absf(gap.y) <= 1.1 and Vector2(gap.x,gap.z).length() <= 2.45
	if not in_range or (gap.length() > .01 and not Props.reachable(exploration,actor,position)): return {}
	return {"point":position,"distance":gap.length()}

func nearby() -> Dictionary:
	if not can_player_use() or resting(): return {}
	var context: Dictionary = Props.context(exploration)
	var local: Dictionary = sites(context["scope"])
	var player: Dictionary = jobs.get(PLAYER,{})
	var best: Dictionary = {}
	for site in local.values():
		if not site.has("entry"): continue
		if not player.is_empty() and (player["scope"] != context["scope"] or player["site"] != site["uid"]): continue
		var choices: Array = []
		if player.is_empty():
			choices.append(["reserve",site["entry"]])
			if not site["points"].is_empty(): choices.append(["reserve",site["points"][0]["shelter"]])
		elif valid(player,site):
			var points: Dictionary = site["points"][player["slot"]]
			match player["phase"]:
				"reserved": choices.append(["checkin",points["shelter"]])
				"checked_in": choices.append(["activity",points["activity"]])
				"activity": choices.append(["continue",points["activity"]])
				"rest": choices.append(["rest",points["shelter"]])
				"departure": choices.append(["checkout",site["entry"]])
		for choice in choices:
			var where: Dictionary = landing(choice[1],context)
			if where.is_empty() or where["distance"] >= best.get("distance",INF): continue
			best = {"site":site["uid"],"action":choice[0],"scope":context["scope"]}
			best.merge(where)
	return best

func prompt(candidate: Dictionary = {}) -> String:
	var player: Dictionary = jobs.get(PLAYER,{})
	if resting():
		var condition: String = view.poses.get(PLAYER,{}).get("label","Resting")
		var target: String = " until "+Visits.time_text(fposmod(player["due"],24)) if player["overnight"] else ""
		return "E · Wake early · "+condition+target
	if candidate.is_empty():
		if player.is_empty(): return notice if notice_time > 0 else ""
		return {"reserved":"Go to the campsite shelter to check in.","checked_in":"Walk to the camp activity.",
			"activity":"Stay at the camp activity.","rest":"Go to the shelter to rest.","departure":"Return to the park arrival to check out."}.get(player["phase"],"")
	var site: Dictionary = sites(candidate["scope"]).get(candidate["site"],{})
	if site.is_empty(): return ""
	var title: String = {
		"reserve":"Reserve "+site["name"],"checkin":"Check in at "+site["name"],
		"activity":"Gather at the campfire" if site["kind"] == "fire" else "Start the picnic",
		"continue":"End camp activity early","rest":"Rest at the shelter","checkout":"Check out at the park"
	}[candidate["action"]]
	var issue: String = usable(site,candidate["scope"]) if candidate["action"] == "reserve" else ""
	var detail: String = issue if not issue.is_empty() else notice if notice_time > 0 else ""
	return "E · "+title+(" · "+detail if not detail.is_empty() else "")

func interact() -> void:
	if resting():
		view.wake(PLAYER)
		transition(jobs[PLAYER],"rest")
		show_notice("Rest interrupted. Return to the shelter to rest again.")
		return
	var candidate: Dictionary = nearby()
	if candidate.is_empty(): return
	var site: Dictionary = sites(candidate["scope"])[candidate["site"]]
	var player: Dictionary = jobs.get(PLAYER,{})
	match candidate["action"]:
		"reserve": book(PLAYER,site,candidate["scope"],exploration.player)
		"checkin":
			transition(player,"checked_in")
			show_notice("Checked in. Walk to the camp activity.")
		"activity":
			if site["kind"] == "fire" and not Plan.fire_safe(weather()):
				show_notice("The weather is unsafe for a campfire.")
				return
			transition(player,"activity")
			player["arrived"] = true
			show_notice("Camp activity started.")
		"continue":
			transition(player,"checked_in")
			show_notice("Camp activity ended early.")
		"rest":
			if not Props.standing_clear(exploration,candidate["point"]):
				show_notice("Clear the shelter approach before resting.")
				return
			transition(player,"resting")
			exploration.player.teleport_to(exploration.player.get_parent().to_local(candidate["point"]))
			view.rest(PLAYER,exploration.player)
		"checkout": finish(PLAYER,"Camping visit complete.",true)
	sync_views()

func resident_target(manager: Node, resident: Dictionary, eligible: bool) -> String:
	var id: String = resident["id"]
	var actor: Node = resident["actor"]
	var visit: Dictionary = jobs.get(id,{})
	if visit.is_empty() and eligible and request_budget > 0 and served_day.get(id,-1) != manager.preview_day:
		for site in sites(CITY).values():
			if site["config"]["park"] != resident["park"] or not usable(site,CITY).is_empty(): continue
			request_budget -= 1
			var route: Dictionary = manager.route(manager.point(actor),site["entry"])
			if not route["path"].is_empty() and route["goal"].distance_to(site["entry"]) <= .65 and book(id,site,CITY,actor):
				served_day[id] = manager.preview_day
				visit = jobs[id]
			break
	return target_key(visit) if not visit.is_empty() else ""

func target_key(visit: Dictionary) -> String:
	return "camp/"+visit["phase"]+"/"+visit["guest"]

func destination(target: String) -> Dictionary:
	if not target.begins_with("camp/"): return {}
	var parts: PackedStringArray = target.split("/",false,2)
	if parts.size() != 3: return {}
	var visit: Dictionary = jobs.get(parts[2],{})
	if visit.is_empty() or target_key(visit) != target: return {}
	var site: Dictionary = sites(CITY).get(visit["site"],{})
	if not valid(visit,site): return {}
	var point: Vector2 = site["entry"]
	var positions: Dictionary = site["points"][visit["slot"]]
	match visit["phase"]:
		"checkin", "rest": point = positions["shelter"]
		"activity": point = positions["activity"]
	var data: Dictionary = root_data()
	var height: float = 0
	if exploration.dimension == "3d" and Plan.Terrain.settings(data)["enabled"]:
		height = Plan.Terrain.sample(data,point,Plan.Terrain.lookup(data))["height"]
	return {"point":point,"height":height,"role":"camp","name":site["name"]}

func resident_arrive(resident: Dictionary, target: String, delta: float) -> bool:
	var id: String = resident["id"]
	var visit: Dictionary = jobs.get(id,{})
	if visit.is_empty() or target_key(visit) != target: return false
	var actor: Node = resident["actor"]
	actor.velocity = Vector2.ZERO if actor is Node2D else Vector3.ZERO
	actor.visible = true
	if not visit["arrived"]:
		visit["arrived"] = true
		visit["seconds"] = 0
	match visit["phase"]:
		"reserved": transition(visit,"checkin")
		"checkin": transition(visit,"activity")
		"activity":
			visit["seconds"] += minf(delta,.25)
			resident["status"] = "Camping activity"
			if visit["seconds"] >= Plan.ACTIVITY_SECONDS: transition(visit,"rest")
		"rest":
			var note: String = view.rest(id,actor)
			resident["status"] = note+" at the campsite"
			visit["seconds"] += minf(delta,.25)
			if rest_done(visit):
				view.wake(id)
				transition(visit,"departure")
		"departure":
			finish(id,"Camping visit complete.",true)
			resident["target"] = ""
			resident["path"] = PackedVector2Array()
			resident["index"] = 0
	return true

func rest_done(visit: Dictionary) -> bool:
	return visit["seconds"] >= Plan.REST_SECONDS and (not visit["overnight"] or time() >= visit["due"])

func resident_begin(residents: Array) -> void:
	request_budget = 2
	if jobs.is_empty() and served_day.is_empty(): return
	var present: Dictionary = {}
	for resident in residents: present[resident["id"]] = true
	for id in jobs.keys():
		if id != PLAYER and not present.has(id): finish(id,"The resident is no longer available.")
	for id in served_day.keys():
		if not present.has(id): served_day.erase(id)

func clear_residents() -> void:
	for id in jobs.keys():
		if id != PLAYER: finish(id,"Resident preview reset.")
	served_day.clear()

func manages(item: Dictionary, key: String) -> bool:
	if Plan.activity(item) != "fire": return false
	for site in sites(key).values():
		if site.get("kind") == "fire" and site["activity"]["uid"] == item["uid"]: return true
	return false

func sync_views() -> void:
	if not is_instance_valid(exploration.player) or not exploration.enabled or exploration.entering \
		or not Plan.enabled(root_data()):
		view.clear_views()
		return
	var context: Dictionary = Props.context(exploration)
	var key: String = context["scope"]
	var keep: Dictionary = {}
	var flames: Dictionary = {}
	var sound: bool = audio_allowed.is_valid() and audio_allowed.call()
	for site in sites(key).values():
		var uid: String = site["uid"]
		var node: Node = context["instances"].get(uid)
		if not is_instance_valid(node) or not node.is_visible_in_tree(): continue
		if not exploration.photo.active:
			keep[uid] = true
			var used: int = occupied(key,uid)
			view.marker(uid,node,exploration.dimension,site["name"]+" · "+(
				"%d/%d camping" % [used,site["config"]["capacity"]] if site["reason"].is_empty() else site["reason"]))
		if site.get("kind") != "fire": continue
		var fire_uid: String = site["activity"]["uid"]
		var fire_node: Node = context["instances"].get(fire_uid)
		if not is_instance_valid(fire_node): continue
		flames[fire_uid] = true
		var on: bool = false
		if not exploration.photo.active and site["reason"].is_empty() and Plan.fire_safe(weather()):
			for job in jobs.values():
				if job["scope"] == key and job["site"] == uid and job["phase"] == "activity" and job["arrived"]:
					on = true
					break
		var candidate: Dictionary = context.duplicate()
		candidate.merge({"item":site["activity"],"node":fire_node})
		view.fire(fire_uid,candidate,exploration,on,sound)
	for uid in view.labels.keys():
		if not keep.has(uid): view.remove_marker(uid)
	for uid in view.flames.keys():
		if not flames.has(uid): view.remove_fire(uid)

func step(delta: float) -> void:
	notice_time = maxf(0,notice_time-delta)
	if not Plan.enabled(root_data()): return
	var now: float = time()
	var jump: bool = last_time >= 0 and (now < last_time-.01 or now-last_time > .75)
	last_time = now
	if exploration.photo.active:
		sync_views()
		return
	var weather_state: Dictionary = weather()
	var residents: Node = clock.citizens if is_instance_valid(clock) else null
	for id in jobs.keys():
		var job: Dictionary = jobs[id]
		var key: String = job["scope"]
		var site: Dictionary = sites(key).get(job["site"],{})
		if jump:
			finish(id,"The city preview clock changed. Check in again.")
		elif not valid(job,site) or (id == PLAYER and key != scope()):
			finish(id,"The campsite or its route changed. The site was released.")
		elif key == CITY and Plan.storm(weather_state):
			finish(id,"Severe weather closed the campsite.")
		elif site["kind"] == "fire" and job["phase"] == "activity" and not Plan.fire_safe(weather_state):
			if id == PLAYER:
				transition(job,"checked_in")
				show_notice("The fire went out. Wait for safer weather.")
			else: finish(id,"Weather ended the campfire activity.")
		elif job["phase"] not in ["departure","rest","resting"] and now >= job["due"]:
			finish(id,"The campsite’s checkout time passed.")
		elif job["phase"] == "departure" and now > job["due"]+2:
			finish(id,"The checkout window ended.")
		elif job["phase"] in ["rest","resting"] and now > job["due"]+1:
			finish(id,"The rest window ended.")
		elif id != PLAYER:
			if not job["arrived"] and is_instance_valid(residents) and residents.active and not residents.paused and not residents.exterior_suspended():
				job["seconds"] += delta
				if job["seconds"] >= Plan.ARRIVAL_TIMEOUT: finish(id,"No safe route to the next campsite stop.")
		else: step_player(job,site,delta)
	sync_views()

func step_player(job: Dictionary, site: Dictionary, delta: float) -> void:
	var phase: String = job["phase"]
	job["seconds"] += delta
	if phase == "reserved" and job["seconds"] >= Plan.ARRIVAL_TIMEOUT:
		finish(PLAYER,"The campsite reservation expired.")
	elif phase == "activity":
		if landing(site["points"][job["slot"]]["activity"],Props.context(exploration)).is_empty():
			transition(job,"checked_in")
			show_notice("You left the camp activity.")
		elif job["seconds"] >= Plan.ACTIVITY_SECONDS:
			transition(job,"rest")
			show_notice("Camp activity complete. Rest at the shelter.")
	elif phase == "resting" and rest_done(job):
		view.wake(PLAYER)
		transition(job,"departure")
		show_notice("Rest complete. Return to the park arrival.")

func _physics_process(delta: float) -> void:
	elapsed += delta
	if elapsed < .18: return
	var frame: float = minf(elapsed,.25)
	elapsed = 0
	step(frame)

func reset() -> void:
	for job in jobs.values(): release(job["locks"])
	jobs.clear()
	served_day.clear()
	history.clear()
	compiled.clear()
	last_time = -1
	elapsed = 0
	notice = ""
	notice_time = 0
	view.reset()
