extends RefCounted

const PATH = "res://resources/catalog/fitness.json"
const Hours = preload("res://scripts/builder/business_plan.gd")
const MAX_HISTORY = 24
const CHECK_IN_SECONDS = 15.0
static var catalog: Dictionary

static func definitions() -> Dictionary:
	if catalog.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if data is Dictionary and data.get("version") == 1: catalog = data
	return catalog

static func enabled(data: Dictionary) -> bool:
	var config: Variant = data.get("fitness", {})
	return valid_settings(config) and config.get("enabled", false)

static func valid_settings(value: Variant) -> bool:
	return value is Dictionary and value.get("enabled", false) is bool

static func valid_station(value: Variant) -> bool:
	if not valid_settings(value): return false
	for key in ["open_hour", "close_hour"]:
		var hour: Variant = value.get(key, 0)
		if not (hour is float or hour is int) or not is_finite(float(hour)) or hour < 0 or hour >= 24: return false
	return true

static func profile(item: Dictionary, mode: String) -> Dictionary:
	var value: Dictionary = definitions().get("stations", {}).get(item.get("asset", ""), {})
	return value if mode in value.get("modes", ["2d", "3d"]) else {}

static func station(item: Dictionary, mode: String) -> Dictionary:
	var value: Variant = item.get("fitness", {})
	var base: Dictionary = profile(item, mode)
	if base.is_empty() or not valid_station(value) or not value.get("enabled", false): return {}
	return {"kind": base["activity"], "open_hour": float(value.get("open_hour", 0)),
		"close_hour": float(value.get("close_hour", 0))}

static func scheduled(setting: Dictionary, hour: float) -> bool:
	return not setting.is_empty() and Hours.open(setting, hour)

static func equipment_reason(item: Dictionary, library: RefCounted, mode: String) -> String:
	var asset: String = item["asset"]
	var ratio: float = float(item["scale"]) / maxf(.01, float(library.assets[asset]["data"].get("default_scale", 1)))
	if ratio < .65 or ratio > 1.6: return "Use an equipment scale between 65% and 160% of its catalog size."
	if item.get("tilt", [0,0]) != [0,0]: return "Level this equipment before booking."
	var height: float = float(item["position"][2 if mode == "2d" else 1])
	if absf(height) > .4: return "Place this equipment on the walking floor before booking."
	return ""

static func required_art(data: Dictionary) -> Array[String]:
	return [definitions()["ball"]] if enabled(data) and has_court(data) else []

static func has_court(data: Dictionary) -> bool:
	var mode: String = data.get("mode", "2d")
	for item in data.get("objects", []):
		if station(item, mode).get("kind") == "penalty": return true
		if item.get("interior") is Dictionary and has_court(item["interior"]): return true
	for floor in data.get("floors", []):
		if has_court(floor["room"]): return true
	return false
