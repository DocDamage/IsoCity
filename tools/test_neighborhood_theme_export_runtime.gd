extends SceneTree
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func settle() -> void:
	for frame in 4:await physics_frame
	for frame in 3:await process_frame
func room_signature(room: Dictionary) -> Dictionary:
	var objects: Array=[]
	for item in room["objects"]:
		var record: Dictionary={}
		for field in ["asset","position","direction","scale","angle","tilt","colors","prop"]:
			if item.has(field):record[field]=item[field]
		objects.append(JSON.stringify(record))
	objects.sort();return {"objects":objects,"tiles":room["tiles"],"exit":room.get("exit",[]),"spawn":room.get("spawn",[]),"starter_kit":room.get("starter_kit",{})}
func focus_node(scene: Node,node: Node,ignore_support: bool=false) -> void:
	if scene.dimension=="2d":
		var bounds:=Rect2();var found: bool=false
		for sprite in node.find_children("*","Sprite2D",true,false):
			if not sprite.texture or not sprite.is_visible_in_tree():continue
			var box: Rect2=sprite.global_transform*sprite.get_rect();bounds=bounds.merge(box) if found else box;found=true
		if found:scene.camera.position=bounds.get_center();scene.camera.zoom=Vector2.ONE*minf(1200.0/maxf(1,bounds.size.x+120),720.0/maxf(1,bounds.size.y+160))
	else:
		var bounds:=AABB();var found: bool=false;var support: Node=node.get_node_or_null("Foundation") if ignore_support else null
		for mesh in node.find_children("*","MeshInstance3D",true,false):
			if not mesh.mesh or not mesh.is_visible_in_tree():continue
			if is_instance_valid(support) and (support==mesh or support.is_ancestor_of(mesh)):continue
			var box: AABB=mesh.global_transform*mesh.mesh.get_aabb();bounds=bounds.merge(box) if found else box;found=true
		if found:
			var radius: float=maxf(1,bounds.size.length()*.5);var at: Vector3=bounds.get_center();scene.camera.projection=Camera3D.PROJECTION_ORTHOGONAL;scene.camera.keep_aspect=Camera3D.KEEP_HEIGHT;scene.camera.position=at+Vector3(1,.8,1).normalized()*radius*3;scene.camera.look_at(at);scene.camera.size=radius*2.4;scene.camera.near=.01;scene.camera.far=radius*8+10
func capture(name: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args():return
	await settle();await RenderingServer.frame_post_draw;check(root.get_texture().get_image().save_png("res://"+name+".png")==OK,"Independent district artwork retained: "+name)
func run() -> void:
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://theme_expectation.json"));var scene: Node=load("res://city.tscn").instantiate();root.add_child(scene);await settle();scene.player.set_physics_process(false);scene.set_process(false);var plan=load("res://scripts/builder/neighborhood_plan.gd");var mode: String=scene.dimension;var exploration: Node=scene.exploration;var buildings: Array=scene.live_data["objects"].filter(func(item: Dictionary):return item.get("neighborhood_palette_selection",{}).get("role")=="building")
	check(JSON.parse_string(JSON.stringify(scene.studio_data))==expected["world"],"Independent runnable scene retains every exact authored source value")
	check(JSON.parse_string(JSON.stringify(plan.Palettes.definitions()))==expected["palettes"],"Full palette definitions and revisions survive registry pruning")
	check(buildings.size()==16 and scene.city_instances.size()==scene.live_data["objects"].size(),"Four themed districts instantiate every selected building and scenery object")
	check(not plan.Zone.Citizen.settings(scene.studio_data)["enabled"] and not plan.Zone.Traffic.settings(scene.studio_data)["enabled"] and not plan.Zone.settings(scene.studio_data)["enabled"],"Portable source retains disabled simulation defaults")
	for id in expected["assets"]:
		var asset: Dictionary=expected["assets"][id];check(exploration.library.assets.has(id) and exploration.library.assets[id]["path"]==asset["path"] and ResourceLoader.exists(asset["path"]),"Selected host asset has its independent prepared scene and definition")
		check(FileAccess.file_exists(asset["preview"]) and FileAccess.get_sha256(asset["preview"])==asset["preview_sha256"] and exploration.library.icon(id)!=null,"Selected preview/sprite artwork retains the exact host dependency bytes")
	var source_hash: String=FileAccess.get_sha256("res://city-source.json")
	for district in expected["districts"]:
		var subjects: Array=buildings.filter(func(item: Dictionary):return item["neighborhood"]["uid"]==district["uid"]);check(subjects.size()==4,"Every curated theme retains its four exact family/member choices: "+district["theme"])
		check(scene.live_data["objects"].any(func(item: Dictionary):return item.get("neighborhood_palette_selection",{}).get("theme")==district["theme"] and item.get("neighborhood_palette_selection",{}).get("role")=="prop"),"Actual supplied street props remain instantiated in the independent theme")
		for item in subjects:
			var outside: Variant=exploration.entrance(scene.city_instances[item["uid"]]);scene.player.teleport_to(outside);await settle();check(load("res://scripts/builder/prop_plan.gd").standing_clear(exploration,scene.player.global_position),"Player body clears the packaged entrance with full district scenery present")
			if item==subjects[0] and "--capture" in OS.get_cmdline_user_args():root.size=Vector2i(1480,900);scene.set_process(false);focus_node(scene,scene.city_instances[item["uid"]]);await capture("building_"+mode+"_"+district["theme"])
			scene.walking=true;scene._set_mode();scene.player.set_physics_process(false);exploration.interact();await settle();check(exploration.interior!=null and exploration.interior_uid==item["uid"],"Selected design enters its independently packaged owned room")
			if exploration.interior:check(JSON.parse_string(JSON.stringify(room_signature(exploration.interior.data_state)))==expected["rooms"][item["asset"]],"Owned room retains host starter artwork, poses, colors, actions and exit instead of falling back to an empty shell")
			if exploration.interior and item==subjects[0] and "--capture" in OS.get_cmdline_user_args():scene.set_process(false);focus_node(scene,exploration.interior,true);await capture("owned_room_"+mode+"_"+district["theme"])
			if exploration.interior:exploration.leave_interior();await settle()
			check(exploration.interior==null and scene.player.position.distance_to(outside)<.01 and scene.player.recovery_count==0,"Owned-room return preserves its entrance without recovery")
		if "--capture" in OS.get_cmdline_user_args():
			root.size=Vector2i(1480,900);scene.walking=false;scene._set_mode();scene.set_process(false);var area:=Rect2(district["bounds"][0],district["bounds"][1],district["bounds"][2],district["bounds"][3]);var point: Array=plan.Traffic.world(area.get_center(),mode)
			if mode=="2d":scene.camera.position=Vector2(point[0],point[1]);scene.camera.zoom=Vector2.ONE*minf(1320.0/((area.size.x+area.size.y)*8),760.0/((area.size.x+area.size.y)*4+220))
			else:scene.camera.projection=Camera3D.PROJECTION_ORTHOGONAL;scene.camera.keep_aspect=Camera3D.KEEP_HEIGHT;var at:=Vector3(point[0],5,point[2]);scene.camera.position=at+Vector3(1,.8,1).normalized()*180;scene.camera.look_at(at);scene.camera.size=90;scene.camera.near=.01;scene.camera.far=500
			await capture("district_"+mode+"_"+district["theme"])
	check(FileAccess.get_sha256("res://city-source.json")==source_hash,"Visits never write to the exported source JSON")
	scene.free();await process_frame;print("NEIGHBORHOOD THEME EXPORT: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
