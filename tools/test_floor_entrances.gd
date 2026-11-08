extends SceneTree

const Plan=preload("res://scripts/builder/floor_plan.gd")
const Entries=preload("res://scripts/builder/floor_entrances.gd")
const Factory=preload("res://scripts/builder/asset_instance.gd")
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
func settle() -> void:
	for frame in 4: await physics_frame
	await process_frame
func capture(mode: String,stage: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	for frame in 5: await process_frame
	RenderingServer.force_draw(false); RenderingServer.force_draw(false); root.get_texture().get_image().save_png("res://output/floor_entrances_"+mode+"_"+stage+".png")
func transforms() -> void:
	for source_mode in ["2d","3d"]:
		var id: String=""
		for candidate in studio.library.assets:
			if studio.library.assets[candidate]["mode"]==source_mode and studio.library.assets[candidate]["behavior"].get("building",false): id=candidate; break
		for mode in ["2d","3d"]:
			var node: Node=Factory.make(studio.library,id,mode); root.add_child(node)
			var directions: Array=studio.library.assets[id]["data"]["directions"].keys() if source_mode=="2d" else ["0","90","217"]
			for direction in directions:
				var item: Dictionary={"uid":"transform","asset":id,"direction":direction,"position":[0,0,0],"scale":1.0,"tilt":[11,-8]}
				Factory.pose(node,item)
				if mode=="2d": node.transform=Transform2D(.37,Vector2(123,-45)).scaled_local(Vector2.ONE*1.7)
				else: node.transform=Transform3D(Basis.from_euler(Vector3(.11,.37,-.08)).scaled(Vector3.ONE*1.7),Vector3(12,3,-7))*node.transform
				var raw:=Vector3(2,3,4); var entry: Dictionary={"uid":"upper","floor":"upper","position":[2,3,4]}; var expected: Variant
				if source_mode=="2d":
					if mode=="2d": expected=node.transform*(Fit.pixels(Vector2(2,4))+Vector2(0,-24))
					else:
						var foot: Array=studio.library.assets[id]["data"]["directions"][direction]["footprint"]
						expected=node.transform*Vector3(2-foot[0]*.5,3.02,4-foot[1]*.5)
				elif mode=="3d": expected=node.transform*raw
				else:
					var projected: Vector3=Basis.from_euler(Vector3(deg_to_rad(-30),deg_to_rad(45),0)).inverse()*(node.model.transform*raw)
					expected=node.transform*(Vector2(projected.x,-projected.y)*node.PIXELS_PER_UNIT)
				check(Entries.outside(node,item,entry,mode,studio.library).distance_to(expected)<.001,"Source entrance follows rotation, height, scale and source view: "+source_mode+"/"+mode+"/"+direction)
				if mode=="3d": node.transform=Transform3D.IDENTITY
			await process_frame; node.free()
	var filter_item: Dictionary={"asset":"2d:House_Blue","direction":"SE","interior":{"floor_entrances":[{"uid":"private","floor":"upper","position":[0,3,0],"view":"NE"},{"uid":"all","floor":"upper","position":[1,3,1]}]}}
	check(Entries.entries(filter_item).size()==2 and Entries.entries(filter_item)[1]["uid"]=="all","A sprite entrance is offered only in its authored source view; all-view entrances remain")
	filter_item["direction"]="NE"; check(Entries.entries(filter_item).size()==3,"Changing to the matching source view reveals its floor entrance")
func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio)
	for frame in 5: await process_frame
	await transforms()
	for mode in ["2d","3d"]:
		studio.switch_mode(mode); var city: RefCounted=studio.current()
		var host: Dictionary=city.data["objects"].filter(func(item: Dictionary)->bool:return studio.library.assets[item["asset"]]["behavior"].get("building",false))[0]; var host_uid: String=host["uid"]
		studio.interior_tools.start(host_uid); studio.current().data["objects"]=[]
		var floors: RefCounted=studio.interior_tools.floor_tools; floors.new_name.text="Upper landing"; floors.new_height.value=3; floors.add_floor(); var upper: String=studio.current().floor_uid
		floors.new_name.text="Basement landing"; floors.new_height.value=-3; floors.add_floor(); var basement: String=studio.current().floor_uid
		var ui: RefCounted=floors.entrances; ui.show(); ui.select_floor(upper); ui.source[0].value=12; ui.source[1].value=3; ui.source[2].value=12
		ui.custom_landing.button_pressed=true
		var landing: Array=[-80,40,0] if mode=="2d" else [-3,.1,2]
		for index in 3: ui.arrival[index].value=landing[index]
		press(ui.dialog,"Apply exterior entrance"); var uid: String=ui.selected_uid
		check(studio.modal_visible() and Plan.valid(floors.root_data()) and floors.root_data()["floor_entrances"][0]["floor"]==upper,"Entrance controls author an upper-floor entrance and capture shortcuts: "+mode)
		var stored: Array=floors.root_data()["floor_entrances"][0]["arrival"]
		check(Vector3(stored[0],stored[1],stored[2]).distance_to(Vector3(landing[0],landing[1],landing[2]))<.001,"The custom room landing is independent of the exterior source point: "+mode)
		floors.root_data()["floor_entrances"][0]["extension"]={"retain":true}; ui.source[0].value=14; press(ui.dialog,"Apply exterior entrance")
		check(floors.root_data()["floor_entrances"][0]["uid"]==uid and floors.root_data()["floor_entrances"][0]["extension"]=={"retain":true},"Updating an entrance preserves identity and extension metadata: "+mode)
		ui.dialog.hide(); studio._command("undo",null); check(floors.root_data()["floor_entrances"][0]["position"][0]==12,"Entrance updates undo through shared floor history: "+mode)
		studio._command("redo",null); check(floors.root_data()["floor_entrances"][0]["position"][0]==14,"Entrance updates redo through shared floor history: "+mode)
		ui.show(); ui.new_record(); ui.select_floor(basement); ui.source[0].value=-12; ui.source[1].value=-3; ui.source[2].value=12; press(ui.dialog,"Apply exterior entrance"); var basement_uid: String=ui.selected_uid
		check(floors.root_data()["floor_entrances"].size()==2 and not floors.root_data()["floor_entrances"][1].has("arrival"),"A separate basement entrance can use the room's ordinary exit: "+mode)
		ui.remove_record(); check(floors.root_data()["floor_entrances"].size()==1,"The remove control deletes only the selected entrance: "+mode)
		ui.dialog.hide(); studio._command("undo",null); check(floors.root_data()["floor_entrances"].size()==2,"Undo restores a removed entrance: "+mode)
		ui.show(); ui.new_record(); ui.select_floor(upper); ui.source[0].value=24; ui.source[1].value=3; ui.source[2].value=12; ui.view_choice.select(0); ui.custom_landing.button_pressed=true
		var second_landing: Array=[80,-40,0] if mode=="2d" else [3,.1,-2]
		for index in 3: ui.arrival[index].value=second_landing[index]
		press(ui.dialog,"Apply exterior entrance"); var second_uid: String=ui.selected_uid
		check(floors.root_data()["floor_entrances"].size()==3 and not floors.root_data()["floor_entrances"][2].has("view"),"One floor can have independent landings, including an entrance available in every sprite view: "+mode)
		ui.show(); ui.load_record(uid); await capture(mode,"editor")
		var original_size: Vector2i=root.size
		ui.dialog.hide(); studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true,"shape_markers":true}); root.size=Vector2i(960,640)
		for frame in 8: await process_frame
		ui.show()
		for frame in 5: await process_frame
		check(ui.dialog.size.x<=960 and ui.dialog.size.y<=600,"Scrollable entrance controls fit the minimum viewport at enlarged text and targets: "+mode)
		ui.dialog.hide(); studio.accessibility_settings.restore({}); root.size=original_size; ui.show(); ui.load_record(uid)
		for invalid in [[0,0],[0,true,0],[0,INF,0]]:
			var broken: Dictionary=floors.root_data()["floor_entrances"][0].duplicate(true); broken["arrival"]=invalid
			check(not Plan.put_record(floors.root_data(),"floor_entrances",broken)["ok"],"Malformed custom landings are rejected: "+mode+str(invalid))
		var entry: Dictionary=floors.root_data()["floor_entrances"][0].duplicate(true)
		ui.walk_here(); var world: Node=studio.worlds[mode]; var exploration: Node=world.exploration; var player: Node=world.player; player.set_physics_process(false)
		host=city.object(host_uid); var authored: Dictionary=city.data.duplicate(true); var outside: Variant=Entries.outside(world.instances[host_uid],host,entry,mode,studio.library)
		check(not studio.interior_tools.editing() and studio.walking and player.position.distance_to(outside)<.001,"Walk from entrance commits the room and uses the transformed exterior point: "+mode)
		check(exploration.marker_nodes.has(host_uid+":"+uid) and exploration.marker_nodes[host_uid+":"+uid].text.contains("Upper landing"),"The exterior marker identifies its destination floor: "+mode)
		check(exploration.prompt().contains("Upper landing") and exploration.nearby["entry"]["uid"]==uid,"Proximity selects the distinct floor-specific entrance: "+mode)
		exploration.interact(); check(exploration.entering and exploration.runtime_modal(),"Custom entrance validation captures control until collision registration: "+mode); await settle()
		check(exploration.interior!=null and exploration.active_floor()==upper and not exploration.entering,"The normal E interaction enters the upper floor directly: "+mode)
		var expected: Variant=Vector2(landing[0],landing[1]) if mode=="2d" else Vector3(landing[0],landing[1]+3,landing[2])
		check(player.position.distance_to(expected)<.01 and not player.is_physics_processing() and player.recovery_count==0,"Entry uses the authored landing and restores the original control state without recovery: "+mode)
		check(exploration.prompt().contains("Return outside") and exploration.exit_markers.get_child_count()==2,"The upper floor shows both independent exterior exits: "+mode)
		await capture(mode,"upper"); exploration.interact(); check(exploration.interior==null and player.position.distance_to(outside)<.01,"The upper exit returns to its exterior entrance: "+mode)
		var base_entry: Dictionary={}
		for record in host["interior"]["floor_entrances"]:
			if record["uid"]==basement_uid: base_entry=record
		var below: Variant=Entries.outside(world.instances[host_uid],host,base_entry,mode,studio.library); player.teleport_to(below); exploration.interact(); await settle()
		check(exploration.interior!=null and exploration.active_floor()==basement,"A separate exterior entrance reaches a basement directly: "+mode)
		exploration.interact(); check(exploration.interior==null and player.position.distance_to(below)<.01,"The basement's default landing returns to the used exterior entry: "+mode)
		var second_entry: Dictionary=host["interior"]["floor_entrances"].filter(func(record: Dictionary)->bool:return record["uid"]==second_uid)[0]
		var second_point: Variant=Entries.outside(world.instances[host_uid],host,second_entry,mode,studio.library)
		player.teleport_to(second_point); exploration.interact(); await settle()
		var second_expected: Variant=Vector2(second_landing[0],second_landing[1]) if mode=="2d" else Vector3(second_landing[0],second_landing[1]+3,second_landing[2])
		check(exploration.interior!=null and exploration.active_floor()==upper and player.position.distance_to(second_expected)<.01,"A second entrance to the same floor uses its own interior landing: "+mode)
		exploration.interact(); check(exploration.interior==null and player.position.distance_to(second_point)<.01,"Each same-floor landing returns through its own exterior entrance: "+mode)
		# Enter normally, then leave through another floor's exterior exit.
		player.teleport_to(exploration.entrance(world.instances[host_uid])); exploration.interact(); await settle()
		if mode=="2d": exploration.interior.floor_stack.switch_floor(upper)
		player.teleport_to(expected); exploration.interact()
		check(exploration.interior==null and player.position.distance_to(outside)<.01,"Leaving through a different floor returns to that floor's transformed exterior point: "+mode)
		# Block the actual rendered landing while the custom entry is being checked.
		player.teleport_to(outside); exploration.interact()
		var blocker: Node=StaticBody2D.new() if mode=="2d" else StaticBody3D.new(); blocker.collision_layer=1; exploration.room_world(upper).add_child(blocker)
		var shape: Node=CollisionShape2D.new() if mode=="2d" else CollisionShape3D.new()
		if mode=="2d": shape.shape=CircleShape2D.new(); shape.shape.radius=12; blocker.position=Vector2(landing[0],landing[1])
		else: shape.shape=BoxShape3D.new(); shape.shape.size=Vector3(1,2,1); blocker.position=Vector3(landing[0],landing[1]+1,landing[2])
		blocker.add_child(shape); await settle()
		check(exploration.interior==null and exploration.entrance_notice.contains("blocked") and player.position.distance_to(outside)<.01 and not player.is_physics_processing(),"An obstructed entrance restores the exterior and original controls with an explanation: "+mode)
		if mode=="3d":
			exploration.interact(); exploration.room_world(upper).floor_surface.platform.collision_layer=0; await settle()
			check(exploration.interior==null and exploration.entrance_notice.contains("unsupported") and not player.is_physics_processing() and player.position.distance_to(outside)<.01,"An unsupported elevated landing is rejected before the character can fall")
		exploration.interact(); exploration.leave_interior(); await settle()
		check(exploration.interior==null and not exploration.entering and player.position.distance_to(outside)<.01,"Leaving during entrance validation cancels its pending callback: "+mode)
		check(city.data==authored,"Entry checks, visits and different-floor exits preserve authored data: "+mode)
		var documents: Dictionary={}
		for key in ["2d","3d"]: documents[key]=studio.documents[key].data.duplicate(true)
		var project_path: String="res://output/floor_entrances_"+mode+".isocity.json"
		check(preload("res://scripts/builder/project_store.gd").write_json(project_path,{"version":1,"active_mode":mode,"documents":documents}),"The ordinary project store saves floor-specific landing records: "+mode)
		var loader=preload("res://scripts/builder/project_repair.gd").new(studio.library); var loaded: Dictionary=loader.read(project_path)
		var saved_host: Dictionary=loaded["content"]["documents"][mode]["objects"].filter(func(item: Dictionary)->bool:return item["uid"]==host_uid)[0]
		var saved_entry: Dictionary=saved_host["interior"]["floor_entrances"][0]
		check(loaded["ok"] and loader.issues.is_empty() and saved_entry["uid"]==uid and saved_entry["extension"]=={"retain":true} and Vector3(saved_entry["arrival"][0],saved_entry["arrival"][1],saved_entry["arrival"][2]).distance_to(Vector3(landing[0],landing[1],landing[2]))<.001,"Project reopening retains custom landings and metadata without repair: "+mode)
		check(preload("res://scripts/builder/exporter.gd").save_scene(world,city.data,studio.library,"res://output/floor_entrances_"+mode+".tscn")==OK,"Floor-specific entrances export to a playable scene: "+mode)
		check(preload("res://scripts/builder/portable_export.gd").new().save(world,city.data,studio.library,"res://output/floor_entrances_"+mode+".zip")["ok"],"Floor-specific entrances package all runtime dependencies: "+mode)
		studio.set_walking(false); player.set_physics_process(true)
	studio.free(); print("FLOOR ENTRANCES: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
