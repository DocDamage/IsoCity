extends SceneTree
const Actions = preload("res://scripts/character_actions.gd")
const OUTPUT = "res://output/verification/asset_expansion/I06"
var checks: int = 0
var failures: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; print("FAIL: " + message)

func _initialize() -> void: call_deferred("run")

func settle() -> void:
	for frame in 8: await process_frame

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var library: RefCounted = preload("res://scripts/builder/asset_library.gd").new()
	var families: int = 0; var actual_runs: int = 0; var fallback_runs: int = 0
	for id in library.assets:
		var data: Dictionary = library.assets[id]["data"]
		if data.get("kind") != "char" or data.get("animations", {}).is_empty(): continue
		families += 1
		var actor: Node = load(library.assets[id]["path"]).instantiate(); root.add_child(actor)
		await process_frame
		var semantics: Dictionary = Actions.for_asset(id)
		check(semantics.has("idle") and semantics.has("walk") and semantics.has("run"), "Reviewed semantic actions exist: " + id)
		for action in ["idle", "walk", "run"]:
			actor.action = action; actor._apply_direction()
			var expected: Dictionary = data["animations"][semantics[action]["clip"]]
			check(actor.authored_animation.current["directions"] == expected["directions"], "Semantic action selects the reviewed clip: " + action + "/" + id)
			check(float(actor.authored_animation.current["fps"]) == float(expected["fps"]), "Supplied cadence is retained")
			for direction in expected["directions"]:
				actor.direction = direction; actor._apply_direction(); actor._update_animation(.1)
				var sprite: Sprite2D = actor.get_node("Sprite2D")
				check(sprite.hframes == int(expected["directions"][direction]["frames"]) and sprite.frame >= 0 and sprite.frame < sprite.hframes, "Every supplied facing uses complete bounded source frames")
		if semantics["run"].has("fallback"):
			fallback_runs += 1; check(str(actor.get_meta("animation_fallback", "")).contains("walk"), "Missing run is reported as a walk fallback")
		else: actual_runs += 1
		actor.action = "sit"; actor._apply_direction()
		check(actor.authored_animation.current["directions"] == data["animations"][semantics["idle"]["clip"]]["directions"] and str(actor.get_meta("animation_fallback", "")).contains("No supported sit"), "Unsupported seating never chooses an attack or arbitrary source clip")
		var sprite: Sprite2D = actor.get_node("Sprite2D"); var before_frame: int = sprite.frame
		actor._update_animation(NAN); actor._update_animation(-1)
		check(sprite.frame == before_frame, "Invalid time cannot advance the actor")
		actor.move_character(1.0 / 60, Vector2.RIGHT); actor.move_character(.25, Vector2.ZERO)
		check(actor.action == "idle" and actor.velocity.is_zero_approx(), "Stopping actual movement restores idle")
		var originals: Dictionary = actor.authored_animation.clips
		actor.authored_animation.clips = originals.duplicate(true)
		var broken: Dictionary = actor.authored_animation.clips[semantics["walk"]["clip"]]
		for view in broken["directions"].values(): view["file"] = "res://output/verification/asset_expansion/I06/missing-source.png"
		actor.action = "walk"; actor._apply_direction(); actor._update_animation(.2)
		check(str(actor.get_meta("animation_fallback", "")).contains("unavailable") and actor.authored_animation.current_view.get("file", "") != "res://output/verification/asset_expansion/I06/missing-source.png", "Missing action art uses a safe idle fallback rather than advancing mismatched frames")
		actor.authored_animation.clips = originals
		actor.free(); await process_frame
	check(families == 9 and actual_runs == 4 and fallback_runs == 5, "All nine families have reviewed genuine or explicitly fallback running")
	check(library.assets["3d:Supplemental_SWAT/SWAT_K9_Dog_Sit"]["data"]["animation_status"] == "posed_mesh" and library.assets["3d:Supplemental_SWAT/SWAT_Pose_Kneel_Aim"]["data"]["supplied_clips"].is_empty(), "Reviewed SWAT/K9 poses are static poses, not animation")
	await workflow()
	print("Character actions: %d checks, %d failures" % [checks, failures]); quit(1 if failures else 0)

