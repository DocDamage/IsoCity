extends SceneTree
const Plan=preload("res://scripts/builder/prop_plan.gd")
var captures: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func settle() -> void:
	for frame in 8:await physics_frame
	for frame in 12:await process_frame
func run() -> void:
	var scene: Node=load("res://city.tscn").instantiate();root.add_child(scene);await settle();scene.player.set_physics_process(false)
	var exploration: Node=scene.exploration
	for host in scene.live_data["objects"]:
		scene.set_process(true);scene.player.teleport_to(exploration.entrance(exploration.instances[host["uid"]]));scene.player.set_physics_process(false)
		var event:=InputEventKey.new();event.keycode=KEY_E;event.pressed=true;scene._unhandled_input(event);await settle()
		if not exploration.interior:failures+=1;printerr("FAIL: rendered independent room entry");continue
		var context: Dictionary=Plan.context(exploration)
		for item in context["data"]["objects"]:
			var profile: Dictionary=Plan.profile(item)
			if profile.is_empty():continue
			var candidate: Dictionary=context.duplicate(false);candidate["item"]=item;candidate["node"]=context["instances"][item["uid"]];candidate["profile"]=profile
			var point: Variant=Plan.ground_point(candidate,exploration,"approach");scene.player.teleport_to(scene.player.get_parent().to_local(point));scene.player.set_physics_process(false)
			if not exploration.props.interact(candidate):failures+=1;printerr("FAIL: rendered kit station use")
			break
		scene.set_process(false)
		if scene.dimension=="2d":scene.camera.position=Vector2.ZERO;scene.camera.zoom=Vector2(2,2)
		else:
			scene.camera.projection=Camera3D.PROJECTION_ORTHOGONAL;scene.camera.size=12;scene.camera.global_position=Vector3(0,1,0)+Basis.from_euler(Vector3(deg_to_rad(-45),deg_to_rad(45),0))*Vector3(0,0,12);scene.camera.look_at(Vector3(0,1,0))
		await settle();await RenderingServer.frame_post_draw
		if root.get_texture().get_image().save_png("res://rendered_"+host["uid"]+".png")!=OK:failures+=1;printerr("FAIL: independent room capture")
		captures+=1;exploration.props.finish(true);exploration.leave_interior();await settle()
	scene.free();await process_frame;print("Rendered independent interiors: %d captures, %d failures"%[captures,failures]);quit(1 if failures else 0)
