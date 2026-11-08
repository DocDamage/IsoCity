extends Node

var street_traffic: Node
var transit: Node

const Plan=preload("res://scripts/builder/citizen_plan.gd")
const Entrances=preload("res://scripts/builder/entrance_anchors.gd")
const Walker3D=preload("res://scripts/builder/player_3d.gd")
const SchoolPlan=preload("res://scripts/builder/school_plan.gd")
const Weather=preload("res://scripts/builder/weather_plan.gd")
var dimension: String="2d"
var library: RefCounted
var container: Node
var plan: Dictionary={}
var residents: Array[Dictionary]=[]
var obstacles: Array[Rect2]=[]
var market_obstacles: Array[Rect2]=[]
var obstacle_layers: Dictionary={}
var hour: float=7
var preview_day: int=0
var paused: bool=false
var active: bool=true
var route_cache: Dictionary={}
var route_attempts: int=0
var scene_signature: int=0
var arrival_heights: Dictionary={}
var businesses: Node
var camping: Node
var activities: RefCounted
var schools=preload("res://scripts/builder/school_runtime.gd").new()
# Editor rendering may show a floor while simulation still owns the city.
var city_data: Callable
var terrain_heights: Dictionary={}
var terrain_data: Dictionary={}:
	set(value):
		terrain_data=value
		terrain_heights=preload("res://scripts/builder/terrain_plan.gd").lookup(value) if preload("res://scripts/builder/terrain_plan.gd").settings(value)["enabled"] else {}

