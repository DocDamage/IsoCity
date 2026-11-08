extends Node

const Plan=preload("res://scripts/builder/service_plan.gd")
const Dispatch=preload("res://scripts/builder/service_dispatch.gd")
const Traffic=preload("res://scripts/builder/traffic_plan.gd")
const Walk=preload("res://scripts/builder/citizen_plan.gd")
const Instance=preload("res://scripts/builder/asset_instance.gd")
const SITE_DISTANCE=1.2
var route_queue=preload("res://scripts/builder/traffic_route_queue.gd").new()
var dispatch=Dispatch.new()
var helper=preload("res://scripts/builder/traffic_runtime.gd").new()
var traffic: Node
var crews: Dictionary={}
var dimension: String="2d"
var library: RefCounted
var active: bool=true
var paused: bool=false
var elapsed: float=0
var auto_time: float=0
var random:=RandomNumberGenerator.new()
var signature: int=0
var automatic_notice: String=""
var site_stops: Dictionary={}
var home_cache: Dictionary={}
var target_owners: Dictionary={}
var exploration: Node
var request_kind: String="fire"
var request_label: String="V"
var cycle_label: String="Shift+V"
var message: String=""
var panel: PanelContainer
var hud_title: Label
var hud_detail: Label
var hud_message: Label
var request_button: Button
var cycle_button: Button
var ui_scale: float=1
var large_targets: bool=false
var high_contrast: bool=false
var ui_elapsed: float=0
var ui_signature: int=-1
var hud_uid: String=""

func _ready() -> void:
	helper.render_signals=false
	add_child(helper); helper.set_physics_process(false); helper.active=false
	var layer:=CanvasLayer.new(); layer.layer=22; add_child(layer)
	panel=PanelContainer.new(); panel.mouse_force_pass_scroll_events=false; layer.add_child(panel); panel.hide()
	var scroll:=ScrollContainer.new(); scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; scroll.follow_focus=true; scroll.mouse_force_pass_scroll_events=false; panel.add_child(scroll)
	var box:=VBoxContainer.new(); box.size_flags_horizontal=Control.SIZE_EXPAND_FILL; box.add_theme_constant_override("separation",6); scroll.add_child(box)
	for index in 3:
		var label:=Label.new(); label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; box.add_child(label)
		if index==0: hud_title=label
		elif index==1: hud_detail=label
		else: hud_message=label
	request_button=Button.new(); request_button.clip_text=true; box.add_child(request_button); request_button.pressed.connect(request_nearby)
	cycle_button=Button.new(); cycle_button.clip_text=true; box.add_child(cycle_button); cycle_button.pressed.connect(cycle_request)

func configure(data: Dictionary,assets: RefCounted,instances: Dictionary,parent: Node,traffic_value: Node,visible_only: bool=true,walk_value: Node=null) -> void:
	traffic=traffic_value; library=assets; dimension=data["mode"]
	if walk_value!=null: exploration=walk_value
	var stamp: int=hash([data.get("services",{}),data.get("fleet",{}),data["objects"],data.get("roads",[]),data.get("layers",{}),data.get("terrain",{}),data.get("terrain_vertices",[]),data.get("water_cells",[]),visible_only])
	if stamp==signature and not dispatch.plan.is_empty(): return
	var settings: Dictionary=Plan.settings(data)
	if not settings["enabled"]:
		reset(); signature=stamp; dispatch.plan={"settings":settings,"stations":{},"targets":{},"notices":PackedStringArray()}; return
	if dispatch.plan.is_empty() or not dispatch.plan["settings"]["enabled"] or dispatch.plan["settings"].get("seed")!=settings["seed"] or settings["automatic"] and not dispatch.plan["settings"]["automatic"]:
		random.seed=settings["seed"]; auto_time=settings["interval"]
	var fleet: Dictionary=data.duplicate(false); fleet["traffic"]={"enabled":true,"population":0,"seed":1,"speed":4,"parking_seconds":8}
	helper.configure(fleet,library,instances,parent,visible_only); helper.container.name="ServiceActors"
	home_cache.clear()
	var arrivals: Dictionary={}
	site_stops.clear()
	for item in data["objects"]:
		if not instances.has(item["uid"]): continue
		var point: Variant=preload("res://scripts/builder/entrance_anchors.gd").position_for(instances[item["uid"]],item,dimension,library)
		arrivals[item["uid"]]=[point.x,point.y,item["position"][2]] if dimension=="2d" else [point.x,point.y,point.z]
		var door: Variant=preload("res://scripts/builder/entrance_anchors.gd").position_for(instances[item["uid"]],item,dimension,library,false)
		var outward: Vector2=Traffic.metric(arrivals[item["uid"]],dimension)-Traffic.metric([door.x,door.y,0] if dimension=="2d" else [door.x,door.y,door.z],dimension)
		if outward.length()>.01:
			var stop: Vector2=Traffic.metric(arrivals[item["uid"]],dimension)+outward.normalized()*2.75
			if not helper.obstacles.any(func(box: Rect2):return box.grow(.65).has_point(stop)): site_stops[item["uid"]]=stop
	dispatch.configure(Plan.build(data,library,arrivals,visible_only),crews)
	signature=stamp
	var anchors: Dictionary={}
	for category in ["stations","targets"]:
		for uid in dispatch.plan[category]:
			var site: Dictionary=dispatch.plan[category][uid]
			anchors[uid]=[site["point"],site["height"],site["config"]["kind"],site["kinds"],site_stops.get(uid)]
	if route_queue.configure(dispatch.plan["network"],helper.obstacles,anchors,26):
		for crew in crews.values():
			refresh_crew(crew)
	refresh_links()

