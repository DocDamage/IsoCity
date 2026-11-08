extends SceneTree

const Templates = preload("res://scripts/builder/templates.gd")
const Economy = preload("res://scripts/builder/economy_plan.gd")
const Floors = preload("res://scripts/builder/floor_plan.gd")
const Connector = preload("res://scripts/builder/connector_plan.gd")
const Repair = preload("res://scripts/builder/project_repair.gd")
const Export = preload("res://scripts/builder/exporter.gd")
const Portable = preload("res://scripts/builder/portable_export.gd")
const Share = preload("res://scripts/builder/creation_share.gd")
const OUTPUT = "res://output/verification/asset_expansion/N18"
const OUTLINE = [[-4,-4], [4,-4], [4,4], [-4,4]]

var studio: Control
var tools: RefCounted
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + message)

func settle() -> void:
	for frame in 8: await process_frame
	await physics_frame

func click_corner(corner: Array) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = studio.worlds["3d"].camera.unproject_position(Vector3(corner[0],0,corner[1]))
	studio._canvas_input(event)
	event.pressed = false
	studio._canvas_input(event)

func outline(corners: Array, canvas: bool = false) -> void:
	tools.draw_button.pressed.emit()
	for corner in corners:
		if canvas: click_corner(corner)
		else:
			tools.x.value = corner[0]
			tools.z.value = corner[1]
			tools.add_button.pressed.emit()
	tools.close_button.pressed.emit()

func opening(key: String, kind: int) -> bool:
	for index in tools.bays.item_count:
		if tools.bays.get_item_metadata(index) != key: continue
		tools.bays.select(index)
		tools.bays.item_selected.emit(index)
		tools.kinds.select(kind)
		tools.opening_button.pressed.emit()
		return true
	return false

func walk(player: Node3D, start: Vector3, direction: Vector3, frames: int) -> Vector3:
	player.set_physics_process(false)
	player.teleport_to(start)
	for frame in frames:
		await physics_frame
		player.move_character(1.0 / 60.0, direction)
	return player.position

func capture() -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	for simple in [false, true]:
		studio.consumer_shell.set_active(simple,false)
		studio.consumer_shell.dismiss_welcome()
		for size in [Vector2i(1480,900), Vector2i(960,640)]:
			root.size = size
			studio.accessibility_settings.restore({"text_scale":1.5,"high_contrast":true,"large_targets":true} if size.x == 960 else {})
			if size.x == 960: studio.workspace_layout.library_toggle.button_pressed = false
			studio._command("modular_rooms",null)
			await settle()
			if tools.reviewed.is_empty(): tools.review_button.pressed.emit()
			var world: Node3D = studio.worlds["3d"]
			world.distance = 17 if size.x == 1480 else (20 if simple else 16)
			world.target = world.camera.global_basis.x * (4.0 if size.x == 1480 else 4.7) if simple else Vector3.ZERO
			world.update_camera()
			tools.apply_button.grab_focus()
			await settle()
			check(tools.apply_button.has_focus() and Rect2(Vector2.ZERO,Vector2(size)).encloses(tools.apply_button.get_global_rect()),
				"Build review is reachable with the keyboard at " + str([simple,size]))
			RenderingServer.force_draw(false)
			RenderingServer.force_draw(false)
			var path: String = OUTPUT + "/review_%s_%d.png" % ["simple" if simple else "precision",size.x]
			check(root.get_texture().get_image().save_png(path) == OK,"Captured the review and proposed geometry.")
			tools.apply_button.release_focus()
	studio.accessibility_settings.restore({})
	root.size = Vector2i(1480,900)
	studio.consumer_shell.set_active(false,false)
	studio._command("modular_rooms",null)
	await settle()

