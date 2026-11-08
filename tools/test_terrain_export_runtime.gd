extends SceneTree
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var scene: Node=load("res://city.tscn").instantiate(); root.add_child(scene)
	for frame in 6: await process_frame
	await physics_frame
	scene.player.set_physics_process(false); scene.walking=false; scene._set_mode()
	var before: Dictionary=scene.studio_data.duplicate(true); var surface: Node=scene.terrain
	check(scene.studio_data["terrain"]["enabled"] and not scene.studio_data["terrain_vertices"].is_empty(),"Fresh portable terrain retains authored settings and elevations")
	var traversal: Node=scene.terrain_traversal; var submerged: Variant=null
	for record in scene.studio_data.get("water_cells",[]):
		var point:=Vector2(record["cell"][0]+.5,record["cell"][1]+.5)*2
		if traversal.depth(point)>.45: submerged=point; break
	check(scene.player.terrain_motion_filter.is_valid() and submerged is Vector2,"Relocated terrain binds walking restrictions and retains a deep pond")
	if submerged is Vector2:
		var p: Variant=Vector2((submerged.x-submerged.y)*8,(submerged.x+submerged.y)*4) if scene.dimension=="2d" else Vector3(submerged.x,0,submerged.y)
		check(not scene.player.terrain_position_safe.call(scene.player.get_parent().to_global(p)),"Relocated recovery rejects deep water")
	if scene.dimension=="2d":
		check(not surface.strips.is_empty() and not scene.get_node("Ground").visible,"Portable isometric terrain rebuilds its own presentation")
		var painted: bool=false; var animated: bool=false; var roads: int=0
		for strip in surface.strips.values():
			for face in strip.faces:
				if not face.has("textures"): continue
				if face["cell"]==Vector2i(0,5): painted=face["textures"][0].get_image().get_pixel(16,8).is_equal_approx(Color.MAGENTA)
				elif face["cell"]==Vector2i(1,5): animated=face["textures"].size()>1 and strip.is_processing()
				else: roads+=1
		check(painted and roads>20,"Relocated terrain retains road textures and actual painted pixels")
		check(animated and surface.is_processing(),"Relocated terrain retains its animated ground clock")
		check(not scene.get_node("TerrainOutside").get_used_cells().is_empty(),"Flat ground outside the terrain boundary survives relocation")
	else:
		check(not surface.chunks.is_empty() and scene.get_node("Foundation").collision_layer==0,"Portable physical terrain replaces the original flat foundation")
		var query:=PhysicsRayQueryParameters3D.create(Vector3(-6,30,4),Vector3(-6,-30,4),2); var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty() and absf(hit["position"].y+3)<.002,"Relocated terrain physics reaches the actual submerged pond bed")
	check(scene.studio_data==before,"Terrain rendering preserves the portable project's source data")
	var home: Dictionary=scene.studio_data["objects"].filter(func(item: Dictionary):return item.has("interior"))[0]
	scene.walking=true; scene._set_mode(); scene.player.teleport_to(scene.exploration.entrance(scene.city_instances[home["uid"]])); scene.exploration.interact()
	for frame in 3: await process_frame
	check(scene.exploration.interior!=null and not surface.visible,"Portable owned interiors suspend exterior terrain")
	check(not traversal.active(),"Portable interiors suspend exterior walking restrictions")
	if scene.dimension=="3d": check(surface.chunks.values().all(func(chunk: Node):return chunk.get_node("Surface").collision_layer==0),"Portable interior suspension disables actual terrain collision bodies")
	else: check(not scene.get_node("Ground").visible and not scene.get_node("TerrainOutside").visible,"Portable interior suspension hides both source and outside ground layers")
	scene.exploration.leave_interior()
	check(surface.visible and (scene.dimension=="2d" or surface.chunks.values().all(func(chunk: Node):return chunk.get_node("Surface").collision_layer==2)),"Returning outside restores the portable terrain")
	check(traversal.active(),"Returning outside restores terrain walking restrictions")
	scene.free(); print("TERRAIN EXPORT: %d checks, %d failures"%[checks,failures]); quit(1 if failures else 0)
