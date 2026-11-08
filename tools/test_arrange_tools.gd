extends SceneTree

const Fit = preload("res://scripts/builder/grid_fit.gd")
const Rotation = preload("res://scripts/builder/rotation.gd")
const Document = preload("res://scripts/builder/document.gd")
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

func vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])

func selected(items: Array) -> void:
	studio.selected_uids.clear()
	for item in items: studio.selected_uids.append(item["uid"])
	studio.selected_uid = studio.selected_uids[0] if not studio.selected_uids.is_empty() else ""
	studio.refresh_controls()

func run() -> void:
	studio = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	for i in 6: await process_frame
	for dimension in ["2d", "3d"]:
		studio.switch_mode(dimension)
		studio.documents[dimension].data = {"title": "Arrange test", "mode": dimension, "objects": [], "tiles": [], "night": false}
		studio.current().undo_history.clear()
		studio.current().redo_history.clear()
		studio.worlds[dimension].apply(studio.current().data)
		studio.lanes_input.button_pressed = false
		studio.surface_input.button_pressed = false
		test_anchors(dimension)
		test_alignment(dimension)
		test_pivots(dimension)
		check(Document.valid(studio.current().data, dimension, studio.library), "Arranged scene validates: " + dimension)
		studio.arrange_tools.snap_target.select(Fit.TARGETS.find("edge_max_x"))
		studio.arrange_tools.set_custom([11, 12, 13] if dimension == "2d" else [21, 22, 23])
		studio.capture_workspace()
	await test_surfaces()
	studio.switch_mode("2d")
	check(studio.arrange_tools.target() == "edge_max_x" and studio.arrange_tools.pivot([]) == Vector3(11, 12, 13), "Each world remembers its own arrangement settings")
	var path: String = "user://test_arrange_tools.isocity.json"
	check(studio.write_project(path), "Save arrangement workspace")
	studio.arrange_tools.set_custom([0, 0, 0])
	check(studio.load_project(path) and studio.arrange_tools.pivot([]) == Vector3(11, 12, 13), "Custom pivot survives project round trip")
	DirAccess.remove_absolute(path)
	if "--capture" in OS.get_cmdline_user_args():
		studio.documents["2d"].data = preload("res://scripts/builder/templates.gd").make("2d", "city")
		studio.worlds["2d"].apply(studio.current().data)
		studio.worlds["2d"].reset_camera()
		selected(studio.current().data["objects"].slice(0, 3))
		studio.arrange_tools.set_custom([32, 16, 0])
		studio.arrange_tools.panel.get_parent().current_tab = studio.arrange_tools.panel.get_index()
		for i in 5: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://output/editor_arrange.png")
		studio.arrange_tools.panel.scroll_vertical = 1000
		for i in 5: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://output/editor_arrange_spacing.png")
		studio.select_asset("2d:Coffee_Shop")
		studio.arrange_tools.panel.get_parent().current_tab = 0
		# Render the preview at a deterministic virtual pointer without moving the user's mouse.
		studio.set_process(false)
		var pointer: Vector2 = studio.canvas.size * Vector2(0.6, 0.6)
		var preview: Dictionary = studio.placement(pointer)
		studio.worlds["2d"].preview(studio.asset_id, preview["position"], preview["direction"], studio.scale_input.value, true)
		var pose: Dictionary = studio.placement_record()
		pose["position"] = preview["position"]
		pose["direction"] = preview["direction"]
		pose["scale"] = studio.scale_input.value
		preload("res://scripts/builder/asset_instance.gd").pose(studio.worlds["2d"].ghost, pose)
		studio.update_overlay(true)
		studio.overlay.caption_position = pointer + Vector2(18, 22)
		studio.overlay.snap_point = studio.overlay_position(Fit.anchor_position(pose, "2d", studio.library, studio.arrange_tools.target()))
		studio.placement_hint.visible = true
		studio.placement_hint.text = "Place once · Coffee Shop"
		for i in 5: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://output/editor_placement_anchor.png")
	studio.free()
	print("ARRANGE TOOLS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func test_anchors(dimension: String) -> void:
	var tools: RefCounted = studio.arrange_tools
	for id in ["2d:Coffee_Shop", "3d:HanX_City/Cafe_Small"]:
		studio.select_asset(id)
		studio.repeat_input.button_pressed = false
		studio._process(0)
		check(studio.placement_hint.visible and studio.placement_hint.text.begins_with("Place once"), "Single placement appears beside selected asset: " + dimension)
		studio.worlds[dimension].preview(id, [0, 0, 0], studio.direction, studio.scale_input.value, true)
		studio.update_overlay(true)
		check(studio.overlay.caption.begins_with("Place once") and studio.overlay.snap_visible, "Single placement and anchor appear at cursor: " + dimension)
		studio.repeat_input.button_pressed = true
		studio._process(0)
		check(studio.placement_hint.text.begins_with("Repeat placement"), "Repeat placement appears beside selected asset: " + dimension)
		studio.worlds[dimension].preview(id, [0, 0, 0], studio.direction, studio.scale_input.value, true)
		studio.update_overlay(true)
		check(studio.overlay.caption.begins_with("Repeat placement"), "Repeat placement appears at cursor: " + dimension)
		studio.repeat_input.button_pressed = false
		studio.scale_input.value = 1.3
		studio.set_rotation_value("angle", 37)
		for target in Fit.TARGETS:
			if target == "top" and dimension == "2d": continue
			tools.snap_target.select(Fit.TARGETS.find(target))
			var record: Dictionary = studio.placement_record()
			record["scale"] = 1.3
			var desired: Array = [32.0, 24.0, 2.0] if dimension == "2d" else [4.0, 2.0, 7.0]
			record["position"] = Fit.place(desired, record, dimension, studio.library, target)
			check(vector(Fit.anchor_position(record, dimension, studio.library, target)).is_equal_approx(vector(desired)), "Selected anchor meets placement destination: " + dimension + "/" + id + "/" + target)
			record["position"][0] += 0.37
			record["position"][1 if dimension == "2d" else 2] += 0.19
			record["position"] = Fit.snap(record, dimension, studio.library, target)
			var at: Array = Fit.anchor_position(record, dimension, studio.library, target)
			var cell: Vector2 = Fit.grid(Vector2(at[0], at[1])) if dimension == "2d" else Vector2(at[0], at[2])
			check(cell.is_equal_approx(cell.round()), "Selected anchor snaps to grid: " + dimension + "/" + target)
		tools.snap_target.select(Fit.TARGETS.find("corner_x"))
		var info: Dictionary = studio.placement(studio.canvas.size / 2)
		var raw: Array = studio.worlds[dimension].point(studio.canvas.size / 2, true, studio.height_input.value)
		var placed_record: Dictionary = studio.placement_record()
		placed_record["scale"] = studio.scale_input.value
		placed_record["position"] = info["position"]
		check(vector(Fit.anchor_position(placed_record, dimension, studio.library, "corner_x")).is_equal_approx(vector(raw)), "Live placement uses selected anchor: " + dimension + "/" + id)
		studio.current().checkpoint()
		studio.stroke_cells.clear()
		var before: int = studio.current().data["objects"].size()
		studio.paint(studio.canvas.size / 2)
		check(studio.current().data["objects"].size() == before + 1 and vector(studio.current().data["objects"][-1]["position"]).is_equal_approx(vector(info["position"])), "Committed placement matches preview: " + dimension + "/" + id)
		check(studio.current().undo() and studio.current().data["objects"].size() == before, "Anchor placement supports undo: " + dimension)
		check(studio.current().redo() and studio.current().data["objects"].size() == before + 1, "Anchor placement supports redo: " + dimension)
		studio.snap_input.button_pressed = false
		info = studio.placement(studio.canvas.size / 2)
		raw = studio.worlds[dimension].point(studio.canvas.size / 2, false, studio.height_input.value)
		placed_record["position"] = info["position"]
		check(vector(Fit.anchor_position(placed_record, dimension, studio.library, "corner_x")).is_equal_approx(vector(raw)), "Custom anchor also works in free placement: " + dimension)
		studio.snap_input.button_pressed = true
	# Independent check against the actual transformed model's authored contact bounds.
	var item: Dictionary = {"asset": "3d:HanX_City/Cafe_Small", "direction": "37", "scale": 1.3, "tilt": [12, 4]}
	var sample: Node3D = load(studio.library.assets[item["asset"]]["path"]).instantiate()
	var source: AABB = preload("res://scripts/model_bounds.gd").get_bounds(sample)
	var expected: Vector3 = Basis.from_euler(Vector3(12, 37, 4) * PI / 180) * Vector3(source.end.x, source.position.y, source.position.z) * 1.3
	check(Fit.anchor(item, dimension, studio.library, "corner_x").is_equal_approx(expected), "Corner follows actual source geometry, rotation, pitch and scale: " + dimension)
	sample.free()
	tools.restore({})
	studio.clear_placement()
	var drag: Dictionary = studio.current().data["objects"][-1]
	selected([drag])
	tools.snap_target.select(Fit.TARGETS.find("edge_max_z"))
	studio.set_tool("select")
	studio.stroke = true
	studio.moved_selection = false
	studio.selection_press = studio.canvas.size / 2
	studio.drag_origins = {drag["uid"]: drag["position"].duplicate()}
	var motion := InputEventMouseMotion.new()
	motion.position = studio.selection_press + Vector2(55, 23)
	var original: Dictionary = studio.current().data.duplicate(true)
	studio._canvas_input(motion)
	var anchor: Array = Fit.anchor_position(drag, dimension, studio.library, "edge_max_z")
	var cell: Vector2 = Fit.grid(Vector2(anchor[0], anchor[1])) if dimension == "2d" else Vector2(anchor[0], anchor[2])
	check(cell.is_equal_approx(cell.round()), "Dragging honors the chosen edge anchor: " + dimension)
	studio.finish_edit(motion.position)
	check(studio.current().undo() and studio.current().data == original, "Anchor drag is one undo gesture: " + dimension)
	studio.changed()
	tools.restore({})

func test_alignment(dimension: String) -> void:
	var tools: RefCounted = studio.arrange_tools
	var ids: Array[String] = []
	for i in 4:
		var item: Dictionary = studio.current().add("3d:HanX_City/Cafe_Small", [i * 90.0, i * 30.0, i * 12.0], str(i * 15), 0.7 + i * 0.3)
		ids.append(item["uid"])
	selected(ids.map(func(uid: String) -> Dictionary: return studio.current().object(uid)))
	for axis in 3:
		tools.axis.select(axis)
		var component: int = 0 if axis == 0 else ((1 if dimension == "2d" else 2) if axis == 1 else (2 if dimension == "2d" else 1))
		for operation in ["min", "center", "max", "centers", "gaps", "spacing"]:
			var original: Dictionary = studio.current().data.duplicate(true)
			var history: int = studio.current().undo_history.size()
			tools.gap.value = 4
			tools.apply_alignment(operation)
			var boxes: Array[AABB] = []
			for uid in ids: boxes.append(tools.bounds(studio.current().object(uid)))
			if operation in ["min", "center", "max"]:
				var values: Array = []
				for box in boxes: values.append(box.position[component] if operation == "min" else (box.end[component] if operation == "max" else box.get_center()[component]))
				check(values.all(func(value: float) -> bool: return is_equal_approx(value, values[0])), "Alignment matches every base: " + dimension + "/" + str(axis) + "/" + operation)
			else:
				boxes.sort_custom(func(a: AABB, b: AABB) -> bool: return a.position[component] < b.position[component])
				var distances: Array[float] = []
				for i in range(1, boxes.size()): distances.append(boxes[i].get_center()[component] - boxes[i - 1].get_center()[component] if operation == "centers" else boxes[i].position[component] - boxes[i - 1].end[component])
				check(distances.all(func(value: float) -> bool: return is_equal_approx(value, distances[0])), "Distribution spaces different-size bases evenly: " + dimension + "/" + str(axis) + "/" + operation)
				if operation == "spacing": check(is_equal_approx(distances[0], 4), "Explicit gap is respected: " + dimension + "/" + str(axis))
			if studio.current().data == original:
				check(studio.current().undo_history.size() == history, "Unchanged alignment adds no history: " + dimension + "/" + operation)
			else:
				check(studio.current().undo() and studio.current().data == original, "Arrange action is one exact undo step: " + dimension + "/" + operation)
			studio.changed()
	tools.axis.select(0)
	tools.reference_mode.select(1)
	tools.refresh()
	tools.reference_choice.select(2)
	var reference_uid: String = str(tools.reference_choice.get_item_metadata(2))
	var reference_position: Array = studio.current().object(reference_uid)["position"].duplicate()
	tools.apply_alignment("max")
	check(studio.current().object(reference_uid)["position"] == reference_position, "Chosen reference stays fixed during alignment: " + dimension)
	studio.current().undo()
	studio.changed()
	tools.gap.value = 3
	tools.apply_alignment("spacing")
	check(vector(studio.current().object(reference_uid)["position"]).is_equal_approx(vector(reference_position)), "Chosen reference stays fixed while matching gaps: " + dimension)
	studio.current().undo()
	studio.changed()
	tools.reference_mode.select(0)
	# Protected members are never transformed, even if their IDs are in the selection.
	var protected_uid: String = ids[-1]
	studio.current().object(protected_uid)["locked"] = true
	var protected_position: Array = studio.current().object(protected_uid)["position"].duplicate()
	tools.apply_alignment("min")
	check(studio.current().object(protected_uid)["position"] == protected_position, "Alignment skips locked objects: " + dimension)
	studio.current().object(protected_uid).erase("locked")

func test_pivots(dimension: String) -> void:
	var tools: RefCounted = studio.arrange_tools
	var a: Dictionary = studio.current().add("3d:HanX_City/Cafe_Small", [4.0, 2.0, 6.0], "0", 1)
	var b: Dictionary = studio.current().add("3d:HanX_City/Cafe_Small", [12.0, 8.0, 14.0], "0", 2)
	var ids: Array = [a["uid"], b["uid"]]
	selected([a, b])
	tools.restore({})
	var center: Vector3 = tools.pivot(studio.selection_items())
	studio._command("scale", 1.5)
	check(vector(a["position"]).is_equal_approx(center + (Vector3(4, 2, 6) - center) * 1.5) and is_equal_approx(b["scale"], 3), "Group-center scale moves origins and preserves relative sizes: " + dimension)
	studio.current().undo()
	studio.changed()
	tools.pivot_mode.select(1)
	studio._command("scale", 2)
	check(vector(studio.current().object(ids[0])["position"]) == Vector3(4, 2, 6) and vector(studio.current().object(ids[1])["position"]) == Vector3(12, 8, 14), "Individual-origin scaling keeps each origin fixed: " + dimension)
	studio.current().undo()
	studio.changed()
	tools.set_custom([0, 0, 0])
	studio.set_rotation_value("angle", 90)
	var expected: Vector3 = Vector3(4, 2, 6).rotated(Vector3.UP, PI / 2) if dimension == "3d" else Vector3(4, -2, 6)
	check(vector(studio.current().object(ids[0])["position"]).is_equal_approx(expected), "Custom-pivot rotation orbits the chosen point: " + dimension)
	studio.current().undo()
	studio.changed()
	tools.set_custom([1, 1, 1])
	studio._command("scale", 2)
	check(vector(studio.current().object(ids[0])["position"]) == Vector3(7, 3, 11), "Custom-pivot scale uses the chosen point: " + dimension)
	studio.current().undo()
	studio.changed()
	tools.pivot_mode.select(1)
	studio.set_rotation_value("angle", 90)
	check(vector(studio.current().object(ids[0])["position"]) == Vector3(4, 2, 6), "Individual-origin rotation preserves origins: " + dimension)
	studio.current().undo()
	studio.changed()
	selected([studio.current().object(ids[0])])
	tools.set_custom([0, 0, 0])
	studio._command("scale", 2)
	check(vector(studio.current().object(ids[0])["position"]) == Vector3(8, 4, 12), "Single object also scales about a custom pivot: " + dimension)
	studio.current().undo()
	studio.changed()
	tools.picking_pivot = true
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = studio.canvas.size / 2
	var at: Array = studio.worlds[dimension].point(click.position, studio.snap_input.button_pressed, studio.height_input.value)
	studio._canvas_input(click)
	check(not tools.picking_pivot and tools.pivot([]).is_equal_approx(vector(at)), "Canvas click sets the custom pivot: " + dimension)

func test_surfaces() -> void:
	studio.switch_mode("3d")
	var world: Node3D = studio.worlds["3d"]
	studio.current().data["objects"] = []
	world.apply(studio.current().data)
	var platform := StaticBody3D.new()
	platform.collision_layer = 2
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 2, 40)
	collider.shape = box
	collider.position.y = 1
	platform.add_child(collider)
	world.add_child(platform)
	await physics_frame
	await physics_frame
	studio.surface_input.button_pressed = true
	world.surface_snapping = true
	studio.lanes_input.button_pressed = false
	studio.select_asset("3d:HanX_City/Cafe_Small")
	studio.height_input.value = 0
	studio.arrange_tools.snap_target.select(Fit.TARGETS.find("center"))
	var at: Vector2 = world.camera.unproject_position(Vector3(0, 2, 0))
	var destination: Array = world.surface_point(at, true, 0)
	check(is_equal_approx(destination[1], 2), "Surface destination uses actual platform height")
	var info: Dictionary = studio.placement(at)
	var record: Dictionary = studio.placement_record()
	record["position"] = info["position"]
	record["scale"] = studio.scale_input.value
	check(vector(Fit.anchor_position(record, "3d", studio.library, "center")).is_equal_approx(vector(destination)), "Chosen base center lands on the picked surface")
	var sample: Node3D = load(studio.library.assets[record["asset"]]["path"]).instantiate()
	var bounds: AABB = preload("res://scripts/model_bounds.gd").get_bounds(sample)
	check(Fit.anchor(record, "3d", studio.library, "top").is_equal_approx(Vector3(bounds.get_center().x, bounds.end.y, bounds.get_center().z)), "Top anchor uses the model roof rather than the contact slab")
	sample.free()
	studio.select_asset("2d:Coffee_Shop")
	studio.set_rotation_value("angle", 30)
	var card: Node3D = preload("res://scripts/builder/asset_instance.gd").make(studio.library, "2d:Coffee_Shop", "3d")
	world.add_child(card)
	var pose: Dictionary = {"asset": "2d:Coffee_Shop", "direction": "SE", "angle": 30, "position": [0, 0, 0], "scale": 1}
	preload("res://scripts/builder/asset_instance.gd").pose(card, pose)
	var actual_box: AABB = card.mixed_bounds()
	var top: Vector3 = card.transform * Vector3(actual_box.get_center().x, actual_box.end.y, actual_box.get_center().z)
	check(Fit.anchor(pose, "3d", studio.library, "top").is_equal_approx(top), "Sprite-card top anchor matches rendered height and orientation")
	card.free()
	platform.free()
	studio.surface_input.button_pressed = false
	studio.clear_placement()