func nearby_target() -> String:
	if not is_instance_valid(exploration) or not exploration.enabled or exploration.interior!=null or dispatch.plan.is_empty(): return ""
	var player: Node=exploration.player
	var point: Vector2=Traffic.metric([player.position.x,player.position.y,0] if dimension=="2d" else [player.position.x,player.position.y,player.position.z],dimension)
	if dimension=="3d" and absf(player.position.y-helper.surface(point)["height"])>.6: return ""
	var best: float=6 if dimension=="2d" else 3.5; var uid: String=""
	for key in dispatch.plan["targets"]:
		var distance: float=point.distance_to(dispatch.plan["targets"][key]["point"])
		if distance<best: best=distance; uid=key
	return uid

func cycle_request() -> void:
	var uid: String=nearby_target()
	var kinds: Array=dispatch.plan["targets"][uid]["kinds"] if not uid.is_empty() else Plan.KINDS.slice(0,4)
	request_kind=kinds[(kinds.find(request_kind)+1)%kinds.size()]; message=""; update_ui()

func request_nearby() -> void:
	var uid: String=nearby_target()
	if uid.is_empty(): message="Walk near a neighborhood building or waste target to request a visit."; update_ui(); return
	if not request_kind in dispatch.plan["targets"][uid]["kinds"]: request_kind=dispatch.plan["targets"][uid]["kinds"][0]
	var result: Dictionary=dispatch.request(request_kind,uid)
	hud_uid=uid
	message=("Visit requested for "+dispatch.plan["targets"][uid]["name"]+".") if result["ok"] else result["reason"]
	update_ui()

func update_ui() -> void:
	if not is_instance_valid(panel): return
	panel.visible=active and not dispatch.plan.is_empty() and dispatch.plan["settings"]["enabled"] and is_instance_valid(exploration) and exploration.enabled and exploration.interior==null
	if not panel.visible: return
	var uid: String=nearby_target()
	if hud_uid!=uid: hud_uid=uid; message=""
	if not uid.is_empty() and not request_kind in dispatch.plan["targets"][uid]["kinds"]: request_kind=dispatch.plan["targets"][uid]["kinds"][0]
	hud_title.text="City services · "+request_kind.capitalize()
	hud_detail.text="Walk near a neighborhood building to request a visit."
	if not uid.is_empty():
		var coverage: Dictionary=Plan.choose(dispatch.plan,request_kind,uid)
		hud_detail.text=dispatch.plan["targets"][uid]["name"]+"\n"+("Covered · %.1f road/driveway units" % coverage["distance"] if coverage["ok"] else coverage["reason"])
	hud_message.text=message
	if not uid.is_empty():
		var recent: Array=dispatch.jobs.filter(func(job: Dictionary):return job["target"]==uid and job["kind"]==request_kind)
		if not recent.is_empty(): hud_message.text+=("\n" if not hud_message.text.is_empty() else "")+recent[-1]["reason"]
	request_button.text=request_label+" · Request visit"; request_button.disabled=uid.is_empty()
	cycle_button.text=cycle_label+" · Next service type"
	var viewport_size: Vector2=get_viewport().get_visible_rect().size
	panel.size=Vector2(maxf(120,minf(300*ui_scale,viewport_size.x*.42-20)),maxf(100,minf(230*ui_scale,viewport_size.y-20)))
	panel.position=Vector2(maxf(0,viewport_size.x-panel.size.x-10),maxf(0,viewport_size.y-panel.size.y-10))
	var stamp: int=hash([ui_scale,large_targets,high_contrast])
	if stamp!=ui_signature:
		ui_signature=stamp
		for control in [hud_title,hud_detail,hud_message]: control.add_theme_font_size_override("font_size",roundi((16 if control==hud_title else 12)*ui_scale))
		for button in [request_button,cycle_button]: button.custom_minimum_size.y=44 if large_targets else 32; button.add_theme_font_size_override("font_size",roundi(14*ui_scale))
		var style:=StyleBoxFlat.new(); style.bg_color=Color.BLACK if high_contrast else Color("152531"); style.border_color=Color.WHITE if high_contrast else Color("527180"); style.set_border_width_all(2 if high_contrast else 1); style.set_content_margin_all(8); panel.add_theme_stylebox_override("panel",style)

func vehicle_states() -> Array[Dictionary]:
	var values: Array[Dictionary]=[]
	for crew in crews.values():
		if crew["vehicle"]["actor"].visible: values.append(crew["vehicle"])
	return values

func worker_actors() -> Array[Node]:
	var values: Array[Node]=[]
	for crew in crews.values():
		if is_instance_valid(crew["worker"]): values.append(crew["worker"])
	return values

func refresh_links() -> void:
	helper.driving=traffic.driving if is_instance_valid(traffic) else null
	helper.transit=traffic.transit if is_instance_valid(traffic) else null
	helper.external_vehicles.assign(vehicle_states())
	helper.pedestrians.clear()
	if is_instance_valid(traffic):
		helper.external_vehicles.append_array(traffic.vehicles)
		helper.pedestrians.assign(traffic.pedestrians)
		traffic.external_vehicles.assign(vehicle_states())
	for actor in worker_actors():
		if not actor in helper.pedestrians: helper.pedestrians.append(actor)
		if is_instance_valid(traffic) and not actor in traffic.pedestrians: traffic.pedestrians.append(actor)
	if is_instance_valid(helper.transit):
		for actor in helper.transit.pedestrian_actors():
			if not actor in helper.pedestrians: helper.pedestrians.append(actor)

