extends SceneTree
const Plan=preload("res://scripts/builder/weather_plan.gd")
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
func mix(frames: int=6) -> void:
	for frame in frames: studio.weather_tools.tick(1.0/60)
func capture(mode: String,stage: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	for frame in 5: await process_frame
	RenderingServer.force_draw(false); RenderingServer.force_draw(false); root.get_texture().get_image().save_png("res://output/weather_"+mode+"_"+stage+".png")
func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio); await settle()
	for mode in ["2d","3d"]:
		studio.switch_mode(mode); await settle()
		var ui: RefCounted=studio.weather_tools; var manager: Node=ui.managers[mode]; var doc: RefCounted=studio.current(); var world: Node=studio.worlds[mode]
		mix(); check(not manager.screen.visible and manager.foliage.entries.is_empty(),"Legacy project remains visually unchanged: "+mode)
		studio._command("weather",null); check(ui.page.is_visible_in_tree(),"Weather command opens the actual scrolling inspector: "+mode)
		var before: Dictionary=doc.data.duplicate(true); var count: int=doc.undo_history.size()
		ui.enabled.button_pressed=true; ui.condition.select(1); ui.season.select(2); ui.intensity.value=80; ui.wind.value=75; ui.direction.value=135; ui.seed.value=431; ui.affect_activity.button_pressed=true; ui.apply_settings(); mix()
		check(doc.undo_history.size()==count+1 and doc.data["weather"]["condition"]=="rain" and doc.data["weather"]["season"]=="autumn" and doc.data["weather"]["affect_activity"],"Weather controls create one normal project-history transaction: "+mode)
		check(manager.screen.visible and manager.screen.rain==.8 and manager.current_state["effective_season"]=="autumn","Studio exterior displays authored rain and autumn: "+mode)
		check(not manager.foliage.entries.is_empty(),"Catalogued real city trees receive seasonal visual effects: "+mode)
		var tree_uid: String=manager.foliage.entries.keys()[0]; var tree: Node=world.instances[tree_uid]; var transform: Variant=tree.transform
		var digest: String=studio.content_digest(); var history: int=doc.undo_history.size(); mix(120)
		check(studio.content_digest()==digest and doc.undo_history.size()==history and tree.transform==transform,"Animated weather does not edit city content, history or collision roots: "+mode)
		await capture(mode,"rain_autumn")
		studio._command("undo",null); mix(); check(doc.data==before and not manager.screen.visible and manager.foliage.entries.is_empty(),"Undo restores clear original visuals: "+mode)
		studio._command("redo",null); mix(); check(manager.screen.rain==.8 and doc.data["weather"]["seed"]==431,"Redo restores the saved weather configuration: "+mode)
		ui.refresh(); ui.condition.select(2); ui.season.select(3); ui.apply_settings(); mix(); await capture(mode,"snow_winter")
		check(manager.screen.snow==.8 and manager.screen.rain==0 and manager.current_state["effective_season"]=="winter","Snow and winter replace previous rain/autumn effects: "+mode)
		var host: Dictionary={}
		for item in doc.data["objects"]:
			if preload("res://scripts/builder/asset_behavior.gd").for_asset(item["asset"],studio.library).get("building",false): host=item; break
		check(not host.is_empty(),"Weather fixture includes an enterable building: "+mode)
		studio.interior_tools.start(host["uid"]); await settle(); mix()
		check(not manager.screen.visible and manager.foliage.entries.is_empty() and ui.apply_button.disabled,"Owned room editing suppresses exterior weather and protects city-level settings: "+mode)
		var root_doc: RefCounted=ui.root_document(); var outer: Dictionary=root_doc.data["weather"].duplicate(true); ui.condition.select(3); ui.apply_settings()
		check(root_doc.data["weather"]==outer,"Room editor cannot accidentally change outer city weather: "+mode)
		studio.interior_tools.leave(); await settle(); ui.refresh(); mix(); check(manager.screen.snow==.8,"Leaving the room restores exterior weather: "+mode)
		studio.set_walking(true); await settle(); mix(); check(manager.screen.visible,"Weather remains active during normal exterior Walk: "+mode)
		studio.set_walking(false)
		ui.refresh(); ui.condition.select(3); ui.cycle.button_pressed=true; ui.duration.value=30; ui.apply_settings(); mix()
		manager.elapsed=30; ui.tick(0); check(manager.current_state["effective_season"]=="spring" and manager.screen.gust==.8,"Season cycling advances winter into spring with visible wind: "+mode)
		await capture(mode,"wind_spring")
		var original_size: Vector2i=root.size; studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true,"shape_markers":true}); root.size=Vector2i(960,640); ui.show(); await settle()
		check(ui.panel.size.x<=ui.page.size.x+2 and ui.page.get_v_scroll_bar().max_value>ui.page.size.y,"Enlarged Weather controls fit and scroll at 960×640: "+mode)
		await capture(mode,"accessible"); root.size=original_size; studio.accessibility_settings.restore({}); await settle()
		var path: String="res://output/weather_"+mode; check(studio.write_project(path+".isocity.json"),"Normal project saving retains weather settings: "+mode)
		var repair=preload("res://scripts/builder/project_repair.gd").new(studio.library); var loaded: Dictionary=repair.read(path+".isocity.json")
		check(loaded["ok"] and repair.issues.is_empty() and loaded["content"]["documents"][mode]["weather"]["seed"]==431,"Reopening weather settings requires no repairs: "+mode)
		studio.show_file_dialog("export"); studio.file_dialog.hide(); studio._file_selected(path+".tscn"); studio._command("export_portable",null); studio.file_dialog.hide(); studio._file_selected(path+".zip")
		check(FileAccess.file_exists(path+".tscn") and FileAccess.file_exists(path+".zip"),"Both real export actions produce weather-enabled projects: "+mode)
		studio.switch_mode("3d" if mode=="2d" else "2d"); check(not manager.screen.visible and manager.foliage.entries.is_empty(),"Changing dimensions restores and releases old weather visuals: "+mode)
	studio.free(); await process_frame
	print("WEATHER WORKFLOW: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
