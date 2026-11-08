extends Node

const Plan=preload("res://scripts/builder/ambience_plan.gd")
const Bank=preload("res://scripts/builder/ambience_bank.gd")
const BUS: String="IsoCity Ambience"
const LIVE_LIMIT: int=Plan.MAX_VOICES*2
var viewport: SubViewport
var camera: Camera3D
var stage: Node3D
var voices: Dictionary={}
var levels: Dictionary={}
var muted: bool=false
var selected: Array[Dictionary]=[]
var last_stop_usec: int=-1000000

func _ready() -> void:
	if AudioServer.get_bus_index(BUS)<0:
		AudioServer.add_bus(); AudioServer.set_bus_name(AudioServer.bus_count-1,BUS)
	viewport=SubViewport.new(); viewport.name="AudioWorld"; viewport.size=Vector2i(2,2); viewport.own_world_3d=true; viewport.audio_listener_enable_3d=true; viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED; add_child(viewport)
	stage=Node3D.new(); viewport.add_child(stage)
	camera=Camera3D.new(); stage.add_child(camera); camera.current=true

func step(delta: float,sources: Array,listener: Vector3,config: Dictionary,right: Vector3=Vector3.RIGHT) -> void:
	if not is_finite(delta) or delta<=0 or not listener.is_finite(): return
	var horizontal:=Vector3(right.x,0,right.z).normalized()
	if horizontal.is_zero_approx(): horizontal=Vector3.RIGHT
	camera.transform=Transform3D(Basis(horizontal,Vector3.UP,horizontal.cross(Vector3.UP)),listener)
	var settings: Dictionary=config.duplicate(true)
	if muted: settings["enabled"]=false
	selected = Plan.mix(sources,listener,settings,func(kind: String)->bool: return Bank.stream(kind) != null)
	var targets: Dictionary={}
	for source in selected: targets[source["uid"]]=source
	# Reserve at most one previous selection while changing room/floor context.
	# Quiet old voices are retired first if contexts change again mid-fade.
	var stale: Array=voices.keys().filter(func(uid: String)->bool:return not targets.has(uid))
	stale.sort_custom(func(a: String,b: String)->bool:return voices[a]["level"]<voices[b]["level"])
	var missing: int=targets.keys().filter(func(uid: String)->bool:return not voices.has(uid)).size()
	while voices.size()+missing>LIVE_LIMIT and not stale.is_empty(): retire(stale.pop_front())
	for source in selected:
		var uid: String=source["uid"]
		if voices.has(uid) and voices[uid]["kind"]!=source["kind"]: retire(uid)
		if not voices.has(uid):
			var stream: AudioStreamWAV=Bank.stream(source["kind"])
			if not stream: continue
			var player:=AudioStreamPlayer3D.new(); player.name="AmbientVoice"; player.stream=stream; player.bus=BUS; player.attenuation_model=AudioStreamPlayer3D.ATTENUATION_DISABLED; player.max_db=0; player.volume_db=-80; player.attenuation_filter_cutoff_hz=20500; stage.add_child(player)
			player.position = source["position"]
			var offset: float = float(posmod(hash(uid),8000))/1000 if not source["kind"] in ["arcade","workshop"] else 0.0
			player.play(fmod(offset,stream.get_length()))
			voices[uid]={"player":player,"kind":source["kind"],"level":0.0}
		voices[uid]["player"].position=source["position"]
	levels.clear(); var total: float=0; var power: float=0
	for uid in voices.keys():
		var voice: Dictionary=voices[uid]; voice["level"]=Plan.smooth(voice["level"],targets.get(uid,{}).get("level",0),delta)
		if voice["level"]<.00005 and not targets.has(uid): retire(uid); continue
		total+=voice["level"]; power+=voice["level"]*voice["level"]
	var scale: float=minf(1,minf(.75/sqrt(maxf(.000001,power)),1.25/maxf(.000001,total)))
	for uid in voices:
		var value: float=voices[uid]["level"]*scale; levels[uid]=value
		voices[uid]["player"].volume_db=linear_to_db(maxf(.00001,value))

func retire(uid: String) -> void:
	if not voices.has(uid): return
	if is_instance_valid(voices[uid]["player"]): voices[uid]["player"].stop(); voices[uid]["player"].free()
	last_stop_usec=Time.get_ticks_usec()
	voices.erase(uid); levels.erase(uid)

func reset() -> void:
	for uid in voices.keys(): retire(uid)
	selected.clear(); levels.clear()

func _exit_tree() -> void:
	var playing: bool=not voices.is_empty()
	for voice in voices.values():
		if is_instance_valid(voice["player"]): voice["player"].stop()
	voices.clear(); levels.clear(); selected.clear()
	# Native playback is released by the audio thread on its next mix. Allow
	# that handoff before shutdown destroys the viewport and stream cache.
	if playing: last_stop_usec=Time.get_ticks_usec()
	var period: float=AudioServer.get_time_since_last_mix()+AudioServer.get_time_to_next_mix()
	var window_ms: float=clampf(period*2000+10,50,250)
	var remaining: int=ceili(window_ms-float(Time.get_ticks_usec()-last_stop_usec)/1000)
	if remaining>0: OS.delay_msec(remaining)
