extends RefCounted

const Patterns = preload("res://scripts/builder/tile_patterns.gd")

static func model_root(instance: Node) -> Node3D:
	if instance.has_method("ground_polygon"): return instance.model
	return instance as Node3D

static func sprite_for(instance: Node) -> Sprite2D:
	if instance.has_method("mixed_bounds"): return instance.source.get_node_or_null("Sprite2D")
	return instance.get_node_or_null("Sprite2D")

static func base_texture(sprite: Sprite2D) -> Texture2D:
	var texture: Texture2D = sprite.texture
	return texture.get_meta("paint_base", texture) if texture else null

static func texture_reference(texture: Texture2D) -> Dictionary:
	if texture is AtlasTexture and texture.atlas:
		var area: Rect2=texture.region
		return {"texture":texture.atlas.resource_path,"atlas_region":[area.position.x,area.position.y,area.size.x,area.size.y]}
	return {"texture":texture.resource_path}

static func edit_texture(edit: Dictionary) -> Texture2D:
	var source: Texture2D=load(edit["texture"])
	var area: Array=edit.get("atlas_region",[])
	if not source or area.size()!=4: return source
	var result:=AtlasTexture.new(); result.atlas=source; result.region=Rect2(area[0],area[1],area[2],area[3]); result.filter_clip=true; return result

static func recolored_texture(texture: Texture2D, edits: Array) -> Texture2D:
	var reference: Dictionary=texture_reference(texture)
	var matching: Array = edits.filter(func(edit: Dictionary): return edit.get("kind") == "pixels" and edit.get("texture") == reference["texture"] and edit.get("atlas_region",[]) == reference.get("atlas_region",[]))
	if matching.is_empty(): return texture
	var picture: Image = texture.get_image().duplicate()
	if not picture or picture.is_empty(): return texture
	picture.convert(Image.FORMAT_RGBA8)
	for edit in matching:
		var rgba: Array = edit["color"]
		var color := Color(rgba[0], rgba[1], rgba[2], rgba[3])
		var pattern: Dictionary = edit.get("pattern", {})
		var pattern_image: Image = Patterns.picture(pattern) if not pattern.is_empty() else null
		for index in edit["pixels"]:
			var x: int = int(index) % picture.get_width()
			var y: int = int(index) / picture.get_width()
			if y >= 0 and y < picture.get_height():
				var alpha: float = picture.get_pixel(x, y).a
				if pattern_image:
					var uv: Vector2 = Patterns.sprite_uv(Vector2(x, y), pattern)
					var sample := Vector2i(floori(fposmod(uv.x, 1) * pattern_image.get_width()), floori(fposmod(uv.y, 1) * pattern_image.get_height()))
					var tile_color: Color = pattern_image.get_pixelv(sample)
					var base: Color = picture.get_pixel(x, y)
					color = base.lerp(Color(tile_color, base.a), tile_color.a)
				picture.set_pixel(x, y, Color(color, alpha))
	var result := ImageTexture.create_from_image(picture)
	result.set_meta("paint_base", texture)
	return result

static func pixels(sprite: Sprite2D, local: Vector2, tolerance: float, single: bool) -> Dictionary:
	var texture: Texture2D = base_texture(sprite)
	if not texture: return {}
	var image: Image = texture.get_image()
	var rect: Rect2 = sprite.get_rect()
	if not rect.has_point(local): return {}
	var frame_size := Vector2i(texture.get_width() / sprite.hframes, texture.get_height() / sprite.vframes)
	var start := Vector2i(local - rect.position) + sprite.frame_coords * frame_size
	var origin := sprite.frame_coords * frame_size
	if not Rect2i(origin, frame_size).has_point(start): return {}
	var target: Color = image.get_pixelv(start)
	if target.a < 0.05: return {}
	var result: Array[int] = []
	var queue: Array[Vector2i] = [start]
	var seen: Dictionary = {}
	var cursor: int = 0
	while cursor < queue.size() and result.size() < 262144:
		var point: Vector2i = queue[cursor]
		cursor += 1
		var index: int = point.y * image.get_width() + point.x
		if seen.has(index) or not Rect2i(origin, frame_size).has_point(point): continue
		seen[index] = true
		var color: Color = image.get_pixelv(point)
		if color.a < 0.05 or color_distance(color, target) > tolerance: continue
		result.append(index)
		if not single:
			for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]: queue.append(point + step)
	var edit: Dictionary=texture_reference(texture); edit.merge({"kind":"pixels","pixels":result,"frame":sprite.frame,"color":[target.r,target.g,target.b,target.a]}); return edit