func road_path(from: Vector2,to: Vector2,clearance: float=.65) -> PackedVector2Array:
	var result: Dictionary=Walk.route(from,to,helper.obstacles,clearance)
	if result["path"].is_empty() or result["start"].distance_to(from)>.8 or result["goal"].distance_to(to)>.4: return []
	return result["path"]

func driveway_clear(path: PackedVector2Array, vehicle: Dictionary, radius: float) -> bool:
	if path.size()<2: return not path.is_empty()
	var bounds:=Rect2(path[0],Vector2.ZERO)
	for point in path: bounds=bounds.expand(point)
	bounds=bounds.grow(radius)
	var nearby: Array=helper.obstacles.filter(func(box: Rect2):return bounds.intersects(box,true))
	for index in range(1,path.size()):
		var start: Vector2=path[index-1]
		var finish: Vector2=path[index]
		var heading: Vector2=start.direction_to(finish)
		var steps: int=maxi(1,ceili(start.distance_to(finish)/.2))
		for step in range(steps+1):
			var point: Vector2=start.lerp(finish,float(step)/steps)
			if nearby.any(func(box: Rect2):return Traffic.Fleet.intersects_obstacle(vehicle,point,heading,box)):
				return false
	return true

func driveway(from: Vector2,to: Vector2,vehicle: Dictionary) -> PackedVector2Array:
	var path: PackedVector2Array=road_path(from,to)
	if vehicle.is_empty() or path.is_empty(): return path
	var radius: float=Vector2(vehicle["half_length"],vehicle["half_width"]).length()+.17
	if driveway_clear(path,vehicle,radius): return path
	path=road_path(from,to,radius)
	return path if driveway_clear(path,vehicle,radius) else PackedVector2Array()

func service_piece(path: PackedVector2Array,lane: Array,kind: String,gate: String="",release: String="",approach: String="") -> Dictionary:
	return {"path":path,"lane":lane,"kind":kind,"gate":gate,"release":release,"approach":approach}

func itinerary(route: PackedStringArray,from: Vector2,to: Vector2,vehicle: Dictionary={}) -> Array[Dictionary]:
	var segments: Array[Dictionary]=[]
	if route.is_empty(): return segments
	var network: Dictionary=dispatch.plan["network"]
	if route.size()==1:
		var direct: PackedVector2Array=driveway(from,to,vehicle)
		if not direct.is_empty(): segments.append(service_piece(direct,[route[0]],"direct",route[0],route[0],Traffic.closest_approach(network,route[0],from)))
		return segments
	var edges: Array=[]
	for index in range(route.size()-1):
		var edge: Dictionary=network["edges"].get(Traffic.edge_id(route[index],route[index+1]),{})
		if edge.is_empty(): return []
		edges.append(edge)
	var drive: PackedVector2Array=driveway(from,edges[0]["points"][0],vehicle)
	if drive.is_empty(): return []
	segments.append(service_piece(drive,[route[0],route[1]],"departure",route[0],"",Traffic.closest_approach(network,route[0],from)))
	for index in edges.size():
		segments.append(service_piece(edges[index]["points"],[route[index],route[index+1]],"edge","",route[0] if index==0 else ""))
		if index+1<edges.size(): segments.append(service_piece(Traffic.turn(network,route[index],route[index+1],route[index+2]),[route[index],route[index+1],route[index+2]],"turn",route[index+1],route[index+1],route[index]))
	drive=driveway(edges[-1]["points"][-1],to,vehicle)
	if drive.is_empty(): return []
	segments.append(service_piece(drive,[route[-2],route[-1]],"arrival",route[-1],route[-1],route[-2])); return segments

func curb_for(job: Dictionary,use_site_stop: bool=true) -> Vector2:
	if use_site_stop and site_stops.has(job["target"]): return site_stops[job["target"]]
	var route: PackedStringArray=job["route"]
	var section: Dictionary=dispatch.plan["network"]["sections"][route[-1]]
	var axis:=Vector2.RIGHT
	if route.size()>1: axis=dispatch.plan["network"]["edges"][Traffic.edge_id(route[-2],route[-1])]["axis"]
	return Traffic.center(section["cell"],dimension)+Vector2(-axis.y,axis.x)*(section["width"]*.5+1.5)

func crew_driveway(job: Dictionary,point: Vector2,vehicle: Dictionary) -> Dictionary:
	var radius: float=Vector2(vehicle["half_length"],vehicle["half_width"]).length()+.17
	var destinations: Array[Vector2]=[curb_for(job)]
	var shoulder: Vector2=curb_for(job,false)
	if shoulder not in destinations: destinations.append(shoulder)
	for clearance in [.65,maxf(.65,radius)]:
		var garage: String=JSON.stringify([job["station"],clearance])
		if not home_cache.has(garage):
			home_cache[garage]=Walk.route(point,point,helper.obstacles,clearance)
		var safe: Dictionary=home_cache[garage]
		if safe["path"].is_empty() or safe["start"].distance_to(point)>3: continue
		var origin: Vector2=safe["start"]
		for curb in destinations:
			var segments: Array[Dictionary]=itinerary(job["route"],origin,curb,vehicle)
			if not segments.is_empty():
				return {"origin":origin,"curb":curb,"segments":segments}
	return {}

