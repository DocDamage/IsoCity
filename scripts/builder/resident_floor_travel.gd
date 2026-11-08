extends RefCounted

const Plan=preload("res://scripts/builder/resident_activity_plan.gd")
const ElevatorState=preload("res://scripts/builder/resident_elevator_state.gd")
var view_ref: WeakRef
var states: Dictionary={}
var stairs: RefCounted
func _init(view: RefCounted) -> void:
	view_ref=weakref(view);stairs=preload("res://scripts/builder/resident_stair_travel.gd").new(view,states)

func cabin_point(link: Dictionary,mode: String) -> Vector3:
	if mode=="3d":return Vector3(link["start"][0],.03,link["start"][1])
	var pixel: Vector2=preload("res://scripts/builder/grid_fit.gd").pixels(Vector2(link["start"][0],link["start"][1]));return Vector3(pixel.x,pixel.y,0)

func empty_snapshot(lift: Node,leg: Dictionary,mode: String,point: Vector3,body: Node) -> Dictionary:
	var value: Dictionary=ElevatorState.initial(lift.link,leg,mode,lift.stop_height(leg["floor"]),lift.stop_height(leg["next_floor"]),{"height":lift.height,"last_stop":lift.last_stop},point)
	if lift.phase!="idle":value["phase"]="calling";value["call_phase"]=lift.phase;value["elapsed"]=lift.elapsed;value["motion"]=lift.motion.duplicate(true);value["notice"]=lift.notice
	value["presentation"]=ElevatorState.capture_presentation(body)
	return value

func cancel(identity: String) -> void:
	if not states.has(identity):return
	var state: Dictionary=states[identity]
	if state.get("kind","")=="stairs":stairs.cancel(identity);return
	var lift: Node=state["lift"].get_ref()
	if is_instance_valid(lift):lift.end_passenger(state["token"])
	states.erase(identity)

func move_to(view: RefCounted,job: Dictionary,body: Node,destination: Vector3,delta: float,speed: float,floor_uid: String) -> Vector3:
	var mode: String="2d" if body is CharacterBody2D else "3d";var at: Vector3=Vector3(body.position.x,body.position.y,0) if mode=="2d" else body.position
	var proposal: Vector3=at.move_toward(destination,delta*(48 if mode=="2d" else 1.8)*speed);var walking: Dictionary=job.duplicate();walking["floor"]=floor_uid;walking["waypoint"]=destination
	return view.move(walking,proposal,delta)

func materialize(job: Dictionary) -> bool:
	if job.has("stair"):return stairs.materialize(job)
	var view: RefCounted=view_ref.get_ref();var visit: Node=view.visit_ref.get_ref();var snapshot: Dictionary=job.get("transport",{})
	if not ElevatorState.valid(snapshot) or not is_instance_valid(visit) or not is_instance_valid(visit.interior) or visit.interior_uid!=job["building"] or job["leg"]>=job["legs"].size():return false
	var leg: Dictionary=job["legs"][job["leg"]];var stack: Node=visit.interior.floor_stack
	if leg["kind"]!="elevator" or leg["link"]!=snapshot["link"] or leg["floor"]!=snapshot["source"] or leg["next_floor"]!=snapshot["target"] or not stack.lifts.has(leg["link"]):return false
	var lift: Node=stack.lifts[leg["link"]];var body: Node=view.actors.get(job["resident"],weakref(null)).get_ref()
	if not is_instance_valid(body) or lift.npc_token!=0 or lift.phase!="idle" or lift.view.fully_inside():return false
	var alighting: bool=snapshot["phase"]=="alighting";var empty: bool=snapshot["phase"] in ["calling","boarding"];var floor_uid: String=leg["next_floor"] if alighting else leg["floor"];var world: Node=view.room_for(floor_uid)
	if not is_instance_valid(world):world=visit.room_world()
	if not view.share_room(world):return false
	view.attach(job["resident"],body,world)
	if visit.dimension=="3d":
		var at: Vector3=world.objects.to_global(snapshot["point"]) if alighting or empty else lift.view.to_global(Vector3(snapshot["offset"].x,snapshot["height"]+snapshot["offset"].y,snapshot["offset"].z))
		body.teleport_to(world.objects.to_local(at))
	else:
		var at: Vector3=snapshot["point"] if alighting or empty else snapshot["offset"];body.teleport_to(Vector2(at.x,at.y))
	var restored: bool=lift.restore_empty_call(job["link_token"],snapshot) if empty else lift.restore_passenger(body,job["link_token"],snapshot)
	if not restored:view.detach(job["resident"]);return false
	ElevatorState.restore_presentation(body,snapshot)
	var state: Dictionary={"lift":weakref(lift),"token":job["link_token"],"phase":"waiting" if empty else "alighting" if alighting else "riding","logical":snapshot.get("point",Vector3.ZERO),"snapshot":snapshot.duplicate(true),"stalled":0.0}
	states[job["resident"]]=state
	if empty:
		body.visible=visit.dimension=="3d" or floor_uid==stack.current_floor;return true
	if alighting:lift.end_passenger(job["link_token"],true)
	elif visit.dimension=="3d":body.reparent(lift.view,true)
	else:lift.view.present_actor()
	body.visible=visit.dimension=="3d" or (floor_uid==stack.current_floor if alighting else absf(lift.height-stack.heights[stack.current_floor])<1.8)
	return true

