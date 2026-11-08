extends RefCounted

const PATH="res://resources/catalog/city_services.json"
const Traffic=preload("res://scripts/builder/traffic_plan.gd")
const KINDS=["fire","medical","sanitation","police","none"]
const MAX_STATIONS=32
const ACCESS_RADIUS=16.0
static var catalog: Dictionary={}
static var loaded: bool=false

static func load_catalog() -> void:
	if loaded: return
	var value: Variant=JSON.parse_string(FileAccess.get_file_as_string(PATH))
	catalog=value if value is Dictionary else {}; loaded=true

static func settings(data: Dictionary) -> Dictionary:
	var raw: Variant=data.get("services",{})
	if not raw is Dictionary: raw={}
	return {"enabled":raw.get("enabled",false) if raw.get("enabled",false) is bool else false,
		"automatic":raw.get("automatic",true) if raw.get("automatic",true) is bool else true,
		"interval":Traffic.number(raw.get("interval",30),30,5,600),
		"seed":int(Traffic.number(raw.get("seed",1),1,1,2147483647))}

static func valid_settings(value: Variant) -> bool:
	if not value is Dictionary: return false
	var normalized: Dictionary=settings({"services":value})
	for key in normalized:
		if not value.has(key): continue
		if key in ["enabled","automatic"]:
			if not value[key] is bool: return false
		elif not (value[key] is int or value[key] is float) or not is_finite(float(value[key])) or float(value[key])!=float(normalized[key]): return false
	return true

static func profile(item: Dictionary) -> Dictionary:
	load_catalog()
	var kind: String=catalog.get("stations",{}).get(item.get("asset",""),"none")
	var raw: Variant=item.get("city_service",{})
	if not raw is Dictionary: raw={"kind":"none"}
	if raw.has("kind"): kind=raw["kind"] if raw["kind"] is String and raw["kind"] in KINDS else "none"
	return {"kind":kind,"radius":Traffic.number(raw.get("radius",96),96,16,512),"units":int(Traffic.number(raw.get("units",1),1,1,8)),"task_seconds":Traffic.number(raw.get("task_seconds",6),6,2,60)}

