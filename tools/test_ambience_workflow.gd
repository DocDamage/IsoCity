extends SceneTree
const Plan=preload("res://scripts/builder/ambience_plan.gd")
const Floors=preload("res://scripts/builder/floor_plan.gd")
var studio: Control
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func mix(frames: int=60) -> void:
	for frame in frames: studio.ambience_tools.tick(1.0/60)
func choose(field: OptionButton,value: String) -> void:
	for index in field.item_count:
		if field.get_item_metadata(index)==value: field.select(index); return
	check(false,"Audio source option exists: "+value)
func settle() -> void:
	for frame in 5: await physics_frame
	await process_frame
func aim(point: Vector3,mode: String) -> void:
	var world: Node=studio.worlds[mode]
	if mode=="2d":
		var pixel: Array=Plan.Traffic.world(Vector2(point.x,point.z),mode); world.camera.position=Vector2(pixel[0],pixel[1])
	else: world.target=Vector3(point.x,0,point.z); world.update_camera()
func capture(mode: String,stage: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	for frame in 5: await process_frame
	RenderingServer.force_draw(false); RenderingServer.force_draw(false); root.get_texture().get_image().save_png("res://output/ambience_"+mode+"_"+stage+".png")
func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio)
	for frame in 5: await process_frame
	for mode in ["2d","3d"]:
		studio.switch_mode(mode); var doc: RefCounted=studio.current(); var world: Node=studio.worlds[mode]; var ui: RefCounted=studio.ambience_tools; var runtime: Node=ui.managers[mode]; var context: RefCounted=ui.contexts[mode]
		mix(); check(runtime.voices.is_empty(),"Build mode is quiet unless the user enables preview: "+mode)
		var original: Dictionary=doc.data.duplicate(true); var history: int=doc.undo_history.size(); studio._command("ambience",null)
		ui.preview.button_pressed=true; ui.volume.value=80; ui.categories["birds"].value=0; ui.apply_settings()
		check(doc.undo_history.size()==history+1 and doc.data["ambience"]["volume"]==.8 and doc.data["ambience"]["preview_in_build"],"City mix controls create one persistent Undo transaction: "+mode)
		var fountain: Dictionary=Plan.emitters(doc.data,studio.library).filter(func(item: Dictionary)->bool:return item["kind"]=="fountain")[0]
		aim(fountain["position"],mode); mix(); check(runtime.selected.any(func(item: Dictionary)->bool:return item["kind"]=="fountain") and runtime.selected.all(func(item: Dictionary)->bool:return item["kind"]!="birds"),"Build preview listens at the view centre and obeys category levels: "+mode)
		var rebuilds: int=context.rebuilds; var actors: Dictionary=runtime.voices.duplicate(); aim(fountain["position"]+Vector3(4,0,0),mode); mix()
		check(context.rebuilds==rebuilds and actors.keys().all(func(uid: String)->bool:return not runtime.voices.has(uid) or runtime.voices[uid]["player"]==actors[uid]["player"]),"Moving the view updates audio without rescanning room content or restarting voices: "+mode)
		var digest: String=studio.content_digest(); var count: int=doc.undo_history.size(); studio.control_settings.execute("ambience_mute"); mix(180)
		check(runtime.voices.is_empty() and ui.muted and studio.content_digest()==digest and doc.undo_history.size()==count,"The remappable mute shortcut silences audio without changing project content or history: "+mode)
		studio.control_settings.execute("ambience_mute"); aim(fountain["position"],mode); mix()
		var bindings: Dictionary=studio.control_settings.bindings.duplicate(true); studio.control_settings.bindings=studio.control_settings.default_bindings()
		var assigned: String=studio.control_settings.assign("ambience_mute",0,KEY_F9); ui.refresh()
		check(assigned.is_empty() and ui.mute_button.tooltip_text.contains("F9"),"Mute controls display the remapped shortcut rather than a fixed key: "+mode)
		var focus: Control=studio.get_viewport().gui_get_focus_owner()
		if focus: focus.release_focus()
		var key:=InputEventKey.new(); key.keycode=KEY_F9; key.pressed=true
		check(studio.control_settings.unhandled(key) and ui.muted and studio.content_digest()==digest,"The remapped physical key dispatches session mute without editing city content: "+mode)
		ui.toggle_mute(); studio.control_settings.bindings=bindings; studio.control_settings.persist(); ui.refresh()
		var fountain_item: Dictionary=doc.data["objects"].filter(func(item: Dictionary)->bool:return Plan.profile(item).get("kind","")=="fountain")[0]; var fountain_uid: String=fountain_item["uid"]
		studio.selected_uid=fountain_uid; studio.selected_uids.assign([fountain_uid]); ui.refresh(); choose(ui.source_kind,"none"); ui.apply_selected(); mix(180)
		check(runtime.selected.all(func(item: Dictionary)->bool:return item["uid"]!="city:"+fountain_uid) and doc.object(fountain_uid)["audio"]["kind"]=="none","Selected source controls can silence an automatic fountain: "+mode)
		studio._command("undo",null); aim(fountain["position"],mode); mix(); check(runtime.selected.any(func(item: Dictionary)->bool:return item["uid"]=="city:"+fountain_uid),"Source Undo restores the actual audible fountain: "+mode)
		studio.selected_uid=fountain_uid; studio.selected_uids.assign([fountain_uid]); ui.refresh(); choose(ui.source_kind,"birds"); ui.source_volume.value=125; ui.source_range.value=40; ui.apply_selected()
		check(Plan.profile(doc.object(fountain_uid))["kind"]=="birds" and doc.object(fountain_uid)["audio"]["range"]==40,"An ordinary object can be assigned another sound type, level and range: "+mode)
		ui.restore_selected(); check(not doc.object(fountain_uid).has("audio"),"Restore automatic sound removes explicit source overrides: "+mode)
		var host: Dictionary=doc.data["objects"].filter(func(item: Dictionary)->bool:return studio.library.assets[item["asset"]]["behavior"].get("building",false))[0]; var host_uid: String=host["uid"]
		studio.interior_tools.start(host_uid); var room_doc: RefCounted=studio.current(); var floors: RefCounted=studio.interior_tools.floor_tools
		room_doc.data["objects"]=[]; floors.new_name.text="Audio upstairs"; floors.new_height.value=3; floors.add_floor(); var top: String=room_doc.floor_uid
		var item: Dictionary=room_doc.add("2d:Sofa_Teal",[-16,-56,0] if mode=="2d" else [-4,0,-3],studio.library.directions("2d:Sofa_Teal")[0]); var room_uid: String=item["uid"]; studio.changed(); studio.selected_uid=room_uid; studio.selected_uids.assign([room_uid]); ui.show(); choose(ui.source_kind,"fountain"); ui.source_range.value=24; ui.apply_selected()
		check(ui.apply_mix.disabled and room_doc.object(room_uid)["audio"]["kind"]=="fountain","Room editing permits localized sound authoring while keeping city-mix ownership clear: "+mode)
		studio._command("undo",null); check(not room_doc.object(room_uid).has("audio"),"Room source edits use the shared floor history: "+mode); studio._command("redo",null)
		floors.commit(Floors.put_record(room_doc.canonical.data,"floor_links",{"uid":"audio_stairs","kind":"stairs","lower":"ground","upper":top,"start":[-3,0],"end":[2,0],"width":1.4}),top)
		studio.set_walking(true); await settle(); mix(180)
		var walking_bindings: Dictionary=studio.control_settings.bindings.duplicate(true); studio.control_settings.bindings=studio.control_settings.default_bindings(); var mute_key:=InputEventKey.new(); mute_key.keycode=KEY_M; mute_key.pressed=true
		check(studio.control_settings.unhandled(mute_key) and ui.muted,"The actual mute key remains available during connected Walk: "+mode)
		if ui.muted: ui.toggle_mute()
		studio.control_settings.bindings=walking_bindings; mix(180)
		check(world.exploration.preview and world.exploration.active_floor()==top and context.last_listener.y>=3,"Connected editor Walk uses the actual upstairs listening height: "+mode)
		check(runtime.selected.any(func(value: Dictionary)->bool:return value["kind"]=="interior") and runtime.voices.keys().all(func(uid: String)->bool:return uid.begins_with("room:"+host_uid+":"+top+":")),"Only the active upstairs room and its localized sources remain audible after transition: "+mode)
		if mode=="2d":
			world.player.teleport_to(preload("res://scripts/builder/grid_fit.gd").pixels(Vector2(2,0))); world.exploration.interact()
			for frame in 40: await physics_frame
			var travel: Dictionary=world.exploration.interior.floor_stack.travel
			check(not travel.is_empty(),"The audio probe reaches actual projected stair travel")
			if not travel.is_empty():
				var path: Vector2=travel["path_end"]-travel["start"]; var progress: float=clampf((world.player.position-travel["start"]).dot(path)/path.length_squared(),0,1); mix(1)
				check(absf(context.last_listener.y-(3+float(travel["rise"])*progress+1.2))<.01,"The listener follows intermediate 2D stair height rather than staying on its source floor")
		studio.set_walking(false); studio.interior_tools.leave(); aim(fountain["position"],mode); mix(180)
		check(runtime.voices.keys().all(func(uid: String)->bool:return uid.begins_with("city:")),"Leaving the room retires its sources and restores exterior audio: "+mode)
		doc.checkpoint(); preload("res://scripts/builder/roads.gd").paint(doc.data,Vector2i(-4,10),Vector2i(4,10)); doc.data["traffic"]={"enabled":true,"population":2,"seed":19311}; doc.finish_checkpoint(); studio.changed(); studio.traffic_tools.tick(.1); await settle()
		var traffic: Node=studio.traffic_tools.managers[mode]; check(not traffic.vehicles.is_empty(),"The moving-audio fixture spawns actual road traffic: "+mode)
		if not traffic.vehicles.is_empty():
			var vehicle: Dictionary=traffic.vehicles[0]; var node: Node=vehicle["actor"]; var point: Vector3=node.position if mode=="3d" else Plan.point([node.position.x,node.position.y,0],mode); aim(point,mode); mix()
			var uid: String="vehicle:"+str(node.get_instance_id()); check(runtime.selected.any(func(value: Dictionary)->bool:return value["uid"]==uid and value["kind"]=="traffic"),"Traffic ambience follows an actual moving vehicle's source identity: "+mode)
			var first: Vector3=runtime.voices[uid]["player"].position
			for frame in 40: await physics_frame
			mix(); check(runtime.voices.has(uid) and runtime.voices[uid]["player"].position.distance_to(first)>.1,"Moving vehicles update native emitter positions without voice recreation: "+mode)
			vehicle["phase"]="parked"; vehicle["timer"]=100; mix(180); check(not runtime.voices.has(uid),"Parked vehicles fade out their motor ambience: "+mode)
		ui.show(); await capture(mode,"panel")
		var original_size: Vector2i=root.size; studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true,"shape_markers":true}); root.size=Vector2i(960,640); ui.show(); await process_frame; await capture(mode,"accessible")
		check(ui.page.get_global_rect().end.x<=960 and ui.page.get_global_rect().position.x>=0 and ui.page.get_v_scroll_bar().max_value>ui.page.size.y,"Audio controls remain in the scrollable inspector at the minimum viewport with enlarged text: "+mode)
		studio.accessibility_settings.restore({}); root.size=original_size
		var path: String="res://output/ambience_"+mode; check(studio.write_project(path+".isocity.json"),"The project store saves global and owned-room source settings: "+mode)
		var repair=preload("res://scripts/builder/project_repair.gd").new(studio.library); var loaded: Dictionary=repair.read(path+".isocity.json"); check(loaded["ok"] and repair.issues.is_empty() and loaded["content"]["documents"][mode]["ambience"]["volume"]==.8,"Reopening retains audio controls without repairs: "+mode)
		var loaded_host: Dictionary=loaded["content"]["documents"][mode]["objects"].filter(func(value: Dictionary)->bool:return value["uid"]==host_uid)[0]
		check(Floors.room(loaded_host["interior"],top)["objects"][0]["audio"]["kind"]=="fountain","Reopening retains audio overrides on their owned upstairs object: "+mode)
		studio.show_file_dialog("export"); studio.file_dialog.hide(); studio._file_selected(path+".tscn"); studio._command("export_portable",null); studio.file_dialog.hide(); studio._file_selected(path+".zip")
		check(FileAccess.file_exists(path+".tscn") and FileAccess.file_exists(path+".zip"),"Both actual export actions package the integrated audio city: "+mode)
		var broken: Dictionary=doc.data.duplicate(true); broken["ambience"]["volume"]=9; broken["objects"][0]["audio"]={"kind":"bad","range":-1,"volume":.5}
		check(not preload("res://scripts/builder/document.gd").valid(broken,mode,studio.library),"Project validation rejects damaged audio controls: "+mode)
		var fixer=preload("res://scripts/builder/project_repair.gd").new(studio.library); var fixed: Dictionary=fixer.world(broken,mode,"city",0)
		check(preload("res://scripts/builder/document.gd").valid(fixed,mode,studio.library) and fixed["ambience"]["birds"]==0 and fixed["objects"][0]["audio"]["volume"]==.5 and fixed["objects"].size()==broken["objects"].size(),"Audio repair retains valid controls, objects and owned content: "+mode)
		ui.reset(); studio.switch_mode("3d" if mode=="2d" else "2d"); check(runtime.voices.is_empty(),"Dimension changes release the previous world's audio: "+mode)
	studio.ambience_tools.reset(); studio.free(); OS.delay_msec(120); await process_frame
	print("AMBIENCE WORKFLOW: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
