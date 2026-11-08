extends SceneTree
const Entries=preload("res://scripts/builder/floor_entrances.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for frame in 4: await physics_frame
	await process_frame
func run() -> void:
	var path: String="res://city.tscn"
	for mode in ["2d","3d"]:
		if "--"+mode in OS.get_cmdline_user_args(): path="res://output/floor_entrances_"+mode+".tscn"
	var scene: Node=load(path).instantiate(); root.add_child(scene)
	for frame in 6: await process_frame
	await physics_frame
	var mode: String=scene.dimension; var exploration: Node=scene.exploration; var player: Node=scene.player; var host: Dictionary={}
	for item in scene.live_data["objects"]:
		if not item.get("interior",{}).get("floor_entrances",[]).is_empty(): host=item; break
	check(not host.is_empty(),"The exported building retains its floor-specific entrance records")
	var authored: Dictionary=scene.studio_data.duplicate(true); var parent: Node=player.get_parent(); var original_zoom: Vector2=scene.camera.zoom if mode=="2d" else Vector2.ONE
	for entry in host["interior"]["floor_entrances"]:
		var outside: Variant=Entries.outside(exploration.instances[host["uid"]],host,entry,mode,exploration.library)
		player.teleport_to(outside); check(exploration.prompt().contains(Entries.name_for(host["interior"],entry["floor"])) and exploration.nearby["entry"]["uid"]==entry["uid"],"Exported proximity selects the named floor-specific entrance")
		exploration.interact(); var tab:=InputEventKey.new(); tab.keycode=KEY_TAB; tab.pressed=true; scene._unhandled_input(tab)
		check(exploration.entering and scene.walking and not player.is_physics_processing(),"An exported entry blocks camera-mode shortcuts while validating its landing")
		await settle()
		check(exploration.interior!=null and exploration.active_floor()==entry["floor"] and player.is_visible_in_tree() and player.is_physics_processing(),"The exported entrance reaches the selected floor and restores ordinary movement")
		var expected: Variant=Entries.landing(host["interior"],entry,mode)
		if mode=="3d": expected.y+=exploration.interior.floor_stack.heights[entry["floor"]]
		check(player.position.distance_to(expected)<.15 and player.recovery_count==0,"The exported landing retains its local coordinates and floor height without recovery")
		var exit_count: int=host["interior"]["floor_entrances"].filter(func(record: Dictionary)->bool:return record["floor"]==entry["floor"]).size()
		check(exploration.prompt().contains("Return outside") and exploration.exit_markers.get_child_count()==exit_count,"The selected floor exposes each of its independent exterior exits")
		exploration.interact(); check(exploration.interior==null and player.get_parent()==parent and player.position.distance_to(outside)<.01 and player.is_physics_processing(),"Normal exported exit restores exterior position, ownership and control")
		if mode=="2d": check(scene.camera.zoom==original_zoom and player.terrain_visual_offset==Vector2.ZERO,"The exported floor exit restores exterior zoom and clears height presentation")
	var upper: Dictionary=host["interior"]["floor_entrances"][0]; var point: Variant=Entries.outside(exploration.instances[host["uid"]],host,upper,mode,exploration.library)
	player.teleport_to(point); exploration.interact(); exploration.leave_interior(); await settle()
	check(exploration.interior==null and player.is_physics_processing() and not exploration.entering,"Cancelling an exported entry invalidates its pending landing check")
	# Test a real imported obstacle, without changing the saved authored data.
	player.teleport_to(point); exploration.interact()
	var local: Variant=Entries.landing(host["interior"],upper,mode); var blocker: Node=StaticBody2D.new() if mode=="2d" else StaticBody3D.new(); blocker.collision_layer=1; exploration.room_world(upper["floor"]).add_child(blocker)
	var shape: Node=CollisionShape2D.new() if mode=="2d" else CollisionShape3D.new()
	if mode=="2d": shape.shape=CircleShape2D.new(); shape.shape.radius=12; blocker.position=local
	else: shape.shape=BoxShape3D.new(); shape.shape.size=Vector3(1,2,1); blocker.position=local+Vector3.UP
	blocker.add_child(shape); await settle()
	check(exploration.interior==null and exploration.entrance_notice.contains("blocked") and player.is_physics_processing() and player.recovery_count==0,"An obstructed exported landing safely rejects the visit and restores control")
	check(scene.studio_data==authored,"Exported entrance use and rejection preserve the authored city and floor data")
	scene.free(); print("FLOOR ENTRANCES EXPORT: %d checks, %d failures"%[checks,failures]); quit(1 if failures else 0)
