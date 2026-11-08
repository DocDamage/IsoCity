extends SceneTree

const Plan = preload("res://scripts/builder/space_outpost_plan.gd")
const Document = preload("res://scripts/builder/document.gd")
const Templates = preload("res://scripts/builder/templates.gd")
const Economy = preload("res://scripts/builder/economy_plan.gd")
const Portable = preload("res://scripts/builder/portable_export.gd")
const OUTPUT = "res://output/verification/asset_expansion/N20/"
var studio: Control
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + message)
	return ok

func settle() -> void:
	for frame in 6: await process_frame
	await physics_frame

func capture(label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	await settle()
	for frame in 3: await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUTPUT + label + ".png") == OK, "Saved " + label)

func phase(runtime: Node, name_value: String, limit: int = 1000) -> bool:
	for frame in limit:
		if runtime.job.get("phase") == name_value: return true
		await physics_frame
	return false

func exercise(mode: String) -> void:
	studio.switch_mode(mode)
	var doc := Document.new()
	doc.data = Templates.make(mode, "blank")
	studio.documents[mode] = doc
	studio.economy_tools.pauses[mode] = true
	studio.changed()
	studio._command("space_outpost", null)
	await settle()
	var tools: RefCounted = studio.outpost_tools
	check(tools.panel.is_visible_in_tree() and tools.practice.has_focus(), mode + " inspector opens with keyboard focus")
	check(not tools.enabled.button_pressed and Plan.required(doc.data).is_empty(), mode + " ordinary city remains idle")
	doc.data["economy"] = {"enabled": true, "starting_cash": 0, "refund_percent": 40, "period_seconds": 300}
	doc.data["economy_account"] = Economy.fresh_account(doc.data, studio.library)
	var blank: Dictionary = doc.data.duplicate(true)
	tools.practice.pressed.emit()
	check(doc.data == blank and "Insufficient" in tools.status.text, mode + " insufficient funds preserve the blank city")
	doc.data["economy"]["starting_cash"] = 10000
	doc.data["economy_account"] = Economy.fresh_account(doc.data, studio.library)
	var proposal: Dictionary = Plan.practice(doc.data, studio.library)
	var quote: Dictionary = Economy.quote(doc.data, proposal["data"], studio.library)
	tools.practice.pressed.emit()
	if not check(Plan.settings(doc.data)["enabled"], mode + " build practice outpost through the normal entry point: " + tools.status.text): return
	check(doc.data["economy_account"] == quote["account"], mode + " exact construction quote")
	var built: Dictionary = doc.data.duplicate(true)
	studio._command("undo", null)
	check(not Plan.settings(doc.data)["enabled"] and doc.data["objects"].is_empty(), mode + " undo rolls back the complete outpost")
	studio._command("redo", null)
	check(doc.data == built, mode + " redo preserves identities and funds")
	tools.orbital.set_pressed_no_signal(true)
	tools.apply.pressed.emit()
	check(Plan.settings(doc.data)["orbital"], mode + " optional satellite settings save")
	if "--capture" in OS.get_cmdline_user_args():
		for simple in [true, false]:
			for compact in [false, true]:
				root.size = Vector2i(960, 640) if compact else Vector2i(1480, 900)
				studio.consumer_shell.set_active(simple, false)
				studio.accessibility_settings.text_scale = 1.5 if compact else 1.0
				studio.accessibility_settings.high_contrast = compact
				studio.accessibility_settings.large_targets = compact
				studio.accessibility_settings.apply()
				studio._command("space_outpost", null)
				await settle()
				check(tools.status.has_focus() and tools.panel.follow_focus and (not compact or tools.apply.custom_minimum_size.y >= 44),
					mode + " inspector has keyboard focus, visible scrolling and larger compact targets")
				await capture("setup_%s_%s_%s" % [mode, "simple" if simple else "precision", "960" if compact else "1480"])
		root.size = Vector2i(1480, 900)
		studio.consumer_shell.set_active(true, false)
		studio.accessibility_settings.text_scale = 1.0
		studio.accessibility_settings.high_contrast = false
		studio.accessibility_settings.large_targets = false
		studio.accessibility_settings.apply()
		await settle()
	var world: Node = studio.worlds[mode]
	var runtime: Node = world.exploration.outpost
	var dock: Dictionary = Plan.inspect(doc.data, studio.library)["docks"]["outpost_dock"]
	var player: Node = world.player
	player.teleport_to(runtime.draw_point(dock["stand"], dock["stand_height"] + (.025 if mode == "3d" else 0.0)))
	studio.set_walking(true)
	await settle()
	check(studio.walking and world.terrain_traversal.safe_position(player.global_position), mode + " Walk starts safely beside the dock")
	if not check(await phase(runtime, "arrival", 200), mode + " schedule launches a real prepared ship"): return
	check(runtime.job["ship"].is_visible_in_tree() and runtime.leases.current("space_outpost:outpost_dock")["token"] == runtime.job["token"],
		mode + " arrival owns the dock before moving")
	check(runtime.leases.acquire("space_outpost:outpost_dock", self) == 0, mode + " second claimant cannot overlap the dock")
	check(is_instance_valid(runtime.orbital), mode + " optional satellite appears separately")
	check(is_instance_valid(runtime.guides) and "Arriving" in world.exploration.prompt(),
		mode + " the ground guides and Walk status identify the actual arrival")
	player.teleport_to(runtime.draw_point(dock["berth"], .025 if mode == "3d" else 0.0))
	check(await phase(runtime, "abort", 240), mode + " occupied approach triggers an actual go-around")
	player.teleport_to(runtime.draw_point(dock["stand"], .025 if mode == "3d" else 0.0))
	if not check(await phase(runtime, "arrival", 500), mode + " a fresh ship retries after go-around"): return
	check(runtime.job["profile"]["asset"] == Plan.definitions()["ships"][1]["asset"], mode + " rotates to second scheduled hull")
	await capture("arrival_" + mode)
	if not check(await phase(runtime, "docked", 450), mode + " vessel lands at its assigned site"): return
	check(is_instance_valid(runtime.job["contact"]) and runtime.job["point"].is_equal_approx(dock["berth"]) and is_zero_approx(runtime.job["lift"]),
		mode + " grounded hull has a bounded walk collision")
	await physics_frame
	var travel: Variant = runtime.draw_point(dock["berth"], dock["height"] + (.025 if mode == "3d" else 0.0)) - player.position
	check(player.test_move(player.global_transform, travel), mode + " actual walking movement is blocked at the grounded hull")
	await capture("docked_" + mode)
	check(await phase(runtime, "unloading", 160) and is_instance_valid(runtime.job.get("cargo")), mode + " actual supply crate moves off the ship")
	await capture("unloading_" + mode)
	check(await phase(runtime, "departure", 380) and runtime.staged.has("outpost_dock"), mode + " supplies stay at the cargo staging point")
	await capture("departure_" + mode)
	for frame in 300:
		if runtime.job.is_empty(): break
		await physics_frame
	check(runtime.completed == 1 and runtime.job.is_empty() and runtime.leases.current("space_outpost:outpost_dock").is_empty(),
		mode + " completed delivery releases ownership and hull")
	check(doc.data["economy_account"] == quote["account"] and doc.data["objects"].size() == 3,
		mode + " simulation leaves the shared authored objects and treasury intact")
	studio.set_walking(false)
	await settle()
	check(runtime.staged.is_empty() and not is_instance_valid(runtime.orbital) and not is_instance_valid(runtime.guides)
		and not world.get_node("Objects").has_node("SupplyShip"),
		mode + " leaving Walk frees staged crates, orbital art and the ship")
	var source: Dictionary = doc.data.duplicate(true)
	if "--capture" not in OS.get_cmdline_user_args():
		var package: Dictionary = Portable.new().save(world, source, studio.library, OUTPUT + "outpost_" + mode + ".zip")
		check(package["ok"], mode + " package includes all allowed scheduled art: " + str(package.get("message", "")))
		if mode == "3d":
			var restricted: Dictionary = source.duplicate(true)
			restricted["objects"].append(Document.placement_item("restricted_outpost_prop", "3d:Supplemental_SWAT/SWAT_Pose_Hand_Signal",
				[-20, 0, -8], "0", 1.0))
			var denied_path: String = OUTPUT + "restricted_outpost.zip"
			var denied: Dictionary = Portable.new().save(world, restricted, studio.library, denied_path)
			check(not denied["ok"] and "restricts redistributing" in denied["message"] and not FileAccess.file_exists(denied_path),
				"Existing export restrictions also apply to an enabled space outpost")
	studio.set_walking(true)
	if not check(await phase(runtime, "arrival", 200), mode + " schedule resumes after returning to Walk"): return
	doc.checkpoint()
	doc.object("outpost_dock")["visible"] = false
	studio.changed()
	doc.finish_checkpoint()
	await settle()
	check(runtime.job.is_empty() and runtime.leases.current("space_outpost:outpost_dock").is_empty() and runtime.network["docks"].is_empty(),
		mode + " hiding the dock cancels arrival and releases ownership")
	studio.set_walking(false)
	studio._command("undo", null)
	check(doc.data == source and Plan.inspect(doc.data, studio.library)["docks"].has("outpost_dock"),
		mode + " undo restores the exact authored dock and treasury")
	var path: String = OUTPUT + "outpost_" + mode + ("_native" if "--capture" in OS.get_cmdline_user_args() else "") + ".isocity.json"
	check(studio.write_project(path), mode + " saves the outpost through Studio")
	var expected: Dictionary = doc.data.duplicate(true)
	check(studio.load_project(path), mode + " saved project reopens")
	await settle()
	var restored: Dictionary = studio.current().data
	check(restored["space_outpost"] == expected["space_outpost"], mode + " authored settings persist with the same integer values")
	check(Economy.normalized_account(restored["economy_account"]) == expected["economy_account"], mode + " treasury persists")
	check(runtime.job.is_empty(), mode + " runtime jobs are local after reopen")

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
	print("SPACE OUTPOST WORKFLOW: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
