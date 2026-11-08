extends SceneTree
const Plan=preload("res://scripts/builder/terrain_plan.gd")
const Surface=preload("res://scripts/builder/terrain_surface_2d.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world:=Node2D.new(); world.y_sort_enabled=true; root.add_child(world); var surface=Surface.new(); world.add_child(surface)
	var data: Dictionary={"terrain":{"enabled":true,"bounds":[-4,-4,8,8]},"terrain_vertices":[],"water_cells":[]}
	for x in range(-4,5):
		for y in range(-4,5): data["terrain_vertices"].append({"cell":[x,y],"height":(x+y)*.2})
	surface.configure(data)
	check(surface.strips.size()>8 and surface.last_rebuilt==surface.strips.size(),"Isometric terrain uses bounded diagonal depth strips")
	var original: Dictionary={}
	for id in surface.strips: original[id]=surface.strips[id].get_instance_id()
	surface.configure(data); check(surface.last_rebuilt==0,"Unchanged 2D terrain retains all presentation nodes")
	for point in [Vector2(-6,-6),Vector2.ZERO,Vector2(2.25,-1.25),Vector2(8,8),Vector2(4,5)]:
		var height: float=Plan.sample(data,point)["height"]; var pixel: Vector2=Plan.project_2d(Vector3(point.x,height,point.y)); var hit: Dictionary=Plan.pick_2d(data,pixel)
		check(hit["ok"] and hit["point"].distance_to(point)<.0001 and absf(hit["height"]-height)<.0001,"Terrain picking inverts projected height and ground coordinates: "+str(point))
	check(not Plan.pick_2d(data,Vector2(INF,0))["ok"] and not Plan.pick_2d(data,Vector2(1e20,1e20))["ok"],"Invalid or distant pointers fail before grid scans")
	surface.position=Vector2(13,17); var translated: Dictionary=surface.pick(surface.to_global(Plan.project_2d(Vector3(2,.4,2))))
	check(translated["ok"] and translated["point"].distance_to(Vector2(2,2))<.001,"Terrain picking accounts for parent presentation transforms"); surface.position=Vector2.ZERO
	var spike: Dictionary={"terrain":{"enabled":true,"bounds":[-4,-4,8,8]},"terrain_vertices":[{"cell":[0,0],"height":10}],"water_cells":[]}
	var occluded: Dictionary=Plan.pick_2d(spike,Plan.project_2d(Vector3(-5,0,-5)))
	check(occluded["ok"] and occluded["height"]>5 and occluded["point"].x>0,"Isometric picking chooses the foreground slope over occluded ground")
	var changed: Dictionary=data.duplicate(true); changed["terrain_vertices"].append({"cell":[0,0],"height":2})
	# Replace the existing center sample rather than authoring duplicate cells.
	changed["terrain_vertices"]=changed["terrain_vertices"].filter(func(item: Dictionary):return item["cell"]!=[0,0] or item["height"]==2)
	surface.configure(changed)
	check(surface.last_rebuilt>0 and surface.last_rebuilt<=4 and surface.last_rebuilt<surface.strips.size(),"One vertex rebuilds only its adjoining depth strips")
	check(surface.strips["-6:-1"].get_instance_id()==original["-6:-1"],"Distant strip nodes survive local terrain edits")
	var hill: Dictionary={"terrain":{"enabled":true,"bounds":[-8,-8,16,16]},"terrain_vertices":[],"water_cells":[]}
	hill=Plan.brush(hill,"raise",Vector2(-6,-6),7,6)["data"]; hill=Plan.brush(hill,"basin",Vector2(6,4),7,4)["data"]; surface.configure(hill)
	var water_faces: int=0; var upward: int=0; var depth_valid: bool=true
	for strip in surface.strips.values():
		for face in strip.faces:
			if strip.position.y!=(face["cell"].x+face["cell"].y+2)*Plan.CELL_SIZE*4: depth_valid=false
			if face["kind"]=="water": water_faces+=1
			else: upward+=1
	check(depth_valid,"Drawn faces share the correct logical ground-depth anchor")
	check(water_faces>0 and upward>water_faces,"Clipped water and shaded land both enter the isometric presentation")
	var target:=Vector2(6,4); var level: float=Plan.water_level(hill,target); var water_hit: Dictionary=Plan.pick_2d(hill,Plan.project_2d(Vector3(target.x,level,target.y)),true)
	check(water_hit["ok"] and water_hit["kind"]=="water" and water_hit["point"].distance_to(target)<.001,"Water-aware picking reaches the visible water surface")
	var bed_height: float=Plan.sample(hill,target)["height"]; var bed_hit: Dictionary=Plan.pick_2d(hill,Plan.project_2d(Vector3(target.x,bed_height,target.y)))
	check(bed_hit["ok"] and bed_hit["kind"]=="land" and Plan.project_2d(Vector3(bed_hit["point"].x,bed_hit["height"],bed_hit["point"].y)).distance_to(Plan.project_2d(Vector3(target.x,bed_height,target.y)))<.001,"Land picking reprojects exactly even when a bank occludes the bed")
	var disabled: Dictionary=hill.duplicate(true); disabled["terrain"]["enabled"]=false; surface.configure(disabled); check(surface.strips.is_empty() and not surface.pick(Vector2.ZERO)["ok"],"Disabled terrain frees its presentation and cannot be picked")
	var hidden: Dictionary=hill.duplicate(true); hidden["layers"]={"Ground":{"visible":false}}; surface.configure(hidden); check(surface.strips.is_empty(),"Hidden Ground frees its isometric terrain strips")
	surface.configure(hill); var camera:=Camera2D.new(); world.add_child(camera); camera.zoom=Vector2.ONE*2; camera.position=Vector2(0,-20)
	if "--capture" in OS.get_cmdline_user_args():
		root.size=Vector2i(1280,800)
		for frame in 5: await process_frame
		await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png("res://output/terrain_geometry_2d.png")
	world.free(); print("TERRAIN 2D: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
