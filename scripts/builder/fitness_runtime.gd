extends Node

const Plan = preload("res://scripts/builder/fitness_plan.gd")
const Court = preload("res://scripts/builder/fitness_court.gd")
const Motion = preload("res://scripts/builder/fitness_motion.gd")
const Props = preload("res://scripts/builder/prop_plan.gd")
const Utility = preload("res://scripts/builder/utility_profiles.gd")
const Reservations = preload("res://scripts/builder/activity_reservations.gd")
const View = preload("res://scripts/builder/fitness_view.gd")
const Visits = preload("res://scripts/builder/business_visits.gd")

var exploration: Node
var clock: Node
var authored_root: Callable
var source: Dictionary = {}
var panel_area := Rect2()
var hud_enabled: bool = true
var ui_scale: float = 1
var high_contrast: bool = false
var large_targets: bool = false
var interact_label: String = "E"
var menu: Dictionary = {}
var booking: Dictionary = {}
var session: Dictionary = {}
var history: Array[Dictionary] = []
var last_result: Dictionary = {}
var notice: String = ""
var notice_time: float = 0
var sequence: int = 0
var locks: Array[Dictionary] = []
var view: RefCounted
var motion := Motion.new()
var court := Court.new()

func root_data() -> Dictionary:
	return authored_root.call() if authored_root.is_valid() else source

func configure(data: Dictionary) -> void:
	source = data
	if not Plan.enabled(root_data()) and (not booking.is_empty() or not session.is_empty() or not menu.is_empty()):
		cancel("Sports preview disabled.")

func manages(item: Dictionary) -> bool:
	return Plan.enabled(root_data()) and not Plan.station(item,exploration.dimension).is_empty()

func hour() -> float:
	return clock.hour if is_instance_valid(clock) else 7.0

func available() -> bool:
	return exploration.enabled and not exploration.entering and not exploration.photo.active \
		and exploration.driving.active.is_empty() and Plan.enabled(root_data()) \
		and is_instance_valid(exploration.player)

func candidate(item: Dictionary, context: Dictionary) -> Dictionary:
	var setting: Dictionary = Plan.station(item,exploration.dimension)
	if setting.is_empty() or not Utility.availability(item,exploration.library,context["data"]).is_empty(): return {}
	var node: Node = context["instances"].get(item["uid"])
	if not is_instance_valid(node) or not node.is_visible_in_tree(): return {}
	var result: Dictionary = context.duplicate()
	result.merge({"item":item,"node":node,"setting":setting,"profile":Plan.profile(item,exploration.dimension)})
	return result

func approach(station: Dictionary) -> Dictionary:
	var player: Node = exploration.player
	var node: Node = station["node"]
	var best: Dictionary = {}
	if station["setting"]["kind"] == "penalty":
		var frame: Dictionary = Court.frame_for(station,exploration)
		if frame.is_empty(): return {}
		var point: Variant = Court.world_point(frame,Vector3(0,0,Court.STANCE))
		var distance: float = player.global_position.distance_to(point)
		return {"point":point,"distance":distance,"frame":frame} if close_enough(point) else {}
	var bounds: Rect2 = Utility.footprint(station["item"],exploration.library,exploration.dimension)
	for side in Utility.SIDES:
		var edge: Vector2 = Utility.side_point(bounds,side,2.1 if exploration.dimension == "2d" else .85)
		var at: Array = Utility.Traffic.world(edge,exploration.dimension)
		var point: Variant = node.get_parent().to_global(Vector2(at[0],at[1])) if exploration.dimension == "2d" \
			else node.get_parent().to_global(Vector3(at[0],node.position.y,at[2]))
		if not close_enough(point) or not Props.reachable(exploration,node,point): continue
		var distance: float = player.global_position.distance_to(point)
		var clear: bool = Props.standing_clear(exploration,point)
		if not best.is_empty():
			if not clear and best["clear"]: continue
			if clear == best["clear"] and distance >= best["distance"]: continue
		best = {"point":point,"distance":distance,"clear":clear}
	return best

