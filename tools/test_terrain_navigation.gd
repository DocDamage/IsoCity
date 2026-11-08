extends SceneTree
const Plan=preload("res://scripts/builder/terrain_plan.gd")
const Nav=preload("res://scripts/builder/terrain_navigation.gd")
const Traffic=preload("res://scripts/builder/traffic_plan.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for frame in 6: await process_frame
	await physics_frame
func coordinate(point: Vector2,mode: String) -> Vector2:
	return Vector2((point.x-point.y)*.5,(point.x+point.y)*.5) if mode=="2d" else point
func length(path: PackedVector2Array) -> float:
	var result: float=0
	for index in range(1,path.size()): result+=path[index-1].distance_to(path[index])
	return result
func run() -> void:
	var studio: Control=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio); await settle()
	for mode in ["2d","3d"]:
		studio.switch_mode(mode)
		var doc=preload("res://scripts/builder/document.gd").new(); doc.data=preload("res://scripts/builder/templates.gd").make(mode,"blank"); doc.data["objects"]=[]; doc.data["roads"]=[]; doc.data["terrain"]={"enabled":true,"bounds":[-8,-8,16,16]}; doc.data["terrain_vertices"]=[]; doc.data["water_cells"]=[]; doc.data["citizens"]={"enabled":true,"population":0}
		for x in range(-1,1):
			for z in range(-2,2): doc.data["water_cells"].append({"cell":[x,z],"level":2})
		var hazards: Array[Rect2]=Nav.obstacles(doc.data)
		check(hazards.size()==4 and hazards.all(func(rect: Rect2):return rect.size==Vector2(4,2)),"Adjacent water cells merge into bounded row obstacles: "+mode)
		studio.documents[mode]=doc; studio.changed(); await settle(); var world: Node=studio.worlds[mode]; var manager: Node=studio.citizen_tools.managers[mode]; manager.set_physics_process(false); manager.configure(doc.data,studio.library,world.instances,world.objects)
		var from: Vector2=coordinate(Vector2(-8,0),mode); var to: Vector2=coordinate(Vector2(8,0),mode); var route: Dictionary=manager.route(from,to)
		check(not route["path"].is_empty() and manager.obstacles.size()==4,"Resident routing receives terrain hazards in its own coordinate system: "+mode)
		var dry: bool=true
		for point in route["path"]:
			var canonical: Vector2=Vector2(point.x+point.y,point.y-point.x) if mode=="2d" else point
			if world.terrain_traversal.depth(canonical)>.45: dry=false
		check(dry,"Every route waypoint avoids the actual pond: "+mode)
		var actor: Node=world.player; actor.set_physics_process(false); var start: Array=Traffic.world(Vector2(-8,0),mode,.02); actor.teleport_to(Vector2(start[0],start[1]) if mode=="2d" else Vector3(start[0],start[1],start[2])); await settle(); var index: int=0
		for frame in 3000:
			await physics_frame
			while index<route["path"].size() and manager.point(actor).distance_to(route["path"][index])<.16: index+=1
			if index>=route["path"].size(): break
			var direction: Vector2=(route["path"][index]-manager.point(actor)).normalized()
			if mode=="2d": actor.move_character(1.0/60,Vector2(direction.x*16,direction.y*8).normalized())
			else: actor.move_character(1.0/60,Vector3(direction.x,0,direction.y))
		check(index>=route["path"].size() and actor.recovery_count==0,"A real walking character follows the planned detour without water entry or recovery: "+mode+str(manager.point(actor)))
		var attempts: int=manager.route_attempts; var stamp: int=manager.scene_signature; doc.data["water_cells"]=[]; studio.changed(); manager.configure(doc.data,studio.library,world.instances,world.objects)
		check(manager.scene_signature!=stamp and manager.route_cache.is_empty() and manager.obstacles.is_empty(),"Draining the pond invalidates cached routes and removes hazards: "+mode)
		var direct: Dictionary=manager.route(from,to); check(length(direct["path"])<length(route["path"]),"Drained terrain restores a shorter direct route: "+mode)
		for x in range(-8,9):
			for z in range(-8,9): doc.data["terrain_vertices"].append({"cell":[x,z],"height":clampf(x*4,0,24)})
		check(not Nav.obstacles(doc.data).is_empty(),"Steep dry banks also produce navigation obstacles: "+mode)
		for vertex in doc.data["terrain_vertices"]: vertex["height"]=2
		doc.add("2d:Apartment_Brick" if mode=="2d" else "3d:HanX_City/Apartment_4F_A",[0,0,0] if mode=="2d" else [0,2,0],"SW" if mode=="2d" else "90"); doc.data["citizens"]["population"]=1; studio.changed(); manager.configure(doc.data,studio.library,world.instances,world.objects)
		check(manager.residents.size()==1 and is_instance_valid(manager.residents[0]["actor"]) and (mode=="2d" or absf(manager.residents[0]["actor"].position.y-2.05)<.01),"Homes on raised terrain spawn residents at the actual supported height: "+mode)
		doc.data["terrain"]["enabled"]=false; check(Nav.obstacles(doc.data).is_empty(),"Legacy flat mode has no terrain navigation obstacles: "+mode)
	studio.free(); print("TERRAIN NAVIGATION: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
