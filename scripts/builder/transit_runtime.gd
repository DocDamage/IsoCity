extends Node
const Plan=preload("res://scripts/builder/transit_plan.gd")
const Traffic=preload("res://scripts/builder/traffic_plan.gd")
const Instance=preload("res://scripts/builder/asset_instance.gd")
const School=preload("res://scripts/builder/school_plan.gd")
const Fleet=preload("res://scripts/builder/fleet_plan.gd")
var bus_pool: Array[Dictionary]=[]
var school_pool: Array[Dictionary]=[]
var route_queue=preload("res://scripts/builder/traffic_route_queue.gd").new()
var passengers=preload("res://scripts/builder/transit_passengers.gd").new()
var helper=preload("res://scripts/builder/traffic_runtime.gd").new()
var buses: Dictionary={}
var walkers: Dictionary={}
var traffic: Node
var services: Node
var library: RefCounted
var dimension: String="2d"
var active: bool=true
var paused: bool=false
var elapsed: float=0
var auto_time: float=0
var signature: int=0
var random:=RandomNumberGenerator.new()
var notice: String=""
var show_hud: bool=false
var panel: PanelContainer
var hud_status: Label
var pause_button: Button
var hud_elapsed: float=0
var text_scale: float=1
func set_text_scale(value: float) -> void:
	if is_equal_approx(value,text_scale): return
	text_scale=value
	for entry in buses.values():
		if dimension=="2d": entry["label"].add_theme_font_size_override("font_size",roundi(10*value))
		else: entry["label"].font_size=roundi(28*value)
func _ready() -> void:
	helper.render_signals=false
	add_child(helper); helper.active=false; helper.set_physics_process(false)
func build_hud() -> void:
	var layer:=CanvasLayer.new(); layer.layer=19; add_child(layer)
	panel=PanelContainer.new(); layer.add_child(panel)
	var box:=VBoxContainer.new(); panel.add_child(box)
	hud_status=Label.new(); hud_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; box.add_child(hud_status)
	pause_button=Button.new(); box.add_child(pause_button); pause_button.pressed.connect(func(): paused=not paused; update_hud())
	var send:=Button.new(); send.text="Send a passenger"; box.add_child(send); send.pressed.connect(automatic_request)
	update_hud()
func update_hud() -> void:
	if not is_instance_valid(panel): return
	panel.visible=show_hud and active and not passengers.plan.is_empty() and passengers.plan["settings"]["enabled"]
	panel.size.x=minf(280,get_viewport().get_visible_rect().size.x-40); panel.custom_minimum_size.x=panel.size.x; panel.position=Vector2((get_viewport().get_visible_rect().size.x-panel.size.x)*.5,80)
	hud_status.text=summary(); pause_button.text="Resume buses" if paused else "Pause buses"
	if not passengers.plan.get("notices",[]).is_empty(): hud_status.text+="\n"+str(passengers.plan["notices"][0])
func _process(delta: float) -> void:
	if not show_hud: return
	if not is_instance_valid(panel): build_hud()
	hud_elapsed+=delta
	if hud_elapsed>=.4: hud_elapsed=0; update_hud()
