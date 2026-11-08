extends "res://tools/test_school_life.gd"

const Audio = preload("res://scripts/builder/ambience_plan.gd")
const Probe = preload("res://tools/ambience_audio_probe.gd")
const OUTPUT = "res://output/verification/asset_expansion/I18"

func run() -> void:
	output = OUTPUT
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	studio = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	while not studio.enhancements_ready: await process_frame
	if studio.consumer_shell: studio.consumer_shell.dismiss_welcome()
	for mode in ["2d","3d"]: await workflow(mode)
	studio.ambience_tools.reset()
	studio.free()
	OS.delay_msec(120)
	await process_frame
	print("SCHOOL AMBIENCE: %d checks, %d failures" % [count,failures])
	quit(1 if failures else 0)

func capture_room(mode: String, manager: Node, world: Node) -> void:
	var ambience: RefCounted = studio.ambience_tools
	var runtime: Node = ambience.managers[mode]
	var visit: Node = world.exploration
	if not visit.interior: return
	var job: Dictionary = manager.activities.scheduler.jobs.values().filter(func(value: Dictionary)->bool:
		return value["state"] == "service").front()
	var point: Vector3 = job["position"]
	world.player.teleport_to(Vector2(point.x,point.y)+Vector2(8,12) if mode == "2d" else point+Vector3(0,0,1.15))
	await settle()
	for frame in 100: ambience.tick(1.0/60)
	var emitted: Array = runtime.selected.filter(func(value: Dictionary)->bool: return value["kind"] == "school")
	check(not emitted.is_empty() and emitted.size() <= Audio.PLACE_VOICES and emitted.all(func(value: Dictionary)->bool:
		return value["uid"].begins_with("room:"+visit.interior_uid+":ground:")),
		"Physically occupied desks sound only on the actual classroom floor "+mode)
	if "--audio-proof" in OS.get_cmdline_user_args():
		check(await Probe.record(studio,"school",OUTPUT+"/runtime_school_"+mode+".wav") == OK,
			"Record the actual isolated classroom bus from seated pupils "+mode)
	manager.paused = true
	for frame in 180: ambience.tick(1.0/60)
	check(runtime.selected.all(func(value: Dictionary)->bool: return value["kind"] != "school") and
		runtime.voices.values().all(func(value: Dictionary)->bool: return value["kind"] != "school"),
		"Pausing resident simulation fades the classroom voices "+mode)
	manager.paused = false
	for frame in 110: ambience.tick(1.0/60)
	check(runtime.selected.any(func(value: Dictionary)->bool: return value["kind"] == "school"),"Resuming returns the seated classroom ambience "+mode)
