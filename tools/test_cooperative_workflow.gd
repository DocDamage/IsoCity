extends SceneTree
var checks: int=0
var failures: int=0
var host: Control
var guest: Control
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for frame in 6: await physics_frame
func wait_until(test: Callable) -> bool:
	for frame in 600:
		if test.call(): return true
		await process_frame
	return false
func place(studio: Control,uid: String,at: float) -> void:
	var doc: RefCounted=studio.current(); doc.checkpoint(); var item: Dictionary=doc.add("2d:Sedan_Blue",[at,0,0],"SE",1); item["uid"]=uid; doc.finish_checkpoint(); studio.changed()
func run() -> void:
	host=load("res://scenes/builder.tscn").instantiate(); host.storage_enabled=false; root.add_child(host); guest=load("res://scenes/builder.tscn").instantiate(); guest.storage_enabled=false; root.add_child(guest); await settle()
	for studio in [host,guest]:
		for mode in ["2d","3d"]: studio.documents[mode].data=preload("res://scripts/builder/templates.gd").make(mode,"blank")
		studio.changed()
	guest.current().data["title"]="Before joining"; guest.changed(); var original_id: String=guest.project_id
	var a: RefCounted=host.cooperative_tools; var b: RefCounted=guest.cooperative_tools
	host._command("cooperative",null); check(a.panel.is_visible_in_tree(),"Cooperative command opens the actual session controls")
	a.name_field.text="Host"; a.password.text="fixture-pass"; a.port.value=0; a.host_game(); b.name_field.text="Guest"; b.password.text="fixture-pass"; b.address.text="127.0.0.1"; b.port.value=a.session.server.get_local_port(); b.join_game()
	check(await wait_until(func():return b.participating and a.participating),"Actual Host/Join controls connect two editor instances")
	check(b.backup["2d"]["title"]=="Before joining" and guest.project_id!=original_id and guest.project_path.is_empty(),"Joining retains the pre-join city and separates shared-copy recovery identity")
	place(host,"host_car",100); place(guest,"guest_car",300)
	check(await wait_until(func():return host.current().data["objects"].size()==2 and guest.current().data["objects"].size()==2 and b.session.pending.is_empty() and not a.dirty and not b.dirty),"Ordinary document/history edits synchronize through the editor changed hook")
	check(host.current().data==guest.current().data and a.snapshot()==a.session.data and b.snapshot()==a.session.data,"Both visible editor documents converge to the accepted shared state")
	guest._command("undo",null); check(await wait_until(func():return host.current().data["objects"].size()==1 and guest.current().data["objects"].size()==1 and b.session.pending.is_empty()),"Normal Undo command routes to shared author history")
	guest._command("redo",null); check(await wait_until(func():return host.current().data["objects"].size()==2 and guest.current().data["objects"].size()==2 and b.session.pending.is_empty()),"Normal Redo command restores shared construction")
	for index in a.area_owner.item_count:
		if a.area_owner.get_item_metadata(index)==b.session.local_id: a.area_owner.select(index)
	a.area_name.text="Guest work area"; a.add_bounds(Rect2(-20,-20,40,40))
	check(await wait_until(func():return guest.current().data.get("protected_areas",[]).size()==1 and not a.dirty),"Host's area controls persist and share an editing assignment")
	place(guest,"permitted",0); check(await wait_until(func():return host.current().data["objects"].size()==3 and guest.current().data["objects"].size()==3 and not b.dirty and b.session.pending.is_empty()),"Assigned editor can build through the normal source transaction")
	a.selected=host.current().data["protected_areas"][0]["uid"]; a.area_owner.select(0); a.apply_area(); await wait_until(func():return guest.current().data["protected_areas"][0]["owner"]=="host")
	place(guest,"blocked",20); check(await wait_until(func():return b.failed_edit and b.session.pending.is_empty()),"Host rejects a normal editor change in an unassigned area")
	check(guest.current().object("blocked").is_empty() and host.current().object("blocked").is_empty() and not b.draft.is_empty(),"Rejected source edits roll back to accepted data and retain a draft")
	check(guest.status.text.contains("Co-op"),"Rejection feedback reaches the main action status")
	var before_areas: Array=host.current().data["protected_areas"].duplicate(true); b.add_center(); check(guest.current().data["protected_areas"]==before_areas,"Client cannot use area assignment controls")
	for mode in ["2d","3d"]:
		host.switch_mode(mode); guest.switch_mode(mode); await settle()
		var asset: String=""
		for id in host.library.assets:
			if id.begins_with(mode+":") and host.library.assets[id]["behavior"].get("building",false): asset=id; break
		var uid: String="shared_building_"+mode; var doc: RefCounted=host.current(); doc.checkpoint(); var building: Dictionary=doc.add(asset,[1400,200,0] if mode=="2d" else [50,0,0],str(host.library.directions(asset)[0]),1); building["uid"]=uid; doc.finish_checkpoint(); host.changed()
		check(await wait_until(func():return not guest.current().object(uid).is_empty() and not a.dirty),"Native building construction is shared: "+mode)
		host.interior_tools.start(uid); check(await wait_until(func():return guest.current().object(uid).has("interior") and not a.dirty),"Lazy owned-room creation is shared: "+mode)
		guest.interior_tools.start(uid); await settle(); check(host.interior_tools.editing() and guest.interior_tools.editing() and a.scope()==b.scope(),"Both editors can work in the same owned room: "+mode)
		place(guest,"room_piece_"+mode,10); check(await wait_until(func():return not host.current().object("room_piece_"+mode).is_empty() and not b.dirty and b.session.pending.is_empty()),"Room edits synchronize without closing the other editor's room: "+mode)
		check(host.interior_tools.editing() and guest.interior_tools.editing(),"Room scope survives remote source replacement: "+mode)
		guest.interior_tools.leave(); host.interior_tools.leave(); await settle()
		if mode=="3d":
			a.select_owner(b.session.local_id); a.area_name.text="3D district"; a.add_bounds(Rect2(-8,-8,16,16)); place(host,"preview_car_3d",4); await wait_until(func():return guest.current().data["protected_areas"].size()==1 and not a.dirty and not b.dirty)
		guest.control_settings.cursor_active=true; guest.control_settings.cursor_position=guest.canvas.size*.5; host.control_settings.cursor_active=true; host.control_settings.cursor_position=host.canvas.size*.5
		check(await wait_until(func():return is_instance_valid(a.cursor_root) and a.cursor_root.get_child_count()>0 and is_instance_valid(b.cursor_root) and b.cursor_root.get_child_count()>0),"Actual world cursor markers are visible to the other editor: "+mode)
		if "--capture" in OS.get_cmdline_user_args():
			RenderingServer.force_draw(false); RenderingServer.force_draw(false); host.worlds[mode].get_viewport().get_texture().get_image().save_png("res://output/cooperative_"+mode+".png")
			check(await host.worlds[mode].exploration.photo.screenshot("res://output/cooperative_clean_"+mode+".png")==OK,"Clean photo capture succeeds with live collaborative annotations: "+mode)
			check(a.cursor_root.visible,"Clean capture restores collaborator cursors: "+mode)
	await wait_until(func():return not a.dirty and not b.dirty and b.session.pending.is_empty())
	var queued_before: int=host.current().data["objects"].size(); place(guest,"queued_one",200); b.tick(.2); check(not b.session.pending.is_empty(),"First local edit enters an actual awaiting-acknowledgment state")
	place(guest,"queued_two",220); b.tick(.01)
	check(await wait_until(func():return host.current().data["objects"].size()==queued_before+2 and guest.current().data["objects"].size()==queued_before+2 and not b.dirty and b.session.pending.is_empty()),"A second edit made during an in-flight edit is retained and committed")
	var host_doc: RefCounted=host.current(); host_doc.checkpoint(); host_doc.object("queued_one")["position"]=[210,0,0]; host_doc.finish_checkpoint(); host.changed()
	var guest_doc: RefCounted=guest.current(); guest_doc.checkpoint(); guest_doc.object("queued_one")["position"]=[220,0,0]; guest_doc.finish_checkpoint(); guest.changed()
	check(await wait_until(func():return b.session.pending.is_empty() and not b.dirty and guest.current().object("queued_one")["position"][0]==210 and b.session.notice.contains("same field")),"Concurrent edits to the same field restore the accepted result with an explicit conflict")
	check(b.draft["3d"]["objects"].any(func(item: Dictionary):return item["uid"]=="queued_one" and item["position"][0]==220) and b.drafts.size()>=2,"Rejected intent survives a preceding remote update without replacing earlier recovery choices")
	var original_storage: String=guest.Store.storage_root; guest.Store.storage_root="res://output/cooperative_recovery"; guest.storage_enabled=true; var persistent: Dictionary=b.draft.duplicate(true); persistent["3d"]["title"]+=" · Recovery fixture"; b.keep_draft(persistent,"Stored conflict draft"); guest.storage_enabled=false
	check(not b.last_draft_path.is_empty() and FileAccess.file_exists(b.last_draft_path) and guest.Store.entries().any(func(value: Dictionary):return value["path"]==b.last_draft_path and value["project_id"]==guest.project_id),"Recovery-enabled drafts are saved under the shared copy's project identity")
	var draft_repair=preload("res://scripts/builder/project_repair.gd").new(guest.library); var reopened_draft: Dictionary=draft_repair.read(b.last_draft_path); check(reopened_draft["ok"] and draft_repair.issues.is_empty(),"A stored conflict draft reopens through ordinary project recovery")
	guest.Store.storage_root=original_storage
	guest.set_walking(true); await settle(); guest.set_walking(false); await settle(); check(b.session.connected,"Walk/Build transitions keep the editing session connected")
	var path: String="res://output/cooperative_city.isocity.json"; check(host.write_project(path),"Normal project saving retains protected areas")
	var repair=preload("res://scripts/builder/project_repair.gd").new(host.library); var saved: Dictionary=repair.read(path); check(saved["ok"] and repair.issues.is_empty(),"Protected shared city reopens without repairs")
	b.leave(); check(not b.session.connected and guest.current().data==a.session.data[guest.mode],"Leaving keeps the last accepted city")
	b.draft_choices.select(0); b.restore_draft(); check(guest.mode=="2d" and not guest.current().object("blocked").is_empty() and guest.project_path.is_empty(),"An earlier selected draft opens as an independent local project")
	b.restore_backup(); check(guest.current().data["title"]=="Before joining" and guest.project_id==original_id,"Pre-join city and project identity can be restored after leaving")
	a.leave()
	for mode in ["2d","3d"]:
		host.switch_mode(mode); await settle(); var export_path: String="res://output/cooperative_"+mode
		host.show_file_dialog("export"); host.file_dialog.hide(); host._file_selected(export_path+".tscn"); host._command("export_portable",null); host.file_dialog.hide(); host._file_selected(export_path+".zip")
		check(FileAccess.file_exists(export_path+".tscn") and FileAccess.file_exists(export_path+".zip"),"Scene and portable exports preserve the shared city's source: "+mode)
	guest.hide(); var size_before: Vector2i=root.size; root.size=Vector2i(960,640); host.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true}); a.show(); await settle()
	var action: Button
	for control in a.panel.find_children("*","Button",true,false):
		if control.text=="Apply area fields": action=control; break
	for frame in 20: await process_frame
	action.grab_focus(); await settle(); a.panel.ensure_control_visible(action); await settle()
	check(a.panel.get_v_scroll_bar().max_value>a.panel.size.y and action.get_global_rect().intersects(a.panel.get_global_rect()),"Keyboard focus scrolls protected-area actions into view with large text at 960×640")
	check(action.size.y>=44 and a.panel.get_child(0).size.x<=a.panel.size.x,"Co-op actions retain large click targets in the narrow inspector")
	if "--capture" in OS.get_cmdline_user_args():
		RenderingServer.force_draw(false); RenderingServer.force_draw(false); root.get_texture().get_image().save_png("res://output/cooperative_accessible.png")
	root.size=size_before; host.accessibility_settings.restore({}); host.free(); guest.free(); await process_frame; await process_frame
	print("Cooperative workflow: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