func configure(data: Dictionary,assets: RefCounted,instances: Dictionary,parent: Node,traffic_value: Node=null,service_value: Node=null,visible_only: bool=true) -> void:
	traffic=traffic_value; services=service_value
	var stamp: int=hash([data.get("transit",{}),data.get("fleet",{}),data.get("transit_lines",[]),data["objects"],data.get("roads",[]),data.get("layers",{}),data.get("terrain",{}),data.get("terrain_vertices",[]),data.get("water_cells",[]),visible_only])
	if signature==stamp and not passengers.plan.is_empty(): return
	if is_instance_valid(helper.container) and helper.container.get_parent()!=parent: reset()
	library=assets; dimension=data["mode"]
	var settings: Dictionary=Plan.settings(data)
	var previous: Dictionary=passengers.plan.get("settings",{})
	if not settings["enabled"]:
		reset(); passengers.configure(Plan.build(data,library)); signature=stamp; return
	if passengers.plan.is_empty() or not passengers.plan["settings"]["enabled"]:
		random.seed=settings["seed"]; auto_time=settings["interval"]
	elif previous.get("seed")!=settings["seed"]: random.seed=settings["seed"]
	if previous.get("interval")!=settings["interval"] or settings["automatic"] and not previous.get("automatic",false): auto_time=settings["interval"]
	var fleet: Dictionary=data.duplicate(false); fleet["traffic"]={"enabled":true,"population":0}
	helper.configure(fleet,library,instances,parent,visible_only); helper.container.name="TransitActors"
	var geometry: Dictionary={}
	for item in data["objects"]:
		if not Plan.is_stop(item) or not instances.has(item["uid"]): continue
		var boxes: Array[Rect2]=[]
		if dimension=="2d":
			var saved: Array[Rect2]=helper.obstacles; var empty: Array[Rect2]=[]; helper.obstacles=empty; helper.collect_2d_obstacles(instances[item["uid"]]); boxes=helper.obstacles; helper.obstacles=saved
		else:
			var collision=preload("res://scripts/builder/citizen_runtime.gd").new(); collision.terrain_data=data; collision.collect_obstacles(instances[item["uid"]]); boxes=collision.obstacles; collision.free()
		if not boxes.is_empty():
			var bounds: Rect2=boxes[0]
			for box in boxes: bounds=bounds.merge(box)
			geometry[item["uid"]]=bounds
	bus_pool=Fleet.pool(data,"transit",library)
	school_pool.clear()
	var school_bus: String=School.required_bus(data)
	if not school_bus.is_empty():
		var school_data: Dictionary={"mode":dimension,"fleet":{"transit":[{"asset":school_bus,"weight":100}]}}
		school_pool=Fleet.pool(school_data,"transit",library)
	var network: Dictionary=Plan.build(data,library,geometry)
	if bus_pool.is_empty() and school_pool.is_empty():
		network["notices"].append("Transit has no available bus with a positive fleet weight.")
	var anchors: Dictionary={}
	for uid in network["stops"]:
		anchors[uid]=Plan.stop_layout(network["stops"][uid])
	var changed: bool=route_queue.configure(network["network"],helper.obstacles,anchors)
	passengers.configure(network,true)
	signature=stamp
	for entry in buses.values():
		var uid: String=passengers.vehicles[entry["vehicle"]["id"]]["line"]
		var line: Dictionary=network["lines"].get(uid,{})
		var stops: Array=network["route_stops"].get(uid,[])
		if changed or line!=entry.get("configured_line",{}) or stops!=entry.get("route_stops",[]) or entry.get("resume_phase","")=="moving" or absf(helper.surface(entry["vehicle"]["point"])["height"]-entry.get("road_height",0.0))>.4:
			entry["configured_line"]=line
			entry["route_stops"]=stops
			refresh_bus(entry,line)
		if not line.is_empty():
			var bus: Dictionary=passengers.vehicles[entry["vehicle"]["id"]]
			bus["retiring"]=line["school_bus"]!=entry["school_bus"]
			entry["label"].text=line["name"].left(40)
			entry["label"].modulate=Color(line["color"])
	for walker in walkers.values():
		if walker["job"]["state"]=="cancelled": walker["actor"].visible=false
func vehicle_states() -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for entry in buses.values(): result.append(entry["vehicle"])
	return result
func pedestrian_actors() -> Array[Node]:
	var result: Array[Node]=[]
	for walker in walkers.values():
		if is_instance_valid(walker["actor"]) and walker["actor"].visible: result.append(walker["actor"])
	return result
func refresh_links() -> void:
	helper.driving=traffic.driving if is_instance_valid(traffic) else null
	helper.external_vehicles.assign(vehicle_states()); helper.pedestrians.clear()
	if is_instance_valid(traffic):
		helper.external_vehicles.append_array(traffic.vehicles); helper.pedestrians.assign(traffic.pedestrians)
	if is_instance_valid(services):
		helper.external_vehicles.append_array(services.vehicle_states())
		for actor in services.worker_actors():
			if not actor in helper.pedestrians: helper.pedestrians.append(actor)
	for actor in pedestrian_actors():
		if not actor in helper.pedestrians: helper.pedestrians.append(actor)
