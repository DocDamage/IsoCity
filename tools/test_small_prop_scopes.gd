extends "res://tools/test_small_prop_view.gd"
const Floor=preload("res://scripts/builder/floor_plan.gd")
func overlap_point(uid: String) -> Vector2:
	var bounds: Rect2=studio.screen_bounds(uid)
	for y in 21:
		for x in 21:
			var at: Vector2=bounds.position+bounds.size*Vector2((x+.5)/21.0,(y+.5)/21.0);var ids: Array=studio.worlds[studio.mode].pick_all(at)
			if ids.has(uid) and ids.size()>1:return at
	return Vector2(-1,-1)
func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio);await settle(16)
	for mode in ["2d","3d"]:
		studio.switch_mode(mode)
		var outer: RefCounted=studio.current();var building: Dictionary=outer.data["objects"].filter(func(item: Dictionary):return studio.library.assets[item["asset"]]["behavior"].get("building",false))[0]
		studio.interior_tools.start(building["uid"]);await settle()
		var doc: RefCounted=studio.current();var floors: RefCounted=studio.interior_tools.floor_tools
		floors.new_name.text="Tiny workshop";floors.new_height.value=3;floors.add_floor();await settle();var upstairs: String=doc.floor_uid
		check(upstairs!="ground","Real owned room gains independent upstairs workspace: "+mode)
		var asset: String="2d:Supplemental_Classroom_school_kit_pencil_sharpener_432fcf98" if mode=="2d" else "3d:Fire_Station_PSX/bench_vise"
		doc.checkpoint();var prop: Dictionary=doc.add(asset,[0,0,0],str(studio.library.directions(asset)[0]));var uid: String=prop["uid"]
		var support: Dictionary=doc.add("3d:HanX_Shop/Cafe_Counter",[0,0,0],"0")
		var shelf: Dictionary=doc.add("3d:HanX_Shop/Shelf_Wall",[0,0,0],"0")
		studio.changed();doc.finish_checkpoint();await settle()
		if mode=="3d":
			var bounds: AABB=preload("res://scripts/builder/asset_scale_preview.gd").render_bounds(studio.worlds[mode].instances[support["uid"]]);prop["position"][1]=bounds.end.y;studio.changed();await settle()
		studio.worlds[mode].reset_camera("room");await settle();var point: Vector2=overlap_point(uid);check(point.x>=0,"Tiny counter/shelf source remains enumerable behind overlapping scenery: "+mode)
		if point.x>=0:
			studio.overlap_picker.show(point);var index: int=-1
			for row in studio.overlap_picker.popup.item_count:
				var value: Variant=studio.overlap_picker.popup.get_item_metadata(row)
				if value is String and value==uid:index=row
			check(index>=0,"Overlap menu exposes the original tiny prop: "+mode)
			if index>=0:studio.overlap_picker.popup.id_pressed.emit(studio.overlap_picker.popup.get_item_id(index))
		else:studio.overlap_picker.choose(uid)
		await capture("upstairs_stack_"+mode)
		var original: Dictionary=doc.canonical.data.duplicate(true);FileAccess.open("res://output/verification/asset_expansion/U18/scope_expected_"+mode+".json",FileAccess.WRITE).store_string(JSON.stringify(original,"\t"));var history: int=doc.undo_history.size();studio._command("small_props_isolate",null);await settle(16)
		check(studio.small_prop_tools.active and not studio.worlds[mode].instances[support["uid"]].visible,"Tiny source on upstairs counter can be isolated: "+mode)
		check(not studio.worlds[mode].instances[shelf["uid"]].visible and hit(uid).x>=0,"Temporary isolation removes shelf occlusion for precise picking: "+mode)
		check(doc.canonical.data==original and doc.undo_history.size()==history,"Isolation preserves entire nested floor document: "+mode)
		await capture("upstairs_"+mode)
		var saved: String="res://output/verification/asset_expansion/U18/nested_"+mode+".isocity.json";check(studio.write_project(saved),"Normal save works during upstairs isolation: "+mode)
		floors.switch_floor("ground");await settle();check(not studio.small_prop_tools.active and studio.worlds[mode].editor_focus.is_empty() and doc.floor_uid=="ground","Switching floor clears isolated scope before applying new room: "+mode)
		floors.switch_floor(upstairs);await settle();check(studio.worlds[mode].instances[support["uid"]].visible and doc.canonical.data==original,"Returning upstairs restores authored counter and prop: "+mode)
		studio.overlap_picker.choose(uid);studio._command("small_props_isolate",null);await settle();studio.interior_tools.leave();await settle()
		check(not studio.small_prop_tools.active and studio.current()==outer,"Leaving owned room resets temporary view: "+mode)
		check(studio.load_project(saved),"Saved isolated upstairs project reopens normally: "+mode);await settle();studio.interior_tools.start(building["uid"]);studio.interior_tools.floor_tools.switch_floor(upstairs);await settle()
		FileAccess.open("res://output/verification/asset_expansion/U18/scope_reopened_"+mode+".json",FileAccess.WRITE).store_string(JSON.stringify(studio.current().canonical.data,"\t"))
		check(JSON.parse_string(JSON.stringify(studio.current().canonical.data))==JSON.parse_string(JSON.stringify(original)),"Normal reopen retains exact nested JSON values: "+mode)
		check(studio.worlds[mode].instances[support["uid"]].visible and not studio.small_prop_tools.active,"Normal reopen restores authored visibility without temporary view: "+mode)
		studio.overlap_picker.choose(uid);studio._command("small_props_isolate",null);await settle();studio._command("home",null);await settle();check(not studio.small_prop_tools.active and studio.worlds[mode].editor_focus.is_empty(),"Reset while isolated clears filter and restores ordinary camera: "+mode)
		studio.interior_tools.leave();await settle()
		var new_outer: RefCounted=studio.current();var native: Dictionary=new_outer.data["objects"][0];studio.overlap_picker.choose(native["uid"]);studio._command("small_props_isolate",null);await settle();studio.switch_mode("3d" if mode=="2d" else "2d");await settle();check(not studio.small_prop_tools.active and studio.worlds[mode].editor_focus.is_empty(),"World switching clears old-scope isolation: "+mode)
	studio.free();await settle();print("SMALL PROP SCOPES: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
