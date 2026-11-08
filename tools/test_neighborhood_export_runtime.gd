extends SceneTree
const Plan=preload("res://scripts/builder/neighborhood_plan.gd")
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
		if "--"+mode in OS.get_cmdline_user_args(): path="res://output/neighborhood_"+mode+".tscn"
	var scene: Node=load(path).instantiate(); root.add_child(scene)
	for frame in 6: await process_frame
	await settle()
	var mode: String=scene.dimension; var exploration: Node=scene.exploration; var player: Node=scene.player; var generated: Array=scene.live_data["objects"].filter(func(item: Dictionary)->bool:return item.has("neighborhood"))
	check(generated.size()==11 and Plan.valid_settings(scene.live_data["neighborhood_generator"]),"The exported scene retains generated buildings and repeatable settings")
	var uid: String=generated[0]["neighborhood"]["uid"]; var roads: Array=scene.live_data["roads"].filter(func(road: Dictionary)->bool:return road.get("neighborhood_uid","")==uid)
	check(roads.size()==108 and roads.all(func(road: Dictionary)->bool:return road["width"]==6 and road["sidewalks"]),"Generated road records retain layout, sidewalks, style and independent editing data")
	var network: Dictionary=Plan.Traffic.build(scene.live_data)
	check(roads.all(func(road: Dictionary)->bool:return network["sections"].has(preload("res://scripts/builder/roads.gd").key(Vector2i(road["cell"][0],road["cell"][1])))),"Every generated road is usable by the exported traffic network")
	var authored: Dictionary=scene.studio_data.duplicate(true); var parent: Node=player.get_parent()
	if mode=="3d":
		var area: Rect2=Plan.bounds(scene.live_data["neighborhood_generator"],mode); var point: Vector2=area.end-Vector2.ONE*10
		var query:=PhysicsRayQueryParameters3D.create(Vector3(point.x,10,point.y),Vector3(point.x,-10,point.y),2); var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty() and absf(hit.get("position",Vector3.INF).y)<.01,"Exported neighborhoods retain physical support beyond the original foundation")
		player.teleport_to(Vector3(point.x,.05,point.y))
		for frame in 40: await physics_frame
		check(absf(player.position.y)<.1 and player.recovery_count==0,"The exported character stands on an actual generated parcel without falling or recovery")
	else: check(scene.get_node("Ground").get_used_cells().size()>7000,"Pixel exports include the generated district's themed editable paving")
	for item in generated:
		var outside: Variant=exploration.entrance(exploration.instances[item["uid"]]); player.teleport_to(outside); exploration.interact(); await settle()
		check(exploration.interior!=null and exploration.interior_uid==item["uid"] and player.is_visible_in_tree(),"Each generated building offers its own usable exported entrance: "+item["asset"])
		if exploration.interior==null: continue
		player.teleport_to(exploration.exit_position); exploration.interact()
		check(exploration.interior==null and player.get_parent()==parent and player.position.distance_to(outside)<.01 and player.recovery_count==0,"Generated interiors return through the same entrance with restored controls")
	check(generated.all(func(item: Dictionary)->bool:return item.has("interior")),"First visits create persistent independently owned rooms for generated buildings")
	var restored: Dictionary=scene.studio_data.duplicate(true)
	for item in restored["objects"]:
		if item.has("neighborhood"): item.erase("interior")
	check(restored==authored,"Visits preserve authored city records apart from their newly owned rooms")
	scene.free(); print("NEIGHBORHOOD EXPORT: %d checks, %d failures"%[checks,failures]); quit(1 if failures else 0)
