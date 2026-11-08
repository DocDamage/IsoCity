extends RefCounted

const Fit = preload("res://scripts/builder/grid_fit.gd")
static var legacy: Dictionary = {}

static func matrix(values: Array) -> Transform2D:
	return Transform2D(Vector2(values[0], values[1]), Vector2(values[2], values[3]), Vector2.ZERO)

static func apply(session: Dictionary, library: RefCounted) -> int:
	if session.get("grid_version", 0) >= 2: return 0
	if legacy.is_empty(): legacy = JSON.parse_string(FileAccess.get_file_as_string("res://resources/catalog/grid_legacy_profiles.json"))
	var count: int = 0
	var data: Dictionary = session.get("documents", {}).get("2d", {})
	for item in data.get("objects", []):
		var id: String = item["asset"]
		if not legacy.has(id) or not library.assets.has(id): continue
		var direction: String = item["direction"]
		var views: Dictionary = library.assets[id]["data"]["directions"]
		var view: Dictionary = views.get(direction, views.get("SE", views.values()[0]))
		var old_views: Dictionary = legacy[id]
		var old: Dictionary = old_views.get(direction, old_views.get("SE", old_views.values()[0]))
		var old_matrix: Transform2D = matrix(old["transform"])
		var new_matrix: Transform2D = matrix(view.get("alignment_transform", [1, 0, 0, 1]))
		var origin := Vector2(view["origin"][0], view["origin"][1])
		var old_origin := Vector2(old["origin"][0], old["origin"][1])
		if origin.is_equal_approx(old_origin) and old_matrix.is_equal_approx(new_matrix): continue
		var raw: Array = view["grid_contact"]
		var contact := Vector2(raw[0], raw[1])
		var offset: Vector2 = ((old_matrix * (contact - old_origin) - new_matrix * (contact - origin)) * item["scale"]).rotated(deg_to_rad(item.get("angle", 0)))
		item["position"] = [item["position"][0] + offset.x, item["position"][1] + offset.y, item["position"][2]]
		if preload("res://scripts/builder/layers.gd").editable(data, item, library): item["position"] = Fit.snap(item, "2d", library)
		count += 1
	session["grid_version"] = 2
	return count