func spawn_buses() -> void:
	for line in passengers.plan["lines"].values():
		for slot in line["fleet"]:
			var id: String="bus_"+line["uid"].sha256_text().substr(0,24)+"_"+str(slot)
			if buses.has(id) or elapsed<line["offset"]+slot*line["headway"]: continue
			var stop: Dictionary=passengers.plan["stops"][line["stops"][0]]
			var point: Vector2=stop["dock"]
			var network: Dictionary=passengers.plan["network"]
			var profile: Dictionary=Fleet.choose(school_pool if line["school_bus"] else bus_pool,passengers.plan["settings"]["seed"],id,func(candidate: Dictionary) -> bool:
				return line["legs"].all(func(leg: Dictionary): return Fleet.fit_route(network,leg["sections"],candidate))
			)
			if profile.is_empty(): continue
			var fields: Dictionary=Fleet.vehicle_fields(profile)
			var heading: Vector2=stop["axis"]
			if helper.external_vehicles.any(func(vehicle: Dictionary):return Fleet.overlaps(fields,point,heading,vehicle,.25)) or not vehicle_clear(point,heading,fields): continue
			if passengers.stop_owners.has(stop["uid"]): continue
			if not passengers.register_vehicle(id,line["uid"],slot,profile["asset"])["ok"]: continue
			var actor: Node=Instance.make(library,profile["asset"],dimension); actor.name=id.validate_node_name(); helper.container.add_child(actor); helper.disable_collisions(actor); actor.set_meta("transit_bus",id)
			var vehicle: Dictionary={"id":id,"actor":actor,"point":point,"heading":heading,"speed":0.0}
			vehicle.merge(fields)
			var label: Node=Label.new() if dimension=="2d" else Label3D.new(); helper.container.add_child(label); label.text=line["name"].left(40); label.modulate=Color(line["color"])
			if dimension=="2d": label.custom_minimum_size=Vector2(100,18); label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; label.clip_text=true; label.z_index=100; label.mouse_filter=Control.MOUSE_FILTER_IGNORE; label.add_theme_font_size_override("font_size",roundi(10*text_scale)); label.add_theme_color_override("font_outline_color",Color.BLACK); label.add_theme_constant_override("outline_size",3)
			else: label.billboard=BaseMaterial3D.BILLBOARD_ENABLED; label.font_size=roundi(28*text_scale); label.pixel_size=.015; label.outline_size=4
			buses[id]={"vehicle":vehicle,"label":label,"school_bus":line["school_bus"],"configured_line":line,"route_stops":line["stops"],"segments":[],"segment":0,
				"distance":0.0,"gate_open":false,"stop_layout":Plan.stop_layout(stop),"status":"Boarding at "+stop["name"]}
			pose_bus(buses[id]); passengers.dock(id,stop["uid"],point,elapsed); helper.external_vehicles.append(vehicle)
func pose_bus(entry: Dictionary) -> void:
	var vehicle: Dictionary=entry["vehicle"]; helper.pose(vehicle)
	var raw: Array=Traffic.world(vehicle["point"],dimension)
	entry["road_height"]=0.0
	if preload("res://scripts/builder/terrain_plan.gd").settings(helper.terrain_data)["enabled"]:
		var height: float=preload("res://scripts/builder/terrain_plan.gd").sample(helper.terrain_data,vehicle["point"],helper.terrain_heights)["height"]
		entry["road_height"]=height
		if dimension=="2d": raw[1]-=height*8
		else: raw[1]=height
	entry["label"].position=Vector2(raw[0]-50,raw[1]-45) if dimension=="2d" else Vector3(raw[0],raw[1]+3.5,raw[2])
func vehicle_clear(point: Vector2,heading: Vector2,vehicle: Dictionary={}) -> bool:
	var fields: Dictionary=vehicle
	if fields.is_empty() and not bus_pool.is_empty():
		fields=Fleet.vehicle_fields(bus_pool[0])
	return not helper.obstacles.any(func(box: Rect2):return Fleet.intersects_obstacle(fields,point,heading,box,.1))

func gate_keeper() -> RefCounted:
	return traffic.gates if is_instance_valid(traffic) else helper.gates
func release_gate(entry: Dictionary) -> void: gate_keeper().release(entry["vehicle"]["id"])
func hold_bus(entry: Dictionary,bus: Dictionary,reason: String) -> void:
	if bus["phase"]!="blocked": entry["resume_phase"]=bus["phase"]
	bus["phase"]="blocked"
	entry["status"]=reason
	entry["vehicle"]["speed"]=0
	entry["gate_open"]=false
	release_gate(entry)
	if passengers.stop_owners.get(bus["stop"])==bus["id"]: passengers.stop_owners.erase(bus["stop"])

func drive_profile(entry: Dictionary) -> Dictionary:
	var profile: Dictionary=entry["vehicle"]["fleet_profile"].duplicate()
	profile["minimum_road_width"]=3.6
	profile["terminal_uturn_only"]=true
	return profile

