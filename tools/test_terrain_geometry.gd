extends SceneTree
const Plan=preload("res://scripts/builder/terrain_plan.gd")
const Surface=preload("res://scripts/builder/terrain_surface_3d.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for frame in 4: await process_frame
	await physics_frame; await process_frame
func run() -> void:
	var world:=Node3D.new(); root.add_child(world); var surface=Surface.new(); world.add_child(surface)
	var data: Dictionary={"terrain":{"enabled":true,"bounds":[-16,-16,32,32]},"terrain_vertices":[],"water_cells":[]}
	surface.configure(data)
	check(surface.chunks.size()==4 and surface.last_rebuilt==4,"Terrain creates four bounded mesh/collision chunks")
	var original: Dictionary={}
	for id in surface.chunks: original[id]=surface.chunks[id].get_instance_id()
	surface.configure(data); check(surface.last_rebuilt==0,"Unchanged terrain retains all mesh and physics resources")
	var changed: Dictionary=data.duplicate(true); changed["terrain_vertices"]=[{"cell":[1,1],"height":4}]; surface.configure(changed)
	check(surface.last_rebuilt==1 and surface.chunks["-1:-1"].get_instance_id()==original["-1:-1"] and surface.chunks["0:0"].get_instance_id()!=original["0:0"],"An interior vertex rebuilds only its owning chunk")
	changed["terrain_vertices"].append({"cell":[0,0],"height":-3}); surface.configure(changed)
	check(surface.last_rebuilt==4,"A shared corner updates every adjoining chunk")
	await settle()
	for point in [Vector2.ZERO,Vector2(1,1),Vector2(2,2),Vector2(-1,-1),Vector2(20,20)]:
		var query:=PhysicsRayQueryParameters3D.create(Vector3(point.x,30,point.y),Vector3(point.x,-30,point.y),2)
		var hit: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty() and hit["normal"].y>0 and absf(hit["position"].y-Plan.sample(changed,point)["height"])<.002,"Physical terrain height matches the upward-facing surface: "+str(point))
	for id in surface.chunks:
		var arrays: Array=surface.chunks[id].get_node("Surface/Land").mesh.surface_get_arrays(0)
		check(arrays[Mesh.ARRAY_VERTEX].size()==16*16*6 and arrays[Mesh.ARRAY_NORMAL].size()==arrays[Mesh.ARRAY_VERTEX].size(),"Chunk vertices and normals cover every cell: "+id)
		var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var clockwise: bool=true
		for index in range(0,points.size(),3):
			if (points[index+1]-points[index]).cross(points[index+2]-points[index]).y>=0: clockwise=false; break
		check(clockwise,"Terrain faces follow Godot's clockwise front winding: "+id)
	var pond: Dictionary=Plan.brush(changed,"basin",Vector2(10,10),7,4)["data"]; surface.configure(pond)
	check(surface.last_rebuilt==1 and surface.chunks["0:0"].has_node("Water"),"Ponds create clipped water only in affected chunks")
	var water_mesh: ArrayMesh=surface.chunks["0:0"].get_node("Water").mesh; var water_faces: PackedVector3Array=water_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(not water_faces.is_empty() and water_faces.size()%3==0,"Water polygons triangulate into a renderable surface")
	for point in water_faces:
		if point.y!=0 or Plan.sample(pond,Vector2(point.x,point.z))["height"]>.001: check(false,"Water never renders uphill from its shoreline"); break
	check(not surface.chunks["0:0"].get_node("Water") is CollisionObject3D and surface.chunks["0:0"].get_node("Water").get_child_count()==0,"Water retains the sculpted bed as the walking surface")
	await settle()
	var bed: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(10,30,10),Vector3(10,-30,10),2))
	check(not bed.is_empty() and absf(bed["position"].y+4)<.002,"Physical rays reach the pond bed rather than colliding with its water surface")
	var ramp: Dictionary={"terrain":{"enabled":true,"bounds":[-4,-4,8,8]},"terrain_vertices":[],"water_cells":[]}
	for x in range(-4,5):
		for y in range(-4,5): ramp["terrain_vertices"].append({"cell":[x,y],"height":x*.5})
	surface.configure(ramp)
	var walker=preload("res://scripts/builder/player_3d.gd").new(); world.add_child(walker); walker.set_physics_process(false); walker.collision_layer=0; walker.collision_mask=2; walker.move_speed=2; walker.teleport_to(Vector3(-6,-1.4,0)); await settle()
	for frame in 240:
		await physics_frame; walker.move_character(1.0/60,Vector3.RIGHT)
	check(walker.position.x>1 and absf(walker.position.y-walker.position.x*.25)<.12 and walker.is_on_floor() and walker.recovery_count==0,"The real exploration character walks a slope from a depression onto raised ground without teleport recovery: "+str([walker.position,walker.velocity,walker.is_on_floor(),walker.recovery_count]))
	walker.free()
	var outside: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(20,30,20),Vector3(20,-30,20),2))
	check(not outside.is_empty() and absf(outside["position"].y)<.002,"A small sculpted patch preserves walkable original foundation outside its bounds")
	var edge_hit: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(6,1,0),Vector3(10,1,0),2))
	check(not edge_hit.is_empty() and absf(edge_hit["position"].x-8)<.002,"Raised terrain edges have physical walls instead of open sides")
	var edge_id: int=surface.boundary.get_instance_id(); var interior_change: Dictionary=ramp.duplicate(true); interior_change["terrain_vertices"].append({"cell":[0,0],"height":1}); surface.configure(interior_change)
	check(surface.boundary.get_instance_id()==edge_id,"Interior sculpting retains unchanged boundary and outside foundation resources")
	var moved: Dictionary={"terrain":{"enabled":true,"bounds":[48,48,8,8]},"terrain_vertices":[],"water_cells":[]}; surface.configure(moved); await settle()
	outside=world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0,30,0),Vector3(0,-30,0),2))
	check(not outside.is_empty() and absf(outside["position"].y)<.002,"Moving the sculpted patch beyond the original city retains its whole original foundation")
	var disabled: Dictionary=pond.duplicate(true); disabled["terrain"]["enabled"]=false; surface.configure(disabled); check(surface.chunks.is_empty(),"Disabling terrain removes all physical/render chunks")
	var hidden: Dictionary=pond.duplicate(true); hidden["layers"]={"Ground":{"visible":false}}; surface.configure(hidden); check(surface.chunks.is_empty(),"Hidden Ground removes terrain collision as well as rendering")
	var picture: Dictionary={"terrain":{"enabled":true,"bounds":[-8,-8,16,16]},"terrain_vertices":[],"water_cells":[]}
	picture=Plan.brush(picture,"raise",Vector2(-7,-5),8,6)["data"]; picture=Plan.brush(picture,"basin",Vector2(6,4),7,4)["data"]; surface.configure(picture)
	var sun:=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-48,-35,0); sun.shadow_enabled=true; world.add_child(sun)
	var environment:=WorldEnvironment.new(); var sky:=Environment.new(); sky.background_mode=Environment.BG_COLOR; sky.background_color=Color("243743"); sky.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; sky.ambient_light_color=Color("d0e0eb"); sky.ambient_light_energy=.5; environment.environment=sky; world.add_child(environment)
	var camera:=Camera3D.new(); world.add_child(camera); camera.position=Vector3(24,26,32); camera.look_at(Vector3.ZERO); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=44; camera.current=true
	if "--capture" in OS.get_cmdline_user_args():
		root.size=Vector2i(1280,800); await settle(); await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png("res://output/terrain_geometry_3d.png")
	world.free(); print("TERRAIN GEOMETRY: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
