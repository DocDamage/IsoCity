extends RefCounted

const PATH = "res://resources/catalog/gardens.json"
const Utility = preload("res://scripts/builder/utility_profiles.gd")
const Terrain = preload("res://scripts/builder/terrain_plan.gd")
const Traffic = preload("res://scripts/builder/traffic_plan.gd")
const Stock = preload("res://scripts/builder/activity_stock.gd")
const MAX_SITES = 128
const MAX_RECEIPTS = 96
const MAX_PRODUCE = 16
const MAX_MOISTURE = 8
const WATER_DOSE = 6
const LIMITS = {"water": 12, "soil": 8, "compost": 4}

static var catalog: Dictionary = {}

static func definitions() -> Dictionary:
	if catalog.is_empty():
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if raw is Dictionary and raw.get("version") == 1: catalog = raw
	return catalog

static func crops() -> Dictionary:
	return definitions().get("crops", {})

static func profile(item: Dictionary) -> Dictionary:
	return definitions().get("sites", {}).get(item.get("asset", ""), {})

static func growing_site(role: String) -> bool:
	return role in ["bed", "greenhouse"]

static func valid_settings(value: Variant) -> bool:
	return value is Dictionary and value.get("enabled", false) is bool

static func valid_site(value: Variant) -> bool:
	return value is Dictionary and value.get("enabled", false) is bool and value.get("irrigation", false) is bool \
		and value.get("crop", "lettuce") in crops()

static func settings(data: Dictionary) -> bool:
	var config: Variant = data.get("garden", {})
	return valid_settings(config) and config.get("enabled", false) and not data.get("interior_room", false)

static func site_config(item: Dictionary) -> Dictionary:
	var raw: Variant = item.get("garden", {})
	if not valid_site(raw): raw = {}
	return {"enabled": raw.get("enabled", false), "irrigation": raw.get("irrigation", false), "crop": raw.get("crop", "lettuce")}

static func selected_records(data: Dictionary) -> Array:
	return data.get("objects", []).filter(func(item: Dictionary) -> bool:
		return item.has("garden") and site_config(item)["enabled"] and not profile(item).is_empty())

static func identity(item: Dictionary, config: Dictionary, mode: String) -> Array:
	return [mode, item["asset"], item["position"].duplicate(), item["direction"], float(item["scale"]),
		item.get("angle", 0.0), item.get("tilt", [0.0, 0.0]).duplicate(), config["crop"]]

static func compile(data: Dictionary, library: RefCounted, check_disabled: bool = false) -> Dictionary:
	var sites: Dictionary = {}
	if not settings(data) and not check_disabled: return sites
	var items: Array = selected_records(data)
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["uid"] < b["uid"])
	var mode: String = data["mode"]
	var terrain: bool = Terrain.settings(data)["enabled"]
	var heights: Dictionary = Terrain.lookup(data) if terrain else {}
	var waters: Dictionary = Terrain.lookup(data, true) if terrain else {}
	for item in items.slice(0, MAX_SITES):
		var config: Dictionary = site_config(item)
		var authored: Dictionary = profile(item)
		var blocked: String = Utility.availability(item, library, data)
		var bounds := Rect2()
		if blocked.is_empty():
			bounds = Utility.footprint(item, library, mode)
			if terrain and growing_site(authored["role"]):
				var point: Vector2 = bounds.get_center()
				var surface: Dictionary = Terrain.sample(data, point, heights)
				var water: Variant = Terrain.water_level(data, point, heights, waters)
				if water != null and water > surface["height"] + Terrain.WADING_DEPTH:
					blocked = "The planting surface is submerged."
		sites[item["uid"]] = {"item": item, "config": config, "profile": authored,
			"rect": bounds, "reason": blocked, "identity": identity(item, config, mode)}
	var planting: Array = sites.values().filter(func(site: Dictionary) -> bool:
		return site["reason"].is_empty() and growing_site(site["profile"]["role"]))
	for index in planting.size():
		for other in range(index + 1, planting.size()):
			var first: Dictionary = planting[index]
			var second: Dictionary = planting[other]
			if not first["rect"].grow(-.01).intersects(second["rect"].grow(-.01)): continue
			var a: Array = first["item"]["position"]
			var b: Array = second["item"]["position"]
			var vertical: int = 2 if mode == "2d" else 1
			if absf(float(a[vertical]) - float(b[vertical])) > .5: continue
			first["reason"] = "Planting sites overlap. Move one before growing."
			second["reason"] = first["reason"]
	return sites

static func required_assets(data: Dictionary) -> Array:
	if not settings(data): return []
	var found: Dictionary = {}
	for item in selected_records(data):
		var art: String = crop_art(item)
		if not art.is_empty(): found[art] = true
	return found.keys()

static func crop_art(item: Dictionary) -> String:
	var config: Dictionary = site_config(item)
	return crops()[config["crop"]]["art"] if config["enabled"] and profile(item).get("crop_art", false) else ""

static func in_season(site: Dictionary, season: String) -> bool:
	return site["profile"]["role"] == "greenhouse" or season in crops()[site["config"]["crop"]]["seasons"]

static func fresh_account(budget: bool) -> Dictionary:
	var stock: Dictionary = {"water": 8, "soil": 4, "compost": 0}
	for crop in crops(): stock["seed/" + crop] = 2
	return {"stock": stock, "cash": 40 if budget else -1, "receipts": {}}

static func count(stock: Dictionary, prefix: String) -> int:
	var total: int = 0
	for key in stock:
		if key.begins_with(prefix): total += int(stock[key])
	return total

static func failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func capacity(key: String) -> int:
	if LIMITS.has(key): return LIMITS[key]
	var pieces: PackedStringArray = key.split("/")
	if pieces.size() != 2 or not crops().has(pieces[1]): return 0
	return 6 if pieces[0] == "seed" else MAX_PRODUCE if pieces[0] == "produce" else 0

# The seed charge, input consumption, yield and reward all use this receipt
# path. A rejected candidate leaves both stock and the preview wallet intact.
static func exchange(account: Dictionary, ticket: String, changes: Dictionary, credits: int, details: Dictionary) -> Dictionary:
	var update: Dictionary = Stock.exchange(account,ticket,changes,credits,details,capacity,
		func(stock: Dictionary) -> String:
			return "produce_full" if count(stock,"produce/") > MAX_PRODUCE else "", MAX_RECEIPTS)
	if update["ok"]: return update
	return failure({
		"missing":"The garden kit is missing a required supply.",
		"capacity":"There is no space for more of that item.",
		"balance":"The garden preview wallet is short of credits.",
		"produce_full":"Harvest basket full. Share some produce before harvesting."
	}[update["reason"]])
