extends Node

const Plan=preload("res://scripts/builder/traffic_plan.gd")
const Fleet=preload("res://scripts/builder/fleet_plan.gd")
const Junctions=preload("res://scripts/builder/traffic_junctions.gd")
const Instance=preload("res://scripts/builder/asset_instance.gd")
const Roads=preload("res://scripts/builder/roads.gd")
const CAR_SIZE=.5
var plan: Dictionary={}
var road_inputs: Array=[]
var base_plan: Dictionary={}
var route_queue=preload("res://scripts/builder/traffic_route_queue.gd").new()
var vehicles: Array[Dictionary]=[]
var fleet_pool: Array[Dictionary]=[]
var external_vehicles: Array[Dictionary]=[]
var transit: Node
var services: Node
var driving: Node
var bays: Dictionary={}
var bay_owners: Dictionary={}
var gates=Junctions.new()
var render_signals: bool=true
var signal_views=preload("res://scripts/builder/traffic_signal_views.gd").new()
var random:=RandomNumberGenerator.new()
var container: Node
var library: RefCounted
var dimension: String="2d"
var elapsed: float=0
var junction_time: float=0
var active: bool=true
var paused: bool=false
var pedestrians: Array[Node]=[]
var obstacles: Array[Rect2]=[]
var signature: int=0
var terrain_data: Dictionary={}
var terrain_heights: Dictionary={}
var terrain_waters: Dictionary={}

func configure(data: Dictionary,assets: RefCounted,instances: Dictionary,parent: Node,visible_only: bool=true) -> void:
	var stamp: int=hash([data.get("traffic",{}),data.get("fleet",{}),data.get("roads",[]),data.get("objects",[]),data.get("layers",{}),data.get("terrain",{}),data.get("terrain_vertices",[]),data.get("water_cells",[]),visible_only,parent.get_instance_id()])
	if stamp==signature and not plan.is_empty(): return
	var terrain=preload("res://scripts/builder/terrain_plan.gd")
	var heights: Dictionary=terrain.lookup(data) if terrain.settings(data)["enabled"] else {}
	terrain_data=data
	terrain_heights=heights
	terrain_waters=terrain.lookup(data,true)
	var previous: Dictionary=plan
	var previous_bays: Dictionary=bays.duplicate(true)
	var config: Dictionary=Plan.settings(data)
	var respawn: bool=previous.is_empty() or previous["settings"]["population"]!=config["population"] or previous["settings"]["seed"]!=config["seed"] or not is_instance_valid(container) or container.get_parent()!=parent
	dimension=data["mode"]; library=assets
	if respawn: clear()
	signature=stamp
	var inputs: Array=Plan.road_inputs(data)
	var surface_changed: bool=not road_inputs.is_empty() and (inputs[-3]!=road_inputs[-3] or inputs[-2]!=road_inputs[-2])
	if base_plan.is_empty() or inputs!=road_inputs:
		road_inputs=inputs.duplicate(true)
		base_plan=Plan.build(data)
	plan=base_plan.duplicate()
	plan["settings"]=config
	plan["notices"]=base_plan["notices"].duplicate()
	gates.synchronize(plan,junction_time)
	if render_signals and is_inside_tree():
		signal_views.synchronize(data,instances,assets)
		signal_views.draw(plan,gates,junction_time)
	if not config["enabled"]:
		clear()
		return
	if not is_instance_valid(container):
		container=Node2D.new() if dimension=="2d" else Node3D.new(); container.name="TrafficActors"
		if container is Node2D: container.y_sort_enabled=true
		parent.add_child(container)
	obstacles.clear()
	obstacles.append_array(preload("res://scripts/builder/terrain_navigation.gd").obstacles(data))
	var collision=preload("res://scripts/builder/citizen_runtime.gd").new()
	collision.terrain_data=data
	for item in data["objects"]:
		if not instances.has(item["uid"]): continue
		var node: Node=instances[item["uid"]]
		if visible_only and not node.visible: continue
		if is_instance_valid(driving) and not preload("res://scripts/builder/driving_plan.gd").profile(item).is_empty(): continue
		if not item.get("traffic_parking",false) or not Plan.parking_surface(item,library):
			if dimension=="2d": collect_2d_obstacles(node)
			else: collision.collect_obstacles(node)
	for box in collision.obstacles:
		if dimension=="3d": obstacles.append(box)
		else:
			var corners: Array[Vector2]=[box.position,box.end,Vector2(box.position.x,box.end.y),Vector2(box.end.x,box.position.y)]
			var converted:=Rect2(Vector2(box.position.x+box.position.y,box.position.y-box.position.x),Vector2.ZERO)
			for p in corners: converted=converted.expand(Vector2(p.x+p.y,p.y-p.x))
			obstacles.append(converted)
	collision.free()
	fleet_pool.clear()
	if config["population"]>0: fleet_pool=Fleet.pool(data,"traffic",library)
	bays=parking(data,instances,visible_only)
	var changed: bool=route_queue.configure(plan,obstacles,bays)
	for id in bay_owners.keys():
		if not bays.has(id): bay_owners.erase(id)
	if respawn:
		random.seed=config["seed"]; spawn()
	elif changed or surface_changed:
		for vehicle in vehicles:
			if changed: refresh_journey(vehicle,previous,previous_bays)
			if surface_changed and vehicle["phase"]!="blocked": pose(vehicle)

