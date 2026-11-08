extends SceneTree
const Terrain=preload("res://scripts/builder/terrain_plan.gd")
const Traffic=preload("res://scripts/builder/traffic_plan.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for frame in 6: await process_frame
	await physics_frame
func run() -> void:
	root.size=Vector2i(1480,900)
	var studio: Control=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio); await settle()
	for mode in ["2d","3d"]:
		studio.switch_mode(mode)
		var doc=preload("res://scripts/builder/document.gd").new(); doc.data=preload("res://scripts/builder/templates.gd").make(mode,"blank"); doc.data["objects"]=[]; doc.data["roads"]=[]; doc.data["terrain"]={"enabled":true,"bounds":[-16,-16,32,32]}; doc.data["terrain_vertices"]=[]; doc.data["water_cells"]=[]; doc.data["traffic"]={"enabled":true,"population":2,"seed":3}
		for x in range(-16,17):
			for z in range(-16,17): doc.data["terrain_vertices"].append({"cell":[x,z],"height":2+x*.2})
		for x in range(-2,3): doc.data["roads"].append({"cell":[x,0],"style":"gravel"})
		studio.documents[mode]=doc; studio.changed(); await settle(); var world: Node=studio.worlds[mode]; var manager: Node=studio.traffic_tools.managers[mode]; manager.set_physics_process(false); manager.configure(doc.data,studio.library,world.instances,world.objects)
		check(manager.vehicles.size()==2 and manager.plan["closed_sections"].is_empty(),"Traffic spawns on a gentle raised road: "+mode)
		var vehicle: Dictionary=manager.vehicles[0]; var start: Vector2=vehicle["point"]; var before: Dictionary=doc.data.duplicate(true)
		for frame in 300: manager.step(1.0/60)
		check(vehicle["point"].distance_to(start)>2 and vehicle["phase"]!="blocked","Real traffic progresses along the raised road: "+mode)
		var actor: Node=vehicle["actor"]; var surface: Dictionary=Terrain.sample(doc.data,vehicle["point"])
		if mode=="3d":
			check(actor.basis.y.normalized().distance_to(surface["normal"])<.001,"Vehicle body follows the road bank normal")
			var bottom: float=preload("res://scripts/builder/roads.gd").bounds_for(studio.library,vehicle["asset"]).position.y*.5
			check(absf(actor.position.y-(surface["height"]+.12-surface["normal"].y*bottom))<.002,"Vehicle contact height follows the raised driving surface")
		else:
			world.terrain_presentation.refresh(); var sprite: Sprite2D=actor.get_node("Sprite2D"); var delta: Vector2=sprite.global_transform.basis_xform(actor.terrain_visual_offset)
			check(delta.y < -8 and absf(delta.x)<.001,"2D moving traffic follows terrain through the shared sprite presenter")
		check(doc.data==before,"Vehicle elevation never rewrites authored terrain: "+mode)
		if mode=="3d":
			var lane: Dictionary=preload("res://scripts/builder/roads.gd").lane(doc.data,[0,0,1.5],"90",studio.library,"3d:HanX_Traffic/Car_Sedan",.5)
			var contact: Vector2=Vector2(lane["position"][0],lane["position"][2])+preload("res://scripts/builder/roads.gd").center_offset(studio.library,"3d:HanX_Traffic/Car_Sedan",lane["direction"],.5,mode)
			var bottom: float=preload("res://scripts/builder/roads.gd").bounds_for(studio.library,"3d:HanX_Traffic/Car_Sedan").position.y*.5
			check(lane["snapped"] and absf(lane["position"][1]+bottom-Terrain.sample(doc.data,contact)["height"]-.12)<.002,"Ordinary vehicle lane snapping uses sculpted road height")
		var path: String="res://output/terrain_traffic_"+mode+".tscn"; check(studio.Exporter.save_scene(world,doc.data,studio.library,path)==OK,"Moving terrain traffic exports: "+mode)
		var viewport:=SubViewport.new(); viewport.size=Vector2i(1000,700); if mode=="3d": viewport.own_world_3d=true
		root.add_child(viewport); var playable: Node=load(path).instantiate(); viewport.add_child(playable); await settle(); playable.player.set_physics_process(false); playable.traffic.set_physics_process(false)
		check(playable.traffic.vehicles.size()==2 and playable.traffic.plan["closed_sections"].is_empty(),"Playable traffic rebuilds the raised road network: "+mode)
		if mode=="3d": check(playable.traffic.vehicles[0]["actor"].position.y>1,"Playable vehicles retain authored terrain height")
		viewport.free()
		var portable: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(world,doc.data,studio.library,"res://output/terrain_traffic_"+mode+".zip"); check(portable["ok"],"Terrain traffic packages collect deformed road and vehicle dependencies: "+mode)
		if mode=="3d":
			for vertex in doc.data["terrain_vertices"]: vertex["height"]-=4
			studio.changed(); manager.configure(doc.data,studio.library,world.instances,world.objects); await settle()
			var ray:=PhysicsRayQueryParameters3D.create(Vector3(.5,30,.5),Vector3(.5,-30,.5),2); var hit: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(ray)
			check(not hit.is_empty() and absf(hit["position"].y-Terrain.sample(doc.data,Vector2(.5,.5))["height"]-.11)<.002 and actor.position.y<0,"Roads and vehicles update to a depression below the original foundation")
			var below: Dictionary=preload("res://scripts/builder/roads.gd").lane(doc.data,[0,0,1.5],"90",studio.library,"3d:HanX_Traffic/Car_Sedan",.5)
			check(below["snapped"] and below["position"][1]<0,"Lane snapping can lower a vehicle into a below-datum road")
			var ids: Array=world.road_node.get_children().map(func(section: Node):return section.get_instance_id())
			for vertex in doc.data["terrain_vertices"]:
				if vertex["cell"]==[15,15]: vertex["height"]+=1
			studio.changed(); check(world.road_node.get_meta("last_rebuilt")==0 and world.road_node.get_children().map(func(section: Node):return section.get_instance_id())==ids,"Distant sculpting retains every live road mesh/collider")
			doc.data=before.duplicate(true); studio.changed(); manager.configure(doc.data,studio.library,world.instances,world.objects)
		if "--capture" in OS.get_cmdline_user_args():
			studio.traffic_tools.show()
			if mode=="3d": world.target=Vector3(0,2,0); world.distance=40; world.update_camera()
			else: world.camera.position=Vector2(0,-16); world.camera.zoom=Vector2.ONE*1.5
			await settle(); await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png("res://output/terrain_traffic_"+mode+".png")
		for x in range(-16,16):
			for z in range(-4,4): doc.data["water_cells"].append({"cell":[x,z],"level":10})
		studio.changed(); manager.configure(doc.data,studio.library,world.instances,world.objects)
		check(manager.plan["sections"].is_empty() and manager.plan["closed_sections"].size()==5 and "flooded" in vehicle["status"],"Flooded road sections close with a specific driving explanation: "+mode)
		var stopped: Vector2=vehicle["point"]; manager.step(1); check(vehicle["point"]==stopped,"Traffic stays stopped on a flooded road: "+mode)
		doc.data["water_cells"]=[]; studio.changed(); manager.configure(doc.data,studio.library,world.instances,world.objects); manager.step(1)
		check(not manager.plan["sections"].is_empty() and vehicle["phase"]!="blocked" and vehicle["point"]!=stopped,"Draining the road restores its original traffic route and movement: "+mode)
		for vertex in doc.data["terrain_vertices"]: vertex["height"]=clampf(vertex["cell"][0]*2,-24,24)
		var steep: Dictionary=Traffic.build(doc.data); check(not steep["closed_sections"].is_empty() and steep["closed_sections"].values().any(func(reason: String):return "steep" in reason),"Steep road banks are excluded from routes: "+mode)
	studio.free(); print("TERRAIN TRAFFIC: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
