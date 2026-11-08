extends RefCounted

static func box(parent: Node3D,name: String,size: Vector3,position: Vector3,color: Color) -> StaticBody3D:
	var body:=StaticBody3D.new(); body.name=name; body.position=position; body.collision_layer=2; parent.add_child(body)
	var mesh:=MeshInstance3D.new(); var shape:=BoxMesh.new(); shape.size=size; mesh.mesh=shape
	var material:=StandardMaterial3D.new(); material.albedo_color=color; material.roughness=0.85; mesh.material_override=material; body.add_child(mesh)
	var collision:=CollisionShape3D.new(); var volume:=BoxShape3D.new(); volume.size=size; collision.shape=volume; body.add_child(collision)
	return body

static func build(parent: Node3D,link: Dictionary,heights: Dictionary) -> Node3D:
	var stair:=Node3D.new(); stair.name="Stairs_"+link["uid"]; parent.add_child(stair)
	var start:=Vector2(link["start"][0],link["start"][1]); var end:=Vector2(link["end"][0],link["end"][1]); var direction: Vector2=(end-start).normalized()
	var rise: float=heights[link["upper"]]-heights[link["lower"]]; var run: float=start.distance_to(end); var width: float=link["width"]
	stair.position=Vector3(start.x,heights[link["lower"]],start.y); stair.rotation.y=atan2(direction.x,direction.y)
	var count: int=ceili(rise/0.24); var tread: float=run/count; var step: float=rise/count
	for index in count:
		box(stair,"Tread_"+str(index),Vector3(width,step+0.10,tread+0.004),Vector3(0,(index+0.5)*step-0.05,(index+0.5)*tread),Color("a9957d") if index%2==0 else Color("bba58a"))
	box(stair,"UpperLanding",Vector3(width,0.16,0.8),Vector3(0,rise-0.08,run+0.4),Color("bba58a"))
	# Solid side guards follow the flight while leaving its full authored width
	# clear for the character. Their tops serve as continuous handrails.
	var angle: float=atan2(rise,run); var length: float=Vector2(run,rise).length()
	for side in [-1,1]:
		var guard:=box(stair,"GuardLeft" if side<0 else "GuardRight",Vector3(0.07,0.78,length),Vector3(side*(width*0.5+0.045),rise*0.5+0.40,run*0.5),Color("59636d"))
		guard.rotation.x=-angle
	stair.set_meta("step_height",step); stair.set_meta("step_count",count)
	return stair
