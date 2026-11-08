extends RefCounted

const PATH = "res://resources/catalog/arcade.json"
const GAME_IDS = ["sprint", "signals"]
const SCORE_LIMIT = 10
const Props = preload("res://scripts/builder/prop_plan.gd")
const Grid = preload("res://scripts/builder/grid_fit.gd")
static var catalog: Dictionary

static func definitions() -> Dictionary:
	if catalog.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if data is Dictionary and data.get("version") == 1: catalog = data
	return catalog

static func enabled(data: Dictionary) -> bool:
	var value: Variant = data.get("arcade", {})
	return valid_settings(value) and value.get("enabled", false)

static func valid_settings(value: Variant) -> bool:
	return value is Dictionary and value.get("enabled", false) is bool

static func valid_cabinet(value: Variant) -> bool:
	return value is Dictionary and value.get("game", "demo") in ["demo", "auto"] + GAME_IDS

static func reviewed(item: Dictionary) -> bool:
	return definitions().get("cabinets", {}).has(item.get("asset", ""))

static func recommended(item: Dictionary) -> String:
	return definitions().get("cabinets", {}).get(item.get("asset", ""), "demo")

static func game(item: Dictionary) -> String:
	var value: Variant = item.get("arcade", {})
	if not reviewed(item) or not valid_cabinet(value): return ""
	var requested: String = value.get("game", "demo")
	if requested == "auto": requested = recommended(item)
	return requested if requested in GAME_IDS else ""

static func title(id: String) -> String:
	return definitions().get("games", {}).get(id, {}).get("title", "")

static func operator_profile(item: Dictionary, library: RefCounted) -> Dictionary:
	var value: Dictionary = Props.profile(item)
	if value.is_empty():
		value = Props.definitions()["kinds"]["appliance"].duplicate()
		value["kind"] = "appliance"
	var authored: Dictionary = item.get("prop", {})
	if authored.has("approach"): return value
	if item["asset"].begins_with("3d:"):
		var box: AABB = Grid.bounds_for(item["asset"],library)
		value["approach"] = [box.get_center().x, 0, box.end.z + .9]
	else:
		value["approach"] = [0, 0, 1.25]
	return value

static func default_action(event: InputEventKey) -> String:
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed: return ""
	match event.keycode:
		KEY_A, KEY_LEFT: return "move_left"
		KEY_D, KEY_RIGHT: return "move_right"
		KEY_W, KEY_UP: return "move_up"
		KEY_S, KEY_DOWN: return "move_down"
		KEY_E: return "interact"
		KEY_ESCAPE: return "cancel"
	return ""

static func submit(board: Array, record: Dictionary) -> Array:
	var next: Array = board.duplicate()
	if next.any(func(entry: Dictionary) -> bool: return entry["id"] == record["id"]): return next
	next.append(record.duplicate(true))
	next.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["id"] < b["id"] if a["score"] == b["score"] else a["score"] > b["score"])
	return next.slice(0, SCORE_LIMIT)
