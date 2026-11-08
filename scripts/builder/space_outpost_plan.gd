extends RefCounted

const CatalogPath = "res://resources/catalog/space_outpost.json"
const DocumentPath = "res://scripts/builder/document.gd"
const Zone = preload("res://scripts/builder/zone_plan.gd")
const Terrain = preload("res://scripts/builder/terrain_plan.gd")
const Site = preload("res://scripts/builder/terrain_site.gd")
const Fit = preload("res://scripts/builder/grid_fit.gd")
const Rotation = preload("res://scripts/builder/rotation.gd")
const Repair = preload("res://scripts/builder/repair_assets.gd")
const DIRECTIONS = [Vector2.DOWN, Vector2.RIGHT, Vector2.UP, Vector2.LEFT]
const MAX_DOCKS = 4
const RUNWAY_LENGTH = 14.0
const HULL_MARGIN = 1.1
const STAND_RADIUS = .55
const CRATE_SCALE = .22
static var catalog: Dictionary = {}

static func definitions() -> Dictionary:
	if catalog.is_empty():
		catalog = JSON.parse_string(FileAccess.get_file_as_string(CatalogPath))
	return catalog

static func valid(raw: Variant) -> bool:
	if not raw is Dictionary or raw.size() != 4: return false
	if not raw.get("enabled") is bool or not raw.get("orbital") is bool: return false
	var interval: Variant = raw.get("interval")
	if not Terrain.integer(interval) or interval < 12 or interval > 180: return false
	var docks: Variant = raw.get("docks")
	if not docks is Array or docks.size() > MAX_DOCKS: return false
	var seen: Dictionary = {}
	for dock in docks:
		if not dock is Dictionary or dock.size() != 2: return false
		var anchor: Variant = dock.get("anchor")
		var heading: Variant = dock.get("heading")
		if not anchor is String or anchor.is_empty() or anchor.length() > 128 or anchor.contains("\n"): return false
		if seen.has(anchor) or not Terrain.integer(heading) or heading < 0 or heading >= DIRECTIONS.size(): return false
		seen[anchor] = true
	return true

static func settings(data: Dictionary) -> Dictionary:
	var raw: Variant = data.get("space_outpost")
	if data.get("interior_room", false) or not valid(raw):
		return {"enabled": false, "orbital": false, "interval": 24, "docks": []}
	var docks: Array[Dictionary] = []
	for dock in raw["docks"]:
		docks.append({"anchor": dock["anchor"], "heading": int(dock["heading"])})
	return {"enabled": raw["enabled"], "orbital": raw["orbital"], "interval": int(raw["interval"]), "docks": docks}

static func required(data: Dictionary) -> Array[String]:
	var config: Dictionary = settings(data)
	var result: Array[String] = []
	if not config["enabled"]: return result
	var source: Dictionary = definitions()
	if config["orbital"]: result.append(source["satellite"])
	if not config["docks"].is_empty():
		result.append(source["cargo"])
		for ship in source["ships"]: result.append(ship["asset"])
	return result

static func failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func patch(point: Vector2, half: float) -> Rect2:
	return Rect2(point - Vector2.ONE * half, Vector2.ONE * half * 2.0)

static func clear(rect: Rect2, context: Dictionary) -> bool:
	for key in ["objects", "roads"]:
		if context[key].any(func(other: Rect2) -> bool: return rect.intersects(other)): return false
	return true

static func dry_site(data: Dictionary, rect: Rect2, context: Dictionary) -> Dictionary:
	return Site.foundation(data, rect, context["heights"], context["waters"])

static func hull_envelope(mode: String, library: RefCounted, heading: int) -> Rect2:
	var bounds := Rect2()
	var basis := Basis(Vector3.UP, deg_to_rad(heading * 90.0))
	var units: float = 2.0 if mode == "2d" else 1.0
	for ship in definitions()["ships"]:
		var box: AABB = Transform3D(basis.scaled(Vector3.ONE * float(ship["scale"])), Vector3.ZERO) * Fit.bounds_for(ship["asset"], library, false)
		var rect := Rect2(Vector2(box.position.x, box.position.z) * units, Vector2(box.size.x, box.size.z) * units)
		bounds = rect if not bounds.has_area() else bounds.merge(rect)
	return bounds.grow(HULL_MARGIN)

