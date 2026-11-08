extends Node

const Plan = preload("res://scripts/builder/arcade_plan.gd")
const Props = preload("res://scripts/builder/prop_plan.gd")
const Utility = preload("res://scripts/builder/utility_profiles.gd")
const Reservations = preload("res://scripts/builder/activity_reservations.gd")
const View = preload("res://scripts/builder/arcade_view.gd")
const GAMES = {
	"sprint": preload("res://scenes/builder/arcade_sprint.tscn"),
	"signals": preload("res://scenes/builder/arcade_signals.tscn"),
}
const TICK = 1.0/60

var exploration: Node
var ui_parent: Node
var controls: RefCounted
var authored_root: Callable
var source: Dictionary = {}
var session: Dictionary = {}
var boards: Dictionary = {}
var last_result: Dictionary = {}
var locks: Array[Dictionary] = []
var sequence: int = 0
var game: Control
var view: RefCounted
var accumulator: float = 0
var focus_available: bool = true
var notice: String = ""
var notice_seconds: float = 0
var ui_scale: float = 1
var high_contrast: bool = false
var large_targets: bool = false

func _ready() -> void:
	get_tree().root.focus_exited.connect(focus_lost)
	get_tree().root.focus_entered.connect(focus_entered)

func root_data() -> Dictionary:
	return authored_root.call() if authored_root.is_valid() else source

func configure(data: Dictionary) -> void:
	source = data
	if active() and not Plan.enabled(root_data()): close("Arcade preview disabled.")

func active() -> bool:
	return not session.is_empty()

func available() -> bool:
	return exploration.enabled and not exploration.entering and not exploration.photo.active \
		and exploration.driving.active.is_empty() and exploration.props.active.is_empty() \
		and exploration.fitness.session.is_empty() and is_instance_valid(exploration.player) and Plan.enabled(root_data())

func manages(item: Dictionary) -> bool:
	return Plan.enabled(root_data()) and not Plan.game(item).is_empty()

func candidate(item: Dictionary, context: Dictionary) -> Dictionary:
	var id: String = Plan.game(item)
	if id.is_empty() or not Utility.availability(item,exploration.library,context["data"]).is_empty(): return {}
	var node: Node = context["instances"].get(item["uid"])
	if not is_instance_valid(node) or not node.is_visible_in_tree(): return {}
	var value: Dictionary = context.duplicate()
	value.merge({"node":node,"item":item,"game":id,"profile":Plan.operator_profile(item,exploration.library)})
	return value

func local_station(uid: String) -> Dictionary:
	var context: Dictionary = Props.context(exploration)
	for item in context["data"].get("objects",[]):
		if item["uid"] == uid: return candidate(item,context)
	return {}

func landing(station: Dictionary) -> Dictionary:
	var player: Node = exploration.player
	var point: Variant = Props.ground_point(station,exploration,"approach")
	var gap: Variant = point-player.global_position
	var near: bool = Vector2(gap.x/8,gap.y/4).length() <= 2.8 if exploration.dimension == "2d" \
		else absf(gap.y) <= 1.0 and Vector2(gap.x,gap.z).length() <= 2.5
	if not near: return {}
	# The approach is outside the cabinet. Its body must still block a path
	# through the front or back, so only exclude the actor from the ray.
	if gap.length() > .01 and not Props.reachable(exploration,player,point): return {}
	return {"point":point,"distance":gap.length()}

func nearby() -> Dictionary:
	if active() or not available(): return {}
	var context: Dictionary = Props.context(exploration)
	var best: Dictionary = {}
	for item in context["data"].get("objects",[]):
		var station: Dictionary = candidate(item,context)
		if station.is_empty(): continue
		var approach: Dictionary = landing(station)
		if approach.is_empty() or approach["distance"] >= best.get("distance",INF): continue
		best = station
		best.merge(approach)
	return best

func stamp(station: Dictionary) -> Array:
	return [station["scope"],station["node"].get_instance_id(),station["node"].global_transform,
		station["item"]["asset"],station["item"]["direction"],station["profile"]["approach"],station["game"]]

func report(text: String) -> void:
	notice = text
	notice_seconds = 6

func prompt(station: Dictionary = {}) -> String:
	if active(): return Plan.title(session["game"])+" · Arcade controls active"
	if station.is_empty(): return notice if notice_seconds > 0 else ""
	return "E · Play "+Plan.title(station["game"]) + (" · "+notice if notice_seconds > 0 else "")

