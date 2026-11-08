extends RefCounted

const Roads = preload("res://scripts/builder/roads.gd")
const Rotation = preload("res://scripts/builder/rotation.gd")
const SOURCE = "res://resources/catalog/traffic_controls.json"
const KINDS = ["stop", "yield", "signal", "one_way"]
const DEFAULT_TIMING = {"green": 8.0, "walk": 5.0, "clear": 2.0}
const RANGE = 8.0
const AMBER = 1.0
static var catalog: Dictionary = {}

static func definitions() -> Dictionary:
	if catalog.is_empty():
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
		if value is Dictionary and value.get("version") == 1:
			catalog = value
	return catalog

static func profile(asset: String) -> Dictionary:
	return definitions().get("assets", {}).get(asset, {})

static func valid(raw: Variant) -> bool:
	if not raw is Dictionary or raw.get("kind") not in KINDS:
		return false
	var cell: Variant = raw.get("cell")
	if not cell is Array or cell.size() != 2:
		return false
	for value in cell:
		if not (value is int or value is float) or not is_finite(value) or absf(value) > 100000 or value != floorf(value):
			return false
	var side: Variant = raw.get("side")
	if not (side is int or side is float) or not is_finite(side) or side < 0 or side > 3 or side != floorf(side):
		return false
	if raw["kind"] != "signal":
		return not raw.has("timing")
	var timing: Variant = raw.get("timing")
	if not timing is Dictionary:
		return false
	for key in DEFAULT_TIMING:
		var duration: Variant = timing.get(key)
		var range_limit: Vector2 = Vector2(1, 8) if key == "clear" else Vector2(3, 45)
		if not (duration is int or duration is float) or not is_finite(duration) or duration < range_limit.x or duration > range_limit.y:
			return false
	return true

static func facing(item: Dictionary, mode: String) -> int:
	var axis: Vector2
	if item.get("asset", "").begins_with("3d:"):
		var angles: Vector3 = Rotation.euler(item)
		var front: Vector3 = Basis.from_euler(angles * PI / 180.0).z
		if absf(front.y) > .25:
			return -1
		axis = Vector2(front.x, front.z)
	else:
		if mode != "2d":
			return -1
		var side: int = ["SE", "SW", "NW", "NE"].find(item.get("direction", ""))
		if side < 0:
			return -1
		var step: Vector2i = Roads.STEPS[side]
		var pixel := Vector2((step.x - step.y) * 8.0, (step.x + step.y) * 4.0)
		pixel = pixel.rotated(deg_to_rad(item.get("angle", 0.0)))
		axis = Vector2(pixel.x / 16.0 + pixel.y / 8.0, pixel.y / 8.0 - pixel.x / 16.0)
	axis = axis.normalized()
	for index in Roads.STEPS.size():
		if axis.dot(Vector2(Roads.STEPS[index])) > .965:
			return posmod(index + int(profile(item["asset"]).get("turn", 0)), 4)
	return -1

static func road_cell(binding: Dictionary) -> Vector2i:
	return Vector2i(binding["cell"][0],binding["cell"][1])

static func road_center(cell: Vector2i, mode: String) -> Vector2:
	return Vector2(cell) * 8 + (Vector2.ONE if mode == "2d" else Vector2.ZERO)

static func reason(item: Dictionary, binding: Dictionary, sections: Dictionary, mode: String, point: Vector2) -> String:
	if not valid(binding):
		return "The saved traffic control is invalid."
	if item.has("missing_asset") or profile(item["asset"]).get("kind") != binding["kind"]:
		return "The original traffic sign or signal is unavailable."
	if not item.get("visible", true):
		return "The hidden traffic control is inactive."
	var cell: Vector2i = road_cell(binding)
	var road: Dictionary = sections.get(Roads.key(cell), {})
	if road.is_empty() or point.distance_to(road_center(cell, mode)) > RANGE:
		return "The bound road is absent or too far from this object."
	var step: Vector2i = Roads.STEPS[int(binding["side"])]
	var neighbor: String = Roads.key(cell + step)
	if neighbor not in road["neighbors"]:
		return "The bound road approach is absent."
	if facing(item, mode) != int(binding["side"]):
		return "The artwork faces a different road approach."
	if binding["kind"] == "one_way" and (road["neighbors"].size() != 2 or Roads.key(cell - step) not in road["neighbors"]):
		return "Bind a one-way sign to a straight section with two connected ends."
	if binding["kind"] == "signal" and road["neighbors"].size() < 3:
		return "A signal needs a junction with at least three approaches."
	return ""