func spawn_crew(job: Dictionary) -> void:
	if target_owners.has(job["target"]) and target_owners[job["target"]]!=job["id"]: job["reason"]="Waiting for another crew to clear the site"; return
	for id in crews.keys():
		if crews[id]["job"]["unit"]==job["unit"] and crews[id]["job"]["state"]=="complete": remove_crew(id)
	var station: Dictionary=dispatch.plan["stations"][job["station"]]
	var profile: Dictionary=job["fleet_profile"]
	var fields: Dictionary=Traffic.Fleet.vehicle_fields(profile)
	var layout: Dictionary=crew_driveway(job,station["point"],fields)
	if layout.is_empty(): job["state"]="blocked"; job["reason"]="No clear driveway fits the selected service vehicle"; return
	var origin: Vector2=layout["origin"]
	var curb: Vector2=layout["curb"]
	var segments: Array[Dictionary]=layout["segments"]
	var heading: Vector2=Traffic.sample(segments[0]["path"],0)["heading"]
	var occupied: Array=vehicle_states()
	if is_instance_valid(traffic): occupied.append_array(traffic.vehicles)
	if is_instance_valid(helper.transit): occupied.append_array(helper.transit.vehicle_states())
	if occupied.any(func(v: Dictionary):return Traffic.Fleet.overlaps(fields,origin,heading,v,.3)): job["reason"]="Waiting for station driveway clearance"; return
	var definition: Dictionary=Plan.unit(job["kind"])
	var actor: Node=Instance.make(library,profile["asset"],dimension); actor.name=("Crew_"+job["unit"]).validate_node_name(); actor.set_meta("service_unit",job["unit"])
	helper.container.add_child(actor); helper.disable_collisions(actor)
	var vehicle: Dictionary={"id":"crew_"+job["unit"],"actor":actor,"point":origin,"heading":heading,"speed":0.0}
	vehicle.merge(fields)
	var worker: Node=load(library.assets[definition["worker_2d"]]["path"]).instantiate() if dimension=="2d" else preload("res://scripts/builder/player_3d.gd").new()
	if dimension=="2d": worker.is_player_controlled=false; worker.move_speed=40
	else: worker.active=false; worker.move_speed=1.8
	helper.container.add_child(worker); worker.set_physics_process(false); worker.collision_layer=0; worker.collision_mask=1 if dimension=="2d" else 3; worker.visible=false; worker.set_meta("service_worker",job["kind"])
	if dimension=="3d": worker.body.get_child(0).material_override.albedo_color=Color(definition["color"])
	var label: Node=Label.new() if dimension=="2d" else Label3D.new(); label.text=definition["activity"]
	if dimension=="2d": label.position=Vector2(-38,-28); label.add_theme_font_size_override("font_size",10); label.z_index=100; label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	else: label.position=Vector3(0,2.3,0); label.billboard=BaseMaterial3D.BILLBOARD_ENABLED; label.font_size=24; label.pixel_size=.02; label.outline_size=4
	worker.add_child(label)
	crews[job["id"]]={"job":job,"vehicle":vehicle,"worker":worker,"home":origin,"curb":curb,"segments":segments,"segment":0,"distance":0.0,"gate_open":false,"stage":"outbound","walk_path":PackedVector2Array(),"walk_index":0,"stalled":0.0,"label":label}
	crews[job["id"]]["station_pose"]=site_pose(station)
	crews[job["id"]]["target_pose"]=site_pose(dispatch.plan["targets"][job["target"]])
	target_owners[job["target"]]=job["id"]
	helper.pose(vehicle)
	var position: Array=Traffic.world(origin,dimension,.05)
	if dimension=="3d": position[1]+=helper.surface(origin)["height"]
	worker.teleport_to(Vector2(position[0],position[1]) if dimension=="2d" else Vector3(position[0],position[1],position[2]))

func site_pose(site: Dictionary) -> Array:
	return [site["point"],site["height"]] if not site.is_empty() else []

func driving_site(crew: Dictionary) -> Dictionary:
	var job: Dictionary=crew["job"]
	return dispatch.plan["stations"].get(job["station"],{}) if crew["stage"]=="returning" else dispatch.plan["targets"].get(job["target"],{})

func wait_for_route(crew: Dictionary,reason: String) -> void:
	var job: Dictionary=crew["job"]
	if job["state"]!="blocked": crew["resume_state"]=job["state"]
	block(crew,reason)
	crew["gate_open"]=false

func restore_crew(crew: Dictionary) -> bool:
	var job: Dictionary=crew["job"]
	if job["state"]=="blocked":
		if not crew.has("resume_state"): return false
		job["state"]=crew["resume_state"]
		crew.erase("resume_state")
	if crew["stage"]!="returning":
		var owner: String=target_owners.get(job["target"],"")
		if not owner.is_empty() and owner!=job["id"]:
			wait_for_route(crew,"Waiting for the service approach to clear")
			return false
		target_owners[job["target"]]=job["id"]
	return true

func usable_piece(crew: Dictionary,piece: Dictionary,distance: float) -> bool:
	var graph: Dictionary=dispatch.plan["network"]
	var lane: Array=piece["lane"]
	var kind: String=piece["kind"]
	var path: PackedVector2Array=piece["path"]
	var vehicle: Dictionary=crew["vehicle"]
	if kind=="direct":
		if not graph["sections"].has(lane[0]): return false
	elif kind=="turn":
		if not Traffic.Fleet.fit_turn(graph,lane[0],lane[1],lane[2],vehicle["fleet_profile"]): return false
		if Traffic.turn(graph,lane[0],lane[1],lane[2])!=path: return false
	else:
		var edge: Dictionary=graph["edges"].get(Traffic.edge_id(lane[0],lane[1]),{})
		if edge.is_empty() or not Traffic.Fleet.fit_edge(graph,lane[0],lane[1],vehicle["fleet_profile"]): return false
		if kind=="edge" and edge["points"]!=path: return false
		if kind=="departure" and edge["points"][0].distance_to(path[-1])>.4: return false
		if kind=="arrival" and edge["points"][-1].distance_to(path[0])>.8: return false
	return route_queue.path_clear(path,vehicle,distance)

