extends SceneTree

const Plan = preload("res://scripts/builder/harbor_plan.gd")
const Tools = preload("res://scripts/builder/harbor_tools.gd")
const Document = preload("res://scripts/builder/document.gd")
const Templates = preload("res://scripts/builder/templates.gd")
const Economy = preload("res://scripts/builder/economy_plan.gd")
const Portable = preload("res://scripts/builder/portable_export.gd")
const OUTPUT = "res://output/verification/asset_expansion/N14/"
var studio: Control
var checks: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + message)
	return ok

func settle() -> void:
	for frame in 7: await process_frame
	await physics_frame

func capture(file: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await settle()
	for frame in 6: await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUTPUT + file + ".png") == OK, "Saved visual verification " + file)

func setup(mode: String) -> RefCounted:
	studio.switch_mode(mode)
	var doc := Document.new()
	doc.data = Templates.make(mode, "blank")
	studio.documents[mode] = doc
	studio.economy_tools.pauses[mode] = true
	studio.changed()
	return doc

func sail_to(runtime: Node, target: Vector2) -> bool:
	for step in 450:
		var point: Vector2 = runtime.boats["pilot"]["point"]
		if point.distance_to(target) < .32:
			for brake in 18: runtime.steer(.05, Vector2.ZERO, true)
			return runtime.boats["pilot"]["point"].distance_to(target) < .6
		runtime.steer(.05, (target - point).normalized())
	return false

func block_landing(mode: String, world: Node, runtime: Node) -> Node:
	var landing: Vector2 = Vector2(11, -1.35)
	if mode == "2d":
		var body := StaticBody2D.new()
		var collision := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(12, 10)
		collision.shape = box
		body.add_child(collision)
		world.get_node("Objects").add_child(body)
		body.position = runtime.world_point(landing)
		return body
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(.8, 1.0, .8)
	collision.shape = box
	body.add_child(collision)
	world.get_node("Objects").add_child(body)
	body.position = runtime.world_point(landing, .5)
	return body

