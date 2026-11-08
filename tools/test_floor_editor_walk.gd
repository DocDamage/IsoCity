extends SceneTree
const Plan=preload("res://scripts/builder/floor_plan.gd")
const Fit=preload("res://scripts/builder/grid_fit.gd")
var checks: int=0
var failures: int=0
var studio: Control
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for frame in 4: await physics_frame
	await process_frame
func move(player: Node,direction: Vector3,frames: int) -> void:
	player.set_physics_process(false)
	for frame in frames:
		await physics_frame; player.move_character(1.0/60,direction)
	await process_frame
func stairs(exploration: Node,player: Node,mode: String,upper: bool,index: int) -> void:
	var link: Dictionary=exploration.owned_room["floor_links"][index]; var raw: Array=link["end"] if upper else link["start"]; var height: float=exploration.interior.floor_stack.heights[link["upper"] if upper else link["lower"]]
	if mode=="2d":
		player.teleport_to(Fit.pixels(Vector2(raw[0],raw[1]))); studio.control_settings.execute("interact")
		for frame in 2000:
			await physics_frame
			if exploration.interior.floor_stack.travel.is_empty(): break
		await process_frame
	else:
		var direction:=Vector3(link["end"][0]-link["start"][0],0,link["end"][1]-link["start"][1]).normalized()*( -1 if upper else 1)
		player.teleport_to(Vector3(raw[0],height+.05,raw[1])-direction*.8); player.set_physics_process(false)
		var destination: Array=link["start"] if upper else link["end"]
		for frame in 160:
			await physics_frame; player.move_character(1.0/60,direction)
			if (player.position-Vector3(destination[0],player.position.y,destination[1])).dot(direction)>=.35: break
		await move(player,Vector3.ZERO,15); player.set_physics_process(true)
func wait_lift(lift: Node) -> void:
	for frame in 4000:
		await physics_frame
		if lift.phase in ["idle","blocked"]: break
	await process_frame
func floor_button(lift: Node,uid: String) -> void:
	for button in lift.choices.get_children():
		if button is Button and button.get_meta("floor_uid","")==uid: button.pressed.emit(); return
	check(false,"Floor choice exists")
