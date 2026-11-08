extends Node
const Plan=preload("res://scripts/builder/driving_plan.gd")
const Terrain=preload("res://scripts/builder/terrain_plan.gd")
const Instance=preload("res://scripts/builder/asset_instance.gd")
const CyclePose=preload("res://scripts/builder/cycling_pose.gd")
var rider_pose=CyclePose.new()
var rider: Node
var course: Node
var preferred_landing: Variant
var exploration: Node
var control_input: Callable
var active: Dictionary={}
var parked: Dictionary={}
var saved: Dictionary={}
var speed: float=0
var notice: String=""
var notice_time: float=0
var heights: Dictionary={}
var waters: Dictionary={}
var traffic: Node
var business_clock: Node
var delivery=preload("res://scripts/builder/delivery_runtime.gd").new()
var construction: Node
var delivery_view: Node
var delivery_key: String="H"
var delivery_cancel_key: String="Shift+H"
var care=preload("res://scripts/builder/vehicle_service_runtime.gd").new()
var care_view: Node
var last_care_uid: String=""
var care_key: String="B"
var care_cancel_key: String="Shift+B"
var cached_frame: int=-1
var cached_vehicles: Array[Dictionary]=[]

func operator() -> Node:
	return rider if is_instance_valid(rider) else exploration.player

func cycling() -> bool:
	return active.get("profile",{}).get("cycle",false)

func configure_care(data: Dictionary,instances: Dictionary) -> void:
	care.supply_requirement=charger_power_reason
	care.configure(data,exploration.library,instances,exploration.dimension)
	if not is_instance_valid(care_view) and (not care.vehicles.is_empty() or not care.bays.is_empty()):
		care_view=load("res://scripts/builder/vehicle_service_view.gd").new()
		care_view.driver=self
		add_child(care_view)

func charger_power_reason(uid: String) -> String:
	if not is_instance_valid(exploration) or not is_instance_valid(exploration.power): return ""
	return exploration.power.requirement(uid,"charger")

func configure_delivery(data: Dictionary,instances: Dictionary) -> void:
	var revision: int=delivery.routes.revision
	var contract: Dictionary={}
	if not is_instance_valid(construction) and preload("res://scripts/builder/construction_plan.gd").enabled(data):
		construction=preload("res://scripts/builder/construction_runtime.gd").new()
		construction.driver=self
		add_child(construction)
		delivery.cargo_delivered.connect(construction.receive)
		delivery.construction_haul_cancelled.connect(construction.haul_cancelled)
	if is_instance_valid(construction): contract=construction.configure(data)
	delivery.configure(data,exploration.library,instances,contract)
	if delivery.routes.revision!=revision or delivery.job.is_empty(): delivery.release_gate(traffic)
	if not is_instance_valid(delivery_view) and (is_instance_valid(construction) or not delivery.sites.is_empty() and not delivery.vehicles.is_empty()):
		delivery_view=load("res://scripts/builder/delivery_view.gd").new()
		delivery_view.driver=self
		add_child(delivery_view)

func delivery_pose() -> Dictionary:
	if active.is_empty(): return {}
	var uid: String=active["item"]["uid"]
	if not delivery.vehicles.has(uid): return {}
	var point: Vector2=active["point"]
	return {"point":point,"speed":speed,"extent":active["extent"],"height":surface(point)["height"]}

func delivery_hour() -> float:
	return business_clock.hour if is_instance_valid(business_clock) else 7.0

func request_delivery() -> bool:
	if not care_visible() or active.is_empty(): return false
	var uid: String=active["item"]["uid"]
	if care.jobs.has(uid): return delivery.fail("Finish vehicle care before handling cargo.")
	if not clear_pose(active["point"],active["yaw"]): return delivery.fail("Clear the vehicle before handling cargo.")
	return delivery.request(uid,delivery_pose(),delivery_hour())

func cancel_delivery() -> void:
	if not care_visible(): return
	if not delivery.job.is_empty(): delivery.cancel()
	elif is_instance_valid(construction): construction.cancel()
	delivery.release_gate(traffic)

func step_deliveries(delta: float) -> void:
	if not care_visible() or delivery.job.is_empty(): return
	var uid: String=active["item"]["uid"] if not active.is_empty() else ""
	delivery.step(delta,uid,delivery_pose(),delivery_hour())
	if delivery.job.is_empty(): delivery.release_gate(traffic)

