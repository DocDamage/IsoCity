extends "res://tools/test_zone_plan.gd"
const OUT="res://output/verification/asset_expansion/I15/"
func run() -> void:
	library=preload("res://scripts/builder/asset_library.gd").new()
	for mode in ["2d","3d"]:
		var fixture_data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"zone_expectation_"+mode+".json"));var data: Dictionary=fixture_data["world"]
		for lot in data["zones"]:lot["theme"]="village";lot["stage"]=0;lot.erase("proposal");lot.erase("selection")
		check(preload("res://scripts/builder/document.gd").valid(data,mode,library),"Themed export uses a valid ordinary authored city: "+mode)
		var futures: Dictionary={}
		for lot in data["zones"]:
			for id in Plan.future_assets(lot,mode,library):futures[id]=library.assets[id]["path"]
		check(futures.size()==216,"Host enumerates all 216 reviewed village appearances across future zone types: "+mode)
		var viewport:=SubViewport.new();viewport.size=Vector2i(64,64);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED;root.add_child(viewport);var world: Node=load("res://scripts/builder/world_"+mode+".gd").new();world.library=library;viewport.add_child(world);world.apply(data);world.player.set_physics_process(false)
		var result: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(world,data,library,"res://output/zoning_village_"+mode+".zip")
		check(result["ok"],"All potential appearance sources collect into a permitted themed portable package: "+mode+result["message"])
		FileAccess.open(OUT+"zone_expectation_village_"+mode+".json",FileAccess.WRITE).store_string(JSON.stringify({"world":data,"future":futures,"candidate_revision":Plan.Candidates.definitions()["revision"]},"\t"));viewport.free();await process_frame
	print("ZONE THEME EXPORT: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
