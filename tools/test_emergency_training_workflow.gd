extends SceneTree

const Plan = preload("res://scripts/builder/emergency_training_plan.gd")
const Document = preload("res://scripts/builder/document.gd")
const Templates = preload("res://scripts/builder/templates.gd")
const Economy = preload("res://scripts/builder/economy_plan.gd")
const Portable = preload("res://scripts/builder/portable_export.gd")
const OUTPUT = "res://output/verification/asset_expansion/N19/"
var studio: Control
var checks: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, text: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + text)
	return ok

func settle() -> void:
	for frame in 8: await process_frame
	await physics_frame

func capture(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	await settle()
	for frame in 6: await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUTPUT + name + ".png") == OK, "Saved native capture " + name)

func setup(mode: String) -> RefCounted:
	studio.switch_mode(mode)
	var doc := Document.new()
	doc.data = Templates.make(mode, "blank")
	studio.documents[mode] = doc
	studio.economy_tools.pauses[mode] = true
	studio.changed()
	return doc

func move_to(runtime: Node, role: String) -> void:
	var step: Dictionary = runtime.plan["steps"][role]
	var player: Node = runtime.exploration.player
	var pos: Variant = runtime.world_point(step["point"], step["height"] + .025)
	player.teleport_to(player.get_parent().to_local(runtime.world().to_global(pos)))
	if runtime.exploration.dimension == "2d": player.set_meta("terrain_height", step["height"])

func perform(runtime: Node, role: String, description: String) -> bool:
	move_to(runtime, role)
	await settle()
	var walk: Node = runtime.exploration
	if not check(walk.prompt().contains("E ·") and walk.nearby.has("emergency"), description + " exposes the actual interaction"): return false
	studio.control_settings.execute("interact")
	return true

func response(runtime: Node, mode: String, id: String) -> bool:
	var service: Node = runtime.services
	for frame in 12000:
		service.step(1.0 / 60)
		runtime._process(1.0 / 60)
		if frame == 260:
			await capture("dispatch_" + mode + "_" + id)
		if runtime.response_returned or runtime.phase == "failed": break
	return runtime.response_returned

