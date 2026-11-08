extends SceneTree
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;print("FAIL: "+message)
func run() -> void:
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://expected_scale.json"))
	var scene: Node=load("res://city.tscn").instantiate();root.add_child(scene)
	for frame in 8:await physics_frame
	var library: RefCounted=scene.exploration.library
	check(preload("res://scripts/builder/document.gd").valid(scene.studio_data,scene.dimension,library),"Independent project validates with actual scale/orientation")
	check(scene.studio_data["objects"].size()==1 and scene.studio_data["objects"][0]["asset"]==expected["asset"],"Only the authored model is exported while comparison is open")
	var item: Dictionary=scene.studio_data["objects"][0]
	check(item["uid"]==expected["uid"] and is_equal_approx(item["scale"],expected["scale"]) and item["direction"]==expected["direction"] and item["tilt"].size()==2 and is_equal_approx(item["tilt"][0],expected["tilt"][0]) and is_equal_approx(item["tilt"][1],expected["tilt"][1]),"Comparison-only scale never replaces saved scale or transforms")
	check(not library.assets.has("2d:Hatchback_Yellow") and not library.assets.has("3d:Supplemental_SWAT/Vehicle_Unmarked_Sedan"),"Reference-only car assets are absent from the portable catalog")
	for name in ["PrivatePlacementComparison","PersonReference","CarReference","GridReference","CalibratedFootprint"]:check(scene.find_children(name,"",true,false).is_empty(),"Private reference node never enters the exported city: "+name)
	var instance: Node=scene.exploration.instances[item["uid"]]
	if scene.dimension=="2d":
		var sprite: Sprite2D=instance.get_node("Sprite2D");var rect: Rect2=instance.transform*sprite.transform*sprite.get_rect()
		check(rect.position.is_equal_approx(Vector2(expected["min"][0],expected["min"][1])) and rect.size.is_equal_approx(Vector2(expected["size"][0],expected["size"][1])),"Independent projected size matches the original placed instance")
	else:
		var box: AABB=instance.transform*preload("res://scripts/model_bounds.gd").get_bounds(instance)
		check(box.position.is_equal_approx(Vector3(expected["min"][0],expected["min"][1],expected["min"][2])) and box.size.is_equal_approx(Vector3(expected["size"][0],expected["size"][1],expected["size"][2])),"Independent prepared dimensions match the original placed instance")
	check(not preload("res://scripts/builder/citizen_plan.gd").settings(scene.studio_data)["enabled"] and not preload("res://scripts/builder/service_plan.gd").settings(scene.studio_data)["enabled"] and not preload("res://scripts/builder/economy_plan.gd").settings(scene.studio_data)["enabled"],"Scale comparison never enables simulations")
	scene.free();await process_frame;await process_frame
	print("ASSET SCALE PORTABLE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
