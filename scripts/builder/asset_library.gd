extends RefCounted

const Catalog = preload("res://scripts/catalog.gd")
const TileRotation = preload("res://scripts/iso_tile_rotation.gd")
const ModelPreview = preload("res://scripts/builder/model_preview.gd")
const MISSING_ICON = preload("res://assets/editor/missing_object.png")
const ICON_LIMIT = 192
const ICON_BYTES = 48*1024*1024
var project_palette: Dictionary={}
var project_palette_ids: Dictionary={}
var project_palette_revision: int=0
func set_project_palette(value: Dictionary) -> bool:
	if value==project_palette:return true
	if not value.is_empty() and not preload("res://scripts/builder/asset_collections.gd").project_valid(value):return false
	project_palette=value.duplicate(true)
	if not project_palette.is_empty():project_palette["version"]=1
	project_palette_ids=preload("res://scripts/builder/asset_palette_policy.gd").compile(project_palette)
	project_palette_revision+=1
	return true
var assets: Dictionary = {}
var icons: Dictionary = {}
var icon_sources: Dictionary = {}
var search_index = preload("res://scripts/builder/asset_search.gd").new()
var families = preload("res://scripts/builder/asset_families.gd").new()
var themes = preload("res://scripts/builder/asset_themes.gd").new()
var capabilities = preload("res://scripts/builder/asset_capabilities.gd").new()
var styles = preload("res://scripts/builder/asset_styles.gd").new()
var tasks = preload("res://scripts/builder/task_collections.gd").new()

func _init() -> void:
	for id in Catalog.get_registry()["items"]:
		var data: Dictionary = Catalog.get_item(id)
		assets["2d:" + id] = {"id": "2d:" + id, "mode": "2d", "name": data.get("display_name", id).replace("_", " "),
			"category": data["category"], "path": Catalog.get_scene_path(id), "data": data}
	for pack in (DirAccess.get_directories_at("res://scenes/items_3d") if DirAccess.dir_exists_absolute("res://scenes/items_3d") else PackedStringArray()):
		for file in DirAccess.get_files_at("res://scenes/items_3d/" + pack):
			if file.ends_with(".tscn"):
				var id: String = "3d:" + pack + "/" + file.get_basename()
				assets[id] = {"id": id, "mode": "3d", "name": file.get_basename().replace("_", " "),
					"category": pack.replace("HanX_", "").replace("_", " "), "path": "res://scenes/items_3d/" + pack + "/" + file, "data": {}}

	for id in assets:
		assets[id]["behavior"] = assets[id]["data"].get("behavior",preload("res://scripts/builder/asset_behavior.gd").get_behavior(id)).duplicate(true)
	for id in Catalog.get_registry().get("models",{}):
		var descriptor: Dictionary=Catalog.get_registry()["models"][id]
		if assets.has(id): assets[id]=descriptor.duplicate(true)
	preload("res://scripts/builder/custom_assets.gd").register(self)
	rebuild_indexes()

func rebuild_indexes() -> void:
	families.build(assets)
	themes.build(assets)
	capabilities.build(self)
	styles.build(self)
	search_index.build(assets)
	tasks.build(assets)

func categories(mode: String) -> Array[String]:
	var result: Array[String] = []
	for asset in assets.values():
		if asset.get("hidden",false): continue
		if (mode == "all" or asset["mode"] == mode or (mode == "added" and asset["data"].has("source_pack"))) and not result.has(asset["category"]):
			result.append(asset["category"])
	result.sort()
	return result

static func pack_name(asset: Dictionary) -> String:
	if asset.get("data",{}).has("source_pack"): return str(asset["data"]["source_pack"])
	if asset["mode"] == "3d": return str(asset["id"]).trim_prefix("3d:").get_slice("/",0)
	if str(asset.get("path","")).contains("/RPG_World/"): return "RPG World"
	return "Pixel Isometric"

func find(mode: String, category: String, query: String, favorites: Array, only_favorites: bool, pack: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var terms: PackedStringArray = search_index.words(query)
	var ranks: Dictionary = {}
	for asset in assets.values():
		if asset.get("hidden",false) or asset.get("unavailable",false): continue
		if (mode != "all" and asset["mode"] != mode and not (mode == "added" and asset["data"].has("source_pack"))) or (category != "All assets" and asset["category"] != category):
			continue
		if only_favorites and not favorites.has(asset["id"]):
			continue
		if not pack.is_empty() and pack_name(asset) != pack: continue
		var score: int = search_index.rank(asset, terms) if not terms.is_empty() else 0
		if score < 0: continue
		ranks[asset["id"]] = score
		result.append(asset)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if ranks[a["id"]] != ranks[b["id"]]: return ranks[a["id"]] > ranks[b["id"]]
		var by_name: int = a["name"].naturalnocasecmp_to(b["name"])
		return by_name < 0 if by_name != 0 else a["id"] < b["id"]
	)
	return result

