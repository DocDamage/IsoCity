extends RefCounted

const PATH = "res://resources/catalog/cooking.json"
const Stock = preload("res://scripts/builder/activity_stock.gd")
const MAX_STOCK = 8
const MAX_PLATES = 4
const MAX_STATIONS = 48
const DEFAULT_RECIPE = "tomato_pan_bread"
const ACTIVE = {"preparing":"prep","cooking":"cook","plating":"serve"}
const TRANSITIONS = {"prep":["preparing","prepared"],"cook":["cooking","cooked"],"serve":["plating","complete"]}
static var catalog: Dictionary = {}

static func definitions() -> Dictionary:
	if catalog.is_empty():
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if raw is Dictionary and raw.get("version") == 1: catalog = raw
	return catalog

static func recipes() -> Dictionary:
	return definitions().get("recipes",{})

static func profile(item: Dictionary) -> Dictionary:
	return definitions().get("stations",{}).get(item.get("asset",""),{})

static func valid_settings(value: Variant) -> bool:
	return value is Dictionary and value.get("enabled",false) is bool

static func valid_station(value: Variant) -> bool:
	return value is Dictionary and value.get("enabled",false) is bool and value.get("power",false) is bool \
		and value.get("recipe",DEFAULT_RECIPE) in recipes()

static func enabled(data: Dictionary) -> bool:
	var config: Variant = data.get("cooking",{})
	return valid_settings(config) and config.get("enabled",false)

static func station(item: Dictionary) -> Dictionary:
	var config: Variant = item.get("cooking",{})
	return config if not item.has("missing_asset") and valid_station(config) and config.get("enabled",false) \
		and not profile(item).is_empty() else {}

static func identity(item: Dictionary) -> String:
	var fields: Array = [item["asset"],item["position"],item["direction"],item["scale"],
		item.get("angle",0.0),item.get("tilt",[0.0,0.0]),station(item)]
	return JSON.stringify(JSON.parse_string(JSON.stringify(fields))).sha256_text()

static func serving_art(item: Dictionary) -> String:
	var config: Dictionary = station(item)
	if config.is_empty() or profile(item)["role"] != "prep": return ""
	return recipes()[config.get("recipe",DEFAULT_RECIPE)]["serving_art"]

static func required_art(data: Dictionary, inherited: bool = false) -> Array:
	if not inherited and not enabled(data): return []
	var assets: Dictionary = {}
	for item in data.get("objects",[]):
		var art: String = serving_art(item)
		if not art.is_empty(): assets[art] = true
		if item.get("interior") is Dictionary:
			for id in required_art(item["interior"],true): assets[id] = true
	for floor in data.get("floors",[]):
		for id in required_art(floor["room"],true): assets[id] = true
	return assets.keys()

static func activity(id: String) -> Dictionary:
	var recipe: Dictionary = recipes().get(id,{})
	if recipe.is_empty(): return {}
	return {"id":"dish/"+id,"label":"Order "+recipe["name"].to_lower(),"progress":"Serving "+recipe["name"].to_lower(),
		"item":recipe["name"],"result_id":id,"icon":recipe["serving_art"],"seconds":1.5}

static func fresh_stock() -> Dictionary:
	return {"stock":definitions()["starter_stock"].duplicate(),"cash":-1,"receipts":{}}

static func capacity(key: String) -> int:
	if key in definitions()["starter_stock"]: return MAX_STOCK
	if key.begins_with("dish/") and key.trim_prefix("dish/") in recipes(): return MAX_PLATES
	return 0

static func exchange(account: Dictionary, ticket: String, changes: Dictionary, details: Dictionary,
		held: Dictionary = {}) -> Dictionary:
	return Stock.exchange(account,ticket,changes,0,details,
		func(key: String) -> int: return capacity(key) - int(held.get(key,0)), Callable(), 128)

static func ingredients_available(stock: Dictionary, inputs: Dictionary) -> String:
	for key in inputs:
		if int(stock.get(key,0)) < int(inputs[key]): return key
	return ""

static func inputs_for(recipe: Dictionary, multiplier: int) -> Dictionary:
	var result: Dictionary = {}
	for key in recipe["inputs"]: result[key] = int(recipe["inputs"][key]) * multiplier
	return result
