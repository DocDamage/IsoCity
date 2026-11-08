extends RefCounted

const Economy = preload("res://scripts/builder/economy_plan.gd")
const Budget = preload("res://scripts/builder/rendering_budget.gd")

# Resource paths survive temporary scene instantiation. Retain references for
# pathless resources so their instance IDs cannot be recycled during a scan.
var sources: Dictionary = {}
var library: RefCounted

func _init(asset_library: RefCounted) -> void:
	library = asset_library

static func quote_text(quote: Dictionary) -> String:
	if quote.is_empty(): return ""
	if quote.get("ok", false) and not quote.get("enabled", false):
		return "Exact economy quote · Creative mode · 0 credits"
	if not quote.has("construction"): return str(quote.get("reason", ""))
	var label := "Exact economy quote\nConstruction %d · refund %d · net charge %+d credits" % [
		quote["construction"], quote["refund"], quote["net"]]
	if not quote["ok"]: label += "\n" + quote["reason"]
	return label

static func units(data: Dictionary, path: Array = [], depth: int = 0, result: Dictionary = {}) -> Dictionary:
	if depth == 0: result = {}
	if depth > 4: return result
	for floor in data.get("floors", []):
		units(floor["room"], path + ["floor", floor["uid"]], depth + 1, result)
	for item in data.get("objects", []):
		var key: Array = path + ["object", item["uid"]]
		result[JSON.stringify(key)] = item
		if item.get("interior") is Dictionary: units(item["interior"], key + ["interior"], depth + 1, result)
	for tile in data.get("tiles", []):
		result[JSON.stringify(path + ["tile", tile["cell"]])] = tile
	return result

static func change(before: Dictionary, after: Dictionary) -> Dictionary:
	var previous: Dictionary = units(before)
	var next: Dictionary = units(after)
	var added: Dictionary = {}
	var removed: Dictionary = {}
	for key in next:
		if signature(next[key]) != signature(previous.get(key, {})): added[key] = next[key]
	for key in previous:
		if signature(previous[key]) != signature(next.get(key, {})): removed[key] = previous[key]
	var roads = preload("res://scripts/builder/roads.gd")
	var old_roads: Dictionary = roads.lookup(before)
	var new_roads: Dictionary = roads.lookup(after)
	var touched: int = 0
	for cell in new_roads:
		if new_roads[cell] != old_roads.get(cell, {}): touched += 1
	for cell in old_roads:
		if not new_roads.has(cell): touched += 1
	return {"added": added, "removed": removed, "roads": new_roads.size() - old_roads.size(), "road_edits": touched}

static func signature(item: Dictionary) -> Array:
	return [item.get("asset", ""), item.get("direction", ""), item.get("angle", 0), item.get("tilt", [0, 0]), item.get("colors", [])]

static func resource_key(resource: Resource) -> Variant:
	return resource.get_instance_id() if resource.resource_path.is_empty() else resource.resource_path

static func store_texture(textures: Dictionary, texture: Texture2D) -> void:
	if not texture: return
	while texture is AtlasTexture and texture.atlas: texture = texture.atlas
	textures[resource_key(texture)] = texture

func scan(id: String, direction: String, edition: Dictionary = {}) -> Dictionary:
	var asset: Dictionary = library.assets.get(id, {})
	var path: String = edition.get("path", asset.get("path", ""))
	var key: Array = [id, path, direction if asset.get("mode") == "2d" else ""]
	if sources.has(key): return sources[key]
	# Bound retained import resources when inspecting many assets in one session.
	if sources.size() >= 64: sources.erase(sources.keys()[0])
	var found := {"triangles": 0, "materials": {}, "textures": {}, "available": false}
	sources[key] = found
	if asset.is_empty() or path.is_empty(): return found
	if asset["mode"] == "2d":
		var views: Dictionary = asset["data"].get("directions", {})
		if not views.has(direction): return found
		var texture: Texture2D = library.icon_for(id, direction)
		if not texture: return found
		store_texture(found["textures"], texture)
		found["available"] = true
		return found
	if not ResourceLoader.exists(path, "PackedScene"): return found
	var scene := load(path) as PackedScene
	if not scene: return found
	var root: Node = scene.instantiate()
	for node in [root] + root.find_children("*", "MeshInstance3D", true, false):
		if not node is MeshInstance3D or not node.mesh: continue
		for surface in node.mesh.get_surface_count():
			var mesh: Mesh = node.mesh
			if mesh is ArrayMesh and mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES: continue
			var arrays: Array = mesh.surface_get_arrays(surface)
			if not arrays.is_empty():
				var indices: Variant = arrays[Mesh.ARRAY_INDEX]
				var vertices: Variant = arrays[Mesh.ARRAY_VERTEX]
				var count: int = indices.size() if indices != null and not indices.is_empty() else vertices.size() if vertices != null else 0
				found["triangles"] += count / 3
			var material: Material = node.get_active_material(surface)
			if not material or found["materials"].has(resource_key(material)): continue
			found["materials"][resource_key(material)] = material
			for property in material.get_property_list():
				var name: String = property["name"]
				if property["type"] != TYPE_OBJECT or not name.ends_with("_texture"): continue
				var image: Variant = material.get(name)
				if image is Texture2D: store_texture(found["textures"], image)
	root.free()
	found["available"] = true
	return found