func route_checkpoint(vehicle: Dictionary) -> String:
	return vehicle.get("resume_phase",vehicle["phase"])

func lane_path(from: String,to: String) -> PackedVector2Array:
	return plan["edges"].get(Plan.edge_id(from,to),{}).get("points",PackedVector2Array())

func hold_journey(vehicle: Dictionary,reason: String) -> void:
	if vehicle["phase"]!="blocked": vehicle["resume_phase"]=vehicle["phase"]
	vehicle["phase"]="blocked"
	vehicle["status"]=reason
	vehicle["speed"]=0
	gates.release(vehicle["id"])
	release_bay(vehicle)
	route_queue.cancel(vehicle["id"])
	vehicle.erase("route_request")
	vehicle.erase("route_suffix")

func recover_to_stop_line(vehicle: Dictionary,edge: PackedVector2Array) -> bool:
	if edge.is_empty() or vehicle["point"].distance_to(edge[-1])>.001:
		return false
	vehicle["path"]=edge
	vehicle["distance"]=Plan.length(edge)
	vehicle["phase"]="edge"
	gates.release(vehicle["id"])
	return true

func recover_parking(vehicle: Dictionary,phase: String,edge: PackedVector2Array) -> bool:
	if edge.is_empty(): return false
	var path: PackedVector2Array=vehicle["path"]
	if path.is_empty(): return false
	var distance: float=vehicle["distance"]
	if phase!="parking_out":
		path=path.duplicate()
		path.reverse()
		distance=maxf(0,Plan.length(path)-distance)
	if path[-1].distance_to(edge[-1])>.001 or not route_queue.path_clear(path,vehicle,distance):
		return false
	release_bay(vehicle)
	vehicle["phase"]="parking_out"
	vehicle["path"]=path
	vehicle["distance"]=distance
	vehicle["timer"]=0.0
	return true

func hold_parking(vehicle: Dictionary,phase: String,previous_bays: Dictionary,reason: String) -> void:
	var bay: Dictionary=previous_bays.get(vehicle["bay"],{})
	if phase in ["parking_in","parked"] and not bay.is_empty():
		# Keep the approach for revalidation while releasing its live claim.
		vehicle["suspended_bay"]=bay
	hold_journey(vehicle,reason)

func restore_parking(vehicle: Dictionary,edge: PackedVector2Array) -> bool:
	var previous: Dictionary=vehicle.get("suspended_bay",{})
	if previous.is_empty() or edge.is_empty(): return false
	var id: String=previous["uid"]
	if bays.get(id,{})!=previous or bay_owners.has(id): return false
	var path: PackedVector2Array=vehicle["path"]
	if path.is_empty() or path[0].distance_to(edge[-1])>.001 or not route_queue.path_clear(path,vehicle): return false
	bay_owners[id]=vehicle["id"]
	vehicle["bay"]=id
	return true

