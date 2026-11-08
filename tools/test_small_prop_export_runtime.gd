extends SceneTree
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;print("FAIL: "+message)
func run() -> void:
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://expected_props.json"));var scene: Node=load("res://city.tscn").instantiate();root.add_child(scene)
	for i in 12:await physics_frame
	var source: Dictionary=expected["source"];var library: RefCounted=scene.exploration.library
	# The binary scene keeps integer variants while JSON reads numbers as floats.
	var runtime_source: Variant = JSON.parse_string(JSON.stringify(scene.studio_data, "", true, true))
	check(runtime_source == source, "Independent project retains every exact authored JSON value")
	check(preload("res://scripts/builder/document.gd").valid(scene.studio_data,scene.dimension,library),"Independent document validates against its own included catalog")
	check(scene.exploration.instances.size()==source["objects"].size(),"Every unselected and authored-hidden object remains included")
	for item in source["objects"]:
		var instance: Node=scene.exploration.instances[item["uid"]]
		var shown: bool=item.get("visible",true) and preload("res://scripts/builder/layers.gd").shown(source,preload("res://scripts/builder/layers.gd").layer(item,library))
		check(instance.visible==shown,"Export retains authored visibility for "+item["name"])
		if not shown:
			var bodies: Array=instance.find_children("*","CollisionObject2D",true,false)+instance.find_children("*","CollisionObject3D",true,false)
			if instance is CollisionObject2D or instance is CollisionObject3D:bodies.append(instance)
			check(bodies.all(func(body: Node):return body.collision_layer==0),"Authored hidden source retains inactive collision visibility: "+item["name"])
		check(library.assets.has(item["asset"]),"Source catalog includes "+item["asset"])
		var position: Array=item["position"]
		check(instance.position.is_equal_approx(Vector2(position[0],position[1]-position[2]*8) if scene.dimension=="2d" else Vector3(position[0],position[1],position[2])),"Actual runtime position retains original coordinates: "+item["name"])
		check(instance.scale.is_equal_approx(Vector2.ONE*item["scale"] if scene.dimension=="2d" else Vector3.ONE*item["scale"]),"Actual runtime source scale remains unchanged: "+item["name"])
	for id in expected["previews"]:
		var preview: Dictionary=expected["previews"][id];check(FileAccess.file_exists(preview["path"]) and FileAccess.get_sha256(preview["path"])==preview["sha256"],"Preview dependency survives relocation: "+id)
	for name in ["SmallPropView","TemporaryDetailView","SmallPropActions"]:check(scene.find_children(name,"",true,false).is_empty(),"Temporary editor controls are excluded: "+name)
	check(not FileAccess.file_exists("res://scripts/builder/small_prop_tools.gd"),"Temporary editing helper is not a runtime dependency")
	check(not preload("res://scripts/builder/citizen_plan.gd").settings(source)["enabled"] and not preload("res://scripts/builder/economy_plan.gd").settings(source)["enabled"],"Unrelated simulations retain disabled defaults")
	if "--capture" in OS.get_cmdline_user_args():
		scene.walking=false;scene.player.visible=false
		if scene.dimension=="2d":scene.camera.position=Vector2(45,0);scene.camera.zoom=Vector2(5,5)
		else:scene.target=Vector3(.5,.5,0);scene.zoom=5
		for i in 12:await process_frame
		RenderingServer.force_draw(false);RenderingServer.force_draw(false);root.get_texture().get_image().save_png("res://verified_props.png")
	var saved: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://city-source.json"));check(saved["documents"][scene.dimension]==source,"Independent source JSON preserves the complete authored document")
	scene.free();await process_frame;await process_frame;print("SMALL PROP EXPORT RUNTIME: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
