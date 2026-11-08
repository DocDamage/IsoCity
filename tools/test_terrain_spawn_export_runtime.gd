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
	var before: Dictionary=scene.studio_data.duplicate(true); var player: Node=scene.player; player.set_physics_process(false)
	check(scene.terrain_traversal.safe_position(player.global_position) and scene.terrain_traversal.metric(player.global_position).length()>4,"Relocated startup resolves the submerged authored position to a dry landing")
	check(player.is_player_controlled if scene.dimension=="2d" else player.active and player.position.y>=2,"Relocated terrain starts with an active supported character")
	for frame in 90:
		await physics_frame
		if scene.dimension=="2d": player.move_character(1.0/60,Vector2.ZERO)
		else: player.move_character(1.0/60,Vector3.ZERO)
	check(player.recovery_count==0 and scene.terrain_traversal.safe_position(player.global_position),"Relocated startup remains supported through actual physics without recovery")
	check(scene.studio_data==before,"Relocated safe-spawn selection preserves authored coordinates")
	scene.free(); print("TERRAIN SPAWN EXPORT: %d checks, %d failures"%[checks,failures]); quit(1 if failures else 0)
