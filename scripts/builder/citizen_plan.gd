extends RefCounted

const ROLES = ["home","work","shop","park"]
const ROLE_PATH = "res://resources/catalog/citizen_roles.json"
const CELL_SIZE = 0.5
const MAX_CELLS = 262144
static var catalog_roles: Dictionary = {}
static var roles_loaded: bool = false

static func settings(data: Dictionary) -> Dictionary:
	var raw: Dictionary=data.get("citizens",{}) if data.get("citizens",{}) is Dictionary else {}
	var result: Dictionary={"enabled":raw.get("enabled",false) if raw.get("enabled",false) is bool else false,
		"interior_activities":raw.get("interior_activities",false) if raw.get("interior_activities",false) is bool else false,
		"population":int(number(raw.get("population",12),12,0,128)),
		"seed":int(number(raw.get("seed",1),1,1,2147483647)),
		"day_length":number(raw.get("day_length",180),180,30,3600),
		"start_hour":number(raw.get("start_hour",7),7,0,23.999)}
	if raw.get("appearance","") is String and not raw.get("appearance","").is_empty(): result["appearance"]=raw["appearance"]
	return result

static func number(value: Variant,fallback: float,low: float,high: float) -> float:
	return clampf(float(value),low,high) if (value is int or value is float) and is_finite(float(value)) else fallback

static func valid_settings(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.has("appearance") and (not value["appearance"] is String or value["appearance"].length()>512 or (not value["appearance"].is_empty() and not value["appearance"].begins_with("2d:"))): return false
	var fixed: Dictionary=settings({"citizens":value})
	for key in fixed:
		if key=="appearance": continue
		if not value.has(key): continue
		if key in ["enabled","interior_activities"]:
			if not value[key] is bool: return false
		elif not (value[key] is int or value[key] is float) or not is_finite(float(value[key])) or float(value[key])!=float(fixed[key]): return false
	return true

static func role(item: Dictionary) -> String:
	# Placed-object overrides are explicit and can opt out of a catalog default.
	if item.has("citizen_role"): return str(item["citizen_role"]) if item["citizen_role"] in ROLES else ""
	if item.has("business") and preload("res://scripts/builder/business_plan.gd").profile(item)["kind"]!="none": return "shop"
	if not roles_loaded:
		var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(ROLE_PATH))
		catalog_roles=raw if raw is Dictionary else {}
		roles_loaded=true
	var value: String=str(catalog_roles.get(item.get("asset",""),""))
	if preload("res://scripts/builder/catalog_defaults.gd").reviewed(item.get("asset", "")) and not preload("res://scripts/builder/catalog_defaults.gd").enabled(item): value = ""
	if value=="shop" and item.get("business",{}) is Dictionary and item.get("business",{}).get("kind","")=="none": return ""
	return value if value in ROLES else ""

static func metric(values: Array,mode: String) -> Vector2:
	return Vector2(values[0]/16.0,values[1]/8.0) if mode=="2d" else Vector2(values[0],values[2])

static func world(point: Vector2,mode: String,elevation: float=0) -> Array:
	return [point.x*16,point.y*8,elevation] if mode=="2d" else [point.x,elevation,point.y]

static func build(data: Dictionary,library: RefCounted,arrivals: Dictionary={},visible_only: bool=true) -> Dictionary:
	var config: Dictionary=settings(data)
	var destinations: Dictionary={"home":[],"work":[],"shop":[],"park":[]}
	var lookup: Dictionary={}
	var mode: String=str(data.get("mode","2d"))
	for item in data.get("objects",[]):
		if not item is Dictionary or not item.has("uid") or not item.has("asset") or lookup.has(item["uid"]): continue
		if not item["uid"] is String or item["uid"].is_empty(): continue
		var use: String=role(item)
		if use.is_empty() or not library.assets.has(item["asset"]) or library.assets[item["asset"]].get("unavailable",false) or item.has("missing_asset"): continue
		if visible_only and (not item.get("visible",true) or not data.get("layers",{}).get(preload("res://scripts/builder/layers.gd").layer(item,library),{}).get("visible",true)): continue
		var position: Variant=item.get("position",[])
		if not preload("res://scripts/builder/document.gd").numbers(position,3): continue
		var point: Vector2=arrivals.get(item["uid"],metric(position,mode))
		if not point.is_finite(): continue
		var destination: Dictionary={"uid":str(item["uid"]),"role":use,"point":point,"name":str(item.get("name",library.assets[item["asset"]].get("name",item["asset"])))}
		destinations[use].append(destination); lookup[item["uid"]]=destination
	for use in ROLES: destinations[use].sort_custom(func(a: Dictionary,b: Dictionary):return a["uid"]<b["uid"])
	var residents: Array[Dictionary]=[]
	var notices: PackedStringArray=[]
	if destinations["home"].is_empty(): notices.append("Assign a home before enabling residents.")
	for use in ["work","shop","park"]:
		if destinations[use].is_empty(): notices.append("No "+use+" destination; residents return home during that activity.")
	if config["enabled"] and not destinations["home"].is_empty():
		var random:=RandomNumberGenerator.new(); random.seed=config["seed"]
		for index in config["population"]:
			var home: Dictionary=destinations["home"][index%destinations["home"].size()]
			var resident: Dictionary={"id":"resident_"+home["uid"]+"_"+str(floori(float(index)/destinations["home"].size())),"home":home["uid"],"offset":random.randf_range(-.2,.2)}
			for use in ["work","shop","park"]:
				var choices: Array=destinations[use]
				resident[use]=choices[random.randi_range(0,choices.size()-1)]["uid"] if not choices.is_empty() else home["uid"]
			residents.append(resident)
	return {"settings":config,"destinations":destinations,"lookup":lookup,"residents":residents,"notices":notices}

