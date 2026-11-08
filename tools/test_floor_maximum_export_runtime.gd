extends SceneTree
const Plan=preload("res://scripts/builder/floor_plan.gd")
const Fit=preload("res://scripts/builder/grid_fit.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for frame in 4: await physics_frame
	await process_frame
func climb(exploration: Node,link: Dictionary,descending: bool=false) -> void:
	var player: Node=exploration.player; var mode: String=exploration.dimension; var source: Array=link["end"] if descending else link["start"]; var target: Array=link["start"] if descending else link["end"]
	var height: float=exploration.interior.floor_stack.heights[link["upper"] if descending else link["lower"]]
	if mode=="2d":
		player.teleport_to(Fit.pixels(Vector2(source[0],source[1]))); exploration.interact()
		for frame in 2000:
			await physics_frame
			if exploration.interior.floor_stack.travel.is_empty(): break
	else:
		var direction:=Vector3(target[0]-source[0],0,target[1]-source[1]).normalized()
		player.set_physics_process(false); player.teleport_to(Vector3(source[0],height+.05,source[1])-direction*.8)
		for frame in 180:
			await physics_frame; player.move_character(1.0/60,direction)
			if (player.position-Vector3(target[0],player.position.y,target[1])).dot(direction)>=.35: break
		for frame in 15: await physics_frame; player.move_character(1.0/60,Vector3.ZERO)
		player.set_physics_process(true)
	await settle()
func wait_lift(lift: Node) -> void:
	for frame in 4000:
		await physics_frame
		if lift.phase in ["idle","blocked"]: break
	await process_frame
func trip(exploration: Node,destination: String) -> void:
	var player: Node=exploration.player; var mode: String=exploration.dimension; var lift: Node=exploration.interior.floor_stack.lifts.values()[0]; var current: String=exploration.active_floor(); var height: float=exploration.interior.floor_stack.heights[current]
	if lift.last_stop!=current:
		player.teleport_to(Fit.pixels(Vector2(4,-2.35)) if mode=="2d" else Vector3(4,height+.05,-2.35)); exploration.interact(); await wait_lift(lift)
		check(lift.last_stop==current and lift.phase=="idle","A maximum-floor landing can call its empty elevator: "+mode)
	player.teleport_to(Fit.pixels(Vector2(4,-4)) if mode=="2d" else Vector3(4,height+.05,-4)); exploration.interact()
	var destinations: int=0
	for button in lift.choices.get_children():
		if button.has_meta("floor_uid"): destinations+=1
	check(lift.menu.visible and not player.is_physics_processing() and destinations==8,"The furnished eight-floor cabin exposes every destination and captures control: "+mode)
	if height>=18 and "--capture" in OS.get_cmdline_user_args():
		for frame in 5: await process_frame
		RenderingServer.force_draw(false); RenderingServer.force_draw(false); root.get_texture().get_image().save_png("res://output/floor_maximum_"+mode+"_elevator.png")
	var chosen: bool=false
	for button in lift.choices.get_children():
		if button is Button and button.get_meta("floor_uid","")==destination: button.pressed.emit(); chosen=true; break
	check(chosen,"The requested destination is available: "+destination)
	await wait_lift(lift)
	check(lift.last_stop==destination and exploration.active_floor()==destination and lift.phase=="idle" and player.is_physics_processing() and player.recovery_count==0,"The furnished maximum-floor lift reaches its actual landing safely: "+mode+"/"+destination)
func ascend(exploration: Node) -> void:
	for link in exploration.owned_room["floor_links"]:
		if link["kind"]!="stairs": continue
		await climb(exploration,link)
		check(exploration.active_floor()==link["upper"] and exploration.player.recovery_count==0,"Successive physical/projected flights reach each furnished storey: "+exploration.dimension+"/"+link["upper"])
		check(exploration.room_world().instances.size()==13,"Each visited floor retains its independent door and twelve furnishings: "+exploration.dimension)
func run() -> void:
	var path: String="res://city.tscn"
	for mode in ["2d","3d"]:
		if "--"+mode in OS.get_cmdline_user_args(): path="res://output/floor_maximum_"+mode+".tscn"
	var scene: Node=load(path).instantiate(); root.add_child(scene)
	for frame in 6: await process_frame
	await physics_frame
	var exploration: Node=scene.exploration; var player: Node=scene.player; var mode: String=scene.dimension; var host: Dictionary={}
	for item in scene.live_data["objects"]:
		if item.get("interior",{}).get("floors",[]).size()==7: host=item; break
	check(not host.is_empty() and Plan.valid(host["interior"]) and host["interior"]["floor_links"].size()==8,"A playable maximum-floor export retains seven flights, eight furnished rooms and its elevator")
	var definitions: Array=Plan.definitions(host["interior"]); var basement: String=definitions[0]["uid"]; var top: String=definitions[-1]["uid"]; var authored: Dictionary=scene.studio_data.duplicate(true); var parent: Node=player.get_parent()
	var entry: Dictionary=host["interior"]["floor_entrances"].filter(func(value: Dictionary)->bool:return value["floor"]==basement)[0]
	var outside: Variant=preload("res://scripts/builder/floor_entrances.gd").outside(exploration.instances[host["uid"]],host,entry,mode,exploration.library)
	player.teleport_to(outside); exploration.interact(); await settle()
	check(exploration.interior!=null and exploration.active_floor()==basement and player.is_visible_in_tree(),"A floor-specific entrance opens the furnished basement in the exported game")
	await ascend(exploration)
	check(Plan.room(host["interior"],top)["objects"][0]["open"] and not Plan.room(host["interior"],"ground")["objects"][0]["open"],"The top-floor door edited in Studio retains its independent state")
	await trip(exploration,basement)
	for definition in definitions.slice(1): await trip(exploration,definition["uid"])
	var stairs: Array=host["interior"]["floor_links"].filter(func(link: Dictionary)->bool:return link["kind"]=="stairs"); stairs.reverse()
	for link in stairs:
		await climb(exploration,link,true); check(exploration.active_floor()==link["lower"] and player.recovery_count==0,"Every furnished flight also supports safe descent: "+mode+"/"+link["lower"])
	player.teleport_to(exploration.exit_point(entry)); exploration.interact()
	check(exploration.interior==null and player.get_parent()==parent and player.position.distance_to(outside)<.01,"The exported basement EXIT restores exterior ownership and its actual entrance")
	var roof_entry: Dictionary=host["interior"]["floor_entrances"].filter(func(value: Dictionary)->bool:return value["floor"]==top)[0]
	var roof_outside: Variant=preload("res://scripts/builder/floor_entrances.gd").outside(exploration.instances[host["uid"]],host,roof_entry,mode,exploration.library)
	player.teleport_to(roof_outside); exploration.interact(); await settle()
	check(exploration.interior!=null and exploration.active_floor()==top and exploration.room_world().instances.size()==13,"The separate roof entrance reaches the eighth furnished floor directly")
	check(exploration.prompt().contains("Return outside") and player.recovery_count==0,"The roof landing is supported and exposes its floor-specific exit")
	exploration.interact(); check(exploration.interior==null and player.get_parent()==parent and player.position.distance_to(roof_outside)<.01,"The eighth-floor EXIT returns through its transformed exterior entrance")
	check(scene.studio_data==authored,"Maximum-floor visits and all connections preserve authored export content")
	scene.free(); print("FLOOR MAXIMUM EXPORT: %d checks, %d failures"%[checks,failures]); quit(1 if failures else 0)
