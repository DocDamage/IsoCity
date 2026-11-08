extends SceneTree
const Plan=preload("res://scripts/builder/terrain_plan.gd")
const Traffic=preload("res://scripts/builder/traffic_plan.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for frame in 5: await process_frame
	await physics_frame
func position(point: Vector2,mode: String,height: float=-1.98) -> Variant:
	var raw: Array=Traffic.world(point,mode,height)
	return Vector2(raw[0],raw[1]) if mode=="2d" else Vector3(raw[0],raw[1],raw[2])
func ground(actor: Node,mode: String) -> Vector2:
	return Traffic.metric([actor.position.x,actor.position.y,0],mode) if mode=="2d" else Vector2(actor.position.x,actor.position.z)
func move(actor: Node,mode: String,direction: Vector2,frames: int=90) -> void:
	for frame in frames:
		await physics_frame
		if mode=="2d": actor.move_character(1.0/60,Vector2((direction.x-direction.y)*8,(direction.x+direction.y)*4).normalized())
		else: actor.move_character(1.0/60,Vector3(direction.x,0,direction.y))
func run() -> void:
	var studio: Control=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio); await settle()
	for mode in ["2d","3d"]:
		studio.switch_mode(mode)
		var doc=preload("res://scripts/builder/document.gd").new(); doc.data=preload("res://scripts/builder/templates.gd").make(mode,"blank"); doc.data["objects"]=[]; doc.data["terrain"]={"enabled":true,"bounds":[-8,-8,16,16]}; doc.data["terrain_vertices"]=[]; doc.data["water_cells"]=[]
		for x in range(-8,9):
			for z in range(-8,9): doc.data["terrain_vertices"].append({"cell":[x,z],"height":-2})
		for x in range(0,4):
			for z in range(-4,4): doc.data["water_cells"].append({"cell":[x,z],"level":0})
		studio.documents[mode]=doc; studio.changed(); await settle()
		var world: Node=studio.worlds[mode]; var actor: Node=world.player; var traversal: Node=world.terrain_traversal; actor.set_physics_process(false); actor.teleport_to(position(Vector2(-2,0),mode)); await settle()
		check(actor.terrain_motion_filter.is_valid() and actor.terrain_position_safe.is_valid(),"The exterior player binds terrain traversal: "+mode)
		await move(actor,mode,Vector2.RIGHT)
		check(ground(actor,mode).x<.01 and ground(actor,mode).x>-.7 and actor.recovery_count==0,"Real walking stops at deep water without recovery teleportation: "+mode+str(ground(actor,mode)))
		check("Deep water" in actor.movement_hint(),"Walking explains the blocked shoreline: "+mode)
		var start: Vector2=ground(actor,mode); await move(actor,mode,Vector2.DOWN,30)
		check(ground(actor,mode).y>start.y+.5 and ground(actor,mode).x<.01,"Characters can continue along the shoreline: "+mode)
		check(not actor.terrain_position_safe.call(actor.get_parent().to_global(position(Vector2(2,0),mode))) and actor.terrain_position_safe.call(actor.get_parent().to_global(position(Vector2(-2,0),mode))),"Recovery excludes flooded positions and accepts dry land: "+mode)
		actor.teleport_to(position(Vector2(2,0),mode)); await move(actor,mode,Vector2.LEFT,120)
		check(ground(actor,mode).x<0,"An actor caught by newly edited water can walk back to shore: "+mode)
		for water in doc.data["water_cells"]: water["level"]=-1.8
		studio.changed(); actor.teleport_to(position(Vector2(-2,0),mode)); await settle(); await move(actor,mode,Vector2.RIGHT,60)
		check(ground(actor,mode).x>.5,"Shallow water remains walkable: "+mode)
		var dynamic: Node=load("res://scenes/items/Characters/Office_Worker.tscn").instantiate() if mode=="2d" else preload("res://scripts/builder/player_3d.gd").new(); world.objects.add_child(dynamic); dynamic.set_physics_process(false)
		check(dynamic.terrain_motion_filter.is_valid(),"New runtime residents and workers automatically bind traversal: "+mode); dynamic.free()
		for water in doc.data["water_cells"]: water["level"]=0
		studio.changed(); var saved: Dictionary=doc.data.duplicate(true); var path: String="res://output/terrain_traversal_"+mode+".tscn"; check(studio.Exporter.save_scene(world,doc.data,studio.library,path)==OK,"Traversal scene exports: "+mode)
		var viewport:=SubViewport.new(); viewport.size=Vector2i(1000,700); root.add_child(viewport); var playable: Node=load(path).instantiate(); viewport.add_child(playable); await settle(); playable.player.set_physics_process(false)
		check(playable.player.terrain_motion_filter.is_valid() and not playable.player.terrain_position_safe.call(playable.player.get_parent().to_global(position(Vector2(2,0),mode))),"Playable scenes rebuild identical water restrictions: "+mode)
		viewport.free(); check(doc.data==saved,"Walking and exporting preserve authored terrain: "+mode)
		doc.data["terrain"]["enabled"]=false; studio.changed(); check(not actor.terrain_motion_filter.is_valid() and not actor.terrain_position_safe.is_valid(),"Disabling terrain releases movement callbacks: "+mode)
	# A 2D sprite cannot rely on physical vertical walls, so test steep banks
	# and patch boundaries through the same filter used by actual movement.
	studio.switch_mode("2d"); var doc: RefCounted=studio.documents["2d"]; doc.data["terrain"]["enabled"]=true; doc.data["water_cells"]=[]
	for vertex in doc.data["terrain_vertices"]: vertex["height"]=clampf(vertex["cell"][0]*4,0,24)
	studio.changed(); var world: Node=studio.worlds["2d"]; var actor: Node=world.player; actor.teleport_to(position(Vector2(-2,0),"2d")); await settle(); await move(actor,"2d",Vector2.RIGHT)
	check(ground(actor,"2d").x<.1 and "steep" in actor.movement_hint(),"2D walking cannot climb a bank steeper than the 3D floor limit")
	actor.teleport_to(position(Vector2(2,0),"2d")); await move(actor,"2d",Vector2.LEFT,60); check(ground(actor,"2d").x<1,"Characters can retreat down a steep bank")
	for vertex in doc.data["terrain_vertices"]: vertex["height"]=4
	studio.changed(); var from: Vector2=world.to_global(position(Vector2(15.9,0),"2d")); var to: Vector2=world.to_global(position(Vector2(16.1,0),"2d")); check("edge" in world.terrain_traversal.blocked(from,to),"Abrupt height differences at terrain patch boundaries cannot be crossed in 2D")
	studio.free(); print("TERRAIN TRAVERSAL: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
