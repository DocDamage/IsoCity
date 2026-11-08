extends RefCounted
const REGISTRY="res://resources/catalog/custom_registry.json"
const ROOT="res://assets/custom_assets"
static var registry_override: String=""

static func registry_path() -> String: return REGISTRY if registry_override.is_empty() else registry_override
static func read_registry(path: String="") -> Dictionary:
	if path.is_empty(): path=registry_path()
	if not FileAccess.file_exists(path): return {"ok":true,"assets":{}}
	var parser:=JSON.new(); var error: Error=parser.parse(FileAccess.get_file_as_string(path)); var value: Variant=parser.data if error==OK else null
	if not value is Dictionary or value.get("format")!=1 or not value.get("assets") is Dictionary: return {"ok":false,"reason":"The custom asset catalog is damaged. Restore it before importing more assets."}
	return {"ok":true,"assets":value["assets"]}
static func register(library: RefCounted) -> void:
	var catalog: Dictionary=read_registry()
	if not catalog["ok"]: return
	for id in catalog["assets"]:
		var asset: Variant=catalog["assets"][id]
		if descriptor_valid(id,asset): library.assets[id]=asset.duplicate(true)
static func descriptor_valid(id: Variant,asset: Variant) -> bool:
	if not id is String or not asset is Dictionary: return false
	if not asset.get("mode") in ["2d","3d"] or not id.begins_with(asset["mode"]+":Custom/"): return false
	if asset.get("id")!=id or not asset.get("name") is String or not asset.get("category") is String: return false
	if not asset.get("path") is String or not asset["path"].begins_with(ROOT+"/") or ".." in asset["path"] or not asset["path"].ends_with(".tscn"): return false
	if not asset.get("data") is Dictionary or not asset.get("behavior") is Dictionary or not FileAccess.file_exists(asset["path"]): return false
	if asset["data"].has("preview_path") and not asset["data"]["preview_path"] is String: return false
	if asset["mode"]=="2d":
		if not asset["data"].get("directions") is Dictionary or asset["data"]["directions"].is_empty(): return false
		for view in asset["data"]["directions"].values():
			if not view is Dictionary or not view.get("file") is String: return false
			for key in ["origin","footprint","grid_contact"]:
				if not view.get(key) is Array or view[key].size()!=2: return false
				for value in view[key]:
					if not (value is int or value is float) or not is_finite(value) or absf(value)>100000: return false
					if key=="footprint" and (value<1 or value>64 or float(value)!=roundf(value)): return false
	return true
static func save_registry(assets: Dictionary,path: String="") -> Error:
	if path.is_empty(): path=registry_path()
	var absolute: String=ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(absolute.get_base_dir()): return ERR_CANT_CREATE
	if not DirAccess.dir_exists_absolute(absolute.get_base_dir()):
		var error: Error=DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
		if error!=OK: return error
	var partial: String=absolute+"."+str(Time.get_ticks_usec())+".partial"
	var file:=FileAccess.open(partial,FileAccess.WRITE)
	if not file: return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"format":1,"assets":assets},"\t")); var error: Error=file.get_error(); file.close()
	if error==OK: error=DirAccess.rename_absolute(partial,absolute)
	if error!=OK: DirAccess.remove_absolute(partial)
	return error
