extends Node3D

const Shapes=preload("res://scripts/builder/floor_stairs_3d.gd")
var controller: Node
var stack: Node3D
var actor: CharacterBody3D
var cabin: AnimatableBody3D
var cabin_gate: StaticBody3D
var stations: Dictionary={}
var own: Array[RID]=[]
var offset:=Vector3.ZERO
var width: float=1.2
var center:=Vector2.ZERO

func box(parent: Node3D,name: String,size: Vector3,point: Vector3,color: Color,visible_mesh: bool=true) -> StaticBody3D:
	var body: StaticBody3D=Shapes.box(parent,name,size,point,color); own.append(body.get_rid())
	if not visible_mesh: body.get_child(0).visible=false
	return body

func cabin_shape(size: Vector3,point: Vector3) -> void:
	var shape:=CollisionShape3D.new(); var volume:=BoxShape3D.new(); volume.size=size; shape.shape=volume; shape.position=point; cabin.add_child(shape)

func configure(runtime: Node) -> void:
	controller=runtime; stack=runtime.stack; actor=runtime.actor; width=float(runtime.link["width"]); center=Vector2(runtime.link["start"][0],runtime.link["start"][1]); position=Vector3(center.x,0,center.y)
	cabin=AnimatableBody3D.new(); cabin.name="Cabin"; cabin.collision_layer=2; cabin.sync_to_physics=false; add_child(cabin); own.append(cabin.get_rid())
	var floor_mesh:=MeshInstance3D.new(); var floor_box:=BoxMesh.new(); floor_box.size=Vector3(width+0.10,0.14,width+0.10); floor_mesh.mesh=floor_box; floor_mesh.position.y=-0.07
	var metal:=StandardMaterial3D.new(); metal.albedo_color=Color("a7b4bf"); metal.metallic=0.4; floor_mesh.material_override=metal; cabin.add_child(floor_mesh); cabin_shape(floor_box.size,floor_mesh.position)
	for side in [-1,1]:
		cabin_shape(Vector3(0.05,2.0,width+0.10),Vector3(side*(width*0.5+0.025),1,0))
		for z in [-1,1]:
			var post:=MeshInstance3D.new(); var mesh:=BoxMesh.new(); mesh.size=Vector3(0.05,2,0.05); post.mesh=mesh; post.material_override=metal; post.position=Vector3(side*(width*0.5+0.025),1,z*(width*0.5+0.025)); cabin.add_child(post)
		var rail:=MeshInstance3D.new(); var mesh:=BoxMesh.new(); mesh.size=Vector3(0.05,0.05,width+0.10); rail.mesh=mesh; rail.material_override=metal; rail.position=Vector3(side*(width*0.5+0.025),1.05,0); cabin.add_child(rail)
	cabin_shape(Vector3(width+0.10,2,0.05),Vector3(0,1,-width*0.5-0.025))
	cabin_shape(Vector3(width+0.10,0.06,width+0.10),Vector3(0,2.08,0))
	cabin_gate=box(cabin,"CabinGate",Vector3(width+0.08,1.95,0.05),Vector3(0,0.975,width*0.5+0.065),Color("576b7c"),false)
	var low: float=runtime.stops[0]["height"]; var high: float=runtime.stops[-1]["height"]+2.15
	for side in [-1,1]: box(self,"ShaftSide",Vector3(0.08,high-low,width+0.40),Vector3(side*(width*0.5+0.18),(high+low)*0.5,0),Color("465967"),false)
	box(self,"ShaftBack",Vector3(width+0.44,high-low,0.08),Vector3(0,(high+low)*0.5,-width*0.5-0.18),Color("465967"),false)
	for index in runtime.stops.size():
		var floor: Dictionary=runtime.stops[index]; var h: float=floor["height"]; var station:=Node3D.new(); station.name="Landing_"+floor["uid"]; add_child(station)
		var gate: StaticBody3D=box(station,"Gate",Vector3(width+0.26,2.0,0.08),Vector3(0,h+1,width*0.5+0.115),Color("607789"),false)
		var panels: Array=[]
		for side in [-1,1]:
			var panel:=MeshInstance3D.new(); var mesh:=BoxMesh.new(); mesh.size=Vector3(width*0.5+0.10,1.98,0.035); panel.mesh=mesh; panel.material_override=metal; panel.position=Vector3(side*width*0.25,h+1,width*0.5+0.115); station.add_child(panel); panels.append(panel)
			box(station,"Frame",Vector3(0.07,2.12,0.07),Vector3(side*(width*0.5+0.19),h+1.06,width*0.5+0.115),Color("425461"))
		box(station,"Header",Vector3(width+0.45,0.10,0.10),Vector3(0,h+2.1,width*0.5+0.115),Color("425461"))
		var bridge: StaticBody3D=box(station,"Threshold",Vector3(width+0.08,0.10,0.26),Vector3(0,h-0.05,width*0.5+0.17),Color("a7b4bf"))
		var label:=Label3D.new(); label.text="E · Elevator · "+str(floor["name"]).left(24); label.billboard=BaseMaterial3D.BILLBOARD_ENABLED; label.font_size=28; label.position=Vector3(0,h+2.35,width*0.5+0.2); station.add_child(label)
		stations[floor["uid"]]={"node":station,"gate":gate,"panels":panels,"bridge":bridge,"height":h}
		if index<runtime.stops.size()-1:
			var next: float=runtime.stops[index+1]["height"]
			box(self,"ShaftFront",Vector3(width+0.44,next-h-2.02,0.08),Vector3(0,(h+2.02+next)*0.5,width*0.5+0.18),Color("465967"),false)
	close_all()

