extends SceneTree
const Plan=preload("res://scripts/builder/driving_plan.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle(frames: int=6) -> void:
	for frame in frames: await physics_frame
	await process_frame
func press(scene: Node,code: int) -> void:
	var key:=InputEventKey.new(); key.keycode=code; key.pressed=true; scene._unhandled_input(key)
func held(code: int,value: bool) -> void:
	var key:=InputEventKey.new(); key.keycode=code; key.physical_keycode=code; key.pressed=value; Input.parse_input_event(key)
func run() -> void:
	var path: String="res://city.tscn"
	for mode in ["2d","3d"]:
		if "--"+mode in OS.get_cmdline_user_args(): path="res://output/driving_"+mode+".tscn"
	var scene: Node=load(path).instantiate(); root.add_child(scene); await settle(); scene.player.set_physics_process(false)
	var mode: String=scene.dimension; var runtime: Node=scene.exploration.driving; var player: Node=scene.player; var before: Dictionary=scene.studio_data.duplicate(true)
	check(runtime!=null and Plan.definitions()["assets"].has("2d:Sedan_Blue"),"Export includes driving runtime and catalog")
	var car: Dictionary=scene.live_data["objects"].filter(func(item: Dictionary)->bool:return not Plan.profile(item).is_empty())[0]; var original: Variant=scene.city_instances[car["uid"]].transform
	var center: Vector2=Plan.center(car,scene.exploration.library,mode); var extent: Vector2=Plan.dimensions(car,scene.exploration.library,mode); var forward: Vector2=Plan.heading(Plan.yaw(car)); var right:=Vector2(forward.y,-forward.x); var point: Vector2=center+right*(extent.x+.8)
	var destination: Variant=Plan.world(point,mode)
	if mode=="3d": destination=scene.terrain_traversal.start_candidate(point,destination,false)
	check(destination!=null,"Export finds supported approach beside road vehicle")
	if destination==null: scene.free(); quit(1); return
	player.teleport_to(destination); await settle(); press(scene,KEY_E)
	check(not runtime.active.is_empty() and not player.visible,"Actual exported E input enters vehicle")
	if runtime.active.is_empty(): scene.free(); quit(1); return
	held(KEY_W,true); await settle(60); held(KEY_W,false)
	check(runtime.active["point"].distance_to(center)>1 and runtime.speed>1,"Exported physical forward input drives vehicle through city")
	press(scene,KEY_E); check(not runtime.active.is_empty() and runtime.notice.contains("stop"),"Export requires stopping before exit")
	held(KEY_SPACE,true); await settle(90); held(KEY_SPACE,false); check(absf(runtime.speed)<.01,"Exported physical Space brakes vehicle to a stop")
	press(scene,KEY_E); check(runtime.active.is_empty() and player.visible and player.collision_mask>0,"Exported E exits safely onto walking surface")
	await settle(); player.set_physics_process(false); press(scene,KEY_E); check(not runtime.active.is_empty(),"Export re-enters vehicle at parked destination")
	check(scene.studio_data==before,"Driving leaves exported authoritative layout unchanged")
	if "--capture" in OS.get_cmdline_user_args():
		await settle(); RenderingServer.force_draw(false); RenderingServer.force_draw(false); root.get_texture().get_image().save_png("res://output/driving_export_"+mode+".png")
	press(scene,KEY_TAB); check(runtime.active.is_empty() and runtime.parked.is_empty() and scene.city_instances[car["uid"]].transform==original,"Switching to free camera restores source vehicles and releases controller")
	scene.free(); await process_frame; print("DRIVING EXPORT: %d checks, %d failures"%[checks,failures]); quit(1 if failures else 0)