func configure(data: Dictionary,assets: RefCounted,instances: Dictionary,parent: Node,visible_only: bool=true) -> void:
	terrain_data=data
	obstacle_layers.clear()
	var exterior: Node=get_parent()
	if is_instance_valid(exterior) and "exploration" in exterior and is_instance_valid(exterior.exploration):
		camping=exterior.exploration.camping
	if is_instance_valid(exterior) and "exploration" in exterior and is_instance_valid(exterior.exploration) and exterior.exploration.interior:
		for state in exterior.exploration.exterior_states:
			for entry in state.get("collisions",[]):
				if is_instance_valid(entry["node"]):obstacle_layers[entry["node"].get_instance_id()]=entry["layer"]
	dimension=data["mode"]; library=assets
	var config: Dictionary=Plan.settings(data)
	var with_schools: bool=SchoolPlan.active(data)
	if activities and (not config["enabled"] or not (config["interior_activities"] or with_schools)):activities.close();activities=null
	var signature: int=hash([dimension,data["objects"],data.get("layers",{}),data.get("terrain",{}),data.get("terrain_vertices",[]),data.get("water_cells",[]),config["enabled"],config["interior_activities"],config["population"],config["seed"],config.get("appearance",""),visible_only])
	if signature==scene_signature and not plan.is_empty():
		if config["start_hour"]!=plan["settings"]["start_hour"]: hour=config["start_hour"]
		plan["settings"]=config
		if activities:activities.reconcile()
		return
	if activities:activities.prepare_rebuild(config.get("appearance",""))
	var previous: Dictionary={}
	if is_instance_valid(container) and container.get_parent()==parent:
		for resident in residents: previous[resident["id"]]=resident
	else: clear()
	var old_settings: Dictionary=plan.get("settings",{})
	if old_settings.is_empty() or old_settings.get("start_hour")!=config["start_hour"]: hour=config["start_hour"]
	residents=[]; obstacles.clear(); route_cache.clear(); arrival_heights.clear(); route_attempts=0
	scene_signature=signature
	if not config["enabled"]:
		clear(); plan={"settings":config,"notices":PackedStringArray(),"lookup":{}}; return
	if not is_instance_valid(container):
		container=Node2D.new() if dimension=="2d" else Node3D.new()
		container.name="CitizenActors"
		if container is Node2D: container.y_sort_enabled=true
		parent.add_child(container)
	var arrivals: Dictionary={}
	for item in data["objects"]:
		if not instances.has(item["uid"]): continue
		var node: Node=instances[item["uid"]]
		if visible_only and not node.visible: continue
		collect_obstacles(node)
		if Plan.role(item).is_empty() and not (with_schools and (SchoolPlan.eligible(item) or SchoolPlan.playground(item))): continue
		var position: Variant=Entrances.position_for(node,item,dimension,library)
		arrivals[item["uid"]]=Vector2(position.x/16,position.y/8) if dimension=="2d" else Vector2(position.x,position.z)
		if dimension=="3d": arrival_heights[item["uid"]]=position.y
	plan=Plan.build(data,library,arrivals,visible_only)
	schools.configure(data,library,arrivals,plan["lookup"])
	obstacles.append_array(preload("res://scripts/builder/terrain_navigation.gd").obstacles(data,dimension=="2d"))
	var retained: Dictionary={};var present: Dictionary={}
	for assignment in plan["residents"]:
		var home: Dictionary=plan["lookup"][assignment["home"]]
		var resident: Dictionary=assignment.duplicate(true)
		var slot: int=int(resident["id"].get_slice("_",resident["id"].get_slice_count("_")-1))
		var angle: float=posmod(str(resident["home"]).hash(),360)*PI/180+slot*2.399963
		resident["spacing"]=Vector2(cos(angle),sin(angle))*(.35+.3*sqrt(slot%9))
		var spawn: Dictionary=route(home["point"]+resident["spacing"],home["point"]+resident["spacing"])
		resident.merge({"actor":null,"target":"","path":PackedVector2Array(),"index":0,"status":"Waiting for a route","waiting":"","visits":[],"stalled":0.0,"retry":0.0,"blocked":false})
		if previous.has(resident["id"]) and is_instance_valid(previous[resident["id"]]["actor"]) and previous[resident["id"]]["actor"].get_meta("citizen_appearance","")==config.get("appearance",""):
			var old: Dictionary=previous[resident["id"]]
			resident["actor"]=old["actor"]; resident["visits"]=old["visits"]
			for key in ["activity_done_target","activity_done_slot"]:
				if old.has(key):resident[key]=old[key]
			resident["blocked"]=not schools.trips.has(resident["id"]) and not (activities and activities.scheduler.jobs.has(resident["id"])) and obstacles.any(func(box: Rect2):return box.grow(.3).has_point(point(old["actor"])))
			if resident["blocked"]:
				resident["waiting"]="Construction blocks this resident; clear the area to resume."
				resident["status"]=resident["waiting"]
				old["actor"].velocity=Vector2.ZERO if dimension=="2d" else Vector3.ZERO
		elif not spawn["path"].is_empty() and (dimension=="2d" or absf(arrival_heights.get(home["uid"],0)-terrain_height(data,spawn["start"]))<.5):
			var actor: Node=make_actor(resident["id"])
			var point: Vector2=spawn["start"]
			actor.teleport_to(Vector2(point.x*16,point.y*8) if dimension=="2d" else Vector3(point.x,terrain_height(data,point)+.05,point.y))
			actor.visible=false
			resident["actor"]=actor; resident["status"]="At home"
		else: resident["status"]="Home has no safe entrance approach"; resident["waiting"]=resident["status"]
		if is_instance_valid(resident["actor"]): retained[resident["actor"].get_instance_id()]=true
		residents.append(resident)
		present[resident["id"]]=true
	schools.assign(residents,plan["lookup"])
	if config["interior_activities"] or not schools.sites.is_empty():
		if not activities:activities=load("res://scripts/builder/resident_activity_runtime.gd").new(self)
		activities.reconcile()
	for old in previous.values():
		# Completed visits have already departed, but their inventory is retained
		# for the living resident. Forget it when that identity leaves the city.
		if not present.has(old["id"]) and is_instance_valid(businesses):businesses.service.forget(old["id"])
		if is_instance_valid(old["actor"]) and not retained.has(old["actor"].get_instance_id()):
			schools.forget(old["id"],transit if is_instance_valid(transit) else null)
			if is_instance_valid(old["actor"]): old["actor"].free()

