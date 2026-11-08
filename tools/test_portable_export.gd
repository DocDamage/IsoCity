extends SceneTree

var checks: int = 0
var failures: int = 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; print("FAIL: " + message)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var studio: Control = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	for i in 5: await process_frame
	studio._command("export_portable",null)
	check(studio.file_action == "export_portable" and studio.file_dialog.visible and studio.file_dialog.filters[0].contains("*.zip"),"Portable action opens ZIP save dialog")
	if "--capture" in OS.get_cmdline_user_args():
		for i in 4: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://output/editor_portable_export.png")
	studio.file_dialog.hide()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output/portable"))
	var exporter: RefCounted = preload("res://scripts/builder/portable_export.gd").new()
	for mode in ["2d","3d"]:
		studio.switch_mode(mode)
		var doc: RefCounted = studio.current()
		var building: Dictionary = doc.data["objects"][0]
		building["interior"] = preload("res://scripts/builder/templates.gd").make(mode,"room")
		building["interior"]["title"] = "My portable room"
		building["interior"]["night"] = true
		var room: Dictionary = building["interior"]
		var mixed: String = "3d:HanX_Park/Bench_Park" if mode == "2d" else "2d:Sofa_Teal"
		var record: Dictionary = {"uid":"portable_mixed","asset":mixed,"position":[40,20,0] if mode == "2d" else [2,0,2],"direction":"90" if mode == "2d" else "NE","scale":1.2}
		room["objects"].append(record)
		preload("res://scripts/builder/repair_assets.gd").register(studio.library)
		var missing: Dictionary = doc.add("2d:__missing_object__",[80,50,0] if mode == "2d" else [5,0,5],"SE")
		missing["missing_asset"] = {"asset":"2d:Removed","original":{"texture":"res://assets/archived_missing_texture.png"}}
		doc.add(mixed,[160,80,0] if mode == "2d" else [7,0,7],record["direction"])
		var painted: Dictionary = doc.add("2d:Park_Bench",[190,90,0] if mode == "2d" else [9,0,7],"SW")
		painted["uid"] = "portable_painted"
		doc.add("2d:Added_animated_boat_9ee9b341",[250,110,0] if mode == "2d" else [13,0,8],"SE",0.5)
		preload("res://scripts/builder/roads.gd").paint(doc.data,Vector2i(2,2),Vector2i(3,2),false,{"style":"brick","width":2,"sidewalks":true})
		studio.worlds[mode].apply(doc.data)
		var parts: GDScript = preload("res://scripts/builder/part_colors.gd")
		var sprite: Sprite2D = parts.sprite_for(studio.worlds[mode].instances[painted["uid"]])
		var texture: Texture2D = parts.base_texture(sprite)
		var pattern: Dictionary = preload("res://scripts/builder/tile_patterns.gd").from_asset(studio.library,"2d:Gravel")
		var pixels: Array = []
		var picture: Image = texture.get_image()
		for y in picture.get_height():
			for x in picture.get_width():
				if picture.get_pixel(x,y).a > 0.9: pixels.append(y * picture.get_width() + x)
		painted["colors"] = [{"kind":"pixels","texture":texture.resource_path,"pixels":pixels,"frame":sprite.frame,"color":[0.2,0.7,0.9,1],"pattern":pattern}]
		if mode == "2d":
			room["tiles"][0]["direction"] = "45"
			room["tiles"][0]["colors"] = [{"kind":"pixels","texture":preload("res://scripts/builder/tile_patterns.gd").from_asset(studio.library,room["tiles"][0]["asset"])["texture"],"pixels":[0],"color":[0.7,0.2,0.9,1],"pattern":pattern}]
		studio.worlds[mode].apply(doc.data)
		var before: Dictionary = doc.data.duplicate(true)
		var destination: String = "res://output/portable/" + mode + ".zip"
		var result: Dictionary = exporter.save(studio.worlds[mode],doc.data,studio.library,destination)
		check(result["ok"],"Export complete " + mode + ": " + result["message"])
		check(doc.data == before,"Export preserves source document " + mode)
		if not result["ok"]: continue
		var zip := ZIPReader.new()
		check(zip.open(destination) == OK,"ZIP readable " + mode)
		var names: PackedStringArray = zip.get_files()
		for required in ["project.godot","city.tscn","city-source.json","README.txt","export-manifest.json","scripts/builder/world_2d.gd","scripts/builder/world_3d.gd","assets/pixel_isometric/LICENSE.txt"]:
			check(names.has(required),"Package contains " + required + " " + mode)
		check(not names.has("scenes/builder.tscn") and not names.has("scripts/builder/studio.gd"),"Runtime package excludes editor " + mode)
		for name in names:
			check(not name.begins_with(".godot/") and not name.is_absolute_path() and not ".." in name.split("/"),"Safe independent package entry " + name)
		var manifest: Dictionary = JSON.parse_string(zip.read_file("export-manifest.json").get_string_from_utf8())
		for file in manifest["files"]:
			var bytes: PackedByteArray = zip.read_file(file["path"])
			check(bytes.size() == int(file["bytes"]) and exporter.hash_bytes(bytes) == file["sha256"],"Manifest integrity " + file["path"])
		var registry: Dictionary = JSON.parse_string(zip.read_file("resources/catalog/catalog_registry.json").get_string_from_utf8())
		check(registry["items"].size() < 60,"Pruned runtime catalog " + mode)
		check(registry["items"].has("Office_Worker"),"Animated player catalog retained " + mode)
		check(names.has(pattern["texture"].trim_prefix("res://")),"Non-object pattern source included " + mode)
		var source: Dictionary = JSON.parse_string(zip.read_file("city-source.json").get_string_from_utf8())
		check(source["grid_version"] == 2 and source["documents"][mode] == JSON.parse_string(JSON.stringify(doc.data)),"Editable layout and repair metadata round trip " + mode)
		zip.close()
		check(exporter.save(studio.worlds[mode],doc.data,studio.library,destination)["ok"],"Existing ZIP can be replaced " + mode)
		var invalid: Dictionary = doc.data.duplicate(true)
		invalid["objects"].append({"uid":"bad","asset":"uninstalled","position":[0,0,0],"direction":"SE","scale":1})
		check(not exporter.save(studio.worlds[mode],invalid,studio.library,destination)["ok"],"Unknown asset stops before scene instantiation " + mode)
		# Missing animation views fail preflight without overwriting an existing ZIP.
		var original: Dictionary = studio.library.assets["2d:Office_Worker"]["data"]["directions"].duplicate(true)
		studio.library.assets["2d:Office_Worker"]["data"]["directions"]["NE"]["file"] = "missing_portable_test.png"
		var old_bytes: PackedByteArray = FileAccess.get_file_as_bytes(destination)
		var failed: Dictionary = exporter.save(studio.worlds[mode],doc.data,studio.library,destination)
		check(not failed["ok"] and failed["message"].contains("missing_portable_test"),"Missing dynamic dependency reports failure " + mode)
		check(FileAccess.get_file_as_bytes(destination) == old_bytes,"Failed export preserves existing package " + mode)
		studio.library.assets["2d:Office_Worker"]["data"]["directions"] = original
		# Export while the editor has suspended the exterior for a room visit.
		studio.set_walking(true)
		var world: Node = studio.worlds[mode]
		world.player.teleport_to(world.exploration.entrance(world.instances[building["uid"]]))
		world.exploration.interact()
		check(world.exploration.interior != null,"Walking editor enters the saved room " + mode)
		var interior: Node = world.exploration.interior
		check(exporter.save(world,doc.data,studio.library,destination)["ok"],"Export from an active room visit " + mode)
		check(world.exploration.interior == interior and not world.objects.visible,"Export preserves active exploration state " + mode)
		world.exploration.leave_interior()
		studio.set_walking(false)
	var dirty_before: bool = studio.dirty
	studio.file_action = "export_portable"
	studio._file_selected("res://output/portable/ui_export")
	check(FileAccess.file_exists("res://output/portable/ui_export.zip") and studio.status.text.begins_with("Portable project exported"),"Editor completion writes ZIP and explains how to open it")
	check(studio.dirty == dirty_before,"Export does not change project save status")
	studio.free()
	print("PORTABLE EXPORT: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
