extends SceneTree
const Plan=preload("res://scripts/builder/photo_plan.gd")
var checks: int=0
var failures: int=0
var studio: Control
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for frame in 5: await physics_frame
	await process_frame
func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio); await settle()
	for raw in [null,[],{"dof_enabled":1},{"focus_distance":0},{"focus_range":INF},{"blur":NAN},{"move_speed":41},{"focus_band":-1},{"band_width":0},{"bookmarks":1},{"paths":[{}]}]: check(not Plan.valid(raw,"3d"),"Malformed camera controls rejected: "+str(raw))
	for mode in ["2d","3d"]:
		if "--2d" in OS.get_cmdline_user_args() and mode!="2d": continue
		if "--3d" in OS.get_cmdline_user_args() and mode!="3d": continue
		studio.switch_mode(mode); var world: Node=studio.worlds[mode]; var runtime: Node=world.exploration.photo; var doc: RefCounted=studio.current(); var before: Dictionary=doc.data.duplicate(true); var history: int=doc.undo_history.size(); var player: Node=world.player
		var original: Variant=world.camera.transform; var original_zoom: Vector2=world.camera.zoom if mode=="2d" else Vector2.ONE; var original_attributes: CameraAttributes=world.camera.attributes if mode=="3d" else null; var physics: bool=player.is_physics_processing(); var visible: bool=player.visible
		check(runtime.start() and runtime.active and not player.is_physics_processing() and not world.exploration.walk_allowed(),"Photo mode takes temporary camera control and suspends avatar movement: "+mode)
		check(Plan.view_valid(runtime.capture_view(),mode),"Actual current camera produces a serializable view: "+mode)
		var start: Dictionary=runtime.view.duplicate(true); runtime.navigate(.1,Vector3(1,0,-1)); var changed: Dictionary=runtime.view.duplicate(true); await settle()
		var actual: Array=runtime.capture_view()["position"]; var expected: Array=changed["position"]; var matches: bool=true
		for index in actual.size(): matches=matches and is_equal_approx(actual[index],expected[index])
		check(runtime.view["position"]!=start["position"] and matches,"Free camera navigation survives normal Studio camera updates: "+mode)
		runtime.configure({"dof_enabled":true,"focus_distance":8,"focus_range":3,"blur":.8,"focus_band":.6,"band_width":.2,"hide_avatar":true})
		if mode=="3d": check(world.camera.attributes is CameraAttributesPractical and world.camera.attributes.dof_blur_far_enabled and world.camera.attributes.dof_blur_near_enabled and is_equal_approx(world.camera.attributes.dof_blur_far_distance,9.5),"Depth of field configures actual camera attributes and focus distances")
		else: check(runtime.focus_layer.visible and is_equal_approx(runtime.focus_screen.material.get_shader_parameter("focus_band"),.6),"2D focus band configures the actual full-screen shader")
		check(not player.visible,"Hide avatar changes actual character visibility: "+mode)
		var bookmark: Dictionary={"uid":"bookmark_test","name":"My camera","view":runtime.capture_view()}; check(Plan.entry_valid(bookmark,mode),"Bookmark contains valid camera and focus settings: "+mode)
		runtime.start_recording()
		for index in 10: runtime.navigate(.1,Vector3(1,0,0)); runtime.advance(.1)
		var samples: Array=runtime.stop_recording().duplicate(true); var take: Dictionary={"uid":"take_test","name":"Street pass","samples":samples}
		check(samples.size()>=10 and Plan.entry_valid(take,mode,true) and runtime.pending_take,"Recording captures a bounded timed camera take: "+mode)
		var midpoint: Dictionary=Plan.sample(samples,.5,mode); check(midpoint["position"]!=samples[0]["view"]["position"] and midpoint["position"]!=samples[-1]["view"]["position"],"Path sampling interpolates actual camera movement: "+mode)
		check(runtime.play(take),"Saved camera path can start playback: "+mode); runtime.advance(.5); check(runtime.view["position"]==midpoint["position"],"Playback moves camera to the interpolated timestamp: "+mode)
		runtime.advance(2); check(runtime.playing.is_empty() and runtime.view["position"]==samples[-1]["view"]["position"],"One-shot playback stops exactly at the final camera pose: "+mode)
		runtime.play(take,true); runtime.advance(1.25); check(not runtime.playing.is_empty() and is_equal_approx(runtime.play_elapsed,.25),"Loop playback wraps by actual recorded duration: "+mode); runtime.playing=[]
		var raw: Dictionary={"dof_enabled":true,"bookmarks":[bookmark],"paths":[take]}; var serialized: Dictionary=JSON.parse_string(JSON.stringify(raw))
		if not Plan.valid(raw,mode) or not Plan.valid(serialized,mode): print("PHOTO JSON DEBUG: "+mode+" raw="+str(Plan.valid(raw,mode))+" serialized="+str(Plan.valid(serialized,mode))+" bookmark="+str(Plan.entry_valid(serialized["bookmarks"][0],mode))+" path="+str(Plan.entry_valid(serialized["paths"][0],mode,true))+" view="+JSON.stringify(serialized["bookmarks"][0]["view"]))
		check(Plan.valid(raw,mode) and Plan.valid(serialized,mode),"Camera library survives JSON serialization: "+mode)
		check(runtime.apply_view(serialized["bookmarks"][0]["view"]) and runtime.play(serialized["paths"][0]),"JSON-loaded camera enums and numeric fields apply to actual camera and playback: "+mode); runtime.playing=[]
		var invalid: Dictionary=take.duplicate(true); invalid["samples"][1]["time"]=0; check(not Plan.entry_valid(invalid,mode,true),"Duplicate/non-increasing camera timestamps are rejected: "+mode)
		var damaged: Dictionary=doc.data.duplicate(true); damaged["photo"]={"blur":7,"bookmarks":[bookmark,{}],"paths":[take,invalid],"future_camera_field":12}
		check(not preload("res://scripts/builder/document.gd").valid(damaged,mode,studio.library),"Project validation rejects damaged camera libraries: "+mode)
		var repair=preload("res://scripts/builder/project_repair.gd").new(studio.library); var repaired: Dictionary=repair.world(damaged,mode,"city",0)
		check(preload("res://scripts/builder/document.gd").valid(repaired,mode,studio.library) and repaired["photo"]["bookmarks"].size()==1 and repaired["photo"]["paths"].size()==1 and repaired["photo"]["future_camera_field"]==12 and not repair.issues.is_empty(),"Repair retains valid bookmarks, paths and future fields while archiving malformed camera data: "+mode)
		var hud:=CanvasLayer.new(); hud.name="TestPhotoHUD"; hud.layer=40; world.add_child(hud); var banner:=ColorRect.new(); banner.color=Color.MAGENTA; banner.size=Vector2(96,48); hud.add_child(banner); await settle()
		var suffix: String="_compatibility" if "gl_compatibility" in OS.get_cmdline_args() else ""
		runtime.configure({"dof_enabled":false}); var path: String="res://output/photo_clean_"+mode+suffix+".png"; var result: Error=await runtime.screenshot(path)
		if DisplayServer.get_name()=="headless": check(result==ERR_UNAVAILABLE and not runtime.capture_busy and hud.visible,"Headless capture reports unavailable without changing visibility: "+mode)
		else:
			var frame: Image=Image.load_from_file(path); check(result==OK and frame and not frame.is_empty() and frame.get_size()==Vector2i(world.get_viewport().get_visible_rect().size),"Clean capture saves a full-resolution PNG: "+mode)
			check(not frame.get_pixel(8,8).is_equal_approx(Color.MAGENTA) and hud.visible and runtime.active,"Clean capture omits actual in-viewport HUD and restores it afterward: "+mode)
		hud.free()
		if DisplayServer.get_name()!="headless":
			runtime.configure({"dof_enabled":true,"blur":.8}); await settle(); var focus_path: String="res://output/photo_focus_"+mode+suffix+".png"; await runtime.screenshot(focus_path)
			var sharp: Image=Image.load_from_file(path); var blurred: Image=Image.load_from_file(focus_path); var difference: float=0; var pixels: int=0
			for x in range(0,sharp.get_width(),8):
				for y in range(0,sharp.get_height(),8):
					var a: Color=sharp.get_pixel(x,y); var b: Color=blurred.get_pixel(x,y); difference+=absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b); pixels+=1
			check(difference/pixels>.002,"Enabled focus changes actual rendered scene pixels: "+mode+" · delta="+str(difference/pixels))
		runtime.stop()
		if mode=="2d":
			runtime.start(); var lens: Dictionary=runtime.capture_view(); lens["zoom"]=[16,16]; lens["frame_height"]=maxf(1,world.get_viewport().get_visible_rect().size.y/4); runtime.apply_view(lens)
			check(world.camera.zoom.x>16 and Plan.view_valid(runtime.capture_view(),mode),"Viewport-scaled high zoom remains serializable in its canonical framing")
			runtime.stop()
		check(not runtime.active and world.camera.transform.is_equal_approx(original) and (world.camera.zoom==original_zoom if mode=="2d" else world.camera.attributes==original_attributes),"Leaving photo mode restores camera pose, lens and original attributes exactly: "+mode)
		check(player.visible==visible and player.is_physics_processing()==physics,"Photo cleanup restores actual avatar control and visibility: "+mode)
		check(doc.data==before and doc.undo_history.size()==history,"Navigation, recording, playback and screenshots leave city/history unchanged: "+mode)
	studio.free(); await process_frame; print("PHOTO FOUNDATION: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
