extends SceneTree
const Plan=preload("res://scripts/builder/interior_kit_plan.gd")
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://output/verification/asset_expansion/U13/");FileAccess.open("res://output/verification/asset_expansion/U13/.gdignore",FileAccess.WRITE).close()
	var library: RefCounted=preload("res://scripts/builder/asset_library.gd").new();var preview: RefCounted=preload("res://scripts/builder/interior_kit_preview.gd").new()
	for mode in ["2d","3d"]:
		var city: Dictionary=preload("res://scripts/builder/templates.gd").make(mode,"blank");city["objects"]=[{"uid":"school","asset":"3d:HanX_School/School_Building","position":[0,0,0],"scale":1.0,"direction":"0"}]
		var baseline: Dictionary=city.duplicate(true)
		for key in ["classroom","shop","cafe","garage","station","apartment","empty"]:
			var proposal: Dictionary=Plan.propose(city,"school","ground",key,"create",[0,0],library)
			check(proposal["ok"],"Private proposal resolves: "+mode+" "+key)
			if not proposal["ok"]:continue
			var finished: bool=await preview.build(proposal,library,root,"--capture" in OS.get_cmdline_user_args())
			check(finished and proposal["geometry_checked"],"Actual private world finishes its clearance review")
			check(proposal["issues"].is_empty(),"Reviewed kit clears floor, exit and station approaches: "+mode+" "+key+" "+JSON.stringify(proposal["issues"]))
			check(city==baseline,"Private rendering and physics never create or mutate an authored room")
			if "--capture" in OS.get_cmdline_user_args():
				await RenderingServer.frame_post_draw
				check(preview.viewport.get_texture().get_image().save_png("res://output/verification/asset_expansion/U13/preview_"+mode+"_"+key+".png")==OK,"Rendered room preview saved")
		var blocked: Dictionary=Plan.propose(city,"school","ground","empty","create",[0,0],library)
		blocked["room"]["objects"].append({"uid":"blocking_exit","asset":"3d:HanX_School/Bookshelf","direction":"0","scale":3.0,"position":[0,60,0] if mode=="2d" else [0,.12,2.5]})
		await preview.build(blocked,library,root,false)
		check(blocked["issues"].any(func(entry: Dictionary):return entry["code"]=="blocked_exit"),"Actual colliders detect furniture blocking the exit (shapes remain active): "+mode)
		var outside: Dictionary=Plan.propose(city,"school","ground","classroom","create",[40,40],library);await preview.build(outside,library,root,false)
		check(outside["issues"].any(func(entry: Dictionary):return entry["code"]=="outside_floor"),"A small authored floor cannot silently stretch to fit the kit")
		var owned: Dictionary=city.duplicate(true);owned["objects"][0]["interior"]=Plan.propose(city,"school","ground","classroom","create",[0,0],library)["room"]
		var overlap: Dictionary=Plan.propose(owned,"school","ground","classroom","add",[0,0],library);await preview.build(overlap,library,root,false)
		check(overlap["issues"].any(func(entry: Dictionary):return entry["code"]=="occupied_footprint"),"Adding over retained furniture is diagnosed without deleting it")
		var stairs: Dictionary=Plan.propose(city,"school","ground","classroom","create",[0,0],library)
		stairs["root"]["floors"]=[{"uid":"up","name":"Up","height":3,"room":Plan.shell(mode)}]
		stairs["root"]["floor_links"]=[{"uid":"steps","kind":"stairs","lower":"ground","upper":"up","start":[-1.65,1.5],"end":[-1.65,-3.5],"width":1.2}]
		await preview.build(stairs,library,root,false)
		check(stairs["issues"].any(func(entry: Dictionary):return entry["code"]=="floor_connection"),"Existing stair flight/landing reservation blocks overlapping kit furniture")
	preview.clear();check(not is_instance_valid(preview.viewport) and not is_instance_valid(preview.world),"Closing releases the private world and physics resources")
	await process_frame;print("INTERIOR KIT PREVIEW: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
