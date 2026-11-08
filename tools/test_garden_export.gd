extends SceneTree

const Plan = preload("res://scripts/builder/garden_plan.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + message)

func frames(count: int) -> void:
	for frame in count: await process_frame

func run() -> void:
	var scene: Node = load("res://city.tscn").instantiate()
	root.add_child(scene)
	await frames(8)
	var exploration: Node = scene.exploration
	var garden: Node = exploration.garden
	var uid: String = ""
	for id in garden.sites:
		if Plan.growing_site(garden.sites[id]["profile"]["role"]): uid = id; break
	check(not uid.is_empty() and Plan.settings(scene.studio_data) and garden.crops.is_empty(),
		"The relocated runtime opens an authored bed and fresh crop state.")
	if uid.is_empty(): quit(1); return
	var site: Dictionary = garden.sites[uid]
	var descriptor: Dictionary = exploration.library.assets[site["item"]["asset"]]
	check(ResourceLoader.exists(descriptor["path"]), "The placed bed scene resolves independently.")
	scene.walking = true
	scene._set_mode()
	scene.player.set_physics_process(false)
	var node: Node = scene.city_instances[uid]
	var target: Vector2 = Plan.Utility.side_point(site["rect"],"south",.6)
	scene.player.teleport_to(garden.world_point(node,target,site["item"]))
	await physics_frame
	check(exploration.interaction_prompt().contains("Plant lettuce"), "The standalone player reaches the active bed.")
	exploration.interact()
	exploration.interact()
	await frames(302)
	check(garden.crops.get(uid,{}).get("growth",-1) == 5, "Actual scene time advances the planted and watered crop.")
	exploration.interact()
	await frames(184)
	check(exploration.interaction_prompt().contains("Harvest lettuce"), "The isolated crop reaches a usable ripe stage.")
	exploration.interact()
	check(garden.account["stock"].get("produce/lettuce",0) == 3 and garden.account["cash"] == 46
		and not scene.studio_data.has("garden_account"), "The independent scene yields three units and six local credits.")
	scene.free()
	await process_frame
	print("PORTABLE GARDEN: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