func safe_piece(entry: Dictionary,piece: Dictionary,distance: float) -> bool:
	var lane: Array=piece["lane"]
	var graph: Dictionary=passengers.plan["network"]
	var kind: String=piece["kind"]
	if kind=="turn":
		if not Traffic.Fleet.fit_turn(graph,lane[0],lane[1],lane[2],entry["vehicle"]["fleet_profile"]): return false
		if graph["sections"][lane[0]]["width"]<3.6 or graph["sections"][lane[1]]["width"]<3.6 or graph["sections"][lane[2]]["width"]<3.6: return false
		if Traffic.turn(graph,lane[0],lane[1],lane[2])!=piece["points"]: return false
	else:
		var edge: Dictionary=graph["edges"].get(Traffic.edge_id(lane[0],lane[1]),{})
		if edge.is_empty() or graph["sections"][lane[0]]["width"]<3.6 or graph["sections"][lane[1]]["width"]<3.6: return false
		var path: PackedVector2Array=piece["points"]
		if kind=="edge" and edge["points"]!=path: return false
		if kind=="departure" and edge["points"][0]!=path[-1]: return false
		if kind=="arrival" and edge["points"][-1]!=path[0]: return false
	return route_queue.path_clear(piece["points"],entry["vehicle"],distance)

func refresh_bus(entry: Dictionary,line: Dictionary) -> void:
	var vehicle: Dictionary=entry["vehicle"]
	var bus: Dictionary=passengers.vehicles[vehicle["id"]]
	var phase: String=entry.get("resume_phase",bus["phase"])
	if phase=="blocked": return
	route_queue.cancel(bus["id"])
	entry.erase("route_request")
	entry.erase("route_boundary")
	var stops: Dictionary=passengers.plan["stops"]
	if phase=="dwell":
		var stop: Dictionary=stops.get(bus["stop"],{})
		if line.is_empty() or not bus["stop"] in line["stops"] or stop.is_empty() or Plan.stop_layout(stop)!=entry["stop_layout"]:
			hold_bus(entry,bus,"Bus platform changed. Waiting for a safe departure.")
		elif not passengers.stop_owners.has(bus["stop"]) or passengers.stop_owners[bus["stop"]]==bus["id"]:
			passengers.stop_owners[bus["stop"]]=bus["id"]
			bus["phase"]="dwell"
			entry.erase("resume_phase")
		return
	if absf(helper.surface(vehicle["point"])["height"]-entry.get("road_height",0.0))>.4:
		hold_bus(entry,bus,"The bus lane changed elevation. Waiting for a supported road connection.")
		return
	var pieces: Array=entry["segments"]
	var index: int=entry["segment"]
	var destination: Dictionary=stops.get(bus["next"],{})
	var next_stop_available: bool=not destination.is_empty() and bus["next"] in passengers.plan["route_stops"].get(bus["line"],[])
	if index>=pieces.size() and next_stop_available and vehicle["point"].distance_to(destination["dock"])<.001:
		bus["phase"]="moving"
		entry.erase("resume_phase")
		return
	var anchor_index: int=index
	var active_safe: bool=index<pieces.size() and safe_piece(entry,pieces[index],entry["distance"])
	if not active_safe:
		anchor_index=index-1
		if entry["distance"]>.001 or anchor_index<0 or vehicle["point"].distance_to(pieces[anchor_index]["points"][-1])>.001 or not safe_piece(entry,pieces[anchor_index],pieces[anchor_index]["length"]):
			hold_bus(entry,bus,"Current bus lane changed. Waiting for a safe road connection.")
			return
	var anchor: Dictionary=pieces[anchor_index]
	if next_stop_available and anchor["kind"]=="arrival" and anchor["points"][-1].distance_to(destination["dock"])<.001:
		bus["phase"]="moving"
		entry.erase("resume_phase")
		return
	if next_stop_available and active_safe and pieces[-1]["points"][-1].distance_to(destination["dock"])<.001 and pieces.slice(index+1).all(func(piece: Dictionary)->bool:return safe_piece(entry,piece,0)):
		bus["phase"]="moving"
		entry.erase("resume_phase")
		return
	entry["route_boundary"]=anchor_index+1
	bus["phase"]="moving"
	entry.erase("resume_phase")
	if not active_safe:
		entry["gate_open"]=false
		release_gate(entry)
	if not next_stop_available or anchor["kind"]=="arrival": return
	var graph: Dictionary=passengers.plan["network"]
	var lane: Array=anchor["lane"]
	var from: String=lane[-2]
	var at: String=lane[-1]
	var bridge: Array=[]
	if anchor["kind"]!="edge":
		var edge: Dictionary=graph["edges"].get(Traffic.edge_id(from,at),{})
		if edge.is_empty() or edge["points"][0].distance_to(anchor["points"][-1])>.001: return
		var piece: Dictionary=Plan.piece(edge["points"],[from,at],"edge")
		if not safe_piece(entry,piece,0): return
		bridge.append(piece)
	var goal: String=destination["section"]
	var behind: String=Traffic.Roads.key(graph["sections"][goal]["cell"]-Vector2i(destination["axis"]))
	var id: int=route_queue.request(bus["id"],at,from,{goal:[behind]},drive_profile(entry))
	if id>0: entry["route_request"]={"id":id,"incoming":from,"bridge":bridge,"stop":destination}