func close_enough(point: Variant) -> bool:
	var gap: Variant = point-exploration.player.global_position
	return Vector2(gap.x/8,gap.y/4).length() <= 2.65 if exploration.dimension == "2d" \
		else absf(gap.y) <= 1.0 and Vector2(gap.x,gap.z).length() <= 2.4

func nearby() -> Dictionary:
	if not available() or not session.is_empty(): return {}
	var context: Dictionary = Props.context(exploration)
	var best: Dictionary = {}
	for item in context["data"].get("objects",[]):
		var station: Dictionary = candidate(item,context)
		if station.is_empty(): continue
		var landing: Dictionary = approach(station)
		if landing.is_empty() or landing["distance"] >= best.get("distance",INF): continue
		best = station
		best.merge(landing)
	return best

func local_station(uid: String) -> Dictionary:
	var context: Dictionary = Props.context(exploration)
	for item in context["data"].get("objects",[]):
		if item["uid"] == uid: return candidate(item,context)
	return {}

func stamp(station: Dictionary) -> Array:
	return [station["scope"],station["node"].get_instance_id(),station["node"].global_transform,
		station["item"]["asset"],station["item"]["direction"],station["setting"]]

func label_for(station: Dictionary) -> String:
	return Plan.definitions()["activities"][station["setting"]["kind"]]["name"]

func report(text: String, ok: bool = true) -> Dictionary:
	notice = text
	notice_time = 6
	return {"ok":ok,"reason":text}

func prompt(station: Dictionary = {}) -> String:
	if not session.is_empty():
		var time: int = ceili(session["remaining"])
		if session["kind"] == "penalty":
			return "%s · Kick · %d goals / %d shots · %d s" % [interact_label,session["score"],session["shots"],time]
		return "%s · Stop · %s · %d s" % [interact_label,session["label"],time]
	if station.is_empty(): return notice if notice_time > 0 else ""
	var suffix: String = "" if Plan.scheduled(station["setting"],hour()) else " · Closed"
	return "%s · %s booking%s" % [interact_label,label_for(station),suffix] + (" · "+notice if notice_time > 0 else "")

func interact(uid: String = "") -> void:
	if not session.is_empty():
		if session["kind"] == "penalty": kick()
		else: cancel("Workout stopped.")
		return
	if not available(): return
	if menu.get("uid") == uid:
		cancel("Booking closed.")
		return
	var station: Dictionary = local_station(uid)
	if station.is_empty() or approach(station).is_empty(): return
	cancel("")
	menu = {"uid":uid,"stamp":stamp(station)}
	if view == null: view = View.new(self)
	view.update(station,true)

func reason(station: Dictionary) -> String:
	if not available(): return "One player must be present in Walk to check in."
	if station.is_empty(): return "This sports station is no longer available."
	if not Plan.scheduled(station["setting"],hour()): return "This station is closed at the current city hour."
	var issue: String = Plan.equipment_reason(station["item"],exploration.library,exploration.dimension)
	if not issue.is_empty(): return issue
	var kind: String = station["setting"]["kind"]
	if kind == "penalty":
		var art: String = Plan.definitions()["ball"]
		if not exploration.library.assets.has(art): return "The supplied ball is unavailable."
	else:
		if not station["profile"]["views"].has(station["item"]["direction"]): return "This equipment view has no calibrated contact points."
		var action: String = Plan.definitions()["activities"][kind]["action"]
		return Motion.support(exploration.player,action)["reason"]
	return ""

