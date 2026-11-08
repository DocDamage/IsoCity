extends SceneTree
const OUT="res://output/verification/asset_expansion/U10/"
const Economy=preload("res://scripts/builder/economy_plan.gd")
var studio: Control
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func settle() -> void:
	for frame in 16:await process_frame
func ready(tools: RefCounted) -> void:
	for frame in 900:
		if tools.proposal.has("ok") and (not tools.proposal["ok"] or tools.proposal.get("geometry_checked",false)):return
		await process_frame
	check(false,"Actual companion review completes within its bound")
func click(at: Vector2) -> void:
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=at;studio._canvas_input(event);await process_frame
func key(code: Key) -> void:
	for pressed in [true,false]:
		var event:=InputEventKey.new();event.keycode=code;event.pressed=pressed;Input.parse_input_event(event);await process_frame
func select(uid: String) -> void:studio.selected_uid=uid;studio.selected_uids.assign([uid]);studio.refresh_controls()
func capture(name: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args():return
	await settle();await RenderingServer.frame_post_draw;check(root.get_texture().get_image().save_png(OUT+name+".png")==OK,"Actual companion workflow capture: "+name)
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT);FileAccess.open(OUT+".gdignore",FileAccess.WRITE).close()
	studio=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio);await settle();await settle();studio.consumer_shell.dismiss_welcome();var tools: RefCounted=studio.companion_tools
	for mode in ["2d","3d"]:
		studio.switch_mode(mode);var doc:=preload("res://scripts/builder/document.gd").new();doc.data=preload("res://scripts/builder/templates.gd").make(mode,"blank");studio.documents[mode]=doc;studio.changed();studio.worlds[mode].reset_camera("blank");await settle()
		var before: Dictionary=doc.data.duplicate(true);var history: int=doc.undo_history.size();studio.select_asset("3d:HanX_School/Student_Desk");await settle()
		check(tools.panel.is_visible_in_tree() and doc.data==before and doc.undo_history.size()==history,"Selecting a reviewed source opens only an optional read-only tray: "+mode)
		for button in tools.panel.find_children("*","Button",true,false):
			if button.accessibility_name=="Dismiss companion suggestions":button.pressed.emit()
		await settle();check(not tools.panel.visible and doc.data==before,"Dismiss stays respected for the current selection")
		studio.select_asset("3d:HanX_School/Student_Desk");await settle();tools.together.pressed.emit();await settle()
		check(not tools.floating.is_empty() and studio.assembly_active.get("companion",false) and studio.assembly_ghosts.size()==2 and doc.data==before and doc.undo_history.size()==history,"Place together creates actual assembly ghosts without spawning or history")
		studio.rotate_by(1);check(tools.floating["draft"]["direction"]=="90" and doc.data==before,"Ordinary rotate changes only the floating complete set");studio.rotate_by(-1)
		await click(studio.canvas.size*.5);await ready(tools)
		check(tools.dialog.visible and studio.modal_visible() and tools.proposal.get("geometry_checked",false) and not tools.dialog.get_ok_button().disabled,"Actual canvas click opens a clear priced assembly review")
		check(doc.data==before and doc.undo_history.size()==history,"Entering review intercepts the canvas before any authoring checkpoint")
		await capture("create_"+mode);tools.dialog.get_cancel_button().grab_focus();await key(KEY_ESCAPE);await settle()
		check(not tools.dialog.visible and not tools.floating.is_empty() and doc.data==before and doc.undo_history.size()==history and not is_instance_valid(tools.preview.viewport),"Cancel returns to floating placement and releases the private world without editing")
		await click(studio.canvas.size*.5);await ready(tools);tools.dialog.get_ok_button().grab_focus();await key(KEY_ENTER);await settle()
		check(doc.data["objects"].size()==2 and doc.undo_history.size()==history+1 and not tools.dialog.visible and studio.assembly_active.is_empty(),"Keyboard Apply creates the entire reviewed pair in one completed history step")
		var applied: Dictionary=doc.data.duplicate(true);var uid: String=doc.data["objects"][0]["uid"]
		check(doc.data["objects"][0]["group"]==doc.data["objects"][1]["group"] and not uid.begins_with("preview_"),"A new set saves fresh concrete identities in one editable group")
		studio._command("undo",null);await settle();check(doc.data==before,"One normal Undo removes the complete new set")
		studio._command("redo",null);await settle();check(doc.data==applied,"Redo restores the same source, companion and group identities")
		studio._command("ungroup",null);select(uid);doc.checkpoint();var source: Dictionary=doc.object(uid);source["name"]="My modified desk";source["custom_extension"]={"keep":true};source["scale"]=1.5;source["direction"]="90";source["position"]=[110,48,0] if mode=="2d" else [2,0,2];studio.changed();doc.finish_checkpoint();await settle()
		var customized: Dictionary=doc.data.duplicate(true);var original: Dictionary=doc.object(uid).duplicate(true);history=doc.undo_history.size();tools.start();await ready(tools)
		check(tools.proposal.get("ok",false) and tools.proposal["created"].size()==1 and tools.proposal["issues"].is_empty(),"Current modified position/scale/heading receive one compatible missing companion")
		tools.apply();await settle();check(doc.object(uid)==original and doc.data["objects"].size()==3 and doc.undo_history.size()==history+1,"Existing customized source and old furniture stay exact during atomic companion application")
		var added: Dictionary=doc.data.duplicate(true);studio._command("undo",null);await settle();check(doc.data==customized,"Existing-source Undo restores exact customized contents")
		studio._command("redo",null);await settle();check(doc.data==added,"Existing-source Redo preserves exact new identities")
		select(uid);tools.start();await ready(tools);history=doc.undo_history.size();check(not tools.proposal["changed"] and not tools.proposal["duplicates"].is_empty() and tools.dialog.get_ok_button().disabled,"Already-present matching pieces are explained instead of duplicated");tools.apply();check(doc.data==added and doc.undo_history.size()==history,"A duplicate review cannot add construction or history");tools.dialog.hide()
		doc.data["layers"]={"Furniture":{"visible":true,"locked":true}};studio.changed();select(uid);tools.start();await ready(tools);check(not tools.proposal.get("ok",false) and tools.dialog.get_ok_button().disabled and tools.message.text.contains("unlock"),"Locked destination layers block the set with an actionable reason");tools.dialog.hide();doc.data.erase("layers")
		doc.object(uid)["position"]=[240,100,0] if mode=="2d" else [6,0,4];doc.data["economy"]={"enabled":true,"starting_cash":0};doc.data["economy_account"]=Economy.fresh_account(doc.data,studio.library);studio.changed();select(uid);await settle();tools.start();await ready(tools);before=doc.data.duplicate(true);history=doc.undo_history.size()
		check(tools.proposal.get("ok",false) and not tools.proposal["quote"]["ok"] and tools.dialog.get_ok_button().disabled,"Insufficient funds remain previewable with an exact whole-set quote")
		tools.apply();check(doc.data==before and doc.undo_history.size()==history,"Unaffordable application preserves every object, budget and history entry");tools.dialog.hide()
		doc.data["economy"]["starting_cash"]=100000;doc.data["economy_account"]=Economy.fresh_account(doc.data,studio.library);studio.changed();select(uid);await settle();tools.start();await ready(tools)
		var cost: int=tools.proposal["quote"]["net"];tools.apply();await settle();check(doc.data["economy_account"]["cash"]==100000-cost and doc.data["economy_account"]["construction_total"]==cost,"The reviewed incremental price is charged exactly once")
		studio._command("undo",null);await settle();check(doc.data["economy_account"]["cash"]==100000,"Companion Undo restores the exterior treasury");studio._command("redo",null);await settle();check(doc.data["economy_account"]["cash"]==100000-cost,"Companion Redo does not charge again")
		select(uid);doc.object(uid)["position"][0]+=100 if mode=="2d" else 4;studio.changed();tools.start();await ready(tools);before=doc.data.duplicate(true);history=doc.undo_history.size();studio.road_drawing=true;tools.apply();check(studio.road_drawing and doc.data==before and doc.undo_history.size()==history,"An active road gesture is preserved rather than discarded by Apply");studio.road_drawing=false
		doc.checkpoint();doc.data["title"]="Changed while reviewing";studio.changed();doc.finish_checkpoint();before=doc.data.duplicate(true);history=doc.undo_history.size();tools.apply();check(doc.data==before and doc.undo_history.size()==history and tools.message.text.contains("changed"),"Stale exact review cannot overwrite a concurrent document edit");tools.dialog.hide()
		studio.clear_placement();studio.consumer_shell.close_drawer();doc.data=preload("res://scripts/builder/templates.gd").make(mode,"blank");studio.changed();studio.worlds[mode].reset_camera("blank");await settle()
		studio.drop_asset("3d:HanX_School/Student_Desk",studio.canvas.size*.5);await settle();var placed_uid: String=doc.data["objects"][0]["uid"]
		check(tools.panel.is_visible_in_tree() and tools.context().get("uid")==placed_uid and studio.asset_id.is_empty(),"Successful single placement offers companions for the actual placed source")
		tools.start();await ready(tools);check(tools.proposal.get("created",[]).size()==1 and tools.proposal["source_uid"]==placed_uid,"Post-placement review adds only the missing chair, never a second desk");tools.dialog.hide()
		studio.select_asset("3d:HanX_School/Student_Desk");studio.repeat_input.button_pressed=true;doc.checkpoint();studio.stroke_cells.clear();studio.paint(studio.canvas.size*Vector2(.8,.65));doc.finish_checkpoint();await settle();placed_uid=doc.data["objects"].back()["uid"]
		check(studio.asset_id=="3d:HanX_School/Student_Desk" and tools.context().get("uid")==placed_uid,"Repeat placement prioritizes the latest successful source over the still-ready asset")
		tools.start();await ready(tools);check(tools.proposal.get("created",[]).size()==1 and tools.proposal["source_uid"]==placed_uid,"Repeat placement reviews companions against that exact existing source");tools.dialog.hide();studio.repeat_input.button_pressed=false;studio.clear_placement()
	studio.free();await process_frame;await process_frame;print("COMPANION WORKFLOW: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