static func color_distance(a: Color, b: Color) -> float:
	return maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))

static func original_mesh(node: MeshInstance3D) -> Mesh:
	return node.get_meta("paint_original", node.mesh)

static var pick_cache: Dictionary = {}

static func triangle_surfaces(mesh: Mesh) -> Array:
	var id: int = mesh.get_instance_id()
	if pick_cache.has(id): return pick_cache[id]["surfaces"]
	var result: Array = []
	for surface in mesh.get_surface_count():
		if mesh is ArrayMesh and mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES: result.append(null); continue
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = indices_for(arrays)
		var faces := PackedVector3Array()
		for index in indices: faces.append(vertices[index])
		var triangles := TriangleMesh.new()
		triangles.create_from_faces(faces)
		result.append(triangles)
	if pick_cache.size() >= 128: pick_cache.erase(pick_cache.keys()[0])
	pick_cache[id] = {"mesh": mesh, "surfaces": result}
	return result

static func visible_in_model(node: Node3D, root: Node3D) -> bool:
	var current: Node = node
	while current is Node3D:
		if not current.visible: return false
		if current == root: return true
		current = current.get_parent()
	return false

static func ray_pick(root: Node3D, from: Vector3, ray: Vector3, detached_projection: bool=false) -> Dictionary:
	var best: float = INF
	var result: Dictionary = {}
	var nodes: Array = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D: nodes.push_front(root)
	for node in nodes:
		if not (visible_in_model(node,root) if detached_projection else node.is_visible_in_tree()): continue
		var mesh: Mesh = original_mesh(node)
		if not mesh: continue
		var inverse: Transform3D = node.global_transform.affine_inverse()
		var local_from: Vector3 = inverse * from
		var local_ray: Vector3 = (inverse.basis * ray).normalized()
		if mesh.get_aabb().intersects_ray(local_from, local_ray) == null: continue
		var surfaces: Array = triangle_surfaces(mesh)
		for surface in surfaces.size():
			if not surfaces[surface]: continue
			var hit: Dictionary = surfaces[surface].intersect_ray(local_from, local_ray)
			if hit.is_empty(): continue
			var world: Vector3 = node.global_transform * hit["position"]
			var distance: float = from.distance_squared_to(world)
			if distance >= best: continue
			var arrays: Array = mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = indices_for(arrays)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var face: int = hit["face_index"]
			var triangle := PackedVector3Array([vertices[indices[face * 3]], vertices[indices[face * 3 + 1]], vertices[indices[face * 3 + 2]]])
			best = distance
			result = {"kind": "faces", "mesh": str(root.get_path_to(node)), "surface": surface, "face": face, "distance": distance, "triangle": triangle, "local_hit": hit["position"]}
	return result

static func indices_for(arrays: Array) -> PackedInt32Array:
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if indices.is_empty():
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for index in vertices.size(): indices.append(index)
	return indices

