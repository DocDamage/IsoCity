extends SceneTree

const Templates = preload("res://scripts/builder/templates.gd")
const Document = preload("res://scripts/builder/document.gd")
const Exporter = preload("res://scripts/builder/exporter.gd")
const IsoMath = preload("res://scripts/iso_math.gd")
var checks: int = 0
var failures: int = 0

func _init() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func _run() -> void:
	var studio: Control = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	await process_frame
	await process_frame
	check(studio.library.assets.size() == Catalog.get_registry()["items"].size() + 386 + Catalog.get_registry().get("models",{}).size(), "All base and added assets are browsable")
	check(not studio.repeat_input.button_pressed, "Single placement is the default")
	for id in studio.library.assets:
		check(studio.library.icon(id) != null, "Asset has a real thumbnail: " + id)
	for dimension in ["2d", "3d"]:
		for kind in ["blank", "room", "city"]:
			var data: Dictionary = Templates.make(dimension, kind)
			check(Document.valid(data, dimension, studio.library), "Template validates: " + dimension + "/" + kind)
			studio.documents[dimension].data = data
			studio.worlds[dimension].apply(data)
			check(studio.worlds[dimension].instances.size() == data["objects"].size(), "Template renders every object: " + dimension + "/" + kind)
			var example_path: String = "res://scenes/examples/%s_%s.tscn" % [kind, dimension]
			check(ResourceLoader.exists(example_path), "Ready-to-run example exists: " + dimension + "/" + kind)
			if ResourceLoader.exists(example_path):
				var example: Node = load(example_path).instantiate()
				root.add_child(example)
				await process_frame
				check(example.get_node("Objects").get_child_count() == data["objects"].size(), "Ready-to-run example includes all template objects: " + dimension + "/" + kind)
				example.free()
	test_traffic(studio)
	test_tile_rotation(studio)
	for dimension in ["2d", "3d"]:
		studio.switch_mode(dimension)
		var dropped_id: String = "2d:Coffee_Shop" if dimension == "2d" else "3d:HanX_City/Cafe_Small"
		var drop_location: Vector2 = studio.canvas.size / 2
		var count_before: int = studio.current().data["objects"].size()
		studio.select_asset(dropped_id)
		studio.worlds[dimension].preview(dropped_id, [0, 0, 0], studio.direction, 1.0, true)
		studio.canvas._drop_data(drop_location, {"type": "builder_asset", "asset_id": dropped_id})
		check(studio.current().data["objects"].size() == count_before + 1, "Drag/drop places one object: " + dimension)
		check(studio.asset_id.is_empty() and studio.tool == "select" and not studio.stroke, "Drag/drop ends placement mode: " + dimension)
		check(not is_instance_valid(studio.worlds[dimension].ghost), "Drag/drop immediately clears the cursor preview: " + dimension)
		var followup := InputEventMouseButton.new()
		followup.button_index = MOUSE_BUTTON_LEFT
		followup.pressed = true
		followup.position = drop_location + Vector2(120, 80)
		studio._canvas_input(followup)
		followup.pressed = false
		studio._canvas_input(followup)
		check(studio.current().data["objects"].size() == count_before + 1, "Next click does not place an extra copy: " + dimension)
		studio._command("undo", null)
		check(studio.current().data["objects"].size() == count_before, "Drop is one undo step: " + dimension)
		studio._command("redo", null)
		check(studio.current().data["objects"].size() == count_before + 1, "Dropped asset can be redone: " + dimension)
		studio._command("undo", null)
		studio.select_asset(dropped_id)
		studio.worlds[dimension].preview(dropped_id, [0, 0, 0], studio.direction, 1.0, true)
		var placed := InputEventMouseButton.new()
		placed.button_index = MOUSE_BUTTON_LEFT
		placed.pressed = true
		placed.position = drop_location
		studio._canvas_input(placed)
		placed.pressed = false
		# Godot dispatches _input before the canvas receives the release event.
		studio._input(placed)
		studio._canvas_input(placed)
		check(studio.current().data["objects"].size() == count_before + 1, "Click/release places one asset: " + dimension)
		check(studio.asset_id.is_empty() and studio.tool == "select" and not is_instance_valid(studio.worlds[dimension].ghost), "Click/release clears the cursor and active asset: " + dimension)
		placed.position += Vector2(120, 80)
		placed.pressed = true
		studio._canvas_input(placed)
		placed.pressed = false
		studio._input(placed)
		studio._canvas_input(placed)
		check(studio.current().data["objects"].size() == count_before + 1, "Click-placement next click adds nothing: " + dimension)
		studio._command("undo", null)
		studio.repeat_input.button_pressed = true
		studio.select_asset(dropped_id)
		for offset in [Vector2.ZERO, Vector2(140, 90)]:
			placed.position = drop_location + offset
			placed.pressed = true
			studio._canvas_input(placed)
			placed.pressed = false
			studio._input(placed)
			studio._canvas_input(placed)
		check(studio.asset_id == dropped_id and studio.tool == "place", "Explicit repeat mode keeps the asset active: " + dimension)
		check(studio.current().data["objects"].size() == count_before + 2, "Repeat mode allows consecutive placements: " + dimension)
		studio._command("undo", null)
		studio._command("undo", null)
		studio.repeat_input.button_pressed = false
		studio.select_asset(dropped_id)
		placed.pressed = true
		studio._canvas_input(placed)
		placed.pressed = false
		studio._input(placed)
		check(studio.asset_id.is_empty(), "Releasing outside the canvas also clears placement: " + dimension)
		studio._command("undo", null)
	studio.switch_mode("2d")
	studio.select_asset("2d:Coffee_Shop")
	studio.set_tool("select")
	var first: Node2D = studio.worlds["2d"].instances.values()[0]
	var sprite: Sprite2D = first.get_node("Sprite2D")
	var location: Vector2 = studio.viewport.canvas_transform * sprite.to_global(sprite.get_rect().get_center())
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = location
	studio._canvas_input(click)
	check(not studio.selected_uid.is_empty(), "Click selects a placed object")
	var selected_position: Array = studio.current().object(studio.selected_uid)["position"].duplicate()
	var selected_test_uid: String = studio.selected_uid
	var selected_world_before: Vector2 = studio.worlds["2d"].instances[selected_test_uid].position
	var previous_history: int = studio.current().undo_history.size()
	var motion := InputEventMouseMotion.new()
	motion.position = location + Vector2(2, 1)
	studio._canvas_input(motion)
	check(studio.current().object(studio.selected_uid)["position"] == selected_position and studio.current().undo_history.size() == previous_history, "Selection ignores small mouse jitter without moving or recording an edit")
	motion.position = location + Vector2(48, 0)
	studio._canvas_input(motion)
	check(studio.current().undo_history.size() == previous_history + 1, "Deliberate drag creates one undo step")
	click.pressed = false
	studio._canvas_input(click)
	studio._command("undo", null)
	check(studio.worlds["2d"].instances[selected_test_uid].position.is_equal_approx(selected_world_before), "Dragging can be undone")
	studio.select_asset("2d:Coffee_Shop")
	var before: int = studio.current().data["objects"].size()
	studio.current().checkpoint()
	studio.paint(studio.canvas.size / 2)
	check(studio.current().data["objects"].size() == before + 1, "Click placement adds one object")
	check(studio.asset_id == "2d:Coffee_Shop" and studio.tool == "place", "Click-selected paint brush remains available for repeated placement")
	studio._command("undo", null)
	check(studio.current().data["objects"].size() == before, "Placement undo")
	studio._command("redo", null)
	check(studio.current().data["objects"].size() == before + 1, "Placement redo")
	studio.selected_uid = studio.current().data["objects"][-1]["uid"]
	studio.refresh_controls()
	studio._command("height", 3.0)
	studio._command("scale", 1.5)
	studio._command("rotate", null)
	var item: Dictionary = studio.current().object(studio.selected_uid)
	check(item["position"][2] == 3.0 and item["scale"] == 1.5 and item["direction"] != "SE", "Inspector edits persist in document")
	studio.duplicate_selection()
	check(studio.current().data["objects"].size() == before + 2, "Duplicate creates a separate editable object")
	studio._command("remove", null)
	check(studio.current().data["objects"].size() == before + 1, "Remove deletes only the selection")
	studio.select_asset("2d:Floor_Wood_Oak")
	studio.brush_input.value = 3
	studio.stroke_cells.clear()
	studio.paint(Vector2(60, 60))
	check(studio.current().data["tiles"].any(func(tile: Dictionary) -> bool: return tile["asset"] == "2d:Floor_Wood_Oak"), "Floor brush paints the floor TileSet")
	studio.toggle_favorite("2d:Coffee_Shop")
	var matches: Array = studio.library.find("2d", "All assets", "coffee shop", studio.favorites, true)
	check(matches.size() == 1 and matches[0]["id"] == "2d:Coffee_Shop", "Search and favorites work together")
	var preserved_2d: Dictionary = studio.documents["2d"].data.duplicate(true)
	studio.switch_mode("3d")
	studio.select_asset("3d:HanX_City/Cafe_Small")
	studio.current().checkpoint()
	studio.stroke_cells.clear()
	studio.paint(studio.canvas.size / 2)
	check(studio.documents["2d"].data == preserved_2d, "Switching workspaces preserves the other document")
	var directory: String = "user://studio_test_" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var path: String = directory + "/project.json"
	var saved: Dictionary = studio.session_data().duplicate(true)
	check(studio.write_project(path), "Project saves")
	check(studio.write_project(path), "Saving over the same project succeeds")
	studio.documents["2d"].data = Templates.make("2d", "blank")
	check(studio.load_project(path), "Project reopens")
	check(JSON.parse_string(JSON.stringify(studio.session_data()["documents"])) == JSON.parse_string(JSON.stringify(saved["documents"])), "Save/load restores both documents exactly")
	var reopened: Dictionary = studio.session_data().duplicate(true)
	var invalid := FileAccess.open(directory + "/invalid.json", FileAccess.WRITE)
	invalid.store_string('{"version":1,"documents":{}}')
	invalid.close()
	check(not studio.load_project(directory + "/invalid.json"), "Invalid project is rejected")
	check(JSON.parse_string(JSON.stringify(studio.session_data())) == JSON.parse_string(JSON.stringify(reopened)), "Invalid load never clears current work")
	for dimension in ["2d", "3d"]:
		var export_path: String = directory + "/export_" + dimension + ".tscn"
		check(Exporter.save_scene(studio.worlds[dimension], studio.documents[dimension].data, studio.library, export_path) == OK, "Scene export succeeds: " + dimension)
		var scene: PackedScene = load(export_path)
		check(scene != null, "Exported scene loads: " + dimension)
		if scene:
			var instance: Node = scene.instantiate()
			root.add_child(instance)
			await process_frame
			check(instance.get_node("Objects").get_child_count() == studio.documents[dimension].data["objects"].size(), "Export includes every placed object: " + dimension)
			check(instance.get_node("Player").visible, "Export includes a playable character: " + dimension)
			instance.walking = false
			instance._set_mode()
			check(not instance.get_node("Player").visible, "Export supports free camera mode: " + dimension)
			instance.free()
		DirAccess.remove_absolute(export_path)
	studio.switch_mode("3d")
	studio.set_walking(true)
	var player: CharacterBody3D = studio.worlds["3d"].player
	player.position = Vector3(50, 0.2, 50)
	var start: Vector3 = player.position
	var press := InputEventKey.new()
	press.keycode = KEY_D
	press.physical_keycode = KEY_D
	press.pressed = true
	Input.parse_input_event(press)
	for index in 30:
		await physics_frame
	check(player.position.distance_to(start) > 1.0, "3D character walks with continuous physics")
	press.pressed = false
	Input.parse_input_event(press)
	studio.set_walking(false)
	check(not player.active and not player.visible, "Returning to Build mode disables the walk avatar")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(directory + "/invalid.json")
	DirAccess.remove_absolute(directory)
	studio.queue_free()
	await process_frame
	await process_frame
	print("STUDIO: ", checks - failures, "/", checks, " checks passed")
	quit(1 if failures else 0)