static func dock_site(data: Dictionary, library: RefCounted, definition: Dictionary, item: Dictionary, context: Dictionary) -> Dictionary:
	if item.is_empty() or item["asset"] != definitions()["dock"] or not Zone.usable(item, data, library):
		return failure("The dock needs a visible Gloria Station cargo marker.")
	var mode: String = data["mode"]
	var marker: Rect2 = Zone.footprint(item, mode, library)
	var heading: int = int(definition["heading"])
	var direction: Vector2 = DIRECTIONS[heading]
	var lateral := Vector2(direction.y, -direction.x)
	var envelope: Rect2 = hull_envelope(mode, library, heading)
	var half_marker: float = marker.size.dot(direction.abs()) * .5
	var ship_reach: float = -minf(envelope.position.dot(direction), envelope.end.dot(direction))
	var stand: Vector2 = marker.get_center() + direction * (half_marker + 1.35)
	var berth: Vector2 = stand + direction * (ship_reach + 1.7)
	var entry: Vector2 = berth + direction * RUNWAY_LENGTH
	var landing := Rect2(berth + envelope.position, envelope.size)
	var corridor: Rect2 = landing.merge(Rect2(entry + envelope.position, envelope.size))
	var cargo_id: String = definitions()["cargo"]
	var cargo_item := {"asset": cargo_id, "direction": str(library.directions(cargo_id)[0]), "scale": CRATE_SCALE, "position": [0, 0, 0]}
	var cargo_bounds: Rect2 = Zone.footprint(cargo_item, mode, library)
	var cargo_clearance: float = maxf(1.0, marker.size.dot(lateral.abs()) * .5 + .65)
	var cargo: Vector2 = stand + lateral * (cargo_bounds.size.dot(lateral.abs()) * .5 + cargo_clearance)
	var cargo_origin: Vector2 = cargo - cargo_bounds.get_center()
	var cargo_patch := Rect2(cargo_origin + cargo_bounds.position, cargo_bounds.size).grow(.2)
	var observation: Rect2 = patch(stand, STAND_RADIUS)
	var operations: Rect2 = corridor.merge(observation).merge(cargo_patch)
	if Terrain.settings(data)["enabled"]:
		var area: Rect2 = Rect2(Terrain.bounds(data))
		area = Rect2(area.position * Terrain.CELL_SIZE, area.size * Terrain.CELL_SIZE)
		if not area.encloses(operations): return failure("Keep the complete dock and approach within the sculpted terrain.")
	if not clear(corridor, context): return failure("Clear buildings and roads from the landing and approach strip.")
	if not clear(observation, context) or not clear(cargo_patch, context):
		return failure("Clear the observation point and cargo staging area beside the dock.")
	var floor: Dictionary = dry_site(data, corridor, context)
	var waiting: Dictionary = dry_site(data, observation, context)
	var staging: Dictionary = dry_site(data, cargo_patch, context)
	if not floor["ok"] or not waiting["ok"] or not staging["ok"] or absf(floor["height"] - waiting["height"]) > .4:
		return failure("The landing strip and observation area need clear, level dry ground.")
	var marker_height: float = item["position"][2 if mode == "2d" else 1]
	if absf(marker_height - float(waiting["height"])) > .65:
		return failure("Place the cargo marker on the landing site’s ground.")
	return {"ok": true, "id": item["uid"], "stand": stand, "stand_height": waiting["height"],
		"cargo": cargo_origin, "cargo_height": staging["height"], "berth": berth, "entry": entry,
		"heading": Rotation.angle_text(heading * 90.0), "height": floor["height"], "corridor": corridor,
		"operations": operations, "landing": landing}

