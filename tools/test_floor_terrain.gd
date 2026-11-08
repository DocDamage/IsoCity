extends SceneTree
const Plan=preload("res://scripts/builder/floor_plan.gd")
const Terrain=preload("res://scripts/builder/terrain_plan.gd")
const Fit=preload("res://scripts/builder/grid_fit.gd")
const Entries=preload("res://scripts/builder/floor_entrances.gd")
const Passages=preload("res://scripts/builder/floor_terrain_plan.gd")
var checks: int=0
var failures: int=0
var studio: Control
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for frame in 5: await physics_frame
	await process_frame
func terrain(data: Dictionary,height: float) -> void:
	data["terrain"]={"enabled":true,"bounds":[-6,-6,12,12]}; data["terrain_vertices"]=[]; data["water_cells"]=[]
	var scale: float=2 if data["mode"]=="2d" else 1
	for x in range(-6,7):
		for z in range(-6,7):
			var point:=Vector2(x,z)*2
			var level: float=0 if (absf(point.y)<=2*scale and absf(point.x)<=4*scale) or (point.x>=2*scale and point.x<=6*scale and point.y>=-6*scale and point.y<=-2*scale) else height
			data["terrain_vertices"].append({"cell":[x,z],"height":level})
	data["water_cells"].append({"cell":[1,1],"level":height+1.2})
func cast(point: Vector3,to: Vector3,player: Node,extra: Array[RID]=[]) -> Dictionary:
	var excluded: Array[RID]=extra.duplicate(); excluded.append(player.get_rid())
	return player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point,to,2,excluded))
func place(player: Node,mode: String,metric: Vector2,world: Node) -> void:
	if mode=="2d": player.teleport_to(Terrain.project_2d(Vector3(metric.x,0,metric.y)))
	else:
		var y: float=world.terrain_traversal.sample_at(metric)["height"]+.025
		var hit: Dictionary=cast(world.to_global(Vector3(metric.x,y+.5,metric.y)),world.to_global(Vector3(metric.x,y-.1,metric.y)),player)
		if not hit.is_empty(): y=world.to_local(hit["position"]).y+.025
		player.teleport_to(player.get_parent().to_local(world.to_global(Vector3(metric.x,y,metric.y))))
func area(points: PackedVector2Array) -> float:
	var result: float=0
	for index in points.size(): result+=points[index].cross(points[(index+1)%points.size()])
	return absf(result)*.5
func overlaps(points: PackedVector2Array,holes: Array) -> bool:
	if area(points)<.00001: return false
	for hole in holes:
		for polygon in Geometry2D.intersect_polygons(points,hole):
			if area(polygon)>.0001: return true
	return false
func cuts_clear(world: Node,mode: String,holes: Array) -> Dictionary:
	var count: int=0; var textured: int=0; var water_faces: int=0; var clear: bool=true; var uv: bool=true
	if mode=="2d":
		for strip in world.terrain.strips.values():
			for face in strip.faces:
				var polygon:=PackedVector2Array()
				for point in face["points"]:
					var pixel: Vector2=point+strip.position+Vector2(0,8 if face["kind"]=="water" else 0)
					polygon.append(Vector2(pixel.x/16+pixel.y/8,pixel.y/8-pixel.x/16))
				count+=1; clear=clear and not overlaps(polygon,holes)
				if face["kind"]=="water": water_faces+=1
				if face.has("uv"): textured+=1; uv=uv and face["uv"].size()==face["points"].size()
	else:
		var meshes: Array=world.terrain.find_children("*","MeshInstance3D",true,false)+world.road_node.find_children("*","MeshInstance3D",true,false)
		for node in meshes:
			var frame: Transform3D=world.global_transform.affine_inverse()*node.global_transform
			for surface in node.mesh.get_surface_count():
				var arrays: Array=node.mesh.surface_get_arrays(surface); var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]; var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
				for start in range(0,indices.size() if not indices.is_empty() else vertices.size(),3):
					var polygon:=PackedVector2Array()
					for offset in 3:
						var point: Vector3=frame*vertices[indices[start+offset] if not indices.is_empty() else start+offset]; polygon.append(Vector2(point.x,point.z))
					count+=1; clear=clear and not overlaps(polygon,holes)
					if node.name=="Water": water_faces+=1
	return {"clear":clear,"faces":count,"textured":textured,"uv":uv,"water":water_faces}
