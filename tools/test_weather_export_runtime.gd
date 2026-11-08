extends SceneTree
const Plan=preload("res://scripts/builder/weather_plan.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for frame in 5: await physics_frame
	await process_frame
func capture(mode: String,stage: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	for frame in 5: await process_frame
	RenderingServer.force_draw(false); RenderingServer.force_draw(false); root.get_texture().get_image().save_png("res://output/weather_export_"+mode+"_"+stage+".png")
func run() -> void:
	var path: String="res://city.tscn"
	for mode in ["2d","3d"]:
		if "--"+mode in OS.get_cmdline_user_args(): path="res://output/weather_"+mode+".tscn"
	var scene: Node=load(path).instantiate(); root.add_child(scene); await settle(); scene.player.set_physics_process(false)
	var mode: String=scene.dimension; var weather: Node=scene.weather; var before: Dictionary=scene.studio_data.duplicate(true)
	check(weather!=null and weather.current_state["seed"]==431 and weather.current_state["condition"]=="wind","Playable export retains its actual weather runtime and saved controls")
	check(weather.screen.visible and weather.screen.gust==.8 and weather.screen.particles.size()==360,"Export renders wind with a bounded stable particle population")
	check(not weather.foliage.entries.is_empty() and Plan.foliage("2d:Tree_Cherry_Blossom")=="blossom","Portable runtime can load explicit seasonal foliage metadata")
	var particles: Array=weather.screen.particles.duplicate(); var elapsed: float=weather.elapsed
	weather.elapsed=30; scene._process(0)
	check(weather.current_state["effective_season"]=="spring" and scene.studio_data==before,"Exported season cycling wraps winter to spring without changing authored data")
	check(weather.screen.particles==particles,"Cycling foliage does not reseed precipitation")
	weather.elapsed=elapsed
	scene.live_data["weather"]["condition"]="rain"; scene._process(1.0/60)
	check(weather.screen.visible and weather.screen.rain==.8 and weather.screen.snow==0,"Exported runtime resolves rain from loaded city settings")
	var clock: float=weather.screen.clock; var point: Vector2=weather.screen.particle_position(weather.screen.particles[0],"rain"); scene._process(.1)
	check(weather.screen.clock>clock and weather.screen.particle_position(weather.screen.particles[0],"rain")!=point,"Actual exported precipitation moves over time")
	if mode=="3d":
		var old: Vector2=weather.screen.wind; scene.yaw+=90; scene._process(1.0/60)
		var right:=Vector2(scene.camera.global_basis.x.x,scene.camera.global_basis.x.z).normalized(); var force: Vector2=weather.current_state["wind_vector"]
		check(not weather.screen.wind.is_equal_approx(old) and is_equal_approx(weather.screen.wind.x,force.dot(right)),"Wind follows current exported camera orientation")
	await capture(mode,"rain")
	scene.live_data["weather"]["condition"]="snow"; scene._process(1.0/60)
	check(weather.screen.snow==.8 and weather.screen.rain==0,"Export switches precipitation without stale rain")
	await capture(mode,"snow")
	var host: Dictionary=scene.live_data["objects"].filter(func(item: Dictionary)->bool:return item.get("interior") is Dictionary)[0]
	var outside: Variant=scene.exploration.entrance(scene.exploration.instances[host["uid"]]); scene.player.teleport_to(outside); scene.exploration.interact(); await settle(); scene._process(1.0/60)
	check(scene.exploration.interior!=null and not weather.screen.visible and weather.foliage.entries.is_empty(),"Actually entering an exported building suppresses outdoor precipitation and wind")
	clock=weather.elapsed
	for frame in 60: scene._process(1.0/60)
	check(is_equal_approx(weather.elapsed,clock),"Season preview clock pauses while indoors")
	await capture(mode,"inside")
	scene.exploration.leave_interior(); scene.player.teleport_to(outside); await settle(); scene._process(1.0/60)
	check(weather.screen.visible and weather.screen.snow==.8 and not weather.foliage.entries.is_empty(),"Returning outdoors restores precipitation and seasonal foliage")
	scene.walking=false; scene._process(1.0/60); check(weather.screen.visible,"Exported free-camera view retains exterior weather")
	scene.live_data["weather"]["enabled"]=false; scene._process(1.0/60)
	check(not weather.screen.visible and weather.foliage.entries.is_empty(),"Disabling exported weather restores original visuals")
	scene.live_data["weather"]=before["weather"].duplicate(true)
	check(scene.studio_data==before,"Runtime effects and room transitions preserve all authored objects and settings")
	scene.free(); await process_frame
	print("WEATHER EXPORT: %d checks, %d failures"%[checks,failures]); quit(1 if failures else 0)
