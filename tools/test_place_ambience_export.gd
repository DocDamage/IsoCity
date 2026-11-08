extends SceneTree

const Plan = preload("res://scripts/builder/ambience_plan.gd")
const Bank = preload("res://scripts/builder/ambience_bank.gd")
var scene: Node
var checks: int
var failures: int

func _initialize() -> void: call_deferred("run")

func check(ok: bool, description: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: "+description)
	return ok

func mix(frames: int = 180) -> void:
	for frame in frames: scene._process(1.0/60)

func sounds(kind: String) -> Array:
	return scene.ambience.selected.filter(func(value: Dictionary)->bool: return value["kind"] == kind)

func at(point: Vector2) -> void:
	var world: Array = Plan.Traffic.world(point,scene.dimension,.08)
	scene.player.teleport_to(Vector2(world[0],world[1]) if scene.dimension == "2d" else Vector3(world[0],world[1],world[2]))
	await physics_frame

func run() -> void:
	scene = load("res://city.tscn").instantiate()
	root.add_child(scene)
	for frame in 8: await process_frame
	scene.walking = true
	scene._set_mode()
	scene.player.set_physics_process(false)
	scene.businesses.set_physics_process(false)
	var village: Node = scene.exploration.village
	village.set_physics_process(false)
	for kind in Plan.KINDS:
		var stream: AudioStreamWAV = Bank.stream(kind)
		check(stream != null and stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.loop_end == 176400,
			"The independent city loads native PCM for "+kind)
	var saved: Dictionary = scene.studio_data.duplicate(true)
	await at(Vector2(40,0))
	mix()
	var shore: Array = sounds("harbor")
	check(shore.size() == 1 and shore[0]["range"] == 18 and shore[0]["position"].y > .75,
		"The independently authored shore override uses the saved range and water elevation.")
	scene.businesses.hour = 12
	scene.businesses.step(.016,false)
	await at(Vector2(0,0))
	mix()
	check(scene.businesses.market.active.has("market") and sounds("market").size() == 1,
		"Actual portable market opening creates one localized voice.")
	scene.businesses.hour = 2
	scene.businesses.step(.016,false)
	mix()
	check(sounds("market").is_empty(),"Portable market closes and releases its audio.")
	if check(village.book.sites.has("smith") and not village.book.sites["smith"]["points"].is_empty(),"Portable smith retains a valid approach."):
		scene.player.teleport_to(scene.player.get_parent().to_local(village.position(village.book.sites["smith"]["points"][0])))
		await physics_frame
		scene.exploration.interact()
		if check(village.selected == "smith","E opens the independently placed smith."):
			village.view.buttons["forge"].pressed.emit()
			village.close()
			village.step(.25)
			mix()
			check(sounds("workshop").size() == 1 and village.book.batches.has("smith"),"The portable craft batch starts its actual spatial loop.")
			for frame in 56: village.step(.25)
			mix()
			check(sounds("workshop").is_empty(),"Completing portable production retires its audio.")
	check(scene.studio_data == saved,"Independent audio, market and crafting do not modify the authored city.")
	scene.ambience.reset()
	scene.free()
	OS.delay_msec(120)
	await process_frame
	print("PORTABLE PLACE AMBIENCE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
