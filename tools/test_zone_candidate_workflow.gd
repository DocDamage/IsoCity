extends "res://tools/test_zone_plan.gd"
const OUT="res://output/verification/asset_expansion/I15/"
var studio: Control
func normalized(value: Dictionary) -> Dictionary:return JSON.parse_string(JSON.stringify(value))
func settle() -> void:
	for frame in 16:await process_frame
	await physics_frame
func select(choice: OptionButton,value: String) -> void:
	for index in choice.item_count:
		if choice.get_item_metadata(index)==value:choice.select(index);choice.item_selected.emit(index);return
	check(false,"Inspector exposes reviewed filter: "+value)
func key(code: Key) -> void:
	for pressed in [true,false]:
		var event:=InputEventKey.new();event.keycode=code;event.pressed=pressed;Input.parse_input_event(event);await process_frame
func capture(name: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args():return
	await RenderingServer.frame_post_draw;check(root.get_texture().get_image().save_png(OUT+name+".png")==OK,"Retained actual zoning controls: "+name)
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT);root.size=Vector2i(1480,900);studio=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio);await settle();await settle();studio.consumer_shell.dismiss_welcome();library=studio.library
	for mode in ["2d","3d"]:
		studio.switch_mode(mode);var doc: RefCounted=preload("res://scripts/builder/document.gd").new();doc.data=fixture(mode,"residential");doc.data["zones"]=[];doc.data["economy"]={"enabled":true,"starting_cash":10000};doc.data["economy_account"]=Economy.fresh_account(doc.data,library);studio.documents[mode]=doc;studio.changed();await settle();var tools: RefCounted=studio.zone_tools;tools.managers[mode].set_process(false);tools.managers[mode].paused=true;studio.economy_tools.pauses[mode]=true;studio._command("zoning",null);var before: Dictionary=doc.data.duplicate(true);var history: int=doc.undo_history.size()
		select(tools.kind,"residential");select(tools.theme_choice,"village");select(tools.density,"low");tools.max_price.value=2000
		check(doc.data==before and doc.undo_history.size()==history and tools.theme_note.text.contains("village"),"Editing theme/density/price controls is a read-only draft: "+mode)
		tools.add_rect(Rect2(-24,8,48,48));await settle();var uid: String=tools.selected;check(doc.data["zones"].size()==1 and doc.data["zones"][0]["theme"]=="village" and doc.data["zones"][0]["density"]=="low" and doc.data["zones"][0]["max_price"]==2000 and doc.data["objects"].size()==2 and doc.data["economy_account"]["cash"]==10000,"Actual designation persists explicit filters without construction or charge: "+mode)
		tools.advance_selected();await settle();var proposal: Dictionary=tools.lot()["proposal"].duplicate(true);var selection: Dictionary=tools.lot()["selection"].duplicate(true)
		check(tools.lot()["stage"]==1 and selection["family"].begins_with("supplemental/village/") and library.assets[proposal["asset"]]["data"]["family_id"]==selection["family"],"Actual themed foundation chooses an exact member of the reviewed design: "+mode)
		tools.name_input.text="Named village lane";tools.apply_lot();await settle();check(tools.lot()["stage"]==1 and tools.lot()["proposal"]==proposal and tools.lot()["selection"]==selection,"Renaming a lot preserves its selected construction instead of restarting it: "+mode)
		history=doc.undo_history.size();tools.apply_lot();check(doc.undo_history.size()==history,"Unchanged complete lot fields add no history step: "+mode)
		select(tools.theme_choice,"industrial");tools.apply_lot();await settle();check(tools.lot()["stage"]==0 and not tools.lot().has("proposal") and not tools.lot().has("selection") and doc.data["objects"].size()==2,"Explicit filter change resets the unbuilt plan while preserving existing objects: "+mode)
		var state: Dictionary=Plan.evaluate(doc.data,tools.lot(),library);tools.managers[mode].states[uid]=state;tools.refresh();check(not state["ok"] and tools.detail.text.contains("No reviewed"),"Invalid theme/type combination explains the actual absence instead of choosing unrelated art: "+mode)
		studio._command("undo",null);await settle();tools.selected=uid;tools.fields_stamp=0;tools.refresh_lot();check(tools.lot()["stage"]==1 and tools.lot()["proposal"]==proposal and tools.lot()["selection"]==selection and tools.chosen_filters()=={"theme":"village","density":"low","max_price":2000},"Ordinary Undo restores the exact saved selection and inspector filters: "+mode)
		var saved: String=OUT+"themed_controls_"+mode+".isocity.json";check(studio.write_project(saved) and studio.load_project(saved),"Themed lot saves and reopens through ordinary project controls: "+mode);await settle();doc=studio.current();tools.selected=uid;tools.fields_stamp=0;tools.refresh_lot();studio.Store.write_json(OUT+"ui_selection_expected_"+mode+".json",selection);studio.Store.write_json(OUT+"ui_selection_reopened_"+mode+".json",tools.lot()["selection"]);check(Plan.Candidates.options(tools.lot())=={"theme":"village","density":"low","max_price":2000} and normalized(tools.lot()["selection"])==normalized(selection),"Reopening retains selected appearance, revision notes and explicit constraints: "+mode)
		for simple in [true,false]:
			studio.consumer_shell.set_active(simple,false)
			for size in [Vector2i(1480,900),Vector2i(960,640)]:
				root.size=size;studio.accessibility_settings.restore({"text_scale":1.5,"high_contrast":true,"large_targets":true} if size.x==960 else {});studio._command("zoning",null);await settle();var name: String=mode+"_"+("simple" if simple else "precision")+"_"+str(size.x);tools.panel.ensure_control_visible(tools.max_price);await settle()
				check(tools.panel.get_child(0).size.x<=tools.panel.size.x,"Reviewed filter controls fit their scrolling inspector: "+name);check(not tools.theme_choice.accessibility_name.is_empty() and tools.theme_choice.focus_mode==Control.FOCUS_ALL,"Theme control has an accessible name and keyboard focus: "+name)
				tools.paused.grab_focus();tools.panel.ensure_control_visible(tools.paused);await settle();before=doc.data.duplicate(true);var paused: bool=tools.managers[mode].paused;await key(KEY_SPACE);await settle();check(tools.managers[mode].paused!=paused and doc.data==before,"Real Space toggles transient growth pause without editing saved content: "+name);tools.managers[mode].paused=true;tools.refresh_settings();tools.panel.ensure_control_visible(tools.max_price);await settle();await capture("filters_"+name)
		studio.accessibility_settings.restore({});root.size=Vector2i(1480,900)
	studio.free();await process_frame;await process_frame;print("ZONE CANDIDATE WORKFLOW: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
