extends RefCounted

const PATH = "res://resources/catalog/cycling.json"
const Traffic = preload("res://scripts/builder/traffic_plan.gd")
const Utility = preload("res://scripts/builder/utility_profiles.gd")
const Terrain = Utility.Terrain
const Roads = Traffic.Roads
const GRID = 8.0
const MAX_RACK_GAP = 5.5
const RIDE_SCALE_MIN = .65
const RIDE_SCALE_MAX = 1.5
static var catalog: Dictionary

static func definitions() -> Dictionary:
	if catalog.is_empty():
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if raw is Dictionary and raw.get("version") == 1: catalog = raw
	return catalog

static func enabled(data: Dictionary) -> bool:
	var setting: Variant = data.get("cycling",{})
	return not data.get("interior_room",false) and valid(setting) and setting.get("enabled",false)

static func valid(setting: Variant) -> bool:
	return setting is Dictionary and setting.get("enabled",false) is bool

static func valid_vehicle(setting: Variant) -> bool:
	return valid(setting) and setting.get("npc",false) is bool and setting.get("rack","") is String and setting.get("rack","").length() <= 128

static func asset_profile(id: String, mode: String) -> Dictionary:
	var metadata: Dictionary = definitions()["assets"].get(id,{})
	if metadata.is_empty() or mode not in metadata["modes"]: return {}
	var result: Dictionary = catalog["profiles"][metadata["kind"]].duplicate()
	result.merge(metadata,true)
	if metadata.has("pixel"): result["view_yaws"] = catalog["pixel_yaw"]
	return result

static func profile(item: Dictionary, data: Dictionary) -> Dictionary:
	if not enabled(data) or item.has("missing_asset"): return {}
	var value: Variant = item.get("cycling",{})
	if not valid_vehicle(value) or not value.get("enabled",false): return {}
	var size: float = item.get("scale",1.0)
	if size < RIDE_SCALE_MIN or size > RIDE_SCALE_MAX: return {}
	var result: Dictionary = asset_profile(item.get("asset",""),data["mode"])
	if result.is_empty(): return {}
	result["cycle"] = true
	return result

static func rack(item: Dictionary) -> bool:
	return item.get("asset","") in definitions()["racks"]

static func copy_reference(item: Dictionary, identities: Dictionary) -> void:
	var value: Variant = item.get("cycling",{})
	if not valid_vehicle(value) or value.get("rack","").is_empty(): return
	if identities.has(value["rack"]): value["rack"] = identities[value["rack"]]
	else:
		value["rack"] = ""
		value["npc"] = false

static func compile(data: Dictionary) -> Dictionary:
	var roads: Dictionary = Traffic.build(data)
	var plan: Dictionary = {"mode":data["mode"],"sections":{},"edges":{},"roads":roads}
	if not enabled(data) or not Utility.Layers.shown(data,"Ground"): return plan
	for key in roads["keys"]:
		var section: Dictionary = roads["sections"][key]
		if section["cycle_access"] == "none": continue
		plan["sections"][key] = {"center":Traffic.center(section["cell"],data["mode"]),
			"width":section["width"],"access":section["cycle_access"],"neighbors":section["neighbors"]}
	var rules: Dictionary = roads["controls"]["sections"]
	for key in plan["sections"]:
		var section: Dictionary = roads["sections"][key]
		for next in section["neighbors"]:
			if not plan["sections"].has(next): continue
			var direction: Vector2i = roads["sections"][next]["cell"]-section["cell"]
			if Traffic.Signals.permits_edge(rules,key,next,direction):
				var id: String = Traffic.edge_id(key,next)
				plan["edges"][id] = true
				# The junction coordinator shares one owner table with motor
				# traffic. Its local network also needs each legal cycle approach.
				if not roads["edges"].has(id): roads["edges"][id] = {"from":key,"to":next}
	return plan

static func cell_key(point: Vector2, plan: Dictionary) -> String:
	return Roads.key(Vector2i(((point-Traffic.center(Vector2i.ZERO,plan["mode"]))/GRID).round()))

static func fits(section: Dictionary, profile_value: Dictionary, extent: Vector2) -> bool:
	return not section.is_empty() and section["access"] in profile_value["access"] and extent.x*2+.18 <= section["width"]

static func track_contains(point: Vector2, plan: Dictionary, profile_value: Dictionary, extent: Vector2) -> bool:
	var key: String = cell_key(point,plan)
	var section: Dictionary = plan["sections"].get(key,{})
	if not fits(section,profile_value,extent): return false
	var offset: Vector2 = point-section["center"]
	var half: float = section["width"]*.5
	if offset.abs().x <= half and offset.abs().y <= half: return true
	for next in section["neighbors"]:
		var other: Dictionary = plan["sections"].get(next,{})
		if not fits(other,profile_value,extent): continue
		if not (plan["edges"].has(Traffic.edge_id(key,next)) or plan["edges"].has(Traffic.edge_id(next,key))): continue
		var axis: Vector2 = (other["center"]-section["center"])/GRID
		var along: float = offset.dot(axis)
		var across: float = absf(offset.cross(axis))
		if along >= 0 and along <= GRID*.5+.001 and across <= lerpf(half,other["width"]*.5,along/GRID):
			return true
	return false

