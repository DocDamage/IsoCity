extends SceneTree
const Plan=preload("res://scripts/builder/terrain_plan.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for frame in 5: await process_frame
	await physics_frame; await process_frame
func ray(world: Node,point: Vector2) -> Dictionary:
	return world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(point.x,30,point.y),Vector3(point.x,-30,point.y),2))
func run() -> void:
	var studio: Control=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio); await settle(); studio.switch_mode("3d")
	var doc=preload("res://scripts/builder/document.gd").new(); doc.data=preload("res://scripts/builder/templates.gd").make("3d","blank"); doc.data["objects"]=[]; doc.data["terrain"]={"enabled":true,"bounds":[-12,-12,24,24]}; doc.data["terrain_vertices"]=[]; doc.data["water_cells"]=[]
	doc.data=Plan.brush(doc.data,"basin",Vector2(-6,4),5,3)["data"]
	var asset: String="3d:HanX_City/Row_Houses_A"; var home: Dictionary=doc.add(asset,[8,0,-8],studio.library.directions(asset)[0])
	studio.documents["3d"]=doc; studio.changed(); await settle()
	var world: Node=studio.worlds["3d"]; var terrain: Node=world.terrain
	check(terrain.chunks.size()==4 and not world.get_node("Foundation").visible and world.get_node("Foundation").collision_layer==0,"Sculpted city ground replaces the legacy foundation")
	var hit: Dictionary=ray(world,Vector2(-6,4))
	check(not hit.is_empty() and absf(hit["position"].y+3)<.002,"Studio exploration physics reaches a depression below the old foundation")
	var ground:=Vector2(-5.7,4.3); var target:=Vector3(ground.x,Plan.sample(doc.data,ground)["height"],ground.y)
	world.surface_snapping=true; var pixel: Vector2=world.camera.unproject_position(target); var snapped: Array=world.surface_point(pixel,false,0)
	check(Vector3(snapped[0],snapped[1],snapped[2]).distance_to(target)<.01,"Existing surface placement snaps to the actual terrain bed: "+str(snapped)+" "+world.surface_feedback)
	pixel=world.camera.unproject_position(Vector3(-6,-3,4)); snapped=world.surface_point(pixel,false,0)
	check(Vector3(snapped[0],snapped[1],snapped[2]).distance_to(Vector3(-6,-3,4))<.01,"Exact terrain vertices remain pickable when a physics seam needs the analytical fallback")
	var retained: Dictionary={}
	for id in terrain.chunks: retained[id]=terrain.chunks[id].get_instance_id()
	home["name"]="Retained home"; studio.changed(); await settle()
	check(terrain.last_rebuilt==0 and terrain.chunks.keys().all(func(id: String):return terrain.chunks[id].get_instance_id()==retained[id]),"Unrelated city edits retain terrain mesh and collision nodes")
	studio.set_walking(true); world.player.set_physics_process(false); world.player.teleport_to(world.exploration.entrance(world.instances[home["uid"]])); world.exploration.interact(); await settle()
	check(world.exploration.interior!=null and not terrain.visible and terrain.chunks.values().all(func(chunk: Node):return chunk.get_node("Surface").collision_layer==0),"Owned interiors suspend exterior terrain rendering and physics")
	check(not world.terrain_traversal.active(),"Owned interiors suspend exterior water restrictions")
	world.apply(doc.data)
	check(not terrain.visible and terrain.chunks.values().all(func(chunk: Node):return chunk.get_node("Surface").collision_layer==0),"Exterior refreshes cannot reactivate terrain during an interior visit")
	world.exploration.leave_interior(); studio.set_walking(false); await settle()
	check(terrain.visible and terrain.chunks.values().all(func(chunk: Node):return chunk.get_node("Surface").collision_layer==2),"Leaving an interior restores the same physical terrain")
	var path: String="res://output/terrain_city_3d.tscn"; var authored: Dictionary=doc.data.duplicate(true)
	check(studio.Exporter.save_scene(world,doc.data,studio.library,path)==OK,"Playable scenes export authored terrain data")
	var viewport:=SubViewport.new(); viewport.size=Vector2i(1000,700); viewport.own_world_3d=true; root.add_child(viewport); var playable: Node=load(path).instantiate(); viewport.add_child(playable); await settle(); playable.player.set_physics_process(false)
	check(playable.terrain.chunks.size()==4 and playable.get_node("Foundation").collision_layer==0,"Playable scenes rebuild their own terrain instead of restoring flat ground")
	hit=ray(playable,Vector2(-6,4)); check(not hit.is_empty() and absf(hit["position"].y+3)<.002,"Exported exploration physics preserves the actual pond bed")
	check(doc.data==authored and playable.studio_data==authored,"World/render/export integration preserves authored terrain records")
	playable.exploration.player.teleport_to(playable.exploration.entrance(playable.city_instances[home["uid"]])); playable.exploration.interact(); await settle()
	check(playable.exploration.interior!=null and not playable.terrain.visible and playable.terrain.chunks.values().all(func(chunk: Node):return chunk.get_node("Surface").collision_layer==0),"Playable owned interiors suspend terrain collisions")
	playable.exploration.leave_interior(); await settle(); check(playable.terrain.visible and playable.terrain.chunks.values().all(func(chunk: Node):return chunk.get_node("Surface").collision_layer==2),"Playable interior return restores terrain surfaces")
	viewport.free()
	var portable: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(world,doc.data,studio.library,"res://output/terrain_3d.zip")
	check(portable["ok"],"Portable cities collect live 3D terrain and owned-room dependencies")
	doc.data["terrain"]["enabled"]=false; studio.changed(); await settle(); hit=ray(world,Vector2(-6,4))
	check(terrain.chunks.is_empty() and world.get_node("Foundation").visible and world.get_node("Foundation").collision_layer==2 and not hit.is_empty() and absf(hit["position"].y)<.002,"Disabling terrain restores the legacy ground and its original collision")
	studio.free(); print("TERRAIN WORLD 3D: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
