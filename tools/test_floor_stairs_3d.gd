extends SceneTree
const Plan=preload("res://scripts/builder/floor_plan.gd")
const Cut=preload("res://scripts/builder/floor_cutouts_3d.gd")
var checks: int=0
var failures: int=0
var world: Node3D
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func room() -> Dictionary:
	return {"title":"Ground","mode":"3d","interior_room":true,"objects":[],"tiles":[],"night":false,"exit":[-4,0.1,0],"spawn":[-4,0.1,0]}
func cast(from: Vector3,to: Vector3) -> Dictionary:
	return world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,2))
func advance(direction: Vector3,frames: int) -> Dictionary:
	var highest: float=world.player.position.y; var max_step: float=0
	for frame in frames:
		await physics_frame
		var before: float=world.player.position.y
		world.player.move_character(1.0/Engine.physics_ticks_per_second,direction)
		highest=maxf(highest,world.player.position.y); max_step=maxf(max_step,world.player.position.y-before)
	await process_frame
	return {"highest":highest,"max_step":max_step}
func capture(path: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	world.camera.projection=Camera3D.PROJECTION_ORTHOGONAL; world.camera.position=Vector3(-11,10,12); world.camera.look_at(Vector3(0,1.5,0)); world.camera.size=16
	for frame in 5: await process_frame
	RenderingServer.force_draw(false); RenderingServer.force_draw(false); root.get_texture().get_image().save_png(path)
func geometry() -> void:
	var surface:=SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for point in [Vector3(-2,0,-2),Vector3(2,0,-2),Vector3(2,0,2),Vector3(-2,0,-2),Vector3(2,0,2),Vector3(-2,0,2)]:
		surface.set_normal(Vector3.UP); surface.set_uv(Vector2(point.x,point.z)*0.25+Vector2.ONE*0.5); surface.set_color(Color((point.x+2)*0.25,0.3,(point.z+2)*0.25)); surface.add_vertex(point)
	var source: ArrayMesh=surface.commit(); var source_hash: int=hash(source.surface_get_arrays(0))
	var opening: PackedVector2Array=Cut.polygon(Vector2(0,-0.5),Vector2(0,0.5),1)
	var clipped: ArrayMesh=Cut.mesh(source,Transform3D.IDENTITY,[opening]); var arrays: Array=clipped.surface_get_arrays(0); var area: float=0; var preserved: bool=true
	for start in range(0,arrays[Mesh.ARRAY_VERTEX].size(),3):
		var a: Vector3=arrays[Mesh.ARRAY_VERTEX][start]; var b: Vector3=arrays[Mesh.ARRAY_VERTEX][start+1]; var c: Vector3=arrays[Mesh.ARRAY_VERTEX][start+2]
		area+=(b-a).cross(c-a).length()*0.5
		var center: Vector3=(a+b+c)/3
		check(not (absf(center.x)<0.49999 and absf(center.z)<0.49999),"No surviving triangle crosses the opening interior")
	for index in arrays[Mesh.ARRAY_VERTEX].size():
		var point: Vector3=arrays[Mesh.ARRAY_VERTEX][index]; var expected:=Vector2(point.x,point.z)*0.25+Vector2.ONE*0.5
		# Godot packs vertex colors to 8-bit channels and octahedrally packs normals.
		preserved=preserved and arrays[Mesh.ARRAY_TEX_UV][index].is_equal_approx(expected) and arrays[Mesh.ARRAY_NORMAL][index].distance_to(Vector3.UP)<0.0001 and absf(arrays[Mesh.ARRAY_COLOR][index].r-expected.x)<=1.0/255+0.00001
	check(absf(area-15)<0.00001,"Clipping conserves exactly the floor area outside the shaft")
	check(preserved,"New edge vertices retain interpolated UVs, normals and colors")
	check(hash(source.surface_get_arrays(0))==source_hash,"Opening generation leaves source mesh resources unchanged")
	var overlap: Array=[opening,Cut.polygon(Vector2(0.25,-0.5),Vector2(0.25,0.5),1)]
	var union_mesh: ArrayMesh=Cut.mesh(source,Transform3D.IDENTITY,overlap); var union_vertices: PackedVector3Array=union_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]; var union_area: float=0
	for index in range(0,union_vertices.size(),3): union_area+=(union_vertices[index+1]-union_vertices[index]).cross(union_vertices[index+2]-union_vertices[index]).length()*0.5
	check(absf(union_area-14.75)<0.00001,"Overlapping shaft footprints subtract their union without duplicate floor fragments")
	check(Cut.mesh(source,Transform3D.IDENTITY,[Cut.polygon(Vector2(20,20),Vector2(20,21),1)])==source,"Distant openings retain the original mesh resource without triangle work")
	var plane:=PlaneMesh.new(); plane.size=Vector2(0.4,0.4)
	var multiple:=ArrayMesh.new(); multiple.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,plane.surface_get_arrays(0))
	var shifted: Array=plane.surface_get_arrays(0); var shifted_vertices: PackedVector3Array=shifted[Mesh.ARRAY_VERTEX]
	for index in shifted_vertices.size(): shifted_vertices[index]+=Vector3(3,0,0)
	shifted[Mesh.ARRAY_VERTEX]=shifted_vertices; multiple.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,shifted)
	var source_material:=StandardMaterial3D.new(); multiple.surface_set_material(1,source_material)
	var mesh:=MeshInstance3D.new(); mesh.mesh=multiple
	var override_a:=StandardMaterial3D.new(); var override_b:=StandardMaterial3D.new(); mesh.set_surface_override_material(0,override_a); mesh.set_surface_override_material(1,override_b)
	var cutter=preload("res://scripts/builder/floor_surface_3d.gd").new(); cutter.openings=[opening]; cutter.clip_mesh(mesh,Transform3D.IDENTITY)
	check(mesh.mesh.get_surface_count()==1 and mesh.mesh.surface_get_material(0)==source_material,"Removing an entire source surface retains the surviving surface's material")
	check(mesh.get_surface_override_material(0)==override_b,"Per-instance material overrides follow surviving source surfaces")
	cutter.restore_instance(mesh)
	check(mesh.mesh==multiple and mesh.get_surface_override_material(0)==override_a and mesh.get_surface_override_material(1)==override_b,"Restoration recovers original override slots before later appearance updates")
	mesh.free(); cutter.free()