static func allows(plan: Dictionary, profile_value: Dictionary, extent: Vector2, from: Vector2, point: Vector2, yaw: float) -> bool:
	var start: String = cell_key(from,plan)
	var finish: String = cell_key(point,plan)
	if start != finish and not plan["edges"].has(Traffic.edge_id(start,finish)): return false
	var forward := Vector2(sin(yaw),cos(yaw))
	var right := Vector2(forward.y,-forward.x)
	for offset in [Vector2.ZERO,forward*extent.y+right*extent.x,forward*extent.y-right*extent.x,
		-forward*extent.y+right*extent.x,-forward*extent.y-right*extent.x]:
		if not track_contains(point+offset,plan,profile_value,extent): return false
	return true

static func object(data: Dictionary, uid: String) -> Dictionary:
	for item in data.get("objects",[]):
		if item["uid"] == uid: return item
	return {}

static func route(plan: Dictionary, from: String, to: String, settings: Dictionary, extent: Vector2) -> PackedStringArray:
	var sections: Dictionary = plan["sections"]
	if not fits(sections.get(from,{}),settings,extent) or not fits(sections.get(to,{}),settings,extent): return []
	var previous: Dictionary = {from:""}
	var queue: Array[String] = [from]
	var index: int = 0
	while index < queue.size() and not previous.has(to):
		var key: String = queue[index]
		index += 1
		for next in sections[key]["neighbors"]:
			if previous.has(next) or not plan["edges"].has(Traffic.edge_id(key,next)) or not fits(sections.get(next,{}),settings,extent):
				continue
			previous[next] = key
			queue.append(next)
	if not previous.has(to): return []
	var result: PackedStringArray = []
	while not to.is_empty():
		result.append(to)
		to = previous[to]
	result.reverse()
	return result

static func rack_route(data: Dictionary, plan: Dictionary, item: Dictionary, profile_value: Dictionary, extent: Vector2,
	from: Vector2, library: RefCounted) -> Dictionary:
	var uid: String = item.get("cycling",{}).get("rack","")
	var fixture: Dictionary = object(data,uid)
	if not rack(fixture) or not Utility.availability(fixture,library,data).is_empty():
		return {"reason":"Link a visible bicycle rack."}
	var point: Vector2 = Utility.footprint(fixture,library,data["mode"]).get_center()
	var choices: Array[Dictionary] = []
	for key in plan["sections"]:
		var gap: float = point.distance_to(plan["sections"][key]["center"])
		if gap <= MAX_RACK_GAP and fits(plan["sections"][key],profile_value,extent): choices.append({"key":key,"gap":gap})
	choices.sort_custom(func(a: Dictionary,b: Dictionary)->bool: return a["gap"] < b["gap"] if a["gap"] != b["gap"] else a["key"] < b["key"])
	for option in choices:
		var keys: PackedStringArray = route(plan,cell_key(from,plan),option["key"],profile_value,extent)
		if keys.is_empty(): continue
		var points := PackedVector2Array([from])
		var first: Vector2 = plan["sections"][keys[0]]["center"]
		var begin: int = 0
		if keys.size() > 1:
			var ahead: Vector2 = (plan["sections"][keys[1]]["center"]-first).normalized()
			if (from-first).dot(ahead) > 0 and absf((from-first).cross(ahead)) < .4: begin = 1
		for index in range(begin,keys.size()):
			var key: String = keys[index]
			var next: Vector2 = plan["sections"][key]["center"]
			if points[-1].distance_to(next) > .05: points.append(next)
		return {"rack":uid,"point":point,"finish":points[-1],"path":rounded(points),"sections":keys,"reason":""}
	return {"reason":"No connected cycle route reaches the rack. Tag adjoining road sections and place the rack beside them."}

static func rounded(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() <= 2: return points
	var result := PackedVector2Array([points[0]])
	for index in range(1,points.size()-1):
		var center: Vector2 = points[index]
		var radius: float = minf(.72,minf(center.distance_to(points[index-1]),center.distance_to(points[index+1]))*.4)
		var before: Vector2 = center.move_toward(points[index-1],radius)
		var after: Vector2 = center.move_toward(points[index+1],radius)
		result.append(before)
		for part in range(1,6):
			var t: float = part/5.0
			result.append(before.lerp(center,t).lerp(center.lerp(after,t),t))
	result.append(points[-1])
	return result
