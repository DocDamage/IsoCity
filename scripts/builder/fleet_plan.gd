extends RefCounted

const SOURCE = "res://resources/catalog/fleet.json"
const DRIVE_ART = "res://resources/catalog/driving.json"
const ROLES = ["traffic", "transit", "fire", "medical", "police", "sanitation"]
const MAX_CHOICES = 32
const ROAD_MARGIN = .04
const BAY_MARGIN = .15
static var catalog: Dictionary = {}
static var art: Dictionary = {}

static func definitions() -> Dictionary:
	if catalog.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
		if parsed is Dictionary and parsed.get("version") == 1:
			catalog = parsed["assets"]
	return catalog

static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.size() > ROLES.size():
		return false
	for role in value:
		var choices: Variant = value[role]
		if role not in ROLES or not choices is Array or choices.size() > MAX_CHOICES:
			return false
		var seen: Dictionary = {}
		for choice in choices:
			if not choice is Dictionary or not choice.get("asset") is String:
				return false
			var asset: String = choice["asset"]
			var weight: Variant = choice.get("weight")
			if asset.is_empty() or asset.length() > 512 or seen.has(asset) or not (weight is int or weight is float):
				return false
			if not is_finite(weight) or weight < 0 or weight > 100 or weight != floorf(weight):
				return false
			seen[asset] = true
	return true

static func allowed_for(asset: String, mode: String, role: String) -> bool:
	return asset.begins_with(mode + ":") and role in definitions().get(asset, {}).get("roles", [])

static func offered(mode: String, role: String) -> Array:
	var result: Array = definitions().keys().filter(func(id: String): return allowed_for(id, mode, role))
	result.sort()
	return result

static func selections(data: Dictionary, role: String) -> Array:
	var config: Dictionary = data.get("fleet", {})
	if config.has(role):
		return config[role]
	var result: Array = []
	for id in offered(data["mode"], role):
		var profile: Dictionary = definitions()[id]
		if profile.get("default", false):
			result.append({"asset": id, "weight": int(profile["weight"])})
	return result

static func required(data: Dictionary, enabled_roles: Array = []) -> Dictionary:
	var result: Dictionary = {}
	for role in ROLES:
		if role not in enabled_roles and not data.get("fleet", {}).has(role):
			continue
		for choice in selections(data, role):
			result[choice["asset"]] = true
	return result

static func views(id: String, profile: Dictionary) -> Dictionary:
	if profile["heading"] == "sprite_cardinal":
		return {"NE": 0, "SE": 90, "SW": 180, "NW": 270}
	if profile["heading"] != "sprite_reviewed":
		return {}
	if art.is_empty():
		art = JSON.parse_string(FileAccess.get_file_as_string(DRIVE_ART)).get("assets", {})
	return art.get(id, {}).get("view_yaws", {})

static func usable(id: String, mode: String, role: String, library: RefCounted) -> bool:
	if not allowed_for(id, mode, role) or not library.assets.has(id):
		return false
	var asset: Dictionary = library.assets[id]
	if asset.get("unavailable", false) or not ResourceLoader.exists(asset["path"], "PackedScene"):
		return false
	if mode == "2d":
		var required_views: Dictionary = views(id, definitions()[id])
		if required_views.is_empty() or required_views.keys().any(func(key: String): return key not in library.directions(id)):
			return false
	return true

static func pool(data: Dictionary, role: String, library: RefCounted) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for choice in selections(data, role):
		var id: String = choice["asset"]
		if choice["weight"] <= 0 or not usable(id, data["mode"], role, library):
			continue
		var profile: Dictionary = definitions()[id].duplicate()
		profile["asset"] = id
		profile["weight"] = int(choice["weight"])
		profile["view_yaws"] = views(id, profile)
		result.append(profile)
	result.sort_custom(func(a: Dictionary, b: Dictionary): return a["asset"] < b["asset"])
	return result

static func choose(pool_value: Array, seed: int, identity: String, fits: Callable = Callable()) -> Dictionary:
	var candidates: Array = pool_value.filter(fits) if fits.is_valid() else pool_value
	var total: int = 0
	for candidate in candidates:
		total += int(candidate["weight"])
	if total <= 0:
		return {}
	var draw: int = ("%d|%s" % [seed, identity]).sha256_text().left(8).hex_to_int() % total
	for candidate in candidates:
		draw -= int(candidate["weight"])
		if draw < 0:
			return candidate
	return {}

