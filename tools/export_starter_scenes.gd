extends SceneTree

const Templates = preload("res://scripts/builder/templates.gd")
const Exporter = preload("res://scripts/builder/exporter.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var studio: Control = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	await process_frame
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://scenes/examples")
	for dimension in ["2d", "3d"]:
		for kind in ["blank", "room", "city"]:
			var data: Dictionary = Templates.make(dimension, kind)
			studio.worlds[dimension].apply(data)
			var path: String = "res://scenes/examples/%s_%s.tscn" % [kind, dimension]
			var result: Error = Exporter.save_scene(studio.worlds[dimension], data, studio.library, path)
			if result != OK:
				printerr("Could not export ", path)
				quit(1)
				return
			print("Created ", path)
	studio.queue_free()
	await process_frame
	quit()
