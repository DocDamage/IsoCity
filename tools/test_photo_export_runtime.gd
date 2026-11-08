extends SceneTree
const Plan=preload("res://scripts/builder/photo_plan.gd")
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
		if "--"+mode in OS.get_cmdline_user_args(): path="res://output/photo_"+mode+".tscn"
	var packed: PackedScene=load(path); var scene: Node=packed.instantiate(); scene.photo_storage_enabled=false; root.add_child(scene); await settle()
	var mode: String=scene.dimension; var ui: RefCounted=scene.photo_tools; var runtime: Node=scene.exploration.photo; var before: Dictionary=scene.studio_data.duplicate(true)
	var store: String="user://photo_verification/"+mode+"_"+str(Time.get_ticks_usec())+"/camera-library.json"; ui.storage_path=store; ui.storage_enabled=true
	check(ui!=null and Plan.settings(scene.live_data)["bookmarks"].size()==1 and Plan.settings(scene.live_data)["paths"].size()==1,"Playable export contains photo controls and authored city camera library")
	press(scene,KEY_P); await settle(); check(runtime.active and ui.dialog.visible and not scene.player.is_physics_processing(),"Actual exported P opens photo mode and suspends movement")
	var lens: Dictionary=runtime.view.duplicate(true); press(scene,KEY_EQUAL); check(runtime.view["zoom"]!=lens["zoom"] if mode=="2d" else runtime.view["fov"]!=lens["fov"],"Exported keyboard zoom changes the active photo lens")
	var original_actor: Variant=scene.player.global_position; var original_camera: Dictionary=runtime.view.duplicate(true); held(KEY_W,true); await settle(18); held(KEY_W,false)
	check(runtime.view["position"]!=original_camera["position"] and scene.player.global_position.is_equal_approx(original_actor),"Exported physical movement moves camera while retaining avatar position")
	ui.bookmarks.select(0); ui.recall(); check(runtime.view["position"]==Plan.settings(scene.live_data)["bookmarks"][0]["view"]["position"],"Export recalls the actual authored camera bookmark")
	var authored_view: Dictionary=Plan.settings(scene.live_data)["bookmarks"][0]["view"]
	check(is_equal_approx(scene.camera.zoom.y/scene.get_viewport().get_visible_rect().size.y,float(authored_view["zoom"][1])/float(authored_view["frame_height"])) if mode=="2d" else is_equal_approx(scene.camera.size,authored_view["size"]),"Bookmark preserves camera framing across editor and game viewport sizes")
	check((scene.camera.attributes is CameraAttributesPractical and scene.camera.attributes.dof_blur_far_enabled) if mode=="3d" else runtime.focus_layer.visible,"Authored focus settings reach actual exported render resources")
	ui.name_field.text="Local player camera"; ui.save_bookmark(); check(Plan.settings(ui.target()["data"])["bookmarks"].size()==2 and FileAccess.file_exists(store),"Export saves a named local bookmark into a separate persistent library")
	var previous_blur: float=Plan.settings(ui.target()["data"])["blur"]; ui.fields["blur"].value=.35; ui.storage_path=store+"/cannot-save.json"; ui.apply_settings()
	check(ui.dirty.has("blur") and is_equal_approx(Plan.settings(ui.target()["data"])["blur"],previous_blur),"Failed settings write retains pending edits and the previous local library")
	ui.storage_path=store; ui.apply_settings(); check(ui.dirty.is_empty() and is_equal_approx(Plan.settings(ui.target()["data"])["blur"],.35),"Retry saves pending camera settings after access is restored")
	var previous_bytes: PackedByteArray=FileAccess.get_file_as_bytes(store); var capacity: int=ui.max_library_bytes; ui.max_library_bytes=1; ui.fields["blur"].value=.45; ui.apply_settings()
	check(ui.dirty.has("blur") and runtime.notice.contains("full") and FileAccess.get_file_as_bytes(store)==previous_bytes,"Capacity rejection preserves pending edits and the readable library byte-for-byte")
	ui.max_library_bytes=capacity; ui.apply_settings(); check(ui.dirty.is_empty() and runtime.notice.is_empty(),"A capacity-rejected edit remains retryable without stale error feedback")
	ui.reload_store(); ui.refresh(); check(ui.bookmarks.item_count==2 and Plan.settings(scene.live_data)["bookmarks"].size()==1,"Reloading local library retains player bookmarks without modifying authored city")
	ui.name_field.grab_focus(); await settle(); check(not ui.can_input(),"Typing in exported photo controls blocks camera movement"); ui.release_focus()
	press(scene,KEY_F5); check(runtime.recording,"Actual exported F5 starts a timed camera recording")
	for frame in 8: runtime.navigate(.1,Vector3.RIGHT); runtime.advance(.1)
	ui.storage_path=store+"/cannot-save.json"; press(scene,KEY_F5)
	check(runtime.pending_take and Plan.settings(ui.target()["data"])["paths"].size()==1,"Failed camera-library write retains the unsaved take and existing paths")
	ui.storage_path=store
	if not runtime.pending_take: runtime.pending_take=true
	press(scene,KEY_F5); check(not runtime.recording and not runtime.pending_take and Plan.settings(ui.target()["data"])["paths"].size()==2,"Retry saves the retained take after the local folder becomes writable")
	ui.paths.select(1); ui.play(false); runtime.advance(.3); check(not runtime.playing.is_empty(),"Exported controls replay a saved local cinematic path"); runtime.playing=[]
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless":
		var hud:=CanvasLayer.new(); hud.name="TestPhotoGameHUD"; hud.layer=50; scene.add_child(hud); var banner:=ColorRect.new(); banner.color=Color.MAGENTA; banner.size=Vector2(96,48); hud.add_child(banner); await settle()
		var image_path: String="res://output/photo_export_"+mode+".png"; runtime.configure({"dof_enabled":false}); var result: Error=await runtime.screenshot(image_path); var frame: Image=Image.load_from_file(image_path)
		check(result==OK and frame and not frame.is_empty() and not frame.get_pixel(8,8).is_equal_approx(Color.MAGENTA),"Clean exported PNG excludes the actual gameplay HUD")
		check(ui.dialog.visible and hud.visible and runtime.active,"Screenshot restores native photo window, HUD and camera ownership"); hud.free()
	press(scene,KEY_P); check(not runtime.active and not ui.dialog.visible and scene.player.is_physics_processing(),"Exported P restores normal camera and avatar control")
	var host: Dictionary=scene.live_data["objects"].filter(func(item: Dictionary)->bool:return item.has("interior") and not item["interior"].get("floors",[]).is_empty())[0]
	scene.player.teleport_to(scene.exploration.entrance(scene.city_instances[host["uid"]])); press(scene,KEY_E); await settle(); scene.player.set_physics_process(false)
	check(scene.exploration.interior!=null,"Actual exported building entry opens room camera ownership")
	press(scene,KEY_P); ui.bookmarks.select(0); ui.recall(); var room_view: Dictionary=Plan.settings(ui.target()["data"])["bookmarks"][0]["view"]; var local: Variant=runtime.context()["world"].to_local(scene.camera.global_position)
	check((local.distance_to(Vector2(room_view["position"][0],room_view["position"][1])) if mode=="2d" else local.distance_to(Vector3(room_view["position"][0],room_view["position"][1],room_view["position"][2])))<.001 and ui.bookmarks.item_count==1,"Exported room recalls editor-authored floor-local view and independent library")
	var upper: String=scene.exploration.owned_room["floors"][0]["uid"]
	if mode=="2d": scene.exploration.interior.floor_stack.switch_floor(upper)
	else: scene.player.teleport_to(Vector3(2,3.05,3)); scene.exploration.interior.floor_stack.update_visibility()
	await settle(); check(not runtime.active and scene.exploration.active_floor()==upper,"Exported floor transition cancels the previous photo context")
	press(scene,KEY_P); ui.bookmarks.select(0); ui.recall(); room_view=Plan.settings(ui.target()["data"])["bookmarks"][0]["view"]; local=runtime.context()["world"].to_local(scene.camera.global_position)
	check((local.distance_to(Vector2(room_view["position"][0],room_view["position"][1])) if mode=="2d" else local.distance_to(Vector3(room_view["position"][0],room_view["position"][1],room_view["position"][2])))<.001,"Exported upstairs bookmark applies the actual floor-height transform")
	ui.stop(); scene.exploration.leave_interior(); check(scene.studio_data==before,"Photo authoring, playback, rooms and persistence leave exported source city unchanged")
	scene.free(); await process_frame
	var reopened: Node=packed.instantiate(); reopened.photo_storage_enabled=false; root.add_child(reopened); await settle(); reopened.photo_tools.storage_enabled=true; reopened.photo_tools.storage_path=store; reopened.photo_tools.reload_store(); press(reopened,KEY_P)
	check(reopened.photo_tools.bookmarks.item_count==2 and Plan.settings(reopened.photo_tools.target()["data"])["paths"].size()==2,"Fresh game instance reopens the saved local camera library")
	reopened.photo_tools.stop(); reopened.free(); await process_frame; print("PHOTO EXPORT: %d checks, %d failures"%[checks,failures]); quit(1 if failures else 0)