static func activity(hour: float,offset: float=0) -> String:
	var time: float=fposmod(hour-offset,24)
	if time<8 or time>=21: return "home"
	if time<12: return "work"
	if time<13: return "shop"
	if time<17: return "work"
	if time<19: return "park"
	return "shop"

static func destination(resident: Dictionary,hour: float) -> String:
	return str(resident.get(activity(hour,resident.get("offset",0)),resident.get("home","")))

static func route(start: Vector2,goal: Vector2,obstacles: Array[Rect2],clearance: float=.3) -> Dictionary:
	if not start.is_finite() or not goal.is_finite(): return failure("Route endpoints are invalid.")
	if maxf(maxf(absf(start.x),absf(start.y)),maxf(absf(goal.x),absf(goal.y)))>1000000: return failure("Route endpoints exceed the supported walking area.")
	for padding in [4.0,12.0,32.0]:
		var low: Vector2i=Vector2i(((start.min(goal)-Vector2.ONE*padding)/CELL_SIZE).floor())
		var high: Vector2i=Vector2i(((start.max(goal)+Vector2.ONE*padding)/CELL_SIZE).ceil())
		var size: Vector2i=high-low+Vector2i.ONE
		if size.x<=0 or size.y<=0 or size.x>MAX_CELLS or size.y>MAX_CELLS or size.x*size.y>MAX_CELLS: return failure("Route spans too large an area. Add closer destinations.")
		var grid:=AStarGrid2D.new(); grid.region=Rect2i(low,size); grid.cell_size=Vector2.ONE*CELL_SIZE
		grid.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		grid.default_compute_heuristic=AStarGrid2D.HEURISTIC_OCTILE; grid.default_estimate_heuristic=AStarGrid2D.HEURISTIC_OCTILE
		grid.update()
		for raw in obstacles:
			if not raw.position.is_finite() or not raw.size.is_finite(): continue
			var box: Rect2=raw.abs().grow(maxf(0,clearance)+CELL_SIZE*.71)
			var first: Vector2i=Vector2i((box.position/CELL_SIZE).ceil()).max(low)
			var last: Vector2i=Vector2i((box.end/CELL_SIZE).floor()).min(high)
			for x in range(first.x,last.x+1):
				for y in range(first.y,last.y+1): grid.set_point_solid(Vector2i(x,y))
		var from: Vector2i=nearest_free(grid,Vector2i((start/CELL_SIZE).round()))
		var to: Vector2i=nearest_free(grid,Vector2i((goal/CELL_SIZE).round()))
		if not grid.is_in_boundsv(from) or not grid.is_in_boundsv(to): continue
		var points: PackedVector2Array=grid.get_point_path(from,to)
		if not points.is_empty(): return {"path":points,"reason":"","start":Vector2(from)*CELL_SIZE,"goal":Vector2(to)*CELL_SIZE,"cells":size.x*size.y}
	return failure("No safe walking route to this destination.")

static func nearest_free(grid: AStarGrid2D,at: Vector2i) -> Vector2i:
	if grid.is_in_boundsv(at) and not grid.is_point_solid(at): return at
	for radius in range(1,9):
		var best: Vector2i=grid.region.end
		var distance: float=INF
		for x in range(at.x-radius,at.x+radius+1):
			for y in range(at.y-radius,at.y+radius+1):
				if maxi(absi(x-at.x),absi(y-at.y))!=radius: continue
				var point:=Vector2i(x,y)
				if grid.is_in_boundsv(point) and not grid.is_point_solid(point) and point.distance_squared_to(at)<distance:
					best=point; distance=point.distance_squared_to(at)
		if best!=grid.region.end: return best
	return grid.region.end

static func failure(reason: String) -> Dictionary:
	return {"path":PackedVector2Array(),"reason":reason,"cells":0}
