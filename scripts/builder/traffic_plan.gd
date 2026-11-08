extends RefCounted

# Traffic uses the road grid's ground coordinates (eight units per section).
# Sprite road tiles have a half-tile contact offset, retained by center().
const Fleet=preload("res://scripts/builder/fleet_plan.gd")
const Roads=preload("res://scripts/builder/roads.gd")
const Signals=preload("res://scripts/builder/traffic_control_plan.gd")
const Profile=preload("res://scripts/builder/road_settings.gd")
const MAX_SECTIONS=4096
const PORT=3.5

static func settings(data: Dictionary) -> Dictionary:
	var raw: Variant=data.get("traffic",{})
	if not raw is Dictionary: raw={}
	return {"enabled":raw.get("enabled",false) if raw.get("enabled",false) is bool else false,
		"population":int(number(raw.get("population",8),8,0,64)),
		"seed":int(number(raw.get("seed",1),1,1,2147483647)),
		"speed":number(raw.get("speed",4),4,1,8),
		"parking_seconds":number(raw.get("parking_seconds",8),8,2,120)}

static func number(value: Variant,fallback: float,low: float,high: float) -> float:
	return clampf(float(value),low,high) if (value is int or value is float) and is_finite(float(value)) else fallback

static func valid_settings(raw: Variant) -> bool:
	if not raw is Dictionary: return false
	var config: Dictionary=settings({"traffic":raw})
	for key in config:
		if not raw.has(key): continue
		if key=="enabled":
			if not raw[key] is bool: return false
		elif not (raw[key] is int or raw[key] is float) or not is_finite(float(raw[key])) or float(raw[key])!=float(config[key]): return false
	return true

static func metric(values: Array,mode: String) -> Vector2:
	if mode=="3d": return Vector2(values[0],values[2])
	return Vector2(values[0]/16.0+values[1]/8.0,values[1]/8.0-values[0]/16.0)

static func world(point: Vector2,mode: String,elevation: float=0) -> Array:
	return [(point.x-point.y)*8,(point.x+point.y)*4,elevation] if mode=="2d" else [point.x,elevation,point.y]

static func center(cell: Vector2i,mode: String) -> Vector2:
	return Signals.road_center(cell,mode)

static func parking_surface(item: Dictionary,library: RefCounted) -> bool:
	var behavior: Dictionary=preload("res://scripts/builder/asset_behavior.gd").for_asset(item["asset"],library)
	return behavior.get("layer","")=="Ground" and not behavior.get("vehicle",false) and not behavior.get("building",false)

# Only authored inputs that can change lanes, closures or junction rules.
static func road_inputs(data: Dictionary) -> Array:
	var roads: Array=[]
	for road in data.get("roads",[]):
		if road is Dictionary:
			roads.append([road.get("cell"),road.get("width",6),road.get("crossing",false),Profile.valid(road),road.get("cycle_access","none")])
	var controls: Array=[]
	for item in data.get("objects",[]):
		if item is Dictionary and item.has("traffic_control"):
			controls.append([item["uid"],item["asset"],item["position"],item["direction"],item.get("angle",0),item.get("tilt",[]),item.get("visible",true),item.get("missing_asset"),item["traffic_control"]])
	var terrain=preload("res://scripts/builder/terrain_plan.gd")
	var sculpted: bool=terrain.settings(data)["enabled"]
	return [data.get("mode","2d"),roads,controls,terrain.bounds(data) if sculpted else null,data.get("terrain_vertices",[]) if sculpted else [],data.get("water_cells",[]) if sculpted else []]

