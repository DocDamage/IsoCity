extends SceneTree
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func settle() -> void:
	for frame in 12:await process_frame
func run() -> void:
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://expected.json"));var scene: Node=load("res://city.tscn").instantiate();scene.photo_storage_enabled=false;root.add_child(scene);await settle();scene.player.set_physics_process(false)
	check(JSON.parse_string(JSON.stringify(scene.studio_data))==expected,"Independent successful placements preserve every authored value and identity")
	var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://city-source.json"));check(source["documents"][scene.dimension]==expected and not JSON.stringify(source).contains("histories"),"Reopenable portable source contains the authored layout without personal histories")
	check(ProjectSettings.get_setting("rendering/renderer/rendering_method")==("gl_compatibility" if scene.dimension=="2d" else "forward_plus"),"Normal import preserves the effective desktop rendering setting")
	check(ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile")==("gl_compatibility" if scene.dimension=="2d" else "mobile"),"Normal import preserves the effective mobile rendering setting")
	for key in ["citizens","traffic","businesses","services","economy","scenario","zoning","transit","weather"]:check(not scene.studio_data.get(key,{}).get("enabled",false),"Personal recents enable no simulation: "+key)
	for item in expected["objects"]:
		check(scene.city_instances.has(item["uid"]),"Selected successful furnishing really instantiates independently")
		check(preload("res://scripts/builder/model_preview.gd").meaningful(scene.exploration.library.icon(item["asset"])),"Selected furnishing retains recognizable preview dependencies")
	if "--capture" in OS.get_cmdline_user_args():
		var item: Dictionary=expected["objects"][0];var raw: Array=item["position"];scene.set_process(false)
		if scene.dimension=="2d":scene.camera.position=Vector2(raw[0],raw[1]-float(raw[2])*8)-Vector2(0,8);scene.camera.zoom=Vector2(8,8)
		else:
			var center:=Vector3(raw[0],float(raw[1])+.4,raw[2]);scene.camera.projection=Camera3D.PROJECTION_ORTHOGONAL;scene.camera.size=3;scene.camera.global_position=center+Vector3(2.6,2.6,3.2);scene.camera.look_at(center)
		await settle();await RenderingServer.frame_post_draw;check(root.get_texture().get_image().save_png("res://rendered_recent.png")==OK,"Independent successful placement renders with ordinary runtime settings")
	scene.free();await process_frame;await process_frame;print("RECENT ASSET PORTABLE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
