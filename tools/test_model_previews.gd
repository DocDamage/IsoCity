extends SceneTree

const Preview = preload("res://scripts/builder/model_preview.gd")
const Document = preload("res://scripts/builder/document.gd")
const Templates = preload("res://scripts/builder/templates.gd")
const OUTPUT = "res://output/verification/asset_expansion/I05"
var checks: int = 0
var failures: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; print("FAIL: " + message)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var library: RefCounted = preload("res://scripts/builder/asset_library.gd").new()
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/fixtures/asset_expansion/model_previews.json"))
	var ids: Array = fixture["assets"]
	var found: Array = library.assets.keys().filter(func(id: String) -> bool: return id.begins_with("3d:Supplemental_Spaceships_II/"))
	check(ids.size() == 25 and found.size() == 25, "All 25 existing ship identities remain available")
	for id in ids:
		check(library.assets.has(id), "Stable ship ID: " + id)
		var texture: Texture2D = library.icon(id)
		check(texture != null and texture.resource_path != "res://assets/editor/missing_object.png" and Preview.meaningful(texture), "Meaningful prepared preview: " + id)
		check(texture.get_image().get_format() == Image.FORMAT_RGBA8 and texture.get_image().get_used_rect().size.x < texture.get_width(), "Transparent image with framing margin: " + id)
		check(library.icon(id) == texture, "Repeated browser access reuses cached texture")
	var flat := Image.create_empty(128, 128, false, Image.FORMAT_RGBA8)
	flat.fill(Color(38.0 / 255.0, 73.0 / 255.0, 93.0 / 255.0))
	check(not Preview.meaningful(ImageTexture.create_from_image(flat)), "Old solid-color placeholder is rejected")
	flat.fill(Color.TRANSPARENT); flat.fill_rect(Rect2i(32, 32, 64, 64), Color.WHITE)
	check(Preview.meaningful(ImageTexture.create_from_image(flat)), "Monochrome silhouette remains valid")
	var id: String = ids[0]
	var original: String = library.assets[id]["data"]["preview_path"]
	library.assets[id]["data"]["preview_path"] = OUTPUT + "/does-not-exist.png"
	library.icons.erase(id)
	check(library.icon(id).resource_path == "res://assets/editor/missing_object.png", "Absent model preview uses visible missing-art marker")
	var placeholder: String = OUTPUT + "/flat.png"
	flat.fill(Color(38.0 / 255.0, 73.0 / 255.0, 93.0 / 255.0)); flat.save_png(placeholder)
	library.assets[id]["data"]["preview_path"] = placeholder
	# Raw test image is intentionally not imported; ImageTexture exercises the
	# same predicate without triggering a project import just for a fixture.
	var loaded := Image.new(); loaded.load_png_from_buffer(FileAccess.get_file_as_bytes(placeholder))
	check(not Preview.meaningful(ImageTexture.create_from_image(loaded)), "Uniform prepared PNG is detected")
	library.assets[id]["data"]["preview_path"] = original; library.icons.erase(id)
	for mode in ["2d", "3d"]:
		var doc: RefCounted = Document.new()
		doc.data = Templates.make(mode, "blank")
		for index in ids.size(): doc.add(ids[index], [index * 7, 0, 0], "0", 1)
		var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(doc.data))
		check(Document.valid(roundtrip, mode, library), "Existing ship placements still validate after JSON round trip: " + mode)
		check(roundtrip["objects"].map(func(item: Dictionary) -> String: return item["asset"]) == ids, "Round trip keeps exact member IDs: " + mode)
	if "--portable" in OS.get_cmdline_user_args():
		await portable(library, ids[0])
	print("Model previews: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func portable(library: RefCounted, id: String) -> void:
	var studio: Control = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false; root.add_child(studio)
	while not studio.enhancements_ready: await process_frame
	for mode in ["2d", "3d"]:
		studio.switch_mode(mode)
		studio.current().data = Templates.make(mode, "blank")
		studio.current().add(id, [0, 0, 0], "0", 1)
		studio.changed()
		for frame in 4: await process_frame
		var path: String = OUTPUT + "/preview_" + mode + ".zip"
		var result: Dictionary = preload("res://scripts/builder/portable_export.gd").new().save(studio.worlds[mode], studio.current().data, library, path)
		check(result["ok"], "Allowed ship portable export: " + mode + " " + result.get("message", ""))
		if result["ok"]:
			var archive := ZIPReader.new(); archive.open(path)
			check(archive.file_exists(library.assets[id]["data"]["preview_path"].trim_prefix("res://")), "Portable includes repaired preview")
			check(not archive.file_exists("assets/supplemental_models/preview_manifest.json"), "Portable does not require editor preview cache")
			archive.close()
	studio.free(); await process_frame; await process_frame
