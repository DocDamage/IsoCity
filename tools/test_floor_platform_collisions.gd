extends SceneTree

const Cut=preload("res://scripts/builder/floor_cutouts_3d.gd")
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;print("FAIL: "+message)
func settle() -> void:
	for frame in 4:await physics_frame
func run() -> void:
	var library: RefCounted=preload("res://scripts/builder/asset_library.gd").new();var area:=Rect2(-6,-6,12,12)
	var cases: Array=[[],[Cut.polygon(Vector2(0,-.8),Vector2(0,.8),1.86,.13)],[Cut.polygon(Vector2(-1,-2),Vector2(1,2),1.2,.2),Cut.polygon(Vector2(0,-.8),Vector2(0,.8),1.86,.13)]]
	for case_index in cases.size():
		var world: Node3D=load("res://scripts/builder/world_3d.gd").new();world.library=library;root.add_child(world);world.apply(preload("res://scripts/builder/templates.gd").make("3d","blank"));world.player.set_physics_process(false);world.player.collision_layer=0
		var floor: Node3D=preload("res://scripts/builder/floor_surface_3d.gd").new();world.add_child(floor);floor.configure(world,area,cases[case_index]);await settle()
		var count: int=0;var mismatch: int=0;var wrong_height: int=0
		for x in range(-11,12):
			for z in range(-11,12):
				var point:=Vector2(x*.5,z*.5);var excluded: bool=false
				for hole in cases[case_index]:
					if Geometry2D.is_point_in_polygon(point,hole):excluded=true;break
				var ray:=PhysicsRayQueryParameters3D.create(Vector3(point.x,.5,point.y),Vector3(point.x,-.5,point.y),2);var hit: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(ray);count+=1
				if hit.is_empty()==(not excluded):mismatch+=1
				if not hit.is_empty() and absf(hit["position"].y)>.002:wrong_height+=1
		check(count==529 and mismatch==0 and wrong_height==0,"Physical slab support matches the flat visual surface and exact empty/rotated/overlapping openings: case "+str(case_index)+" mismatches="+str(mismatch))
		check(floor.platform.get_children().filter(func(node: Node):return node is CollisionShape3D).all(func(shape: CollisionShape3D):return shape.shape is ConvexPolygonShape3D),"Only the procedural flat slab uses convex volume pieces")
		if case_index==1:
			var walker: CharacterBody3D=preload("res://scripts/builder/player_3d.gd").new();walker.active=false;walker.move_speed=1.8;walker.collision_layer=0;walker.collision_mask=3;world.objects.add_child(walker);walker.set_physics_process(false);walker.teleport_to(Vector3(-2,.03,-3));await settle()
			var largest_step: float=0;var drift: float=0
			for frame in 240:
				await physics_frame;var previous: Vector3=walker.global_position;walker.move_character(1.0/60,Vector3.BACK);largest_step=maxf(largest_step,Vector2(walker.global_position.x-previous.x,walker.global_position.z-previous.z).length());drift=maxf(drift,absf(walker.global_position.x+2))
			check(walker.global_position.z>3 and drift<.03 and largest_step<.06 and walker.recovery_count==0,"Actual capsule crosses the former clipped-floor seam without sideways depenetration or recovery: drift="+str(drift)+" step="+str(largest_step))
		world.free();await settle()
	print("FLOOR PLATFORM COLLISIONS: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