func refresh_journey(vehicle: Dictionary,previous: Dictionary,previous_bays: Dictionary) -> void:
	var phase: String=route_checkpoint(vehicle)
	var from: String=vehicle["from"]
	var at: String=vehicle["to"]
	var next: String=vehicle["next"]
	var edge: PackedVector2Array=lane_path(from,at)
	var was_held: bool=vehicle["phase"]=="blocked"
	var needs_route: bool=was_held or vehicle.has("route_request") or vehicle.has("route_suffix")
	var bay: String=vehicle["bay"]
	var bay_changed: bool=not bay.is_empty() and (not bays.has(bay) or bays[bay]!=previous_bays.get(bay,{}))
	vehicle.erase("route_request")
	vehicle.erase("route_suffix")
	vehicle.erase("failed_bay")
	if phase in ["parked","parking_in","parking_out"]:
		if not (was_held and restore_parking(vehicle,edge)):
			if bay_changed or bay.is_empty() and phase!="parking_out" or was_held:
				if not recover_parking(vehicle,phase,edge):
					hold_parking(vehicle,phase,previous_bays,road_wait_reason(from,at,"Parking approach changed"))
					return
				phase="parking_out"
				needs_route=true
			elif edge.is_empty() or not route_queue.path_clear(vehicle["path"],vehicle,vehicle["distance"]):
				hold_parking(vehicle,phase,previous_bays,road_wait_reason(from,at,"Parking approach is obstructed"))
				return
	else:
		var active_path: PackedVector2Array=edge if phase=="edge" else Plan.turn(plan,from,at,next)
		var safe: bool=not active_path.is_empty() and active_path==vehicle["path"] and route_queue.path_clear(active_path,vehicle,vehicle["distance"])
		if phase=="turn":
			safe=safe and Fleet.fit_turn(plan,from,at,next,vehicle.get("fleet_profile",{}))
		if not safe:
			if phase!="turn" or not recover_to_stop_line(vehicle,edge):
				hold_journey(vehicle,road_wait_reason(from,at,"Current lane changed"))
				return
			phase="edge"
			needs_route=true
		if bay_changed:
			release_bay(vehicle)
			needs_route=true
	if was_held:
		vehicle["phase"]=phase
		vehicle["speed"]=0
		vehicle["status"]="Safe lane restored"
		vehicle.erase("resume_phase")
		vehicle.erase("suspended_bay")
	if phase in ["parking_in","parked"]: return
	var end: String=next if phase=="turn" else at
	var arrival: String=at if phase=="turn" else from
	if needs_route or not vehicle["bay"].is_empty() or Plan.exits(previous,end)!=Plan.exits(plan,end):
		if phase=="edge": gates.release(vehicle["id"],at)
		request_route(vehicle,end,arrival)

func road_wait_reason(from: String,to: String,fallback: String) -> String:
	for key in [from,to]:
		var closure: String=plan["closed_sections"].get(key,"")
		if not closure.is_empty(): return closure
	return fallback+". Waiting for a safe road connection."

func request_route(vehicle: Dictionary,at: String,from: String) -> void:
	var goals: Dictionary={}
	var bay: Dictionary=bays.get(vehicle["bay"],{})
	if not bay.is_empty():
		goals[bay["section"]]=[bay["from"]]
	else:
		for target in Plan.exits(plan,at):
			if target!=from: goals[target]=[at]
		if goals.is_empty() and from in Plan.exits(plan,at): goals[from]=[at]
	if goals.is_empty(): return
	var id: int=route_queue.request(vehicle["id"],at,from,goals,vehicle.get("fleet_profile",{}))
	if id>0: vehicle["route_request"]=id

func accept_route(vehicle: Dictionary) -> void:
	if not vehicle.has("route_request"): return
	var result: Dictionary=route_queue.take(vehicle["id"],vehicle["route_request"])
	if result.is_empty(): return
	vehicle.erase("route_request")
	if not result["route"].is_empty():
		vehicle["route_suffix"]=result["route"]
	elif not vehicle["bay"].is_empty():
		vehicle["failed_bay"]=vehicle["bay"]
		release_bay(vehicle)

func collect_2d_obstacles(node: Node) -> void:
	if node is CharacterBody2D: return
	var points: PackedVector2Array=[]
	if node is CollisionPolygon2D and not node.disabled and node.get_parent() is StaticBody2D and node.get_parent().collision_layer:
		points=node.polygon
	elif node is CollisionShape2D and not node.disabled and node.shape and node.get_parent() is StaticBody2D and node.get_parent().collision_layer:
		var rect: Rect2=node.shape.get_rect(); points=PackedVector2Array([rect.position,rect.end,Vector2(rect.position.x,rect.end.y),Vector2(rect.end.x,rect.position.y)])
	if not points.is_empty():
		var bounds:=Rect2(); var first: bool=true
		for point in points:
			var world: Vector2=node.global_transform*point
			var metric: Vector2=Plan.metric([world.x,world.y,0],"2d")
			bounds=Rect2(metric,Vector2.ZERO) if first else bounds.expand(metric); first=false
		obstacles.append(bounds)
	for child in node.get_children(): collect_2d_obstacles(child)

