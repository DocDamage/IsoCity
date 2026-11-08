extends RefCounted

const PATH: String="res://resources/catalog/schools.json"
const MAX_SCHOOLS: int=16
const MAX_ENROLLMENT: int=32
const PLAYGROUND_RANGE: float=24
const BELLS: Array[String]=["arrival","lesson","break_start","break_end","dismissal"]
const CLASS_PHASES: Array[String]=["morning","afternoon"]
const DEFAULTS: Dictionary={
	"enabled":false,"closed":false,"capacity":4,
	"arrival":7.5,"lesson":8.25,"break_start":11.0,"break_end":11.5,"dismissal":15.0,
	"playground":"","home_stop":"","school_stop":"","bus_line":""
}
static var catalog: Dictionary={}

static func definitions() -> Dictionary:
	if catalog.is_empty():
		var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if raw is Dictionary and raw.get("version")==1: catalog=raw
	return catalog

static func eligible(item: Dictionary) -> bool:
	return item.get("asset","") in definitions().get("buildings",[])

static func playground(item: Dictionary) -> bool:
	return item.get("asset","") in definitions().get("playgrounds",[])

static func settings(item: Dictionary) -> Dictionary:
	var raw: Variant=item.get("school",{})
	var result: Dictionary=DEFAULTS.duplicate()
	if raw is Dictionary:
		for key in DEFAULTS:
			if raw.has(key): result[key]=raw[key]
	return result

static func valid(raw: Variant) -> bool:
	if not raw is Dictionary: return false
	for key in raw:
		if not DEFAULTS.has(key): return false
	var value: Dictionary=settings({"school":raw})
	if not value["enabled"] is bool or not value["closed"] is bool: return false
	if not preload("res://scripts/builder/economy_plan.gd").integer(value["capacity"],1,MAX_ENROLLMENT): return false
	var previous: float=-.25
	for key in BELLS:
		var hour: Variant=value[key]
		if not (hour is int or hour is float) or not is_finite(float(hour)) or float(hour)>23.75 or float(hour)<previous+.25: return false
		previous=float(hour)
	for key in ["playground","home_stop","school_stop","bus_line"]:
		if not value[key] is String or value[key].length()>128: return false
	var bus: bool=not value["bus_line"].is_empty()
	return bus and not value["home_stop"].is_empty() and not value["school_stop"].is_empty() and value["home_stop"]!=value["school_stop"] or not bus and value["home_stop"].is_empty() and value["school_stop"].is_empty()

static func enabled(item: Dictionary) -> bool:
	return eligible(item) and item.has("school") and valid(item["school"]) and item["school"].get("enabled",false)

static func active(data: Dictionary) -> bool:
	return data.get("objects",[]).any(func(item: Dictionary)->bool: return enabled(item))

static func bus_asset(mode: String) -> String:
	return str(definitions().get("buses",{}).get(mode,""))

static func required_bus(data: Dictionary) -> String:
	for line in data.get("transit_lines",[]):
		if line is Dictionary and line.get("school_bus",false)==true: return bus_asset(data["mode"])
	return ""

static func phase(config: Dictionary,hour: float) -> String:
	if config["closed"]: return "closed"
	if hour<config["arrival"]: return "before"
	if hour<config["lesson"]: return "arrival"
	if hour<config["break_start"]: return "morning"
	if hour<config["break_end"]: return "break"
	if hour<config["dismissal"]: return "afternoon"
	return "dismissed"

static func lesson_minutes(config: Dictionary) -> float:
	return (config["break_start"]-config["lesson"]+config["dismissal"]-config["break_end"])*60.0

static func enroll(residents: Array[Dictionary],sites: Dictionary,lookup: Dictionary) -> Dictionary:
	var enrolled: Dictionary={}
	var remaining: Dictionary={}
	var ids: Array=sites.keys()
	ids.sort()
	for uid in ids: remaining[uid]=int(sites[uid]["config"]["capacity"])
	for resident in residents:
		var home: Vector2=lookup[resident["home"]]["point"]
		var distance: float=INF
		var selected: String=""
		for uid in ids:
			if remaining[uid]<=0: continue
			var candidate: float=home.distance_squared_to(sites[uid]["point"])
			if candidate<distance:
				selected=uid
				distance=candidate
		if not selected.is_empty():
			remaining[selected]-=1
			enrolled[resident["id"]]=selected
	return enrolled
