extends SceneTree

const Store = preload("res://scripts/builder/project_store.gd")
const Roads = preload("res://scripts/builder/roads.gd")
const Rows = preload("res://scripts/builder/layout_alignment.gd")
const Layers = preload("res://scripts/builder/layers.gd")
const Document = preload("res://scripts/builder/document.gd")

func _init() -> void: call_deferred("run")
func run() -> void:
	var library = preload("res://scripts/builder/asset_library.gd").new()
	var autosave_path: String = Store.resume_autosave()
	var session: Dictionary = Store.read_json(autosave_path, {})
	if session.is_empty() or not Document.valid(session.get("documents", {}).get("2d"), "2d", library): quit(1); return
	var before: Dictionary = session.duplicate(true)
	var data: Dictionary = session["documents"]["2d"]
	var plan: Dictionary = Rows.building_rows(data, library)
	var cars: int = 0
	var buildings: int = 0
	for item in data["objects"]:
		if plan.has(item["uid"]) and item["position"] != plan[item["uid"]]:
			print("BUILDING ", item["uid"], " ", item["position"], " -> ", plan[item["uid"]])
			item["position"] = plan[item["uid"]]
			buildings += 1
		if item["asset"].begins_with("3d:") and Layers.classify(item["asset"], library) == "Vehicles" and Layers.editable(data, item, library):
			var aligned: Dictionary = Roads.lane(data, item["position"], item["direction"], library, item["asset"], item["scale"])
			if aligned.get("snapped", false) and item["position"] != aligned["position"]:
				print("CAR ", item["uid"], " ", item["position"], " -> ", aligned["position"])
				item["position"] = aligned["position"]
				item["direction"] = aligned["direction"]
				cars += 1
	if "--apply" in OS.get_cmdline_user_args() and (cars + buildings) > 0:
		if Store.snapshot(before, "Before calibrated building and car alignment").is_empty(): quit(1); return
		if not Store.write_json(autosave_path, session): quit(1); return
	else:
		if not Store.write_json("res://output/alignment_preview.isocity.json", session): quit(1); return
	print("ALIGNMENT: ", buildings, " building placements and ", cars, " cars corrected", " (saved)" if "--apply" in OS.get_cmdline_user_args() else " (preview only)")
	quit()