func capture(mode: String,stage: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	for frame in 5: await process_frame
	RenderingServer.force_draw(false); RenderingServer.force_draw(false); root.get_texture().get_image().save_png("res://output/floor_editor_walk_"+mode+"_"+stage+".png")
func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio)
	for frame in 5: await process_frame
	for mode in ["2d","3d"]:
		studio.switch_mode(mode); var city: RefCounted=studio.current(); var before: Dictionary=city.data.duplicate(true)
		var host: Dictionary=city.data["objects"].filter(func(item: Dictionary)->bool:return studio.library.assets[item["asset"]]["behavior"].get("building",false))[0]; var host_uid: String=host["uid"]
		studio.interior_tools.start(host_uid); var doc: RefCounted=studio.current(); var floors: RefCounted=studio.interior_tools.floor_tools
		doc.data["objects"]=[]; doc.data["exit"]= [Fit.pixels(Vector2(-5,4)).x,Fit.pixels(Vector2(-5,4)).y,0] if mode=="2d" else [-5,.1,4]
		floors.new_name.text="Middle"; floors.new_height.value=3; floors.add_floor(); var middle: String=doc.floor_uid; doc.data["exit"]=doc.canonical.data["exit"].duplicate()
		floors.new_name.text="Top"; floors.new_height.value=6; floors.add_floor(); var top: String=doc.floor_uid; doc.data["exit"]=doc.canonical.data["exit"].duplicate()
		for floor in Plan.definitions(doc.canonical.data):
			floor["room"]["objects"]=[{"uid":"shared_door","asset":"2d:Door_White","position":[-16,-56,0] if mode=="2d" else [-4,0,-3],"direction":studio.library.directions("2d:Door_White")[0],"scale":1.0,"open":false}]
		var links: Array=[{"uid":"first","kind":"stairs","lower":"ground","upper":middle,"start":[-3,0],"end":[2,0],"width":1.4},{"uid":"second","kind":"stairs","lower":middle,"upper":top,"start":[2,2],"end":[-3,2],"width":1.4},{"uid":"lift","kind":"elevator","lower":"ground","upper":top,"start":[4,-4],"end":[4,-4],"width":1.4}]
		doc.finish_checkpoint(); doc.canonical.data["floor_links"]=links; studio.changed(); floors.switch_floor(middle)
		var authored: Dictionary=city.data.duplicate(true); var history_size: int=doc.undo_history.size(); var world: Node=studio.worlds[mode]; var exploration: Node=world.exploration; var player: Node=world.player; var parent: Node=player.get_parent(); var zoom: Vector2=world.camera.zoom if mode=="2d" else Vector2.ONE
		var build_view: Array=[] if mode=="2d" else [world.target,world.distance,world.yaw,world.pitch]
		studio.control_settings.execute("walk"); await settle()
		check(studio.walking and studio.interior_tools.editing() and exploration.preview and exploration.active_floor()==middle,"Walk directly from an upstairs editor opens the complete connected building: "+mode)
		check(player.is_visible_in_tree() and player.is_physics_processing() and not floors.row.visible and not world.objects.visible,"Walking keeps the real character visible and suspends the editing plane: "+mode)
		check(exploration.interior.floor_stack.lifts.size()==1 and exploration.interior.floor_stack.room["floor_links"].size()==3,"The editor walk includes its elevator and both separate stair flights: "+mode)
		check(doc.undo_history.size()==history_size and city.data==authored,"Entering connected Walk does not create a history entry or change city data: "+mode)
		await stairs(exploration,player,mode,false,1)
		check(exploration.active_floor()==top and player.recovery_count==0,"The second physical flight reaches the top floor directly from editor Walk: "+mode)
		studio.interior_tools.refresh(); studio.selection_inspector.tick_context()
		check(studio.interior_tools.caption.text.contains("Top") and studio.selection_inspector.breadcrumb.text.contains("Top"),"Editor Walk caption and breadcrumb follow the visited floor: "+mode)
		check(studio.title_input.text.contains("Top") and not studio.title_input.editable,"The walking title follows the visited floor without renaming the hidden editing floor: "+mode)
		await capture(mode,"top")
		if mode=="3d": world.yaw+=30; world.pitch-=10
		studio.control_settings.execute("walk")
		check(not studio.walking and exploration.interior==null and doc.floor_uid==top and studio.current()==doc,"Tab returns to editing the visited floor in the same shared document: "+mode)
		check(player.get_parent()==parent and player.is_physics_processing() and world.objects.visible and floors.row.visible,"Tab restores character ownership, control, visible editing plane and floor controls: "+mode)
		check(doc.undo_history.size()==history_size and city.data==authored,"Stair travel and returning to edit do not dirty shared content or history: "+mode)
		if mode=="2d": check(world.camera.zoom==zoom and player.terrain_visual_offset==Vector2.ZERO,"Returning to the 2D editor restores room zoom and clears travel height")
		else: check([world.target,world.distance,world.yaw,world.pitch]==build_view,"Returning to the 3D editor restores the prior build camera after walking orbit changes")
		studio.set_walking(true); await settle(); check(exploration.preview and exploration.active_floor()==top,"Walk resumes from the visited floor's local coordinates: "+mode)
		var door: Node=exploration.room_world().instances["shared_door"]; player.teleport_to(door.global_position+(Vector2(0,24) if mode=="2d" else Vector3(0,0,1.5))); studio.control_settings.execute("interact")
		check(Plan.room(doc.canonical.data,top)["objects"][0]["open"] and not Plan.room(doc.canonical.data,middle)["objects"][0]["open"] and not doc.canonical.data["objects"][0]["open"],"A door interaction edits the correct floor when all floors reuse its local UID: "+mode)
		check(doc.undo_history.size()==history_size+1 and doc.undo_history.back()["floor_uid"]==top,"Walking door changes use the same chronological floor history: "+mode)
		var saved_path: String="res://output/floor_editor_walk_"+mode+".isocity.json"; check(studio.write_project(saved_path) and not studio.dirty,"Saving during connected Walk persists the full owned building: "+mode)
		var loader=preload("res://scripts/builder/project_repair.gd").new(studio.library); var loaded: Dictionary=loader.read(saved_path)
		var saved_host: Dictionary=loaded["content"]["documents"][mode]["objects"].filter(func(item: Dictionary)->bool:return item["uid"]==host_uid)[0]
		if not loader.issues.is_empty(): print("EDITOR WALK REPAIR: ",loader.issues)
		check(loaded["ok"] and loader.issues.is_empty() and Plan.room(saved_host["interior"],top)["objects"][0]["open"] and saved_host["interior"]["floor_links"].size()==3,"Project reopening retains the preview's actual upper-floor door and all connections: "+mode)
		studio.show_file_dialog("export"); check(studio.file_dialog.title.contains("city and owned interiors"),"The export dialog identifies the complete city scope while editing an owned room: "+mode); studio.file_dialog.hide()
		var scene_path: String="res://output/floor_editor_walk_"+mode+".tscn"; studio._file_selected(scene_path)
		var exported: Node=load(scene_path).instantiate(); var exported_host: Dictionary=exported.studio_data["objects"].filter(func(item: Dictionary)->bool:return item["uid"]==host_uid)[0]
		check(exported_host["interior"]["floor_links"].size()==3 and Plan.room(exported_host["interior"],top)["objects"][0]["open"] and exported.studio_data.get("interior_room",false)==false,"Export scene from a connected editor walk includes the full city and every owned floor: "+mode)
		if mode=="3d": check(exported.get_node("Foundation").collision_layer==2 and exported.find_children("*","WorldEnvironment",true,false)[0].environment!=null,"Export rebuilds exterior support and lighting independently of the suspended editor plane")
		else: check(exported.get_node("Ground").visible,"Export restores the city's ground independently of the hidden room editor")
		exported.free()
		studio._command("export_portable",null); check(studio.file_dialog.title.contains("city and owned interiors"),"Portable export identifies the complete city scope: "+mode); studio.file_dialog.hide(); studio._file_selected("res://output/floor_editor_walk_"+mode+".zip")
		check(FileAccess.file_exists("res://output/floor_editor_walk_"+mode+".zip") and studio.status.text.contains("exported"),"Portable ZIP can be created directly from connected editor Walk: "+mode)
		check(studio.walking and exploration.preview and exploration.active_floor()==top and player.is_physics_processing() and not world.objects.visible and doc.undo_history.size()==history_size+1,"Both exports preserve the active walking visit, controls and history: "+mode)
		studio._command("undo",null); check(not studio.walking and doc.floor_uid==top and not doc.data["objects"][0]["open"],"Undo from Walk safely returns to edit and reverts its upstairs door: "+mode)
		studio._command("redo",null); check(doc.data["objects"][0]["open"] and doc.floor_uid==top,"Redo restores the same upstairs edit: "+mode)
		# Empty-cabin call followed by a passenger trip in the editor's runtime.
		studio.set_walking(true); await settle(); var lift: Node=exploration.interior.floor_stack.lifts["lift"]
		player.teleport_to(Fit.pixels(Vector2(4,-2.35)) if mode=="2d" else Vector3(4,6.05,-2.35)); studio.control_settings.execute("interact"); await wait_lift(lift)
		check(lift.last_stop==top and exploration.active_floor()==top,"A landing call brings the elevator to the floor being tested: "+mode)
		player.teleport_to(Fit.pixels(Vector2(4,-4)) if mode=="2d" else Vector3(4,6.05,-4)); studio.control_settings.execute("interact")
		check(lift.menu.visible and studio.modal_visible(),"The editor's elevator chooser captures normal shortcuts: "+mode)
		floor_button(lift,"ground"); await wait_lift(lift)
		check(lift.last_stop=="ground" and exploration.active_floor()=="ground" and player.is_physics_processing() and player.recovery_count==0,"The editor elevator reaches ground and releases control without recovery: "+mode)
		await stairs(exploration,player,mode,false,0); check(exploration.active_floor()==middle,"The first flight connects ground to the middle floor during the same walk: "+mode)
		await stairs(exploration,player,mode,false,1); check(exploration.active_floor()==top and player.recovery_count==0,"Two successive flights reach the top without restarting the visit: "+mode)
		studio.set_walking(false); check(doc.floor_uid==top,"Stopping after several connections retains the final editing floor: "+mode)
		# Cancel while using the chooser and while the lift is in motion.
		floors.switch_floor("ground"); studio.set_walking(true); await settle(); lift=exploration.interior.floor_stack.lifts["lift"]
		player.teleport_to(Fit.pixels(Vector2(4,-4)) if mode=="2d" else Vector3(4,.05,-4)); studio.control_settings.execute("interact"); studio.set_walking(false)
		check(doc.floor_uid=="ground" and player.is_physics_processing() and exploration.interior==null,"Leaving an open elevator chooser restores editing control: "+mode)
		studio.set_walking(true); await settle(); lift=exploration.interior.floor_stack.lifts["lift"]; player.teleport_to(Fit.pixels(Vector2(4,-4)) if mode=="2d" else Vector3(4,.05,-4)); studio.control_settings.execute("interact"); floor_button(lift,top)
		for frame in 60: await physics_frame
		check(lift.phase=="moving" and lift.rider,"The cancellation probe reaches actual elevator motion: "+mode)
		studio.set_walking(false)
		check(doc.floor_uid=="ground" and player.is_physics_processing() and exploration.interior==null and (player.terrain_visual_offset==Vector2.ZERO if mode=="2d" else true),"Stopping mid-ride restores the source-floor editing plane and clears travel control: "+mode)
		studio.set_walking(true); await settle(); check(exploration.preview and not exploration.entering,"The safe source landing supports immediately restarting Walk: "+mode)
		# Cancelling a stair flight returns to its source instead of an airborne
		# position that the flat editing plane cannot represent.
		if mode=="2d":
			player.teleport_to(Fit.pixels(Vector2(-3,0))); studio.control_settings.execute("interact")
			for frame in 12: await physics_frame
			check(not exploration.interior.floor_stack.travel.is_empty(),"The cancellation probe reaches actual 2D stair travel")
		else:
			player.teleport_to(Vector3(-3.8,.05,0)); await move(player,Vector3.RIGHT,35); player.set_physics_process(true)
			check(player.position.y>.5 and player.position.y<2.8,"The cancellation probe reaches the middle of a physical 3D flight")
		studio.set_walking(false)
		check(doc.floor_uid=="ground" and player.is_physics_processing() and exploration.interior==null,"Stopping mid-flight restores a safe source-floor editing position: "+mode)
		studio.set_walking(true); await settle(); check(exploration.preview and player.recovery_count==0,"A cancelled flight can be followed immediately by another connected walk: "+mode)
		lift=exploration.interior.floor_stack.lifts["lift"]; player.teleport_to(Fit.pixels(Vector2(4,-4)) if mode=="2d" else Vector3(4,.05,-4)); studio.control_settings.execute("interact"); floor_button(lift,top)
		for frame in 60: await physics_frame
		check(lift.rider and lift.phase=="moving","The Home probe reaches a real elevator trip: "+mode)
		studio._command("home",null); await settle()
		var reset_point: Variant=studio.interior_tools.exit_point()
		var at_home: bool=player.position.distance_to(reset_point)<.01 if mode=="2d" else Vector2(player.position.x,player.position.z).distance_to(Vector2(reset_point.x,reset_point.z))<.01 and absf(player.position.y-reset_point.y)<.15
		check(studio.walking and exploration.preview and exploration.active_floor()=="ground" and player.is_physics_processing() and at_home,"Home safely closes transit ownership before restarting on its source floor: "+mode)
		studio.set_walking(false)
		# Reject a real obstruction during the initial collision-registration wait.
		studio.set_walking(true)
		var blocker: Node=StaticBody2D.new() if mode=="2d" else StaticBody3D.new(); blocker.collision_layer=1; exploration.room_world().add_child(blocker)
		var shape: Node=CollisionShape2D.new() if mode=="2d" else CollisionShape3D.new()
		if mode=="2d": shape.shape=CircleShape2D.new(); shape.shape.radius=12; blocker.global_position=player.global_position
		else: shape.shape=BoxShape3D.new(); shape.shape.size=Vector3(1,2,1); blocker.global_position=player.global_position+Vector3.UP
		blocker.add_child(shape); await settle()
		check(not studio.walking and exploration.interior==null and player.is_physics_processing() and studio.status.text.contains("blocked"),"A blocked walking start returns to Build with an explanation and usable controls: "+mode)
		studio.set_walking(true); studio.set_walking(false); await settle()
		check(not studio.walking and exploration.interior==null and not exploration.entering and player.is_physics_processing(),"An immediate return to Build invalidates the pending start callback: "+mode)
		studio.set_walking(true); await settle()
		# A normal EXIT returns to the city and ends this single owned-room visit.
		player.teleport_to(exploration.exit_position); studio.control_settings.execute("interact")
		check(not studio.interior_tools.editing() and studio.current()==city and studio.walking and exploration.interior==null,"The normal ground EXIT commits editor changes and returns to city walking: "+mode)
		studio.set_walking(false); check(city.undo() and city.data==before,"The complete interior editing and walking visit remains one city Undo step: "+mode)
		check(city.redo() and Plan.room(city.object(host_uid)["interior"],top)["objects"][0]["open"],"City Redo restores all floors, links and the walking door edit: "+mode); studio.changed()
		var city_history: int=city.undo_history.size(); studio.interior_tools.start(host_uid,top); studio.set_walking(true); await settle(); studio.set_walking(false); studio.interior_tools.leave()
		check(city.undo_history.size()==city_history,"A no-edit connected walking visit leaves the city's undo history unchanged: "+mode)
		studio.interior_tools.start(host_uid,middle); doc=studio.current(); studio.set_walking(true); await settle(); await stairs(exploration,player,mode,false,1)
		var initial_night: bool=Plan.room(doc.canonical.data,top)["night"]; studio._command("night",null)
		var hidden_collisions: bool=true
		for body in world.objects.find_children("*","CollisionObject2D",true,false)+world.objects.find_children("*","CollisionObject3D",true,false): hidden_collisions=hidden_collisions and body.collision_layer==0
		var dimmed: bool=exploration.interior.lighting.color.is_equal_approx(Color(.48,.55,.78)) if mode=="2d" else is_equal_approx(exploration.interior.sun.light_energy,.15)
		check(Plan.room(doc.canonical.data,top)["night"]!=initial_night and Plan.room(doc.canonical.data,middle)["night"]==initial_night and not world.objects.visible and hidden_collisions and dimmed and studio.walking,"Day/Night lights the visited floor without reactivating hidden editor collisions: "+mode)
		studio._command("night",null); studio._command("home",null)
		var home: Array=Plan.room(doc.canonical.data,top)["exit"]; var home_point: Variant=Vector2(home[0],home[1]) if mode=="2d" else Vector3(home[0],home[1]+6,home[2])
		check(studio.walking and exploration.active_floor()==top and player.position.distance_to(home_point)<.01,"Home returns to the visited floor's own walking start: "+mode)
		studio.set_walking(false); studio._command("undo",null); studio._command("undo",null)
		check(doc.floor_uid==top and doc.undo_history.is_empty() and Plan.room(doc.canonical.data,top)["night"]==initial_night,"Walking lighting changes undo through the visited floor's normal history: "+mode)
		studio.interior_tools.leave()
		studio.interior_tools.start(host_uid,top); doc=studio.current(); floors=studio.interior_tools.floor_tools
		var exterior_entry: Dictionary={"uid":"top_exit","floor":top,"position":[12,6,12]}
		floors.commit(Plan.put_record(doc.canonical.data,"floor_entrances",exterior_entry),top); studio.set_walking(true); await settle()
		player.teleport_to(exploration.exit_position); studio.control_settings.execute("interact")
		var exterior_point: Variant=preload("res://scripts/builder/floor_entrances.gd").outside(world.instances[host_uid],city.object(host_uid),exterior_entry,mode,studio.library)
		check(not studio.interior_tools.editing() and studio.walking and exploration.interior==null and player.position.distance_to(exterior_point)<.01,"An upstairs exterior exit from editor Walk returns to its transformed city entrance: "+mode)
		studio.set_walking(false); studio.interior_tools.start(host_uid,top); studio.set_walking(true); await settle(); studio.switch_mode("3d" if mode=="2d" else "2d")
		check(not studio.interior_tools.editing() and exploration.interior==null and not exploration.preview and player.is_physics_processing() and studio.documents[mode]==city,"Changing workspace dimension releases the connected preview and restores the original city document: "+mode)
		studio.switch_mode(mode)
	studio.free(); print("FLOOR EDITOR WALK: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
