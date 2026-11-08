extends SceneTree
const Plan=preload("res://scripts/builder/photo_plan.gd")
var studio: Control
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for frame in 5: await physics_frame
	await process_frame
func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio); await settle()
	for mode in ["2d","3d"]:
		studio.switch_mode(mode); var doc: RefCounted=studio.current(); var world: Node=studio.worlds[mode]; var runtime: Node=world.exploration.photo; var ui: RefCounted=studio.photo_tools
		var before_objects: Array=doc.data["objects"].duplicate(true); var history: int=doc.undo_history.size(); studio._command("photo",null); await settle()
		check(ui.dialog.visible and runtime.active and studio.mode_badge.text.begins_with("PHOTO MODE"),"Actual command opens photo controls and persistent mode badge: "+mode)
		var lens: Dictionary=runtime.view.duplicate(true); var zoom_key:=InputEventKey.new(); zoom_key.keycode=KEY_EQUAL; zoom_key.pressed=true; ui.window_input(zoom_key)
		check(runtime.view["zoom"]!=lens["zoom"] if mode=="2d" else runtime.view["size"]!=lens["size"],"Photo-window keyboard zoom updates the active photo lens: "+mode)
		if mode=="3d":
			var angle: Array=runtime.view["rotation"].duplicate(); var turn:=InputEventKey.new(); turn.keycode=KEY_BRACKETLEFT; turn.pressed=true; ui.window_input(turn); check(runtime.view["rotation"]!=angle,"Photo-window keyboard look updates camera orientation")
		ui.dof.button_pressed=true; ui.fields["blur"].value=.6; ui.apply_settings()
		check(doc.undo_history.size()==history+1 and doc.data["photo"]["dof_enabled"] and is_equal_approx(doc.data["photo"]["blur"],.6),"Applying camera controls creates one ordinary history transaction: "+mode)
		ui.apply_settings(); check(doc.undo_history.size()==history+1,"Unchanged camera settings do not add history: "+mode)
		studio._command("undo",null); ui.tick(.2); check(not doc.data.has("photo") and not runtime.config["dof_enabled"],"Undo restores persisted and preview focus settings: "+mode); studio._command("redo",null); ui.tick(.2)
		ui.name_field.text="Street camera"; ui.save_bookmark(); check(doc.data["photo"]["bookmarks"].size()==1 and ui.bookmarks.item_count==1,"Save bookmark persists the actual camera view in this city: "+mode)
		var bookmarked: Dictionary=doc.data["photo"]["bookmarks"][0]["view"].duplicate(true); runtime.navigate(.1,Vector3.RIGHT); ui.bookmarks.select(0); ui.recall(); check(runtime.view["position"]==bookmarked["position"],"Recall restores the selected saved camera: "+mode)
		ui.name_field.grab_focus(); await settle(); check(studio.control_settings.text_focused() and not ui.can_input(),"Typing into the photo window does not move the camera or run editor shortcuts: "+mode); ui.release_focus()
		ui.name_field.text="Street pass"; ui.record_toggle()
		for frame in 8: runtime.navigate(.1,Vector3.RIGHT); runtime.advance(.1)
		ui.record_toggle(); check(doc.data["photo"]["paths"].size()==1 and Plan.entry_valid(doc.data["photo"]["paths"][0],mode,true),"Stop and save stores a valid timed camera take: "+mode)
		ui.paths.select(0); ui.play(false); runtime.advance(.4); check(not runtime.playing.is_empty(),"Actual path control starts cinematic playback: "+mode); runtime.playing=[]
		var bindings: Dictionary=studio.control_settings.bindings.duplicate(true); check(studio.control_settings.assign("photo",0,KEY_F11).is_empty(),"Photo mode shortcut can be remapped: "+mode)
		var key:=InputEventKey.new(); key.keycode=KEY_F11; key.pressed=true; check(studio.control_settings.input(key) and not runtime.active and not ui.dialog.visible,"Actual remapped shortcut returns to normal camera: "+mode); studio.control_settings.input(key); check(runtime.active and ui.dialog.visible,"Actual remapped shortcut reopens photo mode: "+mode); studio.control_settings.bindings=bindings; studio.control_settings.persist(); ui.stop()
		var host: Dictionary=doc.data["objects"].filter(func(item: Dictionary)->bool:return studio.library.assets[item["asset"]]["behavior"].get("building",false))[0]; studio.interior_tools.start(host["uid"]); await settle(); ui.show(); ui.name_field.text="Room camera"; ui.save_bookmark(); var room: RefCounted=studio.current()
		check(room.data["photo"]["bookmarks"].size()==1 and doc.data["photo"]["bookmarks"].size()==1 and runtime.scope.begins_with("room:"),"Room-editor bookmarks use their own authored location: "+mode); ui.stop()
		var floors: RefCounted=studio.interior_tools.floor_tools; floors.new_name.text="Camera loft"; floors.new_height.value=3; floors.add_floor(); await settle(); ui.show(); ui.name_field.text="Upstairs camera"; ui.save_bookmark(); var upper: String=studio.current().floor_uid
		check(upper!="ground" and studio.current().data["photo"]["bookmarks"].size()==1 and runtime.scope.ends_with(":"+upper+":"),"Upper floors retain separate camera libraries and scope: "+mode)
		ui.stop(); studio._command("undo",null); check(not studio.current().data.has("photo"),"Shared room history undoes the upstairs camera edit: "+mode); studio._command("redo",null); studio.interior_tools.leave(); await settle()
		check(doc.data["objects"].size()==before_objects.size() and doc.data["photo"]["paths"].size()==1,"Room camera authoring preserves the exterior camera take and object collection: "+mode)
		var owned: Dictionary=doc.object(host["uid"])["interior"]; owned["floor_links"]=[{"uid":"photo_stairs","kind":"stairs","lower":"ground","upper":upper,"start":[-3,3],"end":[2,3],"width":1.4}]; studio.changed(); await settle()
		studio.set_walking(true); world.player.teleport_to(world.exploration.entrance(world.instances[host["uid"]])); studio.control_settings.execute("interact"); await settle(); world.player.set_physics_process(false)
		check(world.exploration.interior!=null,"Normal building entry opens connected camera ownership: "+mode); ui.show(); ui.bookmarks.select(0); ui.recall()
		var local: Variant=runtime.context()["world"].to_local(world.camera.global_position); var camera_values: Array=ui.selected(ui.bookmarks,"bookmarks")["view"]["position"]
		check((local.distance_to(Vector2(camera_values[0],camera_values[1])) if mode=="2d" else local.distance_to(Vector3(camera_values[0],camera_values[1],camera_values[2])))<.001,"Room-editor bookmark recalls the same floor-local view during connected Walk: "+mode)
		runtime.start_recording(); runtime.advance(.2)
		if mode=="2d": world.exploration.interior.floor_stack.switch_floor(upper)
		else: world.player.teleport_to(Vector3(2,3.05,3)); world.exploration.interior.floor_stack.update_visibility()
		await settle(); check(not runtime.active and runtime.pending_take and world.exploration.active_floor()==upper,"Floor transition stops photo ownership and retains the unsaved take: "+mode)
		ui.record_toggle(); check(not studio.photo_tools.target()["data"].get("photo",{}).has("paths") and ui.status.text.contains("recorded location"),"A take cannot be saved into a different floor: "+mode); runtime.pending_take=false; runtime.recorded=[]
		ui.show(); ui.bookmarks.select(0); ui.recall(); local=runtime.context()["world"].to_local(world.camera.global_position); camera_values=ui.selected(ui.bookmarks,"bookmarks")["view"]["position"]
		check((local.distance_to(Vector2(camera_values[0],camera_values[1])) if mode=="2d" else local.distance_to(Vector3(camera_values[0],camera_values[1],camera_values[2])))<.001 and runtime.scope.ends_with(":"+upper+":"),"Upstairs bookmark includes the actual connected floor transform: "+mode)
		ui.stop(); world.exploration.leave_interior(); studio.set_walking(false); await settle()
		ui.show(); var original_size: Vector2i=root.size; studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true}); root.size=Vector2i(960,640); ui.show(); await settle(); ui.scroll.ensure_control_visible(ui.record_button); ui.record_button.grab_focus(); await settle()
		check(ui.dialog.size.y<=root.size.y and ui.scroll.get_v_scroll_bar().max_value>ui.scroll.size.y and ui.record_button.get_global_rect().intersects(Rect2(Vector2.ZERO,Vector2(ui.dialog.size))),"Enlarged photo controls scroll and keep focused actions reachable at 960×640: "+mode)
		if "--capture" in OS.get_cmdline_user_args():
			RenderingServer.force_draw(false); RenderingServer.force_draw(false); ui.dialog.get_texture().get_image().save_png("res://output/photo_workflow_"+mode+"_controls.png")
		ui.stop(); root.size=original_size; studio.accessibility_settings.restore({}); await settle()
		var path: String="res://output/photo_"+mode; check(studio.write_project(path+".isocity.json"),"Ordinary saving retains camera libraries: "+mode); var repair=preload("res://scripts/builder/project_repair.gd").new(studio.library); var reopened: Dictionary=repair.read(path+".isocity.json"); check(reopened["ok"] and repair.issues.is_empty(),"Camera bookmarks and takes reopen without repair: "+mode)
		studio.show_file_dialog("export"); studio.file_dialog.hide(); studio._file_selected(path+".tscn"); studio._command("export_portable",null); studio.file_dialog.hide(); studio._file_selected(path+".zip")
		check(FileAccess.file_exists(path+".tscn") and FileAccess.file_exists(path+".zip"),"Actual export actions package camera libraries and focus dependencies: "+mode)
	studio.free(); await process_frame; print("PHOTO WORKFLOW: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
