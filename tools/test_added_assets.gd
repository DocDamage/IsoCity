extends SceneTree

const Library = preload("res://scripts/builder/asset_library.gd")
const Factory = preload("res://scripts/builder/asset_instance.gd")
const Document = preload("res://scripts/builder/document.gd")
const Parts = preload("res://scripts/builder/part_colors.gd")
var checks: int = 0
var failures: int = 0

func _init() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ", message)

func read_catalog(name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://resources/catalog/" + name + ".json"))

func check_catalog(library: RefCounted, imported: Dictionary) -> void:
	var expected_added := {}
	var expected_catalog := {}
	for id in read_catalog("catalog_registry")["items"]:
		expected_catalog["2d:" + id] = true
	for pack in DirAccess.get_directories_at("res://scenes/items_3d"):
		for file in DirAccess.get_files_at("res://scenes/items_3d/" + pack):
			if file.ends_with(".tscn"):
				expected_catalog["3d:" + pack + "/" + file.get_basename()] = true
	for source in [imported, read_catalog("supplemental_registry"), read_catalog("swat_registry"), read_catalog("reviewed_registry")]:
		for id in source.get("items", {}):
			expected_added["2d:" + id] = true
			expected_catalog["2d:" + id] = true
		for id in source.get("models", {}):
			var model: Dictionary = source["models"][id]
			if not model.get("hidden", false) and not model.get("unavailable", false):
				expected_added[id] = true
			expected_catalog[id] = true
	var added := {}
	for asset in library.find("added", "All assets", "", [], false):
		if not asset["id"].contains(":Custom/"): added[asset["id"]] = true
	var installed := {}
	for id in library.assets:
		if not id.contains(":Custom/"): installed[id] = true
	check(added == expected_added, "Added packs filter includes the exact prepared IDs")
	check(installed == expected_catalog, "Original and added identities coexist in the installed catalog")
	print("CATALOG INVENTORY: %d built-in assets, %d in Added packs" % [installed.size(), added.size()])

func run() -> void:
	var library := Library.new()
	var registry: Dictionary = read_catalog("imported_registry")
	check(registry["items"].size() == registry["stats"]["assets"], "Every prepared asset has a unique stable identity")
	check_catalog(library, registry)
	var represented: Dictionary = {}
	var directional: int = 0
	var animated: int = 0
	for id in registry["items"]:
		var item: Dictionary = registry["items"][id]
		var asset: String = "2d:" + id
		check(library.assets.has(asset) and ResourceLoader.exists(item["scene_path"]) and ResourceLoader.exists(item["preview_path"]), "Added asset has a scene and thumbnail: " + id)
		if item["directions"].size() > 1: directional += 1
		var has_animation: bool = false
		for info in item["directions"].values():
			if info.get("frames", 1) > 1: has_animation = true
		if has_animation: animated += 1
		if represented.has(item["source_pack"]): continue
		represented[item["source_pack"]] = true
		for world_mode in ["2d", "3d"]:
			var node: Node = Factory.make(library, asset, world_mode)
			root.add_child(node)
			var directions: Array = library.directions(asset)
			var record: Dictionary = {"uid": "sample", "asset": asset, "direction": directions[0], "position": [0, 0, 0], "scale": 1.0}
			Factory.pose(node, record)
			var doc: Dictionary = {"mode": world_mode, "title": "Added pack", "objects": [record], "tiles": [], "night": false}
			check(Document.valid(doc, world_mode, library), "Pack asset validates in either world: " + item["source_pack"] + "/" + world_mode)
			var sprite: Sprite2D = Parts.sprite_for(node)
			check(sprite != null and sprite.texture != null and sprite.get_rect().size.x > 0, "Pack asset renders in either world: " + item["source_pack"] + "/" + world_mode)
			if world_mode == "3d" and item.get("surface") == "ground": check(node.ground_tile, "Added ground lies flat: " + item["source_pack"])
			node.free()
		await process_frame
	check(represented.size() == registry["source_packs"].size(), "Every added pack has a usable representative")
	check(directional == registry["stats"]["directional"] and animated == registry["stats"]["animated"], "Directional views and animations are retained")
	print("ADDED ASSETS: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