func assert_walk(mode: String, doc: RefCounted, world: Node, original: Dictionary) -> void:
	var runtime: Node = world.exploration.harbor
	var pilot: Dictionary = runtime.boats.get("pilot", {})
	if not check(not pilot.is_empty() and runtime.boats.has("shuttle"), mode + " both real boats appear in Walk: " + str(runtime.network.get("reason", ""))): return
	check(runtime.claims == {"harbor_west": "pilot", "harbor_east": "shuttle"},
		mode + " distinct dock claims are acquired at the authored start")
	check(not world.instances["harbor_pilot"].visible and pilot["visual"].is_visible_in_tree(),
		mode + " mobile artwork replaces its static duplicate only during preview")
	check("Board" in world.exploration.prompt(), mode + " near dry dock presents boarding prompt")
	world.exploration.interact()
	if not check(runtime.active() and not world.player.visible and world.player.collision_layer == 0, mode + " Interact boards from dry land"): return
	check(not world.exploration.walk_allowed(), mode + " walking is suspended while piloting")
	var manual_input: Callable = world.exploration.driving.control_input
	world.exploration.driving.control_input = func(action: String) -> bool: return action == "move_right"
	runtime._physics_process(.05)
	world.exploration.driving.control_input = manual_input
	check(pilot["velocity"].length() > 0 and pilot["wake"].visible, mode + " mapped movement steers and draws a wake")
	if not check(sail_to(runtime, Vector2(6, 1)), mode + " real boat sails along channel"): return
	for step in 8: runtime.steer(.05, Vector2.RIGHT)
	await capture("steering_" + mode)
	for step in 18: runtime.steer(.05, Vector2.ZERO, true)
	world.exploration.interact()
	check(runtime.active() and "free dock" in runtime.notice, mode + " open water never offers unsafe disembarking")
	check(not runtime.claims.has("harbor_west") and runtime.metric(world.player.global_position).distance_to(pilot["point"]) < .02,
		mode + " leaving a berth releases it and camera target follows the boat")
	if not check(sail_to(runtime, Vector2(11, 1)), mode + " pilot reaches another dock"): return
	runtime.claims["harbor_south"] = "shuttle"
	world.exploration.interact()
	check(runtime.active(), mode + " an occupied berth prevents docking")
	runtime.release("harbor_south", "shuttle")
	var obstruction: Node = block_landing(mode, world, runtime)
	await settle()
	world.exploration.interact()
	check(runtime.active(), mode + " a live physics obstruction on the dry landing keeps the rider aboard")
	obstruction.free()
	await settle()
	world.exploration.interact()
	check(not runtime.active() and world.player.visible and runtime.claims.get("harbor_south") == "pilot", mode + " Interact docks and restores walking")
	check(runtime.metric(world.player.global_position).distance_to(Vector2(11, -1.35)) < .1 and world.terrain_traversal.safe_position(world.player.global_position),
		mode + " disembark position is verified dry land")
	await capture("walk_" + mode)
	world.exploration.interact()
	if not check(runtime.active(), mode + " the manual boat can be boarded again at its new berth"): return
	var detour: bool = sail_to(runtime, Vector2(6.2, 1)) and sail_to(runtime, Vector2(6.2, 11)) and sail_to(runtime, Vector2(11, 11))
	if not check(detour, mode + " steering takes the pilot around the island to the north pier"): return
	world.exploration.interact()
	check(not runtime.active() and runtime.claims.get("harbor_north") == "pilot", mode + " pilot occupies the ferry's destination")
	runtime.wait = 0
	runtime.service(.1)
	check(runtime.shuttle_path.is_empty() and runtime.boats["shuttle"]["point"].is_equal_approx(Vector2(17, 1)), mode + " scheduled ferry waits for the real occupied destination")
	world.exploration.interact()
	if not check(runtime.active() and sail_to(runtime, Vector2(13.5, 11)) and sail_to(runtime, Vector2(13.5, 8.4)), mode + " pilot releases the destination and leaves the ferry lane"): return
	for step in 900:
		runtime.service(.05)
		if step == 75: await capture("ferry_" + mode)
		if runtime.crossings == 1: break
	check(runtime.crossings == 1 and runtime.boats["shuttle"]["dock"] == "harbor_north" and not runtime.claims.has("harbor_east"),
		mode + " scheduled ferry follows the route, arrives and releases its origin")
	runtime.wait = 0
	for step in 900:
		runtime.service(.05)
		if runtime.crossings == 2: break
	check(runtime.crossings == 2 and runtime.boats["shuttle"]["dock"] == "harbor_east" and not runtime.claims.has("harbor_north"),
		mode + " ferry makes its scheduled return")
	check(doc.data == original, mode + " steering, disembark and schedules leave authored data and treasury exact")
	check(runtime.active(), mode + " pilot remains aboard until the terrain edit")
	doc.checkpoint()
	doc.data["water_cells"] = []
	studio.changed()
	doc.finish_checkpoint()
	runtime._physics_process(.05)
	check(runtime.claims.is_empty() and runtime.boats.is_empty() and not runtime.active() and world.player.visible,
		mode + " draining the harbor clears claims and restores the player safely")
	check(world.terrain_traversal.safe_position(world.player.global_position), mode + " invalidated trip returns to a dry location")
	studio.set_walking(false)
	await settle()
	check(world.instances["harbor_pilot"].visible and not world.get_node("Objects").has_node("HarborPilot"),
		mode + " stopping restores authored boat and frees preview artwork")
	studio._command("undo", null)
	check(doc.data == original, mode + " undo restores the exact navigable harbor")
	world.player.teleport_to(runtime.world_point(Vector2(2.7, -1.35), .025))
	studio.set_walking(true)
	runtime._physics_process(.05)
	await settle()
	world.exploration.interact()
	check(runtime.active(), mode + " restored harbor can board again before a world switch")
	studio.switch_mode("3d" if mode == "2d" else "2d")
	await settle()
	check(runtime.claims.is_empty() and runtime.boats.is_empty() and not runtime.active(),
		mode + " switching worlds clears both boats and every dock claim")
	studio.switch_mode(mode)

