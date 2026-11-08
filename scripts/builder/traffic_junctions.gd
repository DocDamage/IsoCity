extends RefCounted

const Signals = preload("res://scripts/builder/traffic_control_plan.gd")
const MAX_YIELD = 8.0
var queues: Dictionary = {}
var owners: Dictionary = {}
var owner_axes: Dictionary = {}
var waiting_since: Dictionary = {}
var approaches: Dictionary = {}
var signals: Dictionary = {}
var phase_start: Dictionary = {}
var holds: Dictionary = {}

func synchronize(plan: Dictionary, now: float) -> void:
	var controls: Dictionary = plan.get("controls", {}).get("sections", {})
	for section in holds.keys():
		if now >= holds[section]:
			holds.erase(section)
	for section in signals.keys():
		if not controls.get(section, {}).has("signal"):
			update_signal(section, {}, now)
	for section in controls:
		if controls[section].has("signal"):
			update_signal(section, controls[section]["signal"], now)

func update_signal(section: String, timing: Dictionary, now: float) -> void:
	var previous: Dictionary = signals.get(section, {})
	if previous == timing:
		return
	if timing.is_empty():
		holds[section] = now + previous["clear"]
		signals.erase(section)
		phase_start.erase(section)
	else:
		if not previous.is_empty():
			holds[section] = now + maxf(previous["clear"], timing["clear"])
		signals[section] = timing
		phase_start[section] = now

func phase(plan: Dictionary, section: String, now: float) -> String:
	var timing: Dictionary = plan.get("controls", {}).get("sections", {}).get(section, {}).get("signal", {})
	update_signal(section, timing, now)
	if now < holds.get(section, -INF):
		return "red"
	holds.erase(section)
	if timing.is_empty():
		return ""
	var planned: String = Signals.phase(timing, now - phase_start[section])
	var movement: String = planned.trim_prefix("amber_")
	if owners.has(section) and planned != "red" and movement != owner_axes.get(section, ""):
		return "red"
	return planned

func deny(reason: String) -> Dictionary:
	return {"allowed": false, "reason": reason}

func request(plan: Dictionary, vehicle: String, section: String, now: float, pedestrians: bool = false, approach: String = "") -> Dictionary:
	var road: Dictionary = plan["sections"].get(section, {})
	if road.is_empty():
		return deny("Road removed")
	if owners.get(section, "") == vehicle:
		return {"allowed": true, "reason": ""}
	if not approach.is_empty() and not plan["edges"].has(approach + ">" + section):
		return deny("This lane is one-way")
	var control: Dictionary = plan.get("controls", {}).get("sections", {}).get(section, {})
	var current: String = phase(plan, section, now)
	if current == "red":
		return deny("All-red clearance")
	if current == "walk":
		return deny("Pedestrian crossing phase")
	if control.has("signal"):
		var axis: String = Signals.approach_axis(road, plan["sections"].get(approach, {}))
		if current != axis or axis.is_empty():
			return deny("Traffic signal amber" if current == "amber_" + axis else "Traffic signal red")
	var crossing: bool = road["crossing"] or road["neighbors"].size() >= 3
	if (crossing or not control.is_empty()) and pedestrians:
		return deny("Pedestrian crossing occupied" if not control.is_empty() else "Pedestrian crossing")
	if crossing and not control.has("signal") and fposmod(now, 10.0) < 2.5:
		return deny("Pedestrian crossing")
	var rules: Dictionary = control.get("approaches", {})
	if road["neighbors"].size() < 3 and rules.is_empty():
		return {"allowed": true, "reason": ""}
	if not queues.has(section):
		queues[section] = []
	var queue: Array = queues[section]
	var key: String = vehicle + "@" + section
	if vehicle not in queue:
		queue.append(vehicle)
		waiting_since[key] = now
	approaches[key] = approach
	var default_stop: bool = not control.has("signal") and rules.is_empty()
	var own_rule: String = "stop" if default_stop else rules.get(approach, "")
	if own_rule == "stop" and now - float(waiting_since[key]) < 1:
		return deny("Intersection stop")
	if owners.has(section) or first_eligible(plan, section, current, rules, default_stop, now) != vehicle:
		return deny("Yielding at intersection")
	owners[section] = vehicle
	owner_axes[section] = current
	forget(vehicle, section)
	return {"allowed": true, "reason": ""}

func first_eligible(plan: Dictionary, section: String, current: String, rules: Dictionary, default_stop: bool, now: float) -> String:
	var first: String = ""
	for id in queues[section]:
		var key: String = id + "@" + section
		var approach: String = approaches[key]
		var age: float = now - float(waiting_since[key])
		if not current.is_empty() and Signals.approach_axis(plan["sections"][section], plan["sections"].get(approach, {})) != current:
			continue
		if default_stop:
			return id
		var rule: String = rules.get(approach, "")
		if rule == "stop" and age < 1:
			continue
		if age >= MAX_YIELD or rule.is_empty():
			return id
		if first.is_empty():
			first = id
	return first

func forget(vehicle: String, section: String) -> void:
	queues[section].erase(vehicle)
	waiting_since.erase(vehicle + "@" + section)
	approaches.erase(vehicle + "@" + section)

func release(vehicle: String, section: String = "") -> void:
	for key in queues.keys():
		if not section.is_empty() and section != key:
			continue
		forget(vehicle, key)
		if owners.get(key, "") == vehicle:
			owners.erase(key)
			owner_axes.erase(key)
		if queues[key].is_empty() and not owners.has(key):
			queues.erase(key)

func clear() -> void:
	queues.clear()
	owners.clear()
	owner_axes.clear()
	waiting_since.clear()
	approaches.clear()
	signals.clear()
	phase_start.clear()
	holds.clear()