func accept_bus_route(entry: Dictionary,bus: Dictionary) -> void:
	if not entry.has("route_request"): return
	var request: Dictionary=entry["route_request"]
	var result: Dictionary=route_queue.take(bus["id"],request["id"])
	if result.is_empty(): return
	entry.erase("route_request")
	var route: PackedStringArray=result["route"]
	if route.is_empty(): return
	var graph: Dictionary=passengers.plan["network"]
	var suffix: Array=request["bridge"]
	var before: String=request["incoming"]
	for index in range(1,route.size()):
		var at: String=route[index-1]
		var next: String=route[index]
		suffix.append(Plan.piece(Traffic.turn(graph,before,at,next),[before,at,next],"turn",at))
		var edge: Dictionary=graph["edges"][Traffic.edge_id(at,next)]
		suffix.append(Plan.piece(edge["points"],[at,next],"edge"))
		before=at
	var last: String=route[-1]
	var approach: Dictionary=graph["edges"].get(Traffic.edge_id(before,last),{})
	if approach.is_empty(): return
	var arrival: Dictionary=Plan.piece(PackedVector2Array([approach["points"][-1],request["stop"]["dock"]]),[before,last],"arrival")
	if not safe_piece(entry,arrival,0): return
	suffix.append(arrival)
	entry["segments"]=entry["segments"].slice(0,entry["route_boundary"])+suffix
	entry.erase("route_boundary")

func drive(entry: Dictionary,delta: float,people: Array[Vector2]) -> void:
	var vehicle: Dictionary=entry["vehicle"]; var id: String=vehicle["id"]; var bus: Dictionary=passengers.vehicles[id]
	if bus["phase"]=="blocked": return
	if bus["phase"]=="dwell":
		if bus.get("retiring",false) and bus["manifest"].is_empty() and bus["reserved"].is_empty():
			release_gate(entry)
			passengers.stop_owners.erase(bus["stop"])
			vehicle["actor"].hide()
			vehicle["actor"].queue_free()
			entry["label"].queue_free()
			passengers.vehicles.erase(id)
			buses.erase(id)
			return
		var line: Dictionary=passengers.plan["lines"].get(bus["line"],{})
		if line.is_empty():
			if not bus["manifest"].any(func(uid: String)->bool:return passengers.find(uid).get("state")=="alighting"):
				hold_bus(entry,bus,"The next bus leg is unavailable. Waiting for a connected line.")
			return
		var leg: Dictionary=line["legs"][line["stops"].find(bus["stop"])]
		var result: Dictionary=passengers.depart(id,elapsed)
		entry["status"]="Boarding / timetable" if not result["ok"] else "Driving"
		vehicle["speed"]=0
		if result["ok"]:
			entry["trip_line"]=line
			entry["segments"]=leg["segments"]
			entry["segment"]=0
			entry["distance"]=0.0
			entry["gate_open"]=false
		return
	accept_bus_route(entry,bus)
	if entry.has("route_boundary") and entry["segment"]>=entry["route_boundary"]:
		vehicle["speed"]=0
		if entry.has("route_request"): entry["status"]="Finding a safe route to the next stop"
		else: hold_bus(entry,bus,"Next bus stop is unreachable. Waiting for a safe road connection.")
		return
	if entry["segment"]>=entry["segments"].size():
		var result: Dictionary=passengers.dock(id,bus["next"],vehicle["point"],elapsed,entry.get("trip_line",{}))
		entry["status"]="Waiting for platform" if not result["ok"] else "Boarding / timetable"
		if result["ok"]: entry["stop_layout"]=Plan.stop_layout(passengers.plan["stops"][bus["stop"]])
		return
	var segment: Dictionary=entry["segments"][entry["segment"]]
	if not entry["gate_open"]:
		if not segment["gate"].is_empty():
			var time: float=traffic.gate_time(segment["gate"],elapsed) if is_instance_valid(traffic) else elapsed
			var permission: Dictionary=gate_keeper().request(passengers.plan["network"],id,segment["gate"],time,Traffic.crossing_occupied(passengers.plan["network"],segment["gate"],people),segment.get("approach",""))
			if not permission["allowed"]: entry["status"]=permission["reason"]; vehicle["speed"]=0; return
		entry["gate_open"]=true
	var profile: Dictionary=vehicle.get("fleet_profile",{})
	var speed: float=move_toward(vehicle["speed"],minf(passengers.plan["settings"]["speed"],profile.get("speed",8)),profile.get("acceleration",3)*delta)
	var distance: float=minf(entry["distance"]+speed*delta,segment["length"])
	var sample: Dictionary=Traffic.sample(segment["points"],distance)
	var reason: String=helper.obstructed(vehicle,sample["point"],sample["heading"],people)
	if reason.is_empty() and not vehicle_clear(sample["point"],sample["heading"],vehicle): reason="Road obstructed"
	if not reason.is_empty(): vehicle["speed"]=0; entry["status"]=reason; return
	vehicle["point"]=sample["point"]; vehicle["heading"]=sample["heading"]; vehicle["speed"]=speed; entry["distance"]=distance; entry["status"]="Driving"
	pose_bus(entry)
	if sample["finished"]:
		if not segment["gate"].is_empty(): gate_keeper().release(id,segment["gate"])
		entry["segment"]+=1; entry["distance"]=0.0; entry["gate_open"]=false
