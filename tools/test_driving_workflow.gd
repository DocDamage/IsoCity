extends SceneTree
const Plan=preload("res://scripts/builder/driving_plan.gd")
var studio: Control
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for frame in 6: await physics_frame
	await process_frame
func select(ids: Array) -> void:
	studio.selected_uids.assign(ids); studio.selected_uid=ids[-1] if not ids.is_empty() else ""; studio.driving_tools.stamp=0; studio.driving_tools.refresh()
func capture(mode: String,stage: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	for frame in 5: await process_frame
	RenderingServer.force_draw(false); RenderingServer.force_draw(false); root.get_texture().get_image().save_png("res://output/driving_workflow_"+mode+"_"+stage+".png")
func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio); await settle()
	for mode in ["2d","3d"]:
		studio.switch_mode(mode); var doc: RefCounted=studio.current(); doc.data=preload("res://scripts/builder/templates.gd").make(mode,"city"); studio.changed(); await settle()
		var cars: Array=doc.data["objects"].filter(func(item: Dictionary)->bool:return not Plan.profile(item).is_empty()); var first: Dictionary=cars[0]; var second: Dictionary=cars[1]; var ui: RefCounted=studio.driving_tools; var world: Node=studio.worlds[mode]; var runtime: Node=world.exploration.driving
		select([first["uid"]]); studio._command("driving",null); check(ui.page.is_visible_in_tree(),"Commands opens actual Driving inspector: "+mode)
		var history: int=doc.undo_history.size(); ui.fields["max_speed"].value=9; ui.apply_settings()
		check(first["driving"]["max_speed"]==9 and doc.undo_history.size()==history+1,"Inspector saves ordinary vehicle settings with one history transaction: "+mode)
		ui.apply_settings(); check(doc.undo_history.size()==history+1,"Unchanged Apply does not add history: "+mode)
		studio._command("undo",null); check(not doc.object(first["uid"]).has("driving"),"Undo restores automatic driving profile: "+mode); studio._command("redo",null); first=doc.object(first["uid"]); second=doc.object(second["uid"])
		second["driving"]={"max_speed":7,"reach":1.5}; studio.changed(); select([first["uid"],second["uid"]]); check(ui.caption.text.contains("differ"),"Mixed vehicle settings are identified: "+mode)
		ui.fields["braking"].value=12; ui.apply_settings(); check(first["driving"]["max_speed"]==9 and second["driving"]["max_speed"]==7 and second["driving"]["reach"]==1.5,"Changing one field preserves other mixed settings: "+mode)
		second["locked"]=true; select([first["uid"],second["uid"]]); ui.restore_selected(); check(not first.has("driving") and second.has("driving"),"Restore defaults respects protected selected vehicles: "+mode); second.erase("locked")
		select([first["uid"]]); ui.enabled.button_pressed=false; ui.apply_settings(); ui.preview_selected(); check(not studio.walking and studio.status.text.contains("Enable"),"Disabled vehicles cannot be started from inspector: "+mode)
		ui.enabled.button_pressed=true; ui.fields["max_speed"].value=8; ui.apply_settings(); ui.preview_selected(); await settle(); runtime.set_physics_process(false)
		check(studio.walking and not runtime.active.is_empty() and not world.player.visible,"Drive selected finds a clear approach and enters the actual vehicle: "+mode+" · "+studio.status.text+" · "+world.exploration.prompt()+" · "+str(world.player.global_position))
		var bindings: Dictionary=studio.control_settings.bindings.duplicate(true); var assigned: String=studio.control_settings.assign("interact",0,KEY_F9); var key:=InputEventKey.new(); key.keycode=KEY_F9; key.pressed=true
		check(assigned.is_empty() and studio.control_settings.unhandled(key) and runtime.active.is_empty(),"Remapped physical Interact exits the vehicle: "+mode)
		await settle(); studio.control_settings.unhandled(key); check(not runtime.active.is_empty() and studio.control_settings.walk_hint(world.exploration.prompt()).contains("F9"),"Remapped physical Interact re-enters parked vehicle and updates prompt: "+mode)
		if not runtime.active.is_empty():
			check(studio.control_settings.assign("move_up",0,KEY_F11).is_empty() and studio.control_settings.assign("jump",0,KEY_F12).is_empty(),"Drive movement and braking reuse remappable controls: "+mode)
			var start: Vector2=runtime.active["point"]; var movement:=InputEventKey.new(); movement.keycode=KEY_F11; movement.physical_keycode=KEY_F11; movement.pressed=true; runtime.set_physics_process(true); Input.parse_input_event(movement); await settle(); await settle(); movement.pressed=false; Input.parse_input_event(movement)
			check(runtime.active["point"].distance_to(start)>.01 and runtime.speed>0,"Actual remapped held input accelerates Studio vehicle: "+mode)
			var brake:=InputEventKey.new(); brake.keycode=KEY_F12; brake.physical_keycode=KEY_F12; brake.pressed=true; Input.parse_input_event(brake); await settle(); await settle(); brake.pressed=false; Input.parse_input_event(brake); runtime.set_physics_process(false)
			check(runtime.speed<.01 and studio.control_settings.walk_hint(world.exploration.prompt()).contains("F12 brakes"),"Remapped physical brake stops vehicle and appears in prompt: "+mode)
			await capture(mode,"city_drive")
		studio.control_settings.bindings=bindings; studio.control_settings.persist(); studio.set_walking(false); runtime.set_physics_process(true)
		select([first["uid"]]); var original_size: Vector2i=root.size; studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true}); root.size=Vector2i(960,640); ui.show(); await settle()
		check(ui.page.get_v_scroll_bar().max_value>ui.page.size.y,"Enlarged Driving inspector scrolls at 960×640: "+mode); ui.page.ensure_control_visible(ui.preview_button); studio.accessibility_settings.root_scroll.ensure_control_visible(ui.preview_button); ui.preview_button.grab_focus(); await settle()
		check(Rect2(Vector2.ZERO,Vector2(root.size)).has_point(ui.preview_button.get_global_rect().get_center()),"Keyboard focus reaches enlarged driving actions: "+mode); await capture(mode,"accessible_actions"); root.size=original_size; studio.accessibility_settings.restore({}); await settle()
		var path: String="res://output/driving_"+mode; check(studio.write_project(path+".isocity.json"),"Ordinary saving retains per-vehicle controls: "+mode)
		var repair=preload("res://scripts/builder/project_repair.gd").new(studio.library); var reopened: Dictionary=repair.read(path+".isocity.json"); check(reopened["ok"] and repair.issues.is_empty(),"Saved driving project reopens without repair: "+mode)
		first["driving"]={"max_speed":-1,"reach":2,"future_field":42}; var fixed: Dictionary=repair.world(doc.data,mode,"city",0)
		var restored: Dictionary=fixed["objects"].filter(func(item: Dictionary)->bool:return item["uid"]==first["uid"])[0]
		check(not restored["driving"]["enabled"] and restored["driving"]["reach"]==2 and restored["driving"]["future_field"]==42 and not repair.issues.is_empty(),"Repair disables unsafe controls and retains readable/future settings: "+mode); first["driving"]={"enabled":true,"max_speed":8}; studio.changed()
		studio.show_file_dialog("export"); studio.file_dialog.hide(); studio._file_selected(path+".tscn"); studio._command("export_portable",null); studio.file_dialog.hide(); studio._file_selected(path+".zip")
		check(FileAccess.file_exists(path+".tscn") and FileAccess.file_exists(path+".zip"),"Both actual export actions package driveable cities: "+mode)
	studio.free(); await process_frame; print("DRIVING WORKFLOW: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
