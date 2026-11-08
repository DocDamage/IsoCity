extends SceneTree

const Rotation = preload("res://scripts/builder/rotation.gd")
const Templates = preload("res://scripts/builder/templates.gd")
const Exporter = preload("res://scripts/builder/exporter.gd")
var checks: int = 0
var failures: int = 0

func _init() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ", message)

func run() -> void:
	root.size = Vector2i(1480, 900)
	var studio: Control = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	for i in 5: await process_frame
	var directory: String = "res://output/compass_test_" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var expected: Dictionary = {"N": 225.0, "NE": 180.0, "E": 135.0, "SE": 90.0, "S": 45.0, "SW": 0.0, "W": 315.0, "NW": 270.0}
	var screen_vectors: Dictionary = {"N": Vector2.UP, "NE": Vector2(1, -1), "E": Vector2.RIGHT, "SE": Vector2(1, 1), "S": Vector2.DOWN, "SW": Vector2(-1, 1), "W": Vector2.LEFT, "NW": Vector2(-1, -1)}
	for facing in expected:
		check(is_equal_approx(Rotation.compass_yaw(facing), expected[facing]), "Preset yaw includes cardinal and diagonal headings: " + facing)
		var forward: Vector3 = Basis(Vector3.UP, deg_to_rad(expected[facing])) * Vector3.BACK
		var projected: Vector3 = Basis.from_euler(Vector3(deg_to_rad(-30), deg_to_rad(45), 0)).inverse() * forward
		var on_screen := Vector2(projected.x, -projected.y / 0.5).normalized()
		check(on_screen.dot(screen_vectors[facing].normalized()) > 0.999, "Model forward projects toward the labeled direction: " + facing)
	for world_mode in ["2d", "3d"]:
		studio.documents[world_mode].data = Templates.make(world_mode, "city")
		studio.switch_mode(world_mode)
		studio.changed()
		studio.select_asset("3d:HanX_GasStation/Car_Coupe")
		check(studio.compass_panel.visible and studio.compass_buttons.size() == 8, "All compass buttons appear for model placement: " + world_mode)
		studio.set_rotation_value("pitch", 12)
		studio.set_rotation_value("roll", -7)
		for facing in Rotation.COMPASS:
			studio.compass_buttons[facing].pressed.emit()
			check(is_equal_approx(float(studio.direction), expected[facing]) and studio.compass_buttons[facing].button_pressed, "Compass button sets placement heading and selection state: " + world_mode + "/" + facing)
			check(studio.placement_tilt == Vector2(12, -7), "Compass keeps placement pitch and roll: " + world_mode + "/" + facing)
		studio.compass_buttons["N"].pressed.emit()
		var info: Dictionary = studio.placement(studio.canvas.size / 2)
		check(info["direction"] == "225", "Road lane snap preserves a chosen compass direction: " + world_mode)
		var item: Dictionary = studio.current().add(studio.asset_id, info["position"], studio.direction, 0.5)
		item["tilt"] = [12, -7]
		studio.changed()
		studio.selected_uid = item["uid"]
		studio.selected_uids.assign([item["uid"]])
		studio.refresh_controls()
		for facing in Rotation.COMPASS:
			studio.compass_buttons[facing].pressed.emit()
			var instance: Node = studio.worlds[world_mode].instances[item["uid"]]
			var model: Node3D = instance.model if world_mode == "2d" else instance
			check(model.rotation_degrees.is_equal_approx(Vector3(12, expected[facing], -7)), "Placed model turns to the actual compass heading: " + world_mode + "/" + facing)
		studio._command("undo", null)
		check(studio.current().object(item["uid"])["direction"] == "315", "Compass edit is undoable: " + world_mode)
		studio._command("redo", null)
		check(studio.current().object(item["uid"])["direction"] == "270", "Compass edit is redoable: " + world_mode)
		if world_mode == "2d":
			var first: Dictionary = studio.current().object(item["uid"])
			var values: Array = first["position"].duplicate()
			values[0] += 32
			values[1] += 16
			var second: Dictionary = studio.current().add(first["asset"], values, first["direction"], first["scale"])
			studio.changed()
			studio.selected_uid = first["uid"]
			studio.selected_uids.assign([first["uid"], second["uid"]])
			studio._command("compass", "N")
			var relative := Vector2(second["position"][0] - first["position"][0], second["position"][1] - first["position"][1])
			check(relative.is_equal_approx(Vector2(0, sqrt(512))), "Grouped models orbit in the same direction as their 3D headings in the pixel world")
		if world_mode == "3d":
			studio.worlds[world_mode].yaw = 100
			studio._process(0)
			studio.selected_uid = item["uid"]
			studio.selected_uids.assign([item["uid"]])
			studio.refresh_controls()
			studio.compass_buttons["N"].pressed.emit()
			check(studio.current().object(item["uid"])["direction"] == "280", "Compass follows the current 3D camera after orbiting")
			studio.set_rotation_value("angle", 281)
			check(studio.compass_caption.text.begins_with("Custom"), "Custom headings do not falsely highlight a compass preset")
		var export_path: String = directory + "/compass_" + world_mode + ".tscn"
		check(Exporter.save_scene(studio.worlds[world_mode], studio.current().data, studio.library, export_path) == OK, "Compass headings export: " + world_mode)
		var exported: Node = load(export_path).instantiate()
		root.add_child(exported)
		await process_frame
		var exported_node: Node = exported.get_node("Objects").get_children().filter(func(node: Node): return node.get_meta("builder_uid", "") == item["uid"])[0]
		var model: Node3D = exported_node.model if world_mode == "2d" else exported_node
		check(absf(angle_difference(deg_to_rad(model.rotation_degrees.y), deg_to_rad(float(studio.current().object(item["uid"])["direction"])))) < 0.0001, "Export keeps the model's chosen heading: " + world_mode)
		exported.free()
		studio.worlds["2d"].camera.enabled = world_mode == "2d"
		studio.select_asset("2d:Coffee_Shop")
		check(not studio.compass_panel.visible and studio.view_choice.visible, "Sprites retain their supplied-view selector: " + world_mode)
	var save_path: String = directory + "/compass.isocity.json"
	check(studio.write_project(save_path) and studio.load_project(save_path), "Both worlds' compass headings save and reopen")
	if "--capture" in OS.get_cmdline_user_args():
		studio.switch_mode("2d")
		var chosen: Dictionary = studio.current().data["objects"].filter(func(record: Dictionary): return record["asset"].begins_with("3d:"))[0]
		studio.selected_uid = chosen["uid"]
		studio.selected_uids.assign([chosen["uid"]])
		studio.set_tool("select")
		studio.refresh_controls()
		studio.worlds["2d"].reset_camera("city")
		for i in 8: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://output/compass_controls.png")
	studio.free()
	print("COMPASS: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
