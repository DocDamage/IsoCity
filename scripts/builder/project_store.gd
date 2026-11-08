extends RefCounted

static var storage_root: String = "user://studio_history"
static var legacy_autosave: String = "user://studio_autosave.json"
const MAX_SNAPSHOTS: int = 40

static func read_json(path: String, fallback: Variant) -> Variant:
	if not FileAccess.file_exists(path): return fallback
	var parser := JSON.new()
	return parser.data if parser.parse(FileAccess.get_file_as_string(path)) == OK and parser.data != null else fallback

static func write_json(path: String, value: Variant) -> bool:
	if not prepare_parent(path): return false
	var temporary: String = path + "." + str(Time.get_ticks_usec()) + "_" + str(randi()) + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if not file: return false
	file.store_string(JSON.stringify(value, "\t"))
	file.flush()
	var result: Error = file.get_error()
	file.close()
	if result == OK: result = DirAccess.rename_absolute(temporary,path)
	if result != OK: DirAccess.remove_absolute(temporary)
	return result == OK

static func prepare_parent(path: String) -> bool:
	var ancestor: String = path.get_base_dir()
	while not ancestor.is_empty() and not DirAccess.dir_exists_absolute(ancestor):
		if FileAccess.file_exists(ancestor): return false
		var parent: String = ancestor.get_base_dir()
		if parent == ancestor: break
		ancestor = parent
	return DirAccess.make_dir_recursive_absolute(path.get_base_dir()) == OK

static func new_id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

static func valid_id(value: Variant) -> bool:
	return value is String and value.length() == 32 and value.is_valid_hex_number(false)

static func canonical(path: String) -> String:
	return ProjectSettings.globalize_path(path).replace("\\","/").simplify_path().to_lower()

static func in_history(path: String) -> bool:
	return not path.is_empty() and canonical(path).begins_with(canonical(storage_root) + "/")

static func source_path(session: Dictionary, source: String = "") -> String:
	var path: String = str(session.get("project_path",""))
	if path.is_empty(): path = str(session.get("project_origin_path",""))
	if path.is_empty() and not source.is_empty() and not in_history(source) and canonical(source) != canonical(legacy_autosave): path = source
	return path if not path.is_empty() and not in_history(path) and canonical(path) != canonical(legacy_autosave) else ""

static func identity(session: Dictionary, source: String = "") -> String:
	if valid_id(session.get("project_id")): return session["project_id"].to_lower()
	var origin: String = source_path(session,source)
	if not origin.is_empty() and not in_history(origin): return ("legacy-path:" + canonical(origin)).sha256_text().substr(0,32)
	# Unnamed legacy copies are not attributed to an unrelated named project.
	return ("legacy-content:" + JSON.stringify(session.get("documents",session))).sha256_text().substr(0,32)

static func project_title(session: Dictionary, source: String = "") -> String:
	if session.get("project_title") is String and not session["project_title"].is_empty(): return session["project_title"]
	var path: String = source_path(session,source)
	if not path.is_empty() and not in_history(path): return path.get_file().trim_suffix(".isocity.json").trim_suffix(".json")
	return str(session.get("documents",{}).get(session.get("active_mode","2d"),{}).get("title","Unsaved project"))

static func folder(id: String) -> String:
	return storage_root + "/projects/" + id.to_lower() if valid_id(id) else ""

static func autosave_path(id: String) -> String:
	return folder(id) + "/autosave.isocity.json" if valid_id(id) else ""

static func metadata(session: Dictionary, source: String = "") -> Dictionary:
	var path: String = source_path(session,source)
	return {"project_id":identity(session,source),"project_title":project_title(session,source),"project_path":path}