static func valid_profile(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.has("kind") and (not value["kind"] is String or not value["kind"] in KINDS): return false
	var normalized: Dictionary=profile({"city_service":value})
	for key in ["radius","units","task_seconds"]:
		if value.has(key) and (not (value[key] is int or value[key] is float) or not is_finite(float(value[key])) or float(value[key])!=float(normalized[key])): return false
	return true

static func unit(kind: String) -> Dictionary:
	load_catalog(); return catalog.get("units",{}).get(kind,{}).duplicate(true)

static func access(network: Dictionary,point: Vector2) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	if not point.is_finite(): return result
	var offset: Vector2=Vector2.ONE if network["mode"]=="2d" else Vector2.ZERO
	var low:=Vector2i(((point-offset-Vector2.ONE*ACCESS_RADIUS)/8).ceil())
	var high:=Vector2i(((point-offset+Vector2.ONE*ACCESS_RADIUS)/8).floor())
	# At most 25 nearby grid cells, even in a 4,096-section city.
	for x in range(low.x,high.x+1):
		for y in range(low.y,high.y+1):
			var key: String=preload("res://scripts/builder/roads.gd").key(Vector2i(x,y))
			if not network["sections"].has(key): continue
			var section: Dictionary=network["sections"][key]
			if section["neighbors"].is_empty(): continue
			var center: Vector2=Traffic.center(section["cell"],network["mode"])
			var distance: float=point.distance_to(center)
			if distance<=ACCESS_RADIUS: result.append({"section":key,"point":center,"distance":distance})
	return result

static func build(data: Dictionary,library: RefCounted,arrivals: Dictionary={},visible_only: bool=true) -> Dictionary:
	load_catalog()
	var network: Dictionary=Traffic.build(data)
	var stations: Dictionary={}; var targets: Dictionary={}; var notices: PackedStringArray=[]
	var approach_issues: Dictionary={}
	var terrain=preload("res://scripts/builder/terrain_plan.gd"); var sculpted: bool=terrain.settings(data)["enabled"]; var heights: Dictionary=terrain.lookup(data) if sculpted else {}; var waters: Dictionary=terrain.lookup(data,true) if sculpted else {}
	var items: Array=data.get("objects",[]).duplicate()
	items.sort_custom(func(a: Variant,b: Variant):return str(a.get("uid",""))<str(b.get("uid","")) if a is Dictionary and b is Dictionary else a is Dictionary)
	for item in items:
		if not item is Dictionary or not item.get("uid") is String or item["uid"].is_empty() or stations.has(item["uid"]) or targets.has(item["uid"]): continue
		if not library.assets.has(item.get("asset")) or library.assets[item["asset"]].get("unavailable",false) or item.has("missing_asset"): continue
		if visible_only and (not item.get("visible",true) or not preload("res://scripts/builder/layers.gd").shown(data,preload("res://scripts/builder/layers.gd").layer(item,library))): continue
		var position: Variant=arrivals.get(item["uid"],item.get("position",[]))
		if not preload("res://scripts/builder/document.gd").numbers(position,3): continue
		var point: Vector2=Traffic.metric(position,data["mode"])
		var config: Dictionary=profile(item)
		var eligible: Array=catalog.get("targets",{}).get(item["asset"],[]).duplicate()
		if preload("res://scripts/builder/asset_behavior.gd").for_asset(item["asset"],library).get("building",false) or item.has("interior"): eligible=KINDS.slice(0,4)
		var service_asset: bool=config["kind"]!="none" or not eligible.is_empty()
		var surface: Dictionary=terrain.sample(data,point,heights) if sculpted else {"height":0.0,"normal":Vector3.UP}
		var level: float=surface["height"] if data["mode"]=="3d" else 0.0
		var water: Variant=terrain.water_level(data,point,heights,waters) if sculpted else null
		if surface["normal"].y<terrain.WALKABLE_NORMAL or water!=null and water-surface["height"]>terrain.WADING_DEPTH:
			var reason: String="Service approach is flooded or too steep to walk."
			notices.append(str(item.get("name",item["asset"]))+": "+reason.to_lower())
			if service_asset: approach_issues[item["uid"]]=reason
			continue
		if absf(position[2 if data["mode"]=="2d" else 1]-level)>.5:
			var reason: String="Services require a supported ground-level approach."
			notices.append(str(item.get("name",item["asset"]))+": "+reason.to_lower())
			if service_asset: approach_issues[item["uid"]]=reason
			continue
		if not service_asset: continue
		var entry: Dictionary={"uid":item["uid"],"name":item.get("name",library.assets[item["asset"]]["name"]),"point":point,"height":level,"access":access(network,point),"config":config,"kinds":eligible}
		if config["kind"]!="none":
			if stations.size()>=MAX_STATIONS: notices.append("Service station limit reached (32)."); continue
			stations[item["uid"]]=entry
			if entry["access"].is_empty(): notices.append(entry["name"]+": no connected road within 16 units of the approach.")
		else: targets[item["uid"]]=entry
	var fleets: Dictionary={}
	for kind in KINDS.slice(0,4):
		fleets[kind]=Traffic.Fleet.pool(data,kind,library)
	return {"network":network,"stations":stations,"targets":targets,"settings":settings(data),"notices":notices,"routes":{},"fleets":fleets,"circuits":{},"approach_issues":approach_issues}

# A multi-source shortest-path tree accounts for every nearby driveway access.
# This avoids falsely rejecting a target beside a second, connected road.
static func tree(plan: Dictionary,station_uid: String) -> Dictionary:
	if plan["routes"].has(station_uid): return plan["routes"][station_uid]
	var costs: Dictionary={}; var previous: Dictionary={}; var heap: Array=[]
	for approach in plan["stations"][station_uid]["access"]:
		var key: String=approach["section"]
		if costs.has(key) and costs[key]<=approach["distance"]: continue
		costs[key]=approach["distance"]; previous[key]=""; heap_push(heap,[approach["distance"],key])
	while not heap.is_empty():
		var entry: Array=heap_pop(heap); var cost: float=entry[0]; var key: String=entry[1]
		if cost>costs[key]: continue
		for next in Traffic.exits(plan["network"],key):
			var candidate: float=cost+8
			if costs.has(next) and costs[next]<=candidate: continue
			costs[next]=candidate; previous[next]=key; heap_push(heap,[candidate,next])
	var result: Dictionary={"costs":costs,"previous":previous}; plan["routes"][station_uid]=result; return result

static func heap_push(heap: Array,value: Array) -> void:
	heap.append(value); var index: int=heap.size()-1
	while index>0:
		var parent: int=(index-1)/2
		if not less(heap[index],heap[parent]): break
		var swap: Array=heap[parent]; heap[parent]=heap[index]; heap[index]=swap; index=parent

static func heap_pop(heap: Array) -> Array:
	var first: Array=heap[0]; var last: Array=heap.pop_back()
	if heap.is_empty(): return first
	heap[0]=last; var index: int=0
	while index*2+1<heap.size():
		var child: int=index*2+1
		if child+1<heap.size() and less(heap[child+1],heap[child]): child+=1
		if not less(heap[child],heap[index]): break
		var swap: Array=heap[index]; heap[index]=heap[child]; heap[child]=swap; index=child
	return first

static func less(a: Array,b: Array) -> bool: return a[0]<b[0] or a[0]==b[0] and a[1]<b[1]

static func path_to(paths: Dictionary,key: String) -> PackedStringArray:
	var route: PackedStringArray=[]
	while not key.is_empty() and paths.get("previous",{}).has(key):
		route.append(key)
		key=paths["previous"][key]
	route.reverse()
	return route

static func circuit_key(kind: String,route: PackedStringArray) -> String:
	return JSON.stringify([kind,Array(route)])

static func circuits(plan: Dictionary,kind: String,route: PackedStringArray) -> Array:
	var cache: Dictionary=plan["circuits"]
	var key: String=circuit_key(kind,route)
	if cache.has(key): return cache[key]
	var network: Dictionary=plan["network"]
	var result: Array=[]
	for profile in plan["fleets"][kind]:
		var outbound: PackedStringArray=route
		if not Traffic.Fleet.fit_route(network,outbound,profile):
			outbound=Traffic.route(network,route[0],route[-1],profile)
		if outbound.is_empty(): continue
		var back: PackedStringArray=outbound.duplicate()
		back.reverse()
		if not Traffic.Fleet.fit_route(network,back,profile):
			back=Traffic.route(network,outbound[-1],outbound[0],profile)
		if back.is_empty(): continue
		result.append({"weight":profile["weight"],"profile":profile,"route":outbound,"return_route":back})
	if cache.size()<512:
		cache[key]=result
	return result

static func choose(plan: Dictionary,kind: String,target_uid: String,busy: Dictionary={},identity: String="",required_station: String="") -> Dictionary:
	if not kind in KINDS.slice(0,4): return {"ok":false,"reason":"Unknown service type"}
	if not plan["targets"].has(target_uid) or not kind in plan["targets"][target_uid]["kinds"]: return {"ok":false,"reason":"Select an eligible neighborhood building or service target"}
	var target: Dictionary=plan["targets"][target_uid]
	if target["access"].is_empty(): return {"ok":false,"reason":"Target has no connected road within 16 units"}
	var best: Dictionary={}; var best_cost: float=INF; var matching: bool=false; var connected: bool=false; var covered: bool=false
	var fits: bool=false
	for uid in plan["stations"]:
		if not required_station.is_empty() and uid != required_station: continue
		var station: Dictionary=plan["stations"][uid]
		if station["config"]["kind"]!=kind: continue
		matching=true
		var paths: Dictionary=tree(plan,uid)
		for approach in target["access"]:
			var key: String=approach["section"]
			if not paths["costs"].has(key): continue
			connected=true
			var cost: float=paths["costs"][key]+approach["distance"]
			if cost>station["config"]["radius"]: continue
			covered=true
			var route: PackedStringArray=path_to(paths,key)
			var circuit: Dictionary=Traffic.Fleet.choose(circuits(plan,kind,route),plan["settings"]["seed"],identity if not identity.is_empty() else target_uid,func(candidate: Dictionary)->bool:
				return cost+(candidate["route"].size()-route.size())*8<=station["config"]["radius"]
			)
			if circuit.is_empty(): continue
			fits=true
			var actual: float=cost+(circuit["route"].size()-route.size())*8
			if int(busy.get(uid,0))>=station["config"]["units"] or actual>=best_cost: continue
			best_cost=actual
			best={"ok":true,"station":uid,"target":target_uid,"kind":kind,"route":circuit["route"],"return_route":circuit["return_route"],"fleet_profile":circuit["profile"],"distance":actual,"duration":station["config"]["task_seconds"]}
	if not best.is_empty(): return best
	return {"ok":false,"reason":"No station for this service" if not matching else "Service roads are disconnected or the station lacks road access" if not connected else "Outside station coverage" if not covered else "No selected service vehicle fits the outbound and return roads" if not fits else "All reachable crews are busy"}