func refresh_crew(crew: Dictionary) -> void:
	var job: Dictionary=crew["job"]
	if job["state"] in ["complete","cancelled"] or job["state"]=="blocked" and not crew.has("resume_state"): return
	var vehicle: Dictionary=crew["vehicle"]
	route_queue.cancel(vehicle["id"])
	crew.erase("route_request")
	crew.erase("route_boundary")
	var station: Dictionary=dispatch.plan["stations"].get(job["station"],{})
	var target: Dictionary=dispatch.plan["targets"].get(job["target"],{})
	var station_ok: bool=not station.is_empty() and station["config"]["kind"]==job["kind"] and site_pose(station)==crew["station_pose"]
	var target_ok: bool=not target.is_empty() and job["kind"] in target["kinds"] and site_pose(target)==crew["target_pose"]
	if not target_ok and target_owners.get(job["target"])==job["id"]: target_owners.erase(job["target"])
	if not station_ok or not target_ok and crew["stage"]!="returning":
		wait_for_route(crew,"Station or target approach changed. Waiting for a safe service connection.")
		return
	if not restore_crew(crew): return
	if not crew["stage"] in ["outbound","returning"]: return
	var pieces: Array=crew["segments"]
	var index: int=crew["segment"]
	if pieces.is_empty():
		begin_road_return(crew)
		return
	if index>=pieces.size() and pieces[-1]["kind"] in ["arrival","direct"] and usable_piece(crew,pieces[-1],Traffic.length(pieces[-1]["path"])): return
	var active_safe: bool=index<pieces.size() and usable_piece(crew,pieces[index],crew["distance"])
	if active_safe and pieces.slice(index+1).all(func(piece: Dictionary)->bool:return usable_piece(crew,piece,0)):
		return
	var anchor_index: int=index if active_safe else index-1
	if not active_safe:
		if anchor_index<0 or crew["distance"]>.001 or vehicle["point"].distance_to(pieces[anchor_index]["path"][-1])>.001 or not usable_piece(crew,pieces[anchor_index],Traffic.length(pieces[anchor_index]["path"])):
			wait_for_route(crew,"Current service lane changed. Waiting for a safe road connection.")
			return
		release_gate(crew)
		crew["gate_open"]=false
	var anchor: Dictionary=pieces[anchor_index]
	crew["route_boundary"]=anchor_index+1
	if anchor["kind"] in ["arrival","direct"]: return
	var lane: Array=anchor["lane"]
	var from: String=lane[-2]
	var at: String=lane[-1]
	var start: String=Traffic.edge_id(from,at)
	var bridge: Array=[]
	if anchor["kind"]!="edge":
		var edge: Dictionary=dispatch.plan["network"]["edges"].get(start,{})
		if edge.is_empty() or edge["points"][0].distance_to(anchor["path"][-1])>.001: return
		var piece: Dictionary=service_piece(edge["points"],[from,at],"edge","",from if anchor["kind"]=="departure" else "")
		if not usable_piece(crew,piece,0): return
		bridge.append(piece)
	request_crew_route(crew,{start:bridge},crew_goals(driving_site(crew)))

func crew_goals(site: Dictionary) -> Dictionary:
	var graph: Dictionary=dispatch.plan["network"]
	var goals: Dictionary={}
	for access in site.get("access",[]):
		var at: String=access["section"]
		var incoming: Array=graph["sections"][at]["neighbors"].filter(func(before: String)->bool:return graph["edges"].has(Traffic.edge_id(before,at)))
		if not incoming.is_empty(): goals[at]=incoming
	return goals

func request_crew_route(crew: Dictionary,starts: Dictionary,goals: Dictionary) -> void:
	var vehicle: Dictionary=crew["vehicle"]
	var id: int=route_queue.request_from(vehicle["id"],starts.keys(),goals,vehicle["fleet_profile"])
	if id>0: crew["route_request"]={"id":id,"starts":starts,"goals":goals}

func exact_driveway(from: Vector2,to: Vector2,vehicle: Dictionary) -> PackedVector2Array:
	var path: PackedVector2Array=driveway(from,to,vehicle)
	if path.is_empty(): return []
	if from.distance_to(path[0])>.001: path.insert(0,from)
	if to.distance_to(path[-1])>.001: path.append(to)
	return path if route_queue.path_clear(path,vehicle) else PackedVector2Array()

func reroute_arrival(crew: Dictionary,from: String,at: String) -> PackedVector2Array:
	var graph: Dictionary=dispatch.plan["network"]
	var edge: Dictionary=graph["edges"][Traffic.edge_id(from,at)]
	var start: Vector2=edge["points"][-1]
	var vehicle: Dictionary=crew["vehicle"]
	if crew["stage"]=="returning": return exact_driveway(start,crew["home"],vehicle)
	var uid: String=crew["job"]["target"]
	var site: Dictionary=driving_site(crew)
	var path: PackedVector2Array=exact_driveway(start,site_stops.get(uid,crew["curb"]),vehicle)
	if not path.is_empty(): return path
	var section: Dictionary=graph["sections"][at]
	var side:=Vector2(-edge["axis"].y,edge["axis"].x)
	var curb: Vector2=Traffic.center(section["cell"],dimension)+side*(section["width"]*.5+1.5)
	if curb.distance_to(site["point"])>Plan.ACCESS_RADIUS: return []
	return exact_driveway(start,curb,vehicle)