func test_traffic(studio: Control) -> void:
	var city: Dictionary = Templates.make("2d", "city")
	var cars: Array = city["objects"].filter(func(item: Dictionary) -> bool: return item["asset"] in ["2d:Sedan_Red", "2d:Taxi"])
	var sides: Array[float] = []
	for car in cars:
		var position: Array = car["position"]
		var j: float = (float(position[1]) / 8.0 - float(position[0]) / 16.0) * 0.5
		var footprint: Array = studio.library.assets[car["asset"]]["data"]["directions"][car["direction"]]["footprint"]
		var near_edge: float = j - 0.5
		var far_edge: float = j + float(footprint[1]) - 0.5
		check(near_edge * far_edge > 0, "2D car footprint clears the road divider: " + car["asset"])
		sides.append((near_edge + far_edge) * 0.5)
	check(sides[0] * sides[1] < 0 and cars[0]["direction"] == "SE" and cars[1]["direction"] == "NW", "2D cars occupy opposite lanes and face opposite directions")
	var city3: Dictionary = Templates.make("3d", "city")
	var roads: Array = city3["objects"].filter(func(item: Dictionary) -> bool: return item["asset"].ends_with("/Road_Straight"))
	var vehicles: Array = city3["objects"].filter(func(item: Dictionary) -> bool: return item["asset"].ends_with("/Car_Sedan") or item["asset"].ends_with("/Car_Taxi"))
	var road_axis: Vector3 = Basis(Vector3.UP, deg_to_rad(float(roads[0]["direction"]))) * Vector3.FORWARD
	check(absf(road_axis.dot(Vector3.RIGHT)) > 0.99, "3D road modules run along the street rather than across it")
	for vehicle in vehicles:
		var car_axis: Vector3 = Basis(Vector3.UP, deg_to_rad(float(vehicle["direction"]))) * Vector3.FORWARD
		var lateral_offset: float = float(vehicle["position"][2]) - 3.0
		check(absf(car_axis.dot(road_axis)) > 0.99 and absf(lateral_offset) > 1.04 and absf(lateral_offset) + 1.04 < 3.0, "3D car fits inside its lane, parallel to the street: " + vehicle["asset"])
	check((vehicles[0]["position"][2] - 3.0) * (vehicles[1]["position"][2] - 3.0) < 0 and absf(float(vehicles[0]["direction"]) - float(vehicles[1]["direction"])) == 180.0, "3D traffic uses opposite lanes and headings")
	city["template_revision"] = 1
	cars[0]["position"] = [-80.0, -40.0, 0.0]
	cars[1]["position"] = [48.0, 24.0, 0.0]
	cars[1]["direction"] = "SE"
	var customized: Dictionary = cars[0].duplicate(true)
	customized["uid"] = "custom_car"
	customized["position"] = [240.0, 180.0, 0.0]
	city["objects"].append(customized)
	check(Templates.upgrade_road_layout(city), "Old starter traffic can be upgraded")
	check(cars[0]["position"] != [-80.0, -40.0, 0.0] and cars[1]["direction"] == "NW", "Upgrade fixes untouched starter cars")
	check(customized["position"] == [240.0, 180.0, 0.0], "Upgrade preserves manually placed/moved cars")
	check(not Templates.upgrade_road_layout(city), "Traffic upgrade is idempotent")
	city3["template_revision"] = 1
	for road in roads:
		road["direction"] = "0"
		road["position"][1] = 0.0
	for vehicle in vehicles:
		vehicle["direction"] = "0"
		vehicle["position"][1] = 0.0
		vehicle["position"][2] = 3.0
	roads[0]["position"][2] = 20.0
	Templates.upgrade_road_layout(city3)
	check(roads[1]["direction"] == "90" and vehicles[0]["direction"] == "90" and vehicles[1]["direction"] == "270", "Upgrade fixes the old 3D road and traffic alignment")
	check(roads[0]["position"][2] == 20.0 and roads[0]["direction"] == "0", "Upgrade preserves manually moved road segments")

