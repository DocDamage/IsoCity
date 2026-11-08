extends SceneTree
const OUT="res://output/verification/asset_expansion/U13/"
var checks: int=0
var failures: int=0
var studio: Control
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func settle() -> void:
	for frame in 10:await process_frame
func key(code: Key) -> void:
	for pressed in [true,false]:
		var event:=InputEventKey.new();event.keycode=code;event.pressed=pressed;Input.parse_input_event(event);await process_frame
func ready(tools: RefCounted) -> void:
	for frame in 600:
		if not tools.dialog.visible or tools.proposal.has("ok") and (not tools.proposal["ok"] or tools.proposal.get("geometry_checked",false)):return
		await process_frame
	check(false,"Chooser finishes a bounded preview")
func choose(tools: RefCounted,key: String,operation: String) -> void:
	tools.select(tools.kit,key);tools.select(tools.action,operation);tools.refresh();await ready(tools)
func capture(name: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args():return
	await settle();await RenderingServer.frame_post_draw;check(root.get_texture().get_image().save_png(OUT+name+".png")==OK,"Actual chooser capture: "+name)
func select(uid: String) -> void:studio.selected_uids.assign([uid]);studio.selected_uid=uid;studio.refresh_controls()
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT);FileAccess.open(OUT+".gdignore",FileAccess.WRITE).close()
	studio=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio);await settle();await settle()
	if not studio.consumer_shell:check(false,"Consumer shell initialized");studio.free();quit(1);return
	studio.consumer_shell.dismiss_welcome();var tools: RefCounted=studio.interior_tools.kit_chooser
	for mode in ["2d","3d"]:
		studio.switch_mode(mode);var doc:=preload("res://scripts/builder/document.gd").new();doc.data=preload("res://scripts/builder/templates.gd").make(mode,"blank");studio.documents[mode]=doc
		var host: Dictionary=doc.add("3d:HanX_School/School_Building",[0,0,0],"0");var uid: String=host["uid"];select(uid);studio.changed();await settle()
		var before: Dictionary=doc.data.duplicate(true);var history: int=doc.undo_history.size();tools.show();await ready(tools)
		check(tools.dialog.visible and studio.modal_visible() and tools.proposal.get("geometry_checked",false) and not tools.dialog.get_ok_button().disabled,"First-room chooser reaches a usable reviewed preview: "+mode)
		check(doc.data==before and doc.undo_history.size()==history and not doc.object(uid).has("interior"),"Opening/previewing creates no room or history")
		var border: StyleBox=tools.dialog.get_theme_stylebox("embedded_border","Window")
		if border is StyleBoxFlat:
			var title: Color=tools.dialog.get_theme_color("title_color","Window").srgb_to_linear();var backdrop: Color=border.bg_color.srgb_to_linear();var contrast: float=(maxf(title.get_luminance(),backdrop.get_luminance())+.05)/(minf(title.get_luminance(),backdrop.get_luminance())+.05)
			check(contrast>=4.5,"Window title remains readable against the embedded border")
		await capture("create_"+mode);tools.dialog.get_cancel_button().grab_focus();await key(KEY_ESCAPE);await settle()
		check(not tools.dialog.visible and doc.data==before and not is_instance_valid(tools.preview.viewport),"Cancel preserves the document and releases the private world")
		studio.road_drawing=true;tools.show();await ready(tools);tools.apply();check(studio.road_drawing and doc.data==before and tools.dialog.get_ok_button().disabled,"An active road gesture is preserved and blocks layout application");tools.dialog.hide();studio.road_drawing=false
		tools.show();await ready(tools);tools.dialog.get_ok_button().grab_focus();await key(KEY_ENTER);await settle()
		check(not tools.dialog.visible and doc.object(uid).get("interior",{}).get("starter_kit",{}).get("id")=="classroom" and doc.undo_history.size()==history+1,"Applying first layout creates exactly one completed history step")
		var authored: Dictionary=doc.data.duplicate(true);studio._command("undo",null);check(not doc.object(uid).has("interior"),"Undo removes the newly created room")
		studio._command("redo",null);check(doc.data==authored,"Redo restores the exact reviewed saved identities");select(uid)
		tools.show();await choose(tools,"empty","replace");var preview_source: Dictionary=doc.data.duplicate(true);doc.checkpoint();doc.data["title"]="Changed while previewing";studio.changed();doc.finish_checkpoint();var concurrent: Dictionary=doc.data.duplicate(true);var concurrent_history: int=doc.undo_history.size();tools.apply()
		check(doc.data==concurrent and doc.undo_history.size()==concurrent_history and tools.message.text.contains("changed"),"Stale exact preview cannot overwrite a concurrent edit")
		tools.dialog.hide();doc.data["economy"]={"enabled":true,"starting_cash":0};doc.data["economy_account"]=preload("res://scripts/builder/economy_plan.gd").fresh_account(doc.data,studio.library);studio.changed();await settle();tools.show();await choose(tools,"shop","replace")
		before=doc.data.duplicate(true);history=doc.undo_history.size();check(not tools.proposal["quote"]["ok"] and tools.dialog.get_ok_button().disabled,"Insufficient funds stay visible before application")
		tools.apply();check(doc.data==before and doc.undo_history.size()==history,"Rejected purchase creates no partial room, account or history change")
		tools.dialog.hide();doc.data["economy"]["starting_cash"]=100000;doc.data["economy_account"]=preload("res://scripts/builder/economy_plan.gd").fresh_account(doc.data,studio.library);studio.changed();await settle();tools.show();await choose(tools,"shop","replace")
		var charge: int=tools.proposal["quote"]["net"];tools.apply();await settle()
		check(not tools.dialog.visible and doc.data["economy_account"]["cash"]==100000-charge and doc.data["economy_account"]["construction_total"]==charge,"Reviewed replacement is charged once at the previewed price")
		studio.interior_tools.start(uid);await settle();var floor_doc: RefCounted=studio.current();floor_doc.checkpoint();floor_doc.data["objects"][-1]["name"]="Customized furnishing";studio.changed();floor_doc.finish_checkpoint();var customized: Dictionary=floor_doc.canonical.data.duplicate(true)
		tools.show();await ready(tools);check(tools.selected(tools.action)=="add","Existing rooms default to the least destructive add action")
		await choose(tools,"empty","replace");history=floor_doc.undo_history.size();tools.apply();await settle()
		check(not tools.dialog.visible and floor_doc.undo_history.size()==history+1 and not floor_doc.data["objects"].any(func(item: Dictionary):return item.get("name")=="Customized furnishing"),"Actual owned-floor replacement uses one canonical history step")
		studio._command("undo",null);await settle();check(studio.current().canonical.data==customized,"Owned-floor Undo restores customized contents, IDs and settings")
		studio._command("redo",null);await settle();tools.show();await choose(tools,"apartment","floor");await capture("new_floor_"+mode)
		check(tools.summary.text.contains("needs stairs") and tools.proposal["issues"].is_empty(),"New-floor preview explains required connections and verifies its own layout")
		tools.apply();await settle();var upper: String=studio.current().floor_uid
		check(upper!="ground" and studio.current().canonical.data["floors"].size()==1 and not tools.dialog.visible,"Create-floor action uses the existing owned-floor editor")
		studio._command("undo",null);await settle();check(studio.current().floor_uid=="ground" and studio.current().canonical.data.get("floors",[]).is_empty(),"Undo safely removes the selected created floor")
		studio._command("redo",null);await settle();check(studio.current().floor_uid==upper,"Redo restores the same saved floor identity")
		studio.interior_tools.leave();await settle();doc=preload("res://scripts/builder/document.gd").new();doc.data=preload("res://scripts/builder/templates.gd").make(mode,"room");studio.documents[mode]=doc;studio.selected_uids.clear();studio.selected_uid="";studio.changed();await settle();tools.show();await choose(tools,"apartment","replace")
		check(tools.standalone and tools.proposal["ok"] and tools.proposal["issues"].is_empty() and not tools.dialog.get_ok_button().disabled,"Standalone room templates can preview a replacement too")
		before=doc.data.duplicate(true);tools.apply();await settle();check(not tools.dialog.visible and doc.data!=before,"Standalone replacement applies through ordinary document history")
		studio._command("undo",null);await settle();check(doc.data==before,"Standalone room Undo restores the complete original layout")
		studio._command("redo",null);await settle();tools.show();await choose(tools,"empty","replace")
		for size in [Vector2i(1480,900),Vector2i(960,640)]:
			root.size=size;tools.dialog.popup_centered_clamped(Vector2i(880,680),.9);await settle();await capture("chooser_"+mode+"_"+str(size.x))
			studio.consumer_shell.set_active(false,false);tools.dialog.popup_centered_clamped(Vector2i(880,680),.9);await settle();await capture("chooser_precision_"+mode+"_"+str(size.x));studio.consumer_shell.set_active(true,false)
		studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true});tools.dialog.popup_centered_clamped(Vector2i(880,680),.9);await settle();check(tools.dialog.size.x<=960 and tools.dialog.size.y<=640,"Enlarged chooser fits the supported minimum window");await capture("chooser_accessible_"+mode)
		tools.dialog.hide();studio.accessibility_settings.restore({});root.size=Vector2i(1480,900)
	studio.free();await process_frame;await process_frame;print("INTERIOR KIT WORKFLOW: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