func accept_crew_route(crew: Dictionary) -> void:
	if not crew.has("route_request"): return
	var request: Dictionary=crew["route_request"]
	var result: Dictionary=route_queue.take(crew["vehicle"]["id"],request["id"])
	if result.is_empty(): return
	crew.erase("route_request")
	var route: PackedStringArray=result["route"]
	if route.is_empty(): return
	var from: String=result["start"].get_slice(">",0)
	var last: String=route[-1]
	var before: String=route[-2] if route.size()>1 else from
	var arrival: PackedVector2Array=reroute_arrival(crew,before,last)
	if arrival.is_empty():
		request["goals"][last].erase(before)
		if request["goals"][last].is_empty(): request["goals"].erase(last)
		request_crew_route(crew,request["starts"],request["goals"])
		return
	var graph: Dictionary=dispatch.plan["network"]
	var suffix: Array=request["starts"][result["start"]]
	if not suffix.all(func(piece: Dictionary)->bool:return usable_piece(crew,piece,0)):
		request["starts"].erase(result["start"])
		request_crew_route(crew,request["starts"],request["goals"])
		return
	for index in range(1,route.size()):
		var at: String=route[index-1]
		var next: String=route[index]
		suffix.append(service_piece(Traffic.turn(graph,from,at,next),[from,at,next],"turn",at,at,from))
		var edge: Dictionary=graph["edges"][Traffic.edge_id(at,next)]
		suffix.append(service_piece(edge["points"],[at,next],"edge"))
		from=at
	suffix.append(service_piece(arrival,[before,last],"arrival",last,last,before))
	crew["segments"]=crew["segments"].slice(0,crew["route_boundary"])+suffix
	crew.erase("route_boundary")
	if crew["stage"]=="outbound": crew["curb"]=arrival[-1]

func begin_road_return(crew: Dictionary) -> void:
	var job: Dictionary=crew["job"]
	var vehicle: Dictionary=crew["vehicle"]
	var graph: Dictionary=dispatch.plan["network"]
	crew["worker"].visible=false
	crew["stage"]="returning"
	crew["segment"]=0
	crew["distance"]=0.0
	crew["gate_open"]=false
	var route: PackedStringArray=job["return_route"]
	if Traffic.Fleet.fit_route(graph,route,vehicle["fleet_profile"]):
		var pieces: Array[Dictionary]=itinerary(route,vehicle["point"],crew["home"],vehicle)
		if not pieces.is_empty() and pieces.all(func(piece: Dictionary)->bool:return usable_piece(crew,piece,0)):
			crew["segments"]=pieces
			return
	crew["segments"]=[]
	crew["route_boundary"]=0
	var starts: Dictionary={}
	for access in Plan.access(graph,vehicle["point"]):
		var from: String=access["section"]
		for at in Traffic.exits(graph,from):
			if not Traffic.Fleet.fit_edge(graph,from,at,vehicle["fleet_profile"]): continue
			var id: String=Traffic.edge_id(from,at)
			var edge: Dictionary=graph["edges"][id]
			var departure: PackedVector2Array=exact_driveway(vehicle["point"],edge["points"][0],vehicle)
			if departure.is_empty() or not route_queue.path_clear(edge["points"],vehicle): continue
			starts[id]=[service_piece(departure,[from,at],"departure",from,"",Traffic.closest_approach(graph,from,vehicle["point"])),
				service_piece(edge["points"],[from,at],"edge","",from)]
	request_crew_route(crew,starts,crew_goals(driving_site(crew)))

func gate_request(crew: Dictionary,section: String,people: Array[Vector2],approach: String="") -> bool:
	if section.is_empty(): return true
	var gates: RefCounted=traffic.gates if is_instance_valid(traffic) else helper.gates
	var time: float=traffic.gate_time(section,elapsed) if is_instance_valid(traffic) else elapsed
	var permission: Dictionary=gates.request(dispatch.plan["network"],crew["vehicle"]["id"],section,time,Traffic.crossing_occupied(dispatch.plan["network"],section,people),approach)
	if not permission["allowed"]: crew["job"]["reason"]=permission["reason"]
	return permission["allowed"]

func release_gate(crew: Dictionary,section: String="") -> void:
	var gates: RefCounted=traffic.gates if is_instance_valid(traffic) else helper.gates
	gates.release(crew["vehicle"]["id"],section)

func drive(crew: Dictionary,delta: float,people: Array[Vector2]) -> bool:
	accept_crew_route(crew)
	if crew.has("route_boundary") and crew["segment"]>=crew["route_boundary"]:
		crew["vehicle"]["speed"]=0
		if crew.has("route_request"): crew["job"]["reason"]="Finding a safe service route"
		else: wait_for_route(crew,"Service destination is unreachable. Waiting for a safe road connection.")
		return false
	if crew["segment"]>=crew["segments"].size(): return true
	var segment: Dictionary=crew["segments"][crew["segment"]]
	if not crew["gate_open"]:
		if not gate_request(crew,segment["gate"],people,segment.get("approach","")): crew["vehicle"]["speed"]=0; return false
		crew["gate_open"]=true
	var vehicle: Dictionary=crew["vehicle"]
	var profile: Dictionary=vehicle["fleet_profile"]
	var speed: float=move_toward(vehicle["speed"],profile["speed"],profile["acceleration"]*delta)
	var distance: float=minf(crew["distance"]+speed*delta,Traffic.length(segment["path"]))
	var sample: Dictionary=Traffic.sample(segment["path"],distance)
	var reason: String=helper.obstructed(vehicle,sample["point"],sample["heading"],people)
	if not reason.is_empty(): vehicle["speed"]=0; crew["job"]["reason"]=reason; return false
	vehicle["speed"]=speed; vehicle["point"]=sample["point"]; vehicle["heading"]=sample["heading"]; crew["distance"]=distance
	helper.pose(vehicle); crew["job"]["reason"]="Driving to site" if crew["stage"]=="outbound" else "Driving back to station"
	if not crew["worker"].visible:
		var position: Array=Traffic.world(vehicle["point"],dimension,.05)
		if dimension=="3d": position[1]+=helper.surface(vehicle["point"])["height"]
		crew["worker"].position=Vector2(position[0],position[1]) if dimension=="2d" else Vector3(position[0],position[1],position[2])
	if sample["finished"]:
		if not segment["release"].is_empty(): release_gate(crew,segment["release"])
		crew["segment"]+=1; crew["distance"]=0.0; crew["gate_open"]=false
	return crew["segment"]>=crew["segments"].size()

