extends RefCounted

# Source packages keep res:// paths, but never depend on the editor's import cache.
const REGISTRY: String = "res://resources/catalog/catalog_registry.json"
const CatalogSource = preload("res://scripts/catalog.gd")
const Templates = preload("res://scripts/builder/templates.gd")
var files: Dictionary = {}
var generated: Dictionary = {}
var assets: Dictionary = {}
var errors: Array[String] = []
var license_folders: Dictionary = {}
var future_rooms: Dictionary = {}
var project_policy: Dictionary={}
var library: RefCounted
var paths := RegEx.new()

func save(world: Node, data: Dictionary, source_library: RefCounted, destination: String,project_palette: Dictionary={}) -> Dictionary:
	if project_palette.is_empty():project_palette=source_library.project_palette
	project_policy=project_palette.duplicate(true)
	if not project_palette.is_empty() and not preload("res://scripts/builder/asset_collections.gd").project_valid(project_palette):return {"ok":false,"message":"Review the project recommendation before exporting it."}
	files.clear(); generated.clear(); assets.clear(); errors.clear(); license_folders.clear();future_rooms.clear()
	library = source_library
	paths.compile('["\'](res://[^"\'\\r\\n]+)["\']')
	collect_document(data)
	if preload("res://scripts/builder/zone_plan.gd").settings(data)["enabled"]:
		for lot in data.get("zones",[]):
			for asset in preload("res://scripts/builder/zone_plan.gd").future_assets(lot,data["mode"],library,project_policy):
				collect_asset(asset);collect_future_room(asset,data["mode"])
	for asset in preload("res://scripts/builder/zone_stage_plan.gd").required_assets(data,library): collect_asset(asset)
	# Rooms are created lazily, including buildings the player has never entered.
	collect_document(Templates.make(data["mode"], "room"))
	collect_asset("2d:Office_Worker")
	var citizen_appearance: String=preload("res://scripts/builder/citizen_plan.gd").settings(data).get("appearance","")
	if data["mode"]=="2d" and not citizen_appearance.is_empty(): collect_asset(citizen_appearance)
	var roles: Array=[]
	if preload("res://scripts/builder/transit_plan.gd").settings(data)["enabled"]: roles.append("transit")
	if preload("res://scripts/builder/traffic_plan.gd").settings(data)["enabled"]: roles.append("traffic")
	if preload("res://scripts/builder/service_plan.gd").settings(data)["enabled"]:
		for item in data["objects"]:
			var services=preload("res://scripts/builder/service_plan.gd")
			var kind: String=services.profile(item)["kind"]
			if kind=="none": continue
			if kind not in roles: roles.append(kind)
			if data["mode"]=="2d": collect_asset(services.unit(kind)["worker_2d"])
	for id in preload("res://scripts/builder/fleet_plan.gd").required(data,roles): collect_asset(id)
	var school_bus: String=preload("res://scripts/builder/school_plan.gd").required_bus(data)
	if not school_bus.is_empty(): collect_asset(school_bus)
	for asset in preload("res://scripts/builder/delivery_plan.gd").required_assets(data): collect_asset(asset)
	for asset in preload("res://scripts/builder/village_plan.gd").required_delivery_art(data): collect_asset(asset)
	for asset in preload("res://scripts/builder/construction_plan.gd").required_assets(data): collect_asset(asset)
	for asset in preload("res://scripts/builder/market_plan.gd").required_assets(data): collect_asset(asset)
	for asset in preload("res://scripts/builder/garden_plan.gd").required_assets(data): collect_asset(asset)
	for asset in preload("res://scripts/builder/cooking_plan.gd").required_art(data): collect_asset(asset)
	for asset in preload("res://scripts/builder/fitness_plan.gd").required_art(data): collect_asset(asset)
	if not errors.is_empty(): return failure()
	if not world.is_inside_tree(): return {"ok":false,"message":"The layout is not ready to export."}
	# Walking inside a room suspends the exterior's environment, visibility and
	# floor collisions. Build from authoritative data without altering that visit.
	var preview := SubViewport.new()
	preview.size = Vector2i(64,64)
	preview.own_world_3d = true
	preview.render_target_update_mode = SubViewport.UPDATE_DISABLED
	world.get_tree().root.add_child(preview)
	var scene_world: Node = load("res://scripts/builder/world_" + data["mode"] + ".gd").new()
	scene_world.library = library
	preview.add_child(scene_world)
	scene_world.apply(data)
	var scratch: String = "user://portable_" + str(Time.get_ticks_usec()) + ".tscn"
	var result: Error = preload("res://scripts/builder/exporter.gd").save_scene(scene_world, data, library, scratch,project_policy)
	preview.free()
	if result != OK: return {"ok":false,"message":"Could not prepare the scene: " + error_string(result)}
	generated["city.tscn"] = FileAccess.get_file_as_bytes(scratch)
	scan_resource(FileAccess.get_file_as_string(scratch))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch))
	for path in ["scripts/builder/world_2d.gd","scripts/builder/world_3d.gd","scripts/iso_object.gd","scripts/iso_character.gd","scenes/builder/missing_object_2d.tscn","scenes/builder/missing_tile_2d.tscn","scenes/builder/missing_object_3d.tscn"]:
		collect("res://" + path)
	var utilities=preload("res://scripts/builder/utility_plan.gd")
	for kind in utilities.KINDS:
		if utilities.authored(data,kind): collect(utilities.Profiles.CATALOGS[kind])
	make_registry()
	generated["project.godot"] = ('config_version=5\n\n[application]\nconfig/name=%s\nrun/main_scene="res://city.tscn"\nconfig/features=PackedStringArray("4.7", "GL Compatibility")\n\n[display]\nwindow/size/viewport_width=1480\nwindow/size/viewport_height=900\nwindow/stretch/mode="canvas_items"\n\n[rendering]\nrenderer/rendering_method="gl_compatibility"\nrenderer/rendering_method.mobile="gl_compatibility"\ntextures/canvas_textures/default_texture_filter=0\n' % JSON.stringify(data.get("title","My city"))).to_utf8_buffer()
	if data["mode"]=="3d":
		var project_text: String=generated["project.godot"].get_string_from_utf8()
		project_text=project_text.replace('"GL Compatibility"','"Forward Plus"').replace('renderer/rendering_method="gl_compatibility"','renderer/rendering_method="forward_plus"').replace('renderer/rendering_method.mobile="gl_compatibility"','renderer/rendering_method.mobile="mobile"')
		generated["project.godot"]=project_text.to_utf8_buffer()
	generated["README.txt"] = ("Portable IsoCity project\n\nOpen project.godot with Godot 4.7 or later. Let the editor import the included source assets, then press F6 on city.tscn or F5 to play. The first import can take a little time.\n\nTab switches between walking and camera controls. WASD moves; E uses doors, furniture and vehicles; X recovers a stuck character. Mouse wheel zooms. P opens photo controls, F4 chooses a clean PNG destination, and F5 records/saves a camera path. Player camera libraries are saved separately in the Godot user-data photos folder. 3D projects use Forward+ (Mobile on mobile) for photo depth of field; 2D projects use Compatibility and focus-band blur.\n\ncity-source.json preserves the exported layout, owned interiors and repair metadata. The IsoCity editor can open this project-data file. The portable Godot project runs the current layout; it does not include the Studio editor.\n\nexport-manifest.json lists included asset IDs, source files and checksums. Supplied asset license files are included at their original paths. Check those terms before redistributing assets or this project.\n").to_utf8_buffer()
	var documents: Dictionary = {"2d":Templates.make("2d","blank"),"3d":Templates.make("3d","blank")}
	documents[data["mode"]] = data
	var source: Dictionary={"version":1,"grid_version":2,"active_mode":data["mode"],"documents":documents}
	if not project_palette.is_empty():source["project_palette"]=project_palette.duplicate(true)
	generated["city-source.json"] = JSON.stringify(source, "\t").to_utf8_buffer()
	if not errors.is_empty(): return failure()
	var manifest: Dictionary = {"format":1,"title":data.get("title","My city"),"dimension":data["mode"],"godot":"4.7+","assets":assets.keys(),"files":[]}
	var names: Array = files.keys() + generated.keys()
	names.sort()
	for name in names:
		var bytes: PackedByteArray = generated[name] if generated.has(name) else FileAccess.get_file_as_bytes(files[name])
		manifest["files"].append({"path":name,"bytes":bytes.size(),"sha256":hash_bytes(bytes)})
	generated["export-manifest.json"] = JSON.stringify(manifest,"\t").to_utf8_buffer()
	if not destination.to_lower().ends_with(".zip"): destination += ".zip"
	var absolute: String = ProjectSettings.globalize_path(destination)
	if not DirAccess.dir_exists_absolute(absolute.get_base_dir()): return {"ok":false,"message":"Choose an existing destination folder."}
	# Write beside the destination and commit only a completely closed archive.
	var partial: String = absolute + "." + str(Time.get_ticks_usec()) + ".partial"
	var zip := ZIPPacker.new()
	result = zip.open(partial)
	if result == OK:
		for name in names + ["export-manifest.json"]:
			result = zip.start_file(name)
			if result == OK: result = zip.write_file(generated[name] if generated.has(name) else FileAccess.get_file_as_bytes(files[name]))
			if result == OK: result = zip.close_file()
			if result != OK: break
		var closed: Error = zip.close()
		if result == OK: result = closed
	if result == OK: result = DirAccess.rename_absolute(partial,absolute)
	if result != OK:
		DirAccess.remove_absolute(partial)
		return {"ok":false,"message":"Could not write the package: " + error_string(result)}
	return {"ok":true,"path":destination,"files":names.size()+1,"assets":assets.size(),"message":"Portable project exported · extract the ZIP, open project.godot in Godot, and press F5."}

