extends SceneTree
const Fit=preload("res://scripts/builder/grid_fit.gd")
const Plan=preload("res://scripts/builder/floor_plan.gd")
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
func move(player: Node,mode: String,direction: int,frames: int) -> void:
	player.set_physics_process(false)
	for frame in frames:
		await physics_frame
		player.move_character(1.0/60,Fit.pixels(Vector2(0,direction)).normalized() if mode=="2d" else Vector3(0,0,direction))
	await process_frame
func stop(player: Node,mode: String) -> void:
	for frame in 15:
		await physics_frame; player.move_character(1.0/60,Vector2.ZERO if mode=="2d" else Vector3.ZERO)
	await process_frame
func wait_lift(lift: Node) -> void:
	for frame in 4000:
		await physics_frame
		if lift.phase in ["idle","blocked"]: break
	await process_frame
func floor_button(lift: Node,uid: String) -> void:
	for button in lift.choices.get_children():
		if button is Button and button.get_meta("floor_uid","")==uid: button.pressed.emit(); return
	check(false,"Elevator floor button exists")
func capture(mode: String,stage: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	for frame in 5: await process_frame
	RenderingServer.force_draw(false); RenderingServer.force_draw(false); root.get_texture().get_image().save_png("res://output/floor_elevator_"+mode+"_"+stage+".png")
func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio)
	for frame in 5: await process_frame
	for mode in ["2d","3d"]:
		studio.switch_mode(mode); var city: RefCounted=studio.current()
		var host: Dictionary=city.data["objects"].filter(func(item: Dictionary)->bool:return studio.library.assets[item["asset"]]["behavior"].get("building",false))[0]; var host_uid: String=host["uid"]
		studio.interior_tools.start(host_uid); var doc: RefCounted=studio.current(); doc.data["objects"]=[]; doc.data["exit"]=[-100,80,0] if mode=="2d" else [-4,0.1,2.5]
		var floors: RefCounted=studio.interior_tools.floor_tools; floors.new_name.text="Middle"; floors.new_height.value=3; floors.add_floor(); var middle: String=doc.floor_uid
		floors.new_name.text="Top"; floors.new_height.value=32 if mode=="2d" else 6; floors.add_floor(); var top: String=doc.floor_uid
		var ui: RefCounted=floors.connections; ui.show(); ui.kind.select(1); ui.update_kind(); choose(ui.lower,"ground"); choose(ui.upper,top); ui.start_x.value=0; ui.start_z.value=0; ui.width.value=1.4
		check(not ui.end_x.get_parent().visible and ui.end_x.value==0 and ui.end_z.value==0,"Elevator authoring locks both endpoints to one shaft: "+mode)
		press(ui.dialog,"Apply elevator"); var uid: String=ui.selected_uid
		check(Plan.valid(doc.canonical.data) and doc.canonical.data["floor_links"][0]["kind"]=="elevator" and doc.canonical.data["floor_links"][0]["upper"]==top,"Controls create a range-spanning elevator with intermediate stops: "+mode)
		ui.dialog.hide(); studio._command("undo",null); check(doc.canonical.data.get("floor_links",[]).is_empty(),"Elevator creation is undoable: "+mode)
		studio._command("redo",null); check(doc.canonical.data["floor_links"][0]["uid"]==uid,"Redo restores the same elevator identity: "+mode)
		ui.show(); ui.new_record(); ui.start_x.value=0; ui.start_z.value=0; choose(ui.lower,"ground"); choose(ui.upper,top); press(ui.dialog,"Apply elevator")
		check(doc.canonical.data["floor_links"].size()==1 and ui.message.text.contains("separate space"),"Overlapping cabins are rejected with a repairable authoring explanation: "+mode)
		ui.load_record(uid); await capture(mode,"editor"); ui.dialog.hide(); studio.interior_tools.leave(); var authored: Dictionary=city.data.duplicate(true)
		check(preload("res://scripts/builder/exporter.gd").save_scene(studio.worlds[mode],city.data,studio.library,"res://output/floor_elevator_"+mode+".tscn")==OK,"The elevator authoring workflow exports a playable scene: "+mode)
		check(preload("res://scripts/builder/portable_export.gd").new().save(studio.worlds[mode],city.data,studio.library,"res://output/floor_elevator_"+mode+".zip")["ok"],"The elevator authoring workflow creates a portable package: "+mode)
		studio.set_walking(true)
		var world: Node=studio.worlds[mode]; var player: Node=world.player; var exploration: Node=world.exploration; var parent: Node=player.get_parent()
		player.teleport_to(exploration.entrance(world.instances[host_uid])); exploration.interact()
		for frame in 3: await physics_frame
		var stack: Node=exploration.interior.floor_stack; var lift: Node=stack.lifts[uid]
		check(lift.stops.size()==3 and lift.last_stop=="ground","The explored UI-authored elevator includes the intermediate floor: "+mode)
		player.teleport_to(Fit.pixels(Vector2(0,2.5)) if mode=="2d" else Vector3(0,0.05,2.5)); await move(player,mode,-1,40); await stop(player,mode)
		check(lift.view.fully_inside(),"The character walks through the open gate into the cabin: "+mode)
		player.set_physics_process(true); exploration.interact()
		check(lift.menu.visible and studio.modal_visible() and not player.is_physics_processing(),"The floor chooser captures control and blocks canvas shortcuts: "+mode)
		lift.choose("missing_floor"); check(lift.menu.visible and not lift.rider,"An invalid destination cannot strand a passenger outside the chooser: "+mode)
		exploration.interact(); lift.cancel_menu(); check(player.is_physics_processing() and not lift.menu.visible,"Repeated E and cancellation preserve the original control state: "+mode)
		exploration.interact(); var escape:=InputEventKey.new(); escape.keycode=KEY_ESCAPE; escape.pressed=true; lift._unhandled_key_input(escape)
		check(not lift.menu.visible and player.is_physics_processing(),"Escape cancels the floor chooser and returns control: "+mode)
		exploration.interact(); await capture(mode,"chooser"); floor_button(lift,middle); await wait_lift(lift)
		if lift.phase!="idle": print("LIFT WORKFLOW STATE: ",mode," ",lift.phase," ",lift.notice)
		check(lift.phase=="idle" and lift.last_stop==middle and exploration.active_floor()==middle,"The cabin reaches the selected intermediate floor: "+mode)
		check(player.is_physics_processing() and player.recovery_count==0,"Arrival restores player control without recovery: "+mode)
		if mode=="2d": check(player.terrain_visual_offset==Vector2.ZERO,"A 2D floor transfer clears the cabin's travel elevation")
		await capture(mode,"middle"); await move(player,mode,1,36); await stop(player,mode)
		check(not lift.view.fully_inside() and lift.view.near(),"The character exits to the landing and can reach its call panel: "+mode)
		lift.request(top); await wait_lift(lift); check(lift.last_stop==top and exploration.active_floor()==middle,"An empty cabin trip preserves the waiting character's floor: "+mode)
		exploration.interact(); await wait_lift(lift); check(lift.last_stop==middle,"The landing call returns the cabin: "+mode)
		await move(player,mode,-1,36); await stop(player,mode); player.set_physics_process(true); exploration.interact(); floor_button(lift,"ground"); await wait_lift(lift)
		check(lift.last_stop=="ground" and exploration.active_floor()=="ground" and player.recovery_count==0,"The elevator supports a full round trip: "+mode)
		if mode=="2d":
			var middle_room: Dictionary=Plan.room(city.object(host_uid)["interior"],middle); var landing: Vector2=Fit.pixels(Vector2(0,1.65))
			middle_room["objects"].append({"uid":"blocked_exit","asset":"2d:Door_White","position":[landing.x,landing.y-8,0],"direction":"SE","scale":1.0,"open":false})
			exploration.interact(); floor_button(lift,middle); await wait_lift(lift)
			check(lift.phase=="blocked" and exploration.active_floor()=="ground" and lift.notice.contains("Landing blocked"),"A blocked 2D landing restores the source room and keeps gates closed")
			exploration.interact(); await wait_lift(lift)
			check(lift.phase=="idle" and lift.last_stop=="ground" and player.is_physics_processing() and player.terrain_visual_offset==Vector2.ZERO,"Returning from a blocked 2D landing restores normal controls and visual height")
			middle_room["objects"].clear()
			exploration.interact(); floor_button(lift,top)
			for frame in 2000:
				await physics_frame
				if lift.height>=28: break
			await process_frame
			check(lift.rider and lift.phase=="moving" and player.terrain_visual_offset.y<0,"The 2D cabin and passenger visibly rise while between floors")
			check(lift.height>=28 and world.camera.position.distance_to(player.position+player.terrain_visual_offset)<8,"The editor camera keeps a long elevator trip's visible passenger in view")
			studio.set_walking(false)
			check(exploration.interior==null and player.is_physics_processing() and player.terrain_visual_offset==Vector2.ZERO and not player.has_meta("floor_travel_height"),"Stopping a 2D ride releases movement and presentation state")
		check(city.data==authored,"Calls, rides and cancellations preserve the authored project: "+mode)
		exploration.leave_interior(); check(player.get_parent()==parent and player.is_physics_processing(),"Leaving restores the original character ownership and processing: "+mode)
		studio.set_walking(false)
	studio.queue_free(); await process_frame
	print("FLOOR ELEVATOR WORKFLOW: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
