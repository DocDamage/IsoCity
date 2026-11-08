extends SceneTree

var checks: int = 0
var failures: int = 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; print("FAIL: " + message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for i in 6: await process_frame
func mouse_button(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	root.push_input(event,true)
func mouse_motion(position: Vector2, relative: Vector2 = Vector2.ZERO, held: bool = false) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	root.push_input(event,true)
func shown(tabs: TabContainer, title: String) -> bool:
	for i in tabs.get_tab_count():
		if tabs.get_tab_title(i) == title: return not tabs.is_tab_hidden(i)
	return false
func capture(name: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await settle()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://output/" + name + ".png")
func run() -> void:
	root.size = Vector2i(1480,900)
	var studio: Control = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	await settle()
	var layout: RefCounted = studio.workspace_layout
	studio.clear_placement()
	await settle()
	check(layout.advanced_toggle.get_global_rect().end.y <= layout.tabs.get_global_rect().position.y,"Advanced toggle occupies its own row above inspector tabs")
	check(studio.mode_library.size.x >= 220 and studio.mode_inspector.size.x >= 220 and studio.canvas.size.x > 500,"Both side panels and a usable canvas fit")
	check(not shown(layout.tabs,"Roads") and not shown(layout.tabs,"Colors") and not shown(layout.tabs,"Ground"),"Unrelated tool pages stay hidden during selection")
	check(not layout.advanced_toggle.button_pressed and not studio.pitch_input.is_visible_in_tree() and not studio.roll_input.is_visible_in_tree(),"Basic inspector hides pitch and roll")
	check(studio.height_input.is_visible_in_tree() and studio.scale_input.is_visible_in_tree() and studio.angle_input.is_visible_in_tree(),"Common transforms remain in Basic")
	await capture("editor_workspace_basic")
	var before: float = studio.canvas.size.x
	layout.library_toggle.button_pressed = false
	layout.inspector_toggle.button_pressed = false
	await settle()
	check(not studio.mode_library.visible and not studio.mode_inspector.visible and studio.canvas.size.x > before+400,"Collapsing both panels expands the canvas")
	check(layout.library_toggle.is_visible_in_tree() and layout.inspector_toggle.is_visible_in_tree(),"Panel reopen controls remain accessible")
	await capture("editor_workspace_collapsed")
	layout.library_toggle.button_pressed = true
	layout.inspector_toggle.button_pressed = true
	await settle()
	layout.library_split.split_offset += 70
	layout.inspector_split.split_offset -= 65
	await settle()
	layout.library_split.dragged.emit(layout.library_split.split_offset)
	layout.inspector_split.dragged.emit(layout.inspector_split.split_offset)
	await settle()
	check(studio.mode_library.size.x > 340 and studio.mode_inspector.size.x > 320,"Divider dragging changes both panel widths")
	var saved: Dictionary = layout.settings()
	check(absf(saved["library_width"]-studio.mode_library.size.x)<2 and absf(saved["inspector_width"]-studio.mode_inspector.size.x)<2,"Dragged widths are retained")
	var area: Control = layout.library_split.get_drag_area_controls()[0]
	var pointer: Vector2 = area.get_global_rect().get_center()
	var width_before: float = studio.mode_library.size.x
	mouse_motion(pointer)
	mouse_button(pointer,true)
	mouse_motion(pointer+Vector2(25,0),Vector2(25,0),true)
	await settle()
	mouse_button(pointer+Vector2(25,0),false)
	await settle()
	check(studio.mode_library.size.x>width_before+20 and absf(layout.library_width-studio.mode_library.size.x)<2,"Native mouse dragging resizes the library and persists its actual width")
	studio.set_tool("road")
	await settle()
	check(shown(layout.tabs,"Roads") and layout.tabs.get_tab_title(layout.tabs.current_tab)=="Roads","Road drawing reveals and opens road settings")
	check(studio.road_settings.width.is_visible_in_tree() and studio.road_settings.style.is_visible_in_tree(),"Road settings content remains visible inside its scroll page")
	check(not studio.surface_input.visible and not shown(layout.tabs,"Colors"),"Road drawing hides unrelated placement and color controls")
	await capture("editor_workspace_roads")
	studio.set_tool("color")
	await settle()
	check(shown(layout.tabs,"Colors") and shown(layout.tabs,"Appearance") and not shown(layout.tabs,"Roads") and layout.tabs.get_tab_title(layout.tabs.current_tab)=="Colors","Appearance editing reveals its controls and opens Colors")
	check(not studio.color_editor.tile_angle.is_visible_in_tree() and studio.color_editor.tile_size.is_visible_in_tree(),"Basic tile painting retains size while detailed mapping is collapsed")
	layout.mapping_toggle.button_pressed = true
	studio.color_editor.tile_angle.value = 27
	studio.color_editor.tile_x.value = 0.75
	await settle()
	check(layout.advanced_toggle.button_pressed and studio.color_editor.tile_angle.is_visible_in_tree() and studio.color_editor.tile_projection.is_visible_in_tree(),"Advanced mapping expands rotation, offsets and projection")
	if "--capture" in OS.get_cmdline_user_args():
		studio.color_editor.page.ensure_control_visible(studio.color_editor.tile_projection)
		await capture("editor_workspace_mapping")
	layout.advanced_toggle.button_pressed = false
	check(not studio.color_editor.tile_angle.is_visible_in_tree() and studio.color_editor.tile_angle.value==27 and studio.color_editor.tile_x.value==0.75,"Returning to Basic collapses mapping without resetting values")
	await capture("editor_workspace_colors")
	studio.select_asset("2d:Grass")
	await settle()
	check(shown(layout.tabs,"Ground") and studio.brush_input.visible,"Selecting ground reveals brush controls")
	check(studio.ground_brush.operation.is_visible_in_tree(),"Ground operation settings remain visible inside their scroll page")
	studio.clear_placement()
	check(not shown(layout.tabs,"Ground") and not studio.brush_input.visible,"Leaving ground placement hides brush controls")
	studio.selected_uid = studio.current().data["objects"][0]["uid"]
	studio.selected_uids.assign([studio.selected_uid])
	studio.refresh_controls()
	check(shown(layout.tabs,"Entrance"),"A selected building reveals entrance controls")
	layout.advanced_toggle.button_pressed = true
	layout.library_toggle.button_pressed = false
	studio.capture_workspace()
	var stored: Dictionary = studio.workspace[studio.mode]["layout"].duplicate(true)
	var project: Dictionary = studio.session_data()
	check(project["workspace"]["2d"]["layout"] == stored,"Project sessions contain panel and inspector preferences")
	var repair: RefCounted = preload("res://scripts/builder/project_repair.gd").new(studio.library)
	var damaged: Dictionary = {"2d":{"layout":{"library_width":900,"inspector_width":"bad","advanced":[],"library_open":false}}}
	var cleaned: Dictionary = repair.workspace(damaged)
	check(cleaned["2d"]["layout"].get("library_width")==600 and not cleaned["2d"]["layout"].has("inspector_width") and not cleaned["2d"]["layout"].has("advanced") and not cleaned["2d"]["layout"]["library_open"] and repair.issues.size()==3,"Project repair preserves valid layout settings and reports damaged ones")
	studio.switch_mode("3d")
	await settle()
	check(layout.library_open and not layout.advanced_toggle.button_pressed,"A new world starts with Basic and both panels open")
	studio.switch_mode("2d")
	await settle()
	check(not layout.library_open and layout.advanced_toggle.button_pressed and absf(layout.inspector_width-stored["inspector_width"])<2,"Each world restores its layout preferences")
	var project_path: String = "user://workspace_layout_test.isocity.json"
	check(studio.write_project(project_path),"Project saves with layout preferences")
	layout.restore({})
	check(studio.load_project(project_path),"Project with layout preferences reopens")
	await settle()
	check(not layout.library_open and layout.advanced_toggle.button_pressed and absf(layout.inspector_width-stored["inspector_width"])<2,"Actual project loading restores collapsed panels, widths and Advanced")
	studio.set_walking(true)
	await settle()
	check(not studio.mode_library.visible and not studio.mode_inspector.visible,"Walking hides both panels")
	studio.set_walking(false)
	await settle()
	check(not studio.mode_library.visible and studio.mode_inspector.visible,"Build return preserves explicit panel collapse preferences")
	layout.restore({"library_width":"bad","inspector_width":INF,"library_open":[],"advanced":"bad"})
	check(layout.library_width==296 and layout.inspector_width==280 and layout.library_open and not layout.advanced_toggle.button_pressed,"Malformed layout preferences have safe defaults")
	root.size = Vector2i(1024,720)
	await settle()
	check(studio.size.x<=1024 and studio.canvas.size.x>=240,"Small display retains a usable canvas without a forced wide window")
	studio.switch_mode("3d")
	studio.select_asset("2d:Grass")
	studio.ground_brush.enabled_input.button_pressed = false
	studio.refresh_controls()
	check(shown(layout.tabs,"Ground") and not studio.brush_input.visible,"Disabled ground brushing keeps its settings accessible for reenabling")
	studio.ground_brush.enabled_input.button_pressed = true
	check(studio.brush_input.visible,"Ground brushing can be reenabled from its page")
	studio.clear_placement()
	for title in ["Layers","Roads","Ground","Entrance"]:
		for page in layout.tabs.get_children():
			if page.name==title: check(page is ScrollContainer,"Long settings page scrolls on short windows: " + title)
	layout.library_toggle.button_pressed = false
	layout.inspector_toggle.button_pressed = false
	await settle()
	check(studio.canvas.size.x>900,"Small-display collapse prioritizes the canvas")
	await capture("editor_workspace_small")
	studio.free()
	print("WORKSPACE LAYOUT: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
