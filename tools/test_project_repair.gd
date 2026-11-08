extends SceneTree

const Repair = preload("res://scripts/builder/project_repair.gd")
const Assets = preload("res://scripts/builder/repair_assets.gd")
const Store = preload("res://scripts/builder/project_store.gd")
const Doc = preload("res://scripts/builder/document.gd")
const Rooms = preload("res://scripts/builder/interiors.gd")
const Exporter = preload("res://scripts/builder/exporter.gd")
var checks: int = 0
var failures: int = 0
var directory: String

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; print("FAIL: " + message)

func same(a: Variant, b: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))

func write_text(path: String, content: String) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(content)
	file.close()

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	directory = "res://output/project_repair_test_"+str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	write_text(directory+"/.gdignore","")
	Store.storage_root = directory+"/history"
	Store.legacy_autosave = directory+"/legacy.json"
	var studio: Control = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	for i in 5: await process_frame
	var library: RefCounted = studio.library
	var original: Dictionary = studio.session_data().duplicate(true)
	var unchanged: Dictionary = Repair.new(library).session(original)
	check(unchanged["ok"] and not unchanged["changed"] and unchanged["content"]["documents"] == original["documents"], "Valid documents are preserved without repair")
	var broken_path: String = directory+"/dependency.tscn"
	write_text(broken_path,'[gd_scene load_steps=2 format=3]\n[ext_resource type="Texture2D" path="'+directory+'/not_installed.png" id="1"]\n[node name="Broken" type="Node3D"]\n')
	library.assets["3d:Probe/Unavailable"] = {"id":"3d:Probe/Unavailable","mode":"3d","path":broken_path,"name":"Unavailable dependency","category":"Decorations","data":{},"behavior":{"ground":false,"building":false,"door":false,"vehicle":false,"collision":"box","layer":"Decorations"}}
	check(not Assets.available("3d:Probe/Unavailable",library,{}), "Missing scene dependencies are detected before Godot attempts to load them")
	write_text(directory+"/corrupt.tscn",'[gd_scene format=3]\n[node name="Bad" type="StaticBody3D"]\nposition = Vector3(broken')
	library.assets["3d:Probe/Corrupt"] = library.assets["3d:Probe/Unavailable"].duplicate(true)
	library.assets["3d:Probe/Corrupt"]["id"] = "3d:Probe/Corrupt"
	library.assets["3d:Probe/Corrupt"]["path"] = directory+"/corrupt.tscn"
	check(not Assets.available("3d:Probe/Corrupt",library,{}), "Unreadable scene resources become unavailable without stopping project repair")
	write_text(directory+"/broken.gltf",'{"buffers":')
	check(not Assets.path_available(directory+"/broken.gltf",{}), "Truncated GLTF source metadata is detected without engine errors")
	write_text(directory+"/broken.gltf",'{"buffers":"bad","images":[]}')
	check(not Assets.path_available(directory+"/broken.gltf",{}), "Malformed GLTF dependency collections are detected safely")
	var startup: Control = load("res://scenes/builder.tscn").instantiate()
	startup.storage_enabled = false
	startup.library.assets["3d:HanX_City/Cafe_Small"]["path"] = directory+"/corrupt.tscn"
	root.add_child(startup)
	for i in 5: await process_frame
	check(startup.documents["3d"].data["objects"][1]["asset"] == Assets.OBJECT_3D and not startup.repair_report.is_empty(), "Unavailable default-template assets cannot prevent editor startup")
	startup.select_asset("3d:HanX_City/Cafe_Small")
	check(startup.asset_id.is_empty(), "Unavailable assets cannot be placed through the library")
	startup.free()
	if failures: studio.free(); quit(1); return
	var raw: Dictionary = original.duplicate(true)
	var pixel: Dictionary = raw["documents"]["2d"]
	var model: Dictionary = raw["documents"]["3d"]
	var valid_object: Dictionary = pixel["objects"][3].duplicate(true)
	var valid_tile: Dictionary = pixel["tiles"][2].duplicate(true)
	pixel["objects"][0]["interior"] = Rooms.make("2d","A retained room")
	pixel["objects"][0]["interior"]["objects"][0]["asset"] = "3d:Lost/RoomDesk"
	pixel["objects"][1]["asset"] = "2d:Lost/Bakery"
	var missing_pixel: Dictionary = pixel["objects"][1].duplicate(true)
	model["objects"][0]["asset"] = "3d:Lost/Apartment"
	model["objects"][0]["interior"] = Rooms.make("3d","Another retained room")
	var host_uid: String = model["objects"][0]["uid"]
	var host_room: Dictionary = model["objects"][0]["interior"].duplicate(true)
	model["objects"].append({"uid":"dependency","asset":"3d:Probe/Unavailable","position":[-4,0,9],"direction":"0","scale":1})
	model["objects"].append({"uid":"corrupt_resource","asset":"3d:Probe/Corrupt","position":[-6,0,9],"direction":"0","scale":1})
	model["objects"].append(model["objects"][2].duplicate(true))
	pixel["objects"].append({"uid":42,"asset":"2d:Plant_Monstera","position":[33,"bad"],"scale":"bad","direction":55,"tilt":[90,"bad"],"visible":{"yes":true},"layer":"LostLayer","colors":[{"garbled":true},{"kind":"pixels","texture":"unused","pixels":[0],"color":[1,0,0,1],"pattern":{"broken":true}}]})
	pixel["objects"].append("lost bytes")
	var missing_cell: Array = pixel["tiles"][0]["cell"].duplicate()
	pixel["tiles"][0]["asset"] = "2d:Lost/Ground"
	pixel["tiles"][1]["cell"] = ["bad",1]
	pixel["roads"] = [{"cell":[0,1],"crossing":false,"width":2,"style":"bad","sidewalks":false},{"cell":[0,1],"style":"brick"},"bad road"]
	raw["workspace"]["2d"]["camera"] = ["bad",0,1]
	raw["workspace"]["2d"]["rotation_mode"] = {"bad":true}
	var path: String = directory+"/damaged.isocity.json"
	var raw_text: String = JSON.stringify(raw,"\t")
	write_text(path,raw_text)
	var result: Dictionary = Repair.new(library).read(path)
	check(result["ok"] and result["changed"] and not result["report"]["issues"].is_empty(), "Partially damaged projects produce a repaired document and a report")
	if not result["ok"]: print(result); studio.free(); quit(1); return
	var fixed: Dictionary = result["content"]
	for mode in ["2d","3d"]: check(Doc.valid(fixed["documents"][mode],mode,library), "Repaired world validates: "+mode)
	check(fixed["documents"]["2d"]["objects"].any(func(item:Dictionary)->bool:return same(item,valid_object)) and fixed["documents"]["2d"]["tiles"].any(func(item:Dictionary)->bool:return same(item,valid_tile)), "Unrelated valid objects and tiles are retained exactly")
	var placeholder: Dictionary = fixed["documents"]["2d"]["objects"].filter(func(item:Dictionary)->bool:return item["uid"]==missing_pixel["uid"])[0]
	check(placeholder["asset"] == Assets.OBJECT_2D and same(placeholder["position"],missing_pixel["position"]) and same(placeholder["missing_asset"]["record"],missing_pixel), "Missing sprites keep their placement and complete original record")
	var floor: Dictionary = fixed["documents"]["2d"]["objects"].filter(func(item:Dictionary)->bool:return item["asset"]==Assets.TILE_2D)[0]
	check(same(floor["position"],[(missing_cell[0]-missing_cell[1])*16,(missing_cell[0]+missing_cell[1])*8,0]) and same(floor["missing_asset"]["record"]["cell"],missing_cell), "Missing ground becomes an editable visible cell placeholder")
	var repaired_host: Dictionary = fixed["documents"]["3d"]["objects"].filter(func(item:Dictionary)->bool:return item["uid"]==host_uid)[0]
	check(repaired_host["asset"] == Assets.OBJECT_3D and same(repaired_host["interior"],host_room), "Missing model buildings retain their complete owned rooms")
	check(fixed["documents"]["2d"]["objects"][0]["interior"]["objects"][0]["asset"] == Assets.OBJECT_3D, "Nested room contents are repaired independently")
	var recovered: Dictionary = fixed["documents"]["2d"]["objects"].filter(func(item:Dictionary)->bool:return item["asset"]=="2d:Plant_Monstera")[0]
	check(same(recovered["position"],[33,0,0]) and recovered["scale"] == 1 and recovered["colors"].size() == 1 and not recovered["colors"][0].has("pattern"), "Usable geometry and colors survive damaged fields and patterns")
	check(fixed["documents"]["2d"]["roads"].size() == 1 and fixed["documents"]["2d"]["roads"][0]["width"] == 2 and not fixed["documents"]["2d"]["roads"][0]["sidewalks"], "Valid road fields survive unrelated profile damage")
	check(not fixed["workspace"]["2d"].has("camera") and not fixed["workspace"]["2d"].has("rotation_mode"), "Invalid workspace values cannot break editor restoration")
	check(result["report"]["issues"].any(func(issue:Dictionary)->bool:return issue.get("original") is String and issue["original"]=="lost bytes"), "Unreadable records remain archived in the report")
	var ids: Dictionary = {}
	for item in fixed["documents"]["3d"]["objects"]: ids[item["uid"]] = true
	check(ids.size() == fixed["documents"]["3d"]["objects"].size(), "Duplicate object IDs are repaired without dropping their geometry")
	var partial: Dictionary = Repair.new(library).session({"version":1,"documents":{"2d":original["documents"]["2d"]}})
	check(partial["ok"] and partial["content"]["documents"]["2d"] == original["documents"]["2d"] and partial["content"]["documents"]["3d"]["objects"].is_empty(), "A missing world does not discard the usable world")
	var tail: String = '{"version":1,"documents":{"2d":'+JSON.stringify(original["documents"]["2d"])+',"3d":{"mode":"3d","title":"Damaged","night":false,"tiles":[],"objects":['+JSON.stringify(original["documents"]["3d"]["objects"][0])+',{"uid":"cut'
	write_text(directory+"/truncated.json",tail)
	var truncated: Dictionary = Repair.new(library).read(directory+"/truncated.json")
	check(truncated["ok"] and truncated["content"]["documents"]["3d"]["objects"].size() == 1 and same(truncated["content"]["documents"]["2d"],original["documents"]["2d"]), "Complete records before a truncated JSON tail remain recoverable")
	check(truncated["report"]["issues"].any(func(issue:Dictionary)->bool:return issue.get("original")==tail), "Truncated source text remains archived verbatim")
	var middle: String = '{"version":1,"documents":{"2d":{"mode":"2d","title":"Mixed damage","night":false,"tiles":[],"objects":['+JSON.stringify(valid_object)+',BROKEN BYTES,'+JSON.stringify(missing_pixel)+']},"3d":'+JSON.stringify(original["documents"]["3d"])+'}}'
	write_text(directory+"/middle.json",middle)
	var middle_result: Dictionary = Repair.new(library).read(directory+"/middle.json")
	check(middle_result["ok"] and middle_result["content"]["documents"]["2d"]["objects"].size()==2 and middle_result["content"]["documents"]["3d"]["objects"].size()==original["documents"]["3d"]["objects"].size(), "Complete records on both sides of damaged JSON tokens survive")
	var extension: Dictionary = original.duplicate(true)
	extension["workspace"]["extension"] = {"notes":["keep","these"],"unknown":{"any":"value"},"measurement":1.0e200}
	check(Repair.new(library).session(extension)["content"]["workspace"]["extension"] == extension["workspace"]["extension"], "Unrecognized but valid extension settings are preserved")
	test_bad_fields(original,library)
	studio.storage_enabled = true
	check(studio.load_project(path), "The actual editor opens a partially damaged project")
	studio.storage_enabled = false
	for i in 3: await process_frame
	check(studio.dirty and studio.project_path.is_empty() and FileAccess.get_file_as_string(path) == raw_text, "Repair opens an unsaved copy and preserves the source")
	var backup: String = studio.repair_report.get("source_backup","")
	check(not backup.is_empty() and FileAccess.get_file_as_string(backup) == raw_text, "Before-repair backups preserve the exact source bytes")
	check(studio.repair_tools.dialog.visible and studio.modal_visible() and studio.repair_tools.bar.visible, "The repair report opens visibly and blocks world interaction")
	check(not studio.repair_tools.text.text.is_empty() and studio.repair_tools.missing.item_count >= 4, "The report identifies repairs and unresolved source assets")
	studio.repair_tools.dialog.hide()
	for mode in ["2d","3d"]:
		studio.switch_mode(mode)
		check(studio.worlds[mode].instances.size() == studio.current().data["objects"].size(), "Every retained and substituted object renders: "+mode)
	check(studio.worlds["3d"].instances[host_uid] is StaticBody3D and studio.worlds["3d"].instances[host_uid].has_node("Warning"), "Missing models have visible warning geometry and labels")
	studio.interior_tools.start(host_uid)
	check(studio.interior_tools.editing() and studio.current().data["objects"].size() == host_room["objects"].size(), "Rooms attached to missing buildings remain editable")
	studio.interior_tools.leave()
	studio.switch_mode("2d")
	studio.interior_tools.start(studio.current().data["objects"][0]["uid"])
	var nested_uid: String = studio.current().data["objects"][0]["uid"]
	check(studio.worlds["2d"].instances[nested_uid].has_method("ground_polygon") and studio.worlds["2d"].instances[nested_uid].model.has_node("Warning"), "Missing model contents render as warnings inside editable pixel-world rooms")
	studio.interior_tools.leave()
	studio.switch_mode("3d")
	var protected_state: String = JSON.stringify(studio.session_data())
	write_text(directory+"/unrecoverable.json","no usable JSON")
	check(not studio.load_project(directory+"/unrecoverable.json") and JSON.stringify(studio.session_data()) == protected_state, "Unrecoverable files leave the current project intact")
	if "--capture" in OS.get_cmdline_user_args():
		studio.status.text = "Recovered city · source preserved · placeholders remain editable."
		studio.worlds["3d"].reset_camera("city")
		for i in 10: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://output/editor_repaired_placeholders.png")
		studio.switch_mode("2d")
		studio.worlds["2d"].reset_camera("city")
		for i in 5: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://output/editor_repaired_placeholders_2d.png")
		studio.repair_tools.show()
		for i in 5: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://output/editor_repair_report.png")
		studio.repair_tools.text.get_parent().current_tab = 1
		for index in studio.repair_tools.missing.item_count:
			if studio.repair_tools.missing.get_item_metadata(index) == "2d:Lost/Bakery": studio.repair_tools.missing.select(index)
		studio.repair_tools.query.text = "bakery"
		studio.repair_tools.search_replacements()
		for index in studio.repair_tools.replacements.item_count:
			if studio.repair_tools.replacements.get_item_metadata(index) == "2d:Bakery": studio.repair_tools.replacements.select(index)
		studio.repair_tools.update_button()
		for i in 5: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://output/editor_missing_asset_replacement.png")
		studio.repair_tools.dialog.hide()
		studio.switch_mode("3d")
	var copy_path: String = directory+"/recovered.isocity.json"
	check(studio.write_project(copy_path) and studio.load_project(copy_path), "Repaired projects save and reopen with placeholder metadata")
	check(studio.repair_report.get("issues",[]).size() >= result["report"]["issues"].size(), "Repair reports and archived values persist with the project")
	var report_path: String = directory+"/repair_report.json"
	studio.repair_tools.report_file.file_selected.emit(ProjectSettings.globalize_path(report_path))
	check(Store.read_json(report_path,{})["issues"].any(func(issue:Dictionary)->bool:return issue.get("original") is String and issue["original"]=="lost bytes"), "The report's save action exports archived original records")
	var export_path: String = directory+"/repaired_export.tscn"
	check(Exporter.save_scene(studio.worlds["3d"],studio.current().data,library,export_path)==OK, "Repaired scenes export successfully")
	var exported: Node = load(export_path).instantiate()
	root.add_child(exported)
	check(exported.exploration.library.assets.has(Assets.OBJECT_3D) and exported.exploration.instances.has(host_uid), "Exported runtime restores placeholder definitions and owned rooms")
	exported.free()
	await test_remapping(studio,host_uid,missing_pixel["uid"])
	var auto_path: String = Store.autosave_path(original["project_id"])
	Store.prepare_parent(auto_path)
	write_text(auto_path,tail)
	Store.write_json(Store.storage_root+"/resume.json",{"project_id":original["project_id"]})
	check(Store.resume_autosave() == auto_path, "Startup can identify a truncated but salvageable scoped autosave")
	studio.storage_enabled = true
	check(studio.load_project(auto_path), "Truncated autosaves pass through the actual repair loader")
	studio.storage_enabled = false
	var raw_backup: String = studio.repair_report["source_backup"]
	check(studio.project_id == original["project_id"] and FileAccess.get_file_as_string(raw_backup) == tail, "A damaged autosave keeps its project association and exact pre-repair source")
	check(studio.autosave() and FileAccess.get_file_as_string(raw_backup) == tail and Store.read_json(auto_path,{})["repair_report"].has("source_backup"), "Autosaving the repaired result cannot destroy the damaged original")
	var intact_state: String = JSON.stringify(studio.session_data())
	write_text(directory+"/future.json",JSON.stringify({"version":2,"documents":original["documents"]}))
	check(not studio.load_project(directory+"/future.json") and JSON.stringify(studio.session_data()) == intact_state, "Unsupported formats are preserved instead of guessed into the current schema")
	var proper_root: String = Store.storage_root
	Store.write_json(directory+"/blocked",{})
	Store.storage_root = directory+"/blocked"
	studio.storage_enabled = true
	var failed: bool = studio.load_project(path)
	studio.storage_enabled = false
	Store.storage_root = proper_root
	check(not failed and JSON.stringify(studio.session_data()) == intact_state and FileAccess.get_file_as_string(path) == raw_text, "Repair stops safely when the source cannot be preserved")
	studio.storage_enabled = false
	studio.free()
	print("PROJECT REPAIR: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func test_remapping(studio: Control, host_uid: String, pixel_uid: String) -> void:
	studio.repair_tools.show()
	var tool: RefCounted = studio.repair_tools
	for index in tool.missing.item_count:
		if tool.missing.get_item_metadata(index) == "3d:Lost/Apartment": tool.missing.select(index)
	tool.query.text = "cafe small"
	tool.search_replacements()
	for index in tool.replacements.item_count:
		if tool.replacements.get_item_metadata(index) == "3d:HanX_City/Cafe_Small": tool.replacements.select(index)
	tool.update_button()
	var before: Dictionary = studio.documents["3d"].object(host_uid).duplicate(true)
	tool.replace_selected()
	var after: Dictionary = studio.documents["3d"].object(host_uid)
	check(after["asset"] == "3d:HanX_City/Cafe_Small" and not after.has("missing_asset") and same(after["interior"],before["interior"]) and same(after["position"],before["position"]), "Replacement through the report preserves placement and owned rooms")
	check(studio.documents["3d"].undo() and studio.documents["3d"].object(host_uid).has("missing_asset"), "Replacement operations can be undone")
	studio.changed()
	studio.library.assets["2d:Lost/Bakery"] = studio.library.assets["2d:Bakery"].duplicate(true)
	studio.library.assets["2d:Lost/Bakery"]["id"] = "2d:Lost/Bakery"
	tool.retry_originals()
	check(studio.documents["2d"].object(pixel_uid)["asset"] == "2d:Lost/Bakery" and not studio.documents["2d"].object(pixel_uid).has("missing_asset"), "Restored source files can replace their original placeholders")
	var floor: Dictionary = studio.documents["2d"].data["objects"].filter(func(item:Dictionary)->bool:return item["asset"]==Assets.TILE_2D)[0]
	var floor_uid: String = floor["uid"]
	var cell: Array = floor["missing_asset"]["record"]["cell"].duplicate()
	tool.apply_changes("2d:Lost/Ground","2d:Grass",false)
	check(studio.documents["2d"].object(floor_uid).is_empty() and studio.documents["2d"].data["tiles"].any(func(tile:Dictionary)->bool:return tile["asset"]=="2d:Grass" and same(tile["cell"],cell)), "Aligned ground replacements return to editable native tile-map cells")
	check(studio.documents["2d"].undo() and studio.documents["2d"].object(floor_uid).get("asset")==Assets.TILE_2D, "Undo restores ground placeholders and their original records")
	studio.refresh_worlds()
	tool.dialog.hide()

func test_bad_fields(original: Dictionary, library: RefCounted) -> void:
	var values: Array = [null,true,42,2.5,"broken",[],{},[1,"bad"],INF,NAN,1.0e200]
	for key in ["uid","asset","position","direction","scale","angle","tilt","visible","locked","open","group","layer","name","colors","entrance_anchor","interior","missing_asset"]:
		for value in values:
			var fixture: Dictionary = {"version":1,"documents":{"2d":{"mode":"2d","title":"Typed damage","objects":[{"uid":"typed","asset":"2d:Plant_Monstera","position":[0,0,0],"scale":1,"direction":"SE"}],"tiles":[],"night":false},"3d":{"mode":"3d","title":"Intact","objects":[],"tiles":[],"night":false}}}
			fixture["documents"]["2d"]["objects"][0][key] = value
			var repaired: Dictionary = Repair.new(library).session(fixture)
			check(repaired.get("ok",false) and Doc.valid(repaired["content"]["documents"]["2d"],"2d",library), "Typed corruption remains repairable: "+key+" / "+str(typeof(value)))
	var large: Dictionary = {"version":1,"documents":{"2d":{"mode":"2d","title":"Huge","objects":[{"uid":"huge","asset":"2d:Plant_Monstera","position":[1.0e200,0,0],"scale":1,"direction":"SE"}],"tiles":[],"night":false}}}
	var repaired: Dictionary = Repair.new(library).session(large)
	check(repaired["ok"] and repaired["content"]["documents"]["2d"]["objects"][0]["position"][0] <= Repair.MAX_COORDINATE, "Unrenderable finite coordinates cannot overflow engine transforms")
