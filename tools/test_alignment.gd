extends SceneTree

const Templates = preload("res://scripts/builder/templates.gd")
const Roads = preload("res://scripts/builder/roads.gd")
const Rows = preload("res://scripts/builder/layout_alignment.gd")
const Bounds = preload("res://scripts/model_bounds.gd")
const Exporter = preload("res://scripts/builder/exporter.gd")
var checks: int = 0
var failures: int = 0
var studio: Control

func _init() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ", message)

func grid_point(point: Vector2) -> Vector2:
	return Vector2((point.x / 16 + point.y / 8) * 0.5, (point.y / 8 - point.x / 16) * 0.5)

func run() -> void:
	root.size = Vector2i(1480, 900)
	studio = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	for i in 5: await process_frame
	var building_a: String = ""
	var building_b: String = ""
	for id in studio.library.assets:
		var asset: Dictionary = studio.library.assets[id]
		var view: Dictionary = asset["data"].get("directions", {}).get("SE", {})
		if view.has("alignment_base"):
			var node: Node2D = load(asset["path"]).instantiate()
			root.add_child(node)
			var sprite: Sprite2D = node.get_node("Sprite2D")
			var base: Array = view["alignment_base"]
			var foot := Vector2i(view["footprint"][0], view["footprint"][1])
			var expected: Array[Vector2] = [IsoMath.tile_to_world(Vector2i(0, foot.y)), IsoMath.tile_to_world(foot), IsoMath.tile_to_world(Vector2i(foot.x, 0))]
			for index in 3:
				var actual: Vector2 = sprite.to_global(Vector2(base[index][0], base[index][1]) - node.origin_offset)
				check(actual.distance_to(node.to_global(expected[index])) < 0.002, "Measured solid base lands on the rendered grid footprint: " + id + "/" + str(index))
			var sample := Vector2(100, 120)
			check(sprite.to_local(sprite.to_global(sample)).distance_to(sample) < 0.001, "Pixel selection remains reversible under the calibrated sprite transform: " + id)
			node.free()
		for source in asset["data"].get("source_files", []):
			if source.ends_with("Brutalist Building s2B noshadow stackable.png"): building_a = id
			if source.ends_with("Brutalist Building s2C color b.png"): building_b = id
	check(not building_a.is_empty() and not building_b.is_empty(), "Both visible Brutalist variants have stable catalog entries")
	studio.documents["2d"].data = Templates.make("2d", "city")
	studio.switch_mode("2d")
	var positions: Array = [[-288, -16, 0], [-240, -8, 0], [-192, 16, 0], [-144, 40, 0], [-96, 64, 0], [-48, 88, 0], [-16, 120, 0]]
	var buildings: Array = []
	for index in positions.size(): buildings.append(studio.current().add(building_a if index in [0, 6] else building_b, positions[index], "SE", 0.25))
	studio.changed()
	studio.selected_uid = ""
	studio.selected_uids.clear()
	studio.align_buildings()
	check(buildings[0]["position"] == [-288.0, -32.0, 0.0] and buildings[6]["position"] == [0.0, 112.0, 0.0], "Mixed shadow/no-shadow variants align to the same row")
	for index in range(1, buildings.size()):
		var a: Vector2 = grid_point(Vector2(buildings[index - 1]["position"][0], buildings[index - 1]["position"][1]))
		var b: Vector2 = grid_point(Vector2(buildings[index]["position"][0], buildings[index]["position"][1]))
		check(b.is_equal_approx(a + Vector2(3, 0)), "Adjoining building footprints use a consistent three-cell pitch")
	studio._command("undo", null)
	check(studio.current().object(buildings[0]["uid"])["position"] == [-288.0, -16.0, 0.0], "Building alignment is undoable")
	studio._command("redo", null)
	check(studio.current().object(buildings[0]["uid"])["position"] == [-288.0, -32.0, 0.0], "Building alignment is redoable")
	var car_a: Dictionary = studio.current().add("3d:HanX_GasStation/Car_Coupe", [80, 72, 0], "90", 0.5)
	var car_b: Dictionary = studio.current().add("3d:HanX_GasStation/Car_Coupe", [192, 96, 0], "270", 0.5)
	studio.changed()
	studio.selected_uid = car_a["uid"]
	studio.selected_uids.assign([car_a["uid"], car_b["uid"]])
	studio.align_cars()
	var source_mark: Image = load("res://assets/pixel_isometric/Sprites/City_Ground/Road_Center_Dash_X.png").get_image()
	var low_mark: float = INF
	var high_mark: float = -INF
	for y in source_mark.get_height():
		for x in source_mark.get_width():
			var pixel: Color = source_mark.get_pixel(x, y)
			if minf(pixel.r, minf(pixel.g, pixel.b)) < 0.7 or pixel.a < 0.5: continue
			var normal: float = grid_point(Vector2(x - 16, y)).y
			low_mark = minf(low_mark, normal)
			high_mark = maxf(high_mark, normal)
	check(low_mark > 0.4 and high_mark < 0.55, "Test reads the real white road marking pixels")
	for record in [car_a, car_b]:
		var instance: Node = studio.worlds["2d"].instances[record["uid"]]
		var bounds: AABB = instance.model.transform * Bounds.get_bounds(instance.model)
		var point: Vector3 = bounds.get_center()
		point.y = bounds.position.y
		var sprite: Sprite2D = instance.get_node("Sprite2D")
		var projected: Vector2 = sprite.to_global(sprite.get_rect().position + instance.camera.unproject_position(point))
		var center: float = grid_point(projected).y
		var half_width: float = bounds.size.z * record["scale"] * 0.5
		var lower: float = -1 if record["direction"] == "270" else high_mark
		var upper: float = low_mark if record["direction"] == "270" else 2
		var left_clearance: float = center - half_width - lower
		var right_clearance: float = upper - center - half_width
		check(left_clearance > 0.15 and right_clearance > 0.15, "Rendered wheel footprint stays inside the actual lane with clearance")
		check(absf(left_clearance - right_clearance) < 0.07, "Rendered car is balanced between the painted marking and the road edge")
	# A wider road must derive a different center, rather than reusing the old constants.
	var wider: Dictionary = Templates.make("2d", "city")
	for x in range(-14, 14):
		for tile in wider["tiles"]:
			if tile["cell"] == [x, 1]: tile["asset"] = "2d:Road_Center_Dash_X"
			if tile["cell"] == [x, 2]: tile["asset"] = "2d:Asphalt"
	var wide_lane: Dictionary = Roads.lane(wider, [96.0, 64.0, 0.0], "90", studio.library, car_a["asset"], 0.5)
	check(wide_lane["position"] == [76.0, 74.0, 0.0], "Four-tile double-marked roads derive their own lane center")
	# Exercise the actual selection-motion handler, rather than only Roads.lane.
	studio.selected_uid = car_a["uid"]
	studio.selected_uids.assign([car_a["uid"]])
	studio.tool = "select"
	studio.stroke = true
	studio.moved_selection = false
	studio.marquee_active = false
	studio.lanes_input.button_pressed = true
	studio.selection_press = studio.canvas.size * 0.5
	studio.drag_origins = {car_a["uid"]: car_a["position"].duplicate()}
	var drag := InputEventMouseMotion.new()
	drag.position = studio.selection_press + Vector2(64, 40)
	studio._canvas_input(drag)
	var moved: Array = studio.current().object(car_a["uid"])["position"]
	check(is_equal_approx(grid_point(Vector2(moved[0], moved[1])).y, 1.25) and moved != [92.0, 66.0, 0.0], "Dragging a single car keeps it centered in the painted lane")
	studio.finish_edit(drag.position)
	studio._command("undo", null)
	check(studio.current().object(car_a["uid"])["position"] == [92.0, 66.0, 0.0], "Lane-snapped dragging remains one undoable edit")
	var directory: String = "res://output/alignment_test_" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	check(studio.write_project(directory + "/aligned.json") and studio.load_project(directory + "/aligned.json"), "Aligned layouts save and reopen")
	check(Exporter.save_scene(studio.worlds["2d"], studio.current().data, studio.library, directory + "/aligned.tscn") == OK, "Calibrated and aligned buildings export")
	var exported: Node = load(directory + "/aligned.tscn").instantiate()
	root.add_child(exported)
	await process_frame
	var exported_building: Node = exported.get_node("Objects").get_children().filter(func(node: Node): return node.get_meta("builder_uid", "") == buildings[1]["uid"])[0]
	check(exported_building.get_node("Sprite2D").transform != Transform2D.IDENTITY, "Export retains the corrected building projection")
	exported.free()
	studio.free()
	print("ALIGNMENT: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
