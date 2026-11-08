extends RefCounted

# Descriptive evidence is generated from reviewed source clips. This module
# never assigns gameplay merely because a filename contains an action word.
const PATH = "res://resources/catalog/asset_metadata.json"
static var catalog: Dictionary = {}
static var loaded: bool = false

static func for_asset(id: String) -> Dictionary:
	if not loaded:
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else {}
		var entries: Dictionary = raw.get("assets", {}) if raw is Dictionary and raw.get("assets") is Dictionary else {}
		for key in entries:
			if entries[key] is Dictionary and entries[key].get("runtime_actions") is Dictionary: catalog[key] = entries[key]["runtime_actions"]
		loaded = true
	var key: String = id if id.begins_with("2d:") else "2d:" + id
	var value: Variant = catalog.get(key, {})
	return value if value is Dictionary else {}