func exercise(mode: String, id: String) -> void:
	var doc: RefCounted = setup(mode)
	var ui: RefCounted = studio.scenario_tools
	studio._command("challenges", id)
	await settle()
	check(ui.drill_fields.is_visible_in_tree() and ui.choice.has_focus(), mode + " " + id + " opens directly in Challenges")
	doc.data["economy"] = {"enabled": true, "starting_cash": 0, "refund_percent": 40, "period_seconds": 300}
	doc.data["economy_account"] = Economy.fresh_account(doc.data, studio.library)
	var blank: Dictionary = doc.data.duplicate(true)
	ui.build_drill()
	check(doc.data == blank and "Insufficient" in studio.status.text, mode + " practice setup observes the existing budget")
	doc.data["economy"]["starting_cash"] = 30000
	doc.data["economy_account"] = Economy.fresh_account(doc.data, studio.library)
	var draft: Dictionary = Plan.practice(doc.data, studio.library, id, "quote")
	var quote: Dictionary = Economy.quote(doc.data, draft["data"], studio.library)
	ui.build_drill()
	if not check(doc.data.get("scenario", {}).get("id") == id, mode + " " + id + " practice creates a valid drill: " + studio.status.text): return
	check(doc.data["economy_account"] == quote["account"], mode + " layout construction charges the exact once-only quote")
	check(ui.station_value(ui.drill_choices["desk"]) == doc.data["scenario"]["desk"] and ui.station_value(ui.drill_choices["subject"]) == doc.data["scenario"]["subject"],
		mode + " practice saves the actual dispatch desk and participant references")
	var world: Node = studio.worlds[mode]
	var runtime: Node = world.exploration.emergency
	var service: Node = runtime.services
	service.set_physics_process(false)
	runtime.set_process(false)
	await settle()
	if "--capture" in OS.get_cmdline_user_args():
		for simple in [true, false]:
			studio.consumer_shell.set_active(simple, false)
			for compact in [false, true]:
				root.size = Vector2i(960, 640) if compact else Vector2i(1480, 900)
				studio.accessibility_settings.text_scale = 1.5 if compact else 1.0
				studio.accessibility_settings.high_contrast = compact
				studio.accessibility_settings.large_targets = compact
				studio.accessibility_settings.apply()
				studio._command("challenges", id)
				await settle()
				check(ui.choice.has_focus() and ui.panel.follow_focus and (not compact or ui.choice.custom_minimum_size.y >= 44),
					mode + " " + id + " choice has accessible focus and target size")
				await capture("setup_" + mode + "_" + id + ("_simple" if simple else "_precision") + ("_960" if compact else "_1480"))
		studio.consumer_shell.set_active(true, false)
		root.size = Vector2i(1480, 900)
		studio.accessibility_settings.text_scale = 1.0
		studio.accessibility_settings.high_contrast = false
		studio.accessibility_settings.large_targets = false
		studio.accessibility_settings.apply()
	var original: Dictionary = doc.data.duplicate(true)
	var previous_receipts: int = runtime.receipts.size()
	studio.set_walking(true)
	world.player.set_physics_process(false)
	await settle()
	if not check(runtime.phase == "dispatch" and runtime.plan.get("ok"), mode + " initialized at the dispatch stage: " + runtime.notice): return
	if not await perform(runtime, "desk", mode + " " + id + " dispatch"): return
	if not check(runtime.dispatched and runtime.job.get("training") == original["scenario"]["attempt"],
		mode + " dispatch submits a request owned by this attempt: " + runtime.notice): return
	service.step(.2)
	check(runtime.job["station"] == original["scenario"]["station"] and service.crews.has(runtime.job["id"]),
		mode + " uses the selected station's actual vehicle and crew: " + runtime.job["reason"])
	if id == "medical_drill":
		if not await perform(runtime, "kit", mode + " collect training kit"): return
		check(runtime.kit_collected and runtime.phase == "perimeter", "Medical drill requires and records a real kit interaction")
	for index in original["scenario"]["perimeter"].size():
		if not await perform(runtime, "perimeter_%d" % index, mode + " secure perimeter point %d" % (index + 1)): return
	check(runtime.secured == original["scenario"]["perimeter"].size() and runtime.phase == "subject" and runtime.markers.get_child_count() > 1,
		mode + " field markers visibly record the secured perimeter")
	if not await perform(runtime, "subject", mode + " " + id + " participant"): return
	check(runtime.assisted and runtime.phase == "return", mode + " interacting beside the supplied participant records the assistance")
	await capture("field_" + mode + "_" + id)
	if not await perform(runtime, "desk", mode + " wait for the returning response"): return
	check(runtime.phase == "return" and runtime.receipts.size() == previous_receipts, mode + " desk cannot close a drill before the assigned crew returns")
	if not check(await response(runtime, mode, id), mode + " " + id + " real crew finishes its road and walking circuit: " + runtime.notice + " " + str(runtime.job.get("reason", ""))): return
	if not await perform(runtime, "desk", mode + " complete " + id): return
	check(runtime.phase == "complete" and runtime.progress()["complete"] and runtime.receipts.size() == previous_receipts + 1, mode + " the desk issues one completion receipt")
	world.exploration.interact()
	check(runtime.receipts.size() == previous_receipts + 1 and doc.data == original, mode + " repeat interactions cannot award twice or change the city treasury")
	studio.set_walking(false)
	doc.checkpoint()
	if id == "fire_drill":
		doc.data["objects"].erase(doc.object(original["scenario"]["subject"]))
	else:
		var site: Dictionary = doc.object(original["scenario"]["incident"])
		var point: Vector2 = Plan.Service.Traffic.metric(site["position"], mode)
		site["position"] = Plan.Service.Traffic.world(point + Vector2(.25, 0), mode)
	studio.changed()
	doc.finish_checkpoint()
	check(runtime.phase == "failed" and not runtime.progress()["complete"] and runtime.receipts.size() == previous_receipts + 1,
		mode + " editing the completed " + ("participant" if id == "fire_drill" else "incident approach") + " invalidates the goals")
	studio._command("undo", null)
	check(doc.data == original and runtime.plan["ok"] and runtime.phase == "failed", mode + " undo restores the setup and requires a fresh run")
	ui.start_challenge()
	await settle()
	check(doc.data["scenario"]["attempt"] != original["scenario"]["attempt"] and runtime.phase == "dispatch",
		mode + " the existing Restart action opens a new clean attempt")
	studio.set_walking(true)
	if not await perform(runtime, "desk", mode + " dispatch restarted attempt"): return
	var blocked: Dictionary = runtime.job
	service.step(.2)
	doc.checkpoint()
	doc.data["roads"] = []
	studio.changed()
	doc.finish_checkpoint()
	check(runtime.phase == "failed" and blocked["state"] == "cancelled" and not service.crews.has(blocked["id"]),
		mode + " editing the response road cancels the in-flight training request")
	studio._command("undo", null)
	studio.set_walking(false)
	ui.start_challenge()
	await settle()
	studio.set_walking(true)
	if not await perform(runtime, "desk", mode + " dispatch before restart"): return
	var replaced: Dictionary = runtime.job
	service.step(.2)
	ui.start_challenge()
	await settle()
	check(replaced["state"] == "cancelled" and runtime.phase == "dispatch" and not service.crews.has(replaced["id"]),
		mode + " restarting mid-dispatch clears the old crew and issues a fresh attempt")
	studio.set_walking(true)
	if not await perform(runtime, "desk", mode + " dispatch before stop"): return
	var issued: Dictionary = runtime.job
	service.step(.2)
	ui.stop_challenge()
	check(issued.get("state") == "cancelled" and runtime.attempt.is_empty() and not service.crews.has(issued["id"]),
		mode + " stopping mid-dispatch releases only the training vehicle and its claims")
	studio.set_walking(false)
	world.player.set_physics_process(true)
	service.set_physics_process(true)
	runtime.set_process(true)
	studio._command("undo", null)
	await settle()
	check(doc.data.get("scenario", {}).get("id") == id and runtime.phase == "dispatch", mode + " undo restores the authored drill after stop")
	if "--capture" not in OS.get_cmdline_user_args():
		var name: String = "drill_" + mode + "_" + id
		var path: String = OUTPUT + name + ".isocity.json"
		var expected: Dictionary = doc.data.duplicate(true)
		check(studio.write_project(path), mode + " saves authored drills")
		var exported: Dictionary = Portable.new().save(world, doc.data, studio.library, OUTPUT + name + ".zip")
		check(exported["ok"], mode + " portable exports retain the actual dispatch art: " + exported.get("message", ""))
		if mode == "3d" and id == "fire_drill":
			var swat: String = "3d:Supplemental_SWAT/SWAT_Pose_Hand_Signal"
			doc.checkpoint()
			var participant: Dictionary = doc.object(expected["scenario"]["subject"])
			participant["asset"] = swat
			participant["direction"] = str(studio.library.directions(swat)[0])
			studio.changed()
			doc.finish_checkpoint()
			var pose: Node = world.instances[participant["uid"]]
			check(runtime.plan["ok"] and pose.find_children("*", "AnimationPlayer", true, false).all(func(animation: Node) -> bool: return not animation.is_playing()),
				"The compatible SWAT participant remains a real, static supplied pose")
			var denied: Dictionary = Portable.new().save(world, doc.data, studio.library, OUTPUT + "restricted_swat.zip")
			check(not denied["ok"] and "restricts redistributing" in denied["message"]
				and not FileAccess.file_exists(OUTPUT + "restricted_swat.zip"),
				"Existing SWAT source restrictions block the opted-in artwork export")
			studio._command("undo", null)
			check(doc.data == expected, "Undo restores the fully exportable practice participant")
		check(studio.load_project(path), mode + " opens the saved challenge in Studio")
		await settle()
		var restored: Dictionary = studio.current().data
		check(restored["scenario"] == expected["scenario"] and Economy.normalized_account(restored["economy_account"]) == expected["economy_account"]
			and runtime.phase == "dispatch" and runtime.receipts.is_empty(),
			mode + " load restores authored drill and budget with fresh local progress")

func run() -> void:
	root.size = Vector2i(1480, 900)
	studio = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	while not studio.enhancements_ready: await process_frame
	studio.consumer_shell.dismiss_welcome()
	for mode in ["2d", "3d"]:
		for id in ["fire_drill", "medical_drill"]:
			await exercise(mode, id)
	studio.free()
	await settle()
	print("EMERGENCY TRAINING WORKFLOW: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