func flight_case(city: Dictionary,lower: String,upper: String,height: float,start: Vector2,end: Vector2,width: float,title: String) -> void:
	var data: Dictionary=room(); var extra: Dictionary=room(); extra["night"]=true
	var extra_uid: String=upper if lower=="ground" else lower
	var extra_height: float=height if lower=="ground" else -height
	data["floors"]=[{"uid":extra_uid,"name":title,"height":extra_height,"room":extra}]
	data["floor_links"]=[{"uid":"flight","kind":"stairs","lower":lower,"upper":upper,"start":[start.x,start.y],"end":[end.x,end.y],"width":width}]
	var before: Dictionary=data.duplicate(true)
	check(Plan.valid(data),"Variant is supported by the authored schema: "+title)
	city["objects"][0]["interior"]=data; world.apply(city); world.exploration.nearby={"item":city["objects"][0]}; world.exploration.enter_interior()
	var direction: Vector2=(end-start).normalized(); var run: float=start.distance_to(end); var lower_height: float=0 if lower=="ground" else -height; var upper_height: float=height if lower=="ground" else 0
	world.player.teleport_to(Vector3(start.x-direction.x,lower_height+0.05,start.y-direction.y))
	for frame in 3: await physics_frame
	await advance(Vector3.ZERO,8)
	var frames: int=ceili((run+2.4)/world.player.move_speed*Engine.physics_ticks_per_second)
	var climb: Dictionary=await advance(Vector3(direction.x,0,direction.y),frames); await advance(Vector3.ZERO,12)
	var progress: float=(Vector2(world.player.position.x,world.player.position.z)-start).dot(direction)
	if progress<=run+0.2 or absf(world.player.position.y-upper_height)>=0.12: print("FLIGHT DEBUG: ",title," pose=",world.player.position," expected=",upper_height," steps=",world.player.step_count," climb=",climb," hint=",world.player.movement_hint())
	if progress<=run+0.2:
		var up=world.player.motion_test(world.player.global_transform,Vector3.UP*0.353)
		for index in up.get_collision_count(): print("UP BLOCK: ",up.get_collider(index).name," point=",up.get_collision_point(index))
		var raised: Transform3D=world.player.global_transform; raised.origin.y+=0.353
		var forward=world.player.motion_test(raised,Vector3(direction.x,0,direction.y)*0.0833)
		for index in forward.get_collision_count(): print("FORWARD BLOCK: ",forward.get_collider(index).name," point=",forward.get_collision_point(index))
	check(progress>run+0.2 and absf(world.player.position.y-upper_height)<0.12,"Physical ascent reaches the upper floor: "+title)
	check(climb["max_step"]<=world.player.step_height+0.02 and world.player.recovery_count==0,"Ascent retains bounded steps and never recovers: "+title)
	var stack: Node3D=world.exploration.interior.floor_stack
	check(stack.current_floor==upper,"Cutaway follows the physical destination: "+title)
	check(is_equal_approx(stack.worlds["ground"].sun.light_energy,0.15 if stack.worlds[upper].data_state.get("night",false) else 0.8),"Active floor applies its authored day/night lighting: "+title)
	await advance(Vector3(-direction.x,0,-direction.y),frames); await advance(Vector3.ZERO,12)
	progress=(Vector2(world.player.position.x,world.player.position.z)-start).dot(direction)
	check(progress< -0.2 and absf(world.player.position.y-lower_height)<0.12 and world.player.recovery_count==0,"Physical descent reaches the original floor without recovery: "+title)
	check(stack.current_floor==lower and data==before,"Floor visibility and authored source survive the round trip: "+title)
	world.exploration.leave_interior()
