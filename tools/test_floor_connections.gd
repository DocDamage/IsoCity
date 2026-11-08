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
func press(parent: Node,text: String) -> void:
	for button in parent.find_children("*","Button",true,false):
		if button.text==text: button.pressed.emit(); return
	check(false,"Button exists: "+text)
func choose(field: OptionButton,uid: String) -> void:
	for index in field.item_count:
		if field.get_item_metadata(index)==uid: field.select(index); return
	check(false,"Floor choice exists: "+uid)
func door(mode: String) -> Dictionary:
	var point: Vector2=Fit.pixels(Vector2(4,-2))
	return {"uid":"shared_door","asset":"2d:Door_White","direction":"SE","position":[point.x,point.y,0] if mode=="2d" else [4,0,-2],"scale":1.0,"open":false}
func wait_stairs(stack: Node) -> void:
	for frame in 900:
		await physics_frame
		if stack.travel.is_empty(): break
	await process_frame
func move_3d(player: Node,direction: Vector3,frames: int) -> void:
	for frame in frames:
		await physics_frame; player.move_character(1.0/60,direction)
	await process_frame
func capture(mode: String,stage: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	for frame in 5: await process_frame
	RenderingServer.force_draw(false); RenderingServer.force_draw(false); root.get_texture().get_image().save_png("res://output/floor_connections_"+mode+"_"+stage+".png")
func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio)
	for frame in 5: await process_frame
	for mode in ["2d","3d"]:
		studio.switch_mode(mode)
		var city: RefCounted=studio.current()
		var host: Dictionary=city.data["objects"].filter(func(item: Dictionary)->bool:return studio.library.assets[item["asset"]]["behavior"].get("building",false))[0]
		var host_uid: String=host["uid"]; studio.interior_tools.start(host_uid)
		var doc: RefCounted=studio.current(); var floors: RefCounted=studio.interior_tools.floor_tools
		doc.data["objects"].clear()
		check(floors.connections.button.disabled,"Stair authoring waits for an additional floor: "+mode)
		floors.new_name.text="Apartment"; floors.new_height.value=3; floors.add_floor()
		var upper_uid: String=doc.floor_uid; var ui: RefCounted=floors.connections
		ui.button.pressed.emit(); choose(ui.lower,"ground"); choose(ui.upper,upper_uid)
		ui.start_x.value=-2; ui.start_z.value=0; ui.end_x.value=3; ui.end_z.value=0; ui.width.value=1.2
		check(studio.modal_visible(),"Stair authoring dialog suppresses canvas shortcuts: "+mode)
		press(ui.dialog,"Apply staircase")
		var link_uid: String=ui.selected_uid
		check(Plan.valid(doc.canonical.data) and doc.canonical.data["floor_links"].size()==1,"Stair controls create a supported connection: "+mode)
		check(ui.list.item_count==1 and doc.canonical.data["floor_links"][0]["lower"]=="ground" and doc.canonical.data["floor_links"][0]["upper"]==upper_uid,"Connection list and stable floor IDs match the authored record: "+mode)
		ui.dialog.hide(); studio._command("undo",null)
		check(doc.canonical.data.get("floor_links",[]).is_empty(),"Stair creation is a single shared-history Undo step: "+mode)
		studio._command("redo",null)
		check(doc.canonical.data["floor_links"][0]["uid"]==link_uid,"Redo restores the same connection identity: "+mode)
		doc.canonical.data["floor_links"][0]["extension"]={"keep":true}; ui.show(); ui.load_record(link_uid); ui.width.value=1.4; press(ui.dialog,"Apply staircase")
		check(doc.canonical.data["floor_links"].size()==1 and doc.canonical.data["floor_links"][0]["width"]==1.4 and doc.canonical.data["floor_links"][0]["extension"]=={"keep":true},"Updating stairs preserves identity and extension metadata: "+mode)
		var history_size: int=doc.undo_history.size(); ui.end_x.value=-1; press(ui.dialog,"Apply staircase")
		check(doc.undo_history.size()==history_size and ui.message.text.contains("at least") and doc.canonical.data["floor_links"][0]["end"]==[3.0,0.0],"Invalid short runs preserve data/history and explain the needed clearance: "+mode)
		ui.end_x.value=3; ui.load_record(link_uid); press(ui.dialog,"Remove staircase"); ui.dialog.hide()
		check(doc.canonical.data["floor_links"].is_empty(),"Remove staircase deletes only its connection: "+mode)
		studio._command("undo",null)
		check(doc.canonical.data["floor_links"][0]["uid"]==link_uid,"Undo restores the removed staircase: "+mode)
		ui.show(); ui.load_record(link_uid); await capture(mode,"editor"); ui.dialog.hide()
		var original_size: Vector2i=root.size
		studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true,"shape_markers":true}); root.size=Vector2i(960,640)
		for frame in 8: await process_frame
		ui.show()
		for frame in 5: await process_frame
		check(ui.dialog.size.x<=960 and ui.dialog.size.y<=600,"Stair controls fit the minimum viewport with enlarged text and targets: "+mode)
		ui.dialog.hide(); studio.accessibility_settings.restore({}); root.size=original_size
		var ground_door: Dictionary=door(mode); ground_door["position"]=[-16,-56,0] if mode=="2d" else [-4,0,-3]
		doc.canonical.data["objects"]=[ground_door]; Plan.room(doc.canonical.data,upper_uid)["objects"]=[door(mode)]
		studio.changed(); studio.interior_tools.leave()
		check(preload("res://scripts/builder/exporter.gd").save_scene(studio.worlds[mode],city.data,studio.library,"res://output/floor_connections_"+mode+".tscn")==OK,"The authored connection workflow exports a playable scene: "+mode)
		check(preload("res://scripts/builder/portable_export.gd").new().save(studio.worlds[mode],city.data,studio.library,"res://output/floor_connections_"+mode+".zip")["ok"],"The authored connection workflow exports a portable package: "+mode)
		studio.set_walking(true)
		var world: Node=studio.worlds[mode]; var player: Node=world.player; var exploration: Node=world.exploration
		var original_parent: Node=player.get_parent(); var original_zoom: Vector2=world.camera.zoom if mode=="2d" else Vector2.ONE
		player.teleport_to(exploration.entrance(world.instances[host_uid])); exploration.interact()
		for frame in 3: await physics_frame
		check(exploration.interior!=null and player.is_visible_in_tree(),"Normal exploration opens the owned floors with a visible character: "+mode)
		if mode=="2d": check(world.camera.zoom==Vector2(2,2),"2D interiors use a readable room zoom")
		var stack: Node=exploration.interior.floor_stack
		if mode=="2d":
			player.teleport_to(Fit.pixels(Vector2(-2,0))); exploration.interact()
			check(not stack.travel.is_empty() and not player.is_physics_processing(),"Stair interaction starts controlled walking along the flight: 2d")
			for frame in 10: await physics_frame
			await process_frame
			check(not stack.travel.is_empty() and player.position.distance_to(Fit.pixels(Vector2(-2,0)))>2 and player.terrain_visual_offset.y<0,"2D stair travel visibly walks and rises along the flight before changing rooms")
			await wait_stairs(stack)
			check(stack.travel.is_empty() and stack.notice.is_empty() and exploration.active_floor()==upper_uid and player.position.distance_to(Fit.pixels(Vector2(3,0)))<0.1,"The 2D flight reaches its authored upper landing")
			check(player.is_physics_processing() and player.terrain_visual_offset==Vector2.ZERO,"Arrival restores ordinary movement and clears the stair visual offset")
		else:
			player.set_physics_process(false); player.teleport_to(Vector3(-4,0.05,0)); await move_3d(player,Vector3.RIGHT,115); await move_3d(player,Vector3.ZERO,15)
			check(exploration.active_floor()==upper_uid and player.position.y>2.95,"UI-authored stairs support actual 3D ascent")
		check(player.recovery_count==0,"Floor traversal does not invoke recovery: "+mode)
		var room: Node=exploration.room_world(); var node: Node=room.instances["shared_door"]
		player.teleport_to(node.global_position+(Vector2(0,24) if mode=="2d" else Vector3(0,0,1.5)))
		exploration.interact()
		check(Plan.room(city.object(host_uid)["interior"],upper_uid)["objects"][0]["open"] and not city.object(host_uid)["interior"]["objects"][0]["open"],"Upper door interaction persists in its own room despite a shared ground-floor UID: "+mode)
		exploration.interact()
		check(not Plan.room(city.object(host_uid)["interior"],upper_uid)["objects"][0]["open"],"Closing an upstairs door updates its current room: "+mode)
		await capture(mode,"upper")
		if mode=="2d":
			player.teleport_to(Fit.pixels(Vector2(3,0))); exploration.interact(); await wait_stairs(stack)
			check(exploration.active_floor()=="ground" and player.position.distance_to(Fit.pixels(Vector2(-2,0)))<0.1,"The same authored 2D flight supports descent")
			var owned: Dictionary=city.object(host_uid)["interior"]; var upper_door: Dictionary=Plan.room(owned,upper_uid)["objects"][0]; var old_position: Array=upper_door["position"].duplicate()
			var landing: Vector2=Fit.pixels(Vector2(3,0)); upper_door["position"]=[landing.x,landing.y,0]
			exploration.interact(); await wait_stairs(stack)
			check(exploration.active_floor()=="ground" and stack.notice.contains("landing blocked") and player.position.distance_to(Fit.pixels(Vector2(-2,0)))<0.1,"Blocked upper landings return the 2D character safely to the source floor")
			check(player.is_physics_processing() and player.recovery_count==0 and player.terrain_visual_offset==Vector2.ZERO,"Landing cancellation restores movement without recovery or a stale visual elevation")
			upper_door["position"]=old_position
			var blocker: Dictionary={"uid":"flight_blocker","asset":"2d:Door_White","position":[0,-8,0],"direction":"SE","scale":1.0,"open":false}
			owned["objects"].append(blocker); exploration.apply_room("ground")
			for frame in 3: await physics_frame
			exploration.interact(); await wait_stairs(stack)
			check(exploration.active_floor()=="ground" and stack.notice.contains("path blocked") and player.position.distance_to(Fit.pixels(Vector2(-2,0)))<0.1,"An obstructed 2D flight walks back to its entrance instead of passing through objects")
			check(player.is_physics_processing() and player.recovery_count==0,"Path cancellation restores ordinary movement without recovery")
			owned["objects"].erase(blocker); exploration.apply_room("ground")
			for frame in 3: await physics_frame
			player.teleport_to(Fit.pixels(Vector2(-1.75,0.75))); exploration.interact()
			check(not stack.travel.is_empty() and stack.travel["phase"]=="approach","Interacting beside a 2D staircase first approaches its actual entrance")
			await wait_stairs(stack)
			check(exploration.active_floor()==upper_uid and stack.notice.is_empty(),"The approach continues along the authored flight to its landing")
			player.teleport_to(Fit.pixels(Vector2(3,0))); exploration.interact(); await wait_stairs(stack)
		else:
			player.teleport_to(Vector3(4,3.05,0)); await move_3d(player,Vector3.LEFT,115); await move_3d(player,Vector3.ZERO,15)
			check(exploration.active_floor()=="ground" and absf(player.position.y)<0.05,"UI-authored 3D stairs support descent")
		player.teleport_to(exploration.exit_position); exploration.interact()
		check(exploration.interior==null and player.get_parent()==original_parent and player.is_visible_in_tree(),"Exit restores the original character parent, city and visibility: "+mode)
		if mode=="2d": check(world.camera.zoom==original_zoom,"Leaving the 2D room restores the exterior zoom")
		if mode=="2d":
			player.teleport_to(exploration.entrance(world.instances[host_uid])); exploration.interact(); stack=exploration.interior.floor_stack
			player.teleport_to(Fit.pixels(Vector2(-2,0))); exploration.interact()
			for frame in 4: await physics_frame
			studio.set_walking(false)
			check(exploration.interior==null and player.get_parent()==original_parent and player.is_physics_processing() and player.terrain_visual_offset==Vector2.ZERO,"Stopping Walk during stair travel releases control, visuals and character ownership")
		studio.set_walking(true); player.teleport_to(exploration.entrance(world.instances[host_uid])); exploration.interact()
		if mode=="2d":
			player.teleport_to(Fit.pixels(Vector2(-2,0))); exploration.interact(); await wait_stairs(exploration.interior.floor_stack)
		else:
			player.teleport_to(Vector3(-4,0.05,0)); await move_3d(player,Vector3.RIGHT,115); await move_3d(player,Vector3.ZERO,15)
		studio.interior_tools.refresh()
		check(studio.interior_tools.caption.text.contains("Apartment"),"The interior caption follows the physical active floor: "+mode)
		studio.interior_tools.edit_button.pressed.emit()
		check(studio.interior_tools.editing() and studio.current().floor_uid==upper_uid and not studio.current().object("shared_door").is_empty(),"Edit this room opens the visited upper floor directly: "+mode)
		studio.interior_tools.leave()
		player.set_physics_process(true); studio.set_walking(false)
	studio.queue_free(); await process_frame
	print("FLOOR CONNECTIONS: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
