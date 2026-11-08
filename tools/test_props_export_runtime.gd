extends SceneTree
const Plan=preload("res://scripts/builder/prop_plan.gd")
const Floors=preload("res://scripts/builder/floor_plan.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for frame in 8: await physics_frame
	await process_frame
func capture(mode: String,stage: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	for frame in 5: await process_frame
	RenderingServer.force_draw(false); RenderingServer.force_draw(false); root.get_texture().get_image().save_png("res://output/props_export_"+mode+"_"+stage+".png")
func press(scene: Node) -> void:
	var key:=InputEventKey.new(); key.keycode=KEY_E; key.pressed=true; scene._unhandled_input(key)
func place(exploration: Node,uid: String) -> Dictionary:
	var context: Dictionary=Plan.context(exploration)
	for item in context["data"]["objects"]:
		if item["uid"]!=uid: continue
		var candidate: Dictionary=context.duplicate(false); candidate["item"]=item; candidate["node"]=context["instances"][uid]; candidate["profile"]=Plan.profile(item)
		var point: Variant=Plan.ground_point(candidate,exploration,"approach"); exploration.player.teleport_to(exploration.player.get_parent().to_local(point)); exploration.player.set_physics_process(false); return candidate
	return {}
func tick(runtime: Node,seconds: float) -> void:
	for frame in ceili(seconds*60): runtime._physics_process(1.0/60)
func change_floor(exploration: Node,uid: String) -> void:
	if exploration.dimension=="2d": exploration.interior.floor_stack.switch_floor(uid)
	else:
		var passage: Array=exploration.owned_room["floor_links"][0]["end"]; var height: float=exploration.interior.floor_stack.heights[uid]
		exploration.player.teleport_to(Vector3(passage[0],height+.05,passage[1])); exploration.interior.floor_stack.update_visibility()
	exploration.props._physics_process(1.0/60)
func run() -> void:
	var path: String="res://city.tscn"
	for mode in ["2d","3d"]:
		if "--"+mode in OS.get_cmdline_user_args(): path="res://output/props_"+mode+".tscn"
	var scene: Node=load(path).instantiate(); root.add_child(scene); await settle(); scene.player.set_physics_process(false)
	var mode: String=scene.dimension; var exploration: Node=scene.exploration; var runtime: Node=exploration.props; var before: Dictionary=scene.studio_data.duplicate(true)
	check(runtime!=null and Plan.definitions()["kinds"].size()==5,"Playable export includes the actual prop controller and catalog")
	var bench: Dictionary=scene.live_data["objects"].filter(func(item: Dictionary)->bool:return Plan.profile(item).get("kind","")=="seat")[0]; place(exploration,bench["uid"]); press(scene)
	check(not runtime.active.is_empty() and runtime.active["item"]["uid"]==bench["uid"] and not scene.player.is_physics_processing(),"Actual exported E input seats and locks the transient controller")
	await capture(mode,"outside_seat"); press(scene); check(runtime.active.is_empty() and scene.player.collision_mask==(1 if mode=="2d" else 3),"Exported E restores standing and collision state")
	var mixed: Dictionary=place(exploration,"authored_mixed"); press(scene); var point: Variant=Plan.global_point(mixed,exploration)
	check(not runtime.active.is_empty() and (scene.player.body.global_position+Vector3.UP*.85).distance_to(point)<.01 if mode=="3d" else not runtime.active.is_empty(),"Mixed-source furniture remains usable in the exported world")
	if mode=="3d":
		scene.yaw+=53; scene._process(1.0/60); runtime._process(0); point=Plan.global_point(mixed,exploration)
		check((scene.player.body.global_position+Vector3.UP*.85).distance_to(point)<.01,"Billboard seating follows the current exported camera orientation")
	press(scene); place(exploration,"authored_swing"); press(scene); var start: Variant=scene.player.interaction_visual_offset if mode=="2d" else scene.player.body.global_position; tick(runtime,.5)
	check(not runtime.active.is_empty() and (scene.player.interaction_visual_offset if mode=="2d" else scene.player.body.global_position)!=start,"Exported playground swing animates its real rider and rig")
	await capture(mode,"swing"); press(scene); check(runtime.active.is_empty() and runtime.swing.candidate.is_empty(),"Stopping an exported swing restores original artwork and frees the rig")
	press(scene); tick(runtime,.25); check(not runtime.active.is_empty() and runtime.swing.ropes.all(func(rope: MeshInstance3D)->bool:return is_instance_valid(rope)),"Repeated exported swing rides retain valid fresh rig parts"); press(scene)
	place(exploration,"authored_slide"); press(scene); tick(runtime,6); check(runtime.active.is_empty(),"Exported slide completes its ride and releases the controller")
	place(exploration,"authored_switch"); press(scene); check(runtime.states.get("city:authored_appliance",{}).get("on",false) and runtime.effects.entries.has("city:authored_appliance"),"Exported linked switch powers the actual appliance effect")
	check(not runtime.effects.entries["city:authored_switch"]["light"].visible and runtime.effects.entries["city:authored_appliance"]["light"].visible,"Exported linked switch changes only its controlled device's power effect")
	press(scene); check(not runtime.states["city:authored_appliance"]["on"],"Exported switch cancels appliance power and cycle")
	var appliance: Dictionary=place(exploration,"authored_appliance"); press(scene); tick(runtime,appliance["profile"]["duration"]+1)
	check(runtime.active.is_empty() and runtime.states["city:authored_appliance"]["cycles"]==1 and not runtime.inventory.is_empty(),"Actual exported appliance completes and awards a session result")
	var host: Dictionary=scene.live_data["objects"].filter(func(item: Dictionary)->bool:return not item.get("interior",{}).get("floors",[]).is_empty())[0]; var host_uid: String=host["uid"]; var top: String=host["interior"]["floors"][0]["uid"]
	var outside: Variant=exploration.entrance(exploration.instances[host_uid]); scene.player.teleport_to(outside); press(scene); await settle()
	check(exploration.interior!=null and exploration.interior_uid==host_uid,"Actual exported building entry opens the owned prop room")
	place(exploration,"shared_switch"); press(scene); var ground_key: String="room:"+host_uid+":ground:shared_appliance"
	check(runtime.states.get(ground_key,{}).get("on",false),"Ground-room switch operates its own local target")
	change_floor(exploration,top); place(exploration,"shared_switch"); runtime._physics_process(1.0/60); var upper_key: String="room:"+host_uid+":"+top+":shared_appliance"
	check(exploration.active_floor()==top and not runtime.states.get(upper_key,{}).get("on",false),"Reused appliance IDs keep independent power on the actual upper floor")
	var upper: Dictionary=place(exploration,"shared_bench"); press(scene); await settle(); point=Plan.global_point(upper,exploration)
	check(not runtime.active.is_empty() and runtime.active["scope"]=="room:"+host_uid+":"+top+":","Upper-floor seating uses its owning room and saved action profile")
	check(is_equal_approx(scene.player.body.global_position.y+.85,4.48) if mode=="3d" else float(upper["node"].get_meta("terrain_height",0))>.9,"Actual upper-floor seat retains sculpted terrain elevation")
	await capture(mode,"upstairs_seat"); press(scene); place(exploration,"shared_appliance"); press(scene); tick(runtime,2)
	check(runtime.states[upper_key]["cycles"]==1 and runtime.active.is_empty(),"Upper-floor appliance finishes its own saved cycle")
	place(exploration,"shared_bench"); press(scene); exploration.leave_interior(); check(runtime.active.is_empty() and runtime.effects.entries.is_empty(),"Leaving during use restores the avatar before the owned room is destroyed")
	scene.player.teleport_to(outside); scene._process(1.0/60)
	var other: Dictionary=scene.live_data["objects"].filter(func(item: Dictionary)->bool:return item["uid"]!=host_uid and not item.get("interior",{}).get("floors",[]).is_empty())[0]
	scene.player.teleport_to(exploration.entrance(exploration.instances[other["uid"]])); press(scene); await settle(); place(exploration,"shared_switch"); runtime._physics_process(1.0/60)
	check(exploration.interior_uid==other["uid"] and not runtime.states.get("room:"+other["uid"]+":ground:shared_appliance",{}).get("on",false),"Separate exported buildings isolate identical local prop IDs")
	exploration.leave_interior(); scene.walking=false; scene._set_mode(); check(runtime.active.is_empty() and runtime.effects.entries.is_empty(),"Exported free-camera mode clears prop poses and effects")
	check(scene.studio_data==before,"Using props, results and room/floor transitions preserve all authored export data")
	scene.free(); await process_frame; print("PROPS EXPORT: %d checks, %d failures"%[checks,failures]); quit(1 if failures else 0)
