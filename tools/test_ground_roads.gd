extends SceneTree

const Cells = preload("res://scripts/builder/brush_cells.gd")
const Fit = preload("res://scripts/builder/grid_fit.gd")
const Roads = preload("res://scripts/builder/roads.gd")
const Document = preload("res://scripts/builder/document.gd")
const Exporter = preload("res://scripts/builder/exporter.gd")
var checks: int = 0
var failures: int = 0
var studio: Control

func _init() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func blank() -> void:
	studio.clear_placement()
	studio.current().data = {"title": "Ground test", "mode": studio.mode, "objects": [], "tiles": [], "night": false}
	studio.current().undo_history.clear()
	studio.current().redo_history.clear()
	studio.worlds[studio.mode].apply(studio.current().data)
	studio.ground_brush.restore({})
	studio.surface_input.button_pressed = false
	studio.repeat_input.button_pressed = true
	studio.brush_input.value = 1

func point(cell: Vector2i) -> Vector2:
	var brush: RefCounted = studio.ground_brush
	var coordinate: Vector2 = (Vector2(cell) + Vector2.ONE * 0.5) * brush.step
	if studio.mode == "2d":
		var pixel: Vector2 = Fit.pixels(coordinate)
		return studio.overlay_position([pixel.x, pixel.y, brush.elevation])
	return studio.worlds["3d"].camera.unproject_position(Vector3(coordinate.x, brush.elevation, coordinate.y))

func choose(asset: String, operation: int) -> void:
	studio.select_asset(asset)
	studio.ground_brush.operation.select(operation)
	studio.ground_brush.configure_grid(studio.canvas.size / 2)

