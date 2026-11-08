extends RefCounted

const PATH = "res://resources/catalog/asset_metadata.json"
var members: Dictionary = {}
var representatives: Dictionary = {}
var preferences: Dictionary = {}
var revision: int = 0

static func palette_name(value: String) -> String:
	return {"nopalette": "Original colors", "16bit": "16-bit", "16bit_dither": "16-bit · dithered", "24bit": "24-bit", "voyager": "Voyager", "voyager_dither": "Voyager · dithered"}.get(value, value.replace("_", " ").capitalize())

func build(assets: Dictionary) -> void:
	members.clear(); representatives.clear()
	var overlay: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else {}
	var metadata: Dictionary = overlay.get("assets", {}) if overlay is Dictionary and overlay.get("version") == 1 else {}
	var ids: Array = assets.keys(); ids.sort()
	for id in ids:
		var asset: Dictionary = assets[id]
		if not id.contains(":Custom/"):
			# Explicit custom descriptors remain authoritative. Overlay fields add
			# descriptions and appearance identity, never gameplay behavior.
			asset["data"].merge(metadata.get(id, {}), true)
			var reviewed_name: Variant = asset["data"].get("display_name", "")
			if asset["data"].has("name_key") and reviewed_name is String and not reviewed_name.strip_edges().is_empty(): asset["name"] = reviewed_name
		var family: String = asset["data"].get("family_id", "")
		if family.is_empty(): continue
		if not members.has(family): members[family] = []
		members[family].append(id)
		if not representatives.has(family) or score(asset) > score(assets[representatives[family]]): representatives[family] = id
	revision += 1

func score(asset: Dictionary) -> int:
	var data: Dictionary = asset["data"]
	return (100 if data.get("palette_id", "") == "nopalette" else 0) + (10 if data.get("lighting_id", "") == "studio" else 0)

func remember(asset: Dictionary) -> void:
	var data: Dictionary = asset["data"]
	if not data.get("appearance_group", "").is_empty(): preferences[data["appearance_group"]] = [data.get("palette_id", ""), data.get("lighting_id", "")]

func preferred(asset: Dictionary) -> bool:
	var data: Dictionary = asset["data"]
	return preferences.get(data.get("appearance_group", ""), []) == [data.get("palette_id", ""), data.get("lighting_id", "")]

func collapse(found: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var groups: Dictionary = {}
	for asset in found:
		var family: String = asset["data"].get("family_id", "")
		if family.is_empty(): result.append(asset); continue
		var priority: int = score(asset) + (1000 if preferred(asset) else 0)
		if groups.has(family):
			var current: Dictionary = result[groups[family]["index"]]
			if priority > groups[family]["score"] or (priority == groups[family]["score"] and asset["id"] < current["id"]): result[groups[family]["index"]] = asset; groups[family]["score"] = priority
		else:
			groups[family] = {"index": result.size(), "score": priority}; result.append(asset)
	return result

func options(asset: Dictionary, assets: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in members.get(asset["data"].get("family_id", ""), []):
		if assets.has(id) and not assets[id].get("unavailable", false) and not assets[id].get("hidden", false): result.append(assets[id])
	return result
