extends SceneTree

const Plan = preload("res://scripts/builder/village_plan.gd")
var checks: int
var failures: int

func _initialize() -> void: call_deferred("run")

func check(ok: bool, description: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: "+description)
	return ok

func run() -> void:
	var scene: Node = load("res://city.tscn").instantiate()
	root.add_child(scene)
	for frame in 8: await physics_frame
	var exploration: Node = scene.exploration
	var runtime: Node = exploration.village
	if scene.studio_data.get("title","") == "Village truck test":
		verify_truck(exploration,runtime)
	else:
		await verify_chain(scene,exploration,runtime)
	scene.free()
	await process_frame
	print("PORTABLE VILLAGE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func verify_truck(exploration: Node, runtime: Node) -> void:
	var driver: Node = exploration.driving
	var cargo: String = "3d:HanX_Shop/Cardboard_Boxes"
	check(runtime.book.sites.size() == 2 and driver.delivery.offers.get("granary",{}).has("village_route"),"Relocated village compiles the real truck route.")
	check(exploration.library.assets.has(cargo) and ResourceLoader.exists(exploration.library.assets[cargo]["path"]),"Packaged village crate art loads independently.")
	check(driver.delivery.vehicles.has("van") and driver.delivery.routes.network["sections"].size() >= 10,"Truck and road dependencies are present.")

func verify_chain(scene: Node, exploration: Node, runtime: Node) -> void:
	var book: RefCounted = runtime.book
	if not check(Plan.enabled(scene.studio_data) and book.sites.size() == 6,"Relocated city loads six authored facilities."): return
	check(book.sites.values().all(func(site: Dictionary)->bool:
		return ResourceLoader.exists(exploration.library.assets[site["item"]["asset"]]["path"])),
		"All native village assets resolve independently.")
	check(book.account["stock"].is_empty(),"Standalone starts with fresh stock.")
	scene.walking = true
	scene._set_mode()
	scene.player.set_physics_process(false)
	for frame in 4800:
		await physics_frame
		if not book.order("market").is_empty(): break
	if not check(book.order("market").get("goods") == "bread","Fixed runtime ticks complete the standalone grain-to-bread chain."): return
	var point: Vector2 = book.sites["market"]["points"][0]
	scene.player.teleport_to(scene.player.get_parent().to_local(runtime.position(point)))
	await physics_frame
	check(exploration.interaction_prompt().contains("Market supplies"),"Standalone E locates the village market.")
	exploration.interact()
	if not check(runtime.has_menu(),"Standalone market opens from the normal interaction."): return
	var credits: int = book.account["cash"]
	var order: Dictionary = book.order("market").duplicate()
	runtime.view.buttons["sell"].pressed.emit()
	var replay: Dictionary = book.sell("market",order["id"])
	check(book.account["cash"] == credits+14 and replay.get("credits") == 14,"Standalone market sells once and returns the same receipt on retry.")