func care_snapshot(uid: String) -> Dictionary:
	if not care.vehicles.has(uid): return {}
	var node: Node=exploration.instances.get(uid)
	if not is_instance_valid(node) or not node.is_visible_in_tree(): return {}
	var item: Dictionary=care.vehicles[uid]["item"]
	var parked_pose: Dictionary=parked.get(uid,{})
	var occupied: bool=not active.is_empty() and active["item"]["uid"]==uid
	var point: Vector2=active["point"] if occupied else parked_pose.get("point",Plan.center(item,exploration.library,exploration.dimension))
	var angle: float=active["yaw"] if occupied else parked_pose.get("yaw",Plan.yaw(item))
	return {"point":point,"heading":Plan.heading(angle),"extent":Plan.dimensions(item,exploration.library,exploration.dimension),"speed":speed if occupied else 0.0}

func care_visible() -> bool:
	return is_instance_valid(exploration) and exploration.enabled and not exploration.interior and exploration.editor_scope.is_empty() and not (exploration.photo and exploration.photo.active)

func care_uid() -> String:
	if not active.is_empty(): return active["item"]["uid"]
	if care.jobs.has(last_care_uid) and is_instance_valid(exploration.player):
		var pose: Dictionary=care_snapshot(last_care_uid)
		var position: Variant=exploration.get_parent().to_local(exploration.player.global_position)
		var player_point: Vector2=care.Plan.metric(position,exploration.dimension)
		if not pose.is_empty() and player_point.distance_to(pose["point"])<6: return last_care_uid
	return ""

func request_vehicle_service() -> bool:
	if not care_visible() or active.is_empty(): return false
	var uid: String=active["item"]["uid"]
	if delivery.job.get("vehicle")==uid and (delivery.locked(uid) or (delivery.job.get("phase")=="routing" and delivery.job.get("resume") in ["loading","unloading"])): return false
	if not care.vehicles.has(uid):
		notice="Enable vehicle care for this vehicle in Build."
		notice_time=4
		return false
	var pose: Dictionary=care_snapshot(uid)
	var bay: Dictionary=care.nearby(pose)
	if not bay.is_empty() and not clear_pose(pose["point"],active["yaw"]):
		care.failure(uid,"Clear space around the vehicle before service.")
		return false
	var result: Dictionary=care.request(uid,bay.get("uid",""),pose)
	if result["ok"]: last_care_uid=uid
	return result["ok"]

func cancel_vehicle_service() -> void:
	if not care_visible(): return
	care.cancel(care_uid())

func step_services(delta: float) -> void:
	if care_visible() and not care.jobs.is_empty(): care.step(delta,care_snapshot)

func vehicle_states() -> Array[Dictionary]:
	var frame: int=Engine.get_physics_frames()
	if frame==cached_frame: return cached_vehicles
	cached_frame=frame; cached_vehicles=[]
	if not is_instance_valid(exploration) or exploration.interior or not exploration.editor_scope.is_empty(): return cached_vehicles
	for item in exploration.records:
		if Plan.profile(item).is_empty(): continue
		var node: Node=exploration.instances.get(item["uid"])
		if not is_instance_valid(node) or not node.is_visible_in_tree(): continue
		var state: Dictionary=parked.get(item["uid"],{}); var extent: Vector2=Plan.dimensions(item,exploration.library,exploration.dimension)
		var occupied: bool=not active.is_empty() and active["item"]["uid"]==item["uid"]
		cached_vehicles.append({"id":"drive:"+item["uid"],"actor":node,"asset":item["asset"],"point":state.get("point",Plan.center(item,exploration.library,exploration.dimension)),"heading":Plan.heading(state.get("yaw",Plan.yaw(item))),"half_width":extent.x,"half_length":extent.y,"speed":absf(speed) if occupied else 0.0,"phase":"drive" if occupied else "parked","status":"Player vehicle"})
	if is_instance_valid(course): cached_vehicles.append_array(course.occupants())
	return cached_vehicles