func refresh_floor() -> void:
	for uid in stations:
		var shown: bool=stations[uid]["height"]<=stack.heights[stack.current_floor]+0.01
		for child in stations[uid]["node"].find_children("*","MeshInstance3D",true,false)+stations[uid]["node"].find_children("*","Label3D",true,false): child.visible=shown

func set_height(value: float) -> void:
	cabin.position.y=value

func actor_local() -> Vector3:
	return to_local(actor.global_position)

func fully_inside() -> bool:
	return passenger_inside(actor,stack.current_floor)

func passenger_inside(body: Node,uid: String) -> bool:
	if not body is CharacterBody3D or not stations.has(uid) or absf(stations[uid]["height"]-controller.height)>.15:return false
	var point: Vector3=to_local(body.global_position);var half: float=width*.5-float(body.capsule.shape.radius)+.004
	return absf(point.x)<=half and absf(point.z)<=half and absf(point.y-controller.height)<.15 and body.clear_at(body.global_transform,true)

func distance() -> float:
	if not stations.has(stack.current_floor): return INF
	var point: Vector3=actor_local(); var h: float=stations[stack.current_floor]["height"]
	return Vector2(point.x,point.z-width*0.5-0.6).length() if absf(point.y-h)<0.6 else INF

func near() -> bool:
	return fully_inside() or distance()<1.6

func capture_actor() -> void:
	offset=cabin.to_local(controller.occupant().global_position)

func carry_actor() -> void:
	var body: Node=controller.occupant();body.global_position=cabin.to_global(offset);body.velocity=Vector3.ZERO

func present_actor() -> void:
	pass

func release_actor() -> void:
	pass

func query(shape: Shape3D,pose: Transform3D,ignore_actor: bool) -> bool:
	var parameters:=PhysicsShapeQueryParameters3D.new(); parameters.shape=shape; parameters.transform=pose; parameters.collision_mask=3; parameters.margin=0.0001
	var excluded: Array[RID]=own.duplicate()
	if ignore_actor and is_instance_valid(controller.occupant()):excluded.append(controller.occupant().get_rid())
	parameters.exclude=excluded
	return get_world_3d().direct_space_state.intersect_shape(parameters,1).is_empty()

func doorway_clear(uid: String) -> bool:
	var body: Node=controller.occupant();var step: float=body.step_height if is_instance_valid(body) else actor.step_height
	var shape:=BoxShape3D.new(); shape.size=Vector3(width+0.10,1.8-step,0.14)
	return query(shape,global_transform*Transform3D(Basis.IDENTITY,Vector3(0,stations[uid]["height"]+0.94+step*.5,width*0.5+0.115)),controller.rider)

func can_move(value: float,carrying: bool) -> bool:
	var shape:=BoxShape3D.new(); shape.size=Vector3(width+0.20,2.27,width+0.20)
	return query(shape,global_transform*Transform3D(Basis.IDENTITY,Vector3(0,value+0.995,0)),carrying)

func close_all() -> void:
	cabin_gate.collision_layer=2
	for uid in stations:
		stations[uid]["gate"].collision_layer=2; stations[uid]["bridge"].collision_layer=0; stations[uid]["bridge"].visible=false; door_progress(uid,0)

func door_progress(uid: String,amount: float) -> void:
	var panels: Array=stations[uid]["panels"]
	for index in panels.size(): panels[index].position.x=(-1 if index==0 else 1)*(width*0.25+amount*(width*0.55+0.12))

func open_at(uid: String,amount: float) -> void:
	door_progress(uid,amount); stations[uid]["bridge"].visible=true; stations[uid]["bridge"].collision_layer=2
	if amount>=1: stations[uid]["gate"].collision_layer=0; cabin_gate.collision_layer=0

func prepare_arrival(_uid: String,_carrying: bool) -> void:
	pass

func arrival_step(_delta: float,uid: String,_carrying: bool) -> int:
	var body: Node=controller.occupant()
	if not is_instance_valid(body):return -1
	var pose: Transform3D=body.global_transform; pose.origin=to_global(Vector3(0,stations[uid]["height"]+0.03,width*0.5+0.95))
	if not preload("res://scripts/builder/floor_terrain_plan.gd").landing_allowed(stack.worlds[uid].terrain_traversal,pose.origin): return -1
	var ray:=PhysicsRayQueryParameters3D.create(pose.origin+Vector3.UP*.37,pose.origin-Vector3.UP*.43,2)
	var excluded: Array[RID]=own.duplicate(); excluded.append(body.get_rid()); ray.exclude=excluded
	var hit: Dictionary=get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or hit["normal"].dot(Vector3.UP)<cos(body.floor_max_angle) or absf(hit["position"].y-(pose.origin.y-.03))>body.step_height: return -1
	pose.origin.y=hit["position"].y+.03
	return 1 if query(body.clearance_shape,pose*body.capsule.transform,true) else -1
