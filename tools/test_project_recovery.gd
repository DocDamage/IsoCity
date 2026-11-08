extends SceneTree

const Store = preload("res://scripts/builder/project_store.gd")
var checks: int = 0
var failures: int = 0
var directory: String

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func save(studio: Control, path: String) -> bool:
	studio.storage_enabled = true
	var result: bool = studio.write_project(path)
	studio.storage_enabled = false
	return result

func run() -> void:
	directory = "res://output/project_recovery_test_" + str(Time.get_ticks_usec())
	Store.storage_root = directory + "/history"
	Store.legacy_autosave = directory + "/legacy_autosave.json"
	DirAccess.make_dir_recursive_absolute(directory)
	var studio: Control = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	for i in 5: await process_frame
	var id_a: String = studio.project_id
	var another: Control = load("res://scenes/builder.tscn").instantiate()
	check(another.project_id != id_a and Store.valid_id(another.project_id), "Separate unsaved projects do not share an identity even with identical titles")
	another.free()
	check(Store.valid_id(id_a), "A fresh unsaved project has a safe stable identity")
	check(not Store.valid_id("../outside") and Store.autosave_path("../outside").is_empty(), "Project IDs cannot escape the recovery root")
	check(studio.autosave(), "An unsaved project writes its own autosave")
	var auto_a: String = Store.autosave_path(id_a)
	check(FileAccess.file_exists(auto_a) and Store.resume_autosave() == auto_a, "Startup targets the latest scoped autosave")
	check(studio.project_path.is_empty() and studio.project_id == id_a, "Autosaving does not turn an unsaved city into a named project")
	var path_a: String = directory + "/Harbor.isocity.json"
	var path_b: String = directory + "/Garden.isocity.json"
	check(save(studio,path_a) and studio.project_id == id_a, "First explicit save retains the unsaved project's history identity")
	check(Store.read_json(auto_a,{})["project_path"] == path_a, "Explicit saving updates the autosave's source association")
	studio.current().checkpoint()
	studio.current().data["title"] = "Harbor with unsaved edits"
	studio.changed()
	var content_a: Dictionary = studio.session_data().duplicate(true)
	check(studio.autosave() and studio.dirty and studio.project_path == path_a, "Autosaving retains unsaved-change state and the working file path")
	check(save(studio,path_b), "Save As writes another project")
	var id_b: String = studio.project_id
	var auto_b: String = Store.autosave_path(id_b)
	check(id_b != id_a and FileAccess.file_exists(auto_a) and FileAccess.file_exists(auto_b), "Save As forks identity and preserves both autosaves")
	check(Store.read_json(auto_a,{})["project_id"] == id_a and Store.read_json(auto_b,{})["project_id"] == id_b, "Each autosave identifies exactly the project it restores")
	check(Store.resume_autosave() == auto_b, "Save As immediately makes the new project resumable")
	check(studio.load_project(auto_a) and studio.project_id == id_a and studio.project_path == path_a and studio.dirty, "Resuming A restores its identity, source and unsaved state after working on B")
	var snapshot_a: String = Store.snapshot(studio.session_data(),"Before waterfront changes",null,true)
	var session_b: Dictionary = Store.read_json(path_b,{})
	var snapshot_b: String = Store.snapshot(session_b,"Garden checkpoint")
	for i in 43: Store.snapshot(content_a,"Harbor recovery " + str(i),null,true)
	var entries: Array = Store.entries()
	var a_versions: Array = entries.filter(func(e:Dictionary)->bool:return e.get("project_id")==id_a and e["kind"] in ["snapshot","recovery"])
	var b_versions: Array = entries.filter(func(e:Dictionary)->bool:return e.get("project_id")==id_b and e["kind"] in ["snapshot","recovery"])
	check(a_versions.size() == Store.MAX_SNAPSHOTS and b_versions.size() == 1 and FileAccess.file_exists(snapshot_b), "Retention is bounded per project and never consumes another project's versions")
	check(FileAccess.file_exists(path_a) and FileAccess.file_exists(path_b) and FileAccess.file_exists(auto_a) and FileAccess.file_exists(auto_b), "Pruning leaves explicit saves and latest autosaves intact")
	check(not FileAccess.file_exists(snapshot_a), "Only the oldest generated copies of the active project are pruned")
	check(not Store.can_prune(path_a,id_a) and not Store.can_prune(snapshot_b,id_a) and not Store.can_prune(auto_a,id_a), "Pruning refuses originals, other projects and autosaves")
	var previous_id: String = studio.project_id
	var previous_path: String = studio.project_path
	Store.write_json(directory+"/blocked",{})
	check(not save(studio,directory+"/blocked/fail.json") and studio.project_id == previous_id and studio.project_path == previous_path, "A failed Save As rolls back identity and working path")
	var history_root: String = Store.storage_root
	var original_file: String = FileAccess.get_file_as_string(path_a)
	Store.storage_root = directory+"/blocked"
	var protected_save: bool = save(studio,path_a)
	Store.storage_root = history_root
	check(not protected_save and FileAccess.get_file_as_string(path_a) == original_file and studio.project_id == previous_id, "An existing project is preserved when its before-save recovery copy cannot be written")
	check(studio.load_project(a_versions[0]["path"]) and studio.project_id == id_a and studio.project_path.is_empty() and studio.dirty, "Opening a recovery copy preserves its association and requires an explicit save destination")
	check(studio.project_origin_path == path_a, "A restored copy retains its source path for future attribution")
	var path_c: String = directory+"/Harbor_recovered.isocity.json"
	check(save(studio,path_c) and studio.project_id != id_a, "Saving a restored copy separately forks its history")
	var index_path: String = Store.storage_root+"/index.json"
	DirAccess.remove_absolute(index_path)
	check(Store.entries().any(func(e:Dictionary)->bool:return e["path"] == snapshot_b) and Store.entries().any(func(e:Dictionary)->bool:return e["path"] == auto_a), "Copy-local records recover history after the main index is lost")
	DirAccess.remove_absolute(snapshot_b+".entry.json")
	Store.write_json(snapshot_b+".entry.json",{"partial":true})
	check(Store.entries().any(func(e:Dictionary)->bool:return e["path"] == snapshot_b), "Embedded metadata recovers snapshots when the main index is lost and the copy index is damaged")
	DirAccess.remove_absolute(auto_a+".entry.json")
	check(Store.entries().any(func(e:Dictionary)->bool:return e["path"] == auto_a), "Autosave payloads can reconstruct their own association")
	var legacy: Dictionary = content_a.duplicate(true)
	legacy.erase("project_id")
	legacy.erase("project_origin_path")
	legacy.erase("project_title")
	Store.write_json(Store.legacy_autosave,legacy)
	studio.storage_enabled = true
	check(studio.load_project(Store.legacy_autosave), "Legacy global autosaves remain loadable")
	studio.storage_enabled = false
	var legacy_id: String = Store.identity(legacy,Store.legacy_autosave)
	check(studio.project_id == legacy_id and FileAccess.file_exists(Store.autosave_path(legacy_id)) and FileAccess.file_exists(Store.legacy_autosave), "Legacy migration creates a scoped copy without deleting the original")
	check(Store.identity(legacy,path_a) == Store.identity(legacy,Store.canonical(path_a)), "Legacy identity is stable across equivalent path spellings")
	var unassigned: Dictionary = legacy.duplicate(true)
	unassigned.erase("project_path")
	Store.write_json(Store.legacy_autosave,unassigned)
	check(Store.entries(true).any(func(e:Dictionary)->bool:return e.get("legacy_unassigned",false)), "Unattributable legacy copies are explicitly labeled instead of assigned to another project")
	studio.storage_enabled = true
	studio.show_projects()
	check(studio.browser_entries.all(func(e:Dictionary)->bool:return e.get("project_id") == studio.project_id and not e.get("legacy_unassigned",false)), "Project browser defaults to the current project's own history")
	studio.recovery_filter.select(1)
	studio.populate_projects()
	check(studio.browser_entries.any(func(e:Dictionary)->bool:return e.get("project_id")==id_b), "All projects exposes other projects' recovery histories")
	check(studio.project_list.get_item_text(0).contains(" · ") and studio.project_list.get_item_tooltip(0).contains("Source:"), "Recovery rows identify project and source path")
	var target_index: int = -1
	for index in studio.browser_entries.size():
		if studio.browser_entries[index].get("project_id") == id_a and studio.browser_entries[index]["kind"] == "recovery": target_index = index; break
	studio.project_list.select(target_index)
	studio.restore_selected()
	check(studio.project_id == id_a and studio.project_path.is_empty() and studio.project_origin_path == path_a and studio.dirty, "The actual restore action opens the chosen project's copy without overwriting its source")
	studio.storage_enabled = false
	check(save(studio,path_b), "Saving over an existing destination preserves the destination's previous version")
	var backups: Array = Store.entries().filter(func(e:Dictionary)->bool:return e["kind"]=="recovery" and e["title"].begins_with("Previous save") and e.get("project_id")==id_b)
	check(not backups.is_empty() and Store.read_json(backups[0]["path"],{})["project_id"] == id_b and backups[0]["project_path"] == path_b, "Overwrite backups belong to the overwritten project, not the incoming project")
	var owned_id: String = studio.project_id
	var owner: String = studio.current().data["objects"][0]["uid"]
	var outer_count: int = studio.current().data["objects"].size()
	studio.interior_tools.start(owner)
	var room_count: int = studio.current().data["objects"].size()
	studio.current().add("2d:Plant_Monstera",[100,0,0],studio.library.directions("2d:Plant_Monstera")[0])
	studio.changed()
	check(studio.autosave(), "Scoped autosaves work while editing owned interiors")
	var owned: Dictionary = Store.read_json(Store.autosave_path(owned_id),{})
	check(owned["project_id"] == owned_id and owned["documents"][studio.mode]["objects"].size() == outer_count and owned["documents"][studio.mode]["objects"][0]["interior"]["objects"].size() == room_count+1, "Recovery retains the owning city and its current room contents")
	studio.interior_tools.leave()
	var last_auto: String = Store.resume_autosave()
	Store.write_json(Store.storage_root+"/resume.json",{"project_id":"../invalid"})
	check(Store.resume_autosave() == last_auto, "A damaged resume pointer falls back to the latest known autosave")
	var broken_id: String = Store.new_id()
	Store.write_json(Store.autosave_path(broken_id),{"version":1})
	Store.write_json(Store.storage_root+"/resume.json",{"project_id":broken_id})
	check(Store.resume_autosave() == last_auto, "An unusable autosave does not displace valid resumable projects")
	Store.write_json(Store.legacy_autosave,unassigned)
	check(studio.load_project(Store.legacy_autosave) and studio.project_origin_path.is_empty(), "Unnamed legacy recovery does not invent a source file")
	var unnamed_id: String = studio.project_id
	check(save(studio,directory+"/First_named_legacy.isocity.json") and studio.project_id == unnamed_id, "First naming of an unnamed legacy project retains its recovered history")
	studio.storage_enabled = true
	studio.show_projects()
	studio.recovery_filter.select(1)
	studio.populate_projects()
	if "--capture" in OS.get_cmdline_user_args():
		for i in 10: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://output/editor_project_recovery.png")
	studio.storage_enabled = false
	check(studio.browser.size.y <= root.size.y and studio.recovery_details.text.contains("Source:") and studio.recovery_details.text.contains("Copy:"), "Recovery browser stays on screen and separates project identity from time/source details")
	studio.browser.hide()
	studio.free()
	print("PROJECT RECOVERY: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
