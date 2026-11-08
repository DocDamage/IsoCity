extends RefCounted

const PATH: String = "res://resources/catalog/asset_behaviors.json"
static var catalog: Dictionary = {}
static var loaded: bool = false

static func get_behavior(id: String) -> Dictionary:
	if not loaded:
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		catalog = value if value is Dictionary else {}
		loaded = true
	return catalog.get(id, {"layer": "Decorations", "building": false, "door": false, "vehicle": false, "ground": false, "collision": "box"})

static func for_asset(id: String, library: RefCounted = null) -> Dictionary:
	if library and library.assets.has(id):
		return library.assets[id].get("behavior", get_behavior(id))
	return get_behavior(id)