static func direction(profile: Dictionary, heading: Vector2) -> String:
	var angle: float = atan2(heading.x, heading.y)
	var mappings: Dictionary = profile.get("view_yaws", {})
	if mappings.is_empty():
		return str(rad_to_deg(angle))
	var best: String = ""
	var distance: float = INF
	for view in mappings:
		var delta: float = absf(angle_difference(angle, deg_to_rad(mappings[view])))
		if delta < distance:
			distance = delta
			best = view
	return best

static func fit_edge(network: Dictionary, from: String, to: String, profile: Dictionary) -> bool:
	if not network["edges"].has(from + ">" + to):
		return false
	if profile.is_empty():
		return true
	var lane: float = minf(network["sections"][from]["width"], network["sections"][to]["width"]) * .5
	return profile["width"] <= lane + ROAD_MARGIN

static func fit_turn(network: Dictionary, from: String, at: String, to: String, profile: Dictionary) -> bool:
	if not fit_edge(network, at, to, profile):
		return false
	if from.is_empty() or profile.is_empty():
		return true
	if not fit_edge(network, from, at, profile):
		return false
	var a: Vector2i = network["sections"][from]["cell"]
	var b: Vector2i = network["sections"][at]["cell"]
	var c: Vector2i = network["sections"][to]["cell"]
	return b-a == c-b or network["sections"][at]["width"] >= profile["turn_road_width"]

static func fit_route(network: Dictionary, route: PackedStringArray, profile: Dictionary) -> bool:
	if route.is_empty():
		return false
	for index in range(1, route.size()):
		if not fit_turn(network, route[index-2] if index>=2 else "", route[index-1], route[index], profile):
			return false
	return true

static func fit_bay(bay: Dictionary, profile: Dictionary) -> bool:
	return profile.is_empty() or profile["length"]+BAY_MARGIN <= bay["length"] and profile["width"]+BAY_MARGIN <= bay["width"]

static func vehicle_fields(profile: Dictionary) -> Dictionary:
	return {"asset": profile["asset"], "size": profile["scale"], "half_length": profile["length"]*.5,
		"half_width": profile["width"]*.5, "fleet_profile": profile}

static func overlaps(a: Dictionary, point: Vector2, heading: Vector2, b: Dictionary, pad: float = 0.0) -> bool:
	var other: Vector2 = b.get("heading", heading)
	var side := Vector2(-heading.y, heading.x)
	var other_side := Vector2(-other.y, other.x)
	var relative: Vector2 = b["point"] - point
	for axis in [heading, side, other, other_side]:
		var reach: float = absf(axis.dot(heading))*a.get("half_length", 1.3) + absf(axis.dot(side))*a.get("half_width", .55)
		reach += absf(axis.dot(other))*b.get("half_length", 1.3) + absf(axis.dot(other_side))*b.get("half_width", .55)
		if absf(relative.dot(axis)) >= reach + pad:
			return false
	return true

static func intersects_obstacle(vehicle: Dictionary, point: Vector2, heading: Vector2, box: Rect2, pad: float = .12) -> bool:
	var obstacle: Dictionary = {"point": box.get_center(), "heading": Vector2.RIGHT,
		"half_length": box.size.x*.5, "half_width": box.size.y*.5}
	return overlaps(vehicle, point, heading, obstacle, pad)


# Continuous separating-axis test for a vehicle with fixed heading on one segment.
static func sweep_obstacle(vehicle: Dictionary,start: Vector2,finish: Vector2,heading: Vector2,box: Rect2,pad: float=.12) -> bool:
	var side:=Vector2(-heading.y,heading.x)
	var relative: Vector2=start-box.get_center()
	var motion: Vector2=finish-start
	var half: Vector2=box.size*.5
	var enter: float=0
	var leave: float=1
	for axis in [heading,side,Vector2.RIGHT,Vector2.DOWN]:
		var reach: float=half.x*absf(axis.x)+half.y*absf(axis.y)+pad
		reach+=vehicle.get("half_length",1.3)*absf(axis.dot(heading))+vehicle.get("half_width",.55)*absf(axis.dot(side))
		var offset: float=relative.dot(axis)
		var velocity: float=motion.dot(axis)
		if absf(velocity)<.000001:
			if absf(offset)>=reach: return false
			continue
		var near: float=(-reach-offset)/velocity
		var far: float=(reach-offset)/velocity
		enter=maxf(enter,minf(near,far))
		leave=minf(leave,maxf(near,far))
		if enter>=leave: return false
	return true