func actor_point(actor: Node) -> Vector2:
	return Traffic.metric([actor.position.x,actor.position.y,0] if dimension=="2d" else [actor.position.x,actor.position.y,actor.position.z],dimension)
func teleport(actor: Node,point: Vector2,supported: bool=true) -> void:
	var raw: Array=Traffic.world(point,dimension,.05)
	if dimension=="2d": actor.teleport_to(Vector2(raw[0],raw[1])); return
	var destination:=Vector3(raw[0],raw[1],raw[2])
	destination.y+=helper.surface(point)["height"]
	if supported:
		var global: Vector3=helper.container.to_global(destination)
		var query:=PhysicsRayQueryParameters3D.create(global+Vector3.UP*2,global-Vector3.UP*2,3,[actor.get_rid()])
		var hit: Dictionary=actor.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit["normal"].y>.65: destination=helper.container.to_local(hit["position"])+Vector3.UP*.005
	actor.teleport_to(destination)
func request(origin: Vector2,destination: Vector2) -> Dictionary:
	if passengers.plan.get("settings",{}).get("enabled",false) and bus_pool.is_empty() and school_pool.is_empty() and buses.is_empty():
		return Plan.failure("Choose an available bus with a positive fleet weight.")
	if passengers.plan.is_empty(): return Plan.failure("Transit is not configured.")
	return start_passenger(Plan.journey(passengers.plan,origin,destination,elapsed,helper.obstacles))

func request_school(actor: Node,destination: Vector2,line: String,from: String,to: String) -> Dictionary:
	if not active or paused or school_pool.is_empty() or not is_instance_valid(helper.container):
		return Plan.failure("The school bus is unavailable.")
	if not is_instance_valid(actor) or actor.has_meta("transit_passenger"):
		return Plan.failure("This pupil already has a trip or no walking body.")
	var origin: Vector2=actor_point(actor)
	var itinerary: Dictionary=Plan.school_journey(passengers.plan,origin,destination,elapsed,helper.obstacles,line,from,to,School.bus_asset(dimension))
	return start_passenger(itinerary,actor)

func start_passenger(itinerary: Dictionary,borrowed: Node=null) -> Dictionary:
	if passengers.jobs.filter(func(job: Dictionary):return not job["state"] in ["complete","cancelled"]).size()>=passengers.plan["settings"]["population"]:
		return Plan.failure("The active passenger limit has been reached. Wait for arrivals or increase the transit passenger limit.")
	if not itinerary["ok"]: return itinerary
	for leg in itinerary["legs"]:
		if leg["kind"]=="walk" and not supported_path(leg["path"]): return Plan.failure("The walking connection has no supported ground surface.")
	var result: Dictionary=passengers.request(itinerary)
	if not result["ok"]: return result
	var job: Dictionary=result["job"]
	var actor: Node=borrowed
	var walker: Dictionary={"job":job,"key":"","path":PackedVector2Array(),"index":0,"stalled":0.0}
	if is_instance_valid(borrowed):
		walker["return_parent"]=weakref(actor.get_parent())
		walker["origin"]=actor.position
		actor.reparent(helper.container,true)
	else:
		actor=load("res://scenes/items/Characters/Office_Worker.tscn").instantiate() if dimension=="2d" else preload("res://scripts/builder/player_3d.gd").new()
		if dimension=="2d": actor.is_player_controlled=false; actor.move_speed=28
		else: actor.active=false; actor.move_speed=Plan.WALK_SPEED
		helper.container.add_child(actor)
		actor.name=job["id"]
		teleport(actor,itinerary["legs"][0]["path"][0])
	actor.visible=true
	actor.set_meta("transit_passenger",job["id"])
	actor.set_physics_process(false)
	actor.collision_layer=0
	actor.collision_mask=1 if dimension=="2d" else 3
	walker["actor"]=actor
	walkers[job["id"]]=walker
	for id in walkers.keys():
		if passengers.find(id).is_empty(): remove_walker(id)
	return result

