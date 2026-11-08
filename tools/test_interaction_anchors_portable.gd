extends SceneTree
const Plan=preload("res://scripts/builder/prop_plan.gd")
const Claims=preload("res://scripts/builder/activity_reservations.gd")
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func same(a: Variant,b: Variant) -> bool:
	# JSON stores integral numbers as floats. Keep identities/keys exact while
	# accepting only numeric representation differences at source precision.
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
	var scene: Node=load("res://city.tscn").instantiate();root.add_child(scene)
	for frame in 8:await physics_frame
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://expected.json"))
	check(same(scene.studio_data["objects"],expected["objects"]),"Every authored object and optional anchor survives relocation")
	for setting in ["traffic","citizens","services","economy"]:check(not scene.studio_data.get(setting,{}).get("enabled",false),"Simulation stays disabled: "+setting)
	var exploration: Node=scene.exploration;var runtime: Node=exploration.props
	for item in scene.live_data["objects"]:
		var profile: Dictionary=Plan.profile(item)
		if profile.is_empty():continue
		var context: Dictionary=Plan.context(exploration).duplicate(false);context["item"]=item;context["node"]=context["instances"][item["uid"]];context["profile"]=profile
		var point: Variant=Plan.ground_point(context,exploration,"approach");scene.player.teleport_to(scene.player.get_parent().to_local(point));scene.player.set_physics_process(false)
		check(runtime.interact(context),"Actual relocated prop starts: "+item["asset"])
		if runtime.active.is_empty():continue
		check(runtime.reservation_token>0,"Relocated runtime acquires a station")
		var key: String=runtime.reservation_key;var pool: RefCounted=runtime.reservations
		check(runtime.finish() and pool.current(key).is_empty(),"Relocated exit releases the station")
		check(Plan.standing_clear(exploration,scene.player.global_position),"Relocated exit uses real walking clearance")
	check(same(scene.studio_data["objects"],expected["objects"]),"Transient use changes no authored export data")
	scene.free();await process_frame;print("INTERACTION ANCHORS PORTABLE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
