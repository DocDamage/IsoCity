extends SceneTree
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for i in 6: await process_frame
func capture(name: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await settle()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://output/"+name+".png")
func run() -> void:
	var studio: Control=load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled=false
	root.add_child(studio)
	await settle()
	var presets: RefCounted=studio.workspace_presets
	var layout: RefCounted=studio.workspace_layout
	for mode in ["2d","3d"]:
		studio.switch_mode(mode)
		studio.clear_placement()
		layout.restore({"library_open":false,"inspector_open":true,"library_width":390,"inspector_width":330,"advanced":true})
		studio.set_tool("select")
		var custom: Dictionary=layout.settings().duplicate(true)
		var before: Dictionary=studio.current().data.duplicate(true)
		var history: int=studio.current().undo_history.size()
		presets.apply_preset("building")
		await settle()
		check(not studio.walking and studio.tool=="select" and studio.mode_library.visible and studio.mode_inspector.visible,"Building shows editing panels in Build mode: "+mode)
		check(layout.library_width==320 and layout.inspector_width==280 and not layout.advanced_toggle.button_pressed,"Building uses its common-control layout: "+mode)
		presets.apply_preset("painting")
		await settle()
		check(studio.tool=="color" and not studio.mode_library.visible and studio.mode_inspector.visible and layout.inspector_width==360,"Painting gives the color inspector more room: "+mode)
		check(layout.tabs.get_tab_title(layout.tabs.current_tab)=="Colors","Painting opens color controls: "+mode)
		await capture("editor_workspace_painting_"+mode)
		presets.apply_preset("exploring")
		await settle()
		check(studio.walking and not studio.mode_library.visible and not studio.mode_inspector.visible,"Exploring enters Walk with an unobstructed canvas: "+mode)
		check(presets.walk_button.text=="Back to Build" and presets.choice.is_visible_in_tree(),"Exploring retains an obvious workspace and Build return: "+mode)
		await capture("editor_workspace_exploring_"+mode)
		studio.set_walking(false)
		await settle()
		check(presets.preset=="painting" and studio.tool=="color" and layout.inspector_width==360,"Returning from Exploring restores the previous painting workspace: "+mode)
		presets.apply_preset("custom")
		await settle()
		check(layout.settings()==custom,"Custom panel settings survive preset changes: "+mode)
		check(studio.current().data==before and studio.current().undo_history.size()==history,"Workspace presets do not edit the city or create undo entries: "+mode)
		presets.apply_preset("building")
		layout.advanced_toggle.button_pressed=true
		check(presets.preset=="custom","Manual layout changes become a Custom workspace: "+mode)
		await settle()
		var width: float=studio.canvas.size.x
		var height: float=studio.canvas.size.y
		var preferences: Dictionary=layout.settings().duplicate(true)
		presets.set_focus(true)
		await settle()
		check(not presets.header.visible and not presets.toolbar.visible and not studio.mode_library.visible and not studio.mode_inspector.visible,"Focus hides chrome and both side panels: "+mode)
		check(studio.canvas.size.x>width+400 and studio.canvas.size.y>height+80,"Focus maximizes canvas space in both axes: "+mode)
		check(studio.save_badge.is_visible_in_tree() and studio.status.is_visible_in_tree() and presets.focus_button.is_visible_in_tree(),"Focus keeps saved state, actions and its exit available: "+mode)
		check(studio.session_data()["workspace"][mode]["layout"]==preferences,"Saving in Focus preserves underlying panel preferences: "+mode)
		await capture("editor_workspace_focus_"+mode)
		var key:=InputEventKey.new()
		key.keycode=KEY_F10
		key.pressed=true
		studio._input(key)
		await settle()
		check(not presets.focused and presets.header.visible and layout.settings()==preferences,"F10 exits focus and restores the workspace: "+mode)
		check(studio.current().data==before,"Focus does not modify the document: "+mode)
		presets.apply_preset("painting")
		studio.capture_workspace()
		presets.set_focus(true)
		check(studio.write_project("user://workspace_presets_test.isocity.json"),"Project saves while focus is active: "+mode)
		presets.set_focus(false)
		presets.apply_preset("building")
		check(studio.load_project("user://workspace_presets_test.isocity.json"),"Project with workspace presets reopens: "+mode)
		await settle()
		check(presets.preset=="painting" and not presets.focused and studio.tool=="color" and layout.inspector_width==360,"Named presets persist, while Focus remains temporary: "+mode)
	# A saved Exploring layout retains the edit workspace it should return to.
	presets.apply_preset("building")
	presets.apply_preset("exploring")
	check(studio.write_project("user://workspace_exploring_test.isocity.json"),"Exploring layout saves")
	studio.set_walking(false)
	check(studio.load_project("user://workspace_exploring_test.isocity.json"),"Exploring layout reopens")
	await settle()
	check(presets.preset=="exploring" and studio.walking,"Saved Exploring preset resumes Walk mode")
	studio.set_walking(false)
	check(presets.preset=="building" and studio.tool=="select" and layout.library_open,"A restored Exploring preset returns to its saved edit layout")
	presets.restore({"preset":"unknown","custom":"bad","return_workspace":[]})
	check(presets.preset=="custom" and not presets.focused and not studio.walking,"Malformed preset preferences have safe defaults")
	var repair: RefCounted=preload("res://scripts/builder/project_repair.gd").new(studio.library)
	var damaged: Dictionary={"2d":{"custom":17,"preset":"my-theme","presets":{"preset":"unknown","custom":{"layout":{"library_width":0},"walking":"bad","tool":null},"return_workspace":[]}}}
	var repaired: Dictionary=repair.workspace(damaged)
	check(repair.issues.size()==5 and repaired["2d"]["presets"]["custom"]["layout"]["library_width"]==220,"Project repair reports malformed nested preset settings and bounds widths")
	check(repaired["2d"]["custom"]==17 and repaired["2d"]["preset"]=="my-theme","Preset validation preserves unrelated extension fields outside its namespace")
	root.size=Vector2i(960,640)
	await settle()
	presets.set_focus(true)
	await settle()
	check(studio.canvas.size.x>850 and studio.canvas.size.y>350 and presets.focus_button.is_visible_in_tree(),"Focus and its exit remain usable at the minimum window size")
	await capture("editor_workspace_focus_small")
	studio.free()
	print("WORKSPACE PRESETS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