func remove_walker(id: String,reset_trip: bool=false) -> void:
	var walker: Dictionary=walkers.get(id,{})
	if walker.is_empty(): return
	walkers.erase(id)
	var actor: Variant=walker["actor"]
	var job: Dictionary=walker["job"]
	var manifest: Array=passengers.vehicles.get(job["vehicle"],{}).get("manifest",[])
	var onboard: bool=job["id"] in manifest
	if reset_trip: passengers.abandon(job,"The school trip was interrupted.")
	if not is_instance_valid(actor): return
	if not walker.has("return_parent"):
		actor.free()
		return
	var parent: Node=walker["return_parent"].get_ref()
	if not is_instance_valid(parent):
		actor.free()
		return
	actor.reparent(parent,true)
	actor.remove_meta("transit_passenger")
	if onboard and reset_trip: actor.teleport_to(walker["origin"])
	actor.visible=true

func supported_path(path: PackedVector2Array) -> bool:
	if dimension=="2d": return true
	if not is_instance_valid(helper.container) or path.is_empty(): return false
	for point in path:
		var level: float=helper.surface(point)["height"]; var global: Vector3=helper.container.to_global(Vector3(point.x,level,point.y))
		var query:=PhysicsRayQueryParameters3D.create(global+Vector3.UP*.6,global-Vector3.UP,3)
		var hit: Dictionary=helper.container.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or hit["normal"].y<.65 or absf(helper.container.to_local(hit["position"]).y-level)>.5: return false
	return true
func block_walker(walker: Dictionary,reason: String) -> void:
	var job: Dictionary=walker["job"]
	if not job["vehicle"].is_empty(): passengers.block_vehicle(job["vehicle"],reason)
	job["state"]="blocked"; job["reason"]=reason
func walk(walker: Dictionary,delta: float) -> bool:
	var actor: Node=walker["actor"]; var point: Vector2=actor_point(actor); var path: PackedVector2Array=walker["path"]
	var clear: bool=actor.clear_at(actor.global_position) if dimension=="2d" else actor.clear_at(actor.global_transform,true)
	if not clear: block_walker(walker,"Construction blocks this passenger; clear the area and restart transit"); return false
	while walker["index"]<path.size() and point.distance_to(path[walker["index"]])<.2: walker["index"]+=1
	var movement: Vector2=Vector2.ZERO
	if walker["index"]<path.size(): movement=(path[walker["index"]]-point).normalized()
	for other in helper.external_vehicles:
		if other["id"]==walker["job"]["vehicle"]: continue
		if other["point"].distance_to(point)<2.2: movement=Vector2.ZERO; break
	var coordinator: Node=traffic if is_instance_valid(traffic) else helper
	if not movement.is_zero_approx() and not coordinator.pedestrian_can_enter(point,point+movement*.45,passengers.plan["network"],traffic.junction_time if is_instance_valid(traffic) else elapsed):
		movement=Vector2.ZERO
		if dimension=="2d": actor.velocity=Vector2.ZERO
		else:
			actor.velocity.x=0
			actor.velocity.z=0
	if dimension=="2d":
		actor.move_character(delta,Vector2((movement.x-movement.y)*8,(movement.x+movement.y)*4).normalized()); actor._update_animation(delta)
	else: actor.move_character(delta,Vector3(movement.x,0,movement.y))
	walker["stalled"]=walker["stalled"]+delta if not movement.is_zero_approx() and actor_point(actor).distance_to(point)<.001 else 0.0
	if walker["stalled"]>3: block_walker(walker,"Walking route obstructed; clear the area and restart transit")
	return walker["index"]>=path.size()
