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
func displacement(node: Node) -> Vector2:
	var sprite: Sprite2D=node.get_node("Sprite2D"); return sprite.global_transform.basis_xform(node.terrain_visual_offset)
func run() -> void:
	var studio: Control=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio); await settle(); studio.switch_mode("2d")
	var doc=preload("res://scripts/builder/document.gd").new(); doc.data=preload("res://scripts/builder/templates.gd").make("2d","blank"); doc.data["objects"]=[]; doc.data["terrain"]={"enabled":false,"bounds":[-8,-8,16,16]}; doc.data["terrain_vertices"]=[]; doc.data["water_cells"]=[]
	for x in range(-8,9):
		for y in range(-8,9): doc.data["terrain_vertices"].append({"cell":[x,y],"height":2})
	var home: Dictionary=doc.add("2d:House_Blue",Traffic.world(Vector2(-6,-6),"2d"),"SE",.75); home["angle"]=37
	var model: Dictionary=doc.add("3d:HanX_Traffic/Bus_Stop",Traffic.world(Vector2(5,-5),"2d"),"90",.5)
	studio.documents["2d"]=doc; studio.changed(); await settle(); var world: Node=studio.worlds["2d"]; var presentation: Node=world.terrain_presentation
	var body: Node=world.instances[home["uid"]].get_node("StaticBody2D"); var original: Transform2D=body.global_transform; var logical: Vector2=world.instances[home["uid"]].position
	check(displacement(world.instances[home["uid"]]).is_zero_approx() and not presentation.is_processing(),"Flat legacy cities retain original visuals without per-frame terrain processing")
	doc.data["terrain"]["enabled"]=true; studio.changed(); await settle()
	check(displacement(world.instances[home["uid"]]).distance_to(Vector2(0,-16))<.001,"Scaled and rotated native props receive a world-vertical terrain offset")
	check(displacement(world.instances[model["uid"]]).distance_to(Vector2(0,-16))<.001,"Projected models receive the same terrain elevation")
	check(body.global_transform==original and world.instances[home["uid"]].position==logical,"Presentation leaves collision anchors and authored object coordinates unchanged")
	world.preview(home["asset"],home["position"],home["direction"],home["scale"],true)
	check(displacement(world.ghost).distance_to(Vector2(0,-16))<.001,"Placement ghosts use the same terrain height as committed props")
	world.show_selection(home["uid"]); check(world.selection.position.distance_to(logical+Vector2(0,-16))<.001,"Object selection outlines follow elevated artwork")
	world.show_tile_selection(Vector2i.ZERO); check(world.selection.points[0].distance_to(Vector2(0,-16))<.001,"Ground tile selection corners follow the terrain surface")
	var actor: Node=load("res://scenes/items/Characters/Office_Worker.tscn").instantiate(); world.objects.add_child(actor); actor.set_physics_process(false); actor.is_player_controlled=false; actor.collision_layer=0; actor.collision_mask=0; actor.move_speed=24; actor.teleport_to(Vector2.ZERO); presentation.refresh()
	check(displacement(actor).distance_to(Vector2(0,-16))<.001 and actor.get_meta("terrain_height")==2,"New runtime characters automatically bind to terrain presentation")
	actor.direction="NW"; actor._update_animation(.2); presentation.refresh(); check(displacement(actor).distance_to(Vector2(0,-16))<.001,"Character view and animation changes preserve terrain elevation")
	world.instances[model["uid"]].direction="180"; presentation.refresh(); check(displacement(world.instances[model["uid"]]).distance_to(Vector2(0,-16))<.001,"Model source-view updates preserve terrain elevation")
	var point:=Vector2(1,1); var pixel: Vector2=world.get_viewport().get_canvas_transform()*Plan.project_2d(Vector3(point.x,2,point.y)); var picked: Array=world.point(pixel,false,0)
	check(Traffic.metric(picked,"2d").distance_to(point)<.001 and picked[2]==0,"Ordinary placement picking returns logical ground coordinates on raised terrain")
	for vertex in doc.data["terrain_vertices"]: vertex["height"]=2+vertex["cell"][0]*.2
	studio.changed(); await settle(); var raw: Array=Traffic.world(Vector2(-4,0),"2d"); actor.teleport_to(Vector2(raw[0],raw[1])); presentation.refresh(); var start: Vector2=actor.position
	for frame in 30:
		await physics_frame; actor.move_character(1.0/60,Vector2(8,4).normalized()); presentation.refresh()
	var ground: Vector2=Traffic.metric([actor.position.x,actor.position.y,0],"2d"); var height: float=Plan.sample(doc.data,ground)["height"]
	check(actor.position.distance_to(start)>5 and displacement(actor).distance_to(Vector2(0,-height*8))<.001,"Walking characters update their visual height continuously over slopes")
	check(actor.recovery_count==0,"Terrain presentation does not teleport walking characters")
	var actor_id: int=actor.get_instance_id(); actor.free(); presentation.refresh(); check(not presentation.actors.has(actor_id),"Freed runtime actors leave no stale presentation bindings")
	studio.set_walking(true); world.player.set_physics_process(false); world.player.teleport_to(world.exploration.entrance(world.instances[home["uid"]])); world.exploration.interact(); await settle(); presentation.refresh()
	check(world.exploration.interior!=null and world.player.terrain_visual_offset.is_zero_approx(),"Interior visits remove exterior height from the shared exploration character")
	check(not world.terrain_traversal.active(),"Interior visits suspend exterior terrain movement restrictions")
	world.exploration.leave_interior(); studio.set_walking(false); await settle(); presentation.refresh(); check(not displacement(world.instances[home["uid"]]).is_zero_approx(),"Returning outside restores object elevation")
	var player_ground: Vector2=Traffic.metric([world.player.position.x,world.player.position.y,0],"2d")
	check(presentation.actors.has(world.player.get_instance_id()) and absf(float(world.player.get_meta("terrain_height"))-float(Plan.sample(doc.data,player_ground)["height"]))<0.00001,"Returning the character to its original parent reacquires exterior terrain presentation")
	var before: Dictionary=doc.data.duplicate(true); var path: String="res://output/terrain_presentation_2d.tscn"; check(studio.Exporter.save_scene(world,doc.data,studio.library,path)==OK,"Terrain-height presentations export as ordinary city data")
	var viewport:=SubViewport.new(); viewport.size=Vector2i(1000,700); root.add_child(viewport); var playable: Node=load(path).instantiate(); viewport.add_child(playable); await settle(); playable.player.set_physics_process(false); playable.terrain_presentation.refresh()
	check(displacement(playable.city_instances[home["uid"]]).distance_to(displacement(world.instances[home["uid"]]))<.001,"Playable props rebuild the same visual elevation from authored records")
	check(doc.data==before,"Live elevation never writes visual offsets into the authored document")
	viewport.free(); doc.data["terrain"]["enabled"]=false; studio.changed(); await settle()
	check(world.instances[home["uid"]].terrain_visual_offset.is_zero_approx() and world.instances[model["uid"]].terrain_visual_offset.is_zero_approx() and not presentation.is_processing() and presentation.actors.is_empty(),"Disabling terrain restores visuals and releases actor tracking")
	world.preview(home["asset"],home["position"],home["direction"],home["scale"],true); check(world.ghost.terrain_visual_offset.is_zero_approx(),"Disabling terrain restores the legacy placement preview")
	studio.free(); print("TERRAIN PRESENTATION 2D: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
