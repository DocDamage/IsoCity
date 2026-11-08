extends SceneTree
const OUT="res://output/verification/asset_expansion/I15/"
const Zone=preload("res://scripts/builder/zone_plan.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var library: RefCounted=preload("res://scripts/builder/asset_library.gd").new();var rows: Array=[];var ids: Array=library.assets.keys();ids.sort();var families: Dictionary={}
	for id in ids:
		var asset: Dictionary=library.assets[id]
		if not preload("res://scripts/builder/asset_behavior.gd").for_asset(id,library).get("building",false):continue
		var family: String=asset["data"].get("family_id",id);var row: Dictionary={"id":id,"name":asset["name"],"family":family,"source_mode":asset["mode"],"source_pack":library.pack_name(asset),"themes":library.themes.tags(asset),"price":Zone.Economy.profile(id,library),"source_export_allowed":asset["data"].get("source_export_allowed",true),"mode_geometry":{}}
		if not families.has(family):families[family]=[]
		families[family].append(id)
		for mode in ["2d","3d"]:
			var views: Array=[]
			for direction in library.directions(id):
				var item: Dictionary={"uid":"candidate_audit","asset":id,"position":[0,0,0],"direction":direction,"scale":float(asset["data"].get("default_scale",1))};var footprint: Rect2=Zone.footprint(item,mode,library);var entrance: Dictionary=Zone.Entrances.profile(item,library)
				views.append({"direction":direction,"scale":item["scale"],"rect":[footprint.position.x,footprint.position.y,footprint.size.x,footprint.size.y],"entrance":entrance,"point":[Zone.approach(item,mode,library,false).x,Zone.approach(item,mode,library,false).y],"arrival":[Zone.approach(item,mode,library).x,Zone.approach(item,mode,library).y]})
			row["mode_geometry"][mode]=views
		rows.append(row)
	var report: Dictionary={"asset_count":library.assets.size(),"building_count":rows.size(),"families":families,"current_definitions":Zone.definitions().duplicate(true),"buildings":rows}
	var file:=FileAccess.open(OUT+"building_audit.json",FileAccess.WRITE)
	if not file:printerr("FAIL: Cannot write zoning audit");quit(1);return
	file.store_string(JSON.stringify(report,"\t"));file.close();print("ZONING CANDIDATE AUDIT: %d building assets, %d design families; no source or catalog changes"%[rows.size(),families.size()]);quit()
