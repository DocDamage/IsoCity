extends SceneTree
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func screen_bounds(parent: Node2D) -> Rect2:
	var result:=Rect2();var found: bool=false
	for node in parent.find_children("*","Sprite2D",true,false):
		if not node.texture:continue
		var box: Rect2=parent.global_transform.affine_inverse()*node.global_transform*node.get_rect();result=result.merge(box) if found else box;found=true
	return result if found else Rect2(Vector2.ZERO,Vector2.ONE)
func render_bounds(parent: Node3D) -> AABB:
	var result:=AABB();var found: bool=false
	for node in parent.find_children("*","MeshInstance3D",true,false):
		if not node.mesh:continue
		var box: AABB=parent.global_transform.affine_inverse()*node.global_transform*node.mesh.get_aabb();result=result.merge(box) if found else box;found=true
	return result if found else AABB(Vector3.ZERO,Vector3.ONE)
func capture(scene: Node,name: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args():return
	for frame in 12:await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://"+name+".png")==OK,"Retained independently rendered zoning: "+name)
func run() -> void:
	var scene: Node=load("res://city.tscn").instantiate(); root.add_child(scene)
	for i in 6: await process_frame
	await physics_frame
	scene.zoning.set_process(false); scene.economy.set_process(false); scene.player.set_physics_process(false); scene.citizens.set_physics_process(false); scene.traffic.set_physics_process(false)
	scene.walking=false; scene._set_mode()
	var plan=load("res://scripts/builder/zone_plan.gd")
	check(scene.studio_data["objects"].is_empty() and scene.live_data["zones"].size()==4 and scene.zoning.visuals.size()==4,"Relocated packages load unfinished lots and their visible construction stage")
	var expectation: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://zone_expectation.json"))
	check(JSON.parse_string(JSON.stringify(scene.studio_data))==expectation["world"],"Relocated runtime preserves every authored source value before construction")
	check(load("res://scripts/builder/zone_candidates.gd").definitions()["revision"]==expectation["candidate_revision"],"Full reviewed catalog revision stays fixed when the asset registry is pruned for export")
	for asset in expectation["future"]:
		check(scene.exploration.library.assets.has(asset) and scene.exploration.library.assets[asset]["path"]==expectation["future"][asset] and ResourceLoader.exists(expectation["future"][asset]),"Every host-side possible future building has its packaged definition and source: "+asset)
	for frame in 1200:
		scene.zoning.people=scene.development_people(); scene.zoning.step(.25)
		if scene.live_data["zones"].all(func(lot: Dictionary):return lot["stage"]==3): break
	check(scene.live_data["zones"].all(func(lot: Dictionary):return lot["stage"]==3) and scene.city_instances.size()==4,"Fresh portable projects develop residential, commercial and civic lots into actual scene objects")
	check(scene.exploration.records.size()==4 and scene.citizens.residents.size()==2 and scene.businesses.service.businesses.size()==scene.live_data["objects"].filter(func(item: Dictionary):return load("res://scripts/builder/business_plan.gd").profile(item)["kind"]!="none").size(),"Grown buildings join exploration, resident routines and business activities after relocation")
	check(scene.studio_data["objects"].is_empty() and scene.studio_data["economy_account"]["cash"]==20000,"Live development preserves the portable project's authored source")
	var cost: int=0
	for item in scene.live_data["objects"]: cost+=load("res://scripts/builder/economy_plan.gd").profile(item["asset"],scene.exploration.library)["construction"]
	check(scene.economy.data["economy_account"]["cash"]==20000-cost and scene.economy.rates["income"]==scene.live_data["objects"].reduce(func(total: int,item: Dictionary):return total+load("res://scripts/builder/economy_plan.gd").profile(item["asset"],scene.exploration.library)["income"],0),"Portable development shares actual construction funds and updates income")
	var cash_before: int=scene.economy.data["economy_account"]["cash"]; var net: int=scene.economy.rates["net"]; var period_before: int=scene.economy.data["economy_account"]["period"]; scene.economy.elapsed=0
	for i in int(load("res://scripts/builder/economy_plan.gd").settings(scene.live_data)["period_seconds"])*4: scene.economy.step(.25)
	check(scene.economy.data["economy_account"]["cash"]==cash_before+net and scene.economy.data["economy_account"]["period"]==period_before+1,"Portable operating periods settle actual income and upkeep from the developed city")
	scene.zoning.update_hud(); check(scene.zoning.panel.visible,"Portable development exposes live counts and controls")
	scene.zoning.pause_button.pressed.emit(); var clocks: Dictionary=scene.zoning.timers.duplicate(true); scene.zoning.step(.25)
	check(scene.zoning.paused and scene.zoning.timers==clocks,"Portable pause controls preserve development clocks")
	if "--capture" in OS.get_cmdline_user_args():
		root.size=Vector2i(1480,900);scene.walking=false;scene._set_mode();scene.zoning.container.visible=false;scene.set_process(false)
		if scene.dimension=="2d":
			var bounds: Rect2=screen_bounds(scene.get_node("Objects"));scene.camera.position=bounds.get_center();scene.camera.zoom=Vector2.ONE*minf(1480.0/maxf(1,bounds.size.x+80),900.0/maxf(1,bounds.size.y+80))
		else:
			var bounds: AABB=render_bounds(scene.get_node("Objects"));var radius: float=maxf(1,bounds.size.length()*.5);scene.camera.projection=Camera3D.PROJECTION_ORTHOGONAL;scene.camera.keep_aspect=Camera3D.KEEP_HEIGHT;scene.camera.position=bounds.get_center()+Vector3(1,.8,1).normalized()*radius*3;scene.camera.look_at(bounds.get_center());scene.camera.size=radius*2.3;scene.camera.near=.01;scene.camera.far=radius*8+10
		await capture(scene,"grown_city_"+scene.dimension);scene.set_process(true)
	var home: Dictionary=scene.live_data["objects"].filter(func(item: Dictionary):return load("res://scripts/builder/citizen_plan.gd").role(item)=="home")[0]
	if "--capture" in OS.get_cmdline_user_args():
		scene.set_process(false);var building: Node=scene.city_instances[home["uid"]]
		if scene.dimension=="2d":
			var bounds: Rect2=building.global_transform*screen_bounds(building);scene.camera.position=bounds.get_center();scene.camera.zoom=Vector2.ONE*minf(1200.0/maxf(1,bounds.size.x+60),720.0/maxf(1,bounds.size.y+80))
		else:
			var bounds: AABB=building.global_transform*render_bounds(building);var radius: float=maxf(1,bounds.size.length()*.5);scene.camera.position=bounds.get_center()+Vector3(1,.8,1).normalized()*radius*3;scene.camera.look_at(bounds.get_center());scene.camera.size=radius*2.4;scene.camera.near=.01;scene.camera.far=radius*8+10
		await capture(scene,"grown_building_"+scene.dimension);scene.set_process(true)
	scene.walking=true; scene._set_mode(); scene.player.teleport_to(scene.exploration.entrance(scene.city_instances[home["uid"]])); scene.exploration.interact()
	check(scene.exploration.interior!=null and scene.exploration.interior_uid==home["uid"],"A freshly grown portable building has a usable owned interior")
	if scene.exploration.interior:
		await capture(scene,"grown_owned_room_"+scene.dimension);scene.exploration.leave_interior()
	scene.queue_free(); await process_frame
	print("ZONE EXPORT: %d checks, %d failures" % [checks,failures]); quit(0 if failures==0 else 1)