func make_actor(identity: String) -> Node:
	var actor: Node
	if dimension=="2d":
		var appearance: String=plan.get("settings",{}).get("appearance","")
		var path: String=library.assets[appearance]["path"] if library and library.assets.has(appearance) and library.assets[appearance]["data"].get("kind","")=="char" else "res://scenes/items/Characters/Office_Worker.tscn"
		actor=load(path).instantiate(); actor.set_meta("citizen_appearance",appearance)
		actor.is_player_controlled=false; actor.move_speed=48
	else:
		actor=Walker3D.new(); actor.move_speed=1.8; actor.active=false
	actor.name=identity.validate_node_name(); actor.set_meta("citizen_id",identity)
	actor.collision_layer=0; actor.collision_mask=1 if dimension=="2d" else 3
	container.add_child(actor)
	actor.set_physics_process(false)
	return actor

func obstacle_layer(body: Node) -> int:
	# Suspended city colliders stay physically inactive. Navigation uses their
	# current authored layers, including objects edited during a room visit.
	return obstacle_layers.get(body.get_instance_id(),body.collision_layer)

func collect_obstacles(node: Node) -> void:
	preload("res://scripts/builder/walk_obstacles.gd").append(node,obstacles,obstacle_layer,
		func(point: Vector2)->float: return terrain_height(terrain_data,point))

func route(from: Vector2,to: Vector2) -> Dictionary:
	var key: String=str((from/Plan.CELL_SIZE).round())+":"+str((to/Plan.CELL_SIZE).round())
	if not route_cache.has(key):
		route_attempts+=1
		route_cache[key]=Plan.route(from,to,obstacles if market_obstacles.is_empty() else obstacles+market_obstacles)
	return route_cache[key]

func set_market_obstacles(values: Array[Rect2]) -> void:
	if values==market_obstacles: return
	market_obstacles=values
	route_cache.clear()

func destination(uid: String) -> Dictionary:
	if is_instance_valid(camping) and uid.begins_with("camp/"): return camping.destination(uid)
	if is_instance_valid(businesses):
		var market: Dictionary=businesses.market_destination(uid)
		if not market.is_empty(): return market
	return plan["lookup"].get(uid,{})
func terrain_height(data: Dictionary,point: Vector2) -> float:
	var terrain=preload("res://scripts/builder/terrain_plan.gd")
	return terrain.sample(data,point,terrain_heights)["height"] if terrain.settings(data)["enabled"] else 0.0

func point(actor: Node) -> Vector2:
	return Vector2(actor.position.x/16,actor.position.y/8) if dimension=="2d" else Vector2(actor.position.x,actor.position.z)