func run() -> void:
	studio = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	while not studio.enhancements_ready: await process_frame
	tools = studio.modular_building_tools
	studio.switch_mode("2d")
	studio._command("modular_rooms",null)
	check(tools.draw_button.disabled and tools.message.text.contains("native geometry"),"Pixel world shows why the native kit is unavailable.")
	studio.switch_mode("3d")
	var city: RefCounted = studio.current()
	city.data = Templates.make("3d","blank")
	city.data["economy"] = {"enabled":true,"starting_cash":0}
	studio.changed()
	studio._command("modular_rooms",null)
	await settle()
	outline(OUTLINE,true)
	check(not tools.drawing and tools.request["outline"] == OUTLINE,"The normal canvas inputs draw and close the orthogonal outline. " + str(tools.request["outline"]))
	check(opening("x/0/4",1) and opening("x/0/-4",2),"The wall bay controls place an open doorway and a window.")
	tools.review_button.pressed.emit()
	check(tools.reviewed.is_empty() and tools.message.text.contains("Insufficient construction budget"),"Unaffordable reviews report why nothing was built.")
	city.data["economy"] = {"enabled":true,"starting_cash":50000}
	city.data.erase("economy_account")
	studio.changed()
	tools.review_button.pressed.emit()
	check(not tools.reviewed.is_empty() and is_instance_valid(tools.ghosts) and city.data["objects"].is_empty(),
		"Review shows the exact geometry without editing the document. " + tools.message.text)
	if tools.reviewed.is_empty():
		studio.free()
		quit(1)
		return
	var reviewed_price: int = tools.reviewed["quote"]["construction"]
	await capture()
	city.data["title"] = "A city changed after review"
	tools.apply_button.pressed.emit()
	check(tools.reviewed.is_empty() and city.data["objects"].is_empty() and tools.message.text.contains("Review again"),
		"Apply refuses a stale layout after a document edit.")
	tools.review_button.pressed.emit()
	var before: Dictionary = city.data.duplicate(true)
	var history: int = city.undo_history.size()
	tools.apply_button.pressed.emit()
	check(city.data.get("modular_rooms",[]).size() == 1 and city.data["objects"].size() == 24 and city.undo_history.size() == history + 1,
		"Build commits the whole reviewed room in one edit.")
	check(Economy.account(city.data,studio.library)["construction_total"] == reviewed_price,
		"Actual construction charges exactly the reviewed quote.")
	var built: Dictionary = city.data.duplicate(true)
	studio._command("undo",null)
	check(city.data == before,"Undo removes all modules and restores the treasury.")
	studio._command("redo",null)
	check(city.data == built,"Redo restores the exact room, joints and treasury.")
	studio._command("modular_rooms",null)
	tools.rooms.select(1)
	tools.rooms.item_selected.emit(1)
	var saved_door: String = built["modular_rooms"][0]["owned"]["x/0/4"]["uid"]
	outline([[-4,-4],[8,-4],[8,4],[-4,4]])
	tools.review_button.pressed.emit()
	tools.apply_button.pressed.emit()
	check(city.data["objects"].size() > 24 and city.data["modular_rooms"][0]["owned"]["x/0/4"]["uid"] == saved_door,
		"Redrawing an existing room resizes it while preserving its doorway identity. " + tools.message.text)
	studio._command("undo",null)
	check(city.data == built,"The editor reverses a resize in one action.")
	for item in city.data["objects"]: studio.selected_uids.append(item["uid"])
	studio.duplicate_selection()
	var duplicate_links: Array = city.data["connections"].filter(func(link: Dictionary) -> bool: return link not in built["connections"])
	check(duplicate_links.size() == 8 and duplicate_links.all(func(link: Dictionary) -> bool:
		return link["from"]["object_uid"] in studio.selected_uids and link["to"]["object_uid"] in studio.selected_uids)
		and Connector.retained(city.data,city.data["connections"]) == city.data["connections"],
		"Ordinary duplication preserves the copied module joints with entirely new endpoints.")
	studio._command("undo",null)
	check(city.data == built,"Undo removes the copied parts and their joints together.")
	var save_path: String = OUTPUT + "/reviewed_room.isocity.json"
	check(studio.write_project(save_path,false),"Normal project save writes the room.")
	var repair: RefCounted = Repair.new(studio.library)
	var reopened: Dictionary = repair.read(save_path)
	check(reopened["ok"] and repair.issues.is_empty() and reopened["content"]["documents"]["3d"]["modular_rooms"].size() == 1,
		"Normal reopening keeps ownership and all modules without repair warnings.")
	var damaged: Dictionary = city.data.duplicate(true)
	damaged["modular_rooms"][0]["owned"] = []
	var recovered: Dictionary = Repair.new(studio.library).world(damaged,"3d","modular_room_fixture",0)
	check(recovered["objects"].size() == 24 and recovered["modular_rooms"].is_empty(),
		"Repair archives unreadable outlines while keeping the actual modules.")
	var world: Node3D = studio.worlds["3d"]
	var through: Vector3 = await walk(world.player,Vector3(0,.05,5.2),Vector3.FORWARD,35)
	var stopped: Vector3 = await walk(world.player,Vector3(1.3,.05,5.2),Vector3.FORWARD,35)
	check(through.z < 3.8 and stopped.z > 4.0,"The player crosses the doorway and stops at the adjacent solid wall. " + str([through,stopped]))
	var path: String = OUTPUT + "/reviewed_room.tscn"
	check(Export.save_scene(world,city.data,studio.library,path) == OK,"Playable scene export saves the modular room.")
	var blocked: Dictionary = Portable.new().save(world,city.data,studio.library,OUTPUT + "/restricted_sources.zip")
	check(not blocked["ok"] and blocked["message"].contains("restricts redistributing") and not FileAccess.file_exists(OUTPUT+"/restricted_sources.zip"),
		"Portable export continues to enforce the wall pack's supplied restriction.")
	var image := Image.create_empty(800,500,false,Image.FORMAT_RGB8)
	var metadata: Dictionary = {"title":"Modular room fixture","author":"IsoCity verification","description":"","license":"Fixture layout","source_url":"","kind":"city"}
	var shared: Dictionary = Share.prepare({"kind":"city","document":city.data},metadata,image,studio.library)
	var inspected: Dictionary = Share.inspect(shared.get("creation",{}),studio.library)
	check(inspected.get("ok",false) and inspected["missing"].is_empty()
		and inspected["source"]["document"]["modular_rooms"] == JSON.parse_string(JSON.stringify(city.data["modular_rooms"]))
		and inspected["creation"]["requirements"].any(func(entry: Dictionary) -> bool: return entry["pack"] == "HanX SWAT"),
		"Layout sharing retains procedural ownership and declares the separately installed wall pack.")
	var exported: Node3D = load(path).instantiate()
	root.add_child(exported)
	await settle()
	through = await walk(exported.player,Vector3(0,.05,5.2),Vector3.FORWARD,35)
	stopped = await walk(exported.player,Vector3(1.3,.05,5.2),Vector3.FORWARD,35)
	check(exported.studio_data["modular_rooms"].size() == 1 and through.z < 3.8 and stopped.z > 4.0,
		"Exported scene preserves authored metadata and collision through the doorway. " + str([through,stopped]))
	exported.free()
	await owned_floor(city)
	studio.free()
	await process_frame
	print("MODULAR BUILDING WORKFLOW: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func owned_floor(city: RefCounted) -> void:
	var host: String = "3d:HanX_City/Cafe_Small"
	city.data = Templates.make("3d","blank")
	var building: Dictionary = city.add(host,[0.0,0.0,0.0],"0",1)
	var uid: String = building["uid"]
	studio.changed()
	studio.interior_tools.start(uid,"ground","empty")
	if not studio.interior_tools.editing():
		check(false,"A building opens its owned interior.")
		return
	var doc: RefCounted = studio.current()
	doc.data["objects"] = []
	studio.changed()
	studio._command("modular_rooms",null)
	outline([[-4,-4],[8,-4],[8,4],[-4,4]])
	opening("x/0/4",1)
	tools.review_button.pressed.emit()
	tools.apply_button.pressed.emit()
	check(doc.data.get("modular_rooms",[]).size() == 1,"A modular shell commits through the canonical owned ground floor. " + tools.message.text)
	var floors: RefCounted = studio.interior_tools.floor_tools
	floors.new_name.text = "Upper modular room"
	floors.new_height.value = 3
	floors.add_floor()
	var upper: String = doc.floor_uid
	var links: RefCounted = floors.connections
	links.show()
	links.start_x.value = -1
	links.start_z.value = 0
	links.end_x.value = 4
	links.end_z.value = 0
	links.width.value = 1.2
	links.apply_record()
	links.dialog.hide()
	studio._command("modular_rooms",null)
	outline([[-4,-4],[8,-4],[8,4],[-4,4]])
	opening("x/0/4",1)
	opening("x/4/-4",2)
	tools.review_button.pressed.emit()
	tools.apply_button.pressed.emit()
	var state: Dictionary = doc.canonical.data
	check(Floors.room(state,"ground").get("modular_rooms",[]).size() == 1 and Floors.room(state,upper).get("modular_rooms",[]).size() == 1,
		"Both linked floors retain their independently authored modular outlines. " + tools.message.text)
	check(state.get("floor_links",[]).size() == 1 and state["floor_links"][0]["upper"] == upper,
		"The standard stairs workflow owns the real upper cutout.")
	studio.interior_tools.leave()
	var world: Node3D = studio.worlds["3d"]
	studio.set_walking(true)
	await settle()
	world.player.teleport_to(world.exploration.entrance(world.instances[uid]))
	world.exploration.interact()
	await settle()
	if not world.exploration.interior:
		check(false,"Normal exploration enters the building to reach the modular floors.")
	else:
		var position: Vector3 = await walk(world.player,Vector3(-2.0,.05,0),Vector3.RIGHT,155)
		check(world.exploration.active_floor() == upper and position.y >= 2.95 and world.player.recovery_count == 0,
			"The player ascends through the cutout in the assembled floor. " + str(position))
	studio.set_walking(false)
	var path: String = OUTPUT + "/linked_modular_floors.tscn"
	check(Export.save_scene(world,city.data,studio.library,path) == OK,"Linked modular floors export through the ordinary playable scene path.")
	var exported: Node3D = load(path).instantiate()
	root.add_child(exported)
	await settle()
	exported.player.teleport_to(exported.exploration.entrance(exported.city_instances[uid]))
	exported.exploration.interact()
	await settle()
	if not exported.exploration.interior:
		check(false,"The exported building can be entered.")
	else:
		var position: Vector3 = await walk(exported.player,Vector3(-2.0,.05,0),Vector3.RIGHT,155)
		check(exported.exploration.active_floor() == upper and position.y >= 2.95 and exported.player.recovery_count == 0,
			"Exported stairs and clipped modular floor remain traversable. " + str(position))
	exported.free()