static func entries(include_legacy: bool = false) -> Array:
	var indexed: Dictionary = {}
	var old: Variant = read_json(storage_root + "/index.json",[])
	if old is Array:
		for entry in old:
			if entry is Dictionary and entry.get("path") is String and entry.get("title") is String and FileAccess.file_exists(entry["path"]):
				var upgraded: Dictionary = entry.duplicate(true)
				if not (upgraded.get("timestamp") is int or upgraded.get("timestamp") is float) or not is_finite(float(upgraded.get("timestamp",0))):
					upgraded["timestamp"] = FileAccess.get_modified_time(entry["path"])
					upgraded["time"] = Time.get_datetime_string_from_unix_time(upgraded["timestamp"],true) + " UTC"
				if not valid_id(upgraded.get("project_id")):
					var session: Variant = read_json(entry["path"],{})
					if session is Dictionary:
						upgraded.merge(metadata(session,entry["path"]),true)
						if entry.get("kind") != "project" and not valid_id(session.get("project_id")) and source_path(session).is_empty(): upgraded["legacy_unassigned"] = true
				indexed[canonical(entry["path"])] = upgraded
	# Copies retain their own index records so a lost main index cannot hide them.
	var project_folders: PackedStringArray = DirAccess.get_directories_at(storage_root + "/projects") if DirAccess.dir_exists_absolute(storage_root + "/projects") else PackedStringArray()
	for id in project_folders:
		if not valid_id(id): continue
		for filename in DirAccess.get_files_at(folder(id)):
			if not filename.ends_with(".isocity.json") and not filename.ends_with(".original.json"): continue
			var path: String = folder(id) + "/" + filename
			var entry: Variant = read_json(path + ".entry.json",{})
			if not usable_entry(entry,path,id):
				var session: Variant = read_json(path,{})
				entry = session.get("recovery_meta",{}) if session is Dictionary else {}
				if entry.is_empty() and filename == "autosave.isocity.json" and session is Dictionary and session.get("documents") is Dictionary and identity(session) == id:
					entry = entry_for(session,path,"Latest autosave","autosave")
					entry["timestamp"] = FileAccess.get_modified_time(path)
					entry["time"] = Time.get_datetime_string_from_unix_time(entry["timestamp"],true) + " UTC"
			if usable_entry(entry,path,id):
				indexed[canonical(path)] = entry
	if include_legacy and FileAccess.file_exists(legacy_autosave) and not indexed.has(canonical(legacy_autosave)):
		var session: Variant = read_json(legacy_autosave,{})
		if session is Dictionary and session.get("documents") is Dictionary:
			var entry: Dictionary = entry_for(session,legacy_autosave,"Legacy last-session autosave","legacy_autosave")
			entry["timestamp"] = FileAccess.get_modified_time(legacy_autosave)
			entry["time"] = Time.get_datetime_string_from_unix_time(entry["timestamp"],true) + " UTC"
			entry["legacy_unassigned"] = not valid_id(session.get("project_id")) and source_path(session).is_empty()
			indexed[canonical(legacy_autosave)] = entry
	var result: Array = indexed.values()
	result.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return float(a.get("timestamp",0)) > float(b.get("timestamp",0)))
	return result

static func usable_entry(entry: Variant, path: String, id: String) -> bool:
	if not entry is Dictionary: return false
	var timestamp: Variant = entry.get("timestamp")
	return entry.get("path") == path and entry.get("project_id") == id and entry.get("title") is String and (timestamp is int or timestamp is float) and is_finite(float(timestamp))

static func save_index(list: Array) -> bool:
	return write_json(storage_root + "/index.json",list)

static func entry_for(session: Dictionary, path: String, title: String, kind: String) -> Dictionary:
	var entry: Dictionary = metadata(session)
	entry.merge({"path":path,"title":title,"kind":kind,"time":Time.get_datetime_string_from_system(true).replace("T"," ") + " UTC","timestamp":Time.get_unix_time_from_system(),"thumbnail":""})
	return entry

static func remember(path: String, title: String, thumbnail: Image = null, id: String = "") -> void:
	var session: Variant = read_json(path,{})
	if not session is Dictionary: session = {}
	if valid_id(id): session["project_id"] = id
	session["project_path"] = path
	var entry: Dictionary = entry_for(session,path,title,"project")
	entry["thumbnail"] = storage_root + "/recent_" + canonical(path).sha256_text().substr(0,16) + ".png"
	var list: Array = entries().filter(func(value:Dictionary)->bool:return canonical(value["path"]) != canonical(path))
	DirAccess.make_dir_recursive_absolute(storage_root)
	if thumbnail and not thumbnail.is_empty():
		var picture: Image = thumbnail.duplicate()
		picture.resize(240,150,Image.INTERPOLATE_BILINEAR)
		picture.save_png(entry["thumbnail"])
	list.push_front(entry)
	var count: int = 0
	for value in list.duplicate():
		if value.get("kind") == "project":
			count += 1
			if count > 15: list.erase(value)
	save_index(list)

