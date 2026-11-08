extends SceneTree
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var scene: Node=load("res://city.tscn").instantiate(); root.add_child(scene)
	for frame in 6: await process_frame
	await physics_frame
	scene.player.set_physics_process(false); scene.player.teleport_to(Vector2(10000,10000) if scene.dimension=="2d" else Vector3(1000,0,1000)); scene.traffic.set_physics_process(false)
	var manager: Node=scene.traffic; var before: Dictionary=scene.studio_data.duplicate(true)
	check(manager.vehicles.size()==2 and manager.plan["sections"].size()==5,"Relocated terrain traffic rebuilds its fleet and gentle road network")
	var vehicle: Dictionary=manager.vehicles[0]; var start: Vector2=vehicle["point"]
	for frame in 300: manager.step(1.0/60)
	check(vehicle["point"].distance_to(start)>2 and vehicle["phase"]!="blocked","Relocated traffic physically progresses on the raised road")
	if scene.dimension=="3d":
		var plan=preload("res://scripts/builder/terrain_plan.gd"); var sample: Dictionary=plan.sample(scene.studio_data,vehicle["point"])
		check(vehicle["actor"].position.y>1 and vehicle["actor"].basis.y.normalized().distance_to(sample["normal"])<.001,"Relocated vehicles follow road height and bank angle")
		var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(.5,30,.5),Vector3(.5,-30,.5),2))
		check(not hit.is_empty() and absf(hit["position"].y-plan.sample(scene.studio_data,Vector2(.5,.5))["height"]-.11)<.002,"Relocated physical road mesh follows the terrain instead of retaining a flat slab")
	else:
		scene.terrain_presentation.refresh(); var actor: Node=vehicle["actor"]; var sprite: Sprite2D=actor.get_node("Sprite2D"); var delta: Vector2=sprite.global_transform.basis_xform(actor.terrain_visual_offset)
		check(delta.y < -8 and absf(delta.x)<.001,"Relocated sprite vehicles follow the elevated road")
	check(scene.studio_data==before,"Relocated traffic preserves authored terrain and roads")
	scene.free(); print("TERRAIN TRAFFIC EXPORT: %d checks, %d failures"%[checks,failures]); quit(1 if failures else 0)