func step(delta: float) -> void:
	if paused or not active or plan.is_empty() or not plan["settings"]["enabled"]: return
	if not is_finite(delta) or delta<=0: return
	var advance: float=delta*24.0/plan["settings"]["day_length"]
	preview_day+=floori((hour+advance)/24)
	hour=fposmod(hour+advance,24)
	schools.prepare(hour,advance if delta<=.25 else 0.0,activities)
	var weather: Dictionary=Weather.state(terrain_data)
	if activities:activities.step(delta,weather["walking_speed"])
	var searches: int=0
	if is_instance_valid(camping): camping.resident_begin(residents)
	for resident in residents:
		var actor: Node=resident["actor"]
		if not is_instance_valid(actor): continue
		if is_instance_valid(camping) and camping.jobs.has(resident["id"]) and exterior_suspended(): continue
		if is_instance_valid(businesses) and businesses.market.assignments.has(resident["id"]) and not businesses.outdoor_market(): continue
		resident["retry"]=maxf(0,resident["retry"]-delta)
		var target: String=Weather.target(resident,hour,weather)
		if (resident["target"].begins_with("market/") or resident["target"].begins_with("camp/")) and destination(resident["target"]).is_empty():
			resident["target"]=""
			resident["path"]=PackedVector2Array()
			resident["index"]=0
			resident["retry"]=0.0
		resident["business_state"]=""
		if is_instance_valid(businesses):
			var visit: Dictionary=businesses.service.result(resident["id"])
			if businesses.service.businesses.has(target) and not businesses.available(target) and not (visit.get("state","")=="active" and visit.get("business","")==target): target=resident["home"]
		var pupil: bool=schools.enrolled.has(resident["id"])
		target=schools.desired(resident,hour,target)
		var camp_target: String=""
		if is_instance_valid(camping) and not pupil and not exterior_suspended():
			var at_park: bool=Plan.activity(hour,resident["offset"])=="park" and target==resident["park"] and not resident["blocked"]
			var other_job: bool=(activities and activities.scheduler.jobs.has(resident["id"])) or (is_instance_valid(businesses) and businesses.market.assignments.has(resident["id"]))
			camp_target=camping.resident_target(self,resident,at_park and not other_job)
		var market_target: String=""
		if camp_target.is_empty() and is_instance_valid(businesses) and not pupil and not exterior_suspended():
			var can_shop: bool=Plan.activity(hour,resident["offset"]) in ["shop","park"] and not resident["blocked"] and not (activities and activities.scheduler.jobs.has(resident["id"]))
			market_target=businesses.market_target(resident,actor,can_shop)
		if activities and camp_target.is_empty():
			var job: Dictionary=activities.scheduler.jobs.get(resident["id"],{})
			if job.get("hold_station",false):
				if activities.handled(resident,job["building"]):continue
			elif market_target.is_empty():
				if plan["settings"]["interior_activities"] and not pupil: target=activities.resolve_target(resident,target)
				if activities.handled(resident,target):continue
		if resident["blocked"]: continue
		if schools.using_bus(self,resident,target): continue
		if not camp_target.is_empty(): target=camp_target
		elif not market_target.is_empty(): target=market_target
		var planned: Dictionary=destination(target)
		if is_instance_valid(businesses):
			var visit: Dictionary=businesses.service.result(resident["id"])
			if not visit.is_empty() and visit["business"]!=planned.get("vendor",target): businesses.service.depart(resident["id"])
		if not planned.is_empty() and resident["target"]!=target and searches<2 and resident["retry"]<=0:
			searches+=1
			var spacing: Vector2=Vector2.ZERO if planned["role"] in ["market","camp"] else resident["spacing"]
			var path: Dictionary=route(point(actor),planned["point"]+spacing)
			var missed_camp: bool=planned["role"]=="camp" and path.get("goal",planned["point"]).distance_to(planned["point"])>.65
			if path["path"].is_empty() or missed_camp or point(actor).distance_to(path.get("start",point(actor)))>.8:
				resident["waiting"]="No safe route to "+planned["name"]; resident["status"]=resident["waiting"]; resident["retry"]=3
			else:
				resident["target"]=target; resident["path"]=path["path"]; resident["index"]=0; resident["stalled"]=0
				resident["waiting"]=""
				resident["status"]="Walking to "+planned["name"]
		var movement:=Vector2.ZERO
		var path: PackedVector2Array=resident["path"]
		while resident["index"]<path.size() and point(actor).distance_to(path[resident["index"]])<.16: resident["index"]+=1
		if resident["index"]<path.size(): movement=(path[resident["index"]]-point(actor)).normalized()
		elif not resident["target"].is_empty():
			var arrival: Dictionary=destination(resident["target"])
			resident["status"]="At "+arrival["role"]+" · "+arrival["name"]
			var level_reached: bool=dimension=="2d" or absf(actor.position.y-arrival.get("height",arrival_heights.get(resident["target"],0)))<.5
			if not level_reached: resident["waiting"]="Entrance is above or below the reachable walking surface."
			if level_reached and (resident["visits"].is_empty() or resident["visits"].back()!=resident["target"]):
				resident["visits"].append(resident["target"])
				if resident["visits"].size()>32: resident["visits"].pop_front()
			if level_reached and arrival["role"]=="camp" and is_instance_valid(camping) and camping.resident_arrive(resident,resident["target"],delta): continue
			if level_reached and pupil and schools.arrived(self,resident,resident["target"]):
				if not activities or not activities.scheduler.jobs.has(resident["id"]): actor.visible=true
				continue
			if level_reached and arrival["role"] not in ["market","camp"] and activities and plan["settings"]["interior_activities"] and not pupil and activities.arrive(resident,resident["target"]):continue
			if level_reached and is_instance_valid(businesses) and not pupil:
				var visit: Dictionary=businesses.resident_arrival(resident["target"],resident["id"],actor)
				if not visit.is_empty():
					resident["business_state"]=visit["state"]
					resident["status"]+=" · "+visit["reason"]
		var previous: Vector2=point(actor)
		if is_instance_valid(street_traffic) and not movement.is_zero_approx() and (pupil or not exterior_suspended()):
			var metric: Vector2=Vector2(previous.x+previous.y,previous.y-previous.x) if dimension=="2d" else previous
			var heading: Vector2=Vector2(movement.x+movement.y,movement.y-movement.x).normalized() if dimension=="2d" else movement
			if not street_traffic.pedestrian_can_enter(metric,metric+heading*.45):
				movement=Vector2.ZERO
				if dimension=="2d": actor.velocity=Vector2.ZERO
				else:
					actor.velocity.x=0
					actor.velocity.z=0
				resident["waiting"]="Waiting for the pedestrian signal"
			elif resident["waiting"]=="Waiting for the pedestrian signal":
				resident["waiting"]=""
		actor.visible=not movement.is_zero_approx() or resident["target"].is_empty() or not resident["waiting"].is_empty() or destination(resident["target"]).get("role") in ["park","market","camp"] or resident["business_state"]=="queued"
		if activities and exterior_suspended():
			move_offscreen(resident,movement,delta,weather["walking_speed"])
		elif dimension=="2d":
			actor.move_character(delta,Vector2(movement.x*16,movement.y*8).normalized()*weather["walking_speed"])
			actor._update_animation(delta)
		else: actor.move_character(delta,Vector3(movement.x,0,movement.y)*weather["walking_speed"])
		resident["stalled"]=resident["stalled"]+delta if not movement.is_zero_approx() and point(actor).distance_to(previous)<.001 else 0
		if resident["stalled"]>2:
			resident["path"]=PackedVector2Array(); resident["target"]=""; resident["retry"]=3; resident["stalled"]=0
			resident["status"]="Route obstructed; waiting to retry"
			resident["waiting"]=resident["status"]
		if not resident["waiting"].is_empty(): resident["status"]=resident["waiting"]