func estimate(records: Dictionary, mode: String, edition: Dictionary = {}) -> Dictionary:
	var result := {"instances": records.size(), "models": 0, "live": 0, "shared": 0, "triangles": 0,
		"materials": 0, "textures": 0, "texture_bytes": 0, "painted": 0, "unknown": 0}
	var materials: Dictionary = {}
	var textures: Dictionary = {}
	var views: Dictionary = {}
	for key in records:
		var item: Dictionary = records[key]
		var asset: Dictionary = library.assets.get(item.get("asset", ""), {})
		var painted: bool = not item.get("colors", []).is_empty()
		if painted: result["painted"] += 1
		if asset.is_empty() or item.has("missing_asset"):
			result["unknown"] += 1
			continue
		var id: String = asset["id"]
		var source: Dictionary = scan(id, item.get("direction", ""), edition)
		if not source["available"]: result["unknown"] += 1
		result["triangles"] += source["triangles"]
		materials.merge(source["materials"])
		textures.merge(source["textures"])
		if asset["mode"] != "3d": continue
		result["models"] += 1
		if mode != "2d": continue
		if painted or not edition.is_empty() or not Budget.share_projection(asset): result["live"] += 1
		else:
			var scope: Variant = JSON.parse_string(key) if str(key).begins_with("[") else []
			views[JSON.stringify([scope.slice(0, -2) if scope is Array else [], signature(item)])] = true
	result["shared"] = views.size()
	result["materials"] = materials.size()
	result["textures"] = textures.size()
	for texture: Texture2D in textures.values(): result["texture_bytes"] += texture.get_width() * texture.get_height() * 4
	return result

static func estimate_text(value: Dictionary, mode: String) -> String:
	var description := "%d %s · %d %s · %s source triangles\n%d model material resources · %d source texture resources (%.2f MiB as RGBA8)" % [
		value["instances"], "instance" if value["instances"] == 1 else "instances",
		value["models"], "model" if value["models"] == 1 else "models",
		str(value["triangles"]), value["materials"], value["textures"], value["texture_bytes"] / 1048576.0]
	if mode == "2d" and value["models"] > 0:
		description += "\nPixel models · %d private live views · %d shareable views per room and pose" % [value["live"], value["shared"]]
	if value["painted"] > 0: description += "\n%d painted instances can allocate extra materials or textures." % value["painted"]
	if value["unknown"] > 0: description += "\nSource metrics unavailable for %d instances." % value["unknown"]
	return description

func render_text(before: Dictionary, after: Dictionary) -> String:
	var delta: Dictionary = change(before, after)
	var mode: String = after["mode"]
	var lines := PackedStringArray(["Approximate render cost"])
	if not delta["added"].is_empty(): lines.append("Proposed · " + estimate_text(estimate(delta["added"], mode), mode))
	if not delta["removed"].is_empty(): lines.append("Removed or replaced · " + estimate_text(estimate(delta["removed"], mode), mode))
	if delta["road_edits"] > 0:
		lines.append("%d edited road sections (%+d total) · generated geometry" % [delta["road_edits"], delta["roads"]])
	if lines.size() == 1: lines.append("No change to asset instances or road count.")
	lines.append("Source counts exclude visibility, compression and frame timing.")
	return "\n".join(lines)
