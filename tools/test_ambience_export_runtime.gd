extends SceneTree
const Plan=preload("res://scripts/builder/ambience_plan.gd")
const Floors=preload("res://scripts/builder/floor_plan.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func mix(scene: Node,frames: int=120) -> void:
	for frame in frames: scene._process(1.0/60)
func teleport(scene: Node,point: Vector3) -> void:
	var values: Array=Plan.Traffic.world(Vector2(point.x,point.z),scene.dimension,point.y)
	scene.player.teleport_to(Vector2(values[0],values[1]) if scene.dimension=="2d" else Vector3(values[0],values[1],values[2]))
func mute_key() -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.keycode = KEY_M
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame

func settle() -> void:
	for frame in 5: await physics_frame
	await process_frame
func capture(mode: String,stage: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	for frame in 5: await process_frame
	RenderingServer.force_draw(false); RenderingServer.force_draw(false); root.get_texture().get_image().save_png("res://output/ambience_export_"+mode+"_"+stage+".png")
func run() -> void:
	var path: String="res://city.tscn"
	for mode in ["2d","3d"]:
		if "--"+mode in OS.get_cmdline_user_args(): path="res://output/ambience_"+mode+".tscn"
	var scene: Node=load(path).instantiate(); root.add_child(scene)
	for frame in 6: await process_frame
	await settle(); scene.player.set_physics_process(false)
	var mode: String=scene.dimension; var audio: Node=scene.ambience
	check(audio!=null and scene.ambience_context!=null and Plan.settings(scene.live_data)["volume"]==.8,"A playable export retains its integrated audio runtime and saved city mix")
	for kind in Plan.KINDS:
		var stream: AudioStreamWAV=preload("res://scripts/builder/ambience_bank.gd").stream(kind)
		check(stream!=null and stream.loop_mode==AudioStreamWAV.LOOP_FORWARD and stream.loop_end==176400,"Portable playback can load its actual looping source: "+kind)
	var fountain: Dictionary=Plan.emitters(scene.live_data,scene.exploration.library).filter(func(item: Dictionary)->bool:return item["kind"]=="fountain")[0]
	var nearby: Vector3=fountain["position"]+Vector3(5,0,0); nearby.y=.05; teleport(scene,nearby); mix(scene)
	check(audio.selected.any(func(item: Dictionary)->bool:return item["kind"]=="fountain") and audio.selected.all(func(item: Dictionary)->bool:return item["kind"]!="birds"),"Exported walking uses distance and category controls at the actual character")
	if mode=="3d":
		scene.yaw+=90; scene._process(1.0/60)
		check(scene.ambience_context.last_right.is_equal_approx(Vector3(scene.camera.global_basis.x.x,0,scene.camera.global_basis.x.z).normalized()),"Exported spatial orientation follows the current camera frame")
	await settle(); OS.delay_msec(150); await process_frame
	var bus: int=AudioServer.get_bus_index(audio.BUS); var peak: float=maxf(AudioServer.get_bus_peak_volume_left_db(bus,0),AudioServer.get_bus_peak_volume_right_db(bus,0))
	check(peak>-75 and peak<0,"The exported city produces an actual nonclipping audio-server signal")
	await capture(mode,"outside")
	var data: Dictionary=scene.studio_data.duplicate(true)
	await mute_key()
	mix(scene,180)
	check(audio.muted and audio.voices.is_empty() and scene.studio_data==data,"The exported mute shortcut fades sources without editing authored data")
	await settle(); OS.delay_msec(150); await process_frame
	check(maxf(AudioServer.get_bus_peak_volume_left_db(bus,0),AudioServer.get_bus_peak_volume_right_db(bus,0))<-75,"The exported mute also silences actual bus output")
	await mute_key()
	teleport(scene,nearby+Vector3(300,0,300)); mix(scene,180); check(audio.voices.is_empty(),"Distant exported sources become silent and release playback nodes")
	teleport(scene,nearby); mix(scene)
	var host: Dictionary=scene.live_data["objects"].filter(func(item: Dictionary)->bool:return not item.get("interior",{}).get("floors",[]).is_empty())[0]; var host_uid: String=host["uid"]; var top: String=host["interior"]["floors"][0]["uid"]
	var outside: Variant=scene.exploration.entrance(scene.exploration.instances[host_uid]); scene.player.teleport_to(outside); scene.exploration.interact(); await settle(); mix(scene,180)
	check(scene.exploration.interior!=null and audio.selected.any(func(item: Dictionary)->bool:return item["kind"]=="interior") and audio.voices.keys().all(func(uid: String)->bool:return uid.begins_with("room:"+host_uid+":ground:")),"Entering a building fades exterior sources and opens its own room ambience")
	if mode=="2d": scene.exploration.interior.floor_stack.switch_floor(top)
	scene.player.teleport_to(Vector2(0,60) if mode=="2d" else Vector3(0,3.1,2.5)); await settle(); mix(scene,180)
	check(scene.exploration.active_floor()==top and scene.ambience_context.last_listener.y>=3 and audio.voices.keys().all(func(uid: String)->bool:return uid.begins_with("room:"+host_uid+":"+top+":")),"The exported listener and source ownership follow its upstairs room")
	check(audio.selected.any(func(item: Dictionary)->bool:return item["kind"]=="fountain"),"The saved upstairs object's authored sound override remains audible")
	await capture(mode,"upstairs")
	scene.exploration.leave_interior(); teleport(scene,nearby); mix(scene,180)
	check(audio.voices.keys().all(func(uid: String)->bool:return uid.begins_with("city:") or uid.begins_with("vehicle:")),"Returning outdoors retires upstairs playback and restores city sources")
	check(scene.studio_data==data,"Listening, room transitions and mute preserve all authored city and room settings")
	audio.reset(); scene.free(); OS.delay_msec(120); await process_frame
	print("AMBIENCE EXPORT: %d checks, %d failures"%[checks,failures]); quit(1 if failures else 0)
