extends SceneTree

const Catalog = preload("res://scripts/catalog.gd")
const IsoMath = preload("res://scripts/iso_math.gd")
var failures: int = 0
var checks: int = 0

func _init() -> void:
	call_deferred("_run_tests")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)

func _run_tests() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main: Node2D = scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	check(main.objects_container.get_child_count() == 12, "All 12 starter placements load")
	for tile in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i(-4, 7)]:
		var center: Vector2 = main.tilemap.position + main.tilemap.map_to_local(tile)
		check(center.is_equal_approx(IsoMath.tile_to_world(tile) + Vector2(0, 8)), "TileMap and object grid agree at %s" % tile)
		check(IsoMath.world_to_tile(center) == tile, "Picking the center selects the correct tile")
	for id in Catalog.get_registry()["items"]:
		check(ResourceLoader.exists(Catalog.get_scene_path(id)), "Catalog scene exists: " + id)
	main.clear_placed_objects()
	check(main.undo_stack.is_empty(), "Clear resets history")
	main.current_dir = "NW"
	main.change_elevation(3)
	main.place_object_at(Vector2i(2, 2), "Coffee_Shop")
	var building: Node2D = main.placed_items[Vector2i(2, 2)][0]
	check(building.direction == "NW" and building.elevation == 3, "Placement uses direction and elevation")
	main.undo()
	check(main.objects_container.get_child_count() == 0, "Undo detaches placed object")
	main.redo()
	check(main.objects_container.get_child_count() == 1, "Redo restores placed object")
	main.erase_object_at(Vector2i(2, 2))
	main.undo()
	check(main.objects_container.get_child_count() == 1, "Erasing can be undone")
	main.place_object_at(Vector2i(5, 5), "Office_Worker", {"direction": "SW", "elevation": 2, "action": "sit"})
	main.place_object_at(Vector2i(7, 7), "Dog_Golden")
	main.toggle_day_night()
	main.place_object_at(Vector2i(20, 20), "Water")
	check(main.tilemap.get_cell_source_id(Vector2i(20, 20)) == 1, "Animated water paints on the tile map")
	main.undo()
	check(main.tilemap.get_cell_source_id(Vector2i(20, 20)) == -1, "Tile undo restores the empty cell")
	main.redo()
	main.toggle_mode()
	check(is_instance_valid(main.player_character), "Explore spawns a character")
	var player: CharacterBody2D = main.player_character
	player.grid_pos = Vector2i(50, 50)
	var before: Vector2 = player.position
	var press := InputEventKey.new()
	press.keycode = KEY_D
	press.pressed = true
	Input.parse_input_event(press)
	for frame in range(25):
		await physics_frame
	check(player.position.x > before.x + 10.0, "Character moves continuously across tile boundaries")
	check(player._anim_frame_idx != 0 or player._anim_timer > 0.05, "Walk animation advances while moving")
	press.pressed = false
	Input.parse_input_event(press)
	await physics_frame
	main.toggle_mode()
	var path: String = "user://setup_smoke_%d.json" % Time.get_ticks_usec()
	check(main.save_city(path), "City saves successfully")
	main.current_dir = "SE"
	main.current_elevation = 0
	main.toggle_day_night()
	check(main.load_city(path), "City reloads successfully")
	check(main.objects_container.get_child_count() == 3, "Buildings, placed characters, and pets reload without the explore avatar")
	var restored: Node2D = main.placed_items[Vector2i(2, 2)][0]
	check(restored.direction == "NW" and restored.elevation == 3, "Save restores orientation and elevation")
	var character: Node2D = main.placed_items[Vector2i(5, 5)][0]
	check(character.direction == "SW" and character.elevation == 2 and character.action == "sit", "Save restores character state")
	check(main.night_mode and restored.night_mode, "Save restores night lighting")
	check(main.tilemap.get_cell_source_id(Vector2i(20, 20)) == 1, "Save restores animated ground tiles")
	check(main.undo_stack.is_empty() and main.redo_stack.is_empty(), "Loading resets stale undo/redo references")
	var invalid := FileAccess.open(path, FileAccess.WRITE)
	invalid.store_string('{"tiles": [], "objects": [{"id": "unknown", "grid_pos": [0, 0]}]}')
	invalid.close()
	check(not main.load_city(path), "Invalid city is rejected")
	check(main.objects_container.get_child_count() == 3, "Invalid load preserves the current city")
	main.select_item("Door_White")
	var direction_before: String = main.current_dir
	main._cycle_direction()
	check(main.current_dir != direction_before, "Rotation cycles the selected asset's supported directions")
	main.clear_placed_objects()
	main.undo()
	check(main.objects_container.get_child_count() == 0, "Undo after Clear never resurrects deleted objects")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	main.queue_free()
	await process_frame
	await process_frame
	print("MAIN FEATURES: ", checks - failures, "/", checks, " checks passed")
	quit(1 if failures > 0 else 0)
