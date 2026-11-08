extends SceneTree

const Props = preload("res://scripts/builder/prop_plan.gd")
var scene: Node
var exploration: Node
var camp: Node
var checks: int
var failures: int

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: "+message)
	return ok

func frames(count: int) -> void:
	for frame in count: await process_frame

func use(point: Vector2, action: String) -> bool:
	var target: Variant = camp.world_point(point,Props.context(exploration))
	scene.player.teleport_to(scene.player.get_parent().to_local(target))
	await physics_frame
	var prompt: String = exploration.interaction_prompt()
	if not check(action in prompt,"Expected '%s', saw '%s'" % [action,prompt]): return false
	exploration.interact()
	return true

func visit() -> void:
	var sites: Dictionary = camp.sites("city:")
	if not check(sites.size() == 2 and camp.jobs.is_empty(),"The isolated project has two authored sites and no transient visit."): return
	var fire: Dictionary
	for site in sites.values():
		if site["kind"] == "fire": fire = site
	if not check(not fire.is_empty() and fire["reason"].is_empty(),"The isolated campfire route compiles."): return
	for item in [fire["item"],fire["park"],fire["activity"]]:
		var descriptor: Dictionary = exploration.library.assets.get(item["asset"],{})
		check(ResourceLoader.exists(descriptor.get("path","")),"The linked campsite object resolves independently: "+item["asset"])
	scene.walking = true
	scene._set_mode()
	scene.player.set_physics_process(false)
	scene.businesses.hour = 17
	camp.last_time = -1
	await frames(12)
	if not await use(fire["entry"],"Reserve"): return
	if not await use(fire["points"][0]["shelter"],"Check in"): return
	if not await use(fire["points"][0]["activity"],"Gather at the campfire"): return
	var flame: Dictionary = camp.view.flames.get(fire["activity"]["uid"],{})
	check(not flame.is_empty() and not flame["bed"].visible and is_instance_valid(flame["sound"]),"Standalone fire and sound start.")
	await frames(275)
	if not await use(fire["points"][0]["shelter"],"Rest at the shelter"): return
	check(camp.resting() and is_instance_valid(camp.view.poses["player"]["actor"].get_ref()),"Standalone sleeping pose is active.")
	await frames(275)
	if not await use(fire["entry"],"Check out"): return
	check(camp.jobs.is_empty() and camp.history.size() == 1 and camp.history.back()["state"] == "completed"
		and not is_instance_valid(camp.view.flames[fire["activity"]["uid"]]["sound"]),
		"Standalone checkout clears the job, pose and fire without duplicate receipts.")

func run() -> void:
	scene = load("res://city.tscn").instantiate()
	root.add_child(scene)
	await frames(10)
	exploration = scene.exploration
	camp = exploration.camping
	await visit()
	scene.free()
	await process_frame
	print("PORTABLE CAMPING: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
