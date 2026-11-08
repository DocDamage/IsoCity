extends SceneTree
const Plan=preload("res://scripts/builder/blueprint_plan.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var path: String="res://city.tscn"
	for mode in ["2d","3d"]:
		if "--"+mode in OS.get_cmdline_user_args(): path="res://output/blueprint_"+mode+".tscn"
	var scene: Node=load(path).instantiate(); root.add_child(scene)
	for frame in 6: await physics_frame
	var source: Dictionary=scene.studio_data; var mode: String=source["mode"]; var library: RefCounted=scene.exploration.library
	check(source.get("blueprints",[]).size()==3,"City source retains native, mixed and road proposals")
	check(Plan.valid(source["blueprints"],mode,library),"Portable catalog includes unbuilt building dependencies")
	var ids: Array=[]
	for entry in source["blueprints"]:
		ids.append(entry["uid"])
		if entry["kind"]=="building":
			check(not Plan.rectangles(entry,mode,library).is_empty(),"Relocated asset can compute its footprint")
	check(scene.find_children("BlueprintProposals","",true,false).is_empty(),"Gameplay excludes editor blueprint visuals")
	check(scene.city_instances.size()==source["objects"].size(),"Gameplay contains only constructed objects")
	var result: Dictionary=Plan.construct(source,ids,library)
	check(result["ok"] and result["data"]["blueprints"].is_empty() and result["data"]["objects"].size()==source["objects"].size()+2,"Exported source retains editable construction recipes")
	check(source["blueprints"].size()==3,"Constructing a candidate does not mutate the exported source")
	scene.free(); await process_frame; print("Blueprint export: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
