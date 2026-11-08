extends RefCounted

const OBJECT_2D: String = "2d:__missing_object__"
const TILE_2D: String = "2d:__missing_tile__"
const OBJECT_3D: String = "3d:__missing_object__"

static func register(library: RefCounted) -> void:
	for id in [OBJECT_2D,TILE_2D,OBJECT_3D]:
		if library.assets.has(id): continue
		var mode: String = "3d" if id == OBJECT_3D else "2d"
		var tile: bool = id == TILE_2D
		var picture: String = "missing_tile" if tile else "missing_object"
		var height: int = 16 if tile else 40
		library.assets[id] = {"id":id,"mode":mode,"name":"Missing ground" if tile else "Missing asset","category":"Floors" if tile else "Decorations","hidden":true,"path":"res://scenes/builder/" + ("missing_object_3d" if mode == "3d" else "missing_tile_2d" if tile else "missing_object_2d") + ".tscn", "data":{"directions":{"SE":{"file":"../../editor/"+picture+".png","frame_width":32,"frame_height":height,"origin":[16,1 if tile else 16],"footprint":[1,1],"grid_contact":[16,17 if tile else 32]}}},"behavior":{"layer":"Ground" if tile else "Decorations","ground":tile,"building":false,"door":false,"vehicle":false,"collision":"box"}}

static func register_used(data: Dictionary, library: RefCounted) -> void:
	for item in data.get("objects",[]):
		if not item is Dictionary: continue
		if item.get("asset") in [OBJECT_2D,TILE_2D,OBJECT_3D]: register(library)
		if item.get("interior") is Dictionary: register_used(item["interior"],library)

static func available(id: String, library: RefCounted, cache: Dictionary) -> bool:
	if cache.has(id): return cache[id]
	if not library.assets.has(id): cache[id] = false; return false
	var asset: Dictionary = library.assets[id]
	var result: bool = path_available(asset["path"],{}) and load_checked(asset["path"],false)
	for view in asset.get("data",{}).get("directions",{}).values():
		var file: String = view.get("file","")
		if file.is_empty(): continue
		var path: String = "res://assets/" + file.trim_prefix("../../") if file.begins_with("../../") else "res://assets/pixel_isometric/" + file
		result = result and texture_available(path)
	for animation in asset.get("data",{}).get("animations",{}).values():
		for view in animation.get("directions",{}).values(): result=result and texture_available(preload("res://scripts/sprite_view.gd").path(view))
	cache[id] = result
	return result

static func load_checked(path: String, texture: bool) -> bool:
	# Missing/corrupt source files are an expected repair case. Convert the
	# loader's null result into a report entry rather than engine error spam.
	# Restore logging immediately; callers still validate the returned type.
	var logging: bool = Engine.print_error_messages
	Engine.print_error_messages = false
	var resource: Resource = ResourceLoader.load(path)
	Engine.print_error_messages = logging
	return resource is Texture2D if texture else resource is PackedScene and resource.can_instantiate()

static func texture_available(path: String) -> bool:
	return path.begins_with("res://assets/") and not ".." in path and ResourceLoader.exists(path,"Texture2D") and path_available(path,{}) and load_checked(path,true)

static func path_available(path: String, visited: Dictionary) -> bool:
	if visited.has(path): return true
	visited[path] = true
	if not FileAccess.file_exists(path): return false
	if path.get_extension() in ["tscn","tres"]:
		var pattern := RegEx.new()
		pattern.compile('\\[ext_resource[^\\n]*path="([^"]+)"')
		for match_value in pattern.search_all(FileAccess.get_file_as_string(path)):
			if not path_available(match_value.get_string(1),visited): return false
	elif path.get_extension() == "gltf":
		var parser := JSON.new()
		if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary: return false
		var data: Dictionary = parser.data
		if not data.get("buffers",[]) is Array or not data.get("images",[]) is Array: return false
		for entry in data.get("buffers",[]) + data.get("images",[]):
			if not entry is Dictionary or not entry.get("uri","") is String: return false
			var uri: String = entry.get("uri","")
			if not uri.is_empty() and not uri.begins_with("data:") and not path_available(path.get_base_dir()+"/"+uri,visited): return false
	return true
