extends "res://tools/test_resident_activity_plan.gd"
func select(studio: Control,uid: String) -> void:
	studio.selected_uid=uid;studio.selected_uids.assign([uid]);studio.refresh_controls()
func find_issue(ui: RefCounted,code: String,uid: String) -> int:
	for index in ui.results.item_count:
		var row: Dictionary=ui.results.get_item_metadata(index)
		if row["code"]==code and row["object_uid"]==uid:return index
	return -1
func command(studio: Control) -> void:
	studio.command_palette.show();studio.command_palette.query.text="interaction setup diagnostics";studio.command_palette.refresh();studio.command_palette.execute();await settle()
func key(code: Key) -> void:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=true;Input.parse_input_event(event);await process_frame;event=event.duplicate();event.pressed=false;Input.parse_input_event(event);await settle()
func run() -> void:
	var studio: Control=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio);await settle()
	if studio.consumer_shell:studio.consumer_shell.dismiss_welcome()
	var ui: RefCounted=studio.prop_tools.setup;var initial: Vector2i=root.size
	for mode in ["2d","3d"]:
		studio.switch_mode(mode);var doc:=Docs.new();doc.data=Templates.make(mode,"blank");studio.documents[mode]=doc
		var host: Dictionary=doc.add("3d:HanX_School/School_Building",[112,-32,0] if mode=="2d" else [7,0,-2],"0",.25);host["uid"]="school"
		var room: Dictionary=preload("res://scripts/builder/interiors.gd").make(mode,"Setup classroom");room["objects"]=[];var upstairs:=Docs.new();upstairs.data=room.duplicate(true)
		var chair: Dictionary=upstairs.add("3d:HanX_School/Student_Chair",[0,-32,0] if mode=="2d" else [-2,.12,-2],"0");chair["uid"]="chair"
		room["floors"]=[{"uid":"upper","name":"Classroom","height":3,"room":upstairs.data}];room["floor_links"]=[];host["interior"]=room;studio.changed();await settle();select(studio,"school")
		var world: Node=studio.worlds[mode];var authored: Dictionary=doc.data.duplicate(true);var history: int=doc.undo_history.size();var children: int=world.get_child_count()
		for dimensions in [Vector2i(1480,900),Vector2i(960,640)]:
			root.size=dimensions;studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true} if dimensions.x==960 else {});await settle();await command(studio)
			var label: String=mode+" "+str(dimensions.x);var index: int=find_issue(ui,"return_route","chair")
			check(index>=0 and ui.panel.is_visible_in_tree() and ui.results.has_focus(),"Actual palette command opens and focuses the checklist: "+label)
			check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(ui.results.get_global_rect()),"Focused checklist fits the actual window: "+label+" "+str(ui.results.get_global_rect()))
			if index<0:continue
			ui.results.select(index);ui.results.item_selected.emit(index);await settle()
			var framed: bool=world.camera.position.is_equal_approx(Vector2(112,-32)) if mode=="2d" else world.target.is_equal_approx(Vector3(7,0,-2))
			check(framed and not studio.interior_tools.editing() and ui.detail.text.contains("Classroom") and ui.detail.text.contains("Return route"),"Selecting a finding frames the host and explains its exact unvisited floor: "+label)
			check(world.get_child_count()==children and doc.data==authored and doc.undo_history.size()==history,"Read-only checking and framing create no room, history or authored changes: "+label)
			check(ui.results.get_item_text(index).begins_with("Return route"),"Compact issue labels expose the cause before the object name: "+label)
			if "--capture" in OS.get_cmdline_user_args():
				RenderingServer.force_draw(false);RenderingServer.force_draw(false)
				var shell: String="simple" if studio.consumer_shell and studio.consumer_shell.active else "precision"
				check(root.get_texture().get_image().save_png("res://output/verification/asset_expansion/U12/setup_%s_%s_%d.png"%[mode,shell,dimensions.x])==OK,"Captured the actual setup checklist: "+label)
		await key(KEY_TAB)
		check(ui.detail.has_focus() and Rect2(Vector2.ZERO,Vector2(root.size)).encloses(ui.detail.get_global_rect()) and ui.page.get_global_rect().encloses(ui.detail.get_global_rect()) and not studio.walking,"Tab reveals the complete wrapped issue without starting Walk: "+mode)
		if studio.consumer_shell and studio.consumer_shell.active:
			studio.status.text="Setup is read-only. Existing furnishings and undo are preserved.";await settle()
			check(studio.consumer_shell.notice.is_visible_in_tree() and not studio.consumer_shell.notice.get_global_rect().intersects(ui.detail.get_global_rect()),"Simple status notice leaves the full focused diagnostic readable: "+mode)
		if "--capture" in OS.get_cmdline_user_args():
			RenderingServer.force_draw(false);RenderingServer.force_draw(false)
			var shell: String="simple" if studio.consumer_shell and studio.consumer_shell.active else "precision"
			check(root.get_texture().get_image().save_png("res://output/verification/asset_expansion/U12/setup_%s_%s_detail.png"%[mode,shell])==OK,"Captured focused full issue text: "+mode)
		var index: int=find_issue(ui,"return_route","chair")
		if index<0:continue
		var old: Dictionary=ui.results.get_item_metadata(index)
		var old_asset: String=studio.asset_id;var old_direction: String=studio.direction
		studio.asset_id=studio.library.assets.keys().filter(func(id: String):return studio.library.is_ground_tile(id))[0];studio.direction="SE" if studio.asset_id.begins_with("2d:") else "0"
		studio.ground_brush.operation.select(1);studio.ground_brush.begin(Vector2(160,120));var start: Vector2i=studio.ground_brush.start;var canvas_position: Variant=world.camera.position if mode=="2d" else world.target
		ui.results.select(index);ui.inspect_button.pressed.emit();studio._command("interaction_setup",null)
		check(studio.ground_brush.drawing and studio.ground_brush.start==start and not studio.interior_tools.editing() and (world.camera.position if mode=="2d" else world.target)==canvas_position,"Issue actions leave the actual active area gesture and camera untouched: "+mode)
		studio.ground_brush.drawing=false;studio.asset_id=old_asset;studio.direction=old_direction
		ui.results.grab_focus();await key(KEY_ENTER)
		check(studio.interior_tools.editing() and studio.interior_tools.uid=="school" and studio.current().floor_uid=="upper" and studio.selected_uid=="chair","Keyboard activation explicitly opens the saved floor and frames its fixture: "+mode)
		if studio.interior_tools.editing():studio.interior_tools.leave()
		await settle();select(studio,"school");await command(studio)
		check(doc.data==authored and doc.undo_history.size()==history and studio.mode==mode,"Explicit room inspection preserves source/history and never switches dimension: "+mode)
		old=ui.results.get_item_metadata(find_issue(ui,"return_route","chair"))
		doc.checkpoint();doc.object("school")["interior"]["floor_links"]=[{"uid":"stairs","kind":"stairs","lower":"ground","upper":"upper","start":[0,0],"end":[0,6],"width":1.2}];studio.changed()
		check(not ui.focus_record(old,true) and not studio.interior_tools.editing() and ui.detail.text.contains("changed"),"Stale issue cannot open a scope after the source has changed: "+mode)
		await settle();ui.show_passed.button_pressed=true;ui.refresh();var fixed: int=find_issue(ui,"return_route","chair")
		check(fixed>=0 and ui.results.get_item_metadata(fixed)["severity"]=="ok","Retry uses the actual repaired floor route: "+mode)
		studio._command("undo",null);await settle();select(studio,"school");await command(studio);var undone: int=find_issue(ui,"return_route","chair")
		check(undone>=0 and ui.results.get_item_metadata(undone)["severity"]=="error" and doc.data==authored,"Undo restores the real setup issue and exact authored source: "+mode)
		ui.show_passed.button_pressed=false
		var path: String="res://output/verification/asset_expansion/U12/setup_"+mode+".isocity.json"
		check(studio.write_project(path,false) and studio.load_project(path),"Actual save and reopen preserve the authored setup: "+mode);await settle()
		var reopened: Dictionary=studio.current().data
		check(JSON.parse_string(JSON.stringify(reopened))==JSON.parse_string(JSON.stringify(authored)) and not JSON.stringify(reopened).contains("message_key"),"Reopened source excludes checklist results and transient state: "+mode)
	root.size=initial;studio.free();await settle();print("INTERACTION SETUP WORKFLOW: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
