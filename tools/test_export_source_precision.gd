extends SceneTree
const OUT="res://output/verification/asset_expansion/I15/"
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func normalized(value: Dictionary) -> Dictionary:return JSON.parse_string(JSON.stringify(value))
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT);var library: RefCounted=preload("res://scripts/builder/asset_library.gd").new()
	for mode in ["2d","3d"]:
		var viewport:=SubViewport.new();viewport.size=Vector2i(64,64);viewport.own_world_3d=true;viewport.world_2d=World2D.new();viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED;root.add_child(viewport);var world: Node=load("res://scripts/builder/world_"+mode+".gd").new();world.library=library;viewport.add_child(world)
		var data: Dictionary=preload("res://scripts/builder/templates.gd").make(mode,"blank");data["title"]="Café · precise source 世界";data["precision_marker"]={"small":.123456789123456,"large":31.9999256134033,"nested":[1.98765432198765,{"value":-.000030517578125}]};data["reference_image"]="res://assets/editor/missing_object.png";data["objects"]=[{"uid":"exact_source_fixture","asset":"3d:HanX_School/Student_Chair","position":[31.9999256134033,.123456789123456,1.98765432198765],"direction":"0","scale":1.0}];world.apply(data)
		var path: String=OUT+"exact_source_"+mode+".tscn";check(preload("res://scripts/builder/exporter.gd").save_scene(world,data,library,path)==OK,"Scene with exact nested authored doubles exports: "+mode)
		var packed: PackedScene=load(path);var scene: Node=packed.instantiate();root.add_child(scene)
		check(scene.studio_data==data,"Playable source restores integers, Unicode and nested doubles exactly: "+mode)
		check(not scene.studio_source_base64.contains("res://") and scene.studio_source_base64!=JSON.stringify(data),"Exact source encoding cannot introduce escaped res:// dependencies into the text resource scanner: "+mode)
		var node: Node=scene.city_instances["exact_source_fixture"]
		if mode=="3d":check(node.position==Vector3(31.9999256134033,.123456789123456,1.98765432198765),"Actual placement uses the closest engine float32 transform from the exact authored double: 3d")
		scene.free();await process_frame
		var legacy: Node=packed.instantiate();legacy.studio_source_base64="";var original: Dictionary=legacy.studio_data.duplicate(true);root.add_child(legacy);check(normalized(legacy.studio_data)==normalized(original) and not legacy.studio_data.is_empty(),"Older dictionary-only scenes retain their original playable source behavior: "+mode);legacy.free();await process_frame
		var old_json: Node = packed.instantiate()
		old_json.studio_source_base64 = Marshalls.raw_to_base64(JSON.stringify(data).to_utf8_buffer())
		root.add_child(old_json)
		check(old_json.studio_data == normalized(data), "Legacy JSON payloads retain their authored city: " + mode)
		old_json.free()
		await process_frame
		var package_path: String=OUT+"exact_source_"+mode+".zip";var exported: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(world,data,library,package_path);check(exported["ok"],"Portable dependency scanning accepts resource paths inside exact source metadata: "+mode)
		if exported["ok"]:
			var zip:=ZIPReader.new();zip.open(package_path);var source: Dictionary=JSON.parse_string(zip.read_file("city-source.json").get_string_from_utf8());check(source["documents"][mode]==normalized(data) and zip.get_files().has("assets/editor/missing_object.png"),"Portable source JSON remains exact and retains the legitimate referenced image: "+mode);zip.close()
		viewport.free();await process_frame
	print("EXPORT SOURCE PRECISION: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