func book() -> Dictionary:
	if menu.is_empty() or not booking.is_empty() or not session.is_empty(): return report("Open one sports station first.",false)
	var station: Dictionary = local_station(menu["uid"])
	var issue: String = reason(station)
	if not issue.is_empty(): return report(issue,false)
	if stamp(station) != menu["stamp"] or approach(station).is_empty(): return report("Return to the marked approach to reserve.",false)
	var key: String = station["scope"]+station["item"]["uid"]
	var root: Node = exploration.get_parent()
	var world: Node = station["world"]
	for location in ([root] if root == world else [root,world]):
		var registry: RefCounted = Reservations.for_world(location)
		var token: int = registry.acquire(key,self)
		if token == 0:
			release()
			return report("Another activity holds this station.",false)
		locks.append({"registry":registry,"key":key,"token":token})
	booking = {"uid":menu["uid"],"remaining":Plan.CHECK_IN_SECONDS}
	report("Reserved for one player. Check in at this station.")
	view.update(station)
	return {"ok":true}

func start() -> Dictionary:
	if booking.is_empty(): return report("Reserve a slot first.",false)
	var station: Dictionary = local_station(booking["uid"])
	var issue: String = reason(station)
	if not issue.is_empty(): return report(issue,false)
	if stamp(station) != menu["stamp"] or not valid_locks(): return report("The station or its reservation changed.",false)
	var landing: Dictionary = approach(station)
	if landing.is_empty() or not Props.reachable(exploration,station["node"],landing["point"]) \
		or not Props.standing_clear(exploration,landing["point"]):
		return report("Clear the standing approach before checking in.",false)
	var kind: String = station["setting"]["kind"]
	var profile: Dictionary = Plan.definitions()["activities"][kind]
	var ball_art: Texture2D
	if kind == "penalty":
		ball_art = Court.ball_texture(exploration.library,Plan.definitions()["ball"])
		if ball_art == null: return report("The supplied ball could not be displayed.",false)
	sequence += 1
	var note: String = "" if kind == "penalty" else Motion.support(exploration.player,profile["action"]).get("note","")
	session = {"id":"sports/%d" % sequence,"uid":station["item"]["uid"],"kind":kind,"label":profile["name"],
		"duration":float(profile["seconds"]),"remaining":float(profile["seconds"]),"elapsed":0.0,"aim":0.0,
		"shots":0,"score":0,"cooldown":0.0,"swing":0.0,"note":note}
	booking.clear()
	motion.hold(exploration.player,landing["point"],kind != "penalty")
	if kind == "penalty":
		court.build(landing["frame"],exploration,ball_art)
		motion.kick_pose(exploration.player,court.frame["origin"],0,0)
	else:
		motion.pose(exploration.player,station,profile,0,0)
	report("Session started.")
	view.update(station)
	return {"ok":true}

func valid_locks() -> bool:
	if locks.is_empty(): return false
	for lock in locks:
		if lock["registry"].current(lock["key"]).get("token") != lock["token"]: return false
	return true

func release() -> void:
	for lock in locks: lock["registry"].release(lock["key"],lock["token"])
	locks.clear()

func cancel(reason_text: String, completed: bool = false) -> void:
	if not session.is_empty():
		var actor: Node = exploration.player
		motion.release(actor)
		court.release()
		if is_instance_valid(actor) and exploration.enabled and actor.is_inside_tree() \
			and not Props.standing_clear(exploration,actor.global_position):
			actor.recover_to_safe()
		var result: Dictionary = {"id":session["id"],"station":session["uid"],"kind":session["kind"],
			"status":"completed" if completed else "cancelled","shots":session["shots"],"score":session["score"],
			"seconds":session["elapsed"],"reason":reason_text}
		if completed and session["kind"] != "penalty":
			result["repetitions"] = floori(session["elapsed"]*Plan.definitions()["activities"][session["kind"]]["rate"])
		history.append(result)
		if history.size() > Plan.MAX_HISTORY: history.pop_front()
		last_result = result
	session.clear()
	booking.clear()
	menu.clear()
	release()
	if view: view.hide()
	if not reason_text.is_empty(): report(reason_text)

func close_view() -> void:
	cancel("Sports session cancelled." if not session.is_empty() else "Booking closed.")

