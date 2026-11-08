extends SceneTree

const Document = preload("res://scripts/builder/document.gd")
const Exporter = preload("res://scripts/builder/exporter.gd")
var checks: int = 0
var failures: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var studio: Control = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	for i in 5: await process_frame
	for mode in ["2d","3d"]:
		studio.switch_mode(mode)
		var doc: RefCounted = studio.current()
		var buildings: Array = doc.data["objects"].filter(func(item:Dictionary)->bool:return studio.library.assets[item["asset"]]["behavior"].get("building",false))
		var first: String = buildings[0]["uid"]
		var second: String = buildings[1]["uid"]
		var before: Dictionary = doc.data.duplicate(true)
		var world: Node = studio.worlds[mode]
		studio.interior_tools.start(first)
		check(studio.interior_tools.editing() and studio.current() != doc and studio.interior_tools.outer == doc, "Room editing uses a separate undo context: " + mode)
		check(doc.object(first).has("interior") and not doc.object(second).has("interior"), "Each building owns its room independently: " + mode)
		var room: RefCounted = studio.current()
		var initial_count: int = room.data["objects"].size()
		room.checkpoint()
		var mixed: String = "3d:HanX_Park/Bench_Park" if mode == "2d" else "2d:Sofa_Teal"
		var object: Dictionary = room.add(mixed,[50,0,0] if mode == "2d" else [2,0,2],"0" if mode == "2d" else "SE")
		object["name"] = "Only in the first room"
		var door: Dictionary = room.add("2d:Door_White",[120,-20,0] if mode == "2d" else [3,0,-2],studio.library.directions("2d:Door_White")[0])
		studio.changed()
		check(world.instances.has(object["uid"]) and room.data["objects"].size() == initial_count+2, "Normal editing renders mixed furniture in the room: " + mode)
		check(room.undo() and room.data["objects"].size() == initial_count, "Room edits undo locally: " + mode)
		check(room.redo() and room.data["objects"].size() == initial_count+2, "Room edits redo locally: " + mode)
		studio.changed()
		var session: Dictionary = studio.session_data()
		check(session["documents"][mode]["objects"].size() == before["objects"].size() and session["documents"][mode]["objects"][0].has("interior"), "Saving during room editing retains the exterior and owned contents: " + mode)
		check(Document.valid(session["documents"][mode],mode,studio.library), "Nested rooms validate as project data: " + mode)
		var invalid: Dictionary = session["documents"][mode].duplicate(true)
		invalid["objects"][0]["interior"]["mode"] = "3d" if mode == "2d" else "2d"
		check(not Document.valid(invalid,mode,studio.library), "Mismatched nested room dimensions are rejected: " + mode)
		var path: String = "user://persistent_room_"+mode+".isocity.json"
		check(studio.write_project(path), "Project saves while editing a room: " + mode)
		check(not studio.dirty, "Saving a room marks the complete project saved: " + mode)
		check(not studio.load_project("user://missing_room_test.json") and studio.interior_tools.editing(), "Failed project opening preserves the editing context: " + mode)
		studio.interior_tools.leave()
		check(studio.current() == doc and doc.data["objects"].size() == before["objects"].size(), "Back to city restores exterior editing: " + mode)
		var building_node: Node = world.instances[first]
		doc.object(first)["interior"]["title"] += "!"
		world.apply(doc.data)
		check(world.last_apply_updates == 0 and world.instances[first] == building_node, "Room-only changes do not rebuild exterior objects: " + mode)
		check(doc.undo() and not doc.object(first).has("interior"), "The whole interior editing visit is undoable from the city: " + mode)
		check(doc.redo() and doc.object(first)["interior"]["objects"].size() == initial_count+2, "City redo restores the owned room: " + mode)
		studio.changed()
		var expected_second: Dictionary=preload("res://scripts/builder/interiors.gd").make_for(doc.object(second),mode,studio.library)
		studio.interior_tools.start(second)
		check(studio.current().data["objects"].size() == expected_second["objects"].size() and not studio.current().data["objects"].any(func(item:Dictionary)->bool:return item.get("name","") == "Only in the first room"), "A second building starts with its own building-specific contents: " + mode)
		studio.interior_tools.leave()
		studio.interior_tools.start(first)
		check(studio.current().data["objects"].size() == initial_count+2, "Reopening the first room retains edits: " + mode)
		if "--capture" in OS.get_cmdline_user_args():
			for i in 10: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://output/editor_owned_interior.png" if mode == "3d" else "res://output/editor_owned_interior_2d.png")
		studio.set_walking(true)
		check(studio.interior_tools.interact_exit() and not studio.interior_tools.editing() and studio.walking, "E at the editor room exit returns to walking outside: " + mode)
		studio.set_walking(false)
		studio.interior_tools.start(first)
		check(studio.load_project(path) and not studio.interior_tools.editing(), "Saved projects reopen in the city context: " + mode)
		doc = studio.current()
		check(doc.object(first)["interior"]["objects"].size() == initial_count+2 and not doc.object(second).has("interior"), "Project load retains exactly the saved owned rooms: " + mode)
		studio.selected_uid = first
		studio.selected_uids.assign([first])
		studio.duplicate_selection()
		var duplicate: Dictionary = studio.current().object(studio.selected_uid)
		duplicate["interior"]["title"] = "Independent copy"
		check(doc.object(first)["interior"]["title"] != duplicate["interior"]["title"], "Duplicating buildings deep-copies room contents: " + mode)
		studio.changed()
		var exterior_door: Dictionary = doc.add("2d:Door_White",[250,0,0] if mode == "2d" else [20,0,0],studio.library.directions("2d:Door_White")[0])
		exterior_door["open"] = true
		var hidden: Dictionary = doc.add("2d:Tree_Oak",[300,0,0] if mode == "2d" else [30,0,0],"SE")
		hidden["visible"] = false
		studio.changed()
		var door_layers: Array = collision_layers(world.instances[exterior_door["uid"]])
		var hidden_layers: Array = collision_layers(world.instances[hidden["uid"]])
		studio.set_walking(true)
		world.player.teleport_to(world.exploration.entrance(world.instances[second]))
		world.exploration.interact()
		check(doc.object(second).has("interior") and studio.autosave_pending, "First walking visit persists an independently owned room and schedules autosave: " + mode)
		studio.interior_tools.refresh()
		check(studio.interior_tools.edit_button.visible, "Walking inside offers an Edit this room action: " + mode)
		studio.interior_tools.start(second)
		check(studio.interior_tools.editing() and not studio.walking, "Editing directly from an explored interior restores the city before changing context: " + mode)
		studio.interior_tools.leave()
		check(collision_layers(world.instances[exterior_door["uid"]]) == door_layers and collision_layers(world.instances[hidden["uid"]]) == hidden_layers and not world.instances[hidden["uid"]].visible, "Returning restores open-door and hidden-object collision states exactly: " + mode)
		studio.set_walking(true)
		world.player.teleport_to(world.exploration.entrance(world.instances[first]))
		world.exploration.interact()
		world.player.teleport_to(world.exploration.interior.instances[door["uid"]].position)
		world.exploration.interact()
		check(doc.object(first)["interior"]["objects"].filter(func(item:Dictionary)->bool:return item["uid"]==door["uid"])[0].get("open",false) and not world.objects.visible, "Studio interior door edits persist without exposing exterior geometry: " + mode)
		world.exploration.leave_interior()
		studio.set_walking(false)
		check(collision_layers(world.instances[exterior_door["uid"]]) == door_layers and collision_layers(world.instances[hidden["uid"]]) == hidden_layers, "Walking room exits preserve exterior physics state: " + mode)
		doc.undo()
		studio.changed()
		var history_size: int = doc.undo_history.size()
		var redo_size: int = doc.redo_history.size()
		studio.interior_tools.start(first)
		studio.interior_tools.leave()
		check(doc.undo_history.size() == history_size and doc.redo_history.size() == redo_size, "An unchanged editing visit preserves city undo and redo: " + mode)
		doc.object(first)["interior"]["night"] = true
		studio.changed()
		var export_path: String = "user://persistent_room_export_"+mode+".tscn"
		check(Exporter.save_scene(world,doc.data,studio.library,export_path)==OK, "City exports include owned room data: " + mode)
		var exported: Node = load(export_path).instantiate()
		root.add_child(exported)
		var exploration: Node = exported.exploration
		var actor: Node = exported.player
		actor.set_physics_process(false)
		for repetition in 2:
			actor.teleport_to(exploration.entrance(exploration.instances[first]))
			var outside: Variant = actor.position
			exploration.interact()
			check(exploration.interior != null and exploration.interior_uid == first, "Export enters the correct building: " + mode)
			check(exploration.interior.instances.size() == initial_count+2 and exploration.interior.data_state["objects"].any(func(item:Dictionary)->bool:return item.get("name","") == "Only in the first room"), "Export renders the saved room furnishings on each visit: " + mode)
			if mode == "2d":
				check(exploration.interior.lighting == exported.get_node("Lighting") and exported.get_node("Lighting").color.is_equal_approx(Color(.48,.55,.78)), "2D interiors use one canvas light with their own saved night state")
			else:
				check(exported.find_children("*","WorldEnvironment",false,false)[0].environment == null and exploration.interior.sun.light_energy < 1, "3D interiors use their own environment and saved night lighting")
			check(not exported.get_node("Objects").visible and exploration.instances[first].visible, "Exterior roots hide while object visibility state stays intact: " + mode)
			if "--capture" in OS.get_cmdline_user_args() and mode == "3d" and repetition == 0:
				studio.visible = false
				for i in 10: await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://output/exported_owned_interior_3d.png")
				studio.visible = true
			actor.teleport_to(exploration.interior.instances[door["uid"]].position)
			exploration.interact()
			check(exploration.interior.data_state["objects"].filter(func(item:Dictionary)->bool:return item["uid"]==door["uid"])[0].get("open",false), "Doors operate inside saved interiors: " + mode)
			exploration.interact()
			check(not exploration.interior.data_state["objects"].filter(func(item:Dictionary)->bool:return item["uid"]==door["uid"])[0].get("open",false), "Interior door states can close again: " + mode)
			actor.teleport_to(exploration.exit_position)
			exploration.interact()
			check(exploration.interior == null and actor.position == outside and exported.get_node("Objects").visible, "Room exit restores exterior and player position: " + mode)
			if mode == "2d": check(exported.get_node("Lighting").color == Color.WHITE, "Leaving a 2D room restores exterior daylight")
			else: check(exported.find_children("*","WorldEnvironment",false,false)[0].environment != null, "Leaving a 3D room restores the exterior environment")
		exported.free()
		doc.checkpoint()
		doc.data["objects"].erase(doc.object(first))
		studio.changed()
		doc.undo()
		studio.changed()
		check(doc.object(first).get("interior",{}).get("objects",[]).size() == initial_count+2 and world.exploration.records == doc.data["objects"], "Deleting and undoing a building restores its owned contents and current interaction records: " + mode)
		studio.interior_tools.start(first)
		studio.switch_mode("3d" if mode == "2d" else "2d")
		check(not studio.interior_tools.editing() and studio.interior_tools.root_document(mode).data["objects"].any(func(item:Dictionary)->bool:return item["uid"]==first and item.has("interior")), "Changing dimensions commits the room and restores the city document: " + mode)
		DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(export_path)
	studio.free()
	print("PERSISTENT INTERIORS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func collision_layers(node: Node) -> Array:
	var result: Array = []
	for body in [node] + node.find_children("*","CollisionObject2D",true,false) + node.find_children("*","CollisionObject3D",true,false):
		if body is CollisionObject2D or body is CollisionObject3D: result.append(body.collision_layer)
	return result
