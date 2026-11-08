extends RefCounted

# The original body walks the native treads. This state belongs to the private
# itinerary and can be materialized after closing the transient room tree.
const Plan=preload("res://scripts/builder/resident_activity_plan.gd")
const State=preload("res://scripts/builder/resident_stair_state.gd")
const Presentation=preload("res://scripts/builder/resident_elevator_state.gd")
var view_ref: WeakRef
var states: Dictionary
func _init(view: RefCounted,shared_states: Dictionary) -> void:view_ref=weakref(view);states=shared_states

func cancel(identity: String) -> void:
	var view: RefCounted=view_ref.get_ref();var body: Node=view.attached.get(identity,{}).get("actor",weakref(null)).get_ref()
	if is_instance_valid(body) and body.has_meta("floor_travel_height"):body.remove_meta("floor_travel_height")
	states.erase(identity)

func materialize(job: Dictionary) -> bool:
	var view: RefCounted=view_ref.get_ref();var visit: Node=view.visit_ref.get_ref()
	if not is_instance_valid(visit) or not is_instance_valid(visit.interior) or visit.interior_uid!=job["building"] or job["leg"]>=job["legs"].size():return false
	var leg: Dictionary=job["legs"][job["leg"]];var stack: Node=visit.interior.floor_stack
	if leg["kind"]!="stairs" or not stack.heights.has(leg["floor"]) or not stack.heights.has(leg["next_floor"]):return false
	var snapshot: Dictionary=job.get("stair",State.initial(leg,stack.heights[leg["floor"]],stack.heights[leg["next_floor"]],job["position"]))
	if snapshot.get("link","")!=leg["link"] or snapshot.get("source","")!=leg["floor"] or snapshot.get("target","")!=leg["next_floor"]:return false
	var body: Node=view.actors.get(job["resident"],weakref(null)).get_ref();var world: Node=view.room_for(leg["floor"])
	if not is_instance_valid(world):world=visit.room_world()
	if not is_instance_valid(body) or not view.share_room(world):return false
	view.attach(job["resident"],body,world)
	var point: Vector3=snapshot["point"]
	if visit.dimension=="3d":
		var source: Node=stack.worlds[leg["floor"]];var global: Vector3=source.objects.to_global(point)
		body.reparent(stack,true);body.teleport_to(stack.to_local(global))
	else:body.teleport_to(Vector2(point.x,point.y))
	Presentation.restore_presentation(body,snapshot)
	states[job["resident"]]={"kind":"stairs","snapshot":snapshot.duplicate(true),"wait":2,"stalled":0.0}
	present(body,stack,states[job["resident"]]["snapshot"],visit.dimension)
	return true

func present(body: Node,stack: Node,snapshot: Dictionary,mode: String) -> void:
	body.visible=mode=="3d" or stack.current_floor in [snapshot["source"],snapshot["target"]]
	if mode=="2d":
		var elevation: float=lerpf(snapshot["source_height"],snapshot["target_height"],snapshot["progress"])-stack.heights[stack.current_floor]
		body.set_meta("floor_travel_height",elevation);body.terrain_visual_offset=Vector2(0,-elevation*8)

func step(job: Dictionary,leg: Dictionary,delta: float,speed: float) -> Dictionary:
	var view: RefCounted=view_ref.get_ref();var visit: Node=view.visit_ref.get_ref()
	if not is_instance_valid(visit) or not is_instance_valid(visit.interior) or visit.interior_uid!=job["building"]:return {"handled":false}
	var identity: String=job["resident"];var stack: Node=visit.interior.floor_stack;var mode: String=visit.dimension
	if not states.has(identity) and not materialize(job):return {"handled":true,"reason":"Waiting for the resident's stair flight to become available."}
	var state: Dictionary=states[identity];var snapshot: Dictionary=state["snapshot"];var body: Node=view.actors.get(identity,weakref(null)).get_ref()
	if not is_instance_valid(body):return {"handled":true,"error":"The original resident body is unavailable."}
	var result: Dictionary={"handled":true,"done":false,"position":snapshot["point"],"stair":snapshot,"reason":"Walking the stairs."}
	if state["wait"]>0:state["wait"]-=1;return result
	var point: Vector3
	if mode=="3d":
		var destination: Vector3=stack.worlds[leg["next_floor"]].objects.to_global(leg["to"]);var shift: Vector3=destination-body.global_position;shift.y=0
		var factor: float=minf(1.8*speed,shift.length()*6)/maxf(.001,body.move_speed)
		body.move_character(delta,shift.normalized()*factor);point=stack.worlds[leg["floor"]].objects.to_local(body.global_position)
	else:
		var shift: Vector2=Vector2(leg["to"].x,leg["to"].y)-body.position;var factor: float=minf(48*speed,shift.length()*6)/maxf(.001,body.move_speed)
		# The sprite flight is a flat collision corridor. Sweep it before moving
		# so slide response cannot steer the resident around its obstruction and
		# off the authored flight. Native 3D treads retain the walker's step sweeps.
		if body.test_move(body.global_transform,shift.normalized()*minf(shift.length(),48*speed*delta)):
			body.velocity=Vector2.ZERO;factor=0
		body.move_character(delta,shift.normalized()*factor);body._update_animation(delta);point=Vector3(body.position.x,body.position.y,0)
	var from: Vector2=Plan.metric(leg["from"],mode);var end: Vector2=Plan.metric(leg["to"],mode);var at: Vector2=Plan.metric(point,mode);var line: Vector2=end-from
	snapshot["progress"]=clampf((at-from).dot(line)/maxf(.001,line.length_squared()),0,1);snapshot["point"]=point;snapshot["presentation"]=Presentation.capture_presentation(body)
	present(body,stack,snapshot,mode);result["position"]=point
	if snapshot["progress"]>state.get("progress_mark",0.0)+.001:state["stalled"]=0.0;state["progress_mark"]=snapshot["progress"]
	else:state["stalled"]+=delta
	snapshot["blocked"]=state["stalled"]>3
	if snapshot["blocked"]:result["reason"]="The resident's stair flight is obstructed. Clear the flight to resume."
	var closest: Vector2=from+line*snapshot["progress"]
	# The projected sprite metric is sqrt(2) larger than authored stair width.
	var corridor_distance: float=at.distance_to(closest)*(sqrt(.5) if mode=="2d" else 1.0)
	if corridor_distance>float(leg["width"])*.5:result["error"]="The resident left the clear stair corridor.";return result
	var arrived: bool=at.distance_to(end)<.005
	if mode=="3d":arrived=arrived and absf(point.y-(snapshot["target_height"]-snapshot["source_height"]+leg["to"].y))<.3 and body.is_on_floor()
	if arrived:
		var world: Node=view.room_for(leg["next_floor"])
		if mode=="3d":body.reparent(world.objects,true);result["position"]=body.position
		else:
			body.remove_meta("floor_travel_height");body.terrain_visual_offset=Vector2.ZERO;result["position"]=leg["to"]
		result["done"]=true;states.erase(identity)
	return result
