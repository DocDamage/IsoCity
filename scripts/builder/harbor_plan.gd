extends RefCounted

const Terrain = preload("res://scripts/builder/terrain_plan.gd")
const Traffic = preload("res://scripts/builder/traffic_plan.gd")
const Fit = preload("res://scripts/builder/grid_fit.gd")
const Rotation = preload("res://scripts/builder/rotation.gd")
const Zone = preload("res://scripts/builder/zone_plan.gd")
const Behavior = preload("res://scripts/builder/asset_behavior.gd")
const Layers = Terrain.Layers
const VESSEL = "2d:Added_animated_tireme_c8c74bbe"
const PIER = "2d:Added_piers_pier_f248daea"
const OFFSETS = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
const MAX_DOCKS = 16
const MAX_BLOCKS = 100000
const MAX_DOCK_REACH = 12.0
const MAX_TRANSFER = 6.0
const BERTH_REACH = 1.15
const LEVEL_TOLERANCE = .035
const STEP = .25

static func valid_id(value: Variant) -> bool:
	return value is String and value.length() <= 128 and not value.contains("\n")

static func valid_point(value: Variant) -> bool:
	return (value is Array and value.size() == 2 and Terrain.number(value[0]) and Terrain.number(value[1])
		and absf(value[0]) <= MAX_DOCK_REACH and absf(value[1]) <= MAX_DOCK_REACH)

static func valid(value: Variant) -> bool:
	if not value is Dictionary or not value.get("enabled", false) is bool: return false
	var docks: Variant = value.get("docks", [])
	if not docks is Array or docks.size() > MAX_DOCKS: return false
	var seen: Dictionary = {}
	for dock in docks:
		if not dock is Dictionary or not valid_id(dock.get("anchor")): return false
		var id: String = dock["anchor"]
		if id.is_empty() or seen.has(id) or not valid_point(dock.get("land")) or not valid_point(dock.get("water")): return false
		seen[id] = true
	if not valid_id(value.get("pilot", "")) or not valid_id(value.get("shuttle", "")): return false
	if not value.get("shuttle", "").is_empty() and value.get("pilot", "") == value["shuttle"]: return false
	for key in ["origin", "destination"]:
		if not valid_id(value.get(key, "")): return false
	var interval: Variant = value.get("interval", 30)
	return Terrain.integer(interval) and interval >= 10 and interval <= 300

static func settings(data: Dictionary) -> Dictionary:
	var raw: Variant = data.get("harbor", {})
	if not valid(raw): raw = {}
	var value := {"enabled": false, "docks": [], "pilot": "", "shuttle": "", "origin": "", "destination": "", "interval": 30}
	value.merge(raw, true)
	return value

static func enabled(data: Dictionary) -> bool:
	return not data.get("interior_room", false) and settings(data)["enabled"]

static func hull(item: Dictionary) -> Dictionary:
	if item.get("asset", "") != VESSEL or item.has("missing_asset"): return {}
	var raw: Variant = item.get("scale", 1.0)
	if not Terrain.number(raw): return {}
	var scale_value: float = raw
	if scale_value < .18 or scale_value > 1.5: return {}
	# The reviewed trireme has one clean facing. A conservative circular
	# envelope covers its oars even when steered across that artwork's bearing.
	return {"radius": maxf(.35, 3.1 * scale_value), "draft": maxf(.25, .64 * scale_value),
		"air": maxf(.75, 4.8 * scale_value), "speed": 3.2}

static func cell(point: Vector2) -> Vector2i:
	return Vector2i((point / Terrain.CELL_SIZE).floor())

static func center(at: Vector2i) -> Vector2:
	return (Vector2(at) + Vector2.ONE * .5) * Terrain.CELL_SIZE

