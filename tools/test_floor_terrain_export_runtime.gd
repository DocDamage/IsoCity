extends SceneTree
const Terrain=preload("res://scripts/builder/terrain_plan.gd")
const Fit=preload("res://scripts/builder/grid_fit.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for frame in 5: await physics_frame
	await process_frame
func place(player: Node,mode: String,point: Vector2,world: Node) -> void:
	if mode=="2d": player.teleport_to(Terrain.project_2d(Vector3(point.x,0,point.y)))
	else:
		var height: float=world.terrain_traversal.sample_at(point)["height"]+.025
		var query:=PhysicsRayQueryParameters3D.create(world.to_global(Vector3(point.x,height+.5,point.y)),world.to_global(Vector3(point.x,height-.1,point.y)),2,[player.get_rid()])
		var hit: Dictionary=player.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty(): height=world.to_local(hit["position"]).y+.025
		player.teleport_to(player.get_parent().to_local(world.to_global(Vector3(point.x,height,point.y))))
func water_walk(exploration: Node,player: Node,mode: String) -> void:
	place(player,mode,Vector2(0,3),exploration.room_world()); player.set_physics_process(false)
	for frame in 100:
		await physics_frame; player.move_character(1.0/60,Fit.pixels(Vector2.RIGHT).normalized() if mode=="2d" else Vector3.RIGHT)
	await process_frame
func wait_lift(lift: Node) -> void:
	for frame in 4000:
		await physics_frame
		if lift.phase in ["idle","blocked"]: break
	await process_frame
func run() -> void:
	var path: String="res://city.tscn"
	for mode in ["2d","3d"]:
		if "--"+mode in OS.get_cmdline_user_args(): path="res://output/floor_terrain_"+mode+".tscn"
	var scene: Node=load(path).instantiate(); root.add_child(scene)
	for frame in 6: await process_frame
	await physics_frame
	var mode: String=scene.dimension; var player: Node=scene.player; var exploration: Node=scene.exploration; var host: Dictionary={}
	for item in scene.live_data["objects"]:
		if not item.get("interior",{}).get("floor_links",[]).is_empty(): host=item; break
	check(not host.is_empty() and host["interior"]["terrain"]["enabled"] and host["interior"]["floors"][0]["room"]["terrain"]["enabled"],"The exported city retains independent sculpted floors")
	var authored: Dictionary=scene.studio_data.duplicate(true); var parent: Node=player.get_parent(); var entrance: Variant=exploration.entrance(exploration.instances[host["uid"]]); var source_filter: Callable=player.terrain_motion_filter
	player.teleport_to(entrance); exploration.interact(); await settle()
	check(exploration.interior!=null and exploration.active_floor()=="ground" and player.is_visible_in_tree() and player.is_physics_processing(),"The exported terrain visit finds a supported room start and restores control")
	check(player.terrain_motion_filter.get_object()==exploration.room_traversal,"The exported real walker uses its current room's terrain binding")
	place(player,mode,Vector2(-6,-6),exploration.room_world()); player.set_physics_process(false); await settle()
	check(is_equal_approx(float(player.get_meta("terrain_height",0)),.6) if mode=="2d" else absf(player.position.y-.625)<.02,"The exported raised room uses physical or projected terrain elevation")
	await water_walk(exploration,player,mode)
	check(exploration.room_world().terrain_traversal.metric(player.global_position).x<2.4 and "Deep water" in player.movement_hint() and player.recovery_count==0,"Exported room walking obeys its own deep-water boundary")
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
	check(exploration.active_floor()=="upper" and player.recovery_count==0,"The exported flight reaches upstairs through clipped terrain and road collision")
	place(player,mode,Vector2(-6,6),exploration.room_world()); await settle()
	check(exploration.active_floor()=="upper" and (is_equal_approx(float(player.get_meta("terrain_height",0)),-1.5) if mode=="2d" else absf(player.position.y-1.525)<.02),"The exported deep depression retains its owning upstairs floor")
	if mode=="3d": check(not player.terrain_position_safe.call(Vector3(0,.625,6)),"Packaged upstairs recovery rejects a supported point from a lower room")
	await water_walk(exploration,player,mode)
	check(exploration.room_world().terrain_traversal.metric(player.global_position).x<2.4 and "Deep water" in player.movement_hint(),"The exported upper floor uses its own water and height records")
	var lift: Node=exploration.interior.floor_stack.lifts["lift"]
	if mode=="2d": player.teleport_to(Fit.pixels(Vector2(4,-2.35)))
	else: place(player,mode,Vector2(4,-2.35),exploration.room_world())
	exploration.interact(); await wait_lift(lift)
	check(lift.phase=="idle" and lift.last_stop=="upper","The exported elevator accepts a call above sculpted rooms")
	for frame in 60:
		await physics_frame; player.move_character(1.0/60,Fit.pixels(Vector2(0,-1)).normalized() if mode=="2d" else Vector3(0,0,-1))
		if lift.view.fully_inside(): break
	player.velocity=Vector2.ZERO if mode=="2d" else Vector3.ZERO; player.set_physics_process(true); exploration.interact()
	check(lift.menu.visible and not player.is_physics_processing(),"The exported character can walk through the road landing into the cabin")
	lift.choose("ground"); await wait_lift(lift)
	check(lift.phase=="idle" and exploration.active_floor()=="ground" and player.is_physics_processing() and player.recovery_count==0,"The exported elevator travels through open terrain shafts and restores control")
	exploration.prompt(); player.teleport_to(exploration.exit_position); exploration.interact(); await settle()
	check(exploration.interior==null and player.get_parent()==parent and player.terrain_motion_filter.get_object()==source_filter.get_object(),"The exported exit restores exterior ownership and terrain callbacks")
	check(is_equal_approx(float(player.get_meta("terrain_height",0)),2) if mode=="2d" else absf(player.position.y-entrance.y)<.1,"The exported exit reacquires exterior terrain height")
	check(scene.studio_data==authored,"Sculpted exported visits preserve all authored city, floor, water and road records")
	scene.free(); print("FLOOR TERRAIN EXPORT: %d checks, %d failures"%[checks,failures]); quit(1 if failures else 0)
