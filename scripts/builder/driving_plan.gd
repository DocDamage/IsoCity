extends RefCounted
const PATH: String="res://resources/catalog/driving.json"
const Traffic=preload("res://scripts/builder/traffic_plan.gd")
const Roads=preload("res://scripts/builder/roads.gd")
const Cycling=preload("res://scripts/builder/cycling_plan.gd")
static var catalog: Dictionary={}
static func definitions() -> Dictionary:
	if catalog.is_empty(): catalog=JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return catalog
static func valid(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.has("enabled") and not value["enabled"] is bool: return false
	for key in ["max_speed","reverse_speed","acceleration","braking","steering","reach"]:
		if not value.has(key): continue
		var n: Variant=value[key]
		var bounds: Vector2=Vector2(.5,24) if key in ["max_speed","reverse_speed"] else (Vector2(.2,4) if key=="steering" else (Vector2(.5,6) if key=="reach" else Vector2(.5,20)))
		if not (n is float or n is int) or not is_finite(float(n)) or n<bounds.x or n>bounds.y: return false
	return true
static func profile(item: Dictionary) -> Dictionary:
	var raw: Variant=item.get("driving",{})
	if item.has("missing_asset") or not valid(raw) or not raw.get("enabled",true) or not definitions()["assets"].has(item.get("asset","")): return {}
	var result: Dictionary=definitions()["defaults"].duplicate(true)
	result.merge(definitions()["assets"][item["asset"]],true); result.merge(raw,true)
	return result
static func rider_profile(item: Dictionary,data: Dictionary) -> Dictionary:
	var cycling: Dictionary=Cycling.profile(item,data)
	return profile(item) if cycling.is_empty() else cycling
static func yaw(item: Dictionary, config: Dictionary={}) -> float:
	if item["asset"].begins_with("3d:"): return deg_to_rad(float(item["direction"]))
	var authored: Dictionary=config.get("view_yaws",definitions()["assets"].get(item["asset"],{}).get("view_yaws",{}))
	if authored.has(item["direction"]): return deg_to_rad(float(authored[item["direction"]]))
	return ["NE","SE","SW","NW"].find(item["direction"])*PI*.5
static func direction(item: Dictionary,angle: float,config: Dictionary={}) -> String:
	var authored: Dictionary=config.get("view_yaws",definitions()["assets"].get(item["asset"],{}).get("view_yaws",{}))
	if not authored.is_empty():
		var best: String=str(authored.keys()[0]); var distance: float=INF
		for view in authored:
			var delta: float=absf(angle_difference(angle,deg_to_rad(float(authored[view]))))
			if delta<distance: distance=delta; best=view
		return best
	return str(rad_to_deg(angle)) if item["asset"].begins_with("3d:") else ["NE","SE","SW","NW"][posmod(roundi(angle/(PI*.5)),4)]
static func heading(angle: float) -> Vector2: return Vector2(sin(angle),cos(angle))
static func center(item: Dictionary,library: RefCounted,mode: String) -> Vector2:
	return Traffic.metric(item["position"],mode)+Roads.center_offset(library,item["asset"],item["direction"],item["scale"],mode)*(2 if mode=="2d" else 1)
static func dimensions(item: Dictionary,library: RefCounted,mode: String,config: Dictionary={}) -> Vector2:
	var size: float=item["scale"]
	if config.get("cycle",false):
		var projection: float = 2.0 if mode=="2d" and item["asset"].begins_with("3d:") else 1.0
		return Vector2(config["extent"][0],config["extent"][1])*size*projection
	if item["asset"].begins_with("3d:"):
		var box: AABB=Roads.bounds_for(library,item["asset"])
		return Vector2(maxf(.3,box.size.x*.5*size),maxf(.5,box.size.z*.5*size))
	var view: Dictionary=library.assets[item["asset"]]["data"]["directions"]["SE"]
	var footprint: Array=view.get("footprint",[2,1]); var factor: float=1 if mode=="2d" else .5
	return Vector2(minf(footprint[0],footprint[1]),maxf(footprint[0],footprint[1]))*size*factor
static func world(point: Vector2,mode: String,height: float=0) -> Variant:
	var values: Array=Traffic.world(point,mode,height)
	return Vector2(values[0],values[1]) if mode=="2d" else Vector3(values[0],values[1],values[2])
static func nearby(exploration: Node,parked: Dictionary,only_uid: String="") -> Dictionary:
	if not exploration.enabled or exploration.interior or not exploration.editor_scope.is_empty() or exploration.entering: return {}
	var context: Dictionary=preload("res://scripts/builder/prop_plan.gd").context(exploration)
	if context["data"].get("interior_room",false): return {}
	var player: Node=exploration.player; var local: Variant=context["world"].to_local(player.global_position)
	var position: Vector2=Traffic.metric([local.x,local.y,0] if local is Vector2 else [local.x,local.y,local.z],exploration.dimension)
	var best: float=INF; var result: Dictionary={}
	for item in context["data"].get("objects",[]):
		if not only_uid.is_empty() and item["uid"]!=only_uid: continue
		var config: Dictionary=rider_profile(item,context["data"]); var node: Node=context["instances"].get(item["uid"])
		if config.get("cycle",false) and item.get("cycling",{}).get("npc",false): continue
		if config.is_empty() or not is_instance_valid(node) or not node.is_visible_in_tree() or not item.get("visible",true): continue
		if absf(float(item.get("tilt",[0,0])[0]))>1 or absf(float(item.get("tilt",[0,0])[1]))>1 or absf(float(item.get("angle",0)))>.1: continue
		var current: Dictionary=parked.get(item["uid"],{}); var point: Vector2=current.get("point",center(item,exploration.library,exploration.dimension)); var angle: float=current.get("yaw",yaw(item,config))
		var extent: Vector2=dimensions(item,exploration.library,exploration.dimension,config); var forward: Vector2=heading(angle); var right:=Vector2(forward.y,-forward.x); var relative: Vector2=position-point
		var distance: float=Vector2(maxf(0,absf(relative.dot(right))-extent.x),maxf(0,absf(relative.dot(forward))-extent.y)).length()
		if distance>config["reach"] or distance>=best: continue
		var height: float=float(node.get_meta("terrain_height",0)) if exploration.dimension=="2d" else node.global_position.y
		if absf((float(player.get_meta("terrain_height",0)) if exploration.dimension=="2d" else player.global_position.y)-height)>1.5: continue
		var destination: Variant=context["world"].to_global(world(point,exploration.dimension,height))
		if not preload("res://scripts/builder/prop_plan.gd").reachable(exploration,node,destination): continue
		best=distance; result=context.duplicate(false); result.merge({"item":item,"node":node,"profile":config,"point":point,"yaw":angle,"extent":extent,"distance":player.global_position.distance_to(destination)})
	return result
