extends "res://tools/test_zone_plan.gd"
const Portable=preload("res://scripts/builder/portable_export.gd")
const OUT="res://output/verification/asset_expansion/I15/"
func run() -> void:
	library=preload("res://scripts/builder/asset_library.gd").new();DirAccess.make_dir_recursive_absolute(OUT)
	for mode in ["2d","3d"]:
		var data: Dictionary=fixture(mode,"residential");data["zones"][0]["theme"]="korean_street";var possible: Array=Plan.future_assets(data["zones"][0],mode,library,{})
		if mode=="3d":
			check(possible.is_empty(),"Unsupported Korean 3D representation is not a future candidate")
			# Existing selected sources remain dependencies after a compatibility
			# review retires them from automatic planning.
			possible=Plan.future_assets(data["zones"][0],"2d",library,{})
			data["zones"][0]["stage"]=1;data["zones"][0]["proposal"]={"asset":possible[0]}
		check(not possible.is_empty(),"Explicit Korean lots expose their actual possible future sources: "+mode)
		check(possible.all(func(id: String):return library.assets[id]["data"].get("source_export_allowed",true)==false),"Local-use sources retain their license restriction: "+mode)
		var destination: String=OUT+"protected_export_"+mode+".zip";var sentinel: String="existing-good-package";FileAccess.open(destination,FileAccess.WRITE).store_string(sentinel);var world:=Node.new();var collector=Portable.new();var result: Dictionary=collector.save(world,data,library,destination)
		check(not result["ok"] and result["message"].contains("license") and result["message"].contains("creation layout"),"Future choices cannot silently bypass source redistribution limits: "+mode)
		check(FileAccess.get_file_as_string(destination)==sentinel,"Refused future source export preserves an existing package: "+mode)
		data["zoning"]["enabled"]=false;data["zones"][0].erase("proposal");data["zones"][0]["stage"]=0;var disabled: Dictionary=Portable.new().save(world,data,library,destination)
		check(not disabled["ok"] and disabled["message"]=="The layout is not ready to export.","Disabled growth does not collect unrelated future sources: "+mode)
		data["zones"][0]["stage"]=1;data["zones"][0]["proposal"]={"asset":possible[0]};var pending: Dictionary=Portable.new().save(world,data,library,destination)
		check(not pending["ok"] and pending["message"].contains("license"),"Saved selected construction retains its dependency even with development disabled: "+mode)
		world.free()
	print("ZONE EXPORT POLICY: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
