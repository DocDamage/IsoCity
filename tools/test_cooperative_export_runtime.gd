extends SceneTree
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var path: String="res://city.tscn"
	for mode in ["2d","3d"]:
		if "--"+mode in OS.get_cmdline_user_args(): path="res://output/cooperative_"+mode+".tscn"
	var scene: Node=load(path).instantiate(); root.add_child(scene)
	for frame in 6: await physics_frame
	var data: Dictionary=scene.studio_data
	check(data.get("protected_areas",[]).size()==1,"Shared source retains the saved editing assignment")
	check(data["protected_areas"][0].has("owner") and data["protected_areas"][0].has("rect"),"Saved assignment retains its owner and bounds")
	check(scene.city_instances.size()==data["objects"].size(),"Export contains accepted city construction")
	check(data["objects"].any(func(item: Dictionary):return item.get("interior",{}).get("objects",[]).any(func(piece: Dictionary):return str(piece["uid"]).begins_with("room_piece_"))),"Collaborative owned-room edits survive export")
	check(scene.find_children("CooperativeSession","",true,false).is_empty(),"Playable export opens without a collaborative network listener")
	check(scene.find_children("CollaboratorCursors","",true,false).is_empty(),"Playable city excludes editor cursor markers")
	check(not JSON.stringify(data).contains("resume_token"),"Saved city does not contain private connection credentials")
	scene.free(); await process_frame; print("Cooperative export: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