func capture(mode: String,stage: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	for frame in 5: await process_frame
	RenderingServer.force_draw(false); RenderingServer.force_draw(false); root.get_texture().get_image().save_png("res://output/floor_terrain_"+mode+"_"+stage+".png")
func wait_lift(lift: Node) -> void:
	for frame in 4000:
		await physics_frame
		if lift.phase in ["idle","blocked"]: break
	await process_frame
func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio)
	for frame in 5: await process_frame
	for mode in ["2d","3d"]:
		studio.switch_mode(mode); var city: RefCounted=studio.current(); var world: Node=studio.worlds[mode]; var player: Node=world.player; var exploration: Node=world.exploration
		var host: Dictionary=city.data["objects"].filter(func(item: Dictionary)->bool:return studio.library.assets[item["asset"]]["behavior"].get("building",false))[0]; var host_uid: String=host["uid"]
		city.data["terrain"]={"enabled":true,"bounds":[-8,-8,16,16]}; city.data["terrain_vertices"]=[]; city.data["water_cells"]=[]
		for x in range(-8,9):
			for z in range(-8,9): city.data["terrain_vertices"].append({"cell":[x,z],"height":2})
		if mode=="3d": host["position"][1]=2
		var room: Dictionary=preload("res://scripts/builder/interiors.gd").make(mode,"Garden floor"); room["objects"]=[]; room["tiles"]=[]; room["roads"]=[]; terrain(room,.6)
		room["exit"]=[Terrain.project_2d(Vector3(0,0,6)).x,Terrain.project_2d(Vector3(0,0,6)).y,0] if mode=="2d" else [0,.1,6]
		var upper: Dictionary=preload("res://scripts/builder/interiors.gd").make(mode,"Sunken floor"); upper["objects"]=[]; upper["tiles"]=[]; upper["roads"]=[{"cell":[0,0],"crossing":true,"width":6,"style":"asphalt","sidewalks":true}]; terrain(upper,-.5); upper["exit"]=room["exit"].duplicate()
		for vertex in upper["terrain_vertices"]:
			if vertex["cell"][0]<-2 and vertex["cell"][1]>2: vertex["height"]=-1.5
		room["floors"]=[{"uid":"upper","name":"Sunken floor","height":3,"room":upper}]
		room["floor_links"]=[{"uid":"stairs","kind":"stairs","lower":"ground","upper":"upper","start":[-3,0],"end":[2,0],"width":1.4},{"uid":"lift","kind":"elevator","lower":"ground","upper":"upper","start":[4,-4],"end":[4,-4],"width":1.4}]
		room["floor_entrances"]=[{"uid":"upper_door","floor":"upper","position":[12,3,12]}]
		host["interior"]=room; studio.changed(); var authored: Dictionary=city.data.duplicate(true); studio.set_walking(true); player.set_physics_process(false)
		var source_filter: Callable=player.terrain_motion_filter; var source_safe: Callable=player.terrain_position_safe; var parent: Node=player.get_parent(); var entrance: Variant=exploration.entrance(world.instances[host_uid])
		player.teleport_to(entrance); exploration.interact(); await settle()
		check(exploration.interior!=null and exploration.active_floor()=="ground","A normal owned visit loads a terrain room: "+mode)
		check(player.terrain_motion_filter.get_object()==exploration.room_traversal and player.terrain_position_safe.get_object()==exploration.room_traversal,"The real walker uses the room's movement and safe-position binding: "+mode)
		var active: Node=exploration.room_world(); place(player,mode,Vector2(-6,-6),active); await settle()
		if mode=="2d": check(is_equal_approx(float(player.get_meta("terrain_height",0)),.6) and player.terrain_visual_offset.y<0,"The real 2D visitor receives room terrain elevation")
		else:
			var hit: Dictionary=cast(Vector3(-6,2,-6),Vector3(-6,-1,-6),player)
			check(not hit.is_empty() and absf(hit["position"].y-.6)<.001 and active.floor_surface.platform.collision_layer==0,"Terrain replaces the flat interior slab and supplies real raised support")
			check(cast(Vector3(40,2,40),Vector3(40,-1,40),player).is_empty(),"A terrain room does not retain an unbounded outside foundation")
			check(not exploration.interior.floor_stack.worlds["upper"].terrain.visible,"Ground-floor cutaway hides the upper terrain artwork")
		place(player,mode,Vector2(0,3),active)
		for frame in 100:
			await physics_frame; player.move_character(1.0/60,Fit.pixels(Vector2.RIGHT).normalized() if mode=="2d" else Vector3.RIGHT)
		await process_frame
		var metric: Vector2=active.terrain_traversal.metric(player.global_position)
		check(metric.x<2.4 and "Deep water" in player.movement_hint() and player.recovery_count==0,"Actual room walking stops at deep water without a recovery teleport: "+mode)
		await capture(mode,"ground"); exploration.leave_interior(); await settle()
		check(player.get_parent()==parent and player.terrain_motion_filter==source_filter and player.terrain_position_safe==source_safe,"Leaving restores the exterior character ownership and terrain callbacks: "+mode)
		if mode=="2d": check(is_equal_approx(float(player.get_meta("terrain_height",0)),2),"Exterior presentation reacquires its own height after a terrain-room visit")
		var upper_entrance: Variant=Entries.outside(world.instances[host_uid],host,room["floor_entrances"][0],mode,studio.library)
		player.teleport_to(upper_entrance); exploration.interact(); await settle()
		check(exploration.interior!=null and exploration.active_floor()=="upper","A floor-specific entrance reaches a sculpted upstairs room: "+mode)
		active=exploration.room_world(); place(player,mode,Vector2(-6,-6),active); await settle()
		if mode=="2d": check(is_equal_approx(float(player.get_meta("terrain_height",0)),-.5) and player.terrain_visual_offset.y>0,"Upstairs depressions use their own 2D presentation")
		else:
			var hit: Dictionary=cast(Vector3(-6,4,-6),Vector3(-6,1,-6),player)
			check(not hit.is_empty() and absf(hit["position"].y-2.5)<.001 and exploration.active_floor()=="upper","An upstairs depression has real lowered support and retains its floor identity")
			check(exploration.interior.terrain.visible and active.terrain.visible,"The upstairs cutaway retains its own terrain and the lower visible storey")
		place(player,mode,Vector2(-6,6),active); await settle()
		check(exploration.active_floor()=="upper" and (is_equal_approx(float(player.get_meta("terrain_height",0)),-1.5) if mode=="2d" else absf(player.position.y-1.525)<.01),"Deep upstairs terrain retains its room even below the nominal floor height: "+mode)
		place(player,mode,Vector2(0,3),active)
		for frame in 100:
			await physics_frame; player.move_character(1.0/60,Fit.pixels(Vector2.RIGHT).normalized() if mode=="2d" else Vector3.RIGHT)
		await process_frame
		check(active.terrain_traversal.metric(player.global_position).x<2.4 and "Deep water" in player.movement_hint(),"Upstairs water uses the visited room's height and water records: "+mode)
		await capture(mode,"upper")
		# The authored flight runs through clipped terrain, including its source.
		if mode=="2d":
			player.teleport_to(Fit.pixels(Vector2(2,0))); exploration.interact()
			for frame in 2000:
				await physics_frame
				if exploration.interior.floor_stack.travel.is_empty(): break
		else:
			place(player,mode,Vector2(2.8,0),active)
			for frame in 90: await physics_frame; player.move_character(1.0/60,Vector3.LEFT)
			for frame in 15: await physics_frame; player.move_character(1.0/60,Vector3.ZERO)
		await process_frame
		check(exploration.active_floor()=="ground" and player.recovery_count==0,"The terrain-room flight supports actual descent to ground: "+mode)
		var lift: Node=exploration.interior.floor_stack.lifts["lift"]
		if mode=="2d": player.teleport_to(Fit.pixels(Vector2(4,-4)))
		else: place(player,mode,Vector2(4,-4),exploration.room_world())
		exploration.interact()
		check(lift.menu.visible,"The cabin is usable above the terrain cutout: "+mode)
		lift.choose("upper"); await wait_lift(lift)
		check(lift.phase=="idle" and exploration.active_floor()=="upper" and player.recovery_count==0,"The elevator crosses sculpted floors without terrain blocking its shaft: "+mode)
		# Flatten only this runtime inspection fixture to reconstruct its projected
		# polygons exactly; restore the authored heights after the cutout checks.
		var saved_vertices: Array=upper["terrain_vertices"].duplicate(true); var saved_water: Array=upper["water_cells"].duplicate(true)
		for vertex in upper["terrain_vertices"]: vertex["height"]=0.0
		upper["water_cells"]=[]; var scale: int=2 if mode=="2d" else 1
		for x in range(2*scale-1,2*scale+1):
			for z in range(-2*scale-1,-2*scale+2): upper["water_cells"].append({"cell":[x,z],"level":1.0})
		exploration.apply_room("upper"); await settle(); active=exploration.room_world()
		var holes: Array=Passages.passages(room,"upper"); var inspection: Dictionary=cuts_clear(active,mode,holes)
		check(inspection["clear"] and inspection["faces"]>20 and inspection["water"]>0,"Terrain, water and roads leave the same open stair/elevator footprints: "+mode)
		if mode=="2d": check(inspection["textured"]>0 and inspection["uv"],"Clipped projected road artwork retains matching texture coordinates")
		else:
			check(cast(Vector3(0,3.5,0),Vector3(0,2.8,0),player).is_empty() and cast(Vector3(4,3.5,-4),Vector3(4,2.8,-4),player,lift.view.own).is_empty(),"Neither deformed road collision nor terrain closes a physical shaft")
			exploration.apply_room("upper"); await settle()
			check(cast(Vector3(0,3.5,0),Vector3(0,2.8,0),player).is_empty(),"Reapplying a room keeps cached road cutouts open")
		await capture(mode,"openings"); exploration.interact(); lift.choose("ground"); await wait_lift(lift)
		check(lift.phase=="idle" and exploration.active_floor()=="ground","The passenger can leave a flooded upper landing safely inside the cabin: "+mode)
		exploration.interact(); lift.choose("upper"); await wait_lift(lift)
		check(lift.phase=="blocked" and lift.notice.contains("Landing blocked"),"An elevator refuses arrival at an actual flooded landing: "+mode)
		exploration.interact(); await wait_lift(lift)
		check(lift.phase=="idle" and lift.last_stop=="ground" and not player.is_physics_processing(),"Returning from a flooded landing restores the original processing state: "+mode)
		upper["terrain_vertices"]=saved_vertices; upper["water_cells"]=saved_water; exploration.apply_room("upper")
		if mode=="2d":
			player.teleport_to(Fit.pixels(Vector2(-3,0))); exploration.interact()
			for frame in 2000:
				await physics_frame
				if exploration.interior.floor_stack.travel.is_empty(): break
		else:
			player.teleport_to(Vector3(-3.8,.05,0))
			for frame in 90: await physics_frame; player.move_character(1.0/60,Vector3.RIGHT)
			for frame in 15: await physics_frame; player.move_character(1.0/60,Vector3.ZERO)
		await process_frame
		check(exploration.active_floor()=="upper" and player.recovery_count==0,"Restored sculpted floors support physical ascent through the road opening: "+mode)
		var had_layers: bool=upper.has("layers"); var previous_layers: Dictionary=upper.get("layers",{}).duplicate(true)
		upper["layers"]={"Ground":{"visible":false}}; exploration.apply_room("upper"); await settle()
		check(not exploration.walk_allowed() and "Show Ground" in player.movement_hint() and not (player.is_player_controlled if mode=="2d" else player.active),"Hidden room ground suspends walking with a floor-specific explanation: "+mode)
		if mode=="3d": check(not exploration.room_world().road_node.visible,"The cutaway cannot reveal roads from a hidden Ground layer")
		if had_layers: upper["layers"]=previous_layers
		else: upper.erase("layers")
		exploration.apply_room("upper"); await settle(); check(exploration.walk_allowed() and (player.is_player_controlled if mode=="2d" else player.active),"Showing room ground restores ordinary walking: "+mode)
		exploration.prompt(); player.teleport_to(exploration.exit_position); exploration.interact(); await settle()
		check(exploration.interior==null and player.position.distance_to(upper_entrance)<.01,"A sculpted upstairs room's EXIT follows its actual terrain elevation: "+mode)
		check(city.data==authored,"Terrain presentation, carving and room traversal preserve every authored record: "+mode)
		studio.set_walking(false); studio.interior_tools.start(host_uid,"upper"); var edit_doc: RefCounted=studio.current(); var edit_history: int=edit_doc.undo_history.size()
		studio.set_walking(true); await settle(); player.set_physics_process(false); place(player,mode,Vector2(-6,6),exploration.room_world()); await settle()
		check(exploration.preview and exploration.active_floor()=="upper" and (is_equal_approx(float(player.get_meta("terrain_height",0)),-1.5) if mode=="2d" else absf(player.position.y-1.525)<.01),"Direct editor Walk uses the selected floor's real terrain binding: "+mode)
		studio._command("night",null); check(Plan.room(edit_doc.canonical.data,"upper")["night"] and not edit_doc.canonical.data["night"],"Lighting a terrain preview edits only the visited room: "+mode)
		studio._command("home",null); await settle(); check(exploration.preview and exploration.active_floor()=="upper" and exploration.walk_allowed(),"Home restarts on the sculpted floor's supported walking start: "+mode)
		studio.set_walking(false); check(edit_doc.floor_uid=="upper" and edit_doc.undo_history.size()==edit_history+1,"Returning from sculpted editor Walk preserves floor ownership and shared history: "+mode)
		studio._command("undo",null); studio.interior_tools.leave(); check(city.data==authored,"Undo and leaving a terrain editing visit restore the complete authored city: "+mode)
		check(preload("res://scripts/builder/exporter.gd").save_scene(world,city.data,studio.library,"res://output/floor_terrain_"+mode+".tscn")==OK,"Sculpted multi-floor rooms export to a playable scene: "+mode)
		check(preload("res://scripts/builder/portable_export.gd").new().save(world,city.data,studio.library,"res://output/floor_terrain_"+mode+".zip")["ok"],"Sculpted multi-floor rooms package all runtime dependencies: "+mode)
		studio.set_walking(false); player.set_physics_process(true)
	studio.free(); print("FLOOR TERRAIN: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
