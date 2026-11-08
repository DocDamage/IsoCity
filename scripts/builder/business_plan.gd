extends RefCounted

const PATH="res://resources/catalog/businesses.json"
const KINDS=["cafe","shop","service","none"]
const ACTIVITIES={
	"cafe":[{"id":"coffee","label":"Order coffee","progress":"Preparing coffee","seconds":3.0,"item":"Coffee"},{"id":"snack","label":"Have a snack","progress":"Preparing a snack","seconds":4.0,"item":"Snack"}],
	"shop":[{"id":"browse","label":"Browse the shop","progress":"Browsing shelves","seconds":3.0,"item":"Shopping bag"},{"id":"supplies","label":"Pick up supplies","progress":"Collecting supplies","seconds":4.0,"item":"Supplies"}],
	"service":[{"id":"counter","label":"Visit the service counter","progress":"Being served","seconds":3.0,"item":"Service receipt"}]
}
static var catalog: Dictionary={}
static var loaded: bool=false

static func defaults(kind: String) -> Dictionary:
	return {"kind":kind,"open_hour":7.0,"close_hour":22.0,"capacity":4,"duration_scale":1.0}

static func profile(item: Dictionary) -> Dictionary:
	if not loaded:
		var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(PATH))
		catalog=raw if raw is Dictionary else {}; loaded=true
	var kind: String=catalog.get(item.get("asset",""),"none")
	if preload("res://scripts/builder/catalog_defaults.gd").reviewed(item.get("asset", "")) and not preload("res://scripts/builder/catalog_defaults.gd").enabled(item): kind = "none"
	var raw: Variant=item.get("business",{})
	if not raw is Dictionary: return defaults("none")
	if raw.has("kind"): kind=raw["kind"] if raw["kind"] is String and raw["kind"] in KINDS else "none"
	var result: Dictionary=defaults(kind)
	for key in ["open_hour","close_hour","capacity","duration_scale"]:
		if not raw.has(key): continue
		var value: Variant=raw[key]
		if not (value is int or value is float) or not is_finite(float(value)): continue
		match key:
			"open_hour": result[key]=clampf(value,0,23.999)
			"close_hour": result[key]=clampf(value,0,24)
			"capacity": result[key]=clampi(int(value),1,32)
			"duration_scale": result[key]=clampf(value,.25,10)
	return result

static func valid(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.has("kind") and (not value["kind"] is String or not value["kind"] in KINDS): return false
	var normalized: Dictionary=profile({"business":value})
	for key in ["open_hour","close_hour","capacity","duration_scale"]:
		if value.has(key) and (not (value[key] is int or value[key] is float) or not is_finite(float(value[key])) or float(value[key])!=float(normalized[key])): return false
	return true

static func open(config: Dictionary,hour: float) -> bool:
	if config["kind"]=="none" or not is_finite(hour): return false
	var time: float=fposmod(hour,24)
	var start: float=config["open_hour"]; var end: float=config["close_hour"]
	if is_equal_approx(start,end): return true
	return time>=start and time<end if start<end else time>=start or time<end

static func activities(config: Dictionary) -> Array:
	if config["kind"]=="market": return [config["market_action"].duplicate(true)]
	var actions: Array = ACTIVITIES.get(config["kind"],[]).duplicate(true)
	if config["kind"]=="cafe": actions.append_array(config.get("cooking_actions",[]).duplicate(true))
	return actions

static func action(config: Dictionary,id: String) -> Dictionary:
	for activity in activities(config):
		if activity["id"]==id:
			activity["seconds"]*=config["duration_scale"]; return activity
	return {}

static func build(data: Dictionary,library: RefCounted,visible_only: bool=true) -> Dictionary:
	var result: Dictionary={}
	for item in data.get("objects",[]):
		if not item is Dictionary or not item.get("uid") is String or item["uid"].is_empty() or result.has(item["uid"]): continue
		if not library.assets.has(item.get("asset")) or library.assets[item["asset"]].get("unavailable",false) or item.has("missing_asset"): continue
		if visible_only and (not item.get("visible",true) or not preload("res://scripts/builder/layers.gd").shown(data,preload("res://scripts/builder/layers.gd").layer(item,library))): continue
		var config: Dictionary=profile(item)
		if config["kind"]=="none": continue
		result[item["uid"]]={"uid":item["uid"],"name":item.get("name",library.assets[item["asset"]]["name"]),"config":config}
	return result
