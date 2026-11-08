extends SceneTree
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func move(player: CharacterBody3D,direction: Vector3,frames: int) -> void:
	for frame in frames:
		await physics_frame
		player.move_character(1.0/Engine.physics_ticks_per_second,direction)
	await process_frame
func run() -> void:
	var path: String="res://output/floor_stairs_export_3d.tscn" if "--local" in OS.get_cmdline_user_args() else "res://city.tscn"
	var scene: Node=load(path).instantiate(); root.add_child(scene)
	for frame in 6: await process_frame
	await physics_frame
	var before: Dictionary=scene.studio_data.duplicate(true); var player: CharacterBody3D=scene.player; player.set_physics_process(false)
	var entrance: Vector3=scene.exploration.entrance(scene.exploration.instances["building"])
	player.teleport_to(entrance); scene.exploration.interact()
	check(scene.exploration.interior!=null and scene.exploration.interior_uid=="building","Normal building interaction opens its owned stacked interior")
	var stack: Node3D=scene.exploration.interior.floor_stack
	check(stack.worlds.size()==2 and stack.worlds["upper"].instances.has("mixed_tile"),"Exported runtime loads the upper room and its upstairs-only projected floor asset")
	await move(player,Vector3.RIGHT,115); await move(player,Vector3.ZERO,15)
	check(player.position.x>3.2 and player.position.y>2.95 and stack.current_floor=="upper","Exported character climbs physical treads to the upper floor")
	check(player.step_count>0 and player.recovery_count==0,"Exported ascent uses step handling without recovery")
	var query:=PhysicsRayQueryParameters3D.create(Vector3(0,3.7,0),Vector3(0,2.8,0),2)
	check(player.get_world_3d().direct_space_state.intersect_ray(query).is_empty(),"Exported native/projected floor geometry leaves the physical stairwell open")
	await move(player,Vector3.LEFT,115); await move(player,Vector3.ZERO,15)
	check(player.position.x< -2.4 and absf(player.position.y)<0.05 and player.recovery_count==0,"Exported character descends to ground without recovery")
	scene.exploration.interact()
	check(scene.exploration.interior==null and player.position.distance_to(entrance)<0.01,"Normal exit interaction restores the authored exterior entrance")
	check(scene.studio_data==before,"Exported traversal leaves all authored floor and city data unchanged")
	scene.free(); print("FLOOR STAIRS EXPORT: %d checks, %d failures"%[checks,failures]); quit(1 if failures else 0)