func parking(data: Dictionary,instances: Dictionary,visible_only: bool) -> Dictionary:
	var result: Dictionary={}
	for item in data["objects"]:
		if item.get("traffic_parking",false)!=true or not instances.has(item["uid"]): continue
		var node: Node=instances[item["uid"]]
		if visible_only and not node.visible: continue
		var name: String=item.get("name",item["asset"])
		if not Plan.parking_surface(item,library): plan["notices"].append(name+": parking requires a ground surface."); continue
		var point: Vector2=Plan.metric(item["position"],dimension)
		point+=Roads.center_offset(library,item["asset"],item["direction"],item["scale"],dimension)*(2 if dimension=="2d" else 1)
		var ground: Dictionary=surface(point)
		if absf(item["position"][2 if dimension=="2d" else 1]-(ground["height"] if dimension=="3d" else 0))>.25 or ground["normal"].y<.996 or not item.get("tilt",[0,0]) in [[0,0],[0.0,0.0]]:
			plan["notices"].append(name+": parking requires a level ground approach supported by the local terrain."); continue
		var water: Variant=preload("res://scripts/builder/terrain_plan.gd").water_level(data,point,terrain_heights,terrain_waters)
		if water!=null and water-ground["height"]>.26: plan["notices"].append(name+": parking space is flooded."); continue
		var best: float=INF; var approach: Dictionary={}
		for edge in plan["edges"].values():
			var section: Dictionary=plan["sections"][edge["to"]]
			if section["neighbors"].size()!=2 or section["crossing"]: continue
			var first: Vector2i=plan["sections"][section["neighbors"][0]]["cell"]-section["cell"]
			var second: Vector2i=plan["sections"][section["neighbors"][1]]["cell"]-section["cell"]
			if first+second!=Vector2i.ZERO: continue
			var axis: Vector2=edge["axis"]; var right:=Vector2(-axis.y,axis.x)
			var relative: Vector2=point-Plan.center(section["cell"],dimension)
			if relative.dot(right)<section["width"]*.5+1 or relative.dot(right)>12 or absf(relative.dot(axis))>3: continue
			var distance: float=relative.length()
			if distance>=best: continue
			best=distance; approach={"uid":item["uid"],"point":point,"from":edge["from"],"section":edge["to"],"heading":axis}
		if approach.is_empty(): plan["notices"].append(name+": place beside a straight road, away from crossings and junctions."); continue
		var size: Vector2=bay_size(item,approach["heading"])
		approach["length"]=size.x
		approach["width"]=size.y
		if obstacles.any(func(box: Rect2):return box.grow(1).has_point(point)) or result.values().any(func(bay: Dictionary):return bay["point"].distance_to(point)<3):
			plan["notices"].append(name+": parking space is obstructed or overlaps another bay."); continue
		result[item["uid"]]=approach
	return result
func bay_size(item: Dictionary,axis: Vector2) -> Vector2:
	var id: String=item["asset"]
	var size: float=item["scale"]
	var footprint: Vector2
	var local_x:=Vector2.RIGHT
	if id.begins_with("3d:"):
		var bounds: Vector3=Roads.bounds_for(library,id).size
		footprint=Vector2(bounds.x,bounds.z)*size
		local_x=Vector2.RIGHT.rotated(-deg_to_rad(float(item["direction"])))
	else:
		var views: Dictionary=library.assets[id]["data"].get("directions",{})
		var view: Dictionary=views.get(item["direction"],views.get("SE",{}))
		var cells: Array=view.get("footprint",[1,1])
		footprint=Vector2(cells[0],cells[1])*size*(2 if dimension=="2d" else 1)
		if library.is_ground_tile(id):
			local_x=Vector2.RIGHT.rotated(deg_to_rad(preload("res://scripts/iso_tile_rotation.gd").degrees(item["direction"])))
		else:
			local_x=Vector2.RIGHT.rotated(deg_to_rad(item.get("angle",0)))
	var local_y:=Vector2(-local_x.y,local_x.x)
	return Vector2(absf(axis.dot(local_x))*footprint.x+absf(axis.dot(local_y))*footprint.y,
		absf(axis.cross(local_x))*footprint.x+absf(axis.cross(local_y))*footprint.y)