func prompt(candidate: Dictionary={}) -> String:
	if cycling():
		return "E · Dismount · %.1f m/s · Space brakes"%absf(speed)+course.guide_hint()+(" · "+notice if notice_time>0 else "")
	if not active.is_empty(): return "E · Exit vehicle · %.1f m/s · Move forward/back · Left/right steer · Space brakes"%absf(speed)+(" · "+notice if notice_time>0 else "")
	var verb: String="Mount " if candidate.get("profile",{}).get("cycle",false) else "Drive "
	var text: String="E · "+verb+str(candidate["item"].get("name",candidate["item"]["asset"].get_slice(":",1))).replace("_"," ") if not candidate.is_empty() else ""
	return text+(" · "+notice if notice_time>0 else "")
func nearby(only_uid: String="") -> Dictionary: return Plan.nearby(exploration,parked,only_uid)
func colliders(node: Node) -> Array:
	var result: Array=[]
	for child in [node]+node.find_children("*","CollisionObject2D" if exploration.dimension=="2d" else "CollisionObject3D",true,false):
		if child is CollisionObject2D or child is CollisionObject3D: result.append({"node":child,"layer":child.collision_layer,"mask":child.collision_mask})
	return result
func restore_collisions(state: Dictionary) -> void:
	for entry in state.get("colliders",[]):
		if is_instance_valid(entry["node"]): entry["node"].collision_layer=entry["layer"]; entry["node"].collision_mask=entry["mask"]
func interact(candidate: Dictionary={}) -> bool:
	if not active.is_empty(): return exit_vehicle()
	if candidate.is_empty(): return false
	if candidate["profile"].get("cycle",false):
		var issue: String=CyclePose.support(operator(),candidate["profile"])
		if issue.is_empty(): issue=course.mount_reason(candidate)
		if not issue.is_empty():
			notice=issue; notice_time=5; return false
	var item: Dictionary=candidate["item"]; var uid: String=item["uid"]; var node: Node=candidate["node"]
	if not parked.has(uid):
		parked[uid]={"node":node,"transform":node.transform,"item":item.duplicate(true),"point":candidate["point"],"yaw":candidate["yaw"],"colliders":colliders(node),"terrain_visual":node.terrain_visual_offset if "terrain_visual_offset" in node else Vector2.ZERO,"terrain_height":node.get_meta("terrain_height",0.0)}
	active=candidate.duplicate(false); active["point"]=parked[uid]["point"]; active["yaw"]=parked[uid]["yaw"]
	heights=Terrain.lookup(candidate["data"]); waters=Terrain.lookup(candidate["data"],true)
	var unsupported: bool=absf(float(item["position"][2]))>.35 if exploration.dimension=="2d" else absf(float(node.position.y)+(Plan.Roads.bounds_for(exploration.library,item["asset"]).position.y*float(item["scale"]) if item["asset"].begins_with("3d:") else 0.0)-float(ride_surface(active["point"])["height"]))>.5
	if unsupported: active={}; notice="Vehicle needs a supported road or terrain surface."; notice_time=5; return false
	var obstruction: String=terrain_reason(active["point"],active["yaw"])
	if not obstruction.is_empty(): active={}; notice=obstruction; notice_time=5; return false
	if cycling() and not clear_pose(active["point"],active["yaw"]):
		active={}; notice="Clear space around the cycle before mounting."; notice_time=5; return false
	var player: Node=operator()
	if cycling():
		rider_pose.capture(player)
		player.set_meta("cycling_rider",true)
	saved={"position":player.global_position,"visible":player.visible,"physics":player.is_physics_processing(),"layer":player.collision_layer,"mask":player.collision_mask}
	if exploration.dimension=="2d": saved["terrain_height"]=player.get_meta("terrain_height",0.0); saved["terrain_visual"]=player.terrain_visual_offset
	if "selection" in active["world"] and is_instance_valid(active["world"].selection):
		saved["selection"]=active["world"].selection; saved["selection_visible"]=active["world"].selection.visible; active["world"].selection.hide()
	for entry in parked[uid]["colliders"]:
		if is_instance_valid(entry["node"]): entry["node"].collision_layer=0; entry["node"].collision_mask=0
	player.visible=false; player.collision_layer=0; player.collision_mask=0; player.set_physics_process(false); player.velocity=Vector2.ZERO if exploration.dimension=="2d" else Vector3.ZERO
	speed=0; notice=""
	if care.vehicles.has(uid):
		care.open_wallet()
		last_care_uid=uid
	pose(); return true