func failure() -> Dictionary:
	return {"ok":false,"message":"Export stopped: " + errors[0],"errors":errors.duplicate()}

func hash_bytes(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

func collect_document(data: Dictionary) -> void:
	if data.get("mode")=="2d" and data.get("roads",[]).any(func(road: Dictionary)->bool: return road.get("cycle_access","none")!="none"):
		collect_asset("2d:Bike_Lane")
	var pet_asset: String=preload("res://scripts/builder/pet_plan.gd").required(data)
	if not pet_asset.is_empty(): collect_asset(pet_asset)
	for id in preload("res://scripts/builder/fleet_plan.gd").required(data): collect_asset(id)
	for id in preload("res://scripts/builder/space_outpost_plan.gd").required(data): collect_asset(id)
	for lot in data.get("zones",[]):
		if lot.get("proposal") is Dictionary and not lot["proposal"].is_empty():
			collect_asset(lot["proposal"]["asset"]);collect_future_room(lot["proposal"]["asset"],data["mode"])
	for proposal in data.get("blueprints",[]):
		for item in preload("res://scripts/builder/blueprint_plan.gd").proposal_objects(proposal):
			collect_asset(item["asset"])
			if proposal["kind"]=="assembly":collect_values(item.get("colors",[]))
			if item.get("interior") is Dictionary:collect_document(item["interior"])
			else:collect_future_room(item["asset"],data["mode"])
	for floor in data.get("floors",[]): collect_document(floor["room"])
	for item in data.get("objects",[]):
		collect_asset(item["asset"])
		if item["asset"].begins_with("3d:") and item.get("traffic_control",{}).get("kind","")=="signal":
			var controls=preload("res://scripts/builder/traffic_control_plan.gd")
			if controls.profile(item["asset"]).get("kind","")=="signal":
				for id in controls.definitions()["models"].values(): collect_asset(id)
		collect_values(item.get("colors",[]))
		if item.get("interior") is Dictionary: collect_document(item["interior"])
		else:collect_future_room(item["asset"],data["mode"])
	for tile in data.get("tiles",[]):
		if tile is Dictionary:
			if tile.has("asset"): collect_asset(tile["asset"])
			collect_values(tile.get("colors",[]))

func collect_future_room(asset: String,mode: String) -> void:
	var key: String=mode+":"+asset
	if future_rooms.has(key):return
	future_rooms[key]=true
	if project_policy.get("restricted",false):
		var room: Dictionary=preload("res://scripts/builder/interiors.gd").make_for({"asset":asset},mode,library)
		if not preload("res://scripts/builder/asset_palette_policy.gd").check_config({},room,project_policy,library)["ok"]:return
	for dependency in preload("res://scripts/builder/interior_kits.gd").dependencies_for(asset,mode,library):collect_asset(dependency)

func collect_values(value: Variant) -> void:
	if value is Dictionary:
		for child in value.values(): collect_values(child)
	elif value is Array:
		for child in value: collect_values(child)
	elif value is String and value.begins_with("res://"): collect(value)

func collect_asset(id: String) -> void:
	if assets.has(id): return
	if not library.assets.has(id): errors.append("Asset definition unavailable: " + id); return
	assets[id] = true
	var asset: Dictionary = library.assets[id]
	if asset.get("data",{}).get("source_export_allowed",true)==false:
		errors.append("The supplied license for %s restricts redistributing asset files. Share a creation layout instead of a source project ZIP." % library.pack_name(asset)); return
	collect(asset["path"])
	var visual: Dictionary = preload("res://scripts/builder/rendering_budget.gd").profile(asset)
	var detail: String = visual.get("full",{}).get("path","")
	if not detail.is_empty() and FileAccess.file_exists(detail): collect(detail)
	if asset.get("data",{}).has("preview_path"): collect(asset["data"]["preview_path"])
	elif asset["mode"]=="3d":
		var preview: String="res://resources/previews_3d/"+id.trim_prefix("3d:")+".png"
		if FileAccess.file_exists(preview):collect(preview)
	# Prepared sprite sheets can live apart from their original pack's notices.
	for original in asset.get("data",{}).get("source_files",[]):
		if original.begins_with("res://assets/"): collect_licenses(original.get_base_dir())
	var harbor = preload("res://scripts/builder/harbor_plan.gd")
	if id == harbor.VESSEL: collect("res://assets/BOAT/Read Me.txt")
	for view in asset.get("data",{}).get("directions",{}).values():
		var file: String = view.get("file","")
		if not file.is_empty(): collect("res://assets/" + file.trim_prefix("../../") if file.begins_with("../../") else "res://assets/pixel_isometric/" + file)
	for animation in asset.get("data",{}).get("animations",{}).values():
		for view in animation.get("directions",{}).values():
			var file: String=view.get("file","")
			if not file.is_empty(): collect("res://assets/"+file.trim_prefix("../../") if file.begins_with("../../") else "res://assets/pixel_isometric/"+file)

func make_registry() -> void:
	var registry: Dictionary = {"items":{},"categories":[],"by_category":{},"tilesets":CatalogSource.get_registry().get("tilesets",{})}
	for id in assets:
		if not id.begins_with("2d:") or id.begins_with("2d:__missing_"): continue
		var item: Dictionary = library.assets[id]["data"].duplicate(true)
		item["scene_path"] = library.assets[id]["path"]
		registry["items"][id.trim_prefix("2d:")] = item
		var category: String = item["category"]
		if not registry["categories"].has(category):
			registry["categories"].append(category)
			registry["by_category"][category] = []
		registry["by_category"][category].append(id.trim_prefix("2d:"))
	generated[REGISTRY.trim_prefix("res://")] = JSON.stringify(registry,"\t").to_utf8_buffer()
	var custom: Dictionary={}
	for id in assets:
		if id.contains(":Custom/"): custom[id]=library.assets[id]
	if not custom.is_empty(): generated["resources/catalog/custom_registry.json"]=JSON.stringify({"format":1,"assets":custom},"\t").to_utf8_buffer()
	var models: Dictionary={}
	for id in assets:
		if id.begins_with("3d:Supplemental_"): models[id]=library.assets[id]
	if not models.is_empty(): generated["resources/catalog/supplemental_registry.json"]=JSON.stringify({"version":1,"items":{},"models":models},"\t").to_utf8_buffer()
	var metadata: Dictionary = {}
	for id in assets:
		var entry: Dictionary = {}
		for key in ["display_name", "aliases", "name_key", "name_source", "family_id", "family_name", "palette_id", "lighting_id", "appearance_group", "animation_status", "animation_note", "supplied_clips", "runtime_actions", "content_kind", "content_note", "replacement_ids", "source_view_kind"]:
			if library.assets[id]["data"].has(key): entry[key] = library.assets[id]["data"][key]
		if not entry.is_empty(): metadata[id] = entry
	generated["resources/catalog/asset_metadata.json"] = JSON.stringify({"version": 1, "assets": metadata}, "\t").to_utf8_buffer()
	var themes: Dictionary={}
	for id in assets:
		themes[id]={"themes":library.themes.tags(library.assets[id]),"theme_note":library.assets[id]["data"].get("theme_note","")}
	generated["resources/catalog/asset_theme_metadata.json"]=JSON.stringify({"version":1,"assets":themes},"\t").to_utf8_buffer()
	generated["resources/catalog/asset_themes.json"]=JSON.stringify({"version":1,"definitions":library.themes.definitions},"\t").to_utf8_buffer()
	generated["resources/catalog/asset_style_models.json"]=JSON.stringify(library.styles.subset(assets),"\t").to_utf8_buffer()
	generated["resources/catalog/asset_style_rules.json"]=JSON.stringify({"version":1,"packs":library.styles.rules},"\t").to_utf8_buffer()
	generated["resources/catalog/asset_semantics.json"]=JSON.stringify(library.search_index.subset(assets),"\t").to_utf8_buffer()

func scan_text(text: String, required: bool) -> void:
	for found in paths.search_all(text):
		var path: String = found.get_string(1)
		# Script fallback names and dynamically assembled prefixes aren't files.
		if not required and "%" in path: continue
		if FileAccess.file_exists(path): collect(path)
		elif required or path.get_extension() in ["gd","gdshader","tscn","tres","png"]: errors.append("Missing dependency: " + path)

func scan_resource(text: String) -> void:
	# Saved metadata may deliberately archive missing source paths. Only actual
	# external resource declarations are dependencies of a serialized scene.
	var external := RegEx.new()
	external.compile('\\[ext_resource[^\\n]*path="([^"]+)"')
	for found in external.search_all(text): collect(found.get_string(1))

func collect(path: String) -> void:
	path = path.simplify_path()
	if path=="res://resources/catalog/asset_semantics.json":return
	if not path.begins_with("res://") or ".." in path.trim_prefix("res://").split("/"): errors.append("Unsupported dependency: " + path); return
	if path in ["res://resources/catalog/asset_metadata.json","res://resources/catalog/asset_style_models.json","res://resources/catalog/asset_style_rules.json","res://resources/catalog/asset_themes.json","res://resources/catalog/asset_theme_metadata.json","res://resources/catalog/reviewed_registry.json","res://resources/catalog/custom_registry.json",REGISTRY,"res://resources/catalog/imported_registry.json","res://resources/catalog/supplemental_registry.json","res://resources/catalog/swat_registry.json","res://assets/pixel_isometric/items.json"]: return
	var relative: String = path.trim_prefix("res://")
	if relative.begins_with(".godot/"): return
	if files.has(relative): return
	if not FileAccess.file_exists(path): errors.append("Missing dependency: " + path); return
	files[relative] = path
	if path.get_extension() in ["tscn","tres"]:
		scan_resource(FileAccess.get_file_as_string(path))
	elif path.get_extension() in ["gd","gdshader","gdshaderinc","import"]:
		scan_text(FileAccess.get_file_as_string(path),false)
	elif path.get_extension() == "gltf":
		var gltf: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not gltf is Dictionary: errors.append("Unreadable model: " + path); return
		for record in gltf.get("buffers",[]) + gltf.get("images",[]):
			var uri: String = record.get("uri","")
			if not uri.is_empty() and not uri.begins_with("data:"): collect(path.get_base_dir().path_join(uri.uri_decode()))
	for suffix in [".uid",".import"]:
		if FileAccess.file_exists(path+suffix): collect(path+suffix)
	if relative.begins_with("assets/"): collect_licenses(path.get_base_dir())

func collect_licenses(folder: String) -> void:
	while folder.begins_with("res://assets"):
		if license_folders.has(folder): return
		license_folders[folder] = true
		var entries: PackedStringArray = DirAccess.get_files_at(folder) if DirAccess.dir_exists_absolute(folder) else PackedStringArray()
		for file in entries:
			if file.to_lower().get_basename() in ["license","licence","credits","attribution"]:
				var path: String = folder.path_join(file)
				files[path.trim_prefix("res://")] = path
		folder = folder.get_base_dir()
