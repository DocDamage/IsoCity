extends SceneTree

const Economy = preload("res://scripts/builder/economy_plan.gd")
const CRATE = "2d:crate"
const SHIP = "3d:Supplemental_Spaceships_II/hammerhead_cruiser"
var checks: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + message)

func run() -> void:
	var city: Node = load("res://city.tscn").instantiate()
	root.add_child(city)
	for frame in 8: await RenderingServer.frame_post_draw
	var mode: String = city.dimension
	var document: Dictionary = city.studio_data
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://city-source.json"))
	var saved: Dictionary = source["documents"][mode]
	check(Economy.valid_account(document.get("economy_account")) and Economy.normalized_account(saved["economy_account"]) == Economy.normalized_account(document["economy_account"]),
		"Standalone playable scene restores the exact authored account and ledger.")
	var expected: String = CRATE if mode == "2d" else SHIP
	check(document["objects"].size() == (1 if mode == "2d" else 2) and document["objects"].all(func(item: Dictionary) -> bool: return item["asset"] == expected and city.city_instances.has(item["uid"])),
		"Independent project loads the expected authored asset instances.")
	var asset: Dictionary = city.exploration.library.assets[expected]
	check(ResourceLoader.exists(asset["path"], "PackedScene") and city.exploration.library.icon(expected) != null,
		"Placed asset scene and artwork resolve inside the package.")
	city.economy.paused = true
	check(city.economy.panel.visible and city.economy.data["economy_account"]["cash"] == document["economy_account"]["cash"],
		"Standalone treasury controls and balance are available.")
	if mode == "2d":
		check(not city.exploration.library.assets.has("3d:HanX_Shop/Bottle_Crate") and document["economy_account"]["refund_total"] > 0,
			"Replacement sprite and refund stand on their own.")
	else:
		var budget = preload("res://scripts/builder/rendering_budget.gd")
		var profile: Dictionary = budget.profile(asset)
		check(ResourceLoader.exists(profile["low"]["path"]) and ResourceLoader.exists(profile["full"]["path"]),
			"Both supplied model editions are available in the isolated export.")
	city.free()
	await process_frame
	print("PORTABLE CONSTRUCTION COSTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
