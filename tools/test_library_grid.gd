extends SceneTree

const Library = preload("res://scripts/builder/asset_library.gd")
const Fit = preload("res://scripts/builder/grid_fit.gd")
const Factory = preload("res://scripts/builder/asset_instance.gd")
var checks: int = 0
var failures: int = 0
var assets: int = 0
var views: int = 0

func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL: ", message)

func run() -> void:
	var library := Library.new()
	for id in library.assets:
		assets += 1
		var asset: Dictionary = library.assets[id]
		if id.begins_with("2d:"):
			var node: Node2D = load(asset["path"]).instantiate()
			root.add_child(node)
			for direction in asset["data"]["directions"]:
				views += 1
				var view: Dictionary = asset["data"]["directions"][direction]
				node.direction = direction
				var sprite: Sprite2D = node.get_node("Sprite2D")
				check(view.has("grid_method") and sprite.texture and sprite.get_rect().size.x > 0, "Every view is audited and renders: " + id + "/" + direction)
				if view.has("alignment_transform"):
					var foot := Vector2(view["footprint"][0], view["footprint"][1])
					var contact: Array = view["grid_contact"]
					var actual: Vector2 = sprite.transform * (Vector2(contact[0], contact[1]) - node.origin_offset)
					check(actual.distance_to(Fit.pixels(foot)) < 0.003, "Rendered contact meets the footprint front: " + id + "/" + direction)
					var scaled: Vector2 = foot * float(asset["data"].get("default_scale", 1))
					check(scaled.is_equal_approx(scaled.round()), "Default imported footprint has whole cells: " + id + "/" + direction)
				for angle in [0.0, 45.0, 90.0]:
					var item: Dictionary = {"asset": id, "direction": direction, "angle": angle, "scale": float(asset["data"].get("default_scale", 1)), "position": [41.0, 37.0, 0.0]}
					var position: Array = Fit.snap(item, "2d", library)
					var low: Vector3 = Fit.minimum(item, "2d", library)
					var corner: Vector2 = Fit.grid(Vector2(position[0], position[1])) + Vector2(low.x, low.z)
					check(corner.distance_to(corner.round()) < 0.0001, "Rotated base snaps to a grid intersection: " + id + "/" + direction)
			node.free()
		else:
			var model: Node3D = load(asset["path"]).instantiate()
			var measured: AABB = preload("res://scripts/model_bounds.gd").contact_bounds(model)
			check(Fit.bounds_for(id, library).is_equal_approx(measured), "Audit matches current source mesh contact vertices: " + id)
			model.free()
			for angle in [0.0, 45.0, 90.0, 180.0, 270.0]:
				for size in [0.5, 1.0, 1.5]:
					var item: Dictionary = {"asset": id, "direction": str(angle), "scale": size, "position": [2.2, 0.0, -3.7]}
					var low: Vector3 = Fit.minimum(item, "3d", library)
					var placed: Array = Fit.place([3.0, 0.0, 4.0], item, "3d", library)
					check(Vector3(placed[0], placed[1], placed[2]).is_equal_approx(Vector3(3, 0, 4) - low), "Actual model base, not its source pivot, aligns with the ground: " + id)
					var snapped: Array = Fit.snap(item, "3d", library)
					check(is_equal_approx(snapped[0] + low.x, roundf(snapped[0] + low.x)) and is_equal_approx(snapped[2] + low.z, roundf(snapped[2] + low.z)), "Scaled/rotated model base meets grid lines: " + id)
		if assets % 100 == 0: await process_frame
	var report: Dictionary = {"assets": assets, "sprite_views": views, "checks": checks, "failures": failures}
	var canal: String = ""
	for id in library.assets:
		if library.assets[id]["data"].get("source_name", "").ends_with("Canal E Bend"): canal = id
	check(not canal.is_empty(), "The user's modular canal family is audited")
	if not canal.is_empty():
		var record: Dictionary = {"uid": "legacy_canal", "asset": canal, "direction": "SE", "scale": 0.25, "position": [192.0, 176.0, 0.0], "colors": []}
		var session: Dictionary = {"documents": {"2d": {"mode": "2d", "objects": [record]}, "3d": {"mode": "3d", "objects": []}}}
		var migration = preload("res://scripts/builder/grid_migration.gd")
		check(migration.apply(session, library) == 1, "Opening an old layout compensates for its changed asset anchor")
		var view: Dictionary = library.assets[canal]["data"]["directions"]["SE"]
		var old: Dictionary = migration.legacy[canal]["SE"]
		var raw := Vector2(view["grid_contact"][0], view["grid_contact"][1])
		var previous: Vector2 = Vector2(192, 176) + migration.matrix(old["transform"]) * (raw - Vector2(old["origin"][0], old["origin"][1])) * 0.25
		var current: Vector2 = Vector2(record["position"][0], record["position"][1]) + migration.matrix(view["alignment_transform"]) * (raw - Vector2(view["origin"][0], view["origin"][1])) * 0.25
		check(previous.distance_to(current) <= 18, "Legacy art keeps its visible ground contact within the nearest grid intersection")
		var once: Dictionary = session.duplicate(true)
		check(migration.apply(session, library) == 0 and session == once, "Grid migration applies only once and preserves piece paint")
	report["checks"] = checks
	report["failures"] = failures
	preload("res://scripts/builder/project_store.gd").write_json("res://output/asset_grid_audit/runtime.json", report)
	print("LIBRARY GRID: %d assets, %d sprite views; %d/%d checks passed" % [assets, views, checks - failures, checks])
	quit(1 if failures else 0)
