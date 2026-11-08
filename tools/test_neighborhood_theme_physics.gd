extends "res://tools/test_neighborhood_palettes.gd"
const OUT="res://output/verification/asset_expansion/I16/"
const Fit=preload("res://scripts/builder/asset_scale_preview.gd")
func settle() -> void:
	for frame in 3:await physics_frame
	for frame in 3:await process_frame
func frame_world(world: Node,mode: String) -> void:
	if mode=="2d":
		var bounds: Rect2=Fit.screen_bounds(world.objects);world.camera.position=bounds.get_center();world.camera.zoom=Vector2.ONE*minf(1480.0/maxf(1,bounds.size.x+80),900.0/maxf(1,bounds.size.y+100))
	else:
		var bounds: AABB=Fit.render_bounds(world.objects);var radius: float=maxf(1,bounds.size.length()*.5);world.camera.projection=Camera3D.PROJECTION_ORTHOGONAL;world.camera.keep_aspect=Camera3D.KEEP_HEIGHT;world.camera.position=bounds.get_center()+Vector3(1,.8,1).normalized()*radius*3;world.camera.look_at(bounds.get_center());world.camera.size=radius*2.4;world.camera.near=.01;world.camera.far=radius*8+10
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT);root.size=Vector2i(1480,900);library=preload("res://scripts/builder/asset_library.gd").new();var records: Array=[]
	for mode in ["2d","3d"]:
		var viewport:=SubViewport.new();viewport.size=Vector2i(1480,900);viewport.own_world_3d=true;viewport.world_2d=World2D.new();viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS if "--capture" in OS.get_cmdline_user_args() else SubViewport.UPDATE_DISABLED;root.add_child(viewport);var world: Node=load("res://scripts/builder/world_"+mode+".gd").new();world.library=library;viewport.add_child(world);world.player.set_physics_process(false)
		for theme in Palettes.palettes():
			if not mode in Palettes.palettes()[theme]["modes"]:continue
			var seed_value: int=17;var definition: Dictionary=Palettes.palettes()[theme]
			if not definition["props"].is_empty():
				for candidate_seed in range(1,129):
					if Plan.Zone.Candidates.draw(candidate_seed,"0/0/prop",definition["revision"],"scenery-density",100)<definition["prop_density"]:seed_value=candidate_seed;break
			for pattern in Plan.PATTERNS:
				var source: Dictionary=preload("res://scripts/builder/templates.gd").make(mode,"blank");var config: Dictionary=Plan.defaults();config.merge({"theme":theme,"blocks":1,"density":100,"seed":seed_value,"pattern":pattern},true);var result: Dictionary=Plan.generate(source,config,library);var label: String=mode+"/"+theme+"/"+pattern;check(result["ok"],"Actual combined district fixture generates: "+label)
				if not result["ok"]:continue
				if not definition["props"].is_empty():check(result["props"]>0,"The physical fixture contains an actual optional street prop: "+label)
				world.apply(result["data"]);world.player.set_physics_process(false);world.exploration.set_process(false);await settle();var boxes: Array[Rect2]=[]
				for item in result["data"]["objects"]:
					var box: Rect2=Plan.Zone.footprint(item,mode,library);check(not boxes.any(func(other: Rect2):return other.grow(.5).intersects(box)),"Buildings and scenery preserve each other's physical margin: "+label);boxes.append(box)
					if item["neighborhood_palette_selection"]["role"]!="building":continue
					var arrival: Variant=Plan.Zone.Entrances.position_for(world.instances[item["uid"]],item,mode,library);var metric: Vector2=Plan.Zone.Traffic.metric([arrival.x,arrival.y,0] if mode=="2d" else [arrival.x,arrival.y,arrival.z],mode);check(metric.distance_to(Plan.Zone.approach(item,mode,library))<.001,"Actual source instance agrees with the shared planner transform: "+label);world.player.teleport_to(arrival);await settle();check(preload("res://scripts/builder/prop_plan.gd").standing_clear(world.exploration,world.player.global_position),"Actual player body can stand at the district entrance with scenery present: "+label)
				if pattern=="grid" and "--capture" in OS.get_cmdline_user_args():
					frame_world(world,mode);await settle();await RenderingServer.frame_post_draw;check(viewport.get_texture().get_image().save_png(OUT+"district_"+mode+"_"+theme+".png")==OK,"Actual supplied full district render retained: "+label)
					records.append({"mode":mode,"theme":theme,"config":config,"objects":result["data"]["objects"],"parks":result["parks"],"props":result["props"],"skipped":result["skipped_scenery"]})
		viewport.free();await process_frame
	FileAccess.open(OUT+"physical_districts.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"renders":records},"\t"));print("NEIGHBORHOOD THEME PHYSICS: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