func surface(point: Vector2) -> Dictionary:
	var terrain=preload("res://scripts/builder/terrain_plan.gd")
	return terrain.sample(terrain_data,point,terrain_heights) if terrain.settings(terrain_data)["enabled"] else {"height":0.0,"normal":Vector3.UP,"inside":false}

func spawn() -> void:
	var edges: Array=plan["edges"].keys(); edges.sort()
	if edges.is_empty(): return
	if fleet_pool.is_empty() and plan["settings"]["population"]>0:
		plan["notices"].append("Traffic has no available fleet member with a positive weight.")
		return
	var offset: int=random.randi_range(0,edges.size()-1)
	for index in edges.size():
		if vehicles.size()>=plan["settings"]["population"]: break
		var edge: Dictionary=plan["edges"][edges[(index+offset)%edges.size()]]
		var id: String="traffic_"+str(vehicles.size())
		var profile: Dictionary=Fleet.choose(fleet_pool,plan["settings"]["seed"],id,func(candidate: Dictionary) -> bool:
			if not Fleet.fit_edge(plan,edge["from"],edge["to"],candidate): return false
			return Plan.exits(plan,edge["to"]).any(func(next: String): return Fleet.fit_turn(plan,edge["from"],edge["to"],next,candidate))
		)
		if profile.is_empty(): continue
		var point: Vector2=edge["points"][0]
		var fields: Dictionary=Fleet.vehicle_fields(profile)
		var heading: Vector2=edge["axis"]
		if vehicles.any(func(v: Dictionary):return Fleet.overlaps(fields,point,heading,v,.35)): continue
		if obstacles.any(func(box: Rect2):return Fleet.intersects_obstacle(fields,point,heading,box)): continue
		var actor: Node=Instance.make(library,profile["asset"],dimension); actor.name=id; actor.set_meta("traffic_id",id)
		container.add_child(actor); disable_collisions(actor)
		var vehicle: Dictionary={"id":id,"actor":actor,"from":edge["from"],"to":edge["to"],"next":"","phase":"edge","path":edge["points"],"distance":0.0,"point":point,"heading":heading,"speed":0.0,"status":"Driving","bay":"","timer":0.0,"visits":[],"sections":[],"stops":0,"blocked":0.0}
		vehicle.merge(fields)
		vehicles.append(vehicle); pose(vehicle)
	if vehicles.size()<plan["settings"]["population"]: plan["notices"].append("Spawned %d of %d vehicles. Check road width, turns and lane clearance." % [vehicles.size(),plan["settings"]["population"]])

func disable_collisions(node: Node) -> void:
	if node is CollisionObject2D or node is CollisionObject3D: node.collision_layer=0; node.collision_mask=0
	for child in node.get_children(): disable_collisions(child)

func pose(vehicle: Dictionary) -> void:
	var size: float=vehicle.get("size",CAR_SIZE)
	var heading: Vector2=vehicle["heading"]
	var direction: String
	if vehicle.has("fleet_profile"): direction=Fleet.direction(vehicle["fleet_profile"],heading)
	elif dimension=="2d": direction=["NE","SE","SW","NW"][posmod(roundi(rad_to_deg(atan2(heading.x,heading.y))/90),4)]
	else: direction=str(rad_to_deg(atan2(heading.x,heading.y)))
	var actor: Node=vehicle["actor"]
	Instance.orient(actor,direction)
	var point: Vector2=vehicle["point"]-Roads.center_offset(library,vehicle["asset"],direction,size,dimension)*(2 if dimension=="2d" else 1)
	var elevation: float=.12
	if dimension=="3d":
		var terrain=preload("res://scripts/builder/terrain_plan.gd"); var sculpted: bool=terrain.settings(terrain_data)["enabled"]; var sample: Dictionary=terrain.sample(terrain_data,vehicle["point"],terrain_heights) if sculpted else {"height":0.0,"normal":Vector3.UP}
		var normal: Vector3=sample["normal"]; var forward:=Vector3(heading.x,0,heading.y); var right: Vector3=normal.cross(forward).normalized(); forward=right.cross(normal).normalized(); actor.basis=Basis(right,normal,forward)
		var bottom: float=Roads.bounds_for(library,vehicle["asset"]).position.y*size
		elevation+=sample["height"]-normal.y*bottom
		point-=Vector2(normal.x,normal.z)*bottom
	var position: Array=Plan.world(point,dimension,elevation)
	actor.position=Vector2(position[0],position[1]) if dimension=="2d" else Vector3(position[0],position[1],position[2])
	actor.scale=Vector2.ONE*size if dimension=="2d" else Vector3.ONE*size