func open_at(uid: String) -> bool:
	if active() or not available(): return false
	var station: Dictionary = local_station(uid)
	if station.is_empty(): return false
	var approach: Dictionary = landing(station)
	if approach.is_empty() or not Props.standing_clear(exploration,approach["point"]):
		report("Clear the cabinet’s player approach.")
		return false
	var root: Node = exploration.get_parent()
	var room: Node = station["world"]
	var key: String = station["scope"]+uid
	for location in ([root] if root == room else [root,room]):
		var registry: RefCounted = Reservations.for_world(location)
		var token: int = registry.acquire(key,self)
		if token == 0:
			release()
			report("This cabinet is already reserved.")
			return false
		locks.append({"registry":registry,"key":key,"token":token})
	var player: Node = exploration.player
	session = {"uid":uid,"stamp":stamp(station),"game":station["game"],"phase":"ready",
		"physics":player.is_physics_processing(),"actor":weakref(player),"run":0}
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO if player is Node2D else Vector3.ZERO
	focus_available = true
	if view == null: view = View.new(self)
	make_game()
	view.show_overlay()
	return true

func make_game() -> void:
	if is_instance_valid(game): game.free()
	game = GAMES[session["game"]].instantiate()
	view.screen.add_child(game)
	game.high_contrast = high_contrast
	accumulator = 0

func primary() -> void:
	if not active() or not focus_available: return
	match session["phase"]:
		"ready", "result":
			if session["phase"] == "result": make_game()
			sequence += 1
			session["run"] = sequence
			session["phase"] = "playing"
			game.begin()
		"playing": session["phase"] = "paused"
		"paused": session["phase"] = "playing"
	view.refresh()
	view.focus_primary()

func command(action: String) -> void:
	if not active() or session["phase"] != "playing" or not focus_available: return
	game.command(action)

func input(event: InputEvent, action: String) -> bool:
	if not active() or not event is InputEventKey: return false
	if action == "cancel" or event.keycode == KEY_ESCAPE:
		if event.pressed and not event.echo: close("Left the arcade cabinet.")
		return true
	if action in ["move_left","move_right","move_up","move_down"]:
		if event.pressed and not event.echo: command(action)
		return true
	if action == "interact":
		if event.pressed and not event.echo: primary()
		return true
	# Keep standard keyboard focus and button activation for the modal UI.
	if not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
		if event.keycode == KEY_TAB and action in ["","walk"]: return false
		if event.keycode in [KEY_ENTER,KEY_KP_ENTER,KEY_SPACE] and action in ["","jump"]: return false
	return true

func focus_lost() -> void:
	if not active(): return
	focus_available = false
	accumulator = 0
	if session["phase"] == "playing": session["phase"] = "paused"
	view.refresh()

func focus_entered() -> void:
	if not active(): return
	focus_available = true
	view.refresh()
	view.focus_primary()

func record_result() -> void:
	if session["phase"] != "playing" or not game.finished: return
	session["phase"] = "result"
	var id: String = session["game"]
	last_result = {"id":session["run"],"game":id,"score":game.score,"cabinet":session["uid"]}
	boards[id] = Plan.submit(boards.get(id,[]),last_result)
	view.focus_primary()

func valid_locks() -> bool:
	for lock in locks:
		if lock["registry"].current(lock["key"]).get("token") != lock["token"]: return false
	return not locks.is_empty()

func step(delta: float) -> void:
	notice_seconds = maxf(0,notice_seconds-delta)
	if not active(): return
	var actor: Node = session["actor"].get_ref()
	if not available() or actor != exploration.player:
		close("Arcade session interrupted.")
		return
	var station: Dictionary = local_station(session["uid"])
	if station.is_empty() or stamp(station) != session["stamp"] or not valid_locks():
		close("The cabinet moved, changed, or was removed.")
		return
	if session["phase"] == "playing" and focus_available:
		accumulator += minf(delta,.1)
		while accumulator+0.000001 >= TICK:
			accumulator -= TICK
			game.tick()
			if game.finished:
				record_result()
				break
	view.refresh()

func _physics_process(delta: float) -> void:
	step(delta)

func release() -> void:
	for lock in locks: lock["registry"].release(lock["key"],lock["token"])
	locks.clear()

func close(message: String = "") -> void:
	if not active(): return
	var actor: Node = session["actor"].get_ref()
	if is_instance_valid(actor): actor.set_physics_process(session["physics"])
	session.clear()
	release()
	if is_instance_valid(game): game.free()
	game = null
	accumulator = 0
	if view: view.hide_overlay()
	if not message.is_empty(): report(message)

func reset() -> void:
	close()
	boards.clear()
	last_result.clear()
	notice = ""
	notice_seconds = 0

func binding(id: String, fallback: String) -> String:
	if controls:
		var label: String = controls.label_for(id)
		return fallback if label.is_empty() else label
	return fallback
