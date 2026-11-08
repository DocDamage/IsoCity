extends RefCounted

const Plan=preload("res://scripts/builder/traffic_plan.gd")
const Fleet=preload("res://scripts/builder/fleet_plan.gd")
const BUCKET: float=16.0
const MAX_REQUESTS: int=256
const MAX_EXPANSIONS: int=48
const BUDGET_US: int=900

var revision: int=0
var serial: int=0
var expanded: int=0
var network: Dictionary={}
var layout: Array=[]
var indexed: Array[Rect2]=[]
var requests: Dictionary={}
var completed: Dictionary={}
var order: Array[String]=[]
var obstacle_cells: Dictionary={}
var large_obstacles: Array[Rect2]=[]

func configure(graph: Dictionary,obstacles: Array[Rect2],anchors: Dictionary={},approach_radius: float=16) -> bool:
	var boxes: Array[Rect2]=obstacles.duplicate()
	boxes.sort_custom(func(a: Rect2,b: Rect2)->bool:
		if a.position.x!=b.position.x: return a.position.x<b.position.x
		if a.position.y!=b.position.y: return a.position.y<b.position.y
		if a.size.x!=b.size.x: return a.size.x<b.size.x
		return a.size.y<b.size.y
	)
	if indexed!=boxes:
		indexed=boxes
		index_obstacles(boxes)
	var relevant: Array[Rect2]=boxes.filter(func(box: Rect2)->bool:return near_road(graph,box.grow(approach_radius)))
	var next: Array=[graph["mode"],graph["sections"],graph["edges"],graph["closed_sections"],relevant,anchors]
	if next==layout: return false
	revision+=1
	network=graph
	layout=next
	clear_requests()
	return true

func near_road(graph: Dictionary,area: Rect2) -> bool:
	var offset: Vector2=Plan.center(Vector2i.ZERO,graph["mode"])
	var first:=Vector2i(((area.position-offset)/8).ceil())
	var last:=Vector2i(((area.end-offset)/8).floor())
	var count: int=(last.x-first.x+1)*(last.y-first.y+1)
	var sections: Dictionary=graph["sections"]
	if count>sections.size():
		for section in sections.values():
			var cell: Vector2i=section["cell"]
			if cell.x>=first.x and cell.y>=first.y and cell.x<=last.x and cell.y<=last.y: return true
		return false
	for x in range(first.x,last.x+1):
		for y in range(first.y,last.y+1):
			if sections.has(Plan.Roads.key(Vector2i(x,y))): return true
	return false

func index_obstacles(boxes: Array[Rect2]) -> void:
	obstacle_cells.clear()
	large_obstacles.clear()
	for box in boxes:
		var first:=Vector2i((box.position/BUCKET).floor())
		var last:=Vector2i((box.end/BUCKET).floor())
		if (last.x-first.x+1)*(last.y-first.y+1)>64:
			large_obstacles.append(box)
			continue
		for x in range(first.x,last.x+1):
			for y in range(first.y,last.y+1):
				var key:=Vector2i(x,y)
				if not obstacle_cells.has(key): obstacle_cells[key]=[]
				obstacle_cells[key].append(box)

func nearby(bounds: Rect2) -> Array:
	var found: Dictionary={}
	var first:=Vector2i((bounds.position/BUCKET).floor())
	var last:=Vector2i((bounds.end/BUCKET).floor())
	for x in range(first.x,last.x+1):
		for y in range(first.y,last.y+1):
			for box in obstacle_cells.get(Vector2i(x,y),[]):
				if bounds.intersects(box,true): found[box]=true
	for box in large_obstacles:
		if bounds.intersects(box,true): found[box]=true
	return found.keys()

