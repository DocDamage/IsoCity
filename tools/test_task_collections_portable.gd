extends SceneTree
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func settle() -> void:
	for frame in 12:await process_frame
func run() -> void:
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://expected.json"));var scene: Node=load("res://city.tscn").instantiate();root.add_child(scene);await settle()
	check(JSON.parse_string(JSON.stringify(scene.live_data))==expected,"Independent task selections preserve all authored data")
	var library: RefCounted=preload("res://scripts/builder/asset_library.gd").new()
	check(library.tasks.tasks.size()==4,"Independent subset retains validated task definitions")
	for item in expected["objects"]:
		check(scene.city_instances.has(item["uid"]) and is_instance_valid(scene.city_instances[item["uid"]]),"Selected furnishing actually instantiates: "+item["asset"])
		check(library.tasks.members(item["uid"].trim_prefix("task_"),"hanx")["ids"].has(item["asset"]),"Exported collection index recognizes available selected art")
		check(library.icon(item["asset"])!=null and preload("res://scripts/builder/model_preview.gd").meaningful(library.icon(item["asset"])),"Selected furnishing retains actual preview art")
	check(not library.tasks.members("classroom","hanx")["missing"].is_empty(),"Unselected packs are explained rather than required by browsing definitions")
	for key in ["citizens","traffic","businesses","services","economy","scenario","zoning","transit","weather"]:
		var config: Variant=scene.live_data.get(key,{})
		check(not config is Dictionary or not config.get("enabled",false),"Task browsing enables no simulation: "+key)
	if "--capture" in OS.get_cmdline_user_args():
		scene.set_process(false)
		if scene.dimension=="2d":scene.camera.position=Vector2(120,0);scene.camera.zoom=Vector2(3,3)
		else:scene.camera.projection=Camera3D.PROJECTION_ORTHOGONAL;scene.camera.size=15;scene.camera.global_position=Vector3(4,7,10);scene.camera.look_at(Vector3(4,0,0))
		await settle();await RenderingServer.frame_post_draw;check(root.get_texture().get_image().save_png("res://rendered_tasks.png")==OK,"Independent selected furnishings render")
	scene.free();await process_frame;print("TASK COLLECTIONS PORTABLE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