func exercise(mode: String) -> void:
	var doc: RefCounted = setup(mode)
	var tools: RefCounted = studio.harbor_tools
	studio._command("harbors", null)
	await settle()
	check(tools.panel.is_visible_in_tree() and tools.practice.has_focus(), mode + " Harbors opens and focuses the first action")
	check(not Plan.enabled(doc.data) and not tools.enabled.button_pressed, mode + " harbor preview defaults off")
	doc.data["economy"] = {"enabled": true, "starting_cash": 0, "refund_percent": 40, "period_seconds": 300}
	doc.data["economy_account"] = Economy.fresh_account(doc.data, studio.library)
	var blank: Dictionary = doc.data.duplicate(true)
	tools.practice.pressed.emit()
	check(doc.data == blank and "Insufficient" in tools.status.text, mode + " practice construction follows the treasury budget")
	doc.data["economy"]["starting_cash"] = 10000
	doc.data["economy_account"] = Economy.fresh_account(doc.data, studio.library)
	var quote: Dictionary = Economy.quote(doc.data, Tools.practice_layout(doc.data), studio.library)
	tools.practice.pressed.emit()
	if not check(Plan.enabled(doc.data) and doc.data["objects"].size() == 6, mode + " practice harbor builds through Studio: " + tools.status.text): return
	check(doc.data["economy_account"] == quote["account"], mode + " construction pays the exact economy quote once")
	check("Pilot boat ready" in tools.describe(doc.data, doc.data["harbor"]) and "Ferry route ready" in tools.describe(doc.data, doc.data["harbor"]),
		mode + " the installed boat and pier artwork leave usable connections")
	studio.set_tool("select")
	studio.selected_uid = "harbor_north"
	studio.selected_uids.assign(["harbor_north"])
	tools.refresh()
	check(not tools.dock_remove.disabled and not tools.dock_apply.disabled and is_equal_approx(tools.offsets[0].value, -1.6), mode + " selecting a pier loads authored dock offsets")
	var original: Dictionary = doc.data.duplicate(true)
	tools.dock_remove.pressed.emit()
	check(doc.data["harbor"]["destination"].is_empty(), mode + " removing a pier's dock releases its route reference")
	studio._command("undo", null)
	check(doc.data == original, mode + " undo restores saved offsets and route")
	studio.selected_uid = "harbor_north"
	studio.selected_uids.assign(["harbor_north"])
	studio.duplicate_selection()
	doc.finish_checkpoint()
	check(doc.data["objects"].size() == 7 and doc.data["harbor"] == original["harbor"],
		mode + " duplicating a pier leaves the original dock identity and route assignments")
	studio._command("undo", null)
	check(doc.data == original, mode + " Undo restores duplicated-pier construction spending")
	var world: Node = studio.worlds[mode]
	var harbor: Node = world.exploration.harbor
	if "--capture" in OS.get_cmdline_user_args():
		for simple in [true, false]:
			studio.consumer_shell.set_active(simple, false)
			for compact in [false, true]:
				root.size = Vector2i(960, 640) if compact else Vector2i(1480, 900)
				studio.accessibility_settings.text_scale = 1.5 if compact else 1.0
				studio.accessibility_settings.high_contrast = compact
				studio.accessibility_settings.large_targets = compact
				studio.accessibility_settings.apply()
				studio._command("harbors", null)
				await settle()
				check(tools.status.has_focus() and tools.panel.follow_focus, mode + " validation text follows keyboard focus")
				check(not compact or tools.enabled.custom_minimum_size.y >= 44, mode + " compact targets reach 44 pixels")
				await capture("author_" + mode + ("_simple" if simple else "_precision") + ("_960" if compact else "_1480"))
		studio.consumer_shell.set_active(true, false)
		root.size = Vector2i(1480, 900)
		studio.accessibility_settings.text_scale = 1.0
		studio.accessibility_settings.high_contrast = false
		studio.accessibility_settings.large_targets = false
		studio.accessibility_settings.apply()
	studio.set_walking(true)
	await settle()
	harbor.set_physics_process(false)
	await assert_walk(mode, doc, world, original)
	if studio.walking: studio.set_walking(false)
	harbor.set_physics_process(true)
	if "--capture" not in OS.get_cmdline_user_args():
		var restricted: String = ""
		for id in studio.library.assets:
			if studio.library.assets[id]["data"].get("source_export_allowed", true) == false:
				restricted = id
				break
		if check(not restricted.is_empty(), mode + " real restricted source is available for the negative export fixture"):
			var blocked: Dictionary = doc.data.duplicate(true)
			blocked["objects"].append(Document.placement_item("restricted_fixture", restricted,
				Plan.Traffic.world(Vector2(-10, -8), mode), str(studio.library.directions(restricted)[0]), 1.0))
			var denied: Dictionary = Portable.new().save(world, blocked, studio.library, OUTPUT + "denied_" + mode + ".zip")
			check(not denied["ok"] and "restricts redistributing" in str(denied["message"])
				and not FileAccess.file_exists(OUTPUT + "denied_" + mode + ".zip"),
				mode + " harbor export enforces the existing restricted source policy")
		if "--keep-verified-export" in OS.get_cmdline_user_args(): return
		check(studio.write_project(OUTPUT + "harbor_" + mode + ".isocity.json"), mode + " harbor configuration saves")
		var portable: Dictionary = Portable.new().save(world, doc.data, studio.library, OUTPUT + "harbor_" + mode + ".zip")
		check(portable["ok"], mode + " allowed harbor package exports: " + str(portable.get("reason", "")))

func run() -> void:
	root.size = Vector2i(1480, 900)
	studio = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	while not studio.enhancements_ready: await process_frame
	studio.consumer_shell.dismiss_welcome()
	for mode in ["2d", "3d"]: await exercise(mode)
	studio.free()
	await settle()
	print("HARBOR WORKFLOW: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
