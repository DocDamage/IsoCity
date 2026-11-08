extends "res://tools/test_resident_activity_raised.gd"
var captured: Dictionary={}
func tick() -> void:
	await super.tick()
	var mode: String=citizens.dimension
	if not "--capture" in OS.get_cmdline_user_args() or captured.has(mode) or not studio.worlds[mode].exploration.interior:return
	if citizens.activities.scheduler.jobs.values().filter(func(job: Dictionary):return job["state"]=="service").size()!=2:return
	captured[mode]=true;var world: Node=studio.worlds[mode];var camera: Node=world.camera;var processing: bool=world.is_processing();var studio_processing: bool=studio.is_processing();var position: Variant=camera.position;var zoom: Vector2=camera.zoom if mode=="2d" else Vector2.ONE;var walking: bool=world.walking if mode=="3d" else false;var target: Vector3=world.target if mode=="3d" else Vector3.ZERO;var distance: float=world.distance if mode=="3d" else 0.0
	world.set_process(false);studio.set_process(false)
	if mode=="2d":camera.position=Vector2(32,-56);camera.zoom=Vector2(5,5)
	else:world.walking=false;world.target=Vector3(0,3.2,-3);world.distance=8;world.update_camera()
	await settle();RenderingServer.force_draw(false);RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png("res://output/verification/asset_expansion/I14/raised_room_"+mode+".png")==OK,"Captured both original residents using source chairs on the raised room surface: "+mode)
	if mode=="2d":camera.position=position;camera.zoom=zoom
	else:world.walking=walking;world.target=target;world.distance=distance;world.update_camera()
	world.set_process(processing);studio.set_process(studio_processing)
