extends SceneTree
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for i in 6: await process_frame
	await physics_frame
func click(studio: Control,at: Vector2) -> void:
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new(); event.button_index=MOUSE_BUTTON_LEFT; event.position=at; event.pressed=pressed
		studio._canvas_input(event)
func capture(name: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await settle(); await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://output/"+name+".png")
func target_point(studio: Control,uid: String) -> Vector2:
	var bounds: Rect2=studio.screen_bounds(uid)
	for x in 12:
		for y in 12:
			var point: Vector2=bounds.position+bounds.size*Vector2((x+.5)/12.0,(y+.5)/12.0)
			if studio.worlds[studio.mode].pick(point)==uid: return point
	return Vector2(-1,-1)
func run() -> void:
	root.size=Vector2i(1480,900)
	var studio: Control=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio); await settle()
	var guide: RefCounted=studio.first_build
	check(guide.phase==-2 and studio.workspace_layout.tabs.is_tab_hidden(guide.page.get_index()),"Closed guide has no effect on the initial editor layout")
	guide.restore_preferences({"seen":"yes","completed":7})
	check(not guide.seen and not guide.completed,"Malformed guide preferences retain safe defaults")
	guide.offer(); await settle()
	check(guide.phase==-1 and guide.seen and guide.page.is_visible_in_tree(),"First-use offer reveals the optional introduction")
	guide.close(); guide.offer()
	check(guide.phase==-2,"Dismissed first-use invitation does not repeatedly reopen")
	studio.workspace_presets.set_focus(true)
	var key:=InputEventKey.new(); key.keycode=KEY_F3; key.pressed=true; studio._input(key)
	check(guide.phase==-1,"F3 opens the introduction again")
	check(not studio.workspace_presets.focused and guide.page.is_visible_in_tree(),"Opening the guide exits canvas focus so its instructions are visible")
	await capture("editor_first_build_intro")
	guide.close()
	for mode in ["2d","3d"]:
		studio.switch_mode(mode)
		var doc: RefCounted=preload("res://scripts/builder/document.gd").new()
		doc.data=preload("res://scripts/builder/templates.gd").make(mode,"blank")
		var bench: String="2d:Park_Bench" if mode=="2d" else "3d:HanX_Park/Bench_Park"
		doc.add(bench,[-96,-96,0] if mode=="2d" else [-6,0,-6],"SE" if mode=="2d" else "0")
		studio.documents[mode]=doc; studio.clear_placement(); studio.worlds[mode].apply(doc.data); studio.worlds[mode].reset_camera("room")
		await settle()
		var original: Dictionary=doc.data.duplicate(true)
		var history: int=doc.undo_history.size()
		studio.rotation_controls.choice.select(1); studio.rotation_step.set_value_no_signal(45); studio.arrange_tools.pivot_mode.select(2)
		guide.show(); guide.begin(); await settle()
		check(studio.rotation_controls.choice.selected==0 and studio.rotation_step.value==90 and studio.arrange_tools.pivot_mode.selected==0,"Guide prepares a usable rotation mode and local pivot regardless of previous workspace settings: "+mode)
		check(doc.data==original and doc.undo_history.size()==history,"Starting the guide preserves the city and its history: "+mode)
		check(guide.phase==0 and studio.asset_id==bench and not studio.repeat_input.button_pressed,"Guide prepares a single bench without counting existing benches: "+mode)
		click(studio,studio.canvas.size/2+Vector2(45,35)); await settle()
		check(guide.phase==1 and not guide.uid.is_empty() and doc.data["objects"].size()==2,"Normal canvas placement advances the guide: "+mode)
		check(guide.page.is_visible_in_tree(),"Placement keeps the next guide instruction visible: "+mode)
		check(doc.undo_history.size()==history+1,"Guided placement uses normal undo history: "+mode)
		var uid: String=guide.uid
		guide.act(); guide.frame_bench(); await settle()
		check(guide.page.is_visible_in_tree(),"Guide tool buttons keep the current instruction visible: "+mode)
		var point: Vector2=target_point(studio,uid)
		check(point.x>=0,"Guide bench remains selectable through actual picking: "+mode)
		click(studio,point); await settle()
		check(guide.phase==2 and studio.selected_uids==[uid],"Normal selection advances to rotation: "+mode)
		var before_pose: Array=guide.pose(doc.object(uid))
		await capture("editor_first_build_select_"+mode)
		guide.act(); await settle()
		check(guide.phase==3 and guide.pose(doc.object(uid))!=before_pose,"Actual rotation advances to Undo: "+mode)
		guide.act(); await settle()
		check(guide.phase==4 and guide.pose(doc.object(uid))==before_pose,"Actual Undo restores the bench and advances to Save: "+mode)
		check(doc.data["objects"].size()==2,"Undo rotation retains both the original and new bench: "+mode)
		guide.act(); await settle()
		check(studio.file_dialog.visible and guide.phase==4,"Save step opens a real file picker without claiming success: "+mode)
		studio.file_dialog.hide(); await settle()
		check(guide.phase==4,"Cancelling Save does not advance the guide: "+mode)
		check(studio.write_project("res://output/first_build_background_"+mode+".json",false) and guide.phase==4,"Background/recovery saves do not satisfy the explicit Save task: "+mode)
		check(not studio.write_project("res://output/absent_first_build_directory/city.json") and guide.phase==4,"Failed saves do not advance the task: "+mode)
		var path: String="res://output/first_build_"+mode+".isocity.json"
		check(studio.write_project(path) and guide.phase==5 and guide.saved_path==path,"Successful project write advances to exploration: "+mode)
		var saved: Dictionary=studio.Store.read_json(path,{})
		check(saved["documents"][mode]["objects"].any(func(item: Dictionary): return item["uid"]==uid),"Saved project contains the actual tutorial bench: "+mode)
		var player: Node=studio.worlds[mode].player
		player.teleport_to(Vector2(200,200) if mode=="2d" else Vector3(20,.1,20))
		guide.act(); await settle()
		check(studio.walking and guide.phase==5 and guide.banner.is_visible_in_tree(),"Entering Walk shows a guide prompt and still requires movement: "+mode)
		check(guide.banner.size.y<100 and studio.canvas.size.y>260,"Walk guidance remains bounded and leaves room for exploration: %s (banner %s, canvas %s, window %s)" % [mode,guide.banner.size,studio.canvas.size,root.size])
		check(guide.banner_return.size.x>=130,"Guide's return button keeps its label visible in the flow layout: "+mode)
		studio.set_walking(false); await settle()
		check(guide.phase==5 and not guide.completed,"Returning before moving does not complete exploration: "+mode)
		guide.act(); await settle()
		player.set_physics_process(false)
		for i in 30:
			if mode=="2d": player.move_character(1.0/60.0,Vector2.RIGHT)
			else: player.move_character(1.0/60.0,Vector3.RIGHT)
			guide.tick()
		check(guide.phase==6 and studio.walking,"Real character movement advances to Return to Build: "+mode)
		await capture("editor_first_build_walk_"+mode)
		player.set_physics_process(true)
		guide.act(); await settle()
		check(guide.phase==7 and guide.completed and not studio.walking,"Returning from a completed walk finishes the task: "+mode)
		check(guide.page.is_visible_in_tree() and "complete" in guide.heading.text,"Completion is visible in the inspector: "+mode)
		await capture("editor_first_build_complete_"+mode)
		guide.close()
		check(doc.object(uid)!={} and not guide.banner.visible,"Closing the guide keeps completed edits and removes its prompt: "+mode)
		guide.completed=false
	guide.show(); guide.begin(); await settle()
	var guide_mode: String=studio.mode
	studio.switch_mode("2d" if guide_mode=="3d" else "3d"); await settle()
	check(guide.phase==0 and guide.heading.text=="Guide paused","Switching worlds pauses the correct task")
	guide.act(); await settle()
	check(studio.mode==guide_mode and guide.phase==0,"Return action resumes the original world and step")
	click(studio,studio.canvas.size/2); await settle()
	check(guide.phase==1,"Restart can use a new bench")
	studio._command("undo",null); await settle()
	check(guide.phase==0 and guide.uid.is_empty(),"Undoing placement returns to the Place step safely")
	guide.act(); click(studio,studio.canvas.size/2); await settle()
	var placed: String=guide.uid
	guide.begin(); await settle()
	check(guide.phase==0 and studio.current().object(placed)!={},"Restarting preserves the previous exercise's edits")
	guide.close()
	guide.settings_path="res://output/first_build_preferences_test.json"
	guide.seen=true; guide.completed=true; studio.storage_enabled=true; guide.persist(); studio.storage_enabled=false
	var prefs: Dictionary=studio.Store.read_json(guide.settings_path,{})
	guide.restore_preferences(prefs)
	check(guide.seen and guide.completed,"Completion preferences survive a real write/read round trip")
	guide.restore_preferences({}); guide.offer(); guide.begin(); await settle()
	check(studio.load_project("res://output/first_build_3d.isocity.json") and guide.phase==-2,"Loading another project closes the active task instead of crediting unrelated work")
	guide.show(); guide.begin(); await settle()
	root.size=Vector2i(960,640); await settle()
	check(studio.canvas.size.y>120 and guide.page.is_visible_in_tree(),"Guide and canvas remain usable at the minimum window size")
	await capture("editor_first_build_small")
	studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true})
	await settle()
	guide.show(); await settle()
	check(guide.primary.get_combined_minimum_size().y>=44 and guide.heading.get_theme_font_size("font_size")==27,"Guide inherits enlarged text and click targets")
	check(guide.page.get_global_rect().end.x<=root.size.x,"Enlarged guide is brought into view through the editor scroll area")
	await capture("editor_first_build_accessible")
	guide.close(); studio.queue_free(); await process_frame
	print("FIRST BUILD: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