func test_tile_rotation(studio: Control) -> void:
	var original: Dictionary = studio.documents["2d"].data.duplicate(true)
	studio.documents["2d"].data = Templates.make("2d", "blank")
	studio.worlds["2d"].apply(studio.documents["2d"].data)
	studio.switch_mode("2d")
	studio.select_asset("2d:Road_Arrow_X")
	check(studio.library.directions("2d:Road_Arrow_X").size() == 4 and studio.library.directions("2d:Floor_Wood_Oak").size() == 4, "Road and floor tiles expose quarter-turn rotation")
	studio.rotate_selection()
	check(studio.direction == "SW", "Active tile rotation advances before painting")
	studio.stroke_cells.clear()
	studio.paint(studio.canvas.size / 2)
	var tile: Dictionary = studio.current().data["tiles"][0]
	var cell := Vector2i(tile["cell"][0], tile["cell"][1])
	check(tile["direction"] == "SW" and studio.worlds["2d"].ground.get_cell_alternative_tile(cell) == 1, "Paint stores and renders the rotated tile orientation")
	studio.set_tool("select")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = studio.viewport.canvas_transform * (IsoMath.tile_to_world(cell) + Vector2(0, 8))
	studio._canvas_input(click)
	click.pressed = false
	studio._input(click)
	studio._canvas_input(click)
	check(studio.selected_cell == cell and not studio.selected_tile().is_empty(), "Placed ground tiles can be selected")
	studio.rotate_selection()
	check(tile["direction"] == "NW" and studio.worlds["2d"].ground.get_cell_alternative_tile(cell) == 2, "Placed tile rotates without repainting")
	studio._command("undo", null)
	check(studio.worlds["2d"].ground.get_cell_alternative_tile(cell) == 1, "Tile rotation can be undone")
	studio._command("redo", null)
	check(studio.worlds["2d"].ground.get_cell_alternative_tile(cell) == 2, "Tile rotation can be redone")
	var material: ShaderMaterial = studio.worlds["2d"].ground.tile_set.get_source(0).get_tile_data(studio.worlds["2d"].tile_lookup["2d:Road_Arrow_X"]["atlas"], 2).material
	check(material != null and material.get_shader_parameter("quarter_turns") == 2, "Rotated tile uses an isometric-plane rotation material")
	var prefab: Node2D = load("res://scenes/items/Floors/Floor_Wood_Oak.tscn").instantiate()
	prefab.direction = "SW"
	root.add_child(prefab)
	check(prefab.get_node("Sprite2D").material != null, "Tile prefabs also rotate when used directly in Godot")
	prefab.free()
	var path: String = "user://tile_rotation_" + str(Time.get_ticks_usec())
	check(studio.write_project(path + ".json") and studio.load_project(path + ".json"), "Rotated tile project saves and reopens")
	check(studio.worlds["2d"].ground.get_cell_alternative_tile(cell) == 2, "Save/load preserves the tile orientation")
	check(Exporter.save_scene(studio.worlds["2d"], studio.current().data, studio.library, path + ".tscn") == OK, "Rotated ground exports to a Godot scene")
	var exported: Node = load(path + ".tscn").instantiate()
	root.add_child(exported)
	check(exported.get_node("Ground").get_cell_alternative_tile(cell) == 2, "Exported scene retains rotated ground tiles")
	exported.free()
	var invalid: Dictionary = studio.current().data.duplicate(true)
	invalid["tiles"][0]["direction"] = "invalid"
	check(not Document.valid(invalid, "2d", studio.library), "Invalid saved tile rotations are rejected")
	DirAccess.remove_absolute(path + ".json")
	DirAccess.remove_absolute(path + ".tscn")
	studio.documents["2d"].data = original
	studio.documents["2d"].undo_history.clear()
	studio.documents["2d"].redo_history.clear()
	studio.worlds["2d"].apply(original)
	studio.switch_mode("2d")