func reset() -> void:
	cancel("")
	history.clear()
	last_result.clear()
	notice = ""
	notice_time = 0

func aim(delta: float) -> void:
	if session.get("kind") != "penalty" or court.flying or exploration.photo.active: return
	var limit: float = float(court.frame["half"])*1.65
	session["aim"] = clampf(session["aim"]+delta,-limit,limit)
	court.present(session["aim"])

func kick() -> bool:
	if session.get("kind") != "penalty" or court.flying or session["cooldown"] > 0 or exploration.photo.active: return false
	session["shots"] += 1
	session["swing"] = .38
	court.kick(session["aim"])
	return true

func spectators() -> Array:
	var result: Array[Node] = []
	if not is_instance_valid(clock) or not is_instance_valid(clock.citizens): return result
	for resident in clock.citizens.residents:
		var actor: Node = resident.get("actor")
		if is_instance_valid(actor) and actor.is_visible_in_tree() and actor.get_viewport() == exploration.player.get_viewport():
			result.append(actor)
	return result

func advance_court(delta: float, station: Dictionary, profile: Dictionary) -> void:
	var player: Node = exploration.player
	if not court.flying and session["cooldown"] == 0:
		var left: bool = player.control_input.call("move_left") if player.control_input.is_valid() else Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)
		var right: bool = player.control_input.call("move_right") if player.control_input.is_valid() else Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)
		if left != right: aim((float(right)-float(left))*3.3*delta)
	session["swing"] = maxf(0,session["swing"]-delta)
	motion.kick_pose(player,court.frame["origin"],session["swing"]/.38,delta)
	if court.flying:
		var outcome: String = court.advance(delta,exploration,station["node"],spectators())
		if outcome == "flight": return
		if outcome == "goal": session["score"] += 1
		report({"goal":"Goal!","out":"Out of bounds · return to the mark.","blocked":"Shot blocked · clear the penalty lane."}[outcome])
		session["cooldown"] = .65
	elif session["cooldown"] > 0:
		session["cooldown"] = maxf(0,session["cooldown"]-delta)
		if session["cooldown"] > 0: return
		if session["score"] >= profile["target"] or session["shots"] >= profile["shots"]:
			finish_court()
			return
		court.reset_ball(session["aim"])

func finish_court() -> void:
	cancel("Penalty practice finished · %d goals from %d shots." % [session["score"],session["shots"]],true)

func _physics_process(delta: float) -> void:
	step(minf(delta,.08))

func step(delta: float) -> void:
	notice_time = maxf(0,notice_time-delta)
	if menu.is_empty(): return
	if exploration.photo.active:
		if view: view.hide()
		return
	if not available():
		cancel("Sports session interrupted.")
		return
	var station: Dictionary = local_station(menu["uid"])
	if station.is_empty() or stamp(station) != menu["stamp"]:
		cancel("The sports station moved, changed, or was removed.")
		return
	if session.is_empty():
		if approach(station).is_empty():
			cancel("You left the sports station.")
			return
		if not booking.is_empty():
			booking["remaining"] -= delta
			if booking["remaining"] <= 0 or not valid_locks() or not Plan.scheduled(station["setting"],hour()):
				cancel("The booking expired.")
				return
	else:
		if not valid_locks():
			cancel("The station reservation ended.")
			return
		var kind: String = session["kind"]
		var definition: Dictionary = Plan.definitions()["activities"][kind]
		session["elapsed"] = minf(session["duration"],session["elapsed"]+delta)
		session["remaining"] = session["duration"]-session["elapsed"]
		if kind == "penalty":
			if session["remaining"] <= 0: finish_court(); return
			advance_court(delta,station,definition)
		else:
			motion.pose(exploration.player,station,definition,session["elapsed"],delta)
			if session["remaining"] <= 0:
				cancel("%s workout complete." % session["label"],true)
		if session.is_empty(): return
	if view:
		if hud_enabled: view.update(station)
		else: view.hide()
