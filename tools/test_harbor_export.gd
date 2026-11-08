extends SceneTree

const Plan = preload("res://scripts/builder/harbor_plan.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + message)
	return ok

func frame() -> void:
	for index in 5: await physics_frame
	await RenderingServer.frame_post_draw

func run() -> void:
	var city: Node = load("res://city.tscn").instantiate()
	root.add_child(city)
	await frame()
	city.walking = true
	city._set_mode()
	await frame()
	var harbor: Node = city.exploration.harbor
	harbor.set_physics_process(false)
	var document: Dictionary = city.studio_data.duplicate(true)
	if not check(Plan.enabled(document) and harbor.boats.has("pilot") and harbor.boats.has("shuttle"),
		"Independent project resolves both placed vessels and their berths."): quit(1); return
	check(city.exploration.library.assets.has(Plan.VESSEL) and city.exploration.library.assets.has(Plan.PIER)
		and city.exploration.library.icon(Plan.VESSEL) != null and city.exploration.library.icon(Plan.PIER) != null,
		"The exported vessel and pier resolve their preview artwork.")
	check("Board" in city.exploration.prompt(), "The exported dry spawn provides a boarding prompt.")
	city.exploration.interact()
	if not check(harbor.active() and not city.player.visible, "The portable Interact boards the real vessel."): quit(1); return
	for index in 52: harbor.steer(.05, Vector2.RIGHT)
	check(harbor.boats["pilot"]["point"].x > 6 and harbor.boats["pilot"]["wake"].visible,
		"The exported vessel moves and draws its real wake.")
	for step in 240:
		var point: Vector2 = harbor.boats["pilot"]["point"]
		if point.distance_to(Vector2(11, 1)) < .32: break
		harbor.steer(.05, (Vector2(11, 1) - point).normalized())
	for index in 18: harbor.steer(.05, Vector2.ZERO, true)
	city.exploration.interact()
	check(not harbor.active() and city.player.visible and city.terrain_traversal.safe_position(city.player.global_position),
		"Docking in the export restores the player on dry land.")
	harbor.wait = 0
	for step in 900:
		harbor.service(.05)
		if harbor.crossings == 1: break
	check(harbor.crossings == 1 and harbor.boats["shuttle"]["dock"] == "harbor_north",
		"The exported ferry sails its scheduled route and moors.")
	check(city.studio_data == document and city.economy.data["economy_account"]["cash"] == document["economy_account"]["cash"],
		"Boat travel preserves the exact authored layout and treasury.")
	city.walking = false
	city._set_mode()
	await frame()
	check(harbor.claims.is_empty() and harbor.boats.is_empty() and city.city_instances["harbor_pilot"].visible,
		"Leaving Walk restores authored assets and releases runtime claims.")
	city.free()
	await process_frame
	print("PORTABLE HARBOR: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
