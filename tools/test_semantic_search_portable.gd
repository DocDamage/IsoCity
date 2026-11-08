extends SceneTree
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func run() -> void:
	var expected: Array=JSON.parse_string(FileAccess.get_file_as_string("res://expected_semantic_objects.json"))
	var expected_ids: Array=JSON.parse_string(FileAccess.get_file_as_string("res://expected_semantic_ids.json"))
	var scene: Node=load("res://city.tscn").instantiate();root.add_child(scene)
	for frame in 8:await physics_frame
	var library: RefCounted=scene.exploration.library
	check(preload("res://scripts/builder/document.gd").valid(scene.studio_data,scene.dimension,library),"Independent authored document remains valid")
	check(scene.studio_data["objects"]==expected,"Search choices never alter exported IDs, transforms, UIDs or overrides")
	check(library.search_index.semantics.size()==expected_ids.size(),"Independent semantic overlay includes only actual export dependencies")
	for id in expected_ids:
		check(library.assets.has(id) and library.search_index.semantics.has(id) and not library.search_index.semantics[id]["source_note"].is_empty(),"Reviewed search metadata and provenance survive independently: "+id)
	check(library.search_index.use_matches("3d:HanX_School/Student_Chair","classroom") and library.search_index.use_matches("3d:HanX_GasStation/Workbench","workshop"),"Distinct intended-use groups survive export")
	for fixture in [["classroom seating","3d:HanX_School/Student_Chair"],["chair school","3d:HanX_School/Student_Chair"],["shcool chairs","3d:HanX_School/Student_Chair"],["repair workshop","3d:HanX_GasStation/Workbench"]]:
		check(library.find("all","All assets",fixture[0],[],false).any(func(asset: Dictionary):return asset["id"]==fixture[1]),"Independent semantic/typo/reverse-order search works: "+fixture[0])
	var exact: Array=library.find("all","All assets","3d:HanX_School/Student_Chair",[],false)
	check(not exact.is_empty() and exact[0]["id"]=="3d:HanX_School/Student_Chair","Independent exact ID ranks first")
	check(not preload("res://scripts/builder/citizen_plan.gd").settings(scene.studio_data)["enabled"] and not preload("res://scripts/builder/service_plan.gd").settings(scene.studio_data)["enabled"] and not preload("res://scripts/builder/economy_plan.gd").settings(scene.studio_data)["enabled"],"Semantic search never enables simulations")
	scene.free();await process_frame;await process_frame
	print("SEMANTIC SEARCH PORTABLE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