static func build(data: Dictionary) -> Dictionary:
	var sections: Dictionary={}
	var notices: PackedStringArray=[]
	var closed: Dictionary={}; var terrain=preload("res://scripts/builder/terrain_plan.gd"); var sculpted: bool=terrain.settings(data)["enabled"]; var heights: Dictionary=terrain.lookup(data) if sculpted else {}; var waters: Dictionary=terrain.lookup(data,true) if sculpted else {}
	for entry in data.get("roads",[]):
		if sections.size()>=MAX_SECTIONS: break
		if not entry is Dictionary or not Profile.valid(entry): continue
		var values: Variant=entry.get("cell")
		if not values is Array or values.size()!=2: continue
		if not coordinate(values[0]) or not coordinate(values[1]): continue
		var cell:=Vector2i(values[0],values[1]); var key: String=Roads.key(cell)
		if sections.has(key): continue
		if sculpted:
			var blocked: String=preload("res://scripts/builder/terrain_road_policy.gd").reason(data,center(cell,data.get("mode","2d")),heights,waters)
			if not blocked.is_empty(): closed[key]=blocked; notices.append("Road "+key+": "+blocked); continue
		sections[key]={"cell":cell,"width":float(entry.get("width",6)),"crossing":entry.get("crossing",false)==true,"neighbors":[],"cycle_access":entry.get("cycle_access","none")}
	var keys: Array=sections.keys(); keys.sort()
	var edges: Dictionary={}
	for key in keys:
		var section: Dictionary=sections[key]
		for step in Roads.STEPS:
			var next: String=Roads.key(section["cell"]+step)
			if not sections.has(next): continue
			section["neighbors"].append(next)
	var compiled: Dictionary=Signals.compile(data,sections,metric)
	for key in keys:
		var section: Dictionary=sections[key]
		if section["cycle_access"]=="cycle": continue
		for next in section["neighbors"]:
			if sections[next]["cycle_access"]=="cycle": continue
			var step: Vector2i=sections[next]["cell"]-section["cell"]
			if not Signals.permits_edge(compiled["sections"],key,next,step): continue
			var axis:=Vector2(step); var right:=Vector2(-axis.y,axis.x)
			var start: Vector2=center(section["cell"],data.get("mode","2d"))+axis*PORT+right*section["width"]*.25
			var finish: Vector2=center(sections[next]["cell"],data.get("mode","2d"))-axis*PORT+right*sections[next]["width"]*.25
			var id: String=edge_id(key,next)
			edges[id]={"id":id,"from":key,"to":next,"axis":axis,"points":PackedVector2Array([start,finish]),"length":start.distance_to(finish)}
	if edges.is_empty(): notices.append("Draw at least two connected road sections before enabling traffic.")
	for uid in compiled["issues"]:
		notices.append("Traffic control "+uid+" · "+compiled["issues"][uid])
	return {"settings":settings(data),"mode":data.get("mode","2d"),"sections":sections,"keys":keys,"edges":edges,"notices":notices,"closed_sections":closed,"controls":compiled}

