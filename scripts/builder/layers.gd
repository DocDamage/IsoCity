extends RefCounted

const NAMES: Array[String] = ["Ground", "Buildings", "Furniture", "Vehicles", "Nature", "Decorations", "Characters"]

static func classify(asset: String, library: RefCounted) -> String:
	return preload("res://scripts/builder/asset_behavior.gd").for_asset(asset, library).get("layer", "Decorations")

static func any(text: String, words: Array) -> bool:
	for word in words:
		if word in text: return true
	return false

static func layer(item: Dictionary, library: RefCounted) -> String:
	return item.get("layer", classify(item["asset"], library))

static func shown(data: Dictionary, name: String) -> bool:
	return data.get("layers", {}).get(name, {}).get("visible", true)

static func locked(data: Dictionary, name: String) -> bool:
	return data.get("layers", {}).get(name, {}).get("locked", false)

static func editable(data: Dictionary, item: Dictionary, library: RefCounted) -> bool:
	var name: String = layer(item, library)
	return shown(data, name) and not locked(data, name) and item.get("visible", true) and not item.get("locked", false)

static func set_state(data: Dictionary, name: String, property: String, value: bool) -> void:
	if not data.has("layers"): data["layers"] = {}
	if not data["layers"].has(name): data["layers"][name] = {}
	data["layers"][name][property] = value

static func collision_visibility(root: Node, enabled: bool) -> void:
	for node in [root] + root.find_children("*", "CollisionObject2D", true, false) + root.find_children("*", "CollisionObject3D", true, false):
		if node is CollisionObject2D or node is CollisionObject3D:
			if not node.has_meta("studio_layer"): node.set_meta("studio_layer", node.collision_layer)
			node.collision_layer = node.get_meta("studio_layer") if enabled else 0
