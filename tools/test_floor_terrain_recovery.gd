extends SceneTree
const Entries=preload("res://scripts/builder/floor_entrances.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var scene: Node=load("res://output/floor_terrain_3d.tscn").instantiate(); root.add_child(scene)
	for frame in 5: await process_frame
	var player: Node=scene.player; var exploration: Node=scene.exploration; var host: Dictionary={}
	for item in scene.live_data["objects"]:
		if not item.get("interior",{}).get("floor_links",[]).is_empty(): host=item; break
	# A taller valid storey gives the downstairs candidate enough capsule
	# headroom to expose recovery ownership, independently of ceiling rejection.
	host["interior"]["floors"][0]["height"]=4; host["interior"]["floor_links"][0]["end"][0]=3
	check(preload("res://scripts/builder/document.gd").valid(scene.studio_data,"3d",exploration.library),"The taller recovery fixture remains valid authored project data")
	var authored: Dictionary=scene.studio_data.duplicate(true); var entry: Dictionary=host["interior"]["floor_entrances"][0]
	player.set_physics_process(false); player.teleport_to(Entries.outside(exploration.instances[host["uid"]],host,entry,"3d",exploration.library)); exploration.interact()
	for frame in 5: await physics_frame
	check(exploration.active_floor()=="upper" and absf(player.position.y-3.525)<.01,"Recovery starts in the actual upstairs depression")
	var foreign:=Vector3(0,.625,6)
	check(not player.terrain_position_safe.call(foreign),"Upstairs safety rejects a supported downstairs position")
	player.safe_positions.assign([foreign])
	check(player.recover_to_safe() and player.position.y>3.4 and exploration.active_floor()=="upper" and player.recovery_count==1,"Recovery selects supported ground owned by the current sculpted room")
	var room: Node=exploration.room_world(); var platform:=StaticBody3D.new(); platform.collision_layer=2; room.objects.add_child(platform); platform.position=Vector3(-6,1.5,-6)
	var shape:=CollisionShape3D.new(); shape.shape=BoxShape3D.new(); shape.shape.size=Vector3(2,.2,2); platform.add_child(shape)
	for frame in 2: await physics_frame
	check(player.terrain_position_safe.call(room.to_global(Vector3(-6,1.625,-6))),"An elevated prop owned by this room remains a valid recovery surface")
	check(scene.studio_data==authored,"Recovery and support probes preserve every authored floor record")
	scene.free(); print("FLOOR TERRAIN RECOVERY: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