func pedestrian_points(world: Node=null) -> Array[Vector2]:
	var result: Array[Vector2]=[]
	if not is_instance_valid(world):
		if not is_instance_valid(container): return result
		world=container.get_parent()
	var actors: Array[Node]=pedestrians.duplicate()
	if is_instance_valid(transit): actors.append_array(transit.pedestrian_actors())
	if is_instance_valid(services):
		for worker in services.worker_actors():
			if worker not in actors: actors.append(worker)
	for actor in actors:
		if not is_instance_valid(actor) or not actor.visible or actor.has_meta("cycling_rider"): continue
		var position: Variant=world.to_local(actor.global_position)
		var point: Vector2=Plan.metric([position.x,position.y,0] if dimension=="2d" else [position.x,position.y,position.z],dimension)
		if dimension=="3d" and absf(position.y-surface(point)["height"])>.8: continue
		result.append(point)
	return result

func gate_time(section: String, fallback: float) -> float:
	if plan.get("controls",{}).get("sections",{}).get(section,{}).has("signal") or gates.holds.has(section):
		return junction_time
	return elapsed if not paused and plan.get("settings",{}).get("enabled",false) else fallback

func pedestrian_can_enter(from: Vector2,to: Vector2,network: Dictionary={},time: float=-1) -> bool:
	var layout: Dictionary=plan if network.is_empty() else network
	var controls: Dictionary=layout.get("controls",{}).get("sections",{})
	if controls.is_empty(): return true
	var offset: Vector2=Plan.center(Vector2i.ZERO,layout["mode"])
	var cell:=Vector2i(((to-offset)/8).round())
	var key: String=Roads.key(cell)
	if not controls.get(key,{}).has("signal"): return true
	var center: Vector2=Plan.center(cell,layout["mode"])
	if not Plan.Signals.pedestrian_in_section(to,center) or Plan.Signals.pedestrian_in_section(from,center): return true
	return not gates.owners.has(key) and gates.phase(layout,key,junction_time if time<0 else time)=="walk"

func step(delta: float) -> void:
	if not active or plan.is_empty(): return
	if paused or not plan["settings"]["enabled"]:
		junction_time+=minf(delta,.25)
		signal_views.draw(plan,gates,junction_time)
		return
	# Bounded substeps keep stop lines and following checks effective after a stall.
	var remaining: float=minf(delta,.25)
	route_queue.step()
	while remaining>.00001:
		var tick: float=minf(remaining,1.0/30); remaining-=tick; advance(tick)
	signal_views.draw(plan,gates,junction_time)

func advance(delta: float) -> void:
	elapsed+=delta
	junction_time+=delta
	var people: Array[Vector2]=pedestrian_points()
	for vehicle in vehicles:
		if vehicle["phase"]=="blocked": continue
		accept_route(vehicle)
		if vehicle["phase"]=="parked":
			vehicle["timer"]-=delta
			if vehicle["timer"]>0: continue
			var reverse: PackedVector2Array=vehicle["path"].duplicate(); reverse.reverse()
			set_path(vehicle,reverse,"parking_out")
		var length: float=Plan.length(vehicle["path"])
		if vehicle["distance"]>=length-.00001:
			if not finish_segment(vehicle,people): vehicle["speed"]=0; continue
		var profile: Dictionary=vehicle.get("fleet_profile",{})
		var speed: float=minf(plan["settings"]["speed"],profile.get("speed",8))
		if vehicle["phase"].begins_with("parking"): speed=minf(speed,1.5)
		var acceleration: float=profile.get("acceleration",3)
		var distance: float=minf(Plan.length(vehicle["path"]),vehicle["distance"]+move_toward(vehicle["speed"],speed,acceleration*delta)*delta)
		var sample: Dictionary=Plan.sample(vehicle["path"],distance)
		var obstruction: String=obstructed(vehicle,sample["point"],sample["heading"],people)
		if not obstruction.is_empty(): vehicle["speed"]=0; vehicle["status"]=obstruction; continue
		vehicle["speed"]=move_toward(vehicle["speed"],speed,acceleration*delta)
		vehicle["distance"]=distance; vehicle["point"]=sample["point"]; vehicle["heading"]=sample["heading"]
		vehicle["status"]="Driving" if not vehicle["phase"].begins_with("parking") else "Entering parking" if vehicle["phase"]=="parking_in" else "Leaving parking"
		pose(vehicle)