func input_event(at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	studio._canvas_input(event)

func gesture(a: Vector2i, b: Vector2i) -> void:
	input_event(point(a), true)
	var motion := InputEventMouseMotion.new()
	motion.position = point(b)
	studio._canvas_input(motion)
	input_event(point(b), false)

func count(asset: String = "") -> int:
	var total: int = 0
	var items: Array = studio.current().data["tiles"] if studio.mode == "2d" and studio.ground_brush.native_tiles() else studio.current().data["objects"]
	for item in items:
		if asset.is_empty() or item["asset"] == asset: total += 1
	return total

func run() -> void:
	check(Cells.stamp(Vector2i.ZERO, 3).size() == 9, "Three-cell stamp is a 3x3 square")
	check(Cells.line(Vector2i(-4, -4), Vector2i(4, 4)).size() == 9, "Diagonal line includes both ends without gaps")
	check(Cells.line(Vector2i(4, 4), Vector2i(-4, -4)).size() == 9, "Line works in reverse")
	check(Cells.rectangle(Vector2i(3, 2), Vector2i(-2, -1)).size() == 24, "Reverse rectangle covers every cell")
	check(Cells.rectangle(Vector2i.ZERO, Vector2i(100000, 100000)).size() == Cells.LIMIT, "Huge fills stop at the cell limit")
	check(Cells.flood(Vector2i.ZERO, {}).is_empty(), "Flood fill never expands over empty space")
	studio = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	for i in 6: await process_frame
	for mode in ["2d", "3d"]:
		studio.switch_mode(mode)
		test_brush(mode)
		test_roads(mode)
	await test_ground_surface()
	if "--capture" in OS.get_cmdline_user_args(): await capture()
	studio.free()
	print("GROUND / ROADS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func test_brush(mode: String) -> void:
	for operation in range(3):
		blank()
		choose("2d:Grass", operation)
		var before: Dictionary = studio.current().data.duplicate(true)
		if operation == 0: studio.brush_input.value = 3
		var a := Vector2i(-2, 0) if operation == 0 else Vector2i(-3, -3)
		var b := Vector2i(4, 0) if operation == 0 else Vector2i(3, 3)
		if operation == 2: a = Vector2i(3, 2); b = Vector2i(-2, -1)
		input_event(point(a), true)
		check(operation == 0 or count() == 0, "Line and rectangle wait for release: " + mode + "/" + str(operation))
		var motion := InputEventMouseMotion.new()
		motion.position = point(b)
		studio._canvas_input(motion)
		if operation != 0:
			check(count() == 0 and studio.ground_brush.preview_polygon(point(b)).size() >= 4, "Pending fill has a preview and no committed cells: " + mode)
			if operation == 2:
				var outline: PackedVector2Array = studio.ground_brush.preview_polygon(point(b))
				for cell in Cells.rectangle(a, b): check(Geometry2D.is_point_in_polygon(point(cell), outline), "Rectangle preview encloses each pending cell: " + mode + "/" + str(cell))
		input_event(point(b), false)
		var expected: int = [27, 7, 24][operation]
		check(count() == expected, "Brush operation paints every intended cell exactly once: " + mode + "/" + str(operation))
		var painted: Dictionary = studio.current().data.duplicate(true)
		check(studio.current().undo() and studio.current().data == before, "Ground gesture is one undo step: " + mode)
		check(studio.current().redo() and studio.current().data == painted, "Ground gesture supports exact redo: " + mode)
		studio.changed()
		check(Document.valid(studio.current().data, mode, studio.library), "Ground operation creates valid saved data: " + mode)
	blank()
	choose("2d:Grass", 2)
	gesture(Vector2i.ZERO, Vector2i(2, 2))
	gesture(Vector2i(8, 8), Vector2i(8, 8))
	choose("2d:Dirt", 3)
	gesture(Vector2i.ZERO, Vector2i.ZERO)
	check(count("2d:Dirt") == 9 and count("2d:Grass") == 1, "Flood replaces only the connected matching region: " + mode)
	var previous: int = count()
	gesture(Vector2i(20, 20), Vector2i(20, 20))
	check(count() == previous, "Flood on empty space preserves scene: " + mode)
	blank()
	choose("2d:Grass", 2)
	gesture(Vector2i.ZERO, Vector2i(1, 1))
	choose("2d:Dirt", 0)
	gesture(Vector2i.ONE, Vector2i.ONE)
	choose("2d:Brick_Pavers", 2)
	studio.ground_brush.replace_only.button_pressed = true
	gesture(Vector2i.ZERO, Vector2i(3, 3))
	check(count("2d:Brick_Pavers") == 3 and count("2d:Dirt") == 1 and count() == 4, "Replace-only skips empty cells and other asset types: " + mode)
	var protected: Dictionary = studio.current().data.duplicate(true)
	studio.current().data["layers"] = {"Ground": {"locked": true}}
	gesture(Vector2i.ZERO, Vector2i(3, 3))
	check(studio.current().data["objects"] == protected["objects"] and studio.current().data["tiles"] == protected["tiles"], "Ground layer lock prevents brush edits: " + mode)
	studio.current().data.erase("layers")
	if mode == "3d":
		blank()
		choose("2d:Grass", 1)
		gesture(Vector2i.ZERO, Vector2i(2, 0))
		studio.current().data["objects"][1]["locked"] = true
		choose("2d:Dirt", 3)
		gesture(Vector2i.ZERO, Vector2i.ZERO)
		check(count("2d:Dirt") == 1 and count("2d:Grass") == 2, "Protected 3D ground cells block flood propagation")
		check(studio.worlds["3d"].instances.size() == 3, "Painted 3D cells remain selectable scene objects")
		blank()
		choose("2d:Grass", 2)
		studio.height_input.value = 2
		studio.ground_brush.configure_grid(studio.canvas.size / 2)
		gesture(Vector2i.ZERO, Vector2i.ONE)
		studio.height_input.value = 0
		studio.ground_brush.configure_grid(studio.canvas.size / 2)
		gesture(Vector2i.ZERO, Vector2i.ONE)
		check(count() == 8, "Ground painting keeps different elevation planes separate")
		choose("2d:Dirt", 3)
		gesture(Vector2i.ZERO, Vector2i.ZERO)
		check(count("2d:Dirt") == 4 and count("2d:Grass") == 4, "Flood affects only the selected elevation plane")
		var path: String = "user://ground_brush_export.tscn"
		check(Exporter.save_scene(studio.worlds[mode], studio.current().data, studio.library, path) == OK, "3D painted ground exports")
		var exported: Node = load(path).instantiate()
		root.add_child(exported)
		check(exported.get_node("Objects").get_child_count() == 8, "Export contains every painted ground object")
		exported.free()
		DirAccess.remove_absolute(path)
	studio.ground_brush.replace_only.button_pressed = false
	choose("2d:Grass", 0)
	studio.repeat_input.button_pressed = false
	gesture(Vector2i(30, 30), Vector2i(30, 30))
	check(studio.asset_id.is_empty() and studio.tool == "select", "Ground respects single-use placement: " + mode)
	# Imported surfaces use the same brush operations, with their footprint as cell spacing.
	for id in studio.library.assets:
		if studio.library.is_ground_tile(id) and studio.library.assets[id]["data"].has("source_pack"):
			blank()
			choose(id, 0)
			studio.brush_input.value = 3
			gesture(Vector2i.ZERO, Vector2i.ZERO)
			check(studio.current().data["objects"].size() == 9, "Imported ground paints a full 3x3 stamp: " + mode)
			check(Document.valid(studio.current().data, mode, studio.library), "Imported ground brush saves valid object data: " + mode)
			break
	var project_path: String = "user://painted_ground_roundtrip.isocity.json"
	var painted_data: Dictionary = studio.current().data.duplicate(true)
	check(studio.write_project(project_path), "Painted ground saves to a project: " + mode)
	check(studio.load_project(project_path) and studio.current().data == painted_data, "Painted ground survives an exact project round trip: " + mode)
	DirAccess.remove_absolute(project_path)

func test_roads(mode: String) -> void:
	blank()
	var data: Dictionary = studio.current().data
	data["tiles"] = [{"cell": [0, 0], "asset": "2d:Grass", "direction": "SE"}] if mode == "2d" else []
	var base: Array = data["tiles"].duplicate(true)
	Roads.paint(data, Vector2i.ZERO, Vector2i.ZERO, false, {"width": 6, "sidewalks": true, "style": "asphalt"})
	Roads.paint(data, Vector2i.RIGHT, Vector2i.RIGHT, false, {"width": 2, "sidewalks": false, "style": "brick"})
	check(Document.valid(data, mode, studio.library), "Mixed road profiles validate: " + mode)
	check(Roads.mask(Vector2i.ZERO, Roads.lookup(data)) == 1 and Roads.mask(Vector2i.RIGHT, Roads.lookup(data)) == 4, "Different road profiles connect: " + mode)
	var tiles: Array = Roads.tiles(data)
	check(tiles.any(func(tile: Dictionary) -> bool: return tile["asset"] == "2d:Brick_Pavers"), "2D roads use the chosen surface style")
	check(data["tiles"] == base, "Road rendering preserves original ground: " + mode)
	var invalid: Dictionary = data.duplicate(true)
	invalid["roads"][0]["width"] = 4
	check(not Document.valid(invalid, mode, studio.library), "Unsupported road widths are rejected: " + mode)
	invalid = data.duplicate(true)
	invalid["roads"][0]["sidewalks"] = "yes"
	check(not Document.valid(invalid, mode, studio.library), "Invalid sidewalk data is rejected: " + mode)
	var legacy: Dictionary = data.duplicate(true)
	legacy["roads"] = [{"cell": [0, 0], "crossing": false}]
	check(Document.valid(legacy, mode, studio.library), "Legacy roads still validate: " + mode)
	studio.changed()
	if mode == "3d":
		var root_node: Node3D = studio.worlds[mode].road_node
		var boundaries: Array = []
		var colors: Array[Color] = []
		for section in root_node.get_children():
			var found: Array[float] = []
			for child in section.get_children():
				if not child is MeshInstance3D or not child.mesh is ArrayMesh: continue
				var vertices: PackedVector3Array = child.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = child.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
				check((vertices[1] - vertices[0]).cross(vertices[2] - vertices[0]).y < 0 and normals[0].y > 0.99, "Transition faces upward with Godot's clockwise front-face convention")
				var vertex_colors: PackedColorArray = child.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
				for i in vertices.size():
					var vertex: Vector3 = vertices[i]
					var world: Vector3 = section.transform * vertex
					if is_equal_approx(world.x, 4) and is_equal_approx(world.y, 0.11):
						found.append(world.z)
						colors.append(vertex_colors[i])
			boundaries.append(found)
		check(boundaries.size() == 2 and boundaries.all(func(values: Array) -> bool: return values.has(2.0) and values.has(-2.0)), "Both 3D road ends meet at identical transition widths")
		var expected_color: Color = preload("res://scripts/builder/road_settings.gd").COLORS["asphalt"].lerp(preload("res://scripts/builder/road_settings.gd").COLORS["brick"], 0.5)
		check(not colors.is_empty() and colors.all(func(color: Color) -> bool: return color.is_equal_approx(colors[0]) and absf(color.r - expected_color.r) <= 1.0 / 255 and absf(color.g - expected_color.g) <= 1.0 / 255 and absf(color.b - expected_color.b) <= 1.0 / 255), "Different road materials blend to identical colors at their shared edge")
		for x in [0.0, 4.0, 8.0]:
			var lane: Dictionary = Roads.lane(data, [x, 0, 1], "SE", studio.library, "2d:Sedan_Red")
			check(lane.get("snapped", false) and is_equal_approx(lane["position"][2], lerpf(1.5, 0.5, x / 8)), "Lane centers follow changing road width: " + str(x))
		var export_path: String = "user://road_profiles_export.tscn"
		check(Exporter.save_scene(studio.worlds[mode], data, studio.library, export_path) == OK, "Road transitions export as a runnable scene")
		var scene: Node = load(export_path).instantiate()
		root.add_child(scene)
		check(scene.get_node("SmartRoads").get_child_count() == 2, "Export retains both road sections and their transition meshes")
		scene.free()
		DirAccess.remove_absolute(export_path)
	var before: Dictionary = data.duplicate(true)
	studio.current().checkpoint()
	Roads.paint(data, Vector2i.ZERO, Vector2i.RIGHT, false, {"width": 2, "sidewalks": false, "style": "gravel"})
	studio.changed()
	check(data["roads"].all(func(road: Dictionary) -> bool: return road["width"] == 2 and road["style"] == "gravel" and not road["sidewalks"]), "Drawing over roads applies all selected settings: " + mode)
	check(studio.current().undo() and studio.current().data == before, "Resurfacing is one exact undo step: " + mode)
	data = studio.current().data
	Roads.paint(data, Vector2i.ZERO, Vector2i.RIGHT, true)
	check(data["roads"].is_empty() and data["tiles"] == base, "Removing roads restores underlying ground: " + mode)
	studio.road_settings.width.select(0)
	studio.road_settings.style.select(2)
	studio.road_settings.sidewalks.button_pressed = false
	studio.ground_brush.operation.select(2)
	studio.capture_workspace()
	var path: String = "user://ground_road_project.isocity.json"
	check(studio.write_project(path), "Save brush and road workspace settings: " + mode)
	studio.road_settings.restore({})
	studio.ground_brush.restore({})
	var loaded: bool = studio.load_project(path)
	check(loaded and studio.road_settings.settings() == {"width": 2, "sidewalks": false, "style": "gravel"} and studio.ground_brush.operation.selected == 2, "Reload brush and road workspace settings: " + mode)
	DirAccess.remove_absolute(path)
	studio.set_tool("road")
	var press: Vector2 = studio.overlay_position([0, 0, 0])
	var release: Vector2 = studio.overlay_position([64, 32, 0] if mode == "2d" else [8, 0, 0])
	input_event(press, true)
	var motion := InputEventMouseMotion.new()
	motion.position = release
	studio._canvas_input(motion)
	input_event(release, false)
	check(not studio.current().data["roads"].is_empty() and studio.current().data["roads"].all(func(road: Dictionary) -> bool: return road.get("width") == 2 and road.get("style") == "gravel" and road.get("sidewalks") == false), "Canvas road gesture uses the current UI settings: " + mode)

func test_ground_surface() -> void:
	studio.switch_mode("3d")
	blank()
	choose("2d:Grass", 0)
	studio.surface_input.button_pressed = true
	await physics_frame
	await physics_frame
	gesture(Vector2i.ZERO, Vector2i.ZERO)
	await physics_frame
	await physics_frame
	choose("2d:Dirt", 0)
	gesture(Vector2i.ZERO, Vector2i.ZERO)
	check(count() == 1 and count("2d:Dirt") == 1, "Surface brushing replaces existing ground without stacking")
	check(is_zero_approx(studio.current().data["objects"][0]["position"][1]), "Ground height remains on foundation after repainting")

func capture() -> void:
	studio.switch_mode("3d")
	blank()
	choose("2d:Grass", 2)
	gesture(Vector2i(-8, -5), Vector2i(15, 6))
	var data: Dictionary = studio.current().data
	Roads.paint(data, Vector2i(-1, 0), Vector2i.ZERO, false, {"width": 6, "sidewalks": true, "style": "asphalt"})
	Roads.paint(data, Vector2i.RIGHT, Vector2i.RIGHT, false, {"width": 2, "sidewalks": false, "style": "brick"})
	studio.changed()
	studio.clear_placement()
	studio.worlds["3d"].target = Vector3(2, 0, 0)
	studio.worlds["3d"].distance = 30
	studio.worlds["3d"].update_camera()
	studio.road_settings.panel.get_parent().current_tab = studio.road_settings.panel.get_index()
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://output/editor_roads_brush_3d.png")
	choose("2d:Dirt", 2)
	studio.ground_brush.panel.get_parent().current_tab = studio.ground_brush.panel.get_index()
	var first: Vector2 = point(Vector2i(-5, -4))
	var last_point: Vector2 = point(Vector2i(4, -1))
	input_event(first, true)
	var motion := InputEventMouseMotion.new()
	motion.position = last_point
	studio._canvas_input(motion)
	studio.set_process(false)
	studio.update_overlay(true)
	studio.overlay.brush_polygon = studio.ground_brush.preview_polygon(last_point)
	studio.overlay.caption_position = last_point + Vector2(18, 22)
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://output/editor_ground_rectangle_3d.png")
	input_event(last_point, false)
