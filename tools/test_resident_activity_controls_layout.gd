extends "res://tools/test_resident_activity_interruptions.gd"
var layout_facts: Array=[]
func decorate_room(room: Dictionary,_mode: String) -> void:room["floor_links"].clear()
func key(code: Key) -> void:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=true;Input.parse_input_event(event);await process_frame;event=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=false;Input.parse_input_event(event);await settle()
func snapshot(name: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args():return
	RenderingServer.force_draw(false);RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png("res://output/verification/asset_expansion/I14/"+name+".png")==OK,"Captured actual interior settings and diagnostics: "+name)
func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio);await settle();studio.consumer_shell.dismiss_welcome()
	for mode in ["2d","3d"]:
		var doc: RefCounted=await setup_case(mode,"elevator");studio.control_settings.execute("resident_activities");await settle();var source: Dictionary=doc.data.duplicate(true);var count: int=doc.undo_history.size();var tools: RefCounted=studio.citizen_tools
		for simple in [true,false]:
			studio.consumer_shell.set_active(simple,false)
			for dimensions in [Vector2i(1480,900),Vector2i(960,640)]:
				root.size=dimensions
				for scale_value in [1.0,1.5]:
					studio.accessibility_settings.restore({"text_scale":scale_value,"large_targets":scale_value>1.0,"shape_markers":true});await settle();studio.control_settings.execute("resident_activities");await settle();tools.tick(1)
					var label: String=("simple" if simple else "precision")+"_"+mode+"_"+str(dimensions.x)+"_"+str(int(scale_value*100));var viewport:=Rect2(Vector2.ZERO,Vector2(root.size));var flag: Rect2=tools.interior_activities.get_global_rect();var panel: Rect2=tools.panel.get_global_rect()
					check(tools.interior_activities.has_focus() and viewport.encloses(flag) and panel.encloses(flag),"Command-focused option is fully visible in the actual window and scroll panel: "+label+" "+str(flag)+" panel="+str(panel))
					await key(KEY_SPACE);check(not tools.interior_activities.button_pressed and doc.data==source,"Keyboard activation changes the draft control without authoring: "+label);await key(KEY_SPACE);check(tools.interior_activities.button_pressed,"Keyboard activation restores the draft option: "+label)
					await key(KEY_TAB);check(studio.get_viewport().gui_get_focus_owner()!=tools.interior_activities and not studio.walking,"Tab advances through settings without entering Walk: "+label)
					tools.residents.select(0);tools.residents.item_selected.emit(0)
					if mode=="3d":tools.resident_detail.grab_focus()
					else:studio.control_settings.execute("resident_activities")
					await settle();var target: Control=tools.resident_detail if mode=="3d" else tools.interior_activities;var target_rect: Rect2=target.get_global_rect();var canvas: Rect2=studio.canvas.get_global_rect().intersection(viewport)
					check(target.has_focus() and viewport.encloses(target_rect) and tools.panel.get_global_rect().encloses(target_rect),"Keyboard can reveal the complete focused option or selected-resident readout: "+label)
					check(tools.resident_detail.text.contains("Waiting outside") and tools.resident_detail.text.contains("return route"),"Actual unlinked-floor diagnostics explain why the selected resident waits: "+label)
					check(canvas.size.x>=240 and canvas.size.y>=200,"Settings retain a usable visible canvas: "+label+" "+str(canvas))
					check(doc.data==source and doc.undo_history.size()==count,"Workspace, scaling, keyboard and diagnostics create no authored content/history: "+label)
					layout_facts.append({"name":label,"window":str(viewport),"option":str(flag),"panel":str(panel),"target":str(target_rect),"canvas":str(canvas)});await snapshot("activity_controls_"+label)
		citizens.clear();studio.set_walking(false)
	FileAccess.open("res://output/verification/asset_expansion/I14/control_layout_facts.json",FileAccess.WRITE).store_string(JSON.stringify(layout_facts,"\t"));studio.free();await settle();print("RESIDENT ACTIVITY CONTROLS LAYOUT: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