func obstructed(vehicle: Dictionary,point: Vector2,heading: Vector2,people: Array[Vector2]) -> String:
	if vehicle.has("half_length"):
		if people.any(func(p: Vector2):return absf((p-point).dot(heading))<vehicle["half_length"]+.8 and absf((p-point).cross(heading))<vehicle.get("half_width",.8)+.5): return "Yielding to pedestrian"
	elif people.any(func(p: Vector2):return p.distance_to(point)<1.6): return "Yielding to pedestrian"
	if vehicle.has("fleet_profile"):
		if obstacles.any(func(box: Rect2):return Fleet.intersects_obstacle(vehicle,point,heading,box)): return "Road obstructed"
	elif obstacles.any(func(box: Rect2):return box.grow(.65).has_point(point)): return "Road obstructed"
	var shared: Array[Dictionary]=[]
	if is_instance_valid(transit): shared=transit.vehicle_states()
	if is_instance_valid(driving): shared.append_array(driving.vehicle_states())
	for other in vehicles+external_vehicles+shared:
		if other==vehicle: continue
		var relative: Vector2=other["point"]-point
		if other.has("half_length") or vehicle.has("half_length"):
			if Fleet.overlaps(vehicle,point,heading,other,.18):
				return "Waiting for bus clearance" if str(other.get("id","")).begins_with("bus_") else "Waiting for vehicle clearance"
			if relative.dot(heading)>0 and relative.dot(heading)<vehicle.get("half_length",1.3)+other.get("half_length",1.3)+.45 and absf(relative.cross(heading))<vehicle.get("half_width",.55)+other.get("half_width",.55):
				return "Following traffic"
			continue
		if relative.length()<.9: return "Waiting for vehicle clearance"
		if relative.dot(heading)>0 and relative.dot(heading)<2.8 and absf(relative.cross(heading))<.9: return "Following traffic"
	return ""

func finish_segment(vehicle: Dictionary,people: Array[Vector2]) -> bool:
	match vehicle["phase"]:
		"edge":
			if vehicle.has("route_request"):
				vehicle["status"]="Finding a safe road route"
				return false
			var occupied: bool=Plan.crossing_occupied(plan,vehicle["to"],people)
			var permission: Dictionary=gates.request(plan,vehicle["id"],vehicle["to"],gate_time(vehicle["to"],elapsed),occupied,vehicle["from"])
			if not permission["allowed"]:
				if vehicle["status"]!=permission["reason"]: vehicle["stops"]+=1
				vehicle["status"]=permission["reason"]; return false
			if vehicle["bay"].is_empty() and not vehicle.get("leaving_parking",false): choose_bay(vehicle)
			if not vehicle["bay"].is_empty() and bays[vehicle["bay"]]["section"]==vehicle["to"] and bays[vehicle["bay"]]["from"]==vehicle["from"]:
				var bay: Dictionary=bays[vehicle["bay"]]
				var a: Vector2=vehicle["point"]; var b: Vector2=bay["point"]; var axis: Vector2=vehicle["heading"]
				var points:=PackedVector2Array()
				for index in 25:
					var t: float=index/24.0; var u: float=1-t
					points.append(a*u*u*u+(a+axis*2)*3*u*u*t+(b-axis*2)*3*u*t*t+b*t*t*t)
				set_path(vehicle,points,"parking_in"); return true
			var next: String=journey_next(vehicle)
			if next.is_empty():
				hold_journey(vehicle,"No reachable road continuation. Waiting for a road edit.")
				return false
			vehicle["next"]=next
			vehicle.erase("leaving_parking")
			set_path(vehicle,Plan.turn(plan,vehicle["from"],vehicle["to"],next),"turn")
		"turn":
			gates.release(vehicle["id"],vehicle["to"])
			vehicle["sections"].append(vehicle["to"])
			if vehicle["sections"].size()>64: vehicle["sections"].pop_front()
			vehicle["from"]=vehicle["to"]; vehicle["to"]=vehicle["next"]
			set_path(vehicle,plan["edges"][Plan.edge_id(vehicle["from"],vehicle["to"])]["points"],"edge")
		"parking_in":
			vehicle["phase"]="parked"; vehicle["status"]="Parked"; vehicle["speed"]=0; vehicle["timer"]=plan["settings"]["parking_seconds"]
			vehicle["visits"].append(vehicle["bay"])
			if vehicle["visits"].size()>32: vehicle["visits"].pop_front()
			gates.release(vehicle["id"]); return false
		"parking_out":
			release_bay(vehicle)
			var edge: PackedVector2Array=lane_path(vehicle["from"],vehicle["to"])
			if not recover_to_stop_line(vehicle,edge):
				hold_journey(vehicle,"Parking exit lost its connected lane.")
				return false
			vehicle["leaving_parking"]=true
			return finish_segment(vehicle,people)
	return true

