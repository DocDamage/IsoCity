extends SceneTree
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
	var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/catalog/asset_metadata.json"))
	check(metadata["assets"].size() > 0 and metadata["assets"].size() < 100, "Portable metadata is a real selected subset")
	check(preload("res://scripts/builder/document.gd").valid(scene.studio_data, scene.dimension, library), "Relocated family placements validate")
	check(scene.studio_data["objects"].size() == 3, "Selected bonsai, model and character survive relocation")
	var found: bool = false
	for item in scene.studio_data["objects"]:
		check(library.assets.has(item["asset"]), "Every saved member ID exists unchanged")
		var data: Dictionary = library.assets[item["asset"]]["data"]
		if data.get("source_pack") == "Bonsai trees":
			found = true
			check(data.has("family_id") and data.has("palette_id") and data.has("lighting_id"), "Relocated concrete sprite retains independent appearance dimensions")
			check(library.families.members[data["family_id"]] == [item["asset"]], "Subset indexing never substitutes an unexported representative")
	check(found, "Fixture exercises a reviewed appearance family")
	scene.free(); await process_frame; await process_frame
	print("Relocated asset families: %d checks, %d failures" % [checks, failures]); quit(1 if failures else 0)
