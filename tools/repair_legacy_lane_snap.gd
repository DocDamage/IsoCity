extends SceneTree

# Explicit one-time repair for models placed using the old pixel-road lane origin.
func _init() -> void: call_deferred("run")

func run() -> void:
	if not "--repair-autosave" in OS.get_cmdline_user_args(): quit(); return
	var Store = preload("res://scripts/builder/project_store.gd")
	var Roads = preload("res://scripts/builder/roads.gd")
	var Layers = preload("res://scripts/builder/layers.gd")
	var library = preload("res://scripts/builder/asset_library.gd").new()
	var autosave_path: String = Store.resume_autosave()
	var session: Variant = Store.read_json(autosave_path, {})
	if not session is Dictionary or not session.get("documents") is Dictionary: quit(1); return
	var doc: Dictionary = session["documents"]["2d"]
	if not preload("res://scripts/builder/document.gd").valid(doc, "2d", library): quit(1); return
	var before: Dictionary = session.duplicate(true)
	var count: int = 0
	for item in doc["objects"]:
		if not item["asset"].begins_with("3d:") or Layers.classify(item["asset"], library) != "Vehicles" or not Layers.editable(doc, item, library): continue
		if not ["0", "90", "180", "270"].has(item["direction"]) or item.has("tilt"): continue
		var result: Dictionary = Roads.lane(doc, item["position"], item["direction"], library, item["asset"], item["scale"])
		if not result.get("snapped", false) or item["position"] == result["position"]: continue
		item["position"] = result["position"]
		item["direction"] = result["direction"]
		count += 1
	if count > 0:
		var snapshot: String = Store.snapshot(before, "Before correcting 3D car lanes")
		if snapshot.is_empty() or not Store.write_json(autosave_path, session): quit(1); return
	print("LANE REPAIR: aligned ", count, " placed models; previous layout retained as a named snapshot")
	quit()