func worker_point(worker: Node) -> Vector2:
	return Traffic.metric([worker.position.x,worker.position.y,0] if dimension=="2d" else [worker.position.x,worker.position.y,worker.position.z],dimension)

func begin_walk(crew: Dictionary,to: Vector2,stage: String) -> bool:
	var worker: Node=crew["worker"]
	var start: Vector2=worker_point(worker) if worker.visible else crew["vehicle"]["point"]+Vector2(-crew["vehicle"]["heading"].y,crew["vehicle"]["heading"].x)*.8
	var obstacles: Array[Rect2]=helper.obstacles.duplicate()
	for actor in helper.pedestrians:
		if not is_instance_valid(actor) or actor==worker or not actor.visible: continue
		var position: Variant=helper.container.get_parent().to_local(actor.global_position)
		if dimension=="3d" and absf(position.y)>.8: continue
		var point: Vector2=Traffic.metric([position.x,position.y,0] if dimension=="2d" else [position.x,position.y,position.z],dimension)
		obstacles.append(Rect2(point,Vector2.ZERO))
	var route: Dictionary=Walk.route(start,to,obstacles,.4)
	if route["path"].is_empty() or route["start"].distance_to(start)>.8 or route["goal"].distance_to(to)>(1.1 if stage=="walking_in" else .8):
		if obstacles.size()>helper.obstacles.size(): crew["job"]["reason"]="Waiting for a clear walking approach"
		else: block(crew,"No safe walking approach for the crew")
		return false
	if not worker.visible:
		var spawn: Vector2=route["start"]; var position: Array=Traffic.world(spawn,dimension,.05)
		if dimension=="3d": position[1]+=helper.surface(spawn)["height"]
		worker.teleport_to(Vector2(position[0],position[1]) if dimension=="2d" else Vector3(position[0],position[1],position[2])); worker.visible=true
	crew["walk_path"]=route["path"]; crew["walk_index"]=0; crew["stage"]=stage; crew["stalled"]=0.0; return true

func walk(crew: Dictionary,delta: float) -> bool:
	var worker: Node=crew["worker"]
	var clear: bool=worker.clear_at(worker.global_position) if dimension=="2d" else worker.clear_at(worker.global_transform,true)
	if not clear: block(crew,"Construction blocks this worker; clear the area and restart services"); return false
	var point: Vector2=worker_point(worker); var path: PackedVector2Array=crew["walk_path"]
	while crew["walk_index"]<path.size() and point.distance_to(path[crew["walk_index"]])<.18: crew["walk_index"]+=1
	var movement:=Vector2.ZERO
	if crew["walk_index"]<path.size(): movement=(path[crew["walk_index"]]-point).normalized()
	var coordinator: Node=traffic if is_instance_valid(traffic) else helper
	if not movement.is_zero_approx() and not coordinator.pedestrian_can_enter(point,point+movement*.45,dispatch.plan["network"],traffic.junction_time if is_instance_valid(traffic) else elapsed):
		movement=Vector2.ZERO
	if dimension=="2d":
		worker.move_character(delta,Vector2((movement.x-movement.y)*8,(movement.x+movement.y)*4).normalized()); worker._update_animation(delta)
	else: worker.move_character(delta,Vector3(movement.x,0,movement.y))
	crew["stalled"]=crew["stalled"]+delta if not movement.is_zero_approx() and worker_point(worker).distance_to(point)<.001 else 0.0
	if crew["stalled"]>2: block(crew,"Worker route obstructed; clear the area and restart services")
	return crew["walk_index"]>=path.size()

func at_site(crew: Dictionary) -> bool:
	var worker: Node=crew["worker"]
	var clear: bool=worker.clear_at(worker.global_position) if dimension=="2d" else worker.clear_at(worker.global_transform,true)
	var target: Vector2=dispatch.plan["targets"][crew["job"]["target"]]["point"]
	if not clear or worker_point(worker).distance_to(target)>=SITE_DISTANCE or dimension=="3d" and absf(worker.position.y-helper.surface(target)["height"])>=.5: return false
	var exclusions: Array[RID]=[worker.get_rid()]
	if is_instance_valid(exploration) and is_instance_valid(exploration.player): exclusions.append(exploration.player.get_rid())
	var raw: Array=Traffic.world(target,dimension)
	if dimension=="2d":
		var goal: Vector2=helper.container.to_global(Vector2(raw[0],raw[1]))
		if goal.distance_squared_to(worker.global_position)<.0001: return true
		var query:=PhysicsRayQueryParameters2D.create(worker.global_position,goal,1,exclusions)
		return worker.get_world_2d().direct_space_state.intersect_ray(query).is_empty()
	var goal: Vector3=helper.container.to_global(Vector3(raw[0],0,raw[2])); goal.y=worker.global_position.y+.25
	var start: Vector3=worker.global_position+Vector3.UP*.25
	if start.distance_squared_to(goal)<.0001: return true
	var query:=PhysicsRayQueryParameters3D.create(start,goal,1,exclusions)
	return worker.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func block(crew: Dictionary,reason: String) -> void:
	crew["job"]["state"]="blocked"; crew["job"]["reason"]=reason; crew["vehicle"]["speed"]=0; release_gate(crew)
	crew["worker"].velocity=Vector2.ZERO if dimension=="2d" else Vector3.ZERO

