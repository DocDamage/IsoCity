extends SceneTree

const Document = preload("res://scripts/builder/document.gd")
const Templates = preload("res://scripts/builder/templates.gd")
const Roads = preload("res://scripts/builder/roads.gd")
const Layers = preload("res://scripts/builder/layers.gd")
const Store = preload("res://scripts/builder/project_store.gd")
const Exporter = preload("res://scripts/builder/exporter.gd")
var checks: int = 0
var failures: int = 0
var directory: String

func _init() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func click(studio: Control, at: Vector2, pressed: bool = true, shift: bool = false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = at
	event.pressed = pressed
	event.shift_pressed = shift
	studio._canvas_input(event)

func motion(studio: Control, at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	studio._canvas_input(event)

func run() -> void:
	root.size = Vector2i(1480, 900)
	directory = "res://output/upgrade_test_" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	Store.storage_root = directory + "/history"
	var studio: Control = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	for i in 5: await process_frame
	check(studio.enhancements_ready, "Upgraded controls are ready")
	for mode in ["2d", "3d"]:
		studio.documents[mode].data = Templates.make(mode, "blank")
		studio.switch_mode(mode)
		studio.changed()
		var data: Dictionary = studio.current().data
		var original_tiles: Array = data["tiles"].duplicate(true)
		Roads.paint(data, Vector2i(-2, 0), Vector2i(2, 0))
		Roads.paint(data, Vector2i(0, -2), Vector2i(0, 2))
		check(data["roads"].size() == 9, "Crossing roads share one section: " + mode)
		check(Roads.mask(Vector2i.ZERO, Roads.lookup(data)) == 15, "Four-way intersection is inferred: " + mode)
		check(Document.valid(data, mode, studio.library), "Road network saves in a valid document: " + mode)
		studio.changed()
		if mode == "2d":
			check(studio.worlds[mode].ground.get_used_cells().size() > 100, "Road generates connected paving and asphalt")
			check(Roads.tiles(data).any(func(t: Dictionary): return t["asset"] == "2d:Crosswalk_X"), "Intersections get crossings")
		else:
			check(studio.worlds[mode].road_node.get_child_count() == 9, "Every 3D road section has geometry and collision")
			check(studio.worlds[mode].road_node.get_child(0).get_child_count() >= 5, "Road has paving, asphalt, markings and collision")
		var car: String = "2d:Sedan_Red" if mode == "2d" else "3d:HanX_Traffic/Car_Sedan"
		var position_value: Array = [64, 32, 0] if mode == "2d" else [6, 0, 0.4]
		var lane: Dictionary = Roads.lane(data, position_value, "SE" if mode == "2d" else "0", studio.library, car)
		check(lane["position"] != position_value, "Cars move off road center onto a lane: " + mode)
		check(lane["direction"] == ("SE" if mode == "2d" else "90"), "Cars face the lane direction: " + mode)
		var opposite: Dictionary = Roads.lane(data, [64, 31, 0] if mode == "2d" else [6, 0, -0.4], "SE" if mode == "2d" else "0", studio.library, car)
		check(opposite["direction"] == ("NW" if mode == "2d" else "270"), "Opposite lane reverses heading: " + mode)
		data["roads"].clear()
		studio.changed()
		check(data["tiles"] == original_tiles, "Removing roads preserves original ground: " + mode)
		# Drive the real road gesture, not only the generator.
		studio.set_tool("road")
		var before: int = studio.current().undo_history.size()
		click(studio, studio.canvas.size / 2)
		motion(studio, studio.canvas.size / 2 + Vector2(160, 30))
		click(studio, studio.canvas.size / 2 + Vector2(160, 30), false)
		check(data["roads"].size() > 1 and studio.current().undo_history.size() == before + 1, "Road stroke is one undo action: " + mode)
		studio._command("undo", null)
		check(studio.current().data["roads"].is_empty(), "Road gesture undo removes the complete stroke: " + mode)
		# Layer locks block road edits and placement without altering the layout.
		studio._command("layer", ["Ground", "locked", true])
		click(studio, studio.canvas.size / 2)
		click(studio, studio.canvas.size / 2, false)
		check(studio.current().data["roads"].is_empty(), "Locked ground refuses road painting: " + mode)
		studio._command("layer", ["Ground", "locked", false])
		var a: Dictionary = studio.current().add(car, [0, 0, 0], "SE" if mode == "2d" else "0")
		var b: Dictionary = studio.current().add(car, [80, 40, 0] if mode == "2d" else [5, 0, 0], "SE" if mode == "2d" else "0")
		studio.changed()
		studio.selected_uids.assign([a["uid"], b["uid"]])
		studio.selected_uid = a["uid"]
		studio.group_selection(true)
		check(a.get("group") == b.get("group") and a.has("group"), "Grouping persists in document: " + mode)
		studio.copy_selection()
		studio.duplicate_selection()
		check(studio.current().data["objects"].size() == 4 and studio.selected_uids.size() == 2, "Duplicate acts on the entire selection: " + mode)
		var copies: Array = studio.selection_items()
		check(copies[0].get("group") != a.get("group") and copies[0].get("group") == copies[1].get("group"), "Duplicate creates an independent group: " + mode)
		var old_positions: Array = [copies[0]["position"].duplicate(), copies[1]["position"].duplicate()]
		studio.rotate_by(1)
		check(copies[0]["position"] != old_positions[0], "Group rotation moves members about a shared pivot: " + mode)
		studio.rotate_by(-1)
		check(Vector3(copies[0]["position"][0], copies[0]["position"][1], copies[0]["position"][2]).is_equal_approx(Vector3(old_positions[0][0], old_positions[0][1], old_positions[0][2])), "Counterrotation restores group position: " + mode)
		studio.name_action = "assembly"
		studio.name_field.text = "Reusable cars " + mode
		studio.confirm_name()
		check(studio.assemblies[-1]["objects"][0]["position"] == [0.0, 0.0, 0.0], "Assembly stores positions relative to its anchor: " + mode)
		studio.show_assemblies()
		studio.assembly_list.select(0)
		studio.choose_assembly()
		check(studio.assembly_ghosts.size() == 2, "Assembly displays all members before placement: " + mode)
		studio.paint(studio.canvas.size / 2)
		check(studio.current().data["objects"].size() == 6 and studio.assembly_active.is_empty() and studio.tool == "select", "Assembly places once and releases the cursor: " + mode)
		studio._command("layer", ["Vehicles", "locked", true])
		check(studio.selection_items().is_empty(), "Locking a layer clears editable selection: " + mode)
		var count_before: int = studio.current().data["objects"].size()
		studio.select_asset(car)
		studio.paint(studio.canvas.size / 2)
		check(studio.current().data["objects"].size() == count_before, "Locked layer refuses new objects: " + mode)
		studio._command("layer", ["Vehicles", "visible", false])
		check(not studio.worlds[mode].instances[a["uid"]].visible, "Layer visibility changes rendered objects: " + mode)
		studio._command("layer", ["Vehicles", "visible", true])
		studio._command("layer", ["Vehicles", "locked", false])
		studio.selected_uids.clear()
		studio.selected_uid = a["uid"]
		studio._command("assign_layer", "Decorations")
		check(a.get("layer") == "Decorations", "Custom layer assignment persists: " + mode)
		# Save per-mode workspace, then switch away and back.
		studio.set_tool("select")
		studio.search.text = "car"
		if mode == "2d": studio.worlds[mode].camera.position = Vector2(51, -22)
		else: studio.worlds[mode].target = Vector3(12, 0, 5)
		studio.switch_mode("3d" if mode == "2d" else "2d")
		studio.switch_mode(mode)
		check(studio.search.text == "car" and studio.tool == "select", "Workspace restores search and tool: " + mode)
		check(studio.worlds[mode].camera.position.is_equal_approx(Vector2(51, -22)) if mode == "2d" else studio.worlds[mode].target.is_equal_approx(Vector3(12, 0, 5)), "Workspace restores camera: " + mode)
	await test_surfaces_and_exploration(studio)
	await test_selection_input(studio)
	await test_storage_and_export(studio)
	studio.free()
	print("STUDIO UPGRADE: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func test_surfaces_and_exploration(studio: Control) -> void:
	studio.documents["3d"].data = Templates.make("3d", "blank")
	studio.switch_mode("3d")
	var item: Dictionary = studio.current().add("3d:HanX_Shop/Cafe_Counter", [0, 0, 0], "0")
	studio.changed()
	studio.worlds["3d"].reset_camera("room")
	await physics_frame
	await process_frame
	var world: Node3D = studio.worlds["3d"]
	var instance: Node3D = world.instances[item["uid"]]
	var bounds: AABB = instance.transform * preload("res://scripts/model_bounds.gd").get_bounds(instance)
	var top: Vector3 = bounds.get_center()
	top.y = bounds.end.y
	var at: Vector2 = world.camera.unproject_position(top)
	world.surface_snapping = true
	var point: Array = world.surface_point(at, false, 0)
	check(absf(point[1] - top.y) < 0.1, "Surface snap hits the countertop instead of the ground plane")
	world.surface_snapping = false
	check(world.surface_point(at, false, 0)[1] == 0, "Surface snap can be disabled")
	studio.select_asset("3d:HanX_Shop/Cafe_Table_Set")
	studio.surface_input.button_pressed = true
	var info: Dictionary = studio.placement(at)
	check(info["position"][1] > 0.5, "Actual placement uses the selected surface height")
	studio.worlds["3d"].preview(studio.asset_id, info["position"], info["direction"], 1, true)
	studio.update_overlay(true)
	check(studio.overlay.footprint.size() == 4, "3D placement shows the projected footprint")
	var door: Dictionary = studio.current().add("3d:Fire_Station_PSX/steel_personnel_door", [5, 0, 0], "0")
	var building: Dictionary = studio.current().add("3d:HanX_City/Cafe_Small", [-8, 0, -8], "0")
	studio.changed()
	var door_node: Node3D = world.instances[door["uid"]]
	check(door_node.has_meta("precise_collision") and door_node.get_node("CollisionShape3D").disabled, "Door collision uses actual mesh geometry")
	check(world.instances[building["uid"]].has_meta("precise_collision"), "Building collision follows its model")
	studio.set_walking(true)
	world.player.position = door_node.position + Vector3(0, 0.2, 1)
	check("Open door" in world.exploration.prompt(), "Nearby doors expose an interaction")
	world.exploration.interact()
	check(door.get("open", false) and door_node.collision_layer == 0 and is_equal_approx(door_node.rotation_degrees.y, 90), "Opening a door changes visual, collision and saved state")
	world.exploration.interact()
	check(not door["open"] and door_node.collision_layer != 0, "Door closes and restores collision")
	world.player.position = world.exploration.entrance(world.instances[building["uid"]])
	check("Enter furnished" in world.exploration.prompt(), "Buildings have marked entrance interactions")
	var outside: Vector3 = world.player.position
	world.exploration.interact()
	check(world.exploration.interior != null and building.has("interior") and world.exploration.interior.instances.size() == building["interior"]["objects"].size(), "Entrance opens the building's own furnished interior")
	check(world.exploration.interior.get_child_count() > 10, "Interior contains actual room furnishings")
	world.exploration.interact()
	check(world.exploration.interior == null and world.player.position == outside, "Exit returns the character to the original entrance")
	check(world.player.has_node("Character") and world.player.limbs.size() == 4, "3D walker has an articulated character")
	studio.set_walking(false)
	studio.documents["2d"].data = Templates.make("2d", "blank")
	studio.switch_mode("2d")
	var door2: Dictionary = studio.current().add("2d:Door_White", [0, 0, 0], "SE")
	var building2: Dictionary = studio.current().add("2d:Coffee_Shop", [150, 0, 0], "SE")
	studio.changed()
	var world2: Node2D = studio.worlds["2d"]
	studio.set_walking(true)
	world2.player.position = Vector2(0, 12)
	world2.exploration.interact()
	check(door2.get("open", false) and world2.instances[door2["uid"]].get_node("Sprite2D").frame > 0, "2D door shows its supplied open frame")
	check(world2.instances[door2["uid"]].get_node("StaticBody2D").collision_layer == 0, "Open 2D doors permit passage")
	world2.player.position = world2.exploration.entrance(world2.instances[building2["uid"]])
	world2.exploration.interact()
	check(world2.exploration.interior != null, "2D building entrance opens a furnished interior")
	studio.set_walking(false)
	check(world2.exploration.interior == null, "Returning to build mode leaves the interior safely")

func test_selection_input(studio: Control) -> void:
	studio.documents["2d"].data = Templates.make("2d", "blank")
	studio.switch_mode("2d")
	var a: Dictionary = studio.current().add("2d:Sedan_Red", [-100, 0, 0], "SE")
	var b: Dictionary = studio.current().add("2d:Taxi", [100, 0, 0], "SE")
	studio.changed()
	studio.set_tool("select")
	await process_frame
	var a_screen: Vector2 = studio.screen_bounds(a["uid"]).get_center()
	var b_screen: Vector2 = studio.screen_bounds(b["uid"]).get_center()
	click(studio, a_screen)
	click(studio, a_screen, false)
	click(studio, b_screen, true, true)
	click(studio, b_screen, false, true)
	check(studio.selected_uids.size() == 2, "Shift-click selects two objects through the canvas")
	var a_original: Array = a["position"].duplicate()
	var b_original: Array = b["position"].duplicate()
	click(studio, a_screen)
	motion(studio, a_screen + Vector2(64, 32))
	click(studio, a_screen + Vector2(64, 32), false)
	check(a["position"] != a_original and b["position"] != b_original, "Dragging one selected object moves both")
	check(is_equal_approx(a["position"][0] - a_original[0], b["position"][0] - b_original[0]), "Dragging keeps the group's relative spacing")
	studio._command("undo", null)
	await process_frame
	var selection_box: Rect2 = studio.screen_bounds(a["uid"]).merge(studio.screen_bounds(b["uid"])).grow(30)
	click(studio, selection_box.position)
	motion(studio, selection_box.end)
	check(studio.overlay.marquee_visible, "Marquee is visible while dragging")
	click(studio, selection_box.end, false)
	check(studio.selected_uids.size() == 2, "Marquee selects all intersecting objects")
	studio._command("layer", ["Vehicles", "locked", true])
	check(studio.worlds["2d"].pick(a_screen).is_empty(), "Locked layers are excluded from picking")
	studio._command("layer", ["Vehicles", "locked", false])
	studio.select_asset("2d:Road_Arrow_X")
	studio.rotate_by(-1)
	check(studio.direction == "NE", "Counterclockwise ground rotation wraps to NE")
	studio.rotate_by(0, true)
	check(studio.direction == "SE", "Reset restores ground orientation")
	studio.select_asset("2d:Sedan_Red")
	studio.worlds["2d"].preview(studio.asset_id, [-100, 0, 0], "SE", 1, true)
	studio.update_overlay(true)
	check(studio.overlay.footprint.size() > 2 and studio.overlay.warning, "2D footprint warns when objects overlap")

func test_storage_and_export(studio: Control) -> void:
	var path: String = directory + "/project.isocity.json"
	check(studio.write_project(path), "Upgraded project saves")
	check(not studio.dirty and "Saved" in studio.save_badge.text, "Save badge confirms an explicit save")
	var original: Dictionary = studio.session_data().duplicate(true)
	check(Store.write_json(directory + "/assembly.json", studio.assemblies), "Assembly library writes atomically")
	check(Store.read_json(directory + "/assembly.json", []) == JSON.parse_string(JSON.stringify(studio.assemblies)), "Assembly library round trips")
	var snapshot: String = Store.snapshot(original, "Named checkpoint")
	check(not snapshot.is_empty() and FileAccess.file_exists(snapshot), "Named snapshot creates a real project copy")
	Store.remember(path, "Recent project")
	check(Store.entries().size() == 2 and Store.entries()[0]["kind"] == "project", "Project browser index includes recent project and snapshot")
	for i in 43: Store.snapshot(original, "Recovery " + str(i), null, true)
	check(Store.entries().size() == 41, "Recovery keeps 40 versions and preserves recent project")
	check(FileAccess.file_exists(path), "History pruning never removes an original project")
	studio.current().checkpoint()
	studio.current().add("2d:Taxi", [0, 100, 0], "SE")
	studio.changed()
	check(studio.dirty and "Unsaved" in studio.save_badge.text, "Edit updates the save badge")
	studio._command("undo", null)
	check(not studio.dirty, "Undo back to saved content clears the unsaved badge")
	check(studio.load_project(path), "Saved workspace reopens")
	check(JSON.parse_string(JSON.stringify(studio.session_data()["workspace"])) == JSON.parse_string(JSON.stringify(original["workspace"])), "Workspace state persists in project files")
	var malformed: Dictionary = studio.current().data.duplicate(true)
	malformed["roads"] = [{"cell": [0, 1.5]}]
	check(not Document.valid(malformed, "2d", studio.library), "Malformed road coordinates are rejected before rendering")
	malformed = studio.current().data.duplicate(true)
	malformed["layers"] = {"Vehicles": {"locked": "yes"}}
	check(not Document.valid(malformed, "2d", studio.library), "Malformed layer state is rejected before rendering")
	for mode in ["2d", "3d"]:
		studio.switch_mode(mode)
		Roads.paint(studio.current().data, Vector2i(-1, 1), Vector2i(2, 1))
		Layers.set_state(studio.current().data, "Ground", "visible", false)
		studio.changed()
		var export_path: String = directory + "/export_" + mode + ".tscn"
		check(Exporter.save_scene(studio.worlds[mode], studio.current().data, studio.library, export_path) == OK, "Upgraded scene exports: " + mode)
		var instance: Node = load(export_path).instantiate()
		root.add_child(instance)
		await process_frame
		check(instance.exploration != null and instance.exploration.enabled, "Export supports entrance and door interactions: " + mode)
		check(instance.studio_data["roads"].size() == studio.current().data["roads"].size(), "Export preserves the road network: " + mode)
		if mode == "3d": check(instance.has_node("SmartRoads") and instance.get_node("SmartRoads").get_child_count() >= 4, "3D export includes generated roads")
		else: check(instance.get_node("Ground").visible and instance.get_node("Ground").get_used_cells().size() > 0, "2D export includes hidden workspace ground")
		instance.free()
