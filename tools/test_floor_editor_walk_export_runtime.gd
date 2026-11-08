extends SceneTree
const Fit=preload("res://scripts/builder/grid_fit.gd")
const Plan=preload("res://scripts/builder/floor_plan.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func stairs(exploration: Node,player: Node,mode: String,link: Dictionary) -> void:
	if mode=="2d":
		player.teleport_to(Fit.pixels(Vector2(link["start"][0],link["start"][1]))); exploration.interact()
		for frame in 2000:
			await physics_frame
			if exploration.interior.floor_stack.travel.is_empty(): break
	else:
		var direction:=Vector3(link["end"][0]-link["start"][0],0,link["end"][1]-link["start"][1]).normalized(); var height: float=exploration.interior.floor_stack.heights[link["lower"]]
		player.set_physics_process(false); player.teleport_to(Vector3(link["start"][0],height+.05,link["start"][1])-direction*.8)
		for frame in 160:
			await physics_frame; player.move_character(1.0/60,direction)
			if (player.position-Vector3(link["end"][0],player.position.y,link["end"][1])).dot(direction)>=.35: break
		for frame in 15: await physics_frame; player.move_character(1.0/60,Vector3.ZERO)
		player.set_physics_process(true)
	await process_frame
func wait_lift(lift: Node) -> void:
	for frame in 4000:
		await physics_frame
		if lift.phase in ["idle","blocked"]: break
	await process_frame
func run() -> void:
	var path: String="res://city.tscn"
	for mode in ["2d","3d"]:
		if "--"+mode in OS.get_cmdline_user_args(): path="res://output/floor_editor_walk_"+mode+".tscn"
	var scene: Node=load(path).instantiate(); root.add_child(scene)
	for frame in 6: await process_frame
	await physics_frame
	var mode: String=scene.dimension; var exploration: Node=scene.exploration; var player: Node=scene.player; var host: Dictionary={}
	for item in scene.live_data["objects"]:
		if item.get("interior",{}).get("floor_links",[]).size()==3: host=item; break
	check(not host.is_empty() and host["interior"]["floors"].size()==2 and not scene.studio_data.get("interior_room",false),"An export created inside editor Walk retains the city and every connected owned floor")
	if mode=="3d": check(scene.get_node("Foundation").visible and scene.get_node("Foundation").collision_layer==2 and scene.find_children("*","WorldEnvironment",true,false)[0].environment!=null,"The exported city retains exterior support and lighting despite being saved from a suspended room plane")
	else: check(scene.get_node("Ground").visible,"The exported city retains visible exterior ground")
	var authored: Dictionary=scene.studio_data.duplicate(true); var parent: Node=player.get_parent(); var entrance: Variant=exploration.entrance(exploration.instances[host["uid"]])
	player.teleport_to(entrance); exploration.interact()
	for frame in 3: await physics_frame
	check(exploration.interior!=null and not exploration.preview and exploration.active_floor()=="ground" and player.is_visible_in_tree(),"The scene opens a normal owned visit without depending on Studio preview state")
	await stairs(exploration,player,mode,host["interior"]["floor_links"][0]); check(exploration.active_floor()==host["interior"]["floor_links"][0]["upper"] and player.recovery_count==0,"The first exported flight reaches the middle floor without recovery")
	await stairs(exploration,player,mode,host["interior"]["floor_links"][1]); var top: String=host["interior"]["floor_links"][1]["upper"]
	check(exploration.active_floor()==top and player.recovery_count==0,"A second exported flight reaches the top during the same visit")
	var door: Node=exploration.room_world().instances["shared_door"]; var clear_door: bool=true
	for body in [door]+door.find_children("*","CollisionObject2D",true,false)+door.find_children("*","CollisionObject3D",true,false):
		if body is CollisionObject2D or body is CollisionObject3D: clear_door=clear_door and body.collision_layer==0
	check(Plan.room(host["interior"],top)["objects"][0]["open"] and not host["interior"]["objects"][0]["open"] and clear_door,"The scene retains the exact upstairs door edited during Studio Walk")
	var lift: Node=exploration.interior.floor_stack.lifts["lift"]; player.teleport_to(Fit.pixels(Vector2(4,-2.35)) if mode=="2d" else Vector3(4,6.05,-2.35)); exploration.interact(); await wait_lift(lift)
	check(lift.last_stop==top and exploration.active_floor()==top,"The exported upper-floor landing can call its elevator")
	player.teleport_to(Fit.pixels(Vector2(4,-4)) if mode=="2d" else Vector3(4,6.05,-4)); exploration.interact()
	check(lift.menu.visible and not player.is_physics_processing(),"The exported cabin retains its usable destination chooser")
	for button in lift.choices.get_children():
		if button is Button and button.get_meta("floor_uid","")=="ground": button.pressed.emit(); break
	await wait_lift(lift)
	check(lift.last_stop=="ground" and exploration.active_floor()=="ground" and player.is_physics_processing() and player.recovery_count==0,"The exported lift completes the combined multi-flight and elevator round trip")
	player.teleport_to(exploration.exit_position); exploration.interact()
	check(exploration.interior==null and player.get_parent()==parent and player.position.distance_to(entrance)<.01,"The exported ground exit restores exterior ownership and position")
	check(scene.studio_data==authored,"The export remains independent of editor state and preserves authored content during traversal")
	scene.free(); print("FLOOR EDITOR WALK EXPORT: %d checks, %d failures"%[checks,failures]); quit(1 if failures else 0)