static func surface_color(node: MeshInstance3D, surface: int, face: int) -> Color:
	var mesh: Mesh = original_mesh(node)
	var material: Material = mesh.surface_get_material(surface)
	var color := Color.WHITE
	if material is BaseMaterial3D: color = material.albedo_color
	var arrays: Array = mesh.surface_get_arrays(surface)
	var indices: PackedInt32Array = indices_for(arrays)
	var vertex: int = indices[face * 3]
	if material is BaseMaterial3D and material.vertex_color_use_as_albedo and arrays[Mesh.ARRAY_COLOR] != null and arrays[Mesh.ARRAY_COLOR].size() > vertex:
		color *= arrays[Mesh.ARRAY_COLOR][vertex]
	if material is BaseMaterial3D and material.albedo_texture and arrays[Mesh.ARRAY_TEX_UV] != null:
		var uv: Vector2 = (arrays[Mesh.ARRAY_TEX_UV][vertex] + arrays[Mesh.ARRAY_TEX_UV][indices[face * 3 + 1]] + arrays[Mesh.ARRAY_TEX_UV][indices[face * 3 + 2]]) / 3
		var picture: Image = material.albedo_texture.get_image()
		if picture and not picture.is_empty(): color *= picture.get_pixel(posmod(floori(uv.x * picture.get_width()), picture.get_width()), posmod(floori(uv.y * picture.get_height()), picture.get_height()))
	return color

static func connected_faces(root: Node3D, hit: Dictionary, tolerance: float, single: bool) -> Dictionary:
	if hit.is_empty(): return {}
	var node: MeshInstance3D = root.get_node(hit["mesh"])
	var surface: int = hit["surface"]
	var arrays: Array = original_mesh(node).surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = indices_for(arrays)
	var count: int = indices.size() / 3
	var seed: Color = surface_color(node, surface, hit["face"])
	var edges: Dictionary = {}
	var face_edges: Array = []
	if not single:
		for face in count:
			var keys: Array[String] = []
			for corner in 3:
				var a: String = str(vertices[indices[face * 3 + corner]].snapped(Vector3.ONE * 0.0001))
				var b: String = str(vertices[indices[face * 3 + (corner + 1) % 3]].snapped(Vector3.ONE * 0.0001))
				var key: String = a + ":" + b if a < b else b + ":" + a
				keys.append(key)
				if not edges.has(key): edges[key] = []
				edges[key].append(face)
			face_edges.append(keys)
	var queue: Array = [hit["face"]]
	var seen: Dictionary = {}
	var selected: Array[int] = []
	var cursor: int = 0
	while cursor < queue.size():
		var face: int = queue[cursor]
		cursor += 1
		if seen.has(face): continue
		seen[face] = true
		if color_distance(surface_color(node, surface, face), seed) > tolerance: continue
		selected.append(face)
		if not single:
			for key in face_edges[face]:
				for neighbor in edges[key]:
					if not seen.has(neighbor): queue.append(neighbor)
	return {"kind": "faces", "mesh": hit["mesh"], "surface": surface, "faces": selected, "color": [seed.r, seed.g, seed.b, seed.a]}