func set_path(vehicle: Dictionary,path: PackedVector2Array,phase: String) -> void:
	vehicle["path"]=path; vehicle["distance"]=0.0; vehicle["phase"]=phase

func choose_bay(vehicle: Dictionary) -> void:
	var candidates: Array=bays.keys(); candidates.sort()
	for id in candidates:
		if bay_owners.has(id) or vehicle.get("failed_bay","")==id: continue
		var bay: Dictionary=bays[id]
		var profile: Dictionary=vehicle.get("fleet_profile",{})
		if not Fleet.fit_bay(bay,profile): continue
		var route: PackedStringArray=Plan.route(plan,vehicle["to"],bay["from"],profile,vehicle["from"])
		if route.is_empty(): continue
		var prior: String=route[-2] if route.size()>1 else vehicle["from"]
		if not Fleet.fit_turn(plan,prior,bay["from"],bay["section"],profile): continue
		bay_owners[id]=vehicle["id"]; vehicle["bay"]=id; return

func journey_next(vehicle: Dictionary) -> String:
	var from: String=vehicle["from"]
	var at: String=vehicle["to"]
	var profile: Dictionary=vehicle.get("fleet_profile",{})
	var suffix: PackedStringArray=vehicle.get("route_suffix",PackedStringArray())
	if suffix.size()>1 and suffix[0]==at and route_queue.compatible(from,at,suffix[1],profile):
		var next: String=suffix[1]
		suffix.remove_at(0)
		vehicle["route_suffix"]=suffix
		return next
	vehicle.erase("route_suffix")
	if not vehicle["bay"].is_empty():
		var bay: Dictionary=bays[vehicle["bay"]]
		var route: PackedStringArray=Plan.route(plan,at,bay["from"],profile,from)
		var next: String=bay["section"] if at==bay["from"] else route[1] if route.size()>1 else ""
		if not next.is_empty() and route_queue.compatible(from,at,next,profile): return next
		release_bay(vehicle)
	var options: Array=Plan.exits(plan,at).filter(func(next: String)->bool:return route_queue.compatible(from,at,next,profile))
	if options.size()>1: options.erase(from)
	return options[random.randi_range(0,options.size()-1)] if not options.is_empty() else ""

func release_bay(vehicle: Dictionary) -> void:
	if bay_owners.get(vehicle["bay"],"")==vehicle["id"]: bay_owners.erase(vehicle["bay"])
	vehicle["bay"]=""

func _physics_process(delta: float) -> void: step(delta)

func summary() -> String:
	if plan.is_empty() or not plan["settings"]["enabled"]: return "Traffic simulation is off."
	var parked: int=0; var waiting: int=0
	for vehicle in vehicles:
		if vehicle["phase"]=="parked": parked+=1
		elif vehicle["speed"]==0: waiting+=1
	return "%d vehicles · %d parked · %d waiting · %d usable parking spaces" % [vehicles.size(),parked,waiting,bays.size()]

func clear() -> void:
	for vehicle in vehicles: gates.release(vehicle["id"])
	route_queue.clear_requests()
	vehicles.clear(); bays.clear(); bay_owners.clear(); obstacles.clear(); elapsed=0
	if is_instance_valid(container): container.free()
	container=null

func restart_vehicles() -> void:
	clear()
	signature=0

func reset() -> void:
	clear()
	gates.clear()
	signal_views.clear()
	junction_time=0
	plan={}
	base_plan={}
	road_inputs.clear()
	signature=0
func _exit_tree() -> void:
	signal_views.clear()
	clear()
