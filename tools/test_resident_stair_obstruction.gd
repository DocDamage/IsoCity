extends "res://tools/test_resident_stair_routines.gd"
var obstructed: Dictionary={}
func facts_path() -> String:return "res://output/verification/asset_expansion/I14/stair_obstruction_facts.json"
func tick() -> void:
	await super.tick()
	var mode: String=citizens.dimension;var world: Node=studio.worlds[mode];var visit: Node=world.exploration
	if obstructed.has(mode) or not visit.interior:return
	var held: Array=citizens.activities.scheduler.jobs.values().filter(func(job: Dictionary):return job.has("stair") and job["stair"]["progress"]>.25 and job["stair"]["progress"]<.4)
	if held.is_empty():return
	obstructed[mode]=true
	var job: Dictionary=held[0];var token: int=job["link_token"];var building: String=visit.interior_uid;var body: Node=citizens.residents.filter(func(resident: Dictionary):return resident["id"]==job["resident"])[0]["actor"];var obstacle: Node
	if mode=="3d":
		obstacle=StaticBody3D.new();obstacle.collision_layer=2;visit.interior.floor_stack.add_child(obstacle);obstacle.position=body.position+Vector3(0,.9,-.8);var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(1.55,2,.3);shape.shape=box;obstacle.add_child(shape)
	else:
		obstacle=StaticBody2D.new();obstacle.collision_layer=1;visit.room_world().objects.add_child(obstacle);var leg: Dictionary=job["legs"][job["leg"]];var heading: Vector2=(Vector2(leg["to"].x,leg["to"].y)-body.position).normalized();obstacle.position=body.position+heading*30;var shape:=CollisionShape2D.new();var box:=RectangleShape2D.new();box.size=Vector2(50,18);shape.shape=box;shape.rotation=heading.angle()+PI*.5;obstacle.add_child(shape)
	await settle()
	for frame in 300:await super.tick()
	check(job["link_token"]==token and job.has("stair") and job["stair"].get("blocked",false) and job["stair"]["progress"]<.55,"An actual blocked native flight retains its capacity and reports obstruction without timer completion: "+mode+" "+str(citizens.activities.history))
	var point: Vector3=job["position"];var body_id: int=body.get_instance_id();visit.leave_interior();await settle()
	for frame in 40:await super.tick()
	check(job["position"]==point and job["link_token"]==token and not visit.interior,"Blocked flight remains blocked while its room is unrendered: "+mode)
	world.player.teleport_to(visit.entrance(world.instances[building]));studio.control_settings.execute("interact");await settle();world.player.teleport_to(Vector2(128,0) if mode=="2d" else Vector3(5,.2,4));facts[mode]["previous"].clear()
	check(body.get_instance_id()==body_id and citizens.activities.scheduler.jobs[job["resident"]]["link_token"]==token,"Reopening the now-clear flight resumes the same body and ownership: "+mode)
func after_completed(doc: RefCounted,mode: String) -> void:
	check(obstructed.get(mode,false),"The fixture actually obstructs a live native flight: "+mode)
	await super.after_completed(doc,mode)