func held(id: String) -> bool:
	if control_input.is_valid(): return control_input.call(id)
	match id:
		"move_up": return Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)
		"move_down": return Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)
		"move_left": return Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)
		"move_right": return Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)
		"jump": return Input.is_physical_key_pressed(KEY_SPACE)
	return false
func _physics_process(delta: float) -> void:
	notice_time=maxf(0,notice_time-delta)
	step_services(delta)
	step_deliveries(delta)
	if exploration.photo and exploration.photo.active: return
	if active.is_empty(): return
	var uid: String=active["item"]["uid"]
	if not exploration.enabled or exploration.interior or not is_instance_valid(active["node"]) or not active["node"].is_visible_in_tree() or exploration.instances.get(uid)!=active["node"] or active["item"]!=parked[uid]["item"]:
		reset(); return
	var input := Vector2(float(held("move_right"))-float(held("move_left")),float(held("move_up"))-float(held("move_down")))
	var brake: bool=held("jump")
	if cycling() and course.step_guide(self,delta,input,brake): return
	step(delta,input,brake)
func step(delta: float,input: Vector2,brake: bool=false) -> void:
	if active.is_empty(): return
	delta=clampf(delta,0,.1); input=input.limit_length(1)
	var uid: String=active["item"]["uid"]
	if care.locked(uid) or delivery.locked(uid):
		speed=0
		return
	var available: float=care.energy_limit(uid)
	if available<=.00001:
		speed=0
		if not input.is_zero_approx():
			notice="No energy left in this vehicle."
			notice_time=2
		return
	var previous: Vector2=active["point"]
	var profile: Dictionary=active["profile"]; var throttle: float=input.y
	var target: float=throttle*(profile["max_speed"] if throttle>=0 else profile["reverse_speed"])*care.performance(uid)
	var rate: float=profile["acceleration"] if not is_zero_approx(throttle) and (is_zero_approx(speed) or signf(speed)==signf(throttle)) else profile["braking"]
	if brake: target=0; rate=profile["braking"]
	elif is_zero_approx(throttle): rate=2
	speed=move_toward(speed,target,rate*delta)
	var turn: float=input.x*profile["steering"]*clampf(absf(speed)/2,0,1)*signf(speed)*delta
	var angle: float=active["yaw"]+turn
	if not clear_pose(active["point"],angle) or (cycling() and not course.on_course(active,active["point"],angle)): angle=active["yaw"]
	advance_motion(clampf(speed*delta,-available,available),angle)
	if not delivery.job.is_empty(): delivery.clear_abandoned_gate(traffic,active["point"])
	care.travelled(uid,previous.distance_to(active["point"]))
	if care.energy_limit(uid)<=.00001: speed=0
	pose(delta)

func advance_motion(travel: float,angle: float) -> bool:
	if is_zero_approx(travel):
		active["yaw"]=angle
		parked[active["item"]["uid"]]["yaw"]=angle
		return true
	var uid: String=active["item"]["uid"]
	var successful: bool=true
	var count: int=maxi(1,ceili(absf(travel)/.2)); var distance: float=travel/count
	for index in count:
		var destination: Vector2=active["point"]+Plan.heading(angle)*distance
		var reason: String=terrain_reason(destination,angle)
		if reason.is_empty() and is_instance_valid(course): reason=course.reason(self,destination,angle)
		if reason.is_empty(): reason=traffic_reason(destination,angle)
		if not reason.is_empty(): speed=0; notice=reason; notice_time=3; successful=false; break
		var fraction: float=motion_fraction(active["point"],destination,angle)
		if cycling() and fraction>=.999:
			var cycle_gate: String=course.gate_reason(self,destination)
			if not cycle_gate.is_empty(): speed=0; notice=cycle_gate; notice_time=3; successful=false; break
		if fraction>0 and not delivery.job.is_empty():
			var gate: String=delivery.gate_reason(traffic,active["world"],uid,active["point"],active["point"].lerp(destination,fraction))
			if not gate.is_empty(): speed=0; notice=gate; notice_time=3; successful=false; break
		active["point"]=active["point"].lerp(destination,maxf(0,fraction-.001) if fraction<1 else 1)
		if fraction<1: speed=0; notice="Vehicle blocked · reverse or steer around the obstacle."; notice_time=3; successful=false; break
	active["yaw"]=angle; parked[uid]["point"]=active["point"]; parked[uid]["yaw"]=angle
	return successful
