extends RefCounted

const MACHINES = ["wash", "dry"]
const MAX_LOAD = 6
const MAX_STATIONS = 64
const MAX_FACILITIES = 32
const MAX_ORDERS = 12
const RECEIPT_LIMIT = 64
const PATH = "res://resources/catalog/laundry.json"
static var catalog: Dictionary

static func definitions() -> Dictionary:
	if catalog.is_empty():
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if raw is Dictionary and raw.get("version") == 1: catalog = raw
	return catalog

static func customers() -> Dictionary:
	return definitions().get("customers", {})

static func enabled(data: Dictionary) -> bool:
	var settings: Variant = data.get("laundry", {})
	return valid_settings(settings) and settings.get("enabled", false)

static func valid_settings(value: Variant) -> bool:
	return value is Dictionary and value.get("enabled", false) is bool

static func valid_station(value: Variant) -> bool:
	if not valid_settings(value) or not value.get("power", false) is bool or not value.get("water", false) is bool:
		return false
	var capacity: Variant = value.get("capacity", 1)
	if not (capacity is int or capacity is float) or not is_finite(float(capacity)):
		return false
	return capacity >= 1 and capacity <= MAX_LOAD and floorf(float(capacity)) == float(capacity)

static func profile(item: Dictionary) -> Dictionary:
	return definitions().get("stations", {}).get(item.get("asset", ""), {})

static func station(item: Dictionary) -> Dictionary:
	var setting: Variant = item.get("laundry", {})
	var base: Dictionary = profile(item)
	if base.is_empty() or not valid_station(setting) or not setting.get("enabled", false): return {}
	var role: String = base["role"]
	return {"role": role, "capacity": mini(int(setting.get("capacity", base.get("capacity", 1))), int(base.get("capacity", 1))),
		"power": role in MACHINES and setting.get("power", false),
		"water": role == "wash" and setting.get("water", false), "dual": base.get("dual", false)}

static func identity(item: Dictionary) -> Array:
	return [item["uid"], item["asset"], item["position"], item["direction"], item["scale"], item.get("angle"), item.get("tilt")]

static func accepts(station_setting: Dictionary, stage: String) -> bool:
	return station_setting["role"] == stage or stage == "dry" and station_setting["dual"]

static func fresh_account() -> Dictionary:
	return {"stock": {"detergent": definitions().get("starter_detergent", 0)}, "cash": -1, "receipts": {}}

static func detergent_capacity(key: String) -> int:
	return int(definitions().get("detergent_capacity", 0)) if key == "detergent" else 0