static func failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func compile(data: Dictionary, library: RefCounted = null) -> Dictionary:
	var result := {"ok": true, "reason": "", "waters": {}, "heights": {}, "blocks": {}, "items": {}}
	if not Terrain.settings(data)["enabled"] or not Layers.shown(data, "Ground"):
		return failure("Show and enable terrain before using the harbor.")
	var waters: Dictionary = {}
	for record in data.get("water_cells", []):
		var at := Vector2i(record["cell"][0], record["cell"][1])
		waters[at] = float(record["level"])
	if waters.is_empty(): return failure("Add connected water with sufficient depth.")
	result["waters"] = waters
	for vertex in data.get("terrain_vertices", []):
		result["heights"][Vector2i(vertex["cell"][0], vertex["cell"][1])] = float(vertex["height"])
	result["bounds"] = Terrain.bounds(data)
	for item in data["objects"]: result["items"][item["uid"]] = item
	if not library: return result

	var low := Vector2i(Terrain.MAX_CELL, Terrain.MAX_CELL)
	var high := Vector2i(Terrain.MIN_CELL, Terrain.MIN_CELL)
	for at: Vector2i in waters:
		low = low.min(at)
		high = high.max(at)
	var shore_area := Rect2i(low - Vector2i(4, 4), high - low + Vector2i(9, 9)).intersection(result["bounds"])
	var blocks: Dictionary = {}
	var count: int = 0
	var mode: String = data["mode"]
	var settings_value: Dictionary = settings(data)
	var assigned: Array = [settings_value["pilot"], settings_value["shuttle"]]
	for item in data["objects"]:
		if item["uid"] in assigned and item["asset"] == VESSEL: continue
		if item.has("missing_asset") or not item.get("visible", true): continue
		if not library.assets.has(item["asset"]) or not Layers.shown(data, Layers.layer(item, library)): continue
		var behavior: Dictionary = Behavior.for_asset(item["asset"], library)
		if behavior.get("ground", false) or behavior.get("collision", "box") == "none": continue
		var rect: Rect2 = Zone.footprint(item, mode, library)
		if not rect.has_area(): continue
		var base: float = float(item["position"][2] if mode == "2d" else item["position"][1])
		var shape: AABB
		if item["asset"].begins_with("3d:"):
			shape = Transform3D(Basis.from_euler(Rotation.euler(item) * PI / 180.0).scaled(Vector3.ONE * float(item["scale"])), Vector3.ZERO) 				* Fit.bounds_for(item["asset"], library, false)
		else:
			shape = Fit.sprite_box(item, library)
			shape.size *= float(item["scale"])
		var block := {"uid": item["uid"], "rect": rect, "bottom": base + shape.position.y, "top": base + maxf(.15, shape.end.y)}
		var start: Vector2i = cell(rect.position)
		var area := Rect2i(start, cell(rect.end) - start + Vector2i.ONE).intersection(shore_area)
		for x in range(area.position.x, area.end.x):
			for y in range(area.position.y, area.end.y):
				var at := Vector2i(x, y)
				if not blocks.has(at): blocks[at] = []
				blocks[at].append(block)
				count += 1
				if count > MAX_BLOCKS: return failure("Too many obstructions around the harbor. Use a smaller water area.")
	result["blocks"] = blocks
	return result

static func bed(plan: Dictionary, point: Vector2) -> float:
	var at: Vector2i = cell(point)
	var uv: Vector2 = point / Terrain.CELL_SIZE - Vector2(at)
	var heights: Dictionary = plan["heights"]
	var b: float = heights.get(at + Vector2i.RIGHT, 0.0)
	var c: float = heights.get(at + Vector2i.DOWN, 0.0)
	if uv.x + uv.y <= 1.0:
		var a: float = heights.get(at, 0.0)
		return a + (b - a) * uv.x + (c - a) * uv.y
	var d: float = heights.get(at + Vector2i.ONE, 0.0)
	return d + (c - d) * (1.0 - uv.x) + (b - d) * (1.0 - uv.y)

static func touches(rect: Rect2, point: Vector2, radius: float) -> bool:
	return point.distance_squared_to(point.clamp(rect.position, rect.end)) <= radius * radius

static func blocked(plan: Dictionary, at: Vector2i, point: Vector2, radius: float, bottom: float, top: float, except: String = "") -> bool:
	for obstacle in plan["blocks"].get(at, []):
		if not except.is_empty() and obstacle.get("uid") == except: continue
		if bottom < float(obstacle["top"]) + .03 and top > float(obstacle["bottom"]) - .03 \
			and touches(obstacle["rect"], point, radius): return true
	return false

static func passable(plan: Dictionary, point: Vector2, level: float, vessel: Dictionary) -> bool:
	if not plan.get("ok", false) or vessel.is_empty() or not point.is_finite() or not is_finite(level): return false
	var waters: Dictionary = plan["waters"]
	var heights: Dictionary = plan["heights"]
	var radius: float = vessel["radius"]
	var low: Vector2i = cell(point - Vector2.ONE * radius)
	var high: Vector2i = cell(point + Vector2.ONE * radius)
	for x in range(low.x, high.x + 1):
		for y in range(low.y, high.y + 1):
			var at := Vector2i(x, y)
			var extent := Rect2(Vector2(at) * Terrain.CELL_SIZE, Vector2.ONE * Terrain.CELL_SIZE)
			if not touches(extent, point, radius): continue
			var surface: float = waters.get(at, INF)
			if absf(surface - level) > LEVEL_TOLERANCE: return false
			# Both triangular bed faces lie below their highest corner. Treat
			# a partly shallow cell as closed so a wide hull cannot clip shoals.
			for offset in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.ONE]:
				if surface - float(heights.get(at + offset, 0.0)) < vessel["draft"]: return false
			if blocked(plan, at, point, radius, level - vessel["draft"], level + vessel["air"]): return false
	return true

