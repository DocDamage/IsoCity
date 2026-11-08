extends SceneTree
const Props=preload("res://scripts/builder/prop_plan.gd")
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func settle() -> void:
	for frame in 12:await process_frame
func packed_scene_values(data: Dictionary) -> Dictionary:
	var result: Dictionary=data.duplicate(true)
	# PackedScene writes the shortest float text needed to preserve Godot's
	# Vector positions. Compare their exact float32 values; every other saved
	# field and the portable JSON source still require exact equality.
	for item in result["objects"]:
		for axis in 3:item["position"][axis]=PackedFloat32Array([item["position"][axis]])[0]
	return result
func run() -> void:
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://expected.json"));var scene: Node=load("res://city.tscn").instantiate();scene.photo_storage_enabled=false;root.add_child(scene);await settle();scene.player.set_physics_process(false);var mode: String=scene.dimension
	check(packed_scene_values(JSON.parse_string(JSON.stringify(scene.studio_data)))==packed_scene_values(expected),"Relocated scene preserves exact float32 poses and all other source fields")
	var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://city-source.json"));check(source["documents"][mode]==expected,"Portable source independently reopens the exact companion layout")
	check(ProjectSettings.get_setting("rendering/renderer/rendering_method")==("gl_compatibility" if mode=="2d" else "forward_plus"),"Normal import retains the effective desktop renderer")
	check(ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile")==("gl_compatibility" if mode=="2d" else "mobile"),"Normal import retains the effective mobile renderer")
	for field in ["citizens","traffic","businesses","services","economy","scenario","zoning","transit","weather","ambience"]:check(not scene.studio_data.get(field,{}).get("enabled",false),"Companions enable no new simulation: "+field)
	for item in expected["objects"]:
		check(scene.city_instances.has(item["uid"]),"Every selected companion really instantiates independently")
		check(preload("res://scripts/builder/model_preview.gd").meaningful(scene.exploration.library.icon(item["asset"])),"Every companion retains recognizable preview dependencies")
		check(scene.exploration.library.assets[item["asset"]]["data"].get("source_export_allowed",true),"Every exported source retains its allowed export flag")
	var chair: Dictionary=expected["objects"].filter(func(item: Dictionary):return item["asset"]=="3d:HanX_School/Student_Chair")[0];var exploration: Node=scene.exploration;var candidate: Dictionary={"item":chair,"node":scene.city_instances[chair["uid"]],"profile":Props.profile(chair)};var at: Variant=Props.ground_point(candidate,exploration,"approach")
	scene.player.teleport_to(scene.player.get_parent().to_local(at));check(Props.standing_clear(exploration,at) and exploration.props.interact(candidate) and not exploration.props.active.is_empty(),"Relocated chair can be used beside its saved desk");check(exploration.props.finish() and exploration.props.active.is_empty(),"Relocated paired chair has a usable exit")
	var canopy: Dictionary=expected["objects"].filter(func(item: Dictionary):return item["asset"]=="3d:HanX_GasStation/Fuel_Canopy")[0];var node: Node=scene.city_instances[canopy["uid"]];var anchors=preload("res://scripts/builder/entrance_anchors.gd")
	for step in 13:
		var local:=Vector3(-1.5+step*.25,.2 if mode=="3d" else 0,1.25);var point: Variant=anchors.source_position(node,canopy,mode,exploration.library,local);point=node.get_parent().to_global(point)
		check(Props.standing_clear(exploration,point),"Actual player shape clears the continuous under-canopy path")
		if step==0:scene.player.teleport_to(scene.player.get_parent().to_local(point))
		else:
			var motion: Variant=point-scene.player.global_position;scene.player.move_and_collide(motion);check(scene.player.global_position.distance_to(point)<.02,"Actual player motion traverses the supplied roof opening")
	if "--capture" in OS.get_cmdline_user_args():
		scene.set_process(false)
		for fixture in [["classroom","3d:HanX_School/Student_Desk",3.0,8.0],["pump","3d:HanX_GasStation/Fuel_Pump",18.0,1.6],["shelf","3d:HanX_Shop/Shelf_Wall",5.0,6.0]]:
			var item: Dictionary=expected["objects"].filter(func(value: Dictionary):return value["asset"]==fixture[1])[0];var raw: Array=item["position"]
			if mode=="2d":scene.camera.position=Vector2(raw[0],raw[1])-Vector2(0,18 if fixture[0]!="pump" else 40);scene.camera.zoom=Vector2.ONE*float(fixture[3])
			else:
				var center:=Vector3(raw[0],1.8 if fixture[0]=="pump" else .5,raw[2]);scene.camera.projection=Camera3D.PROJECTION_ORTHOGONAL;scene.camera.size=fixture[2];scene.camera.global_position=center+Vector3(12,10,14);scene.camera.look_at(center)
			await settle();await RenderingServer.frame_post_draw;check(root.get_texture().get_image().save_png("res://rendered_"+fixture[0]+".png")==OK,"Independent complete companion set renders: "+fixture[0])
	scene.free();await process_frame;await process_frame;print("COMPANION PORTABLE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
