extends SceneTree
const Plan=preload("res://scripts/builder/prop_plan.gd")
const Floors=preload("res://scripts/builder/floor_plan.gd")
const Fit=preload("res://scripts/builder/grid_fit.gd")
var studio: Control
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for frame in 8: await physics_frame
	await process_frame
func capture(mode: String,stage: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	for frame in 5: await process_frame
	RenderingServer.force_draw(false); RenderingServer.force_draw(false); root.get_texture().get_image().save_png("res://output/props_workflow_"+mode+"_"+stage+".png")
func select(ids: Array) -> void:
	studio.selected_uids.assign(ids); studio.selected_uid=ids[-1] if not ids.is_empty() else ""; studio.prop_tools.stamp=0; studio.prop_tools.refresh()
func choose(field: OptionButton,value: String) -> void:
	for index in field.item_count:
		if field.get_item_metadata(index)==value: field.select(index); field.item_selected.emit(index); return
	check(false,"Authored option exists: "+value)
func label(value: String) -> void:
	studio.prop_tools.action_label.text=value; studio.prop_tools.action_label.text_changed.emit(value)
func fixture_item(asset: String,uid: String,mode: String,x: float,z: float) -> Dictionary:
	return {"uid":uid,"asset":asset,"position":[x*16,z*8,0] if mode=="2d" else [x,0,z],"direction":studio.library.directions(asset)[0],"scale":1.0}
func terrain(room: Dictionary,height: float) -> void:
	room["terrain"]={"enabled":true,"bounds":[-6,-6,12,12]}; room["terrain_vertices"]=[]; room["water_cells"]=[]
	for x in range(-6,7):
		for z in range(-6,7): room["terrain_vertices"].append({"cell":[x,z],"height":height})
func place(exploration: Node,uid: String) -> Dictionary:
	var context: Dictionary=Plan.context(exploration)
	for item in context["data"]["objects"]:
		if item["uid"]!=uid: continue
		var candidate: Dictionary=context.duplicate(false); candidate["item"]=item; candidate["node"]=context["instances"][uid]; candidate["profile"]=Plan.profile(item)
		var point: Variant=Plan.ground_point(candidate,exploration,"approach")
		exploration.player.teleport_to(exploration.player.get_parent().to_local(point)); exploration.player.set_physics_process(false)
		return candidate
	return {}
func change_floor(exploration: Node,uid: String) -> void:
	if exploration.dimension=="2d": exploration.interior.floor_stack.switch_floor(uid)
	else:
		var height: float=exploration.interior.floor_stack.heights[uid]; var passage: Array=exploration.owned_room["floor_links"][0]["end"]
		# Storey changes pass through an actual stair opening. A hill elsewhere
		# intentionally retains its owning floor even across vertical datums.
		exploration.player.teleport_to(Vector3(passage[0],height+.05,passage[1])); exploration.interior.floor_stack.update_visibility()
	exploration.props._physics_process(1.0/60)
	check(exploration.active_floor()==uid,"Stair opening changes to the requested storey: "+exploration.dimension+"/"+uid)
func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio); await settle()
	for mode in ["2d","3d"]:
		studio.switch_mode(mode); var city: RefCounted=studio.current(); var world: Node=studio.worlds[mode]; var ui: RefCounted=studio.prop_tools; var exploration: Node=world.exploration; var runtime: Node=exploration.props
		var assets: Dictionary={"switch":"2d:Floor_Lamp","appliance":"2d:Washing_Machine","swing":"2d:Swing_Set","slide":"2d:Playground_Slide","mixed":"3d:HanX_Park/Bench_Park"} if mode=="2d" else {"switch":"3d:HanX_Park/Lamp_Park","appliance":"3d:HanX_Shop/Vending_Machine","swing":"3d:HanX_School/Swing_Set","slide":"3d:HanX_School/Slide","mixed":"2d:Park_Bench"}
		for index in assets.size():
			var key: String=assets.keys()[index]; city.data["objects"].append(fixture_item(assets[key],"authored_"+key,mode,14+index*4,-7))
		studio.changed(); await settle(); var bench: Dictionary=city.data["objects"].filter(func(item: Dictionary)->bool:return Plan.profile(item).get("kind","")=="seat")[0]; var uid: String=bench["uid"]
		select([uid]); studio._command("props",null); check(ui.page.is_visible_in_tree(),"Command opens the actual Props inspector: "+mode)
		var history: int=city.undo_history.size(); label("Read outside"); ui.reach.value=2.5; ui.advanced.button_pressed=true; ui.point_checks["point"].button_pressed=true; ui.point_fields["point"][1].value=.6; ui.apply_settings()
		check(city.undo_history.size()==history+1 and city.object(uid)["prop"]["label"]=="Read outside" and is_equal_approx(city.object(uid)["prop"]["point"][1],.6),"Changed controls save one ordinary source-anchor transaction: "+mode)
		ui.apply_settings(); check(city.undo_history.size()==history+1,"Reapplying unchanged controls adds no history: "+mode)
		studio._command("undo",null); check(not city.object(uid).has("prop"),"Undo restores automatic interaction settings: "+mode); studio._command("redo",null)
		var mixed: Dictionary=city.object("authored_mixed"); mixed["prop"]={"kind":"seat","reach":1.4,"point":[.2,.7,.1]}; studio.changed(); select([uid,mixed["uid"]]); check(ui.caption.text.contains("differ"),"Mixed selections identify different authored settings: "+mode)
		label("Rest here"); ui.apply_settings()
		check(city.object(uid)["prop"]["reach"]==2.5 and mixed["prop"]["reach"]==1.4 and mixed["prop"]["point"]==[.2,.7,.1],"Editing only the action label preserves differing ranges and anchors: "+mode)
		mixed["locked"]=true; select([uid,mixed["uid"]]); ui.restore_selected(); check(not city.object(uid).has("prop") and mixed.has("prop"),"Restore automatic respects protected members of a selection: "+mode); mixed.erase("locked")
		select(["authored_switch"]); choose(ui.target,"authored_appliance"); ui.apply_settings(); check(city.object("authored_switch")["prop"]["target"]=="authored_appliance","Target dropdown authors a local appliance link: "+mode)
		check(ui.initially_on.disabled and ui.initially_on.tooltip_text.contains("target"),"Linked switches explain that starting power belongs to their target device: "+mode)
		ui.preview_selected(); await settle(); check(studio.walking and exploration.prompt().contains("switch"),"Explore selected prop positions the player for normal use: "+mode)
		var bindings: Dictionary=studio.control_settings.bindings.duplicate(true); var assigned: String=studio.control_settings.assign("interact",0,KEY_F9)
		var key:=InputEventKey.new(); key.keycode=KEY_F9; key.pressed=true
		check(assigned.is_empty() and studio.control_settings.unhandled(key) and runtime.states.get("city:authored_appliance",{}).get("on",false),"Actual remapped physical input activates a linked appliance: "+mode)
		check(not runtime.effects.entries["city:authored_switch"]["light"].visible and runtime.effects.entries["city:authored_appliance"]["light"].visible,"Linked power changes the target device without powering the controller's own lamp: "+mode)
		check(studio.control_settings.walk_hint(exploration.prompt()).contains("F9"),"Prop prompts display the remapped Interact key: "+mode)
		studio.control_settings.unhandled(key); studio.control_settings.bindings=bindings; studio.control_settings.persist(); studio.set_walking(false); select([uid])
		var blocker: Node=StaticBody2D.new() if mode=="2d" else StaticBody3D.new(); var blocking_shape: Node=CollisionShape2D.new() if mode=="2d" else CollisionShape3D.new(); blocker.collision_layer=1
		if mode=="2d": blocking_shape.shape=RectangleShape2D.new(); blocking_shape.shape.size=Vector2(200,200)
		else: blocking_shape.shape=BoxShape3D.new(); blocking_shape.shape.size=Vector3(10,4,10)
		blocker.add_child(blocking_shape); world.add_child(blocker); blocker.global_position=world.instances[uid].global_position; await settle()
		ui.preview_selected()
		check(not studio.walking and studio.status.text.contains("blocked"),"Explore refuses a fully blocked standing area without taking player control: "+mode+" · walking="+str(studio.walking)+" mask="+str(world.player.collision_mask)+" · "+studio.status.text)
		blocker.free(); await physics_frame; ui.preview_selected(); await settle(); world.player.set_physics_process(false); studio.control_settings.execute("interact")
		check(not runtime.active.is_empty() and runtime.active["item"]["uid"]==uid,"Default Interact seats the actual exterior character: "+mode)
		await capture(mode,"outside_seat"); studio.control_settings.execute("interact"); studio.set_walking(false)
		var host: Dictionary=city.data["objects"].filter(func(item: Dictionary)->bool:return studio.library.assets[item["asset"]]["behavior"].get("building",false))[0]; var host_uid: String=host["uid"]
		studio.interior_tools.start(host_uid); var room_doc: RefCounted=studio.current(); var floors: RefCounted=studio.interior_tools.floor_tools; room_doc.data["objects"]=[]
		var flat: Dictionary=fixture_item("2d:Park_Bench" if mode=="2d" else "3d:HanX_Park/Bench_Park","flat_seat",mode,0,0); room_doc.data["objects"]=[flat]; studio.changed(); await settle()
		var local_approach: Variant=Plan.anchor(world.instances["flat_seat"],flat,studio.library,mode,Plan.profile(flat),"approach"); var exit_values: Array=room_doc.data["exit"]; var exit_point: Variant=Vector2(exit_values[0],exit_values[1]) if mode=="2d" else Vector3(exit_values[0],exit_values[1],exit_values[2])
		var delta: Variant=exit_point-local_approach
		flat["position"]=[delta.x,delta.y,0] if mode=="2d" else [delta.x,delta.y,delta.z]; studio.changed(); studio.set_walking(true); await settle(); world.player.teleport_to(exit_point); world.player.set_physics_process(false); exploration.interact()
		check(not runtime.active.is_empty() and studio.interior_tools.at_exit(),"Flat-room seated fixture overlaps its editing exit: "+mode)
		check(runtime.active.get("scope","")=="room:"+host_uid+":ground:","Flat room-editor use belongs to its building rather than the city namespace: "+mode)
		studio.control_settings.execute("interact"); check(runtime.active.is_empty() and studio.interior_tools.editing(),"Interact releases an active prop before handling a flat-room editor exit: "+mode)
		studio.set_walking(false); room_doc.data["objects"]=[]
		floors.new_name.text="Props upstairs"; floors.new_height.value=3; floors.add_floor(); var top: String=room_doc.floor_uid
		for floor in Floors.definitions(room_doc.canonical.data):
			var room: Dictionary=floor["room"]
			room["exit"]=[0,-80,0] if mode=="2d" else [-5,.1,-5]
			room["objects"]=[fixture_item("2d:Park_Bench" if mode=="2d" else "3d:HanX_Park/Bench_Park","shared_bench",mode,-2,-2),fixture_item("2d:Floor_Lamp" if mode=="2d" else "3d:HanX_Park/Lamp_Bollard","shared_switch",mode,2,-2),fixture_item(assets["appliance"],"shared_appliance",mode,4,-2)]
			room["objects"][1]["prop"]={"target":"shared_appliance"}; room["objects"][2]["prop"]={"duration":1.5}
			if floor["uid"]==top:
				terrain(room,1)
				if mode=="3d":
					for item in room["objects"]: item["position"][1]=1.0
		room_doc.canonical.data["floor_links"]=[{"uid":"props_stairs","kind":"stairs","lower":"ground","upper":top,"start":[-3,3],"end":[2,3],"width":1.4}]; room_doc.finish_checkpoint(); studio.changed(); await settle(); select(["shared_bench"]); ui.show()
		history=room_doc.undo_history.size(); label("Upper reading seat"); ui.apply_settings()
		check(room_doc.undo_history.size()==history+1 and room_doc.undo_history.back()["floor_uid"]==top and Floors.room(room_doc.canonical.data,top)["objects"][0]["prop"]["label"]=="Upper reading seat" and not room_doc.canonical.data["objects"][0].has("prop"),"Owned-floor authoring changes only its own object in shared chronological history: "+mode)
		studio._command("undo",null); check(not room_doc.object("shared_bench").has("prop"),"Room Undo restores its automatic seat profile: "+mode); studio._command("redo",null)
		select(["shared_bench"]); ui.preview_selected(); await settle(); check(exploration.preview and exploration.active_floor()==top,"Explore selected prop from upstairs opens connected room Walk: "+mode)
		world.player.set_physics_process(false); studio.control_settings.execute("interact"); check(not runtime.active.is_empty() and runtime.active["scope"]=="room:"+host_uid+":"+top+":","Connected Walk uses the actual upstairs prop ownership: "+mode)
		var candidate: Dictionary=runtime.active; var point: Variant=Plan.global_point(candidate,exploration)
		check(point.y>3 if mode=="3d" else float(candidate["node"].get_meta("terrain_height",0))>.9,"Seat placement includes active room terrain and floor elevation: "+mode)
		await settle()
		if mode=="3d": check(is_equal_approx(world.player.body.global_position.y+.85,4.48),"The actual seated body uses the floor height plus one-metre terrain and seat surface")
		else:
			var sprite: Sprite2D=world.player.get_node("Sprite2D"); check(sprite.to_global(sprite.offset+world.player.origin_offset).distance_to(point+Vector2(0,.85*8))<.01,"Terrain presentation retains exact seated sprite alignment over multiple frames")
		await capture(mode,"upstairs_seat"); studio.control_settings.execute("interact"); place(exploration,"shared_switch"); studio.control_settings.execute("interact"); var upper_key: String="room:"+host_uid+":"+top+":shared_appliance"
		check(runtime.states.get(upper_key,{}).get("on",false),"Upstairs switch powers its own reused local appliance UID: "+mode)
		change_floor(exploration,"ground"); place(exploration,"shared_switch"); runtime._physics_process(1.0/60); var ground_key: String="room:"+host_uid+":ground:shared_appliance"
		check(not runtime.states.get(ground_key,{}).get("on",false),"Power state cannot leak to another floor with the same local UID: "+mode)
		place(exploration,"shared_bench"); studio.control_settings.execute("interact"); change_floor(exploration,top)
		check(runtime.active.is_empty() and world.player.collision_mask==(1 if mode=="2d" else 3),"Changing floors during use releases the old pose and collision lock: "+mode+" · floor="+exploration.active_floor()+" active="+str(runtime.active.get("scope",""))+" mask="+str(world.player.collision_mask))
		studio.set_walking(false); studio.interior_tools.leave(); await settle(); world.player.set_physics_process(true)
		var other: Dictionary=city.data["objects"].filter(func(item: Dictionary)->bool:return item["uid"]!=host_uid and studio.library.assets[item["asset"]]["behavior"].get("building",false))[0]
		other["interior"]=city.object(host_uid)["interior"].duplicate(true); studio.changed(); var authored: Dictionary=city.data.duplicate(true); var city_history: int=city.undo_history.size()
		studio.set_walking(true); var entry: Variant=exploration.entrance(world.instances[other["uid"]]); world.player.teleport_to(entry); studio.control_settings.execute("interact"); await settle()
		check(exploration.interior!=null and exploration.interior_uid==other["uid"],"Actual normal building entry opens a separate owned prop room: "+mode)
		place(exploration,"shared_switch"); runtime._physics_process(1.0/60); var other_key: String="room:"+other["uid"]+":ground:shared_appliance"
		check(not runtime.states.get(other_key,{}).get("on",false) and runtime.states.has(upper_key),"Reused prop IDs in another building cannot inherit the first building's power state: "+mode)
		exploration.leave_interior(); studio.set_walking(false); world.player.set_physics_process(true)
		check(city.data==authored and city.undo_history.size()==city_history,"Room entry, use-state isolation and return preserve authored building content/history: "+mode)
		select([uid]); ui.show(); var original_size: Vector2i=root.size; studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true,"shape_markers":true}); root.size=Vector2i(960,640); ui.show(); await settle()
		check(ui.panel.size.x<=ui.page.size.x+2 and ui.page.get_v_scroll_bar().max_value>ui.page.size.y,"Enlarged Props controls fit and scroll at 960×640: "+mode)
		await capture(mode,"accessible"); ui.page.ensure_control_visible(ui.preview_button); studio.accessibility_settings.root_scroll.ensure_control_visible(ui.preview_button); ui.preview_button.grab_focus(); await settle()
		check(Rect2(Vector2.ZERO,Vector2(root.size)).has_point(ui.preview_button.get_global_rect().get_center()) and ui.page.scroll_vertical>0,"Keyboard focus reaches the scrolled Props action controls at enlarged text size: "+mode)
		await capture(mode,"accessible_actions"); root.size=original_size; studio.accessibility_settings.restore({}); await settle()
		var path: String="res://output/props_"+mode; check(studio.write_project(path+".isocity.json"),"Ordinary saving retains city and owned-floor interactions: "+mode)
		var repair=preload("res://scripts/builder/project_repair.gd").new(studio.library); var loaded: Dictionary=repair.read(path+".isocity.json")
		check(loaded["ok"] and repair.issues.is_empty(),"Reopening authored props and terrain rooms requires no repair: "+mode)
		studio.show_file_dialog("export"); studio.file_dialog.hide(); studio._file_selected(path+".tscn"); studio._command("export_portable",null); studio.file_dialog.hide(); studio._file_selected(path+".zip")
		check(FileAccess.file_exists(path+".tscn") and FileAccess.file_exists(path+".zip"),"Both actual export actions create playable prop projects: "+mode)
	studio.free(); await process_frame; print("PROPS WORKFLOW: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
