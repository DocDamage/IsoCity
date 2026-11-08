extends SceneTree
const Business = preload("res://scripts/builder/business_plan.gd")
const Citizen = preload("res://scripts/builder/citizen_plan.gd")
var checks: int = 0
var failures: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; print("FAIL: " + message)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var scene: Node = load("res://city.tscn").instantiate(); root.add_child(scene)
	for frame in 8: await physics_frame
	var library: RefCounted = scene.exploration.library
	check(preload("res://scripts/builder/document.gd").valid(scene.studio_data, scene.dimension, library), "Relocated optional revision validates")
	check(scene.studio_data["objects"].size() == 14, "Twelve reviewed buildings, one legacy shop and one explicit opt-out survive export")
	check(scene.businesses.service.businesses.size() == 12, "Only the twelve enabled reviewed buildings offer exported activities")
	for item in scene.studio_data["objects"]:
		if item.get("name", "") in ["Legacy shop", "Disabled shop"]:
			check(Business.profile(item)["kind"] == "none" and Citizen.role(item).is_empty(), "Legacy/disabled choice survives a fresh portable import")
		else:
			check(Business.profile(item)["kind"] in ["cafe", "shop", "service"] and Citizen.role(item) == "shop", "Export resolves reviewed building defaults")
			if Business.profile(item)["kind"] == "service":
				scene.businesses.set_physics_process(false); scene.businesses.hour = 12.5
				scene.player.set_physics_process(false); scene.player.teleport_to(scene.exploration.entrance(scene.exploration.instances[item["uid"]]))
				var previous: int = scene.businesses.service.inventory.get("player", {}).get("Service receipt", 0)
				check(scene.businesses.request_player(item["uid"], "counter")["ok"], "Relocated player reaches the reviewed counter: " + item["asset"])
				scene.businesses.step(6, false)
				check(scene.businesses.service.inventory.get("player", {}).get("Service receipt", 0) == previous + 1, "Relocated counter completes exactly once")
	var cafe: Dictionary = scene.studio_data["objects"].filter(func(item: Dictionary) -> bool: return item["asset"] == "3d:HanX_Shop/Shop_Cafe")[0]
	scene.businesses.set_physics_process(false); scene.businesses.hour = 12.5
	scene.player.set_physics_process(false); scene.player.teleport_to(scene.exploration.entrance(scene.exploration.instances[cafe["uid"]]))
	check(scene.businesses.request_player(cafe["uid"], "coffee")["ok"], "Relocated player can use the new cafe")
	scene.businesses.step(6, false)
	check(scene.businesses.service.inventory.get("player", {}).get("Coffee", 0) == 1, "Relocated cafe awards its real activity result")
	scene.free(); await process_frame; await process_frame
	print("Relocated functional defaults: %d checks, %d failures" % [checks, failures]); quit(1 if failures else 0)
