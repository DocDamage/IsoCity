extends SceneTree

const Library = preload("res://scripts/builder/asset_library.gd")
const Bounds = preload("res://scripts/model_bounds.gd")

func _init() -> void: call_deferred("run")
func run() -> void:
	var library := Library.new()
	var report: Dictionary = {"assets": {}, "errors": [], "models": 0}
	for id in library.assets:
		if not id.begins_with("3d:"): continue
		var node: Node3D = load(library.assets[id]["path"]).instantiate()
		var bounds: AABB = Bounds.get_bounds(node)
		if bounds.size.x <= 0 or bounds.size.z <= 0 or not bounds.position.is_finite() or not bounds.size.is_finite():
			report["errors"].append(id)
		else:
			var base: AABB = Bounds.contact_bounds(node)
			report["assets"][id] = {"min": [bounds.position.x, bounds.position.y, bounds.position.z], "size": [bounds.size.x, bounds.size.y, bounds.size.z], "base_min": [base.position.x, base.position.y, base.position.z], "base_size": [base.size.x, base.size.y, base.size.z], "method": "mesh contact vertices"}
			report["models"] += 1
		node.free()
	var path: String = "res://resources/catalog/model_grid_bounds.json"
	preload("res://scripts/builder/project_store.gd").write_json(path, report)
	print("MODEL GRID AUDIT: ", report["models"], " models, ", report["errors"].size(), " errors")
	quit(0 if report["errors"].is_empty() else 1)
