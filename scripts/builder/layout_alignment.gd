extends RefCounted

const Layers = preload("res://scripts/builder/layers.gd")

static func building_rows(data: Dictionary, library: RefCounted, allowed: Array = []) -> Dictionary:
	if data["mode"] != "2d": return {}
	var remaining: Array[Dictionary] = []
	for item in data["objects"]:
		if not allowed.is_empty() and not allowed.has(item["uid"]): continue
		if not Layers.editable(data, item, library) or not is_zero_approx(item.get("angle", 0)): continue
		var asset: Dictionary = library.assets.get(item["asset"], {})
		if asset.get("data", {}).get("source_pack") != "Brutalist Metropole v1.1.2": continue
		var view: Dictionary = asset["data"].get("directions", {}).get(item["direction"], {})
		if not view.has("alignment_transform"): continue
		var p: Array = item["position"]
		var x: float = (p[0] / 16.0 + p[1] / 8.0) * 0.5
		var y: float = (p[1] / 8.0 - p[0] / 16.0) * 0.5
		var size: float = item["scale"]
		remaining.append({"uid": item["uid"], "x": x, "y": y, "width": view["footprint"][0] * size, "depth": view["footprint"][1] * size, "height": p[2]})
	var result: Dictionary = {}
	while remaining.size() >= 3:
		var rows: Dictionary = {}
		for entry in remaining:
			var edge: int = roundi(entry["y"] + entry["depth"])
			rows[edge] = int(rows.get(edge, 0)) + 1
		var edge: int = rows.keys()[0]
		for key in rows:
			if rows[key] > rows[edge]: edge = key
		var group: Array[Dictionary] = []
		for entry in remaining:
			if absf(entry["y"] + entry["depth"] - edge) <= 1.05: group.append(entry)
		for entry in group: remaining.erase(entry)
		if group.size() < 3: continue
		group.sort_custom(func(a: Dictionary, b: Dictionary): return a["x"] < b["x"])
		var anchor: int = -1
		for i in group.size():
			if absf(group[i]["y"] + group[i]["depth"] - edge) < 0.05: anchor = i; break
		if anchor < 0: continue
		# Avoid pulling unrelated buildings together across a large empty space.
		var close: bool = true
		for i in range(1, group.size()):
			if absf(group[i]["x"] - group[i - 1]["x"] - group[i - 1]["width"]) > 1.1: close = false
		if not close: continue
		for i in range(anchor - 1, -1, -1): group[i]["x"] = group[i + 1]["x"] - group[i]["width"]
		for i in range(anchor + 1, group.size()): group[i]["x"] = group[i - 1]["x"] + group[i - 1]["width"]
		for entry in group:
			var y: float = edge - entry["depth"]
			result[entry["uid"]] = [(entry["x"] - y) * 16, (entry["x"] + y) * 8, entry["height"]]
	return result