static func travel(plan: Dictionary, a: Vector2, b: Vector2, level: float, vessel: Dictionary) -> bool:
	if not a.is_finite() or not b.is_finite(): return false
	var count: int = maxi(1, ceili(a.distance_to(b) / STEP))
	if count > 256: return false
	for index in range(count + 1):
		if not passable(plan, a.lerp(b, float(index) / count), level, vessel): return false
	return true

static func shore_safe(plan: Dictionary, point: Vector2) -> bool:
	if not plan.get("ok", false) or not point.is_finite(): return false
	var ground: float = bed(plan, point)
	for offset in [Vector2.ZERO, Vector2(.3, 0), Vector2(-.3, 0), Vector2(0, .3), Vector2(0, -.3)]:
		var sample: Vector2 = point + offset
		var at: Vector2i = cell(sample)
		if not plan["bounds"].has_point(at): return false
		var height: float = bed(plan, sample)
		if absf(height - ground) > .28 or float(plan["waters"].get(at, -INF)) - height > .04: return false
		if blocked(plan, at, sample, 0, height + .04, height + 1.7): return false
	return true

static func socket(plan: Dictionary, data: Dictionary, definition: Dictionary, vessel: Dictionary) -> Dictionary:
	if not plan.get("ok", false): return failure(plan["reason"])
	var anchor: Dictionary = plan["items"].get(definition.get("anchor", ""), {})
	if (anchor.get("asset", "") != PIER or anchor.has("missing_asset") or not anchor.get("visible", true)
		or not Layers.shown(data, Layers.layer(anchor, null))):
		return failure("Restore the dock's visible pier.")
	var origin: Vector2 = Traffic.metric(anchor["position"], data["mode"])
	var land: Vector2 = origin + Vector2(definition["land"][0], definition["land"][1])
	var water: Vector2 = origin + Vector2(definition["water"][0], definition["water"][1])
	var level: float = plan["waters"].get(cell(water), INF)
	if not shore_safe(plan, land): return failure("The dock needs a dry, clear landing.")
	if land.distance_to(water) > MAX_TRANSFER: return failure("Move the berth within six metres of its landing.")
	if not is_finite(level) or not passable(plan, water, level, vessel):
		return failure("The berth lacks depth or clearance for this vessel.")
	var distance: float = land.distance_to(water)
	var samples: int = maxi(1, ceili(distance / STEP))
	for index in range(1, samples):
		var at: Vector2 = land.lerp(water, float(index) / samples)
		var ground: float = maxf(bed(plan, at), plan["waters"].get(cell(at), -INF))
		if blocked(plan, cell(at), at, .24, ground + .04, ground + 1.7, anchor["uid"]):
			return failure("The boarding connection is obstructed.")
	return {"ok": true, "anchor": anchor["uid"], "land": land, "land_y": bed(plan, land),
		"water": water, "level": level, "reason": ""}

static func moored_at(plan: Dictionary, point: Vector2, dock: Dictionary, hull: Dictionary) -> bool:
	return (dock["ok"] and point.distance_to(dock["water"]) <= BERTH_REACH
		and travel(plan, point, dock["water"], dock["level"], hull))

static func route(plan: Dictionary, from: Dictionary, to: Dictionary, vessel: Dictionary) -> Dictionary:
	if not plan.get("ok", false): return failure(plan["reason"])
	if not from.get("ok", false) or not to.get("ok", false): return failure("Both docks need safe berths and dry landings.")
	var level: float = from["level"]
	if absf(float(to["level"]) - level) > LEVEL_TOLERANCE: return failure("The docks are on different water levels.")
	var first: Vector2i = cell(from["water"])
	var goal: Vector2i = cell(to["water"])
	if first == goal:
		if not travel(plan, from["water"], to["water"], level, vessel):
			return failure("The short berth crossing is obstructed.")
		return {"ok": true, "points": [from["water"], to["water"]], "level": level}
	if not travel(plan, from["water"], center(first), level, vessel) or not travel(plan, center(goal), to["water"], level, vessel):
		return failure("A berth has no clear connection to the water route.")
	var queue: Array[Vector2i] = [first]
	var visited: Dictionary = {first: first}
	var index: int = 0
	while index < queue.size():
		var here: Vector2i = queue[index]
		index += 1
		if here == goal:
			var points: Array[Vector2] = [to["water"]]
			while here != first:
				points.append(center(here))
				here = visited[here]
			points.append(center(first))
			points.append(from["water"])
			points.reverse()
			return {"ok": true, "points": points, "level": level}
		for offset in OFFSETS:
			var next: Vector2i = here + offset
			if visited.has(next) or not plan["waters"].has(next): continue
			if not travel(plan, center(here), center(next), level, vessel): continue
			visited[next] = here
			queue.append(next)
	return failure("No connected route has enough depth and clearance.")
