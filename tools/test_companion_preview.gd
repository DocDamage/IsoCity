extends SceneTree
const OUT="res://output/verification/asset_expansion/U10/"
const Plan=preload("res://scripts/builder/companion_plan.gd")
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT);FileAccess.open(OUT+".gdignore",FileAccess.WRITE).close()
	var library: RefCounted=preload("res://scripts/builder/asset_library.gd").new();var preview=preload("res://scripts/builder/companion_preview.gd").new()
	for mode in ["2d","3d"]:
		for key in Plan.definitions()["relationships"]:
			var recipe: Dictionary=Plan.definitions()["relationships"][key];var root_data: Dictionary=preload("res://scripts/builder/templates.gd").make(mode,"blank");var before: Dictionary=root_data.duplicate(true)
			var source: Dictionary={"asset":recipe["source"],"position":[0,0,0],"scale":library.assets[recipe["source"]]["data"].get("default_scale",1.0),"direction":str(library.directions(recipe["source"])[0])}
			var proposal: Dictionary=Plan.propose(root_data,{},key,"",source,library);check(proposal["ok"],"Companion sources prepare without missing dependencies")
			if not proposal["ok"]:continue
			check(await preview.build(proposal,library,root,"--capture" in OS.get_cmdline_user_args()),"Private actual placement/physics review finishes")
			check(proposal["geometry_checked"] and proposal["issues"].is_empty(),"Reviewed source set clears actual approaches and ground: "+mode+" "+key+" "+JSON.stringify(proposal["issues"]))
			check(root_data==before,"Rendering and clearance leave all authored data untouched")
			if "--capture" in OS.get_cmdline_user_args():
				await RenderingServer.frame_post_draw;check(preview.viewport.get_texture().get_image().save_png(OUT+"preview_"+mode+"_"+key+".png")==OK,"Actual source-set render saved")
			if key=="covered_pump":
				preview.see_through(true);await process_frame
				var point: Variant=preload("res://scripts/builder/grid_fit.gd").pixels(Vector2(0,1.25)) if mode=="2d" else Vector3(0,.2,1.25)
				check(preload("res://scripts/builder/prop_plan.gd").standing_clear(preview.world.exploration,point),"Canopy cutaway preserves real under-roof physics clearance")
				if "--capture" in OS.get_cmdline_user_args():
					await RenderingServer.frame_post_draw;check(preview.viewport.get_texture().get_image().save_png(OUT+"under_canopy_"+mode+".png")==OK,"Explicit see-through view reveals the covered source artwork")
		# Compare the proposed coordinates to the placement factory's actual
		# source-point adapter, including legacy wrapper angles and card lifts.
		for fixture in [["classroom_desk","90",1.5,[8,-6],30],["shelf_stock","270",.75,[-4,5],-20]]+library.directions("2d:Supplemental_Camping_gear_kit_camp_stove_5cbaa2d4").map(func(direction: String):return ["camp_cooking",direction,1.2,[5,-3],25]):
			var recipe: Dictionary=Plan.definitions()["relationships"][fixture[0]];var data: Dictionary=preload("res://scripts/builder/templates.gd").make(mode,"blank");var id: String=recipe["source"]
			var source: Dictionary={"asset":id,"position":[24,12,0] if mode=="2d" else [2,.2,1],"scale":float(library.assets[id]["data"].get("default_scale",1))*float(fixture[2]),"direction":fixture[1],"tilt":fixture[3],"angle":fixture[4]}
			var proposal: Dictionary=Plan.propose(data,{},fixture[0],"",source,library);check(proposal["ok"],"Modified source has a valid bounded assembly proposal")
			if not proposal["ok"]:continue
			await preview.build(proposal,library,root,false)
			var a: Dictionary=proposal["room"]["objects"][0];var b: Dictionary=proposal["room"]["objects"][1];var grid=preload("res://scripts/builder/grid_fit.gd");var anchors=preload("res://scripts/builder/entrance_anchors.gd")
			var source_center: Vector3=grid.bounds_for(a["asset"],library,true).get_center() if a["asset"].begins_with("3d:") else Vector3(.5,0,.5)
			var target_center: Vector3=grid.bounds_for(b["asset"],library,true).get_center() if b["asset"].begins_with("3d:") else Vector3(.5,0,.5)
			var raw: Array=recipe["companions"][0]["offset"];source_center+=Vector3(raw[0],raw[1],raw[2])/float(library.assets[id]["data"].get("default_scale",1))
			var expected: Variant=anchors.source_position(preview.world.instances[a["uid"]],a,mode,library,source_center);var actual: Variant=anchors.source_position(preview.world.instances[b["uid"]],b,mode,library,target_center)
			if expected.distance_to(actual)>=.001:printerr("ANCHOR DIAGNOSTIC: "+JSON.stringify({"mode":mode,"source":a,"target":b,"expected":str(expected),"actual":str(actual),"distance":expected.distance_to(actual)}))
			check(expected.distance_to(actual)<.001,"Actual native/mixed placement anchors match scaled, rotated and tilted source geometry: "+mode+" "+str(fixture[0])+" "+str(fixture[1]))
	preview.clear();await process_frame;await process_frame;print("COMPANION PREVIEW: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