static func inspect(data: Dictionary, library: RefCounted) -> Dictionary:
	var config: Dictionary = settings(data)
	var result := {"ok": true, "reason": "", "docks": {}, "rejected": {}, "orbital": false}
	if not config["enabled"]: return result
	if not Terrain.Layers.shown(data, "Ground"): return failure("Show Ground before running the outpost.")
	var source: Dictionary = definitions()
	var cache: Dictionary = {}
	result["orbital"] = config["orbital"] and Repair.available(source["satellite"], library, cache)
	if result["orbital"] and data["mode"] == "2d":
		var icon: Texture2D = library.icon(source["satellite"])
		result["orbital"] = icon != null and icon != library.MISSING_ICON
	if config["docks"].is_empty(): return result
	if not Repair.available(source["cargo"], library, cache): return failure("The supply crate artwork is unavailable.")
	for ship in source["ships"]:
		if not Repair.available(ship["asset"], library, cache): return failure("A supply ship’s prepared model is unavailable.")
	var items: Dictionary = {}
	for item in data["objects"]: items[item["uid"]] = item
	var context: Dictionary = Zone.site_context(data, library)
	for definition in config["docks"]:
		var id: String = definition["anchor"]
		var site: Dictionary = dock_site(data, library, definition, items.get(id, {}), context)
		if site["ok"]:
			for existing in result["docks"].values():
				if existing["operations"].intersects(site["operations"]):
					site = failure("The landing approach overlaps another dock.")
					break
		if site["ok"]: result["docks"][id] = site
		else: result["rejected"][id] = site["reason"]
	return result

static func blank(data: Dictionary) -> bool:
	for key in ["objects", "roads", "tiles", "terrain_vertices", "water_cells", "protected_areas"]:
		if not data.get(key, []).is_empty(): return false
	return true

static func practice(data: Dictionary, library: RefCounted) -> Dictionary:
	if not blank(data): return failure("Use a blank city for the practice outpost.")
	if data.get("interior_room", false): return failure("Build the outpost in an exterior world.")
	var source: Dictionary = definitions()
	var next: Dictionary = data.duplicate(true)
	var mode: String = next["mode"]
	if not next.has("terrain"):
		next["terrain"] = {"enabled": true, "bounds": [-22, -16, 44, 37], "land_color": "606677"}
	var document = load(DocumentPath)
	for spec in [
		["outpost_habitat", source["habitat"], Vector2(-11, -9), .43, "Exo-Lunar habitat"],
		["outpost_dock", source["dock"], Vector2(0, 0), .30, "Gloria cargo dock"],
		["outpost_stores", source["cargo"], Vector2(-6, -1), .25, "Outpost stores"],
	]:
		if not Repair.available(spec[1], library, {}): return failure("The supplied outpost artwork is unavailable.")
		var item: Dictionary = document.placement_item(spec[0], spec[1], Zone.Traffic.world(spec[2], mode),
			str(library.directions(spec[1])[0]), spec[3])
		item["name"] = spec[4]
		# Center the footprint at the same metric point in both workspaces.
		var offset: Vector2 = Zone.footprint(item, mode, library).get_center() - spec[2]
		item["position"] = Zone.Traffic.world(spec[2] - offset, mode, .035 if mode == "3d" else 0.0)
		next["objects"].append(item)
	next["space_outpost"] = {"enabled": true, "orbital": false, "interval": 24, "docks": [{"anchor": "outpost_dock", "heading": 0}]}
	var plan: Dictionary = inspect(next, library)
	if not plan["ok"]: return plan
	if not plan["docks"].has("outpost_dock"): return failure(plan["rejected"].get("outpost_dock", "The practice dock is unavailable."))
	var dock: Dictionary = plan["docks"]["outpost_dock"]
	next["spawn"] = Zone.Traffic.world(dock["stand"], mode, dock["stand_height"] + (.025 if mode == "3d" else 0.0))
	return {"ok": true, "data": next}