func icon(id: String) -> Texture2D:
	return icon_for(id,"")

func icon_for(id: String, direction: String) -> Texture2D:
	if not assets.has(id): return null
	var asset: Dictionary = assets[id]
	if asset.get("hidden",false) or asset.get("unavailable",false): return MISSING_ICON
	var data: Dictionary = asset["data"]
	var frame: Dictionary = {}
	var path: String = ""
	var model: bool = asset["mode"] == "3d"
	if model:
		var supplied: Variant = data.get("preview_path","res://resources/previews_3d/"+id.trim_prefix("3d:")+".png")
		path = supplied if supplied is String else ""
	elif direction.is_empty() and data.has("preview_path"):
		path = data["preview_path"]
	else:
		var directions_by_name: Dictionary = data.get("directions",{})
		if not directions_by_name.is_empty():
			frame = directions_by_name[direction] if not direction.is_empty() else directions_by_name.get("SE",directions_by_name.values()[0])
			var file: String = frame.get("file","")
			path = "res://assets/"+file.trim_prefix("../../") if file.begins_with("../../") else "res://assets/pixel_isometric/"+file
	var key: String = id if direction.is_empty() else id+":"+direction
	var stamp: Array = [asset["path"],path,frame.hash(),data.get("source_hash",""),FileAccess.get_modified_time(path) if FileAccess.file_exists(path) else 0]
	if icons.has(key) and icon_sources.get(key) == stamp:
		var existing: Texture2D = icons[key]
		icons.erase(key)
		icons[key] = existing
		return existing
	var result: Texture2D
	if model:
		result = ModelPreview.texture_file(path)
		if not ModelPreview.meaningful(result): result = MISSING_ICON
	elif FileAccess.file_exists(path):
		var texture := load(path) as Texture2D
		if texture and not frame.is_empty():
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			var area: Rect2 = preload("res://scripts/sprite_view.gd").region(frame,texture)
			atlas.region = Rect2(area.position,Vector2(frame.get("frame_width",area.size.x),frame.get("frame_height",area.size.y)))
			result = atlas
		else: result = texture
	if result:
		icons.erase(key)
		icons[key] = result
		icon_sources[key] = stamp
		trim_icons()
	return result

func trim_icons() -> void:
	# Estimate backing storage for distinct source textures, including atlases.
	# Actual renderer residency also depends on imports, mipmaps and other users.
	var textures: Dictionary = {}
	var resident: int = 0
	for key in icons:
		var backing: Texture2D = backing_texture(icons[key])
		var id: int = backing.get_instance_id()
		if textures.has(id): textures[id] += 1
		else:
			textures[id] = 1
			resident += backing.get_width()*backing.get_height()*4
	while not icons.is_empty() and (icons.size() > ICON_LIMIT or resident > ICON_BYTES):
		var oldest: String = icons.keys()[0]
		var backing: Texture2D = backing_texture(icons[oldest])
		var id: int = backing.get_instance_id()
		textures[id] -= 1
		if textures[id] == 0: resident -= backing.get_width()*backing.get_height()*4
		icons.erase(oldest)
		icon_sources.erase(oldest)
	for key in icon_sources.keys():
		if not icons.has(key): icon_sources.erase(key)

func backing_texture(texture: Texture2D) -> Texture2D:
	return texture.atlas if texture is AtlasTexture and texture.atlas else texture

func invalidate_icons(id: String) -> void:
	for key in icons.keys():
		if key == id or key.begins_with(id+":"):
			icons.erase(key)
			icon_sources.erase(key)

func directions(id: String) -> Array:
	if id.begins_with("3d:"):
		return ["0", "90", "180", "270"]
	if is_ground_tile(id):
		return TileRotation.DIRECTIONS
	return assets.get(id, {}).get("data", {}).get("directions", {}).keys()

func is_ground_tile(id: String) -> bool:
	return assets.has(id) and assets[id]["mode"] == "2d" and assets[id]["behavior"].get("ground", false)

func valid_direction(id: String, direction: String) -> bool:
	if (id.begins_with("3d:") or is_ground_tile(id)) and direction.is_valid_float():
		return is_finite(float(direction)) and absf(float(direction)) <= 360000
	return directions(id).has(direction)

func directional_icon(id: String, direction: String) -> Texture2D:
	if not id.begins_with("2d:") or is_ground_tile(id): return icon(id)
	var entry: Dictionary = assets.get(id,{}).get("data",{}).get("directions",{}).get(direction,{})
	return icon_for(id,direction) if not entry.is_empty() else icon(id)
