extends SceneTree
const Plan=preload("res://scripts/builder/zone_plan.gd")
const Candidates=preload("res://scripts/builder/zone_candidates.gd")
const Collections=preload("res://scripts/builder/asset_collections.gd")
const Fit=preload("res://scripts/builder/asset_scale_preview.gd")
const OUT="res://output/verification/asset_expansion/I15/"
var checks: int=0
var failures: int=0
var library: RefCounted
var physical: Array=[]
var captures: Dictionary={}
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func fixture(mode: String,definition: Dictionary) -> Dictionary:
	var data: Dictionary=preload("res://scripts/builder/templates.gd").make(mode,"blank");data["zoning"]={"enabled":true,"seed":17};data["zones"]=[{"uid":"design_fixture","kind":definition["zone"],"theme":definition["themes"][0],"density":definition["density"],"rect":[-32,8,64,64],"stage":0}];data["roads"]=[]
	for x in range(-12,13):data["roads"].append({"cell":[x,0]})
	var home: String="2d:House_Blue" if mode=="2d" else "3d:HanX_City/Row_Houses_A"
	for sign_value in [-1,1]:data["objects"].append({"uid":"existing_home_"+str(sign_value),"asset":home,"position":Plan.Traffic.world(Vector2(sign_value*60,-24),mode),"direction":library.directions(home)[0],"scale":1.0})
	return data
func settle() -> void:
	for frame in 3:await physics_frame
	for frame in 3:await process_frame
func frame(world: Node,mode: String) -> void:
	if mode=="2d":
		var bounds: Rect2=Fit.screen_bounds(world.objects);world.camera.position=bounds.get_center();world.camera.zoom=Vector2.ONE*minf(1480.0/maxf(1,bounds.size.x+60),900.0/maxf(1,bounds.size.y+80))
	else:
		var bounds: AABB=Fit.render_bounds(world.objects);var radius: float=maxf(1,bounds.size.length()*.5);world.camera.projection=Camera3D.PROJECTION_ORTHOGONAL;world.camera.keep_aspect=Camera3D.KEEP_HEIGHT;world.camera.position=bounds.get_center()+Vector3(1,.8,1).normalized()*radius*3;world.camera.look_at(bounds.get_center());world.camera.size=radius*2.4;world.camera.near=.01;world.camera.far=radius*8+10
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT);root.size=Vector2i(1480,900);library=preload("res://scripts/builder/asset_library.gd").new()
	for mode in ["2d","3d"]:
		var viewport:=SubViewport.new();viewport.size=Vector2i(1480,900);viewport.own_world_3d=true;viewport.world_2d=World2D.new();viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS if "--capture" in OS.get_cmdline_user_args() else SubViewport.UPDATE_DISABLED;root.add_child(viewport);var world: Node=load("res://scripts/builder/world_"+mode+".gd").new();world.library=library;viewport.add_child(world);world.player.set_physics_process(false)
		for definition in Candidates.definitions()["families"]:
			if not mode in definition["modes"]:
				check(definition["members"]==["2d:Hopital"] and mode=="2d" or "korean_street" in definition["themes"] and mode=="3d","Unsupported automatic representation is explicit: oversized native hospital or obscured Korean flat card")
				continue
			var id: String=library.families.representatives.get(definition["id"],definition["members"][0]);var policy: Dictionary=Collections.project_empty();policy["restricted"]=true;policy["collection"]["entries"]=[Collections.asset_entry(id,library)["entry"]];library.set_project_palette(policy)
			var data: Dictionary=fixture(mode,definition);var before: String=JSON.stringify(data);var lot: Dictionary=data["zones"][0];var state: Dictionary=Plan.evaluate(data,lot,library);var label: String=mode+" "+definition["id"]
			check(state["ok"],"Reviewed design has an eligible terrain/road/entrance pose: "+label+" "+state["reason"])
			if not state["ok"]:physical.append({"mode":mode,"id":id,"family":definition["id"],"reason":state["reason"],"passed":false});continue
			check(state["proposal"]["asset"]==id and state["selection"]["family"]==definition["id"] and state["eligible_families"]==1,"Exact member selection follows eligibility and project restriction: "+label)
			check(JSON.stringify(data)==before and Plan.evaluate(data,lot,library)["proposal"]==state["proposal"],"Fixed-revision planning is deterministic and read-only: "+label)
			check(state["cost"]==Plan.Economy.profile(id,library)["construction"] and state["selection"]["price"]==state["cost"],"Reviewed selection uses the unchanged real construction profile: "+label)
			var proposal: Dictionary=state["proposal"];var view_data: Dictionary=data.duplicate(true);view_data["objects"]=[proposal];view_data["zones"]=[];world.apply(view_data);world.player.set_physics_process(false);world.exploration.set_process(false);await settle()
			var node: Node=world.instances[proposal["uid"]];var arrival: Variant=Plan.Entrances.position_for(node,proposal,mode,library);var metric: Vector2=Plan.Traffic.metric([arrival.x,arrival.y,0] if mode=="2d" else [arrival.x,arrival.y,arrival.z],mode)
			check(metric.distance_to(Plan.approach(proposal,mode,library))<.001,"Planned arrival equals the actual mixed/native instance transform: "+label)
			world.player.teleport_to(arrival);await settle();var clear: bool=preload("res://scripts/builder/prop_plan.gd").standing_clear(world.exploration,world.player.global_position)
			check(clear,"Actual player body clears the supplied building entrance: "+label)
			physical.append({"mode":mode,"id":id,"family":definition["id"],"direction":proposal["direction"],"position":proposal["position"],"arrival":[arrival.x,arrival.y] if mode=="2d" else [arrival.x,arrival.y,arrival.z],"passed":clear})
			var theme: String=definition["themes"][0];var key: String=mode+"_"+theme+"_"+definition["zone"]
			if "--capture" in OS.get_cmdline_user_args() and not captures.has(key):
				frame(world,mode);await settle();await RenderingServer.frame_post_draw;check(viewport.get_texture().get_image().save_png(OUT+"design_"+key+".png")==OK,"Retained reviewed source artwork: "+key);captures[key]=id
		viewport.free();await process_frame
	var file:=FileAccess.open(OUT+"physical_designs.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures,"designs":physical,"captures":captures},"\t"));file.close();print("ZONE DESIGNS: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