func traffic_reason(point: Vector2,angle: float) -> String:
	if not is_instance_valid(traffic): return ""
	var others: Array=traffic.vehicles+traffic.external_vehicles
	if is_instance_valid(course): others.append_array(course.occupants())
	if is_instance_valid(traffic.transit): others.append_array(traffic.transit.vehicle_states())
	var forward: Vector2=Plan.heading(angle); var right:=Vector2(forward.y,-forward.x); var extent: Vector2=active["extent"]
	for other in others:
		if not is_instance_valid(other.get("actor")) or other["actor"]==active["node"] or not other["actor"].is_visible_in_tree(): continue
		var axis: Vector2=other.get("heading",Vector2.DOWN); var side:=Vector2(axis.y,-axis.x); var relative: Vector2=other["point"]-point; var separate: bool=false
		for normal in [axis,side,forward,right]:
			var reach: float=other.get("half_length",1.3)*absf(normal.dot(axis))+other.get("half_width",.55)*absf(normal.dot(side))+extent.y*absf(normal.dot(forward))+extent.x*absf(normal.dot(right))+.15
			if absf(relative.dot(normal))>=reach: separate=true; break
		if not separate: return "Traffic ahead · brake or steer around it."
	for actor in traffic.pedestrians:
		if not is_instance_valid(actor) or actor==operator() or actor.has_meta("cycling_rider") or not actor.is_visible_in_tree(): continue
		var position: Variant=active["world"].to_local(actor.global_position); var relative: Vector2=Plan.Traffic.metric([position.x,position.y,0] if exploration.dimension=="2d" else [position.x,position.y,position.z],exploration.dimension)-point
		if absf(relative.dot(forward))<extent.y+.4 and absf(relative.dot(right))<extent.x+.4: return "Pedestrian ahead · wait for a clear route."
	return ""
func surface(point: Vector2) -> Dictionary:
	return Terrain.sample(active["data"],point,heights) if Terrain.settings(active["data"])["enabled"] else {"height":0.0,"normal":Vector3.UP}
func ride_surface(point: Vector2) -> Dictionary:
	var ground: Dictionary=surface(point)
	if exploration.dimension!="3d": return ground
	var world: Node3D=active["world"]; var height: float=ground["height"]
	var ray:=PhysicsRayQueryParameters3D.create(world.to_global(Vector3(point.x,height+.45,point.y)),world.to_global(Vector3(point.x,height-.5,point.y)),3,excluded())
	var hit: Dictionary=operator().get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty() and hit["normal"].dot(world.global_basis.y.normalized())>.939693:
		return {"height":world.to_local(hit["position"]).y,"normal":world.global_basis.inverse()*hit["normal"]}
	return ground
func terrain_reason(point: Vector2,angle: float) -> String:
	if cycling() and absf(float(ride_surface(point)["height"])-float(ride_surface(active["point"])["height"]))>.17:
		return "Curb or step ahead · dismount to walk."
	if not Terrain.settings(active["data"])["enabled"]: return ""
	var center: Dictionary=surface(point); var forward: Vector2=Plan.heading(angle); var right:=Vector2(forward.y,-forward.x); var extent: Vector2=active["extent"]
	for offset in [Vector2.ZERO,right*extent.x+forward*extent.y,right*extent.x-forward*extent.y,-right*extent.x+forward*extent.y,-right*extent.x-forward*extent.y]:
		var at: Vector2=point+offset; var ground: Dictionary=surface(at)
		if ground["normal"].y<.939693: return "Too steep to drive · flatten the bank or choose another route."
		var water: Variant=Terrain.water_level(active["data"],at,heights,waters)
		if water!=null and float(water)-ground["height"]>.26: return "Deep water · drive along a dry route."
		if absf(float(ground["height"])-float(center["height"]))>offset.length()*.364+.3: return "Terrain edge is too high for this vehicle."
	if absf(float(center["height"])-float(surface(active["point"])["height"]))>.35: return "Terrain edge is too high for this vehicle."
	return ""
func excluded() -> Array[RID]:
	var result: Array[RID]=[operator().get_rid()]
	for entry in parked[active["item"]["uid"]]["colliders"]:
		if is_instance_valid(entry["node"]): result.append(entry["node"].get_rid())
	return result
