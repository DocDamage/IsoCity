extends SceneTree

const Bounds = preload("res://scripts/model_bounds.gd")

func option(name: String, fallback: String = "") -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var index: int = args.find(name)
	return args[index + 1] if index >= 0 and index + 1 < args.size() else fallback

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Model preview rendering needs a display renderer; use the preparation tool for GIF fallback.")
		quit(1)
		return
	var jobs: Array = []
	var job_path: String = option("--jobs")
	if not job_path.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(job_path))
		if not parsed is Array:
			printerr("Preview jobs must be a JSON array")
			quit(1)
			return
		jobs = parsed
	else:
		var packs: PackedStringArray = DirAccess.get_directories_at("res://scenes/items_3d")
		packs.sort()
		for pack in packs:
			if not option("--pack").is_empty() and pack != option("--pack"): continue
			var files: PackedStringArray = DirAccess.get_files_at("res://scenes/items_3d/" + pack)
			files.sort()
			for file in files:
				if not file.ends_with(".tscn"): continue
				var folder: String = option("--output-dir", "res://resources/previews_3d").path_join(pack)
				jobs.append({"scene": "res://scenes/items_3d/" + pack + "/" + file, "output": folder.path_join(file.get_basename() + ".png")})
	if jobs.is_empty():
		printerr("No model preview jobs selected")
		quit(1)
		return
	var renderer: RefCounted=preload("res://scripts/builder/model_thumbnail.gd").new(self)
	var count: int=0;var failures: int=0
	for job in jobs:
		if not job is Dictionary or not job.get("scene") is String or not job.get("output") is String:failures+=1;continue
		var image: Image=await renderer.render(job["scene"])
		if not image:printerr("Preview render failed: ",job["scene"]," ",renderer.error);failures+=1;continue
		var result: Error=renderer.write_validated(image,job["output"])
		if result!=OK:printerr("Preview failed: ",job["output"]," ",error_string(result));failures+=1
		else:count+=1
	renderer.cancel();await process_frame
	print("Rendered ",count," model previews; ",failures," failures");quit(1 if failures else 0)
