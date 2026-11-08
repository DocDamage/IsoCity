extends "res://tools/test_resident_stair_context.gd"
func facts_path() -> String:return "res://output/verification/asset_expansion/I14/stair_gallery_facts.json"
func before_close(mode: String) -> void:await capture_walk(mode,"before")
func after_open(mode: String) -> void:await capture_walk(mode,"reopened")
func capture_walk(mode: String,stage: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args():return
	var world: Node=studio.worlds[mode];var camera: Node=world.camera;var processing: bool=world.is_processing();var studio_processing: bool=studio.is_processing();var position: Variant=camera.position;var zoom: Vector2=camera.zoom if mode=="2d" else Vector2.ONE;var walking: bool=world.walking if mode=="3d" else false;var target: Vector3=world.target if mode=="3d" else Vector3.ZERO;var distance: float=world.distance if mode=="3d" else 0.0
	world.set_process(false);studio.set_process(false)
	if mode=="2d":camera.position=Vector2(16,-20);camera.zoom=Vector2(4,4)
	else:world.walking=false;world.target=Vector3(0,1.5,-1);world.distance=9;world.update_camera()
	await settle();RenderingServer.force_draw(false);RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png("res://output/verification/asset_expansion/I14/stair_"+stage+"_"+mode+".png")==OK,"Captured the actual original body on the native stair flight: "+mode+" "+stage)
	if mode=="2d":camera.position=position;camera.zoom=zoom
	else:world.walking=walking;world.target=target;world.distance=distance;world.update_camera()
	world.set_process(processing);studio.set_process(studio_processing)
