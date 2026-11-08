extends SceneTree
const Plan=preload("res://scripts/builder/ambience_plan.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func emitter(uid: String,kind: String,position: Vector3) -> Dictionary:
	var value: Dictionary=Plan.definitions()["kinds"][kind].duplicate(true); value.merge({"uid":uid,"kind":kind,"position":position}); return value
func run() -> void:
	var runtime=preload("res://scripts/builder/ambience_runtime.gd").new(); root.add_child(runtime); var config: Dictionary=Plan.defaults()
	var sources: Array=[emitter("water","fountain",Vector3(0,0,-2)),emitter("birds","birds",Vector3(3,2,-3))]
	for frame in 60: runtime.step(1.0/60,sources,Vector3.ZERO,config)
	check(runtime.viewport.own_world_3d and runtime.viewport.audio_listener_enable_3d and runtime.viewport.get_camera_3d()==runtime.camera,"The audio world has its own active spatial listener")
	check(runtime.voices.size()==2 and runtime.levels["water"]>0 and runtime.levels["birds"]>0,"Nearby source categories create native spatial voices with actual gain")
	var player: AudioStreamPlayer3D=runtime.voices["water"]["player"]; var near: float=runtime.levels["water"]
	check(player.playing and player.stream is AudioStreamWAV and player.bus==runtime.BUS and player.position==sources[0]["position"],"Native voices play their looping PCM stream at the authored position on the dedicated bus")
	check(is_equal_approx(db_to_linear(player.volume_db),near),"Computed mixing gain reaches the real audio player")
	for frame in 8: await physics_frame
	OS.delay_msec(150); await process_frame
	var bus: int=AudioServer.get_bus_index(runtime.BUS)
	var output: float=maxf(AudioServer.get_bus_peak_volume_left_db(bus,0),AudioServer.get_bus_peak_volume_right_db(bus,0))
	check(output>-70 and output<0,"The native audio server receives a nonclipping mixed signal from the isolated spatial world")
	print("AMBIENCE OUTPUT: ",output," dB")
	runtime.step(1.0/60,sources,Vector3.ZERO,config,Vector3(0,0,-1)); check(runtime.camera.global_basis.x.is_equal_approx(Vector3(0,0,-1)),"The virtual listener tracks the scene's viewing direction")
	for frame in 60: runtime.step(1.0/60,sources,Vector3(20,0,0),config)
	check(runtime.voices["water"]["player"]==player and runtime.levels["water"]<near,"Moving the listener attenuates existing voices without restarting them")
	for frame in 180: runtime.step(1.0/60,sources,Vector3(200,0,0),config)
	check(runtime.voices.is_empty() and runtime.levels.is_empty(),"Out-of-range sources fade away and release native audio nodes")
	runtime.step(1.0/60,sources,Vector3.ZERO,config); runtime.muted=true
	for frame in 180: runtime.step(1.0/60,sources,Vector3.ZERO,config)
	check(runtime.voices.is_empty(),"A runtime mute fades and releases every source")
	runtime.muted=false; var crowd: Array=[]
	for index in 100: crowd.append(emitter("crowd_"+str(index),"shop",Vector3.ZERO))
	for frame in 60: runtime.step(1.0/60,crowd,Vector3.ZERO,config)
	check(runtime.voices.size()==Plan.MAX_VOICES,"Dense scenes only instantiate the selected source budget")
	var next: Array=[]
	for index in 100: next.append(emitter("next_"+str(index),"interior",Vector3.ZERO))
	runtime.step(1.0/60,next,Vector3.ZERO,config); var total: float=0
	for level in runtime.levels.values(): total+=level
	check(runtime.voices.size()<=runtime.LIVE_LIMIT and total<=1.250001,"Context crossfades keep bounded native voices and aggregate output")
	for frame in 180: runtime.step(1.0/60,next,Vector3.ZERO,config)
	check(runtime.voices.size()==Plan.MAX_VOICES and runtime.voices.keys().all(func(uid: String)->bool:return uid.begins_with("next_")),"Old room/context voices are retired after their fade")
	runtime.reset(); check(runtime.voices.is_empty() and runtime.stage.get_child_count()==1,"Reset releases voices while retaining the isolated listener")
	var panned: Array=[emitter("pan","fountain",Vector3(-8,0,-4))]
	for frame in 60: runtime.step(1.0/60,panned,Vector3.ZERO,config)
	for frame in 8: await physics_frame
	OS.delay_msec(150); await process_frame
	var left: float=AudioServer.get_bus_peak_volume_left_db(bus,0); var right: float=AudioServer.get_bus_peak_volume_right_db(bus,0)
	check(left>right+.5,"A source to the listener's left produces stronger real left-channel output")
	for frame in 60: runtime.step(1.0/60,panned,Vector3.ZERO,config,Vector3.LEFT)
	for frame in 8: await physics_frame
	OS.delay_msec(150); await process_frame
	left=AudioServer.get_bus_peak_volume_left_db(bus,0); right=AudioServer.get_bus_peak_volume_right_db(bus,0)
	check(right>left+.5,"Rotating the scene-facing listener reverses actual stereo panning")
	runtime.free(); OS.delay_msec(120); await process_frame
	print("AMBIENCE RUNTIME: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
