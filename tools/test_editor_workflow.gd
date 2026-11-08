extends SceneTree

const Layers = preload("res://scripts/builder/layers.gd")
var checks: int = 0
var failures: int = 0

func _init() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func run() -> void:
	root.size = Vector2i(1480, 900)
	var studio: Control = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	for i in 8: await process_frame
	var outliner: RefCounted = studio.scene_outliner
	var palette: RefCounted = studio.command_palette
	for dimension in ["2d", "3d"]:
		studio.switch_mode(dimension)
		var doc: RefCounted = studio.current()
		var uid: String = doc.data["objects"][0]["uid"]
		outliner.refresh(true)
		check(outliner.tree.get_root().get_child_count() == doc.data["objects"].size(), "Outliner lists every placed object: " + dimension)
		outliner.apply_edit({"uid": uid}, 0, "My custom building")
		check(doc.object(uid)["name"] == "My custom building", "Rename an object: " + dimension)
		studio._command("undo", null)
		check(not doc.object(uid).has("name"), "Rename supports undo: " + dimension)
		studio._command("redo", null)
		check(doc.object(uid)["name"] == "My custom building", "Rename supports redo: " + dimension)
		outliner.search.text = "custom building"
		outliner.refresh(true)
		check(outliner.tree.get_root().get_child_count() == 1, "Outliner filters renamed objects: " + dimension)
		outliner.tree.get_root().get_first_child().select(0)
		outliner.select_item()
		check(studio.selected_uid == uid, "Outliner selects the canvas object: " + dimension)
		outliner.apply_edit({"uid": uid}, 1, false)
		check(not studio.worlds[dimension].instances[uid].visible, "Outliner hides an object: " + dimension)
		check(not Layers.editable(doc.data, doc.object(uid), studio.library), "Hidden objects are protected: " + dimension)
		outliner.apply_edit({"uid": uid}, 1, true)
		outliner.apply_edit({"uid": uid}, 2, true)
		check(studio.worlds[dimension].instances[uid].visible and not Layers.editable(doc.data, doc.object(uid), studio.library), "Lock preserves visibility and protects editing: " + dimension)
		studio._command("undo", null)
		check(Layers.editable(doc.data, doc.object(uid), studio.library), "Lock supports undo: " + dimension)
		doc.checkpoint()
		doc.object(uid)["group"] = "test_group"
		doc.data["objects"][1]["group"] = "test_group"
		studio.changed()
		outliner.apply_edit({"group": "test_group"}, 0, "My neighborhood")
		outliner.search.text = "My neighborhood"
		outliner.refresh(true)
		check(outliner.tree.get_root().get_child_count() == 1 and outliner.tree.get_root().get_first_child().get_child_count() == 2, "Group names are searchable and contain their members: " + dimension)
		outliner.tree.get_root().get_first_child().select(0)
		outliner.select_item()
		check(studio.selected_uids.size() == 2, "Selecting a group selects its members: " + dimension)
		outliner.apply_edit({"group": "test_group"}, 1, false)
		check(not studio.worlds[dimension].instances[uid].visible and not studio.worlds[dimension].instances[doc.data["objects"][1]["uid"]].visible, "Hide applies to every group member: " + dimension)
		studio._command("undo", null)
		check(studio.worlds[dimension].instances[uid].visible and studio.worlds[dimension].instances[doc.data["objects"][1]["uid"]].visible, "Group visibility is one undo action: " + dimension)
		outliner.apply_edit({"group": "test_group"}, 2, true)
		check(doc.object(uid).get("locked", false) and doc.data["objects"][1].get("locked", false), "Lock applies to every group member: " + dimension)
		studio._command("undo", null)
		outliner.search.text = ""
		outliner.refresh(true)
		check(preload("res://scripts/builder/document.gd").valid(doc.data, dimension, studio.library), "Outliner metadata validates: " + dimension)
		var invalid: Dictionary = doc.data.duplicate(true)
		invalid["objects"][0]["locked"] = "yes"
		check(not preload("res://scripts/builder/document.gd").valid(invalid, dimension, studio.library), "Invalid protection flags are rejected: " + dimension)
	var path: String = "user://test_editor_workflow.isocity.json"
	check(studio.write_project(path), "Save project with object and group names")
	check(studio.load_project(path), "Reload project with outliner properties")
	check(studio.current().data.get("group_names", {}).get("test_group") == "My neighborhood", "Group name survives saving")
	palette.show()
	check(studio.modal_visible(), "Command palette blocks world input")
	palette.query.text = "roads connected"
	palette.refresh()
	check(palette.matches.size() == 1, "Palette accepts independent search words")
	palette.execute()
	check(studio.tool == "road" and not palette.dialog.visible, "Palette executes chosen command and closes")
	palette.show()
	palette.query.text = "no such command"
	palette.refresh()
	check(palette.matches.is_empty() and palette.dialog.get_ok_button().disabled, "An empty palette result cannot execute")
	palette.dialog.hide()
	var shortcut := InputEventKey.new()
	shortcut.keycode = KEY_P
	shortcut.ctrl_pressed = true
	shortcut.shift_pressed = true
	shortcut.pressed = true
	studio._input(shortcut)
	check(palette.dialog.visible and palette.query.has_focus(), "Ctrl+Shift+P opens and focuses palette")
	palette.query.text = "snapshot"
	palette.refresh()
	palette.execute()
	check(studio.name_dialog.visible and studio.name_action == "snapshot", "Palette opens the real snapshot naming flow")
	studio.name_dialog.hide()
	if "--capture" in OS.get_cmdline_user_args():
		studio.switch_mode("2d")
		outliner.panel.get_parent().current_tab = outliner.panel.get_index()
		for i in 5: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://output/editor_outliner.png")
		palette.show()
		palette.query.text = "align"
		palette.refresh()
		for i in 5: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://output/editor_commands.png")
		palette.dialog.hide()
	studio.free()
	DirAccess.remove_absolute(path)
	print("EDITOR WORKFLOW: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
