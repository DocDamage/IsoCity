extends SceneTree

const Plan = preload("res://scripts/builder/cycling_plan.gd")
const Drive = preload("res://scripts/builder/driving_plan.gd")
var checks: int
var failures: int
var scene: Node

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: "+message)
	return ok

func frames(count: int) -> void:
	for frame in count: await physics_frame

func visit() -> void:
	var walk: Node = scene.exploration
	var course: Node = walk.cycling
	var driver: Node = walk.driving
	if not check(Plan.enabled(scene.studio_data) and course.plan["edges"].has("1,0>2,0"),
		"The relocated world loads the authored cycle route."): return
	var modes: Dictionary = Plan.Traffic.build(scene.studio_data)
	check(not modes["edges"].has("1,0>2,0"),"The standalone motor graph excludes the reserved connection.")
	var bike: Dictionary = {}
	var npc: Dictionary = {}
	for item in scene.studio_data["objects"]:
		if item.get("cycling",{}).get("npc",false): npc = item
		elif not Plan.profile(item,scene.studio_data).is_empty(): bike = item
	if not check(not bike.is_empty() and not npc.is_empty()
		and ResourceLoader.exists(walk.library.assets[bike["asset"]]["path"])
		and ResourceLoader.exists(walk.library.assets[npc["asset"]]["path"]),"Both supplied cycle models resolve independently."): return
	scene.walking = true
	scene._set_mode()
	scene.player.set_physics_process(false)
	var origin: Vector2 = Drive.center(bike,walk.library,scene.dimension)
	var candidate: Variant = scene.to_global(Drive.world(origin+Vector2(0,1.55),scene.dimension,.14))
	scene.player.teleport_to(scene.player.get_parent().to_local(candidate))
	await frames(8)
	check(walk.interaction_prompt().contains("Mount"),"The ordinary interaction finds the authored bicycle.")
	walk.interact()
	if not check(driver.cycling() and scene.player.visible and scene.player.has_meta("cycling_rider"),"The isolated player mounts with a visible rider pose."): return
	check(course.guide() and course.routes.has(driver.get_instance_id()),"Rack guidance resolves from the packaged documents.")
	for frame in 2200:
		await physics_frame
		if driver.active.is_empty() and course.attempted.get(npc["uid"]) == "completed": break
	check(driver.active.is_empty() and driver.notice == "Parked at the bicycle rack."
		and scene.player.visible and not scene.player.has_meta("cycling_rider"),"Actual standalone time completes the player route and restores walking.")
	check(course.attempted.get(npc["uid"]) == "completed" and not course.runner.operator().has_meta("cycling_rider"),
		"A separate preview rider completes the scooter route and dismounts.")

func run() -> void:
	scene = load("res://city.tscn").instantiate()
	root.add_child(scene)
	await frames(8)
	await visit()
	scene.free()
	await process_frame
	print("PORTABLE CYCLING: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
