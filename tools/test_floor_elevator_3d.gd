extends SceneTree
var checks: int=0
var failures: int=0
var world: Node3D
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func room() -> Dictionary:
	return {"mode":"3d","title":"Lift room","interior_room":true,"night":false,"objects":[],"tiles":[],"exit":[-4,0.1,2.5]}
func move(direction: Vector3,frames: int) -> void:
	for frame in frames:
		await physics_frame; world.player.move_character(1.0/60,direction)
	await process_frame
func wait_lift(lift: Node) -> Dictionary:
	var highest_step: float=0; var previous: float=world.player.global_position.y
	for frame in 4000:
		await physics_frame
		highest_step=maxf(highest_step,absf(world.player.global_position.y-previous)); previous=world.player.global_position.y
		if lift.phase in ["idle","blocked"]: break
	await process_frame
	return {"step":highest_step}
func run() -> void:
	var library=preload("res://scripts/builder/asset_library.gd").new(); var data: Dictionary=room()
	data["floors"]=[{"uid":"middle","name":"Middle","height":3,"room":room()},{"uid":"top","name":"Top","height":6,"room":room()}]
	data["floor_links"]=[{"uid":"lift","kind":"elevator","lower":"ground","upper":"top","start":[0,0],"end":[0,0],"width":1.2}]
	var before: Dictionary=data.duplicate(true)
	world=load("res://scripts/builder/world_3d.gd").new(); world.library=library; root.add_child(world)
	var city: Dictionary={"mode":"3d","title":"Lift city","night":false,"objects":[{"uid":"building","asset":"2d:House_Blue","position":[0,0,0],"direction":"SE","scale":1,"interior":data}],"tiles":[]}
	world.apply(city); world.walk(true); world.player.set_physics_process(false); world.player.teleport_to(world.exploration.entrance(world.instances["building"])); world.exploration.interact()
	for frame in 3: await physics_frame
	var stack: Node=world.exploration.interior.floor_stack; var lift: Node=stack.lifts["lift"]
	check(lift.stops.size()==3 and lift.phase=="idle" and lift.last_stop=="ground","One elevator serves all authored floors within its endpoint range")
	check(lift.view.stations["ground"]["gate"].collision_layer==0 and lift.view.stations["middle"]["gate"].collision_layer==2,"Only the cabin's current landing is physically open")
	world.player.teleport_to(Vector3(0,0.05,2.5)); await move(Vector3.FORWARD,40); await move(Vector3.ZERO,15)
	check(lift.view.fully_inside() and world.player.position.z<0.3,"The character walks through the open landing into the physical cabin")
	world.exploration.interact(); check(lift.menu.visible,"E inside the cabin opens the floor chooser")
	lift.cancel_menu(); check(not lift.menu.visible and not world.player.is_physics_processing(),"Cancelling the chooser restores the prior physics-processing state")
	world.exploration.interact(); lift.choose("middle")
	check(lift.rider and lift.phase=="closing","Choosing a floor closes gates before travel")
	var ride: Dictionary=await wait_lift(lift)
	if lift.phase!="idle": print("LIFT STATE: ",lift.phase," h=",lift.height," actor=",world.player.position," notice=",lift.notice)
	check(lift.phase=="idle" and lift.last_stop=="middle" and absf(world.player.position.y-3)<0.05,"The moving cabin carries its passenger to the intermediate floor")
	check(ride["step"]<0.03 and world.player.recovery_count==0,"Cabin movement is continuous and never invokes recovery")
	check(lift.view.stations["ground"]["gate"].collision_layer==2 and lift.view.stations["middle"]["gate"].collision_layer==0,"Arrival opens the destination and keeps the empty lower shaft gated")
	await move(Vector3.BACK,35); await move(Vector3.ZERO,15)
	check(world.player.position.z>1.5 and absf(world.player.position.y-3)<0.05,"The character walks out across the destination threshold")
	lift.request("top"); await wait_lift(lift)
	check(lift.last_stop=="top" and absf(world.player.position.y-3)<0.05,"The cabin can move empty without carrying a waiting character")
	world.exploration.interact(); await wait_lift(lift)
	check(lift.last_stop=="middle" and lift.phase=="idle","A landing call returns the cabin to the waiting floor")
	await move(Vector3.FORWARD,35); await move(Vector3.ZERO,15)
	world.exploration.interact(); lift.choose("ground"); await wait_lift(lift)
	check(lift.last_stop=="ground" and absf(world.player.position.y)<0.05 and world.player.recovery_count==0,"The same cabin supports a safe return trip")
	var shapes=preload("res://scripts/builder/floor_stairs_3d.gd")
	var obstruction: Node3D=shapes.box(stack,"ShaftObstruction",Vector3(1.2,0.2,1.2),Vector3(0,2.5,0),Color.RED)
	for frame in 3: await physics_frame
	world.exploration.interact(); lift.choose("middle"); await wait_lift(lift)
	check(lift.phase=="blocked" and lift.height<0.4 and lift.rider,"A shaft obstruction halts the cabin before it reaches the passenger")
	world.exploration.interact(); await wait_lift(lift)
	check(lift.phase=="idle" and lift.last_stop=="ground" and absf(world.player.position.y)<0.05 and world.player.recovery_count==0,"E returns a blocked cabin safely to its previous landing")
	obstruction.free()
	var doorway: Node3D=shapes.box(stack,"DoorwayObstruction",Vector3(0.8,1.8,0.12),Vector3(0,0.94,0.715),Color.RED)
	for frame in 3: await physics_frame
	world.exploration.interact(); lift.choose("middle")
	check(lift.phase=="waiting" and lift.view.stations["ground"]["gate"].collision_layer==0,"An occupied doorway prevents gate closure and travel")
	world.exploration.interact(); check(lift.phase=="idle" and not lift.rider,"A waiting passenger can cancel without losing cabin access")
	doorway.free()
	var exit_obstruction: Node3D=shapes.box(stack,"LandingObstruction",Vector3(0.7,1.8,0.6),Vector3(0,3.94,1.55),Color.RED)
	for frame in 3: await physics_frame
	world.exploration.interact(); lift.choose("middle"); await wait_lift(lift)
	check(lift.phase=="blocked" and absf(lift.height-3)<0.01 and lift.view.stations["middle"]["gate"].collision_layer==2,"An obstructed exit keeps the destination gate closed")
	world.exploration.interact(); await wait_lift(lift)
	check(lift.phase=="idle" and lift.last_stop=="ground" and world.player.recovery_count==0,"A passenger can return from a blocked destination")
	exit_obstruction.free()
	check(data==before,"Calling and riding do not change authored rooms or elevator records")
	world.player.set_physics_process(true); world.exploration.interact(); lift.choose("top")
	for frame in 60: await physics_frame
	check(lift.rider and lift.phase=="moving" and not world.player.is_physics_processing(),"Ride controls remain captured while the cabin is between floors")
	world.exploration.leave_interior(); check(world.player.is_physics_processing() and world.exploration.interior==null,"Leaving mid-ride releases physics control without retaining the cabin")
	var many: Dictionary=room(); many["floors"]=[]
	for index in 7: many["floors"].append({"uid":"level_"+str(index+1),"name":"Level "+str(index+1),"height":(index+1)*3,"room":room()})
	many["floors"][0]["name"]="A".repeat(80)
	many["floor_links"]=[{"uid":"all","kind":"elevator","lower":"ground","upper":"level_7","start":[0,0],"end":[0,0],"width":1.2}]
	city["objects"][0]["interior"]=many; world.apply(city); world.player.set_physics_process(false); world.player.teleport_to(world.exploration.entrance(world.instances["building"])); world.exploration.interact()
	for frame in 3: await physics_frame
	world.player.teleport_to(Vector3(0,0.05,2.5)); await move(Vector3.FORWARD,40); await move(Vector3.ZERO,15)
	lift=world.exploration.interior.floor_stack.lifts["all"]; var original_size: Vector2i=root.size; root.size=Vector2i(960,640); world.exploration.interact()
	for frame in 5: await process_frame
	check(lift.stops.size()==8 and lift.menu.visible and lift.menu.position.y+lift.menu.size.y<=640,"The maximum-floor chooser remains bounded in the minimum viewport")
	check(lift.menu.size.x<=320,"Maximum-length floor names do not expand the chooser beyond its bounded width")
	var scroll: ScrollContainer=lift.choices.get_parent()
	check(scroll.get_v_scroll_bar().max_value>scroll.size.y and scroll.follow_focus,"All eight stops and cancellation remain reachable through keyboard-following scrolling")
	lift.cancel_menu(); root.size=original_size; world.exploration.leave_interior()
	var wide_range: Dictionary=room(); wide_range["floors"]=[{"uid":"basement","name":"Basement","height":-24,"room":room()},{"uid":"top","name":"Top","height":32,"room":room()}]
	wide_range["floor_links"]=[{"uid":"narrow","kind":"elevator","lower":"basement","upper":"top","start":[0,0],"end":[0,0],"width":0.8}]
	city["objects"][0]["interior"]=wide_range; world.apply(city); world.player.set_physics_process(false); world.player.teleport_to(world.exploration.entrance(world.instances["building"])); world.exploration.interact()
	for frame in 3: await physics_frame
	world.player.teleport_to(Vector3(0,-23.95,2.5)); await move(Vector3.FORWARD,40); await move(Vector3.ZERO,15)
	lift=world.exploration.interior.floor_stack.lifts["narrow"]
	check(lift.view.fully_inside(),"The minimum-width cabin admits the character without embedding it")
	world.exploration.interact(); lift.choose("top"); var longest: Dictionary=await wait_lift(lift)
	check(lift.phase=="idle" and lift.last_stop=="top" and absf(world.player.position.y-32)<0.05,"A cabin traverses the full supported basement-to-top height range")
	check(longest["step"]<0.03 and world.player.recovery_count==0,"The full 56-metre ride remains continuous without recovery")
	world.exploration.leave_interior(); world.free(); print("FLOOR ELEVATOR 3D: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
