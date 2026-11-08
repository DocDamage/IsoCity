extends SceneTree

const Plan = preload("res://scripts/builder/arcade_plan.gd")
const Props = preload("res://scripts/builder/prop_plan.gd")
const Race = preload("res://scripts/builder/arcade_sprint.gd")
const Signals = preload("res://scripts/builder/arcade_signals.gd")
var scene: Node
var checks: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + message)

func frames(count: int) -> void:
	for frame in count: await physics_frame

func key(code: int) -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame

func open_game(id: String) -> bool:
	var walk: Node = scene.exploration
	var runtime: Node = walk.arcade
	var context: Dictionary = Props.context(walk)
	for item in context["data"]["objects"]:
		if Plan.game(item) != id: continue
		var candidate: Dictionary = runtime.candidate(item,context)
		if candidate.is_empty(): return false
		var point: Variant = Props.ground_point(candidate,walk,"approach")
		scene.player.teleport_to(scene.player.get_parent().to_local(point))
		await frames(4)
		await key(KEY_E)
		if runtime.session.get("game") != id: return false
		await key(KEY_E)
		return runtime.session.get("phase") == "playing"
	return false

func finish() -> void:
	scene.free()
	await process_frame
	print("PORTABLE ARCADE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func run() -> void:
	scene = load("res://city.tscn").instantiate()
	root.add_child(scene)
	await frames(8)
	var walk: Node = scene.exploration
	var runtime: Node = walk.arcade
	var host: String = scene.studio_data["objects"][0]["uid"]
	check(Plan.enabled(scene.studio_data) and runtime.boards.is_empty() and not runtime.active(),
		"The standalone project starts with authored games and a fresh leaderboard.")
	scene.walking = true
	scene._set_mode()
	scene.player.set_physics_process(false)
	scene.player.teleport_to(walk.entrance(scene.city_instances[host]))
	await frames(4)
	await key(KEY_E)
	await frames(8)
	check(walk.interior_uid==host,"The normal player enters the actual exported arcade.")
	if walk.interior_uid != host: await finish(); return
	scene.player.set_physics_process(false)
	var race: bool = await open_game("sprint")
	check(race and runtime.game is Control,"Exported input opens and starts the racer.")
	if not race: await finish(); return
	await key(KEY_D)
	for index in Race.COURSE.size():
		var difference: int = Race.COURSE[index].y-runtime.game.lane
		for shift in absi(difference):
			runtime.view.directions["move_right" if difference>0 else "move_left"].pressed.emit()
		for frame in Race.GAP+6:
			if runtime.game.section>index: break
			await physics_frame
	check(runtime.last_result.get("score")==3200 and runtime.session.get("phase")=="result",
		"Real physics frames drive the complete race and score its gates.")
	await key(KEY_ESCAPE)
	check(not runtime.active() and scene.walking and runtime.locks.is_empty(),
		"Escape restores standalone exploration and frees the cabinet.")
	var sequence: bool = await open_game("signals")
	check(sequence and runtime.game.stage=="watch","Exported input opens the separate signal game.")
	if not sequence: await finish(); return
	for index in Signals.PATTERNS.size():
		var pattern: Array = Signals.PATTERNS[index]
		for frame in pattern.size()*Signals.SLOT_TICKS+6:
			if runtime.game.stage=="reply": break
			await physics_frame
		for direction in pattern: runtime.view.directions[Signals.ACTIONS[direction]].pressed.emit()
		await frames(1)
	check(runtime.last_result.get("score")==4300 and runtime.session.get("phase")=="result"
		and runtime.boards.get("signals",[]).size()==1 and runtime.boards.get("sprint",[]).size()==1,
		"Real-time prompts and input submit the expected separate game scores.")
	await key(KEY_ESCAPE)
	check(not runtime.active() and not runtime.view.overlay.visible and scene.walking,
		"Leaving the second game restores the original view.")
	await finish()
