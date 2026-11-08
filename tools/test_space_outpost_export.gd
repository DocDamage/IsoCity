extends SceneTree

const Plan = preload("res://scripts/builder/space_outpost_plan.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + message)
	return ok

func settle() -> void:
	for frame in 5: await physics_frame
	await RenderingServer.frame_post_draw

func run() -> void:
	var city: Node = load("res://city.tscn").instantiate()
	root.add_child(city)
	await settle()
	city.walking = true
	city._set_mode()
	await settle()
	var runtime: Node = city.exploration.outpost
	runtime.set_physics_process(false)
	var document: Dictionary = city.studio_data.duplicate(true)
	var library: RefCounted = city.exploration.library
	if not check(Plan.settings(document)["enabled"] and runtime.network["docks"].has("outpost_dock"),
		"Independent export resolves the authored outpost and its dock."):
		quit(1)
		return
	check(Plan.required(document).all(func(id: String) -> bool: return library.assets.has(id)),
		"All scheduled and orbital assets exist in the independent library.")
	check(Plan.required(document).filter(func(id: String) -> bool: return id.begins_with("3d:")).all(
		func(id: String) -> bool: return library.icon(id) != null and library.icon(id) != library.MISSING_ICON),
		"Exported ship and satellite previews contain the supplied art.")
	check(city.terrain_traversal.safe_position(city.player.global_position), "The independent Walk spawn is clear and dry.")
	for step in 80:
		runtime._physics_process(.05)
		if not runtime.job.is_empty(): break
	if not check(runtime.job.get("phase") == "arrival" and is_instance_valid(runtime.orbital),
		"The ship and the optional orbital scenery appear separately."):
		quit(1)
		return
	var phases: Dictionary = {}
	for step in 380:
		var phase: String = runtime.job.get("phase", "")
		phases[phase] = true
		runtime._physics_process(.05)
		if runtime.completed == 1: break
	check(phases.has_all(["arrival", "docked", "unloading", "departure"]) and runtime.completed == 1,
		"The independent project lands a real ship, unloads it, and completes departure.")
	check(runtime.staged.has("outpost_dock") and runtime.leases.current("space_outpost:outpost_dock").is_empty(),
		"Cargo reaches the staging point and dock ownership is released.")
	check(city.studio_data == document, "Runtime supply visits leave the authored layout and budget intact.")
	city.walking = false
	city._set_mode()
	await settle()
	check(runtime.job.is_empty() and runtime.staged.is_empty() and not is_instance_valid(runtime.orbital),
		"Leaving Walk cleans all local supply visuals.")
	city.free()
	await settle()
	print("PORTABLE SPACE OUTPOST: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
