extends SceneTree
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func run() -> void:
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://expected_health.json"))
	var objects: Array=JSON.parse_string(FileAccess.get_file_as_string("res://expected_health_objects.json"))
	var scene: Node=load("res://city.tscn").instantiate();root.add_child(scene)
	for frame in 8:await physics_frame
	var library: RefCounted=scene.exploration.library
	check(preload("res://scripts/builder/document.gd").valid(scene.studio_data,scene.dimension,library) and scene.studio_data["objects"]==objects,"Independent export preserves exact authored objects, IDs, UIDs and transforms")
	for id in expected["previews"]:
		var preview: Dictionary=expected["previews"][id]
		check(FileAccess.file_exists(preview["path"]) and FileAccess.get_sha256(preview["path"])==preview["sha256"],"Required default/repaired thumbnail bytes survive independently: "+id)
		check(preload("res://scripts/builder/model_preview.gd").meaningful(library.icon(id)),"Independent browser uses real supplied/prepared artwork: "+id)
	var audit: RefCounted=load("res://verify_asset_health.gd").new();audit.begin(library)
	while audit.active:audit.step(16,100000);await process_frame
	var report: Dictionary=audit.report()
	check(report["status"]=="complete" and report["assets_scanned"]==library.assets.size(),"Independent health audit covers every retained asset")
	check(report["issues"].filter(func(issue: Dictionary):return issue["severity"]=="defect").is_empty(),"Fresh independent sources, thumbnails and frame metadata have no definite health defects")
	check(report["issues"].filter(func(issue: Dictionary):return issue["code"]=="optional_source_unavailable").all(func(issue: Dictionary):return issue["severity"]=="review"),"Unavailable optional intake originals remain review notes while prepared art opens")
	for item in objects:check(scene.exploration.instances.has(item["uid"]),"Actual retained prepared model opens in the independent world: "+item["asset"])
	check(scene.find_children("PrivateModelThumbnail","",true,false).is_empty(),"Private repair scenes never become playable content")
	check(not preload("res://scripts/builder/citizen_plan.gd").settings(scene.studio_data)["enabled"] and not preload("res://scripts/builder/service_plan.gd").settings(scene.studio_data)["enabled"] and not preload("res://scripts/builder/economy_plan.gd").settings(scene.studio_data)["enabled"],"Library health never enables simulations")
	scene.free();await process_frame;await process_frame
	print("ASSET HEALTH PORTABLE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
