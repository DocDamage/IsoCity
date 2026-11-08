extends SceneTree
const Fit=preload("res://scripts/builder/grid_fit.gd")
const Plan=preload("res://scripts/builder/floor_plan.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func wait_stairs(stack: Node) -> void:
	for frame in 1000:
		await physics_frame
		if stack.travel.is_empty(): break
	await process_frame
func move(player: Node,direction: Vector3,frames: int) -> void:
	for frame in frames:
		await physics_frame; player.move_character(1.0/Engine.physics_ticks_per_second,direction)
	await process_frame
func run() -> void:
	var path: String="res://city.tscn"
	for mode in ["2d","3d"]:
		if "--"+mode in OS.get_cmdline_user_args(): path="res://output/floor_connections_"+mode+".tscn"
	var scene: Node=load(path).instantiate(); root.add_child(scene)
	for frame in 6: await process_frame
	await physics_frame
	var mode: String=scene.dimension; var player: Node=scene.player; var exploration: Node=scene.exploration; var host: Dictionary={}
	for item in scene.live_data["objects"]:
		if not item.get("interior",{}).get("floor_links",[]).is_empty(): host=item; break
	check(not host.is_empty(),"The UI-authored building retains its connection records in the exported scene")
	var before: Dictionary=scene.studio_data.duplicate(true); var original_parent: Node=player.get_parent(); var original_zoom: Vector2=scene.camera.zoom if mode=="2d" else Vector2.ONE
	var entrance: Variant=exploration.entrance(exploration.instances[host["uid"]]); player.teleport_to(entrance); exploration.interact()
	for frame in 3: await physics_frame
	check(exploration.interior!=null and player.is_visible_in_tree(),"Ordinary exported entrance interaction retains the visible character")
	var upper_uid: String=host["interior"]["floors"][0]["uid"]; var stack: Node=exploration.interior.floor_stack
	if mode=="2d":
		player.teleport_to(Fit.pixels(Vector2(-2,0))); exploration.interact(); await wait_stairs(stack)
		check(stack.travel.is_empty() and stack.notice.is_empty() and player.is_physics_processing(),"Exported 2D stair animation restores ordinary player control")
	else:
		player.set_physics_process(false); player.teleport_to(Vector3(-4,0.05,0)); await move(player,Vector3.RIGHT,115); await move(player,Vector3.ZERO,15)
	check(exploration.active_floor()==upper_uid and player.recovery_count==0,"The UI-authored flight reaches its upper floor without recovery")
	var node: Node=exploration.room_world().instances["shared_door"]
	player.teleport_to(node.global_position+(Vector2(0,24) if mode=="2d" else Vector3(0,0,1.5))); exploration.interact()
	check(Plan.room(host["interior"],upper_uid)["objects"][0]["open"] and not host["interior"]["objects"][0]["open"],"Exported door interaction targets upstairs when ground uses the same local UID")
	exploration.interact(); check(not Plan.room(host["interior"],upper_uid)["objects"][0]["open"],"The exported upstairs door closes and retains its own state")
	if mode=="2d":
		player.teleport_to(Fit.pixels(Vector2(3,0))); exploration.interact(); await wait_stairs(stack)
	else:
		player.teleport_to(Vector3(4,3.05,0)); await move(player,Vector3.LEFT,115); await move(player,Vector3.ZERO,15)
	check(exploration.active_floor()=="ground" and player.recovery_count==0,"The exported connection supports descent to ground without recovery")
	player.teleport_to(exploration.exit_position); exploration.interact()
	check(exploration.interior==null and player.get_parent()==original_parent and player.position.distance_to(entrance)<0.01,"Ordinary exported exit restores the exterior position and original player ownership")
	if mode=="2d": check(scene.camera.zoom==original_zoom and player.terrain_visual_offset==Vector2.ZERO,"Exported 2D exit restores exterior zoom and clears stair presentation")
	check(scene.studio_data==before,"Traversal and reversible door use preserve all authored floor/city data")
	scene.free(); print("FLOOR CONNECTIONS EXPORT: %d checks, %d failures"%[checks,failures]); quit(1 if failures else 0)
