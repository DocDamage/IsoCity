extends SceneTree
const OUT="res://output/verification/asset_expansion/U15/"
const Plan=preload("res://scripts/builder/asset_collections.gd")
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func settle() -> void:
	for frame in 12:await process_frame
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT);FileAccess.open(OUT+".gdignore",FileAccess.WRITE).close();var studio: Control=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio);await settle();await settle();studio.consumer_shell.dismiss_welcome()
	var private_id: String="3d:Custom/Unplaced_Private_Palette_Reference";var asset: Dictionary=studio.library.assets["3d:HanX_School/Teacher_Chair"].duplicate(true);asset["id"]=private_id;asset["name"]="Private recommendation only";asset["data"]["source_export_allowed"]=false;studio.library.assets[private_id]=asset
	for mode in ["2d","3d"]:
		studio.switch_mode(mode);var doc: RefCounted=preload("res://scripts/builder/document.gd").new();doc.data=preload("res://scripts/builder/templates.gd").make(mode,"blank");var building: String="2d:House_Blue" if mode=="2d" else "3d:HanX_City/Row_Houses_A";var chair: String="3d:HanX_School/Student_Chair";var saved: Dictionary=doc.add(building,[-100,0,0] if mode=="2d" else [-12,0,0],studio.library.directions(building)[0]);saved["name"]="Saved palette room";saved["interior"]=preload("res://scripts/builder/interiors.gd").make_for(saved,mode,studio.library);var custom: Dictionary={"uid":"kept_palette_furnishing","asset":chair,"position":[30,10,0] if mode=="2d" else [1,.12,1],"direction":studio.library.directions(chair)[0],"scale":1.0,"name":"Exact palette furnishing"};saved["interior"]["objects"].append(custom);var fresh: Dictionary=doc.add(building,[100,0,0] if mode=="2d" else [12,0,0],studio.library.directions(building)[0]);fresh["name"]="Unvisited permitted room"
		var future: Dictionary=preload("res://scripts/builder/interiors.gd").make_for(fresh,mode,studio.library);var ids: Array=[building,chair,private_id]
		for id in Plan.records(future).values():
			if not ids.has(id):ids.append(id)
		var policy: Dictionary=Plan.project_empty();policy["restricted"]=true
		for id in ids:policy["collection"]["entries"].append(Plan.asset_entry(id,studio.library)["entry"])
		policy["collection"]["entries"].append({"kind":"asset","id":"2d:Uninstalled_Palette_Shelf","name":"Remembered shelf on another computer"});studio.project_palette_document.restore(policy);studio.documents[mode]=doc;studio.changed();await settle();var original: Dictionary=doc.data.duplicate(true);var exporter: RefCounted=preload("res://scripts/builder/portable_export.gd").new();var path: String=OUT+"palette_portable_"+mode+".zip";var result: Dictionary=exporter.save(studio.worlds[mode],doc.data,studio.library,path)
		check(result["ok"] and doc.data==original,"Permitted portable package saves with exact authored rooms and project policy: "+mode)
		if not result["ok"]:printerr(result);continue
		var zip:=ZIPReader.new();check(zip.open(path)==OK,"Portable archive opens: "+mode);var source: Dictionary=JSON.parse_string(zip.read_file("city-source.json").get_string_from_utf8());var manifest: Dictionary=JSON.parse_string(zip.read_file("export-manifest.json").get_string_from_utf8());var names: PackedStringArray=zip.get_files()
		check(JSON.stringify(source["documents"][mode])==JSON.stringify(JSON.parse_string(JSON.stringify(original))) and source["project_palette"]==JSON.parse_string(JSON.stringify(policy)),"Portable source preserves every authored value and all missing reference metadata: "+mode)
		check(not manifest["assets"].has(private_id) and not manifest["assets"].has("2d:Uninstalled_Palette_Shelf"),"Unplaced private or unavailable recommendations never become required art dependencies: "+mode)
		check(names.has("scripts/builder/asset_palette_policy.gd") and names.has("scripts/builder/asset_collections.gd") and not names.has("scripts/builder/collection_tools.gd") and not names.has("scripts/builder/asset_collection_store.gd"),"Runtime policy is retained while editor management and personal preferences are absent: "+mode)
		check(zip.read_file("city.tscn").get_string_from_utf8().contains("project_palette ="),"Playable packed scene carries common policy independently of source JSON: "+mode);zip.close()
		studio.Store.write_json(OUT+"portable_palette_expectation_"+mode+".json",{"world":original,"policy":policy,"owned_uid":saved["uid"],"fresh_uid":fresh["uid"],"private_id":private_id,"chair":chair,"future_layout":future})
		var hash: String=FileAccess.get_sha256(path);doc.data["objects"].append({"uid":"private_art_fixture","asset":private_id,"position":[0,0,0],"direction":studio.library.directions(private_id)[0],"scale":1.0});var denied: Dictionary=exporter.save(studio.worlds[mode],doc.data,studio.library,path)
		check(not denied["ok"] and denied["message"].contains("license") and FileAccess.get_sha256(path)==hash,"Palette permission never overrides an actual source-export license or replaces the good package: "+mode);doc.data=original;studio.changed()
	studio.free();await process_frame;await process_frame;print("COLLECTION PORTABLE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
