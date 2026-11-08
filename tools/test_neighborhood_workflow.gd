extends SceneTree
const Plan=preload("res://scripts/builder/neighborhood_plan.gd")
var studio: Control
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func ready(ui: RefCounted) -> void:
	for iteration in 60:
		if ui.pending.is_empty() or ui.preview_ready:return
		await physics_frame;await process_frame
func capture(mode: String,stage: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	for frame in 5: await process_frame
	RenderingServer.force_draw(false); RenderingServer.force_draw(false); root.get_texture().get_image().save_png("res://output/neighborhood_"+mode+"_"+stage+".png")
func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio)
	for frame in 5: await process_frame
	for mode in ["2d","3d"]:
		studio.switch_mode(mode); var doc: RefCounted=studio.current(); var ui: RefCounted=studio.neighborhood_tools; var world: Node=studio.worlds[mode]
		studio._command("neighborhood",null); var before: Dictionary=doc.data.duplicate(true); var history: int=doc.undo_history.size(); var nodes: Dictionary=world.instances.duplicate()
		check(ui.dialog.visible and studio.modal_visible(),"The neighborhood command opens a modal authoring dialog: "+mode)
		ui.generate();await ready(ui); check(not ui.pending.is_empty() and ui.pending["affordable"] and not ui.dialog.get_ok_button().disabled,"Default generation finds a clear site beside the existing city: "+mode)
		check(doc.data==before and doc.undo_history.size()==history and world.instances==nodes,"A rendered preview leaves city contents, geometry and history unchanged: "+mode)
		check(ui.preview_world.get_parent()==ui.viewport and ui.preview_world.player.is_physics_processing()==false and ui.preview_world.instances.size()>world.instances.size(),"Preview geometry and disabled actors live in an isolated viewport: "+mode)
		ui.seed_input.value=9981; check(ui.pending.is_empty() and ui.preview_world==null and ui.dialog.get_ok_button().disabled,"Changing generation fields invalidates the previous preview: "+mode)
		ui.generate(); ui.cancel(); check(not ui.dialog.visible and ui.preview_world==null and doc.data==before and doc.undo_history.size()==history,"Cancel frees preview geometry without touching the city or history: "+mode)
		ui.show(); ui.seed_input.value=19311; ui.density.value=65; ui.blocks.value=2; ui.pattern.select(1)
		for index in ui.theme.item_count:
			if ui.theme.get_item_metadata(index)==("historic" if mode=="2d" else "urban"): ui.theme.select(index)
		ui.generate(); var result: Dictionary=ui.pending; check(result.get("buildings",0)==11 and result.get("roads",0)==108,"Preview summaries report the chosen density and staggered road layout: "+mode)
		await capture(mode,"preview")
		ui.cancel(); var original_size: Vector2i=root.size; root.size=Vector2i(960,640); studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true,"shape_markers":true}); ui.show(); ui.generate(); await process_frame
		check(ui.dialog.size.x<=960 and ui.dialog.size.y<=640,"Scrollable generation controls fit the minimum viewport with enlarged text and targets: "+mode)
		await capture(mode,"accessible")
		ui.cancel(); studio.accessibility_settings.restore({}); root.size=original_size; ui.show(); ui.seed_input.value=19311; ui.density.value=65; ui.blocks.value=2; ui.pattern.select(1)
		for index in ui.theme.item_count:
			if ui.theme.get_item_metadata(index)==("historic" if mode=="2d" else "urban"): ui.theme.select(index)
		ui.generate();await ready(ui)
		ui.commit(); check(not ui.dialog.visible and ui.preview_world==null and doc.data["objects"].size()==before["objects"].size()+11 and doc.undo_history.size()==history+1,"Add commits ordinary city objects and roads as one Undo step: "+mode)
		check(studio.selected_uids.size()==11 and studio.dirty and Plan.valid_settings(doc.data["neighborhood_generator"]),"The generated buildings are selected, editable and marked for saving: "+mode)
		var authored: Dictionary=doc.data.duplicate(true); var new_uid: String=studio.selected_uid; var position: Array=doc.object(new_uid)["position"].duplicate()
		doc.checkpoint(); doc.object(new_uid)["position"][0]+=4; doc.finish_checkpoint(); studio.changed(); check(world.instances[new_uid].position!=world.position_for(position) if mode=="2d" else world.instances[new_uid].position.x!=position[0],"Generated buildings use ordinary incremental object editing: "+mode)
		studio._command("undo",null); check(doc.data==authored,"Undo restores an individually edited generated building: "+mode)
		studio._command("undo",null); check(doc.data==before and world.instances==nodes,"One more Undo removes the complete neighborhood and restores the original city: "+mode)
		studio._command("redo",null); check(doc.data==authored,"Redo restores the exact seed result, roads, ground and block groups: "+mode)
		await capture(mode,"city")
		var path: String="res://output/neighborhood_"+mode; check(studio.write_project(path+".isocity.json"),"The ordinary save command persists generated editable content: "+mode)
		var repair=preload("res://scripts/builder/project_repair.gd").new(studio.library); var loaded: Dictionary=repair.read(path+".isocity.json")
		check(loaded["ok"] and repair.issues.is_empty() and loaded["content"]["documents"][mode]["objects"].size()==authored["objects"].size() and Plan.valid_settings(loaded["content"]["documents"][mode]["neighborhood_generator"]),"Reopening retains generation settings and ordinary records without repair: "+mode)
		studio.show_file_dialog("export"); studio.file_dialog.hide(); studio._file_selected(path+".tscn"); studio._command("export_portable",null); studio.file_dialog.hide(); studio._file_selected(path+".zip")
		check(FileAccess.file_exists(path+".tscn") and FileAccess.file_exists(path+".zip"),"Actual scene and portable export actions accept generated cities: "+mode)
		ui.show(); ui.beside_city(); ui.generate();await ready(ui); var stale: Dictionary=doc.data.duplicate(true); doc.data["title"]="City changed during preview"; studio.changed(); ui.commit()
		check(ui.dialog.visible and ui.pending.is_empty() and ui.summary.text.contains("city changed") and doc.data["objects"]==stale["objects"],"A stale preview cannot overwrite intervening city changes: "+mode)
		ui.cancel(); doc.data["title"]=stale["title"]; studio.changed(); ui.show(); ui.origin_x.value=0; ui.origin_z.value=0; ui.generate()
		check(ui.pending.is_empty() and ui.dialog.get_ok_button().disabled and ui.summary.text.contains("existing"),"Occupied-site previews explain the conflict and disable committing: "+mode)
		ui.cancel(); var saved: Dictionary=doc.data.duplicate(true); doc.data["economy"]={"enabled":true,"starting_cash":1}; doc.data.erase("economy_account"); ui.show(); ui.beside_city(); ui.generate()
		check(not ui.pending.is_empty() and not ui.pending["affordable"] and ui.dialog.get_ok_button().disabled and ui.summary.text.contains("budget"),"Unaffordable previews explain the construction cost and cannot commit: "+mode)
		ui.cancel(); doc.data=saved; studio.changed(); ui.show(); ui.beside_city(); ui.generate(); studio.switch_mode("3d" if mode=="2d" else "2d")
		check(not ui.dialog.visible and ui.preview_world==null and ui.pending.is_empty(),"Changing dimensions releases preview state: "+mode)
		studio.switch_mode(mode); var host: Dictionary=doc.data["objects"].filter(func(item: Dictionary)->bool:return studio.library.assets[item["asset"]]["behavior"].get("building",false))[0]
		studio.interior_tools.start(host["uid"]); studio._command("neighborhood",null); check(not ui.dialog.visible and studio.status.text.contains("exterior city"),"Interior editors cannot generate city neighborhoods: "+mode); studio.interior_tools.leave()
	studio.free(); print("NEIGHBORHOOD WORKFLOW: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