func automatic_request() -> void:
	var targets: Array=dispatch.plan["targets"].keys(); targets.sort()
	if targets.is_empty(): automatic_notice="Add eligible neighborhood buildings for service visits."; return
	for attempt in 16:
		var uid: String=targets[random.randi_range(0,targets.size()-1)]
		var kinds: Array=dispatch.plan["targets"][uid]["kinds"]
		var kind: String=kinds[random.randi_range(0,kinds.size()-1)]
		if not Plan.choose(dispatch.plan,kind,uid)["ok"]: continue
		var result: Dictionary=dispatch.request(kind,uid)
		if result["ok"] and not result["existing"]: automatic_notice=""; return
	automatic_notice="No new reachable automatic visit; inspect coverage or pending requests."

func step(delta: float) -> void:
	if not active or paused or dispatch.plan.is_empty() or not dispatch.plan["settings"]["enabled"] or not is_finite(delta) or delta<=0: return
	route_queue.step(24,500)
	var remaining: float=minf(delta,.25)
	while remaining>.00001:
		var tick: float=minf(remaining,1.0/60); remaining-=tick; advance(tick)

func advance(delta: float) -> void:
	elapsed+=delta; auto_time+=delta
	if dispatch.plan["settings"]["automatic"] and auto_time>=dispatch.plan["settings"]["interval"]: auto_time=0; automatic_request()
	dispatch.dispatch(2)
	for job in dispatch.jobs:
		if job["state"]=="outbound" and not crews.has(job["id"]): spawn_crew(job)
	refresh_links()
	var people: Array[Vector2]=helper.pedestrian_points()
	for crew in crews.values():
		if crew["job"]["state"]=="working" and not at_site(crew): block(crew,"Worker has left the service approach")
	dispatch.work(delta)
	for id in crews.keys():
		var crew: Dictionary=crews[id]; var job: Dictionary=crew["job"]
		if job["state"]=="cancelled": remove_crew(id); continue
		if job["state"] in ["complete","blocked"]: continue
		match crew["stage"]:
			"outbound":
				if drive(crew,delta,people): begin_walk(crew,dispatch.plan["targets"][job["target"]]["point"],"walking_in")
			"walking_in":
				job["reason"]="Worker approaching site"
				var finished: bool=walk(crew,delta)
				if job["state"]!="blocked":
					if at_site(crew):
						dispatch.arrive(job); crew["stage"]="working"; crew["worker"].velocity=Vector2.ZERO if dimension=="2d" else Vector3.ZERO
					elif finished: block(crew,"Worker cannot reach the actual service approach")
			"working":
				if dimension=="2d": crew["worker"].action="idle"; crew["worker"]._update_animation(delta)
				else:
					for limb in crew["worker"].limbs: limb.rotation=Vector3.ZERO
					crew["worker"].limbs[0].rotation.x=-.6+sin(elapsed*4)*.2
				if job["state"]=="returning": begin_walk(crew,crew["vehicle"]["point"]+Vector2(-crew["vehicle"]["heading"].y,crew["vehicle"]["heading"].x)*.8,"walking_out")
			"walking_out":
				if walk(crew,delta) and job["state"]!="blocked":
					begin_road_return(crew)
			"returning":
				if drive(crew,delta,people) and crew["vehicle"]["point"].distance_to(crew["home"])<.4:
					dispatch.returned(job); crew["vehicle"]["speed"]=0; crew["vehicle"]["actor"].visible=false
					if target_owners.get(job["target"])==job["id"]: target_owners.erase(job["target"])

func remove_crew(id: String) -> void:
	if not crews.has(id): return
	var crew: Dictionary=crews[id]; release_gate(crew); route_queue.cancel(crew["vehicle"]["id"])
	if target_owners.get(crew["job"]["target"])==id: target_owners.erase(crew["job"]["target"])
	if is_instance_valid(crew["vehicle"]["actor"]): crew["vehicle"]["actor"].free()
	if is_instance_valid(crew["worker"]):
		if is_instance_valid(traffic): traffic.pedestrians.erase(crew["worker"])
		helper.pedestrians.erase(crew["worker"]); crew["worker"].free()
	crews.erase(id)

func reset() -> void:
	for id in crews.keys(): remove_crew(id)
	if is_instance_valid(traffic): traffic.external_vehicles.clear()
	route_queue.clear_requests(); helper.reset(); dispatch.reset(); site_stops.clear(); home_cache.clear(); target_owners.clear(); signature=0; elapsed=0; auto_time=0; automatic_notice=""; message=""; hud_uid=""
	if is_instance_valid(panel): panel.hide()

func _physics_process(delta: float) -> void: step(delta)
func _process(delta: float) -> void:
	ui_elapsed+=delta
	if not active:
		if is_instance_valid(panel): panel.hide()
		return
	if ui_elapsed>=.15: ui_elapsed=0; update_ui()
func _exit_tree() -> void: reset()