static func apply(instance: Node, item: Dictionary) -> void:
	var edits: Array = item.get("colors", [])
	if item["asset"].begins_with("2d:"):
		var sprite: Sprite2D = sprite_for(instance)
		if not sprite: return
		sprite.texture = recolored_texture(base_texture(sprite), edits)
		if instance.has_method("mixed_bounds"):
			instance.last_frame = ""
			instance.update_visual()
		return
	var root: Node3D = model_root(instance)
	if not root: return
	var signature: String = JSON.stringify(edits)
	if root.get_meta("paint_signature", "") == signature: return
	for node in root.find_children("*", "MeshInstance3D", true, false):
		if not node.mesh: continue
		if not node.has_meta("paint_original"): node.set_meta("paint_original", node.mesh)
		var original: Mesh = node.get_meta("paint_original")
		var path: String = str(root.get_path_to(node))
		var matching: Array = edits.filter(func(edit: Dictionary): return edit.get("kind") == "faces" and edit.get("mesh") == path)
		if matching.is_empty(): node.mesh = original; continue
		var painted := ArrayMesh.new()
		for surface in original.get_surface_count():
			var arrays: Array = original.surface_get_arrays(surface)
			var indices: PackedInt32Array = indices_for(arrays)
			var colors: Dictionary = {}
			for edit in matching:
				if edit["surface"] == surface:
					for face in edit["faces"]: colors[int(face)] = edit
			var batches: Dictionary = {}
			var styles: Dictionary = {}
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var local_to_root: Transform3D = root.global_transform.affine_inverse() * node.global_transform
			for face in indices.size() / 3:
				var style: Dictionary = {}
				if colors.has(face):
					style = {"color": colors[face]["color"]}
					if colors[face].has("pattern"):
						style["pattern"] = colors[face]["pattern"]
						var a: Vector3 = local_to_root * vertices[indices[face * 3]]
						var b: Vector3 = local_to_root * vertices[indices[face * 3 + 1]]
						var c: Vector3 = local_to_root * vertices[indices[face * 3 + 2]]
						style["axis"] = (b - a).cross(c - a).abs().max_axis_index()
				var key: String = JSON.stringify(style) if not style.is_empty() else "original"
				styles[key] = style
				if not batches.has(key): batches[key] = PackedInt32Array()
				for corner in 3: batches[key].append(indices[face * 3 + corner])
			for key in batches:
				var subset: Array = arrays.duplicate()
				subset[Mesh.ARRAY_INDEX] = batches[key]
				painted.add_surface_from_arrays(original.surface_get_primitive_type(surface), subset)
				var material: Material = original.surface_get_material(surface)
				if key != "original":
					material = material.duplicate() if material is StandardMaterial3D else StandardMaterial3D.new()
					var style: Dictionary = styles[key]
					var rgba: Array = style["color"]
					material.albedo_color = Color(rgba[0], rgba[1], rgba[2], rgba[3])
					material.albedo_texture = null
					material.vertex_color_use_as_albedo = false
					if style.has("pattern"):
						material.albedo_color = Color.WHITE
						material.albedo_texture = Patterns.texture(style["pattern"])
						material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
						material.texture_repeat = true
						material.uv1_scale = Vector3.ONE
						material.uv1_offset = Vector3.ZERO
						var uv := PackedVector2Array()
						for vertex in vertices: uv.append(Patterns.mesh_uv(local_to_root * vertex, style["axis"], style["pattern"]))
						subset[Mesh.ARRAY_TEX_UV] = uv
						# Replace the just-added surface with its projected UVs.
						var surface_index: int = painted.get_surface_count() - 1
						painted.surface_remove(surface_index)
						painted.add_surface_from_arrays(original.surface_get_primitive_type(surface), subset)
				painted.surface_set_material(painted.get_surface_count() - 1, material)
		node.mesh = painted
	root.set_meta("paint_signature", signature)
	if instance.has_method("ground_polygon"): instance.update_projection()

static func valid(edits: Variant) -> bool:
	if not edits is Array or edits.size() > 1024: return false
	for edit in edits:
		if not edit is Dictionary or not edit.get("color") is Array or edit["color"].size() != 4: return false
		for channel in edit["color"]:
			if not (channel is int or channel is float) or not is_finite(channel) or channel < 0 or channel > 1: return false
		if edit.has("pattern") and not Patterns.valid(edit["pattern"]): return false
		if edit.get("kind") == "pixels":
			if not edit.get("texture") is String or not edit.get("pixels") is Array or edit["pixels"].size() > 262144: return false
			if edit.has("atlas_region"):
				if not edit["atlas_region"] is Array or edit["atlas_region"].size()!=4: return false
				for index in 4:
					var value: Variant=edit["atlas_region"][index]
					if not (value is int or value is float) or not is_finite(value) or floorf(value)!=value or value<(0 if index<2 else 1) or value>16384: return false
			for index in edit["pixels"]:
				if not (index is int or index is float) or not is_finite(index) or index < 0 or index > 16777216 or floorf(index) != index: return false
		elif edit.get("kind") == "faces":
			if not edit.get("mesh") is String or not (edit.get("surface") is float or edit.get("surface") is int): return false
			if not is_finite(edit["surface"]) or edit["surface"] < 0 or edit["surface"] > 4096 or floorf(edit["surface"]) != edit["surface"]: return false
			if not edit.get("faces") is Array or edit["faces"].size() > 262144: return false
			for face in edit["faces"]:
				if not (face is int or face is float) or not is_finite(face) or face < 0 or face > 10000000 or floorf(face) != face: return false
		else: return false
	return true