func path_clear(path: PackedVector2Array,vehicle: Dictionary,distance: float=0) -> bool:
	if path.is_empty(): return false
	var fields: Dictionary=vehicle
	if not vehicle.has("half_length") and vehicle.has("length"):
		fields={"half_length":vehicle["length"]*.5,"half_width":vehicle["width"]*.5}
	var radius: float=Vector2(fields.get("half_length",1.3),fields.get("half_width",.55)).length()+.13
	if path.size()==1:
		return not nearby(Rect2(path[0]-Vector2.ONE*radius,Vector2.ONE*radius*2)).any(func(box: Rect2)->bool:
			return Fleet.intersects_obstacle(fields,path[0],fields.get("heading",Vector2.RIGHT),box)
		)
	var walked: float=0.0
	for index in range(1,path.size()):
		var start: Vector2=path[index-1]
		var finish: Vector2=path[index]
		var length: float=start.distance_to(finish)
		walked+=length
		if walked+.00001<distance or length<.00001: continue
		var heading: Vector2=start.direction_to(finish)
		start=finish-heading*clampf(walked-distance,0,length)
		var area:=Rect2(start,Vector2.ZERO).expand(finish).grow(radius)
		var boxes: Array=nearby(area)
		if boxes.is_empty(): continue
		# Sweeping an oriented rectangle in a straight line is interval overlap
		# on its two axes and the two axes of the fixed obstacle.
		for box in boxes:
			if Fleet.sweep_obstacle(fields,start,finish,heading,box): return false
	return true

func compatible(from: String,at: String,to: String,profile: Dictionary) -> bool:
	if not Fleet.fit_turn(network,from,at,to,profile): return false
	var minimum: float=profile.get("minimum_road_width",0)
	if minimum>0 and (network["sections"][at]["width"]<minimum or network["sections"][to]["width"]<minimum): return false
	if profile.get("terminal_uturn_only",false) and from==to and network["sections"][at]["neighbors"].size()>1: return false
	if not from.is_empty() and not path_clear(Plan.turn(network,from,at,to),profile): return false
	return path_clear(network["edges"][Plan.edge_id(at,to)]["points"],profile)

func request(actor: String,at: String,incoming: String,goals: Dictionary,profile: Dictionary) -> int:
	return request_from(actor,[Plan.edge_id(incoming,at)],goals,profile)

func request_from(actor: String,starts: Array,goals: Dictionary,profile: Dictionary) -> int:
	cancel(actor)
	if starts.is_empty() or goals.is_empty() or requests.size()+completed.size()>=MAX_REQUESTS: return 0
	serial+=1
	var previous: Dictionary={}
	for start in starts: previous[start]=""
	requests[actor]={"id":serial,"revision":revision,"goals":goals,"profile":profile,
		"queue":starts.duplicate(),"cursor":0,"previous":previous}
	order.append(actor)
	return serial

func cancel(actor: String) -> void:
	requests.erase(actor)
	completed.erase(actor)
	order.erase(actor)

func clear_requests() -> void:
	requests.clear()
	completed.clear()
	order.clear()

func step(limit: int=MAX_EXPANSIONS,time_us: int=BUDGET_US) -> void:
	var started: int=Time.get_ticks_usec()
	expanded=0
	while not order.is_empty() and expanded<limit and Time.get_ticks_usec()-started<time_us:
		var actor: String=order.pop_front()
		expand_one(actor)
		expanded+=1
		if requests.has(actor): order.append(actor)

func expand_one(actor: String) -> void:
	var work: Dictionary=requests[actor]
	var state: String=work["queue"][work["cursor"]]
	work["cursor"]+=1
	var at: String=state.get_slice(">",1)
	var from: String=state.get_slice(">",0)
	if network["sections"].has(at) and work["goals"].has(at):
		var permitted: Array=work["goals"][at]
		if permitted.is_empty() or from in permitted:
			var route: PackedStringArray=[]
			var start: String=""
			while not state.is_empty():
				route.append(state.get_slice(">",1))
				start=state
				state=work["previous"][state]
			route.reverse()
			finish(actor,route,start)
			return
	for next in Plan.exits(network,at):
		var edge: String=Plan.edge_id(at,next)
		if not work["previous"].has(edge) and compatible(from,at,next,work["profile"]):
			work["previous"][edge]=state
			work["queue"].append(edge)
	if work["cursor"]==work["queue"].size(): finish(actor,[])

func finish(actor: String,route: PackedStringArray,start: String="") -> void:
	var work: Dictionary=requests[actor]
	completed[actor]={"id":work["id"],"revision":work["revision"],"route":route,"start":start}
	requests.erase(actor)

func take(actor: String,id: int) -> Dictionary:
	var result: Dictionary=completed.get(actor,{})
	if result.get("id",0)!=id or result.get("revision",-1)!=revision: return {}
	completed.erase(actor)
	return result
