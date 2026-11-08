@tool
class_name Catalog
extends RefCounted

static var _registry: Dictionary = {}
static var _loaded: bool = false

static func get_registry() -> Dictionary:
	if not _loaded:
		_load_registry()
	return _registry

static func get_item(id: String) -> Dictionary:
	var reg := get_registry()
	var items_dict: Dictionary = reg.get("items", {})
	return items_dict.get(id, {})

static func get_categories() -> Array:
	var reg := get_registry()
	return reg.get("categories", [])

static func get_items_in_category(cat: String) -> Array:
	var reg := get_registry()
	var by_cat: Dictionary = reg.get("by_category", {})
	return by_cat.get(cat, [])

static func get_scene_path(id: String) -> String:
	var item: Dictionary = get_item(id)
	if item.is_empty():
		return ""
	if item.has("scene_path"): return item["scene_path"]
	var category: String = item.get("category", "")
	if category.begins_with("RPG_"):
		return "res://scenes/items/RPG_World/%s/%s.tscn" % [category.trim_prefix("RPG_"), id]
	return "res://scenes/items/%s/%s.tscn" % [category.replace(" & ", "_").replace(" ", "_"), id]

static func _load_registry() -> void:
	_loaded = true
	var path: String = "res://resources/catalog/catalog_registry.json"
	if not FileAccess.file_exists(path):
		path = "res://assets/pixel_isometric/items.json"
		if not FileAccess.file_exists(path):
			return
	
	var file := FileAccess.open(path, FileAccess.READ)
	if file:
		var json_str := file.get_as_text()
		var json := JSON.new()
		var err := json.parse(json_str)
		if err == OK and json.data is Dictionary:
			var raw_dict: Dictionary = json.data
			if raw_dict.has("by_category"):
				_registry = raw_dict
			else:
				_registry = _process_raw_items_json(raw_dict)
	for added_path in ["res://resources/catalog/imported_registry.json","res://resources/catalog/supplemental_registry.json","res://resources/catalog/swat_registry.json","res://resources/catalog/reviewed_registry.json"]:
		if not FileAccess.file_exists(added_path): continue
		var added: Variant = JSON.parse_string(FileAccess.get_file_as_string(added_path))
		if added is Dictionary:
			if not _registry.has("models"): _registry["models"]={}
			_registry["models"].merge(added.get("models",{}),true)
			for id in added.get("items", {}):
				var item: Dictionary = added["items"][id]
				_registry["items"][id] = item
				var category: String = item["category"]
				if not _registry["categories"].has(category): _registry["categories"].append(category)
				if not _registry["by_category"].has(category): _registry["by_category"][category] = []
				if not _registry["by_category"][category].has(id): _registry["by_category"][category].append(id)

static func _process_raw_items_json(raw: Dictionary) -> Dictionary:
	var processed: Dictionary = {
		"categories": raw.get("categories", []),
		"items": {},
		"by_category": {}
	}
	for cat in processed["categories"]:
		processed["by_category"][cat] = []
		
	var item_list: Array = raw.get("items", [])
	for item in item_list:
		var iid: String = item.get("name", "")
		var cat: String = item.get("category", "")
		processed["items"][iid] = item
		if not processed["by_category"].has(cat):
			processed["by_category"][cat] = []
		processed["by_category"][cat].append(iid)
		
	return processed

