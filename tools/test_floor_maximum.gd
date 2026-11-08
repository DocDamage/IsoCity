extends "res://tools/test_floor_maximum_export_runtime.gd"
var studio: Control
func same_content(a: Variant,b: Variant) -> bool:
	if (a is float or a is int) and (b is float or b is int): return absf(float(a)-float(b))<=1e-9*maxf(1,absf(float(a)))
	if typeof(a)!=typeof(b): return false
	if a is Dictionary:
		if a.size()!=b.size(): return false
		for key in a:
			if not b.has(key) or not same_content(a[key],b[key]): return false
		return true
	if a is Array:
		if a.size()!=b.size(): return false
		for index in a.size():
			if not same_content(a[index],b[index]): return false
		return true
	return a==b
func choose(field: OptionButton,uid: String) -> void:
	for index in field.item_count:
		if field.get_item_metadata(index)==uid: field.select(index); return
	check(false,"Floor option exists: "+uid)
func capture(mode: String,stage: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	for frame in 5: await process_frame
	RenderingServer.force_draw(false); RenderingServer.force_draw(false); root.get_texture().get_image().save_png("res://output/floor_maximum_"+mode+"_"+stage+".png")
func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio)
	for frame in 5: await process_frame
	for mode in ["2d","3d"]:
		studio.switch_mode(mode); var city: RefCounted=studio.current(); var before: Dictionary=city.data.duplicate(true)
		var host: Dictionary=city.data["objects"].filter(func(item: Dictionary)->bool:return studio.library.assets[item["asset"]]["behavior"].get("building",false))[0]; var host_uid: String=host["uid"]
		studio.interior_tools.start(host_uid); var doc: RefCounted=studio.current(); var floors: RefCounted=studio.interior_tools.floor_tools
		doc.data["objects"]=[]; doc.data["exit"]=[-144,-8,0] if mode=="2d" else [-5,.1,4]
		for height in [-3,3,6,9,12,15,18]:
			floors.new_name.text="Basement" if height<0 else "Level "+str(height/3); floors.new_height.value=height; floors.add_floor()
		var definitions: Array=Plan.definitions(doc.canonical.data); var basement: String=definitions[0]["uid"]; var top: String=definitions[-1]["uid"]
		check(definitions.size()==8 and floors.choice.item_count==8,"The real floor controls author the supported eight-storey building: "+mode)
		var at_limit: Dictionary=doc.canonical.data.duplicate(true); var count: int=doc.undo_history.size(); floors.new_name.text="Ninth"; floors.new_height.value=21; floors.add_floor()
		check(doc.canonical.data==at_limit and doc.undo_history.size()==count and floors.message.text.contains("8 floors"),"A ninth floor explains the limit without changing contents or history: "+mode)
		for definition in definitions:
			floors.switch_floor(definition["uid"]); doc.checkpoint(); doc.data["objects"]=[]; doc.data["exit"]=[-144,-8,0] if mode=="2d" else [-5,.1,4]
			if mode=="2d": preload("res://scripts/builder/templates.gd").ground(doc,"Floor_Wood_Oak",-7,7,-7,14)
			var door: Dictionary=doc.add("2d:Door_White",[-16,-56,0] if mode=="2d" else [-4,0,-3],studio.library.directions("2d:Door_White")[0]); door["uid"]="shared_door"; door["open"]=false
			for index in 12:
				var x: float=-5+(index%3)*2; var z: float=6+floori(index/3.0)*2
				var asset: String="2d:Sofa_Teal" if mode=="2d" else "3d:HanX_Shop/Cafe_Table_Set"
				var pixel: Vector2=Fit.pixels(Vector2(x,z)); var item: Dictionary=doc.add(asset,[pixel.x,pixel.y,0] if mode=="2d" else [x,0,z],studio.library.directions(asset)[0]); item["name"]=definition["name"]+" seating "+str(index)
			doc.finish_checkpoint(); studio.changed()
		var ui: RefCounted=floors.connections; ui.show()
		for index in 7:
			ui.new_record(); choose(ui.lower,definitions[index]["uid"]); choose(ui.upper,definitions[index+1]["uid"]); ui.kind.select(0); ui.update_kind()
			ui.start_x.value=-3 if index%2==0 else 2; ui.end_x.value=2 if index%2==0 else -3; ui.start_z.value=0 if index%2==0 else 2; ui.end_z.value=ui.start_z.value; ui.width.value=1.4; ui.apply_record()
		ui.new_record(); ui.kind.select(1); ui.update_kind(); choose(ui.lower,basement); choose(ui.upper,top); ui.start_x.value=4; ui.start_z.value=-4; ui.width.value=1.4; ui.apply_record(); ui.dialog.hide()
		check(Plan.valid(doc.canonical.data) and doc.canonical.data["floor_links"].size()==8,"The actual connection controls author seven flights and one eight-stop elevator: "+mode)
		var entrances: RefCounted=floors.entrances; entrances.show()
		for uid in [basement,top]:
			entrances.new_record(); entrances.select_floor(uid); entrances.source[0].value=12; entrances.source[1].value=-3 if uid==basement else 18; entrances.source[2].value=12; entrances.custom_landing.button_pressed=true
			var arrival: Array=[-144,-8,0] if mode=="2d" else [-5,.1,4]
			for index in 3: entrances.arrival[index].value=arrival[index]
			entrances.apply_record()
		entrances.dialog.hide(); floors.switch_floor(top); floors.refresh_fields(); floors.name_input.text="Roof lounge"; floors.update_floor()
		check(Plan.definitions(doc.canonical.data)[-1]["name"]=="Roof lounge","The maximum-floor building retains editable floor names: "+mode)
		var furnished: Dictionary=doc.canonical.data.duplicate(true); floors.switch_floor(basement); floors.remove_floor()
		check(doc.canonical.data["floors"].size()==6 and doc.canonical.data["floor_links"].size()==6 and doc.canonical.data["floor_entrances"].size()==1,"Removing the basement cascades its flight, range elevator and entrance: "+mode)
		studio._command("undo",null); check(doc.canonical.data==furnished,"Shared Undo restores the complete furnished basement and all affected connections: "+mode)
		floors.switch_floor(basement); var world: Node=studio.worlds[mode]; var exploration: Node=world.exploration; var player: Node=world.player
		check(preload("res://scripts/builder/document.gd").valid(doc.canonical.data,mode,studio.library),"The combined maximum-floor building is valid project content: "+mode)
		studio.set_walking(true); await settle(); check(exploration.active_floor()==basement and exploration.preview,"Connected editor Walk starts in the furnished basement: "+mode)
		if exploration.interior==null:
			print("MAXIMUM START: ",studio.status.text); studio.free(); quit(1); return
		await ascend(exploration)
		var door: Node=exploration.room_world().instances["shared_door"]; player.teleport_to(door.global_position+(Vector2(0,24) if mode=="2d" else Vector3(0,0,1.5))); studio.control_settings.execute("interact")
		check(Plan.room(doc.canonical.data,top)["objects"][0]["open"] and not Plan.room(doc.canonical.data,basement)["objects"][0]["open"],"Walking edits the correct repeated local door UID across all eight floors: "+mode)
		if mode=="3d": player.teleport_to(Vector3(-2,18.05,7)); await settle()
		await capture(mode,"walk_roof"); await trip(exploration,basement)
		for definition in definitions.slice(1): await trip(exploration,definition["uid"])
		studio.set_walking(false); check(doc.floor_uid==top and floors.choice.item_count==8,"Returning to Build selects the reached top floor without losing other rooms: "+mode)
		var safe_landing: Variant=Fit.pixels(Vector2(4,-2.35)) if mode=="2d" else Vector3(4,.05,-2.35)
		check(player.position.distance_to(safe_landing)<.01,"Returning to Build from an idle upstairs cabin uses its supported landing: "+mode)
		if mode=="3d": world.distance=28; world.target=Vector3(0,0,3); world.update_camera()
		await capture(mode,"build_roof"); floors.manage.pressed.emit(); await capture(mode,"manage"); floors.dialog.hide()
		var file: String="res://output/floor_maximum_"+mode; check(studio.write_project(file+".isocity.json"),"The ordinary save command persists the complete furnished eight-floor city: "+mode)
		var loader=preload("res://scripts/builder/project_repair.gd").new(studio.library); var loaded: Dictionary=loader.read(file+".isocity.json"); var saved_host: Dictionary=loaded["content"]["documents"][mode]["objects"].filter(func(item: Dictionary)->bool:return item["uid"]==host_uid)[0]
		check(loaded["ok"] and loader.issues.is_empty() and same_content(saved_host["interior"],doc.canonical.data),"Reopening preserves every floor, furnishing, connection, entrance and walking door edit without repair: "+mode)
		studio.set_walking(true); await settle(); check(studio.walking and exploration.preview and exploration.active_floor()==top and player.recovery_count==0,"Walk restarts safely after leaving an idle top-floor cabin: "+mode)
		studio.show_file_dialog("export"); studio.file_dialog.hide(); studio._file_selected(file+".tscn")
		studio._command("export_portable",null); studio.file_dialog.hide(); studio._file_selected(file+".zip")
		check(FileAccess.file_exists(file+".tscn") and FileAccess.file_exists(file+".zip") and studio.walking and exploration.active_floor()==top,"Both actual export actions preserve the connected maximum-floor visit: "+mode)
		studio.set_walking(false); studio.interior_tools.leave(); check(city.undo() and city.data==before,"The entire maximum-floor authoring and walking visit remains one city Undo step: "+mode)
		check(city.redo() and city.object(host_uid)["interior"]["floors"].size()==7,"City Redo restores the full furnished building: "+mode); studio.changed()
	studio.free(); print("FLOOR MAXIMUM: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