func run() -> void:
	geometry()
	var library=preload("res://scripts/builder/asset_library.gd").new(); var data: Dictionary=room(); var upper: Dictionary=room(); upper["title"]="Upper"
	upper["objects"]=[{"uid":"tile","asset":"3d:HanX_Shop/Floor_Tile_Store","position":[0,0.04,0],"direction":"0","scale":2.0}]
	upper["objects"].append({"uid":"mixed_tile","asset":"2d:Floor_Wood_Oak","position":[0,0.08,0],"direction":"SE","scale":3.0})
	data["floors"]=[{"uid":"upper","name":"Upper","height":3.0,"room":upper}]
	data["floor_links"]=[{"uid":"flight","kind":"stairs","lower":"ground","upper":"upper","start":[-2,0],"end":[3,0],"width":1.3}]
	check(Plan.valid(data),"Physical staircase fixture uses the authored floor schema")
	var before: Dictionary=data.duplicate(true)
	world=load("res://scripts/builder/world_3d.gd").new(); world.library=library; root.add_child(world)
	var city: Dictionary=room(); city.erase("interior_room"); city["objects"]=[{"uid":"building","asset":"2d:House_Blue","position":[0,0,0],"direction":"SE","scale":1.0,"interior":data}]
	world.apply(city); world.walk(true); world.player.set_physics_process(false); world.exploration.nearby={"item":city["objects"][0]}; world.exploration.enter_interior()
	var interior: Node3D=world.exploration.interior; var stack: Node3D=interior.floor_stack
	for frame in 3: await physics_frame
	check(stack!=null and stack.worlds.size()==2 and stack.worlds["upper"].position.y==3,"Runtime builds actual vertically offset floor worlds")
	check(interior.get_node("Foundation").collision_layer==0 and stack.worlds["upper"].get_node("Foundation").collision_layer==0,"Unbounded legacy foundations cannot block or bridge the flight")
	check(not stack.worlds["upper"].objects.visible and interior.objects.visible,"Higher-floor artwork is cut away while standing downstairs")
	check(stack.stairs["flight"].get_meta("step_height")<=0.24 and stack.stairs["flight"].get_meta("step_count")>=12,"Stairs have actual bounded-height treads")
	check(cast(Vector3(0,3.7,0),Vector3(0,2.8,0)).is_empty(),"The upper platform and native floor tile both have an open physical stairwell")
	check(not cast(Vector3(4,3.7,2),Vector3(4,2.8,2)).is_empty(),"The upper floor remains supported outside the opening")
	await capture("res://output/floor_stairs_ground_3d.png")
	var climbed: Dictionary=await advance(Vector3.RIGHT,115)
	await advance(Vector3.ZERO,15)
	check(world.player.position.x>3.2 and world.player.position.y>2.95,"The character physically climbs from ground to the upper landing")
	check(climbed["max_step"]<=world.player.step_height+0.02 and world.player.step_count>0,"Ascent uses ordinary step handling without oversized rises or teleports")
	check(stack.current_floor=="upper" and stack.worlds["upper"].objects.visible,"Upper artwork becomes visible as the character arrives")
	check(world.player.recovery_count==0,"The stair ascent never invokes recovery teleportation")
	var upper_world: Node3D=stack.worlds["upper"]; upper_world.apply(upper)
	for frame in 2: await physics_frame
	check(cast(Vector3(0,3.7,0),Vector3(0,2.8,0)).is_empty(),"Applying room state again cannot restore a solid foundation over the stairwell")
	check(not upper_world.grid.visible and not interior.grid.visible,"Room state updates keep all runtime editor grids hidden")
	upper["night"]=true; upper_world.apply(upper)
	for frame in 2: await physics_frame
	check(cast(Vector3(0,3.7,0),Vector3(0,2.8,0)).is_empty() and is_equal_approx(interior.sun.light_energy,0.15),"Appearance refresh preserves the opening and applies the active floor's lighting")
	upper["night"]=false; upper_world.apply(upper)
	for frame in 2: await physics_frame
	check(cast(Vector3(0,3.7,0),Vector3(0,2.8,0)).is_empty(),"Returning to daytime keeps authored floor colliders clipped")
	upper["objects"][1]["direction"]="NW"; upper_world.apply(upper)
	for frame in 2: await physics_frame
	check(cast(Vector3(0,3.7,0),Vector3(0,2.8,0)).is_empty(),"Projected sprite floor rotation regenerates and clips its quad without closing the shaft")
	var mixed: Node3D=upper_world.instances["mixed_tile"]; mixed.last_frame=""; mixed.update_visual()
	for frame in 2: await physics_frame
	check(cast(Vector3(0,3.7,0),Vector3(0,2.8,0)).is_empty() and mixed.mesh.mesh is ArrayMesh,"A live sprite-frame refresh keeps the floor's render and collision openings")
	upper["objects"][1]["direction"]="SE"; upper_world.apply(upper)
	await capture("res://output/floor_stairs_3d.png")
	await advance(Vector3.LEFT,115); await advance(Vector3.ZERO,15)
	check(world.player.position.x< -2.4 and absf(world.player.position.y)<0.05,"The character descends to the original ground floor")
	check(world.player.recovery_count==0 and stack.current_floor=="ground","Descent restores the ground cutaway without recovery")
	check(data==before,"Runtime stacking, clipping, walking and reapplying leave the authored interior intact")
	world.exploration.leave_interior(); check(world.exploration.interior==null and world.get_node("Foundation").collision_layer==2,"Leaving the stack restores exterior physics")
	check(preload("res://scripts/builder/exporter.gd").save_scene(world,city,library,"res://output/floor_stairs_export_3d.tscn")==OK,"Actual playable scene export retains the authored stacked interior")
	var package: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(world,city,library,"res://output/floor_stairs_3d.zip")
	check(package["ok"],"Portable package creation includes stacked room and clipping dependencies")
	await flight_case(city,"ground","upper",2.4,Vector2(-1.75,0),Vector2(1.75,0),0.8,"minimum-width low storey")
	await flight_case(city,"ground","upper",3,Vector2(-2,-2),Vector2(2,2),1.0,"diagonal flight")
	await flight_case(city,"ground","upper",8,Vector2(-5.6,0),Vector2(5.6,0),1.2,"eight-metre flight")
	await flight_case(city,"basement","ground",3,Vector2(-2,0),Vector2(3,0),1.2,"basement flight")
	world.free(); print("FLOOR STAIRS 3D: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
