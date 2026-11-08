extends SceneTree
const Plan=preload("res://scripts/builder/terrain_plan.gd")
const Roads=preload("res://scripts/builder/roads.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for frame in 5: await process_frame
	await physics_frame
func ray(world: Node,point: Vector2) -> Dictionary:
	return world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(point.x,30,point.y),Vector3(point.x,-30,point.y),2))
func run() -> void:
	var world:=Node3D.new(); root.add_child(world)
	var data: Dictionary={"mode":"3d","terrain":{"enabled":true,"bounds":[-8,-8,16,16]},"terrain_vertices":[],"water_cells":[],"roads":[{"cell":[0,0],"style":"gravel","width":6,"sidewalks":true},{"cell":[1,0],"style":"gravel","width":2,"sidewalks":true}]}
	for x in range(-8,9):
		for z in range(-8,9): data["terrain_vertices"].append({"cell":[x,z],"height":x*.3+z*.1+(1 if x==0 and z==0 else 0)})
	var roads: Node3D=Roads.make_3d(data); world.add_child(roads); await settle()
	check(roads.get_child_count()==2 and roads.get_child(0).find_children("*","CollisionShape3D",true,false)[0].shape is ConcavePolygonShape3D,"Terrain roads replace flat slab collisions with their deformed mesh")
	for point in [Vector2(.4,.7),Vector2(1.2,-1.3),Vector2(3.7,0),Vector2(4.2,0),Vector2(7.7,.4)]:
		var hit: Dictionary=ray(world,point); var height: float=Plan.sample(data,point)["height"]+.11
		check(not hit.is_empty() and absf(hit["position"].y-height)<.002 and hit["normal"].y>0,"Road collision follows the exact terrain triangles across transitions: "+str(point)+str(hit.get("position")))
	var vertices: int=0; var finite: bool=true
	for section in roads.get_children():
		for mesh in section.get_children():
			if not mesh is MeshInstance3D: continue
			for surface in mesh.mesh.get_surface_count():
				var arrays: Array=mesh.mesh.surface_get_arrays(surface)
				for p in arrays[Mesh.ARRAY_VERTEX]: vertices+=1; finite=finite and p.is_finite()
	check(vertices>1000 and finite,"Roads subdivide on terrain grid/diagonals with finite render geometry")
	var retained: int=roads.get_child(1).get_instance_id(); var edited: Dictionary=data.duplicate(true); edited["terrain_vertices"].append({"cell":[-1,0],"height":3}); Roads.update_3d(roads,edited)
	check(roads.get_meta("last_rebuilt")==1 and roads.get_child(0).get_instance_id()==retained,"An edit near one section retains the distant road mesh and collider")
	Roads.update_3d(roads,edited); check(roads.get_meta("last_rebuilt")==0,"Unchanged terrain and roads rebuild no resources")
	var flat: Dictionary=data.duplicate(true); flat["terrain"]["enabled"]=false; var legacy: Node3D=Roads.make_3d(flat); world.add_child(legacy); check(legacy.get_child(0).find_children("*","CollisionShape3D",true,false)[0].shape is BoxShape3D,"Disabled terrain retains the original road geometry/collision path"); legacy.free()
	world.free(); print("TERRAIN ROADS: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