static func register_autosave(session: Dictionary, path: String) -> bool:
	var id: String = identity(session)
	if canonical(path) != canonical(autosave_path(id)): return false
	var entry: Dictionary = entry_for(session,path,"Latest autosave","autosave")
	if not write_json(path + ".entry.json",entry): return false
	var list: Array = entries().filter(func(value:Dictionary)->bool:return canonical(value["path"]) != canonical(path))
	list.push_front(entry)
	if not save_index(list): return false
	return write_json(storage_root + "/resume.json",{"project_id":id})

static func resume_autosave() -> String:
	var pointer: Variant = read_json(storage_root + "/resume.json",{})
	if pointer is Dictionary and valid_id(pointer.get("project_id")):
		var path: String = autosave_path(pointer["project_id"])
		if resumable(path): return path
	for entry in entries():
		if entry.get("kind") == "autosave" and resumable(entry["path"]): return entry["path"]
	return legacy_autosave if resumable(legacy_autosave) else ""

static func resumable(path: String) -> bool:
	var session: Variant = read_json(path,{})
	if (not session is Dictionary or not session.get("documents") is Dictionary) and FileAccess.file_exists(path):
		var parsed: Dictionary = load("res://scripts/builder/project_repair.gd").new(null).parse_text(FileAccess.get_file_as_string(path))
		session = parsed.get("value",{})
	if not session is Dictionary or session.get("version",1) != 1 or not session.get("documents") is Dictionary: return false
	for mode in ["2d","3d"]:
		var world: Variant = session["documents"].get(mode)
		if world is Dictionary and (world.get("objects") is Array or world.get("tiles") is Array): return true
	return false

static func can_prune(path: String, id: String) -> bool:
	var parent: String = canonical(path.get_base_dir())
	return valid_id(id) and path.get_file().begins_with("snapshot_") and path.ends_with(".isocity.json") and parent == canonical(folder(id))

static func preserve_source(source: String, session: Dictionary, id: String) -> String:
	var path: String = folder(id) + "/before_repair_" + str(Time.get_ticks_usec()) + "_" + str(randi()) + ".original.json"
	if not prepare_parent(path): return ""
	if DirAccess.copy_absolute(source,path) != OK: return ""
	var tagged: Dictionary = session.duplicate()
	tagged["project_id"] = id
	if not in_history(source) and canonical(source) != canonical(legacy_autosave): tagged["project_path"] = source
	var entry: Dictionary = entry_for(tagged,path,"Original source before repair","original")
	if not write_json(path+".entry.json",entry): return ""
	var list: Array = entries().filter(func(value:Dictionary)->bool:return canonical(value["path"]) != canonical(path))
	list.push_front(entry)
	return path if save_index(list) else ""

static func snapshot(session: Dictionary, title: String, thumbnail: Image = null, automatic: bool = false, source: String = "") -> String:
	var tagged: Dictionary = session.duplicate()
	tagged.merge(metadata(session,source),true)
	var id: String = tagged["project_id"]
	var suffix: String = str(Time.get_ticks_usec()) + "_" + str(randi())
	var path: String = folder(id) + "/snapshot_" + suffix + ".isocity.json"
	var entry: Dictionary = entry_for(tagged,path,title,"recovery" if automatic else "snapshot")
	entry["thumbnail"] = path.trim_suffix(".isocity.json") + ".png"
	tagged["recovery_meta"] = entry
	if not write_json(path,tagged): return ""
	if not write_json(path + ".entry.json",entry): return ""
	if thumbnail and not thumbnail.is_empty():
		var picture: Image = thumbnail.duplicate()
		picture.resize(240,150,Image.INTERPOLATE_BILINEAR)
		picture.save_png(entry["thumbnail"])
	var list: Array = entries().filter(func(value:Dictionary)->bool:return canonical(value["path"]) != canonical(path))
	list.push_front(entry)
	var count: int = 0
	for value in list.duplicate():
		if value.get("kind") not in ["snapshot","recovery"] or value.get("project_id") != id: continue
		count += 1
		if count <= MAX_SNAPSHOTS: continue
		if not can_prune(value["path"],id): continue
		list.erase(value)
		DirAccess.remove_absolute(value["path"])
		DirAccess.remove_absolute(value["path"] + ".entry.json")
		var thumb: String = str(value.get("thumbnail",""))
		if canonical(thumb.get_base_dir()) == canonical(folder(id)) and thumb.get_file().begins_with("snapshot_") and thumb.ends_with(".png"): DirAccess.remove_absolute(thumb)
	if not save_index(list): return ""
	return path
