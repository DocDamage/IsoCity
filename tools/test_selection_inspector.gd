extends SceneTree
var checks: int = 0
var failures: int = 0
func check(value: bool, message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func select(studio: Control, items: Array) -> void:
	studio.selected_uids.clear()
	for item in items: studio.selected_uids.append(item["uid"])
	studio.selected_uid = items[0]["uid"] if not items.is_empty() else ""
	studio.refresh_controls()
func settle() -> void:
	for i in 5: await process_frame
func capture(name: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await settle()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://output/"+name+".png")
func run() -> void:
	var studio: Control = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled=false
	root.add_child(studio)
	await settle()
	var inspector: RefCounted = studio.selection_inspector
	for mode in ["2d","3d"]:
		studio.switch_mode(mode)
		studio.clear_placement()
		var doc: RefCounted = studio.current()
		var a: Dictionary = doc.add("2d:Coffee_Shop",[40,1,0] if mode=="2d" else [2,1,4],"SE",1)
		var b: Dictionary = doc.add("3d:HanX_Park/Bench_Park",[100,2,2] if mode=="2d" else [5,2,7],"90",2)
		a["name"]="Alice's café"
		a["group"]="g"
		b["group"]="g"
		doc.data["group_names"]={"g":"Market block"}
		b["tilt"]=[15,20]
		studio.changed()
		select(studio,[a])
		check(inspector.breadcrumb.text.contains("Alice's café") and inspector.breadcrumb.text.contains("Buildings") and inspector.breadcrumb.text.contains("Market block"),"Single selection shows name, layer and group: "+mode)
		check(not inspector.affected.visible and not inspector.mixed["scale"],"Single selection has plain numeric fields: "+mode)
		select(studio,[a,b])
		check(inspector.breadcrumb.text.contains("2 objects") and inspector.affected.text.contains("2 editable"),"Multiple selection shows affected count and group context: "+mode)
		check(inspector.mixed["height"] and inspector.mixed["scale"] and inspector.mixed["angle"],"Differing numeric values are Mixed: "+mode)
		await settle()
		check(inspector.mixed_labels["height"].visible and inspector.mixed_labels["scale"].visible,"Mixed fields remain labeled after native controls redraw: "+mode)
		check(inspector.field_notes["scale"].text.contains("keep size ratios") and inspector.field_notes["angle"].text.contains("relative headings"),"Relative group adjustment behavior is explained: "+mode)
		check(inspector.view_note.text.contains("1 of 2"),"Mixed asset source-view control gives its compatible count: "+mode)
		check(inspector.field_notes["pitch"].text.contains("1 of 2") if mode=="2d" else inspector.field_notes["pitch"].text.contains("2 of 2"),"Tilt shows exact eligible count: "+mode)
		studio.workspace_layout.advanced_toggle.button_pressed=false
		check(not inspector.field_notes["pitch"].is_visible_in_tree(),"Basic hides advanced field count with its row: "+mode)
		studio.workspace_layout.advanced_toggle.button_pressed=true
		studio.set_rotation_value("pitch",25)
		check(b["tilt"][0]==25 and (not a.has("tilt") if mode=="2d" else a["tilt"][0]==25),"Tilt changes only eligible objects even when active object is a sprite: "+mode)
		check(not inspector.mixed["pitch"],"Absolute tilt fields converge after editing: "+mode)
		studio._command("height",3)
		check(a["position"][2 if mode=="2d" else 1]==3 and b["position"][2 if mode=="2d" else 1]==3 and not inspector.mixed["height"],"Height applies to all eligible objects: "+mode)
		# Entering the first object's existing height must still update the second.
		b["position"][2 if mode=="2d" else 1]=4
		studio.refresh_controls()
		studio.height_input.get_line_edit().grab_focus()
		studio.height_input.get_line_edit().release_focus()
		check(b["position"][2 if mode=="2d" else 1]==4,"Focusing and leaving a Mixed field without editing preserves differences: "+mode)
		studio.height_input.get_line_edit().grab_focus()
		studio.height_input.get_line_edit().text="3"
		studio.height_input.get_line_edit().text_submitted.emit("3")
		check(b["position"][2 if mode=="2d" else 1]==3,"Submitting an unchanged active value updates other mixed objects: "+mode)
		studio.height_input.get_line_edit().release_focus()
		studio._command("scale",1.5)
		check(is_equal_approx(a["scale"],1.5) and is_equal_approx(b["scale"],3) and inspector.mixed["scale"],"Scaling retains relative sizes and Mixed state: "+mode)
		var difference: float = studio.Rotation.heading(b,studio.library)-studio.Rotation.heading(a,studio.library)
		studio.set_rotation_value("angle",45)
		check(is_equal_approx(wrapf(studio.Rotation.heading(b,studio.library)-studio.Rotation.heading(a,studio.library),0,360),wrapf(difference,0,360)),"Heading adjustments retain relative headings: "+mode)
		var c: Dictionary = doc.add("2d:Bakery",[200,0,0] if mode=="2d" else [8,0,3],"SW")
		studio.changed()
		select(studio,[a,c,b])
		check(studio.view_choice.get_item_text(studio.view_choice.selected)=="Mixed","Differing sprite source views display Mixed: "+mode)
		studio._command("source_view","SW")
		check(a["direction"]=="SW" and c["direction"]=="SW" and b["direction"]!="SW","Source view changes compatible sprites and preserves models: "+mode)
		check(studio.view_choice.get_item_text(studio.view_choice.selected)=="SW","Common source view appears after adjustment: "+mode)
		var ground: Dictionary = doc.add("2d:Grass",[250,0,0] if mode=="2d" else [10,0,3],"SE")
		select(studio,[a,ground])
		studio._command("source_view","SW")
		check(ground["direction"]=="SE","Source-view editing excludes ground world rotation: "+mode)
		select(studio,[a,b])
		b["layer"]="Furniture"
		b.erase("group")
		studio.refresh_controls()
		check(inspector.breadcrumb.text.contains("Mixed layers") and inspector.breadcrumb.text.contains("Mixed groups") and studio.assign_layer.get_item_text(0).contains("Mixed"),"Mixed layer/group context is explicit: "+mode)
		b["locked"]=true
		studio.refresh_controls()
		check(not inspector.affected.visible and inspector.breadcrumb.text.contains("Alice's café"),"Protected selections are excluded from the editable count: "+mode)
		b["locked"]=false
		select(studio,[a,b])
		await capture("editor_selection_mixed_"+mode)
		var before: Dictionary = doc.data.duplicate(true)
		studio.refresh_controls()
		check(doc.data==before,"Rendering Mixed and context does not mutate documents: "+mode)
		select(studio,[])
		check(not inspector.mixed["scale"] and studio.scale_input.get_line_edit().text!="Mixed" and inspector.breadcrumb.text.contains("No selection"),"Clearing selection clears stale Mixed values and context: "+mode)
		select(studio,[a])
		studio.interior_tools.start(a["uid"])
		await settle()
		check(inspector.breadcrumb.text.contains("Alice's café") and inspector.breadcrumb.text.contains("Interior"),"Interior breadcrumb identifies its owning building: "+mode)
		var room_item: Dictionary = studio.current().data["objects"][0]
		select(studio,[room_item])
		check(inspector.breadcrumb.text.contains(studio.library.assets[room_item["asset"]]["name"]),"Interior breadcrumb includes selected room object: "+mode)
		await capture("editor_selection_room_"+mode)
		studio.interior_tools.leave()
		await settle()
		check(not inspector.breadcrumb.text.contains("Interior"),"Leaving the room restores exterior location: "+mode)
		var extreme: Dictionary = doc.add("3d:HanX_Park/Bench_Park",[0,-2,-1],"0",0.1)
		select(studio,[extreme])
		check(is_equal_approx(studio.scale_input.value,0.1) and studio.height_input.value==(-1 if mode=="2d" else -2),"Inspector represents supported small sizes and negative heights faithfully: "+mode)
	studio.free()
	print("SELECTION INSPECTOR: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