func query(point: Vector2,angle: float) -> Variant:
	var extent: Vector2=active["extent"]; var world: Node=active["world"]
	if exploration.dimension=="2d":
		var shape:=ConvexPolygonShape2D.new(); var points:=PackedVector2Array(); var forward: Vector2=Plan.heading(angle); var right:=Vector2(forward.y,-forward.x)
		for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]: points.append(world.global_transform.basis_xform(Plan.world(right*extent.x*corner.x+forward*extent.y*corner.y,"2d")))
		shape.points=points
		var parameters:=PhysicsShapeQueryParameters2D.new(); parameters.shape=shape; parameters.transform=Transform2D(0,world.to_global(Plan.world(point,"2d"))); parameters.collision_mask=1; parameters.exclude=excluded(); parameters.margin=.01
		return parameters
	var height: float=float(active["profile"]["height"])*float(active["item"]["scale"]) if cycling() else .6
	var center: float=float(ride_surface(point)["height"])+height*.5+.10 if cycling() else float(surface(point)["height"])+.55
	var shape:=BoxShape3D.new(); shape.size=Vector3(extent.x*2,height,extent.y*2)
	var parameters:=PhysicsShapeQueryParameters3D.new(); parameters.shape=shape; parameters.transform=world.global_transform*Transform3D(Basis(Vector3.UP,angle),Plan.world(point,"3d",center)); parameters.collision_mask=1; parameters.exclude=excluded(); parameters.margin=.01
	return parameters
func clear_pose(point: Vector2,angle: float) -> bool:
	var parameters: Variant=query(point,angle)
	return (operator().get_world_2d().direct_space_state.intersect_shape(parameters,1) if exploration.dimension=="2d" else operator().get_world_3d().direct_space_state.intersect_shape(parameters,1)).is_empty()
func motion_fraction(from: Vector2,to: Vector2,angle: float) -> float:
	if not clear_pose(from,angle): return 0
	var parameters: Variant=query(from,angle); var world: Node=active["world"]
	parameters.motion=world.global_transform.basis_xform(Plan.world(to-from,"2d")) if exploration.dimension=="2d" else world.global_basis*Vector3(to.x-from.x,0,to.y-from.y)
	var result: PackedFloat32Array=operator().get_world_2d().direct_space_state.cast_motion(parameters) if exploration.dimension=="2d" else operator().get_world_3d().direct_space_state.cast_motion(parameters)
	return result[0] if result.size()>0 else 0
func pose(delta: float=0.0) -> void:
	if active.is_empty(): return
	cached_frame=-1
	var node: Node=active["node"]; var item: Dictionary=active["item"]; var direction: String=Plan.direction(item,active["yaw"],active["profile"]); var size: float=item["scale"]
	Instance.orient(node,direction,active["data"].get("night",false))
	var point: Vector2=active["point"]-Plan.Roads.center_offset(exploration.library,item["asset"],direction,size,exploration.dimension)*(2 if exploration.dimension=="2d" else 1)
	var ground: Dictionary=ride_surface(active["point"]); var height: float=ground["height"]
	if exploration.dimension=="3d" and item["asset"].begins_with("3d:"): height-=Plan.Roads.bounds_for(exploration.library,item["asset"]).position.y*size
	node.position=Plan.world(point,exploration.dimension,height if exploration.dimension=="3d" else 0)
	if exploration.dimension=="3d" and item["asset"].begins_with("3d:"):
		var normal: Vector3=ground["normal"]; var heading: Vector2=Plan.heading(active["yaw"]); var forward:=Vector3(heading.x,0,heading.y); var right: Vector3=normal.cross(forward).normalized(); forward=right.cross(normal).normalized()
		node.basis=Basis(right,normal,forward).scaled(Vector3.ONE*size)
		var bounds: AABB=Plan.Roads.bounds_for(exploration.library,item["asset"]); var contact:=Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)
		node.position=Plan.world(active["point"],"3d",ground["height"])-node.basis*contact
	if exploration.dimension=="2d" and "terrain_visual_offset" in node:
		node.terrain_visual_offset=Vector2(0,-ground["height"]*8)/size; node.set_meta("terrain_height",ground["height"])
	var player: Node=operator()
	player.global_position=active["world"].to_global(Plan.world(active["point"],exploration.dimension,ground["height"]))
	player.visible=cycling(); player.collision_layer=0; player.collision_mask=0
	if exploration.dimension=="2d": player.set_meta("terrain_height",ground["height"])
	if cycling(): rider_pose.apply(player,active,Plan.heading(active["yaw"]),direction,delta,speed)