static func coordinate(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and absf(float(value))<=100000 and float(value)==floorf(float(value))

static func edge_id(from: String,to: String) -> String: return from+">"+to

static func exits(plan: Dictionary, at: String) -> Array:
	var result: Array=[]
	for next in plan["sections"].get(at,{}).get("neighbors",[]):
		if plan["edges"].has(edge_id(at,next)):
			result.append(next)
	return result

static func crossing_occupied(plan: Dictionary, section: String, people: Array[Vector2]) -> bool:
	var origin: Vector2=center(plan["sections"][section]["cell"],plan["mode"])
	var controlled: bool=plan.get("controls",{}).get("sections",{}).has(section)
	for point in people:
		if Signals.pedestrian_in_section(point,origin) if controlled else point.distance_to(origin)<4.5:
			return true
	return false

static func closest_approach(plan: Dictionary, section: String, point: Vector2) -> String:
	var road: Dictionary=plan["sections"][section]
	# A driveway only needs to report an approach at a controlled junction.
	if road["neighbors"].size()<3: return ""
	var origin: Vector2=center(road["cell"],plan["mode"])
	var best: float=-INF
	var result: String=""
	for neighbor in road["neighbors"]:
		var axis: Vector2=Vector2(plan["sections"][neighbor]["cell"]-road["cell"])
		var distance: float=(point-origin).dot(axis)
		if distance>best:
			best=distance
			result=neighbor
	return result

static func route(plan: Dictionary,from: String,to: String,profile: Dictionary={},incoming: String="") -> PackedStringArray:
	var sections: Dictionary=plan["sections"]
	if not sections.has(from) or not sections.has(to): return []
	if not profile.is_empty(): return route_for_profile(plan,from,to,profile,incoming)
	var previous: Dictionary={from:""}; var queue: Array[String]=[from]; var index: int=0
	while index<queue.size() and not previous.has(to):
		var key: String=queue[index]; index+=1
		for next in exits(plan,key):
			if previous.has(next): continue
			previous[next]=key; queue.append(next)
	if not previous.has(to): return []
	var result: PackedStringArray=[]; var key: String=to
	while not key.is_empty(): result.append(key); key=previous[key]
	result.reverse(); return result

static func route_for_profile(plan: Dictionary,from: String,to: String,profile: Dictionary,incoming: String) -> PackedStringArray:
	var start: String=edge_id(incoming,from)
	var previous: Dictionary={start:""}
	var queue: Array[String]=[start]
	var index: int=0
	while index<queue.size():
		var state: String=queue[index]
		index+=1
		var at: String=state.get_slice(">",1)
		if at==to:
			var result: PackedStringArray=[]
			while not state.is_empty():
				result.append(state.get_slice(">",1))
				state=previous[state]
			result.reverse()
			return result
		for next in exits(plan,at):
			var step: String=edge_id(at,next)
			if previous.has(step) or not Fleet.fit_turn(plan,state.get_slice(">",0),at,next,profile):
				continue
			previous[step]=state
			queue.append(step)
	return []

static func next_section(plan: Dictionary,at: String,previous: String,random: RandomNumberGenerator,profile: Dictionary={}) -> String:
	if not plan["sections"].has(at): return ""
	var choices: Array=exits(plan,at)
	if not profile.is_empty():
		choices=choices.filter(func(next: String): return Fleet.fit_turn(plan,previous,at,next,profile))
	if choices.size()>1: choices.erase(previous)
	return choices[random.randi_range(0,choices.size()-1)] if not choices.is_empty() else ""

static func turn(plan: Dictionary,previous: String,at: String,next: String) -> PackedVector2Array:
	var incoming: Dictionary=plan["edges"].get(edge_id(previous,at),{})
	var outgoing: Dictionary=plan["edges"].get(edge_id(at,next),{})
	if incoming.is_empty() or outgoing.is_empty(): return []
	var a: Vector2=incoming["points"][-1]; var b: Vector2=outgoing["points"][0]
	var points:=PackedVector2Array()
	# Cubic control points retain entry/exit lane tangents through turns and
	# dead-end turnarounds. Every point stays inside the road section square.
	var control_a: Vector2=a+incoming["axis"]*2.5
	var control_b: Vector2=b-outgoing["axis"]*2.5
	for sample_index in 25:
		var t: float=sample_index/24.0; var u: float=1-t
		points.append(a*u*u*u+control_a*3*u*u*t+control_b*3*u*t*t+b*t*t*t)
	return points

static func length(points: PackedVector2Array) -> float:
	var total: float=0
	for index in range(1,points.size()): total+=points[index-1].distance_to(points[index])
	return total

static func sample(points: PackedVector2Array,distance: float) -> Dictionary:
	if points.is_empty(): return {"point":Vector2.ZERO,"heading":Vector2.ZERO,"finished":true}
	var remaining: float=maxf(0,distance)
	for index in range(1,points.size()):
		var segment: Vector2=points[index]-points[index-1]; var span: float=segment.length()
		if span>.00001 and remaining<span: return {"point":points[index-1]+segment*(remaining/span),"heading":segment/span,"finished":false}
		remaining-=span
	var heading: Vector2=(points[-1]-points[-2]).normalized() if points.size()>1 else Vector2.ZERO
	return {"point":points[-1],"heading":heading,"finished":true}
