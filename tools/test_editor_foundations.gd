extends SceneTree

const Document = preload("res://scripts/builder/document.gd")
const Delta = preload("res://scripts/builder/document_delta.gd")
var checks: int = 0
var failures: int = 0

func _init() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func run() -> void:
	test_history()
	var studio: Control = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	await process_frame
	await process_frame
	var library: RefCounted = studio.library
	for id in library.assets:
		var behavior: Dictionary = library.assets[id].get("behavior", {})
		check(behavior.get("layer") in preload("res://scripts/builder/layers.gd").NAMES and behavior.get("building") is bool and behavior.get("door") is bool and behavior.get("vehicle") is bool and behavior.get("ground") is bool and behavior.get("collision") in ["mesh", "box", "none"], "Explicit behavior metadata: " + id)
	library.assets["custom:neutral_name"] = {"id": "custom:neutral_name", "mode": "3d", "category": "Uncategorized", "behavior": {"layer": "Buildings", "building": true, "door": true, "vehicle": true, "collision": "mesh"}}
	check(preload("res://scripts/builder/exploration.gd").is_building("custom:neutral_name", library), "Building behavior is independent of filename")
	check(preload("res://scripts/builder/exploration.gd").is_door("custom:neutral_name", library), "Door behavior is independent of filename")
	check(preload("res://scripts/builder/layers.gd").classify("custom:neutral_name", library) == "Buildings", "Layer classification uses explicit metadata")
	library.assets.erase("custom:neutral_name")
	check(not library.find("all", "All assets", "shop coffee", [], false).is_empty(), "Search words work in any order")
	check(library.find("2d", "All assets", "cofee shop", [], false).any(func(a: Dictionary) -> bool: return a["id"] == "2d:Coffee_Shop"), "Search tolerates a missing letter")
	check(library.find("2d", "All assets", "cofefe shop", [], false).any(func(a: Dictionary) -> bool: return a["id"] == "2d:Coffee_Shop"), "Search tolerates transposed letters")
	check(library.find("all", "All assets", "automobile", [], false).any(func(a: Dictionary) -> bool: return "car" in a["name"].to_lower()), "Vehicle synonym finds cars")
	check(library.find("all", "All assets", "coffee shop", [], false)[0]["id"] == "2d:Coffee_Shop", "Exact name ranks first")
	check(library.find("3d", "All assets", "coffee", [], true).is_empty(), "Favorites filter still applies")
	check(library.find("2d", "All assets", "coffee", ["2d:Coffee_Shop"], true).size() == 1, "Favorites work with ranked search")
	check(library.find("all", "All assets", "coffee qzxqzxqz", [], false).is_empty(), "Every search word must match")
	check(library.find("all", "All assets", "  coffee---SHOP  ", [], false)[0]["id"] == "2d:Coffee_Shop", "Search normalizes punctuation and case")
	for dimension in ["2d", "3d"]:
		var world: Node = studio.worlds[dimension]
		var data: Dictionary = studio.documents[dimension].data
		world.apply(data)
		check(world.last_apply_updates == 0 and world.last_apply_tile_updates == 0, "Unchanged apply does no rendering work: " + dimension)
		var item: Dictionary = data["objects"][0]
		var other: Node = world.instances[data["objects"][1]["uid"]]
		var entrance_markers: Dictionary = world.exploration.marker_nodes.duplicate()
		item["position"][0] += 1
		world.apply(data)
		check(world.last_apply_updates == 1, "Only the edited instance is updated: " + dimension)
		check(other == world.instances[data["objects"][1]["uid"]], "Unedited instance is preserved: " + dimension)
		check(world.last_apply_tile_updates == 0, "Moving an object leaves ground unchanged: " + dimension)
		for marker_uid in entrance_markers:
			check(world.exploration.marker_nodes.get(marker_uid) == entrance_markers[marker_uid], "Entrance marker instance is retained: " + dimension + "/" + marker_uid)
		var original_asset: String = item["asset"]
		item["asset"] = "2d:Coffee_Shop" if dimension == "3d" else "3d:HanX_City/Cafe_Small"
		world.apply(data)
		check(world.last_apply_updates == 1, "Replacing an asset updates exactly one instance: " + dimension)
		item["asset"] = original_asset
		world.apply(data)
		data["objects"].erase(item)
		world.apply(data)
		check(world.last_apply_updates == 1 and not world.instances.has(item["uid"]), "Deleting an object removes only its instance: " + dimension)
		if dimension == "2d":
			var tile: Dictionary = data["tiles"][0]
			tile["direction"] = "SW"
			world.apply(data)
			check(world.last_apply_tile_updates == 1, "Changing one ground cell updates one cell")
			data["tiles"].erase(tile)
			world.apply(data)
			check(world.last_apply_tile_updates == 1, "Removing one ground cell erases one cell")
		var prototype: Dictionary = data["objects"][0]
		for i in 250:
			var copy: Dictionary = prototype.duplicate(true)
			copy["uid"] = "stress_" + str(i)
			copy["position"][0] += i * 4
			data["objects"].append(copy)
		world.apply(data)
		var started: int = Time.get_ticks_usec()
		data["objects"][-1]["position"][0] += 1
		world.apply(data)
		check(world.last_apply_updates == 1 and world.last_apply_tile_updates == 0, "A small edit in a larger scene still updates only one instance: " + dimension)
		print("Incremental apply in ", dimension, " with ", data["objects"].size(), " objects: ", Time.get_ticks_usec() - started, " us")
	studio.free()
	print("EDITOR FOUNDATIONS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func test_history() -> void:
	var doc := Document.new()
	for i in 1500: doc.data["objects"].append({"uid": str(i), "position": [i, 0, 0], "colors": []})
	var original: Dictionary = doc.data.duplicate(true)
	doc.checkpoint()
	doc.data["objects"][700]["position"][0] = 999
	doc.finish_checkpoint()
	check(doc.undo_history[0]["collections"]["objects"]["changes"].size() == 1, "History retains only one edited object in a large document")
	check(JSON.stringify(doc.undo_history[0]).length() < JSON.stringify(original).length() / 20, "A single edit uses a fraction of a full snapshot")
	check(doc.undo() and doc.data == original, "Single-object undo restores exact content")
	check(doc.redo() and doc.data["objects"][700]["position"][0] == 999, "Single-object redo restores edit")
	var rng := RandomNumberGenerator.new()
	rng.seed = 8821
	var states: Array[Dictionary] = [doc.data.duplicate(true)]
	for step in 120:
		doc.checkpoint()
		match step % 6:
			0: doc.data["objects"].remove_at(rng.randi_range(0, doc.data["objects"].size() - 1))
			1: doc.data["objects"].insert(rng.randi_range(0, doc.data["objects"].size()), {"uid": "new" + str(step), "position": [1, 2, 3]})
			2: doc.data["objects"][rng.randi_range(0, doc.data["objects"].size() - 1)]["colors"] = [{"value": step}]
			3: doc.data["objects"].reverse()
			4: doc.data["layers"] = {"Ground": {"visible": step % 2 == 0}}
			5: doc.data["tiles"].append({"cell": [step, -step], "asset": "test"})
		states.append(doc.data.duplicate(true))
	for i in range(states.size() - 2, -1, -1): check(doc.undo() and doc.data == states[i], "Mixed history undo " + str(i))
	for i in range(1, states.size()): check(doc.redo() and doc.data == states[i], "Mixed history redo " + str(i))
	doc.checkpoint()
	doc.data["title"] = "branched"
	check(doc.redo_history.is_empty(), "A new edit clears redo")
	doc.undo_history.clear()
	doc.redo_history.clear()
	doc.checkpoint()
	doc.data["title"] = "after reset"
	check(doc.undo() and doc.data["title"] == "branched", "Clearing history cannot revive a stale pending baseline")
	var before: Dictionary = {"tiles": [], "objects": [], "roads": [], "a": [1, 2]}
	var after: Dictionary = {"tiles": [], "objects": [], "a": [3], "new": true}
	var delta: Dictionary = Delta.between(before, after)
	var value: Dictionary = before.duplicate(true)
	Delta.apply(value, delta, true)
	check(value == after, "Delta restores added and removed document fields")
	Delta.apply(value, delta, false)
	check(value == before, "Delta reverses added and removed document fields")
