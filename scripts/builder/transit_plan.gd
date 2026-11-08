extends RefCounted
const PATH: String="res://resources/catalog/transit.json"
const Traffic=preload("res://scripts/builder/traffic_plan.gd")
const Zones=preload("res://scripts/builder/zone_plan.gd")
const Citizen=preload("res://scripts/builder/citizen_plan.gd")
const Layers=preload("res://scripts/builder/layers.gd")
const MAX_STOPS: int=128
const MAX_LINES: int=16
const MAX_LINE_STOPS: int=16
const MAX_LEG_SECTIONS: int=512
const MAX_COMPILED_SECTIONS: int=8192
const MAX_FLEET: int=64
const WALK_RADIUS: float=24
const WALK_SPEED: float=1.8
const APPROACH_TOLERANCE: float=1.6
static var catalog: Dictionary={}
static func definitions() -> Dictionary:
	if catalog.is_empty():
		var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(PATH)); catalog=raw if raw is Dictionary else {}
	return catalog
static func settings(data: Dictionary) -> Dictionary:
	var raw: Dictionary=data.get("transit",{}) if data.get("transit",{}) is Dictionary else {}
	return {"enabled":raw.get("enabled",false) if raw.get("enabled",false) is bool else false,
		"automatic":raw.get("automatic",true) if raw.get("automatic",true) is bool else true,
		"speed":Traffic.number(raw.get("speed",4),4,1,8),"interval":Traffic.number(raw.get("interval",20),20,5,600),
		"population":int(Traffic.number(raw.get("population",32),32,0,128)),"seed":int(Traffic.number(raw.get("seed",1),1,1,2147483647))}
static func valid_settings(value: Variant) -> bool:
	if not value is Dictionary: return false
	var fixed: Dictionary=settings({"transit":value})
	for key in fixed:
		if not value.has(key): continue
		if key in ["enabled","automatic"]:
			if not value[key] is bool: return false
		elif not (value[key] is int or value[key] is float) or not is_finite(float(value[key])) or float(value[key])!=float(fixed[key]): return false
	return true