func step_walker(walker: Dictionary,delta: float) -> void:
	var job: Dictionary=walker["job"]; var actor: Node=walker["actor"]; var state: String=job["state"]
	if state in ["complete","cancelled"]: actor.visible=false; return
	if state=="blocked": return
	if not job["vehicle"].is_empty() and passengers.vehicles.get(job["vehicle"],{}).get("phase")=="blocked": return
	if state=="onboard":
		actor.visible=false
		if buses.has(job["vehicle"]): teleport(actor,buses[job["vehicle"]]["vehicle"]["point"],false)
		return
	if state=="waiting":
		for id in buses:
			if passengers.reserve(job,id,elapsed)["ok"]: break
		return
	var key: String=state+str(job["index"])
	if walker["key"]!=key:
		var path: PackedVector2Array=[]
		if state=="walking": path=job["legs"][job["index"]]["path"]
		else:
			var bus: Dictionary=passengers.vehicles[job["vehicle"]]; var stop: Dictionary=passengers.plan["stops"][bus["stop"]]
			var door: Vector2=stop["dock"]+stop["right"]*1.2
			if state=="alighting": teleport(actor,door); actor.visible=true
			var goal: Vector2=stop["platform"] if state=="alighting" else door
			var route: Dictionary=Plan.walking(actor_point(actor),goal,helper.obstacles)
			if not route["ok"]: block_walker(walker,route["reason"]); return
			path=route["path"]
		if not supported_path(path): block_walker(walker,"The walking connection has no supported ground surface"); return
		walker["path"]=path; walker["index"]=0; walker["key"]=key; walker["stalled"]=0.0
	if not walk(walker,delta): return
	if state=="walking" and (dimension=="2d" or absf(actor.position.y-helper.surface(actor_point(actor))["height"])<.5): passengers.walk_arrived(job,actor_point(actor),elapsed)
	elif state=="boarding":
		if passengers.board(job,actor_point(actor)):
			actor.visible=false; teleport(actor,buses[job["vehicle"]]["vehicle"]["point"],false)
	elif state=="alighting": passengers.alight(job,actor_point(actor),elapsed)
func automatic_request() -> void:
	if walkers.values().filter(func(w: Dictionary):return not w["job"]["state"] in ["complete","cancelled"]).size()>=passengers.plan["settings"]["population"]: return
	var stops: Array=passengers.plan["stops"].values()
	if stops.size()<2: return
	for attempt in 8:
		var from: Dictionary=stops[random.randi_range(0,stops.size()-1)]; var to: Dictionary=stops[random.randi_range(0,stops.size()-1)]
		if from["uid"]==to["uid"]: continue
		var result: Dictionary=request(from["platform"]+from["right"]*2,to["platform"]+to["right"]*2)
		if result["ok"]: notice=""; return
		notice=result["reason"]
func step(delta: float) -> void:
	if not active or paused or passengers.plan.is_empty() or not passengers.plan["settings"]["enabled"] or not is_finite(delta) or delta<=0: return
	route_queue.step(24,500)
	var remaining: float=minf(delta,.25)
	while remaining>.00001:
		var tick: float=minf(.05,remaining); remaining-=tick; elapsed+=tick; refresh_links(); spawn_buses()
		for walker in walkers.values(): step_walker(walker,tick)
		var people: Array[Vector2]=helper.pedestrian_points()
		for entry in buses.values(): drive(entry,tick,people)
		auto_time-=tick
		if passengers.plan["settings"]["automatic"] and auto_time<=0:
			auto_time=passengers.plan["settings"]["interval"]; automatic_request()
func summary() -> String:
	if passengers.plan.is_empty() or not passengers.plan["settings"]["enabled"]: return "Public transit is off."
	var value: String="%d lines · %d buses · %d passengers · %d arrived"%[passengers.plan["lines"].size(),buses.size(),passengers.jobs.filter(func(job: Dictionary):return not job["state"] in ["complete","cancelled"]).size(),passengers.completed]
	var waiting: Array=buses.values().filter(func(entry: Dictionary):return passengers.vehicles[entry["vehicle"]["id"]]["phase"]=="blocked")
	if not waiting.is_empty(): value+="\n"+waiting[0]["status"]
	return value
func reset() -> void:
	for entry in buses.values(): release_gate(entry)
	for id in walkers.keys(): remove_walker(id,true)
	route_queue.clear_requests(); buses.clear(); walkers.clear(); bus_pool.clear(); school_pool.clear(); passengers.reset(); helper.reset(); elapsed=0; auto_time=0; signature=0; notice=""
func _physics_process(delta: float) -> void: step(delta)
func _exit_tree() -> void: reset()
