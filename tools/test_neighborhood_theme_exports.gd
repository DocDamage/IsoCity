extends "res://tools/test_neighborhood_palettes.gd"
const OUT="res://output/verification/asset_expansion/I16/"
func room_signature(room: Dictionary) -> Dictionary:
	var objects: Array=[]
	for item in room["objects"]:
		var record: Dictionary={}
		for field in ["asset","position","direction","scale","angle","tilt","colors","prop"]:
			if item.has(field):record[field]=item[field]
		objects.append(JSON.stringify(record))
	objects.sort();return {"objects":objects,"tiles":room["tiles"],"exit":room.get("exit",[]),"spawn":room.get("spawn",[]),"starter_kit":room.get("starter_kit",{})}
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT);library=preload("res://scripts/builder/asset_library.gd").new()
	for mode in ["2d","3d"]:
		var source: Dictionary=preload("res://scripts/builder/templates.gd").make(mode,"blank");source["economy"]={"enabled":true,"starting_cash":1000000};source["economy_account"]=Plan.Economy.fresh_account(source,library);var recipes: Array=[];var originals: Dictionary=source.duplicate(true)
		for theme in ["hanx_modern","village","industrial","historical"]:
			var definition: Dictionary=Palettes.palettes()[theme];var seed_value: int=17
			for candidate_seed in range(1,129):
				if Plan.Zone.Candidates.draw(candidate_seed,"0/0/prop",definition["revision"],"scenery-density",100)<definition["prop_density"]:seed_value=candidate_seed;break
			var config: Dictionary=Plan.defaults();config.merge({"theme":theme,"blocks":1,"density":100,"seed":seed_value,"origin":[12*(recipes.size()%2),12*floori(recipes.size()/2.0)]},true);var result: Dictionary=Plan.generate(source,config,library);check(result["ok"] and result["affordable"],"Permitted theme becomes an ordinary quoted district: "+mode+theme)
			if not result["ok"]:continue
			check(result["props"]>0,"The exported fixture includes an actual supplied street prop: "+mode+theme)
			source=result["data"];recipes.append({"theme":theme,"config":config,"uid":result["uid"],"bounds":[result["bounds"].position.x,result["bounds"].position.y,result["bounds"].size.x,result["bounds"].size.y]})
		var viewport:=SubViewport.new();viewport.size=Vector2i(64,64);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED;root.add_child(viewport);var world: Node=load("res://scripts/builder/world_"+mode+".gd").new();world.library=library;viewport.add_child(world);world.apply(source);world.player.set_physics_process(false)
		var expected_assets: Dictionary={};var expected_rooms: Dictionary={};var ids: Dictionary={}
		for item in source["objects"]:
			ids[item["asset"]]=true
			if item.get("neighborhood_palette_selection",{}).get("role")=="building":expected_rooms[item["asset"]]=room_signature(preload("res://scripts/builder/interiors.gd").make_for(item,mode,library))
		for tile in source["tiles"]:ids[tile["asset"]]=true
		for id in ids:
			var asset: Dictionary=library.assets[id];var preview: String=asset["data"].get("preview_path","")
			if asset["mode"]=="3d" and preview.is_empty():preview="res://resources/previews_3d/"+id.trim_prefix("3d:")+".png"
			if preview.is_empty():
				var texture: Texture2D=library.icon(id);preview=texture.atlas.resource_path if texture is AtlasTexture else texture.resource_path
			check(not preview.is_empty() and FileAccess.file_exists(preview) and not preview.ends_with("missing_object.png"),"Host records meaningful source artwork for every selected building, scenery and paving asset: "+id)
			expected_assets[id]={"path":asset["path"],"preview":preview,"preview_sha256":FileAccess.get_sha256(preview)}
		var destination: String="res://output/neighborhood_themes_"+mode+".zip";var exported: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(world,source,library,destination);check(exported["ok"],"All four permitted themes package their exact selected dependencies: "+mode+exported["message"]);FileAccess.open(OUT+"theme_export_expectation_"+mode+".json",FileAccess.WRITE).store_string(JSON.stringify({"world":source,"districts":recipes,"palettes":Palettes.definitions(),"assets":expected_assets,"rooms":expected_rooms},"\t"))
		check(source["economy_account"]["cash"]<1000000 and not Plan.Zone.Citizen.settings(source)["enabled"] and not Plan.Zone.Traffic.settings(source)["enabled"] and not Plan.Zone.settings(source)["enabled"],"The fixture has intentional quoted purchases and disabled unrelated simulations: "+mode)
		if mode=="2d":
			var config: Dictionary=Plan.defaults();config.merge({"theme":"korean_street","blocks":1,"density":100,"seed":17,"origin":[0,0]},true);var korean: Dictionary=Plan.generate(originals,config,library);check(korean["ok"],"Limited Korean source remains usable as a local district")
			var protected: String=OUT+"preserved_korean_source.zip";FileAccess.open(protected,FileAccess.WRITE).store_buffer(FileAccess.get_file_as_bytes(destination));var good_hash: String=FileAccess.get_sha256(protected);var blocked: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(world,korean["data"],library,protected);check(not blocked["ok"] and blocked["message"].contains("license") and FileAccess.get_sha256(protected)==good_hash,"Restricted Korean source export preserves an actual good permitted ZIP")
			var metadata: Dictionary={"title":"Korean street layout","author":"Local verification","description":"Original artwork requires the supplied local asset pack.","license":"Layout only; supplied artwork retains its own terms.","source_url":"","kind":"city"};var prepared: Dictionary=preload("res://scripts/builder/creation_share.gd").prepare({"kind":"city","document":korean["data"]},metadata,library.icon(korean["data"]["objects"][0]["asset"]).get_image(),library);check(prepared["ok"],"Layout-only sharing remains available without redistributing Korean source files")
			if prepared["ok"]:
				var shared_path: String=OUT+"korean_street.isocity-creation.json";FileAccess.open(shared_path,FileAccess.WRITE).store_string(JSON.stringify(prepared["creation"]));var reopened: Dictionary=preload("res://scripts/builder/creation_share.gd").read(shared_path,library);check(reopened["ok"] and reopened["missing"].is_empty() and reopened["source"]["document"]==JSON.parse_string(JSON.stringify(korean["data"])),"Korean layout source reopens exactly with installed local art and provenance")
		viewport.free();await process_frame
	print("NEIGHBORHOOD THEME EXPORTS: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