static func nearest(item: Dictionary, sections: Dictionary, mode: String, point: Vector2, timing: Dictionary) -> Dictionary:
	var kind: String = profile(item.get("asset", "")).get("kind", "")
	if kind.is_empty():
		return {"reason": "Choose a supported stop sign, yield sign, one-way sign or signal."}
	var side: int = facing(item, mode)
	if side < 0:
		return {"reason": "Face the sign along a road axis in its native world."}
	var keys: Array = sections.keys()
	keys.sort()
	var best: Dictionary = {}
	var best_distance: float = RANGE + .0001
	var nearest_issue: String = "No road is close enough to bind this object."
	var nearest_distance: float = INF
	for key in keys:
		var cell: Vector2i = sections[key]["cell"]
		var distance: float = road_center(cell, mode).distance_to(point)
		if distance > best_distance:
			continue
		var candidate: Dictionary = {"kind": kind, "cell": [cell.x, cell.y], "side": side}
		if kind == "signal":
			candidate["timing"] = timing.duplicate()
		var issue: String = reason(item, candidate, sections, mode, point)
		if issue.is_empty() and (best.is_empty() or distance < best_distance):
			best = candidate
			best_distance = distance
		elif distance < nearest_distance:
			nearest_issue = issue
			nearest_distance = distance
	return {"binding": best} if not best.is_empty() else {"reason": nearest_issue}

static func compile(data: Dictionary, sections: Dictionary, metric: Callable) -> Dictionary:
	var mode: String = data.get("mode", "2d")
	var grouped: Dictionary = {}
	var issues: Dictionary = {}
	for item in data.get("objects", []):
		if not item is Dictionary or not item.has("traffic_control"):
			continue
		var binding: Dictionary = item["traffic_control"] if item["traffic_control"] is Dictionary else {}
		var uid: String = item["uid"]
		var issue: String = reason(item, binding, sections, mode, metric.call(item["position"], mode))
		if not issue.is_empty():
			issues[uid] = issue
			continue
		var cell: Vector2i = road_cell(binding)
		var key: String = Roads.key(cell)
		if not grouped.has(key):
			grouped[key] = []
		grouped[key].append({"uid": uid, "binding": binding})
	var controls: Dictionary = {}
	var active: Dictionary = {}
	for key in grouped:
		var junction: Dictionary = merge(grouped[key], sections[key]["cell"])
		if junction.is_empty():
			for entry in grouped[key]:
				issues[entry["uid"]] = "Traffic controls conflict at this road. Rebind or remove the conflicting control."
			continue
		controls[key] = junction
		for entry in grouped[key]:
			active[entry["uid"]] = key
	return {"sections": controls, "issues": issues, "active": active}

static func merge(entries: Array, cell: Vector2i) -> Dictionary:
	var result: Dictionary = {"approaches": {}}
	for entry in entries:
		var binding: Dictionary = entry["binding"]
		var kind: String = binding["kind"]
		var side: int = binding["side"]
		if kind == "signal":
			var timing: Dictionary = {}
			for key in DEFAULT_TIMING:
				timing[key] = float(binding["timing"][key])
			if not result["approaches"].is_empty() or result.has("one_way") or result.get("signal", timing) != timing:
				return {}
			result["signal"] = timing
		elif kind == "one_way":
			if result.has("signal") or not result["approaches"].is_empty() or result.get("one_way", side) != side:
				return {}
			result["one_way"] = side
		else:
			var approach: String = Roads.key(cell + Roads.STEPS[side])
			if result.has("signal") or result.has("one_way") or result["approaches"].get(approach, kind) != kind:
				return {}
			result["approaches"][approach] = kind
	return result

static func permits_edge(controls: Dictionary, from: String, to: String, direction: Vector2i) -> bool:
	for key in [from, to]:
		var side: int = controls.get(key, {}).get("one_way", -1)
		if side >= 0 and Roads.STEPS[side] != direction:
			return false
	return true

static func phase(timing: Dictionary, age: float) -> String:
	var clear: float = timing["clear"]
	var green: float = timing["green"]
	var walk: float = timing["walk"]
	var at: float = fposmod(maxf(0, age), green * 2 + AMBER * 2 + clear * 3 + walk)
	for interval in [[clear, "red"], [green, "x"], [AMBER, "amber_x"], [clear, "red"],
			[green, "y"], [AMBER, "amber_y"], [clear, "red"], [walk, "walk"]]:
		if at < interval[0]:
			return interval[1]
		at -= interval[0]
	return "red"

static func pedestrian_in_section(point: Vector2, center: Vector2) -> bool:
	var offset: Vector2 = (point - center).abs()
	return offset.x < 3.6 and offset.y < 3.6

static func approach_axis(road: Dictionary, approach: Dictionary) -> String:
	if approach.is_empty():
		return ""
	return "x" if road["cell"].x != approach["cell"].x else "y"