static func number(value: Variant,low: float,high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=low and float(value)<=high
static func identifier(value: Variant) -> bool:
	return value is String and not value.is_empty() and value.length()<=128
static func color_valid(value: Variant) -> bool:
	if not value is String: return false
	var digits: String=value.trim_prefix("#").to_lower()
	if not digits.length() in [6,8]: return false
	for character in digits:
		if not character in "0123456789abcdef": return false
	return true
static func line_settings(value: Dictionary) -> Dictionary:
	var result: Dictionary=definitions()["line_defaults"].duplicate(true)
	result["school_bus"]=false
	for key in result:
		if value.has(key): result[key]=value[key]
	return result
static func valid_lines(value: Variant) -> bool:
	if not value is Array or value.size()>MAX_LINES: return false
	var ids: Dictionary={}
	for line in value:
		if not line is Dictionary or not identifier(line.get("uid")) or ids.has(line["uid"]): return false
		ids[line["uid"]]=true
		if not line.get("name","") is String or line.get("name","").length()>128: return false
		var config: Dictionary=line_settings(line)
		if not config["enabled"] is bool or not config["school_bus"] is bool or not color_valid(config["color"]): return false
		if not number(config["headway"],10,900) or not number(config["dwell"],2,60) or not number(config["offset"],0,899.999999) or config["offset"]>=config["headway"]: return false
		if not preload("res://scripts/builder/economy_plan.gd").integer(config["capacity"],1,64): return false
		if not line.get("stops") is Array or line["stops"].size()<2 or line["stops"].size()>MAX_LINE_STOPS: return false
		var stops: Dictionary={}
		for uid in line["stops"]:
			if not identifier(uid) or stops.has(uid): return false
			stops[uid]=true
	return true
static func is_stop(item: Dictionary) -> bool:
	return item.get("transit_stop",item.get("asset","") in definitions()["stops"])==true
static func stop_allowed(item: Dictionary,library: RefCounted) -> bool:
	if not library.assets.has(item.get("asset")): return false
	var behavior: Dictionary=preload("res://scripts/builder/asset_behavior.gd").for_asset(item["asset"],library)
	return not behavior.get("building",false) and not behavior.get("ground",false) and not behavior.get("vehicle",false) and not behavior.get("layer","") in ["Characters"]
static func failure(reason: String) -> Dictionary: return {"ok":false,"reason":reason}
static func stop(data: Dictionary,item: Dictionary,library: RefCounted,network: Dictionary,geometry: Dictionary={}) -> Dictionary:
	if not is_stop(item) or not stop_allowed(item,library): return failure("Use a nonbuilding platform or street prop as a stop.")
	if not Zones.usable(item,data,library): return failure("The stop is hidden or unavailable.")
	if library.assets[item["asset"]]["mode"]!=data["mode"] and not geometry.has(item["uid"]): return failure("Mixed-platform collision geometry is not available.")
	var box: Rect2=geometry[item["uid"]] if geometry.has(item["uid"]) else Zones.footprint(item,data["mode"],library)
	var center: Vector2=box.get_center(); var best: Dictionary={}; var distance: float=INF
	var terrain_rejection: String=""
	var terrain=preload("res://scripts/builder/terrain_plan.gd"); var sculpted: bool=terrain.settings(data)["enabled"]; var heights: Dictionary=terrain.lookup(data) if sculpted else {}; var waters: Dictionary=terrain.lookup(data,true) if sculpted else {}
	var surface: Dictionary=terrain.sample(data,center,heights) if sculpted else {"height":0.0,"normal":Vector3.UP}
	if absf(item["position"][2 if data["mode"]=="2d" else 1]-(surface["height"] if data["mode"]=="3d" else 0))>=.5: return failure("Stops require a ground-level platform supported by the local terrain.")
	if not network.has("road_profiles"): network["road_profiles"]=preload("res://scripts/builder/roads.gd").lookup(data)
	for key in network["keys"]:
		var section: Dictionary=network["sections"][key]
		if section["crossing"] or section["neighbors"].size()!=2: continue
		var cell: Vector2i=section["cell"]; var a: Vector2i=network["sections"][section["neighbors"][0]]["cell"]-cell; var b: Vector2i=network["sections"][section["neighbors"][1]]["cell"]-cell
		if a!=-b: continue
		var point: Vector2=Traffic.center(cell,data["mode"]); var delta: Vector2=center-point
		if delta.length()>16: continue
		var axis:=Vector2(a); var right:=Vector2(-axis.y,axis.x); var side: float=delta.dot(right)
		if is_zero_approx(side): continue
		if side<0: axis=-axis; right=-right
		var half: float=(box.size.x*absf(right.x)+box.size.y*absf(right.y))*.5
		var outer: float=section["width"]*.5+(1 if network["road_profiles"].get(key,{}).get("sidewalks",true) else 0)
		if absf(side)-half<outer+.25: continue
		var score: float=delta.length_squared()
		if score<distance:
			var platform: Vector2=center+right*(half+.8); var platform_surface: Dictionary=terrain.sample(data,platform,heights) if sculpted else {"height":0.0,"normal":Vector3.UP}; var water: Variant=terrain.water_level(data,platform,heights,waters) if sculpted else null
			if platform_surface["normal"].y<terrain.WALKABLE_NORMAL or water!=null and water-platform_surface["height"]>terrain.WADING_DEPTH: terrain_rejection="The platform is flooded or too steep to walk."; continue
			if absf(platform_surface["height"]-surface["height"])>.4: terrain_rejection="The platform crosses an abrupt terrain bank."; continue
			distance=score
			best={"uid":item["uid"],"name":item.get("name",library.assets[item["asset"]]["name"]),"section":key,"axis":axis,"right":right,"platform":platform,"height":platform_surface["height"],"dock":point+right*section["width"]*.25,"road_point":point,"bounds":box}
	return {"ok":true,"stop":best} if not best.is_empty() else failure(terrain_rejection if not terrain_rejection.is_empty() else "Place the platform outside the sidewalk beside a straight, connected road, away from crossings and junctions.")
static func constrained_route(network: Dictionary,from: Dictionary,to: Dictionary) -> PackedStringArray:
	var sections: Dictionary=network["sections"]
	var first: String=preload("res://scripts/builder/roads.gd").key(sections[from["section"]]["cell"]+Vector2i(from["axis"]))
	var behind: String=preload("res://scripts/builder/roads.gd").key(sections[to["section"]]["cell"]-Vector2i(to["axis"]))
	if not sections.has(first) or not sections.has(behind): return []
	var initial: String=Traffic.edge_id(from["section"],first); var goal: String=Traffic.edge_id(behind,to["section"])
	if not network["edges"].has(initial) or not network["edges"].has(goal): return []
	var previous: Dictionary={initial:""}; var queue: Array[String]=[initial]; var cursor: int=0
	while cursor<queue.size() and not previous.has(goal):
		var edge: String=queue[cursor]; cursor+=1; var before: String=edge.get_slice(">",0); var at: String=edge.get_slice(">",1)
		for next in Traffic.exits(network,at):
			if next==before and sections[at]["neighbors"].size()>1: continue
			var id: String=Traffic.edge_id(at,next)
			if not previous.has(id): previous[id]=edge; queue.append(id)
	if not previous.has(goal): return []
	var route: PackedStringArray=[]; var edge: String=goal
	while not edge.is_empty(): route.append(edge.get_slice(">",1)); edge=previous[edge]
	route.append(from["section"]); route.reverse()
	return route if route.size()<=MAX_LEG_SECTIONS else PackedStringArray()
static func piece(points: PackedVector2Array,lane: Array,kind: String,gate: String="") -> Dictionary:
	return {"points":points,"lane":lane,"kind":kind,"gate":gate,"approach":lane[0] if kind=="turn" else "","length":Traffic.length(points)}

static func segments(network: Dictionary,route: PackedStringArray,from: Dictionary,to: Dictionary) -> Array:
	var result: Array=[]
	if route.size()<2: return result
	var first: Dictionary=network["edges"][Traffic.edge_id(route[0],route[1])]
	result.append(piece(PackedVector2Array([from["dock"],first["points"][0]]),[route[0],route[1]],"departure"))
	for index in range(1,route.size()):
		var edge: Dictionary=network["edges"][Traffic.edge_id(route[index-1],route[index])]
		result.append(piece(edge["points"],[route[index-1],route[index]],"edge"))
		if index<route.size()-1:
			result.append(piece(Traffic.turn(network,route[index-1],route[index],route[index+1]),[route[index-1],route[index],route[index+1]],"turn",route[index]))
	var last: Dictionary=network["edges"][Traffic.edge_id(route[-2],route[-1])]
	result.append(piece(PackedVector2Array([last["points"][-1],to["dock"]]),[route[-2],route[-1]],"arrival"))
	return result

static func stop_layout(stop: Dictionary) -> Array:
	return [stop["section"],stop["platform"],stop["dock"],stop["axis"],stop["height"]]

static func issue(result: Dictionary,code: String,entity: String,uid: String,title: String,reason: String,related: Array=[]) -> void:
	result["notices"].append(title+": "+reason)
	result["issues"].append({"code":code,"entity":entity,"uid":uid,"title":title,"reason":reason,"related":related})

static func build(data: Dictionary,library: RefCounted,geometry: Dictionary={}) -> Dictionary:
	var config: Dictionary=settings(data)
	var result: Dictionary={"settings":config,"stops":{},"lines":{},"route_stops":{},"options":{},"notices":[],"issues":[],"fleet":0,"compiled_sections":0,"walk_cache":{}}
	if not config["enabled"]: return result
	var network: Dictionary=Traffic.build(data); result["network"]=network
	var items: Array=data.get("objects",[]).duplicate(); items.sort_custom(func(a: Dictionary,b: Dictionary):return a["uid"]<b["uid"])
	for item in items:
		if not is_stop(item): continue
		if result["stops"].size()>=MAX_STOPS: result["notices"].append("Transit stop limit reached (128)."); break
		var compiled: Dictionary=stop(data,item,library,network,geometry)
		if compiled["ok"]: result["stops"][item["uid"]]=compiled["stop"]
		else: issue(result,"invalid_platform","object",item["uid"],item.get("name",item["uid"]),compiled["reason"])
	if not Layers.shown(data,"Ground"): result["notices"].append("Show Ground to operate transit."); return result
	for raw in data.get("transit_lines",[]):
		if not valid_lines([raw]): result["notices"].append("Invalid bus line metadata."); continue
		var line: Dictionary=line_settings(raw); line.merge({"uid":raw["uid"],"name":raw.get("name","Bus line"),"stops":raw["stops"].duplicate(),"legs":[],"departures":[0.0]},true)
		if not line["enabled"]: continue
		result["route_stops"][line["uid"]]=line["stops"]
		var reason: String=""; var section_count: int=0; var total: float=0
		for index in line["stops"].size():
			var from: String=line["stops"][index]; var to: String=line["stops"][(index+1)%line["stops"].size()]
			if not result["stops"].has(from) or not result["stops"].has(to): reason="One or more stops are unavailable."; break
			var path: PackedStringArray=constrained_route(network,result["stops"][from],result["stops"][to])
			if path.is_empty(): reason="No directional road path connects its platforms (maximum 512 road sections per leg)."; break
			if Array(path).any(func(key: String):return network["sections"][key]["width"]<3.6): reason="Buses require standard-width roads along every route leg."; break
			section_count+=path.size()
			if result["compiled_sections"]+section_count>MAX_COMPILED_SECTIONS: reason="Transit route complexity limit reached (8,192 road sections)."; break
			var pieces: Array=segments(network,path,result["stops"][from],result["stops"][to]); var distance: float=0; var stops: int=0
			for piece in pieces:
				distance+=piece["length"]
				if not piece["gate"].is_empty() and network["sections"][piece["gate"]]["neighbors"].size()>=3: stops+=1
			var duration: float=distance/config["speed"]+stops
			line["legs"].append({"from":from,"to":to,"sections":path,"segments":pieces,"length":distance,"seconds":duration})
			total+=duration+line["dwell"]
			if index<line["stops"].size()-1: line["departures"].append(total)
		if not reason.is_empty(): issue(result,"invalid_bus_line","line",line["uid"],line["name"],reason,line["stops"]); continue
		line["raw_cycle"]=total; line["fleet"]=maxi(1,ceili(total/line["headway"])); line["cycle"]=line["fleet"]*line["headway"]; line["first_departure"]=line["offset"]+line["dwell"]
		if line["fleet"]>8 or result["fleet"]+line["fleet"]>MAX_FLEET:
			issue(result,"bus_fleet_limit","line",line["uid"],line["name"],"Increase headway; service needs %d buses (maximum eight per line, 64 total)." % line["fleet"],line["stops"])
			continue
		result["compiled_sections"]+=section_count; result["fleet"]+=line["fleet"]; result["lines"][line["uid"]]=line
		for i in line["stops"].size():
			var from: String=line["stops"][i]
			if not result["options"].has(from): result["options"][from]=[]
			for count in range(1,line["stops"].size()):
				var j: int=(i+count)%line["stops"].size(); var arrival: float=line["departures"][j]-line["dwell"]
				if j==0: arrival=line["raw_cycle"]-line["dwell"]
				elif j<i: arrival+=line["cycle"]
				result["options"][from].append({"line":line["uid"],"from":from,"to":line["stops"][j],"board_index":i,"alight_index":j,"seconds":arrival-line["departures"][i]})
	return result
static func next_departure(line: Dictionary,index: int,ready: float) -> Dictionary:
	var base: float=line["first_departure"]+line["departures"][index]
	var trip: int=maxi(0,ceili((ready-base-.0000001)/line["headway"]))
	return {"time":base+trip*line["headway"],"trip":trip}
static func walking(from: Vector2,to: Vector2,obstacles: Array[Rect2]) -> Dictionary:
	if from.distance_to(to)>WALK_RADIUS+APPROACH_TOLERANCE*2: return failure("Stops are beyond walking access range.")
	var route: Dictionary=Citizen.route(from,to,obstacles,.6)
	if route["path"].is_empty() or route.get("start",Vector2.INF).distance_to(from)>APPROACH_TOLERANCE or route.get("goal",Vector2.INF).distance_to(to)>APPROACH_TOLERANCE: return failure("No safe walking access to the platform.")
	var length: float=preload("res://scripts/builder/scenario_plan.gd").route_length(route["path"])
	return {"ok":true,"path":route["path"],"length":length,"seconds":length/WALK_SPEED} if length<=WALK_RADIUS else failure("Walking access exceeds 24 units.")
static func school_journey(plan: Dictionary,origin: Vector2,destination: Vector2,now: float,obstacles: Array[Rect2],line_id: String,from: String,to: String,bus_asset: String) -> Dictionary:
	var line: Dictionary=plan.get("lines",{}).get(line_id,{})
	if not line.get("school_bus",false) or not from in line["stops"] or not to in line["stops"] or from==to:
		return failure("Choose a connected school-bus line with both assigned stops.")
	var a: Dictionary=plan["stops"][from]
	var b: Dictionary=plan["stops"][to]
	var access: Dictionary=walking(origin,a["platform"],obstacles)
	var egress: Dictionary=walking(b["platform"],destination,obstacles)
	if not access["ok"]: return failure("Walking to the boarding stop: "+access["reason"])
	if not egress["ok"]: return failure("Walking from the arrival stop: "+egress["reason"])
	for option in plan["options"].get(from,[]):
		if option["line"]!=line_id or option["to"]!=to: continue
		var departure: Dictionary=next_departure(line,option["board_index"],now+access["seconds"])
		var ride: Dictionary=option.duplicate()
		ride.merge({"kind":"ride","departure":departure["time"],"arrival":departure["time"]+option["seconds"],"trip":departure["trip"]})
		return {"ok":true,"required_bus":bus_asset,"legs":[
			{"kind":"walk","from":"","to":from,"path":access["path"],"seconds":access["seconds"]},
			ride,{"kind":"walk","from":to,"to":"","path":egress["path"],"seconds":egress["seconds"]}]}
	return failure("The assigned school bus does not serve both stops.")

static func journey(plan: Dictionary,origin: Vector2,destination: Vector2,now: float,obstacles: Array[Rect2]=[]) -> Dictionary:
	if not origin.is_finite() or not destination.is_finite() or not is_finite(now) or now<0 or now>1000000000: return failure("Journey coordinates or time are invalid.")
	if not plan["settings"]["enabled"] or plan["lines"].is_empty(): return failure("Enable a connected bus line before requesting a journey.")
	var access: Dictionary={}; var egress: Dictionary={}
	var candidates: Array=plan["stops"].keys()
	candidates.sort_custom(func(a: String,b: String):return origin.distance_squared_to(plan["stops"][a]["platform"])<origin.distance_squared_to(plan["stops"][b]["platform"]))
	for uid in candidates.slice(0,8):
		var path: Dictionary=walking(origin,plan["stops"][uid]["platform"],obstacles)
		if path["ok"]: access[uid]=path
	candidates.sort_custom(func(a: String,b: String):return destination.distance_squared_to(plan["stops"][a]["platform"])<destination.distance_squared_to(plan["stops"][b]["platform"]))
	for uid in candidates.slice(0,8):
		var path: Dictionary=walking(plan["stops"][uid]["platform"],destination,obstacles)
		if path["ok"]: egress[uid]=path
	if access.is_empty() or egress.is_empty(): return failure("No safe origin/destination platform within 24 walking units.")
	var costs: Dictionary={}; var parents: Dictionary={}; var states: Dictionary={}; var queue: Array=[]
	for uid in access:
		var key: String=JSON.stringify([uid,0]); costs[key]=now+access[uid]["seconds"]; states[key]={"stop":uid,"rides":0}
		parents[key]={"before":"","leg":{"kind":"walk","from":"","to":uid,"path":access[uid]["path"],"seconds":access[uid]["seconds"]}}; queue.append(key)
	var best: String=""; var arrival: float=INF
	while not queue.is_empty():
		queue.sort_custom(func(a: String,b: String):return a<b if is_equal_approx(costs[a],costs[b]) else costs[a]<costs[b])
		var key: String=queue.pop_front(); var state: Dictionary=states[key]; var time: float=costs[key]
		if time>=arrival: break
		if state["rides"]>0 and egress.has(state["stop"]) and time+egress[state["stop"]]["seconds"]<arrival: arrival=time+egress[state["stop"]]["seconds"]; best=key
		if state["rides"]>=MAX_LINES: continue
		for option in plan["options"].get(state["stop"],[]):
			var departure: Dictionary=next_departure(plan["lines"][option["line"]],option["board_index"],time)
			var at: float=departure["time"]+option["seconds"]; var next: String=JSON.stringify([option["to"],state["rides"]+1])
			if costs.has(next) and costs[next]<=at: continue
			var leg: Dictionary=option.duplicate(true); leg.merge({"kind":"ride","departure":departure["time"],"arrival":at,"trip":departure["trip"]},true)
			costs[next]=at; parents[next]={"before":key,"leg":leg}; states[next]={"stop":option["to"],"rides":state["rides"]+1}
			if not next in queue: queue.append(next)
	if best.is_empty(): return failure("No scheduled passenger connection links these districts. Share a stop between lines to create a transfer.")
	var legs: Array=[]; var key: String=best
	while not key.is_empty(): legs.append(parents[key]["leg"]); key=parents[key]["before"]
	legs.reverse(); var exit: Dictionary=egress[states[best]["stop"]]
	legs.append({"kind":"walk","from":states[best]["stop"],"to":"","path":exit["path"],"seconds":exit["seconds"]})
	return {"ok":true,"legs":legs,"departure":now,"arrival":arrival,"transfers":states[best]["rides"]-1,"origin":origin,"destination":destination}
