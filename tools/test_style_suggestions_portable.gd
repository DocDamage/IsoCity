extends SceneTree
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func run() -> void:
	var expected: Array=JSON.parse_string(FileAccess.get_file_as_string("res://expected_styles.json"))
	var scene: Node=load("res://city.tscn").instantiate();root.add_child(scene)
	for frame in 8:await physics_frame
	var library: RefCounted=scene.exploration.library
	check(preload("res://scripts/builder/document.gd").valid(scene.studio_data,scene.dimension,library),"Independent mixed-style document remains valid")
	check(scene.studio_data["objects"]==expected,"Exact IDs, transforms, UIDs and overrides survive style browsing/export")
	var expected_ids: Array=JSON.parse_string(FileAccess.get_file_as_string("res://expected_style_ids.json"))
	check(library.styles.evidence.size()==expected_ids.size(),"Only authored and normal room-template measurements are exported")
	for id in expected_ids:
		var profile: Dictionary=library.styles.profile(id)
		check(not profile.is_empty() and not profile["materials"].is_empty() and library.styles.span_valid(profile["span"]),"Source hashes and import parameters verify measured material/size evidence: "+id)
		check(library.styles.evidence.has(id) and library.styles.sources_valid(library.styles.evidence[id]),"All measured source dependencies remain present and match: "+id)
	var cafe: Dictionary=library.styles.profile("3d:HanX_Shop/Shop_Cafe")
	var satellite: Dictionary=library.styles.profile("3d:Supplemental_Satellites/03_cubesat_3u")
	check(cafe["themes"]!=satellite["themes"],"Different reviewed themes remain distinct in the independent catalog")
	check(not library.styles.compare(cafe,satellite,scene.dimension)["suggested"],"Shared mesh materials alone never promise cross-theme compatibility")
	check(not preload("res://scripts/builder/citizen_plan.gd").settings(scene.studio_data)["enabled"] and not preload("res://scripts/builder/service_plan.gd").settings(scene.studio_data)["enabled"] and not preload("res://scripts/builder/economy_plan.gd").settings(scene.studio_data)["enabled"],"Browsing never enables simulations")
	scene.free();await process_frame;await process_frame
	print("STYLE SUGGESTIONS PORTABLE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