func select_action(browser: RefCounted, action: String) -> void:
	for index in browser.preview_actions.item_count:
		var choice: Dictionary = browser.preview_actions.get_item_metadata(index)
		if choice.get("kind") == "semantic" and choice.get("action") == action:
			browser.preview_actions.select(index); browser.preview_actions.item_selected.emit(index); return
	check(false, "Preview action is exposed: " + action)

func workflow() -> void:
	var studio: Control = load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled = false; root.add_child(studio)
	while not studio.enhancements_ready: await process_frame
	var browser: RefCounted = studio.asset_browser
	var before: Dictionary = studio.current().data.duplicate(true); var history: int = studio.current().undo_history.size()
	browser.show_asset("2d:Office_Worker"); select_action(browser, "walk")
	check(browser.frames == 4 and browser.frame_origin.x == 2 * browser.frame_size.x and browser.ground_marker.visible, "Native walk preview selects source frames 2–5 and shows ground contact")
	browser.playback_speed.value = 2; browser.tick(.1)
	check(browser.frame.value > 0, "Playback speed changes actual preview progress")
	browser.play.button_pressed = false; var stopped: float = browser.frame.value; browser.tick(.25)
	check(browser.frame.value == stopped, "Preview can pause")
	browser.frame.value = 2
	check(browser.atlas.region.position.x == browser.frame_origin.x + 2 * browser.frame_size.x, "Action-local scrubbing maps to the correct original atlas frame")
	select_action(browser, "sit")
	check(browser.frames == 1 and not browser.play.visible and browser.frame_origin.x == 6 * browser.frame_size.x, "Static seating pose is one frame rather than a fake animation")
	browser.show_asset("2d:Supplemental_Characters_Blue_robot_IdleAim_32743945_Character"); select_action(browser, "run")
	check(browser.details.text.contains("walk fallback") and browser.frames > 1, "Preview describes a missing run honestly")
	browser.tick(NAN); browser.tick(-1)
	check(is_finite(browser.elapsed), "Invalid preview time leaves a finite clock")
	for index in browser.preview_actions.item_count:
		var choice: Dictionary = browser.preview_actions.get_item_metadata(index)
		if choice.get("kind") == "source" and choice.get("action") == "standingshoot":
			browser.preview_actions.select(index); browser.preview_actions.item_selected.emit(index)
			check(browser.frames > 1, "Standalone source actions remain inspectable separately from supported runtime actions")
			break
	browser.dialog.hide()
	browser.show_asset("2d:Supplemental_Characters_Blue_robot_IdleAim_32743945_Character")
	var data: Dictionary = studio.library.assets[browser.selected_id]["data"]
	var original_clip: Dictionary = data["animations"]["standingshoot"]
	data["animations"]["standingshoot"] = original_clip.duplicate(true)
	for view in data["animations"]["standingshoot"]["directions"].values(): view["file"] = "res://output/verification/asset_expansion/I06/missing-preview.png"
	for index in browser.preview_actions.item_count:
		var choice: Dictionary = browser.preview_actions.get_item_metadata(index)
		if choice.get("kind") == "source" and choice.get("action") == "standingshoot": browser.preview_actions.select(index); browser.preview_actions.item_selected.emit(index); break
	check(browser.atlas == null and not browser.play.button_pressed and browser.frame_note.text.contains("unavailable"), "Missing preview source is explained and releases the previous animation")
	data["animations"]["standingshoot"] = original_clip; browser.dialog.hide()
	check(not browser.valid_preview_view({"file":"res://image.png", "frames":NAN}, {}, {"frames":1}) and not browser.valid_preview_view({"file":"res://image.png", "region":"broken"}, {}, {"frames":1}), "Corrupt frame counts and regions are rejected before slicing")
	check(not browser.valid_preview_view({"file":"res://image.png", "origin":[true, 1]}, {}, {"frames":1}), "Corrupt contact points cannot break the ground marker")
	check(browser.picture.texture == null and browser.character_picture.texture == null and browser.atlas == null and studio.current().data == before and studio.current().undo_history.size() == history, "Closing action inspection releases preview resources and leaves the city/history untouched")
	studio.free(); await process_frame; await process_frame