func exit_vehicle(force: bool=false,relocate: bool=true) -> bool:
	if active.is_empty(): return true
	if not is_instance_valid(operator()): active={}; saved={}; return true
	var player: Node=operator(); var destination: Variant=saved["position"]; var uid: String=active["item"]["uid"]; var landing_height: float=saved.get("terrain_height",0.0)
	if not force and relocate:
		if absf(speed)>.3: notice="Brake to a stop before exiting."; notice_time=3; return false
		var found: bool=false; var forward: Vector2=Plan.heading(active["yaw"]); var right:=Vector2(forward.y,-forward.x)
		for radius in [.65,1.2,2.0]:
			var offsets: Array=[right*(active["extent"].x+radius),-right*(active["extent"].x+radius),-forward*(active["extent"].y+radius),forward*(active["extent"].y+radius)]
			if preferred_landing is Vector2:
				var toward: Vector2=preferred_landing-active["point"]
				offsets.sort_custom(func(a: Vector2,b: Vector2)->bool: return a.dot(toward)>b.dot(toward))
			for offset in offsets:
				var point: Vector2=active["point"]+offset; var sample: Dictionary=surface(point); var world_point: Variant=active["world"].to_global(Plan.world(point,exploration.dimension,sample["height"]))
				if absf(float(sample["height"])-float(surface(active["point"])["height"]))>.5: continue
				var mask: int=player.collision_mask; player.collision_mask=saved["mask"]
				if exploration.dimension=="3d":
					var supported: Variant=world_point
					if cycling(): supported=course.walking_surface(player,world_point)
					elif "terrain_traversal" in active["world"]: supported=active["world"].terrain_traversal.start_candidate(point,world_point,false)
					if supported==null: player.collision_mask=mask; continue
					world_point=supported
				var clear: bool
				if exploration.dimension=="2d": clear=player.clear_at(world_point)
				else:
					var transform: Transform3D=player.global_transform; transform.origin=world_point; clear=player.clear_at(transform)
				var reachable: bool=clear and (course.exit_reachable(self,world_point) if cycling() else preload("res://scripts/builder/prop_plan.gd").reachable(exploration,active["node"],world_point))
				player.collision_mask=mask
				if reachable and (not player.terrain_position_safe.is_valid() or player.terrain_position_safe.call(world_point)):
					destination=world_point; landing_height=sample["height"]; found=true; break
			if found: break
		if not found: notice="Exit space is blocked · park beside a clear walking area."; notice_time=5; return false
	restore_collisions(parked[uid])
	if cycling():
		rider_pose.release(player)
		player.remove_meta("cycling_rider")
		if is_instance_valid(course): course.dismounted(self)
	preferred_landing=null
	player.visible=saved["visible"]; player.collision_layer=saved["layer"]; player.collision_mask=saved["mask"]; player.set_physics_process(saved["physics"])
	if is_instance_valid(saved.get("selection")):
		if saved["selection_visible"] and active["world"].has_method("show_selection"): active["world"].show_selection(uid)
		else: saved["selection"].visible=false
	if relocate: player.teleport_to(player.get_parent().to_local(destination))
	if exploration.dimension=="2d": player.set_meta("terrain_height",landing_height); player.terrain_visual_offset=saved["terrain_visual"] if force else Vector2(0,-landing_height*8)
	delivery.release_gate(traffic)
	active={}; saved={}; speed=0; return true
func reset() -> void:
	exit_vehicle(true)
	care.reset()
	delivery.release_gate(traffic)
	if is_instance_valid(construction): construction.reset()
	delivery.reset()
	last_care_uid=""
	for state in parked.values():
		if not is_instance_valid(state["node"]): continue
		state["node"].transform=state["transform"]; Instance.pose(state["node"],state["item"]); restore_collisions(state)
		if "terrain_visual_offset" in state["node"]: state["node"].terrain_visual_offset=state["terrain_visual"]
		state["node"].set_meta("terrain_height",state["terrain_height"])
	parked.clear(); heights.clear(); waters.clear(); cached_vehicles.clear(); cached_frame=-1; speed=0
func _exit_tree() -> void: reset()
