extends RefCounted

# Roads are a non-destructive overlay: removing a road reveals the original ground.
const Settings = preload("res://scripts/builder/road_settings.gd")
const STEPS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]

static func key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]

static func cell_at(position: Array, mode: String) -> Vector2i:
	if mode == "2d":
		var point := Vector2(position[0] / 16.0, position[1] / 8.0)
		return Vector2i(roundi((point.x + point.y) / 8.0), roundi((point.y - point.x) / 8.0))
	return Vector2i(roundi(position[0] / 8.0), roundi(position[2] / 8.0))

static func path(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = [a]
	var cursor := a
	# Bound each gesture so accidental distant clicks cannot freeze the editor.
	while cursor != b and result.size() < 256:
		if cursor.x != b.x: cursor.x += signi(b.x - cursor.x)
		else: cursor.y += signi(b.y - cursor.y)
		result.append(cursor)
	return result

static func paint(data: Dictionary, a: Vector2i, b: Vector2i, erase: bool = false, configuration: Dictionary = {}) -> void:
	if not configuration.is_empty() and not Settings.valid(configuration): return
	if not data.has("roads"): data["roads"] = []
	for cell in path(a, b):
		var existing: Dictionary = {}
		for entry in data["roads"]:
			var coordinates: Array=entry["cell"]
			if Vector2i(coordinates[0],coordinates[1])==cell:
				existing=entry
				break
		if erase:
			if not existing.is_empty(): data["roads"].erase(existing)
		elif existing.is_empty() and data["roads"].size() < 4096:
			var added: Dictionary = {"cell": [cell.x, cell.y], "crossing": false}
			if not configuration.is_empty(): added.merge(Settings.profile(configuration))
			data["roads"].append(added)
		elif not existing.is_empty() and not configuration.is_empty(): existing.merge(Settings.profile(configuration), true)

static func lookup(data: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for entry in data.get("roads", []): result[key(Vector2i(entry["cell"][0], entry["cell"][1]))] = entry
	return result

static func mask(cell: Vector2i, network: Dictionary) -> int:
	var result: int = 0
	for i in 4:
		if network.has(key(cell + STEPS[i])): result |= 1 << i
	return result

static func tiles(data: Dictionary) -> Array:
	var result: Dictionary = {}
	for tile in data["tiles"]: result[key(Vector2i(tile["cell"][0], tile["cell"][1]))] = tile
	var network: Dictionary = lookup(data)
	# Rasterize transitions on the tile grid. All style families are compatible.
	var entries: Array = network.values()
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return key(Vector2i(a["cell"][0], a["cell"][1])) < key(Vector2i(b["cell"][0], b["cell"][1])))
	for paving in [true, false]:
		for entry in entries:
			var coarse := Vector2i(entry["cell"][0], entry["cell"][1])
			var cell: Vector2i = coarse * 4
			var half: float = Settings.outer_half(entry) * 0.5 if paving else Settings.half_width(entry) * 0.5
			for x in range(-2, 3):
				for y in range(-2, 3):
					var included: bool = absi(x) <= half and absi(y) <= half if paving else absi(x) < half and absi(y) < half
					if paving:
						if not entry.get("sidewalks", true): included = false
						for direction in STEPS:
							if network.has(key(coarse + direction)) and x * direction.x + y * direction.y > Settings.half_width(entry) * 0.5: included = false
					for direction in STEPS:
						var other: Dictionary = network.get(key(coarse + direction), {})
						if other.is_empty(): continue
						if paving and not entry.get("sidewalks", true) and not other.get("sidewalks", true): continue
						var along: float = x * direction.x + y * direction.y
						var across: float = absf(y if direction.x else x)
						if along < 0 or along > 2: continue
						var other_half: float = Settings.outer_half(other) * 0.5 if paving else Settings.half_width(other) * 0.5
						var edge: float = lerpf(half, other_half, along / 4.0)
						if (across <= edge if paving else across < edge): included = true
					if included: put_tile(result, cell + Vector2i(x, y), "Sidewalk" if paving else Settings.TILES[entry.get("style", "asphalt")])
	for entry in entries:
		var coarse := Vector2i(entry["cell"][0], entry["cell"][1])
		var cell: Vector2i = coarse * 4
		var links: int = mask(coarse, network)
		if entry.get("style", "asphalt") == "asphalt":
			if links in [1, 4, 5]: put_tile(result, cell, "Road_Center_Dash_X")
			elif links in [2, 8, 10]: put_tile(result, cell, "Road_Center_Dash_Y")
		if entry.get("cycle_access","none") != "none":
			result[key(cell)] = {"cell":[cell.x,cell.y],"asset":"2d:Bike_Lane","direction":"SW" if links in [2,8,10] else "SE"}
		if entry.get("crossing", false) or count_bits(links) >= 3:
			var radius: int = 1 if entry.get("width", 6) == 6 else 0
			for offset in range(-radius, radius + 1): put_tile(result, cell + Vector2i(0, offset), "Crosswalk_X")
	return result.values()

static func put_tile(result: Dictionary, cell: Vector2i, asset: String) -> void:
	result[key(cell)] = {"cell": [cell.x, cell.y], "asset": "2d:" + asset, "direction": "SE"}

static func count_bits(value: int) -> int:
	var total: int = 0
	for bit in 4:
		if value & (1 << bit): total += 1
	return total

static func section_stamp(data: Dictionary,entry: Dictionary,network: Dictionary,heights: Dictionary) -> int:
	var cell:=Vector2i(entry["cell"][0],entry["cell"][1]); var neighbors: Array=[]
	for step in STEPS: neighbors.append(network.get(key(cell+step),{}))
	var terrain=preload("res://scripts/builder/terrain_plan.gd"); var config: Dictionary=terrain.settings(data); var samples: Array=[]
	if config["enabled"]:
		var first:=Vector2i(cell*4)-Vector2i(2,2)
		for x in range(first.x,first.x+5):
			for z in range(first.y,first.y+5): samples.append(heights.get(terrain.key(Vector2i(x,z)),{}).get("height",0))
	return hash([entry,neighbors,config["enabled"],config["bounds"] if config["enabled"] else [],samples])
static func update_3d(root: Node3D,data: Dictionary) -> Node3D:
	if not is_instance_valid(root): root=Node3D.new(); root.name="SmartRoads"
	var network: Dictionary=lookup(data); var terrain=preload("res://scripts/builder/terrain_plan.gd"); var heights: Dictionary=terrain.lookup(data) if terrain.settings(data)["enabled"] else {}; var changed: Dictionary={}; var existing: Dictionary={}
	for section in root.get_children(): existing[str(section.get_meta("road_cell",""))]=section
	for id in existing:
		if not network.has(id): existing[id].free()
	for id in network:
		var stamp: int=section_stamp(data,network[id],network,heights)
		if is_instance_valid(existing.get(id)) and existing[id].get_meta("road_signature",-1)==stamp: continue
		if is_instance_valid(existing.get(id)): existing[id].free()
		changed[id]=true
	if not changed.is_empty():
		var rebuilt: Node3D=make_3d(data,changed)
		for section in rebuilt.get_children(): rebuilt.remove_child(section); root.add_child(section)
		rebuilt.free()
	root.set_meta("last_rebuilt",changed.size()); return root
static func make_3d(data: Dictionary,only: Dictionary={}) -> Node3D:
	var root := Node3D.new()
	root.name = "SmartRoads"
	var network: Dictionary = lookup(data)
	var surfaces: Dictionary = {}
	for style in Settings.STYLES: surfaces[style] = material(Settings.COLORS[style])
	var pavement := material(Color("a5aaa9"))
	var paint_material := material(Color("eee5bd"))
	var cycle_marking := material(Color("75c8aa"))
	var terrain=preload("res://scripts/builder/terrain_plan.gd"); var sculpted: bool=terrain.settings(data)["enabled"]; var heights: Dictionary=terrain.lookup(data) if sculpted else {}
	for entry in network.values():
		var cell := Vector2i(entry["cell"][0], entry["cell"][1])
		if not only.is_empty() and not only.has(key(cell)): continue
		var links: int = mask(cell, network)
		var half: float = Settings.half_width(entry)
		var outer: float = Settings.outer_half(entry)
		var color: Color = Settings.COLORS[entry.get("style", "asphalt")]
		var node := StaticBody3D.new()
		node.name = "Road_%d_%d" % [cell.x, cell.y]
		node.position = Vector3(cell.x * 8, 0, cell.y * 8)
		node.collision_layer = 2
		node.set_meta("road_profile", Settings.profile(entry))
		node.set_meta("road_cell",key(cell)); node.set_meta("road_signature",section_stamp(data,entry,network,heights))
		root.add_child(node)
		if entry.get("sidewalks", true):
			var x_min: float = -half if links & 4 else -outer
			var x_max: float = half if links & 1 else outer
			var z_min: float = -half if links & 8 else -outer
			var z_max: float = half if links & 2 else outer
			box(node, Vector3(x_max - x_min, 0.12, z_max - z_min), Vector3((x_min + x_max) * 0.5, 0.01, (z_min + z_max) * 0.5), pavement)
		box(node, Vector3(half * 2, 0.04, half * 2), Vector3(0, 0.09, 0), surfaces[entry.get("style", "asphalt")])
		for direction in STEPS:
			var other: Dictionary = network.get(key(cell + direction), {})
			if other.is_empty(): continue
			var end_half: float = (half + Settings.half_width(other)) * 0.5
			var end_outer: float = (outer + Settings.outer_half(other)) * 0.5
			if entry.get("sidewalks", true) or other.get("sidewalks", true):
				ribbon(node, direction, minf(half, 3.9), outer, 4, end_outer, 0.07, Color("a5aaa9"), Color("a5aaa9"))
			ribbon(node, direction, half, half, 4, end_half, 0.11, color, color.lerp(Settings.COLORS[other.get("style", "asphalt")], 0.5))
		var shape := CollisionShape3D.new()
		var slab := BoxShape3D.new()
		slab.size = Vector3(8, 0.14, 8)
		shape.shape = slab
		shape.position.y = 0.04
		node.add_child(shape)
		if entry.get("style", "asphalt") == "asphalt":
			if links in [1, 4, 5, 0]: box(node, Vector3(2.2, 0.012, 0.10), Vector3(0, 0.117, 0), paint_material)
			elif links in [2, 8, 10]: box(node, Vector3(0.10, 0.012, 2.2), Vector3(0, 0.117, 0), paint_material)
		if entry.get("cycle_access","none") != "none":
			for direction in STEPS:
				if network.get(key(cell+direction),{}).get("cycle_access","none") == "none": continue
				var along := Vector3(direction.x,0,direction.y)
				var length: float = 3.6 if entry["cycle_access"] == "cycle" else 2.15
				box(node,Vector3(.18+absf(along.x)*length,.014,.18+absf(along.z)*length),along*length*.5+Vector3.UP*.132,cycle_marking)
		if entry.get("crossing", false) or count_bits(links) >= 3:
			var count: int = 3 if half > 1 else 1
			for stripe in range(-count, count + 1): box(node, Vector3(0.35, 0.014, minf(1.6, half)), Vector3(stripe * half * 0.23, 0.125, half * 0.6), paint_material)
		if sculpted: preload("res://scripts/builder/terrain_roads_3d.gd").deform(node,data,heights)
	return root

static var ribbon_material: StandardMaterial3D

static func ribbon(parent: Node3D, direction: Vector2i, start: float, start_half: float, finish: float, finish_half: float, height: float, first_color: Color, last_color: Color) -> void:
	var axis := Vector3(direction.x, 0, direction.y)
	var normal := Vector3(-direction.y, 0, direction.x)
	var points: Array[Vector3] = [axis * start + normal * start_half, axis * finish + normal * finish_half, axis * finish - normal * finish_half, axis * start - normal * start_half]
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in [0, 2, 1, 0, 3, 2]:
		mesh.set_normal(Vector3.UP)
		mesh.set_color(first_color if index in [0, 3] else last_color)
		mesh.add_vertex(points[index] + Vector3.UP * height)
	var instance := MeshInstance3D.new()
	instance.name = "RoadTransition" if height > 0.1 else "SidewalkTransition"
	instance.mesh = mesh.commit()
	if not ribbon_material:
		ribbon_material = material(Color.WHITE)
		ribbon_material.vertex_color_use_as_albedo = true
		ribbon_material.vertex_color_is_srgb = true
		ribbon_material.cull_mode = BaseMaterial3D.CULL_BACK
	instance.material_override = ribbon_material
	parent.add_child(instance)

static func material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 1
	return result

static func box(parent: Node3D, size: Vector3, position: Vector3, surface: Material) -> void:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.position = position
	mesh.material_override = surface
	parent.add_child(mesh)

static var model_bounds: Dictionary = {}
static var pixel_segment_cache: Dictionary = {}

static func painted_pixel_segments(data: Dictionary) -> Array:
	var signature: int = hash(data.get("tiles", []))
	if pixel_segment_cache.has(signature): return pixel_segment_cache[signature]
	var surfaces: Dictionary = {}
	var markings: Dictionary = {"x": {}, "y": {}}
	for tile in data.get("tiles", []):
		var asset: String = tile["asset"]
		var cell := Vector2i(tile["cell"][0], tile["cell"][1])
		if asset.begins_with("2d:Asphalt") or asset.begins_with("2d:Road_") or asset.begins_with("2d:Crosswalk"):
			surfaces[key(cell)] = true
		if asset not in ["2d:Road_Center_Dash_X", "2d:Road_Center_Dash_Y"]: continue
		var degrees_value: float = preload("res://scripts/iso_tile_rotation.gd").degrees(tile.get("direction", "SE"))
		if not is_zero_approx(fposmod(degrees_value, 90)): continue
		var horizontal: bool = asset.ends_with("_X")
		if posmod(roundi(degrees_value / 90), 2) == 1: horizontal = not horizontal
		var axis: String = "x" if horizontal else "y"
		var normal: int = cell.y if horizontal else cell.x
		if not markings[axis].has(normal): markings[axis][normal] = []
		markings[axis][normal].append(cell)
	var result: Array = []
	for axis in ["x", "y"]:
		var normals: Array = markings[axis].keys()
		normals.sort()
		var groups: Array = []
		for normal in normals:
			if groups.is_empty() or normal > groups.back().back() + 1: groups.append([])
			groups.back().append(normal)
		for group in groups:
			var first: float = INF
			var last: float = -INF
			for normal in group:
				for cell in markings[axis][normal]:
					var along: float = cell.x if axis == "x" else cell.y
					first = minf(first, along)
					last = maxf(last, along + 1)
			var middle: int = floori((first + last) * 0.5)
			var low: int = group[0]
			var high: int = group.back()
			for step in 8:
				var cell := Vector2i(middle, low - 1) if axis == "x" else Vector2i(low - 1, middle)
				if not surfaces.has(key(cell)): break
				low -= 1
			for step in 8:
				var cell := Vector2i(middle, high + 1) if axis == "x" else Vector2i(high + 1, middle)
				if not surfaces.has(key(cell)): break
				high += 1
			if high - low < 1: continue
			var first_mark: float = group[0] + 0.5
			var last_mark: float = group.back() + 0.5
			var center: float = (first_mark + last_mark) * 0.5
			# The double marking is excluded from each drivable lane. Image
			# origins are not lane centers: use the middle of the visible asphalt.
			var lower_lane: float = (low + first_mark) * 0.5
			var upper_lane: float = (high + 1 + last_mark) * 0.5
			var a := Vector2(first, center) if axis == "x" else Vector2(center, first)
			var b := Vector2(last, center) if axis == "x" else Vector2(center, last)
			# +normal points toward increasing y for x roads, decreasing x for y roads.
			result.append([a, b, upper_lane - center if axis == "x" else center - lower_lane, 0.0, center - lower_lane if axis == "x" else upper_lane - center])
	if pixel_segment_cache.size() >= 8: pixel_segment_cache.erase(pixel_segment_cache.keys()[0])
	pixel_segment_cache[signature] = result
	return result

static func bounds_for(library: RefCounted, asset: String) -> AABB:
	if not model_bounds.has(asset):
		var node: Node3D = load(library.assets[asset]["path"]).instantiate()
		model_bounds[asset] = preload("res://scripts/model_bounds.gd").get_bounds(node)
		node.free()
	return model_bounds[asset]

static func center_offset(library: RefCounted, asset: String, direction: String, size: float, mode: String) -> Vector2:
	if asset.begins_with("3d:"):
		var center: Vector3 = Basis(Vector3.UP, deg_to_rad(float(direction))) * bounds_for(library, asset).get_center() * size
		return Vector2(center.x, center.z)
	if mode == "3d": return Vector2.ZERO
	var view: Dictionary = library.assets[asset]["data"].get("directions", {}).get(direction, {})
	var footprint: Array = view.get("footprint", [1, 1])
	return Vector2(footprint[0], footprint[1]) * size * 0.5

static func lane(data: Dictionary, values: Array, direction: String, library: RefCounted, asset: String, size: float = 1.0) -> Dictionary:
	var unchanged: Dictionary = {"position": values, "direction": direction, "snapped": false}
	if not preload("res://scripts/builder/asset_behavior.gd").for_asset(asset, library).get("vehicle", false): return unchanged
	var mode: String = data["mode"]
	var p := Vector2(values[0], values[2] if mode == "3d" else values[1])
	if mode == "2d": p = Vector2((p.x / 16.0 + p.y / 8.0) / 2, (p.y / 8.0 - p.x / 16.0) / 2)
	p += center_offset(library, asset, direction, size, mode)
	var segments: Array = []
	var network: Dictionary = lookup(data)
	var spacing: float = 8 if mode == "3d" else 4
	# Pixel tiles are anchored at a corner; their road center is half a tile farther in.
	var tile_center := Vector2(0.5, 0.5) if mode == "2d" else Vector2.ZERO
	for entry in network.values():
		var cell := Vector2i(entry["cell"][0], entry["cell"][1])
		for step in [Vector2i.RIGHT, Vector2i.DOWN]:
			if network.has(key(cell + step)):
				var other: Dictionary = network[key(cell + step)]
				var factor: float = 0.5 if mode == "3d" else 0.25
				var first_offset: float = Settings.half_width(entry) * factor
				var last_offset: float = Settings.half_width(other) * factor
				segments.append([Vector2(cell) * spacing + tile_center, Vector2(cell + step) * spacing + tile_center, first_offset, 0.12, first_offset, last_offset,true])
	for item in data["objects"]:
		if item["asset"].ends_with("/Road_Straight"):
			var road_position: Array = item["position"]
			var center := Vector2(road_position[0], road_position[2] if mode == "3d" else road_position[1])
			if mode == "2d": center = Vector2((center.x / 16 + center.y / 8) / 2, (center.y / 8 - center.x / 16) / 2)
			var axis := Vector2(sin(deg_to_rad(float(item["direction"]))), cos(deg_to_rad(float(item["direction"]))))
			var road_scale: float = item["scale"]
			segments.append([center - axis * 4 * road_scale, center + axis * 4 * road_scale, 1.5 * road_scale, road_position[1] + 0.1 if mode == "3d" else 0.0])
	if mode == "2d": segments.append_array(painted_pixel_segments(data))
	var best: float = INF
	var snapped := p
	var angle: String = direction
	var authored: Dictionary = library.assets[asset].get("data", {}).get("view_yaws", {})
	var surface_height: float = values[1]
	for segment in segments:
		var a: Vector2 = segment[0]
		var b: Vector2 = segment[1]
		var axis: Vector2 = (b - a).normalized()
		var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(p, a, b)
		var distance: float = p.distance_to(nearest)
		if distance >= best or distance > (5.0 if mode == "3d" else 3.5): continue
		best = distance
		var normal := Vector2(-axis.y, axis.x)
		var side: float = 1.0 if (p - nearest).dot(normal) >= 0 else -1.0
		if absf((p - nearest).dot(normal)) < 0.05:
			if asset.begins_with("3d:"): side = 1.0 if Vector2(sin(deg_to_rad(float(direction))), cos(deg_to_rad(float(direction)))).dot(axis) >= 0 else -1.0
			elif authored.has(direction): side = 1.0 if Vector2(sin(deg_to_rad(float(authored[direction]))), cos(deg_to_rad(float(authored[direction])))).dot(axis) >= 0 else -1.0
			else: side = 1.0 if direction in ["SE", "SW"] else -1.0
		var lane_offset: float = segment[4] if side < 0 and segment.size() > 4 else segment[2]
		if segment.size() > 5: lane_offset = lerpf(segment[2], segment[5], clampf((nearest - a).dot(b - a) / (b - a).length_squared(), 0, 1))
		snapped = nearest + normal * side * lane_offset
		var yaw: float = wrapf(rad_to_deg(atan2(axis.x, axis.y)) + (0 if side > 0 else 180), 0, 360)
		if asset.begins_with("3d:"): angle = preload("res://scripts/builder/rotation.gd").angle_text(yaw)
		else:
			# Sprite views choose the closest supplied heading.
			var views: Array = ["NE", "SE", "SW", "NW"]
			angle = views[posmod(roundi(yaw / 90), 4)]
			if mode == "2d" and absf(axis.x) < 0.5: angle = "NE" if side < 0 else "SW"
			if not library.directions(asset).has(angle): angle = direction
			if not authored.is_empty():
				var closest: float = INF
				for view in authored:
					var difference: float = absf(angle_difference(deg_to_rad(yaw), deg_to_rad(float(authored[view]))))
					if difference < closest: closest = difference; angle = view
		surface_height = maxf(values[1], segment[3])
		if mode=="3d" and segment.size()>6 and segment[6] and preload("res://scripts/builder/terrain_plan.gd").settings(data)["enabled"]: surface_height=preload("res://scripts/builder/terrain_plan.gd").sample(data,snapped)["height"]+.12
	if best == INF: return unchanged
	var origin: Vector2 = snapped - center_offset(library, asset, angle, size, mode)
	var result: Array
	if mode == "3d":
		var bottom: float = bounds_for(library, asset).position.y * size if asset.begins_with("3d:") else 0.0
		result = [origin.x, surface_height - bottom, origin.y]
	else: result = [(origin.x - origin.y) * 16, (origin.x + origin.y) * 8, values[2]]
	return {"position": result, "direction": angle, "snapped": true}