func step(job: Dictionary,leg: Dictionary,delta: float,speed: float) -> Dictionary:
	if leg["kind"]=="stairs":return stairs.step(job,leg,delta,speed)
	var view: RefCounted=view_ref.get_ref();var visit: Node=view.visit_ref.get_ref()
	if leg["kind"]!="elevator" or not is_instance_valid(visit) or not is_instance_valid(visit.interior) or visit.interior_uid!=job["building"]:return {"handled":false}
	var identity: String=job["resident"];var stack: Node=visit.interior.floor_stack
	if not is_instance_valid(stack) or not stack.lifts.has(leg["link"]):return {"handled":true,"error":"The resident's elevator is unavailable."}
	var lift: Node=stack.lifts[leg["link"]];var body: Node=view.actors.get(identity,weakref(null)).get_ref();var mode: String=visit.dimension
	if not is_instance_valid(body):return {"handled":true,"error":"The original resident body is unavailable."}
	if not states.has(identity):
		if job.has("transport"):
			if not materialize(job):return {"handled":true,"reason":"Waiting for a clear elevator to restore this resident's trip."}
		else:
			var source_world: Node=view.room_for(leg["floor"])
			if not is_instance_valid(source_world):source_world=visit.room_world()
			view.attach(identity,body,source_world);states[identity]={"lift":weakref(lift),"token":job["link_token"],"phase":"waiting","logical":Vector3.ZERO,"stalled":0.0}
	var state: Dictionary=states[identity];var result: Dictionary={"handled":true,"done":false,"position":job["position"],"reason":"Waiting for the elevator car."}
	if state["phase"] in ["waiting","boarding"]:
		body.visible=mode=="3d" or stack.current_floor==leg["floor"]
		if lift.view.fully_inside():result["reason"]="Waiting for the player to leave the elevator cabin.";return result
		if lift.restoration_pending>0:return result
		if lift.npc_token!=0 or (lift.call_owner_token!=0 and lift.call_owner_token!=job["link_token"]):return result
		if lift.phase!="idle":
			if lift.call_owner_token==job["link_token"]:
				result["snapshot"]=empty_snapshot(lift,leg,mode,job["position"],body)
				if lift.phase=="blocked":result["reason"]=lift.notice;lift.retry_call(leg["floor"],job["link_token"])
			return result
		if lift.last_stop!=leg["floor"]:
			if lift.call_for_passenger(leg["floor"],job["link_token"]):result["snapshot"]=empty_snapshot(lift,leg,mode,job["position"],body)
			return result
		var source_world: Node=view.room_for(leg["floor"]);var unseen: bool=not is_instance_valid(source_world)
		var center: Vector3=cabin_point(lift.link,mode)
		if unseen:
			body.global_position=lift.view.global_position
		else:
			result["position"]=move_to(view,job,body,center,delta,speed,leg["floor"]);result["reason"]="Boarding the elevator."
			if Plan.metric(result["position"],mode).distance_to(Plan.metric(center,mode))>(.06 if mode=="3d" else .12):state["phase"]="boarding";result["snapshot"]=empty_snapshot(lift,leg,mode,result["position"],body);return result
		if not lift.begin_passenger(body,leg["floor"],leg["next_floor"],job["link_token"],unseen):return result
		if mode=="3d":body.reparent(lift.view,true)
		state["phase"]="riding"
	if state["phase"]=="riding":
		var status: Dictionary=lift.passenger_result(state["token"])
		if status["state"]=="missing":return {"handled":true,"error":"The reserved elevator passenger was removed."}
		state["snapshot"]=lift.snapshot_passenger(state["token"]);result["snapshot"]=state["snapshot"]
		if mode=="3d":result["position"]=view.room_for(leg["floor"]).objects.to_local(body.global_position)
		else:body.visible=absf(lift.height-stack.heights[stack.current_floor])<1.8
		result["reason"]="Travelling by elevator."
		if status["state"]=="blocked":result["reason"]=status["reason"];lift.retry_passenger(state["token"]);return result
		if status["state"]!="complete":return result
		var target_world: Node=view.room_for(leg["next_floor"])
		if is_instance_valid(target_world):body.reparent(target_world.objects,true)
		else:body.visible=false
		lift.end_passenger(state["token"],true);state["phase"]="alighting";state["logical"]=cabin_point(lift.link,mode)
	if state["phase"]=="alighting":
		var target_world: Node=view.room_for(leg["next_floor"]);var at: Vector3
		if is_instance_valid(target_world):at=move_to(view,job,body,leg["to"],delta,speed,leg["next_floor"])
		else:state["logical"]=state["logical"].move_toward(leg["to"],delta*48*speed);at=state["logical"]
		result.merge({"position":at,"floor":leg["next_floor"],"reason":"Leaving the elevator at the destination landing."},true)
		state["snapshot"]["phase"]="alighting";state["snapshot"]["point"]=at;state["snapshot"]["presentation"]=ElevatorState.capture_presentation(body);result["snapshot"]=state["snapshot"]
		if Plan.metric(at,mode).distance_to(Plan.metric(leg["to"],mode))<.04:result["done"]=true;lift.end_passenger(state["token"]);states.erase(identity)
	return result