func interior_activities_enabled() -> bool:
	return not plan.is_empty() and plan["settings"].get("enabled",false) and (plan["settings"].get("interior_activities",false) or not schools.sites.is_empty())

func exterior_suspended() -> bool:
	var root: Node=get_parent()
	return is_instance_valid(root) and "exploration" in root and root.exploration and root.exploration.interior!=null

func move_offscreen(resident: Dictionary,movement: Vector2,delta: float,speed_scale: float) -> void:
	if movement.is_zero_approx():return
	var actor: Node=resident["actor"];var next: Vector2=resident["path"][resident["index"]]
	# The city colliders are suspended during a room visit. Advance the existing
	# validated exterior path logically instead of colliding with the room plane.
	if dimension=="2d":actor.teleport_to(actor.position.move_toward(Vector2(next.x*16,next.y*8),actor.move_speed*delta*speed_scale))
	else:
		var at: Vector2=point(actor).move_toward(next,actor.move_speed*delta*speed_scale);actor.teleport_to(Vector3(at.x,terrain_height(terrain_data,at)+.05,at.y))

func _physics_process(delta: float) -> void: step(delta)

func summary() -> String:
	if plan.is_empty() or not plan["settings"]["enabled"]: return "Citizen simulation is off."
	var walking: int=0; var blocked: int=0
	for resident in residents:
		if resident["index"]<resident["path"].size(): walking+=1
		elif not is_instance_valid(resident["actor"]) or not resident["waiting"].is_empty(): blocked+=1
	return "%02d:%02d · %d residents · %d walking · %d waiting for routes" % [floori(hour),floori(fposmod(hour,1)*60),residents.size(),walking,blocked]

func clear() -> void:
	if is_instance_valid(camping): camping.clear_residents()
	if activities:activities.close();activities=null
	schools.reset(transit if is_instance_valid(transit) else null)
	if is_instance_valid(businesses):
		for resident in residents: businesses.service.forget(resident["id"])
	residents.clear(); obstacles.clear(); obstacle_layers.clear(); route_cache.clear(); arrival_heights.clear(); route_attempts=0
	if is_instance_valid(container): container.free()
	container=null

func reset() -> void:
	clear(); plan={}; scene_signature=0; preview_day=0

func _notification(what: int) -> void:
	# Workspace switching reparents the canvas and temporarily removes this
	# entire world from the tree. Keep its transient actors/jobs for re-entry;
	# explicit resets and actual destruction still release every reservation.
	if what==NOTIFICATION_PREDELETE:clear()
