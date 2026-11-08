extends SceneTree
const Fit=preload("res://scripts/builder/grid_fit.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func move(player: Node,mode: String,direction: int,frames: int) -> void:
	player.set_physics_process(false)
	for frame in frames:
		await physics_frame; player.move_character(1.0/60,Fit.pixels(Vector2(0,direction)).normalized() if mode=="2d" else Vector3(0,0,direction))
	for frame in 15:
		await physics_frame; player.move_character(1.0/60,Vector2.ZERO if mode=="2d" else Vector3.ZERO)
	await process_frame
func wait_lift(lift: Node) -> void:
	for frame in 4000:
		await physics_frame
		if lift.phase in ["idle","blocked"]: break
	await process_frame
func select_floor(lift: Node,uid: String) -> void:
	for button in lift.choices.get_children():
		if button is Button and button.get_meta("floor_uid","")==uid: button.pressed.emit(); return
	check(false,"Exported floor chooser contains destination")
func run() -> void:
	var path: String="res://city.tscn"
	for mode in ["2d","3d"]:
		if "--"+mode in OS.get_cmdline_user_args(): path="res://output/floor_elevator_"+mode+".tscn"
	var scene: Node=load(path).instantiate(); root.add_child(scene)
	for frame in 6: await process_frame
	await physics_frame
	var mode: String=scene.dimension; var player: Node=scene.player; var exploration: Node=scene.exploration; var host: Dictionary={}; var record: Dictionary={}
	for item in scene.live_data["objects"]:
		for link in item.get("interior",{}).get("floor_links",[]):
			if link["kind"]=="elevator": host=item; record=link; break
	check(not host.is_empty(),"The exported city retains its authored elevator")
	var before: Dictionary=scene.studio_data.duplicate(true); var parent: Node=player.get_parent(); var entrance: Variant=exploration.entrance(exploration.instances[host["uid"]])
	player.teleport_to(entrance); exploration.interact()
	for frame in 3: await physics_frame
	var lift: Node=exploration.interior.floor_stack.lifts[record["uid"]]; var middle: String=lift.stops[1]["uid"]; var top: String=lift.stops[-1]["uid"]
	check(lift.stops.size()==3 and player.is_visible_in_tree(),"An ordinary exported visit loads every elevator stop and retains the character")
	player.teleport_to(Fit.pixels(Vector2(0,2.5)) if mode=="2d" else Vector3(0,0.05,2.5)); await move(player,mode,-1,40)
	check(lift.view.fully_inside(),"The exported character physically enters the open cabin")
	player.set_physics_process(true); exploration.interact()
	var tab:=InputEventKey.new(); tab.keycode=KEY_TAB; tab.pressed=true; scene._unhandled_input(tab)
	check(lift.menu.visible and scene.walking and not player.is_physics_processing(),"The exported floor chooser captures control and blocks camera-mode shortcuts")
	select_floor(lift,middle); await wait_lift(lift)
	check(lift.phase=="idle" and lift.last_stop==middle and exploration.active_floor()==middle and player.is_physics_processing(),"The exported cabin delivers its passenger and restores control")
	check(player.recovery_count==0,"The exported ride does not recover or reposition a stuck character")
	await move(player,mode,1,36); lift.request(top); await wait_lift(lift)
	check(lift.last_stop==top and exploration.active_floor()==middle,"An exported empty-cabin trip leaves the waiting character on its floor")
	exploration.interact(); await wait_lift(lift); check(lift.last_stop==middle,"The exported landing call returns the cabin")
	await move(player,mode,-1,36); player.set_physics_process(true); exploration.interact(); select_floor(lift,"ground"); await wait_lift(lift)
	check(lift.last_stop=="ground" and exploration.active_floor()=="ground" and player.recovery_count==0,"The exported elevator supports a safe round trip")
	if mode=="2d":
		player.set_physics_process(true); exploration.interact(); select_floor(lift,top)
		for frame in 2000:
			await physics_frame
			if lift.height>=28: break
		await process_frame
		check(lift.rider and lift.height>=28 and scene.camera.position.distance_to(player.position+player.terrain_visual_offset)<8,"The exported camera follows its visible passenger throughout a long elevator trip")
		await wait_lift(lift)
		check(lift.last_stop==top and exploration.active_floor()==top and not player.has_meta("floor_travel_height"),"Long-trip arrival clears the temporary camera elevation")
		exploration.interact(); select_floor(lift,"ground"); await wait_lift(lift)
		check(lift.last_stop=="ground" and player.is_physics_processing() and player.recovery_count==0,"The exported passenger safely returns from the highest supported floor")
	player.teleport_to(exploration.exit_position); exploration.interact()
	check(exploration.interior==null and player.get_parent()==parent and player.position.distance_to(entrance)<0.01,"Normal exported exit restores exterior position and character ownership")
	check(scene.studio_data==before,"Exported calls and rides preserve all authored city and floor records")
	scene.free(); print("FLOOR ELEVATOR EXPORT: %d checks, %d failures"%[checks,failures]); quit(1 if failures else 0)
