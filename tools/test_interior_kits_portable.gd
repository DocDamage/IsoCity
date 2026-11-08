extends SceneTree
const Plan=preload("res://scripts/builder/prop_plan.gd")
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func settle() -> void:
	for frame in 8:await physics_frame
	await process_frame
func same(a: Variant,b: Variant) -> bool:
	if (a is float or a is int) and (b is float or b is int):return absf(float(a)-float(b))<=1e-8*maxf(1,absf(float(a)))
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for key in a:
			if not b.has(key) or not same(a[key],b[key]):return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for i in a.size():
			if not same(a[i],b[i]):return false
		return true
	return a==b
func run() -> void:
	var scene: Node=load("res://city.tscn").instantiate();root.add_child(scene);await settle();scene.player.set_physics_process(false)
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://expected.json"));check(same(scene.studio_data["objects"],expected["objects"]),"All owned kit objects, identities and source coordinates survive relocation")
	for setting in ["traffic","citizens","services","economy"]:check(not scene.studio_data.get(setting,{}).get("enabled",false),"Simulation remains disabled: "+setting)
	var exploration: Node=scene.exploration
	var known_ids: Array=[]
	for item in expected["objects"]:
		for child in item.get("interior",{}).get("objects",[]):known_ids.append(child["uid"])
	for host in scene.live_data["objects"]:
		var lazy: bool=not host.has("interior");var saved: Dictionary=host.get("interior",{}).duplicate(true)
		scene.player.teleport_to(exploration.entrance(exploration.instances[host["uid"]]));scene.player.set_physics_process(false)
		var event:=InputEventKey.new();event.keycode=KEY_E;event.pressed=true;scene._unhandled_input(event);await settle()
		check(exploration.interior!=null and exploration.interior_uid==host["uid"],"Actual exported input enters the owned/lazy room: "+host["uid"])
		if not exploration.interior:continue
		var context: Dictionary=Plan.context(exploration);var room: Dictionary=context["data"]
		check(room.get("starter_kit",{}).get("id")==("classroom" if lazy else saved["starter_kit"]["id"]),"Correct saved/default kit opens independently")
		check(Plan.standing_clear(exploration,scene.player.global_position),"Independent room entry has walking clearance")
		var count: int=0
		for item in room["objects"]:
			check(context["instances"].has(item["uid"]),"Saved furnishing has an actual independent instance")
			var profile: Dictionary=Plan.profile(item)
			if profile.is_empty():continue
			var candidate: Dictionary=context.duplicate(false);candidate["item"]=item;candidate["node"]=context["instances"][item["uid"]];candidate["profile"]=profile
			var point: Variant=Plan.ground_point(candidate,exploration,"approach");scene.player.teleport_to(scene.player.get_parent().to_local(point));scene.player.set_physics_process(false)
			check(exploration.props.interact(candidate),"Independent kit furnishing starts its supported interaction")
			check(exploration.props.finish(),"Independent interaction exits and releases control");count+=1
		check(count==0 if room["starter_kit"]["id"]=="empty" else count>0,"Furnished kits have usable stations; an intentionally empty room has none")
		if not lazy:check(same(host["interior"],saved),"Visiting and using an existing kit preserves all authored room data")
		else:
			check(host["interior"]["objects"].all(func(item: Dictionary):return not item["uid"] in known_ids),"Lazy creation gives its furnishings fresh identities")
		exploration.leave_interior();await settle();check(exploration.interior==null and exploration.props.active.is_empty(),"Room exit frees the private world and active use")
	scene.free();await process_frame;print("INTERIOR KITS PORTABLE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
