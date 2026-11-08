extends SceneTree

const Plan = preload("res://scripts/builder/cycling_plan.gd")
const Drive = preload("res://scripts/builder/driving_plan.gd")
const Templates = preload("res://scripts/builder/templates.gd")
const Repair = preload("res://scripts/builder/project_repair.gd")
const Portable = preload("res://scripts/builder/portable_export.gd")
const OUTPUT = "res://output/verification/asset_expansion/N15"
const BIKE = "3d:HanX_Traffic/Bicycle"
const SCOOTER = "3d:HanX_Traffic/Scooter"
const RACK = {"2d":"2d:Bike_Rack","3d":"3d:HanX_Park/Bike_Rack"}
const HOUSE = {"2d":"2d:Apartment_Brick","3d":"3d:HanX_City/Apartment_4F_A"}
const ROAD_STYLE = {"width":6,"sidewalks":true,"style":"asphalt"}

var studio: Control
var world: Node
var course: Node
var driver: Node
var tools: RefCounted
var checks: int
var failures: int

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: "+message)
	return ok

func settle() -> void:
	for frame in 8: await process_frame
	await physics_frame

func center(cell: Vector2i) -> Vector2:
	return Plan.Traffic.center(cell,studio.mode)

func placed(id: String, point: Vector2, direction: String, title: String) -> Dictionary:
	var doc: RefCounted = studio.current()
	var mode: String = studio.mode
	var at: Vector2 = point-Plan.Roads.center_offset(studio.library,id,direction,1.0,mode)*(2 if mode == "2d" else 1)
	var record: Dictionary = doc.add(id,Plan.Traffic.world(at,mode),direction,1.0)
	record["name"] = title
	return record

func setup(mode: String) -> Dictionary:
	studio.switch_mode(mode)
	var data: Dictionary = Templates.make(mode,"blank")
	studio.current().data = data
	data["economy"] = {"enabled":true,"starting_cash":50000}
	var shared: Dictionary = ROAD_STYLE.duplicate()
	shared["cycle_access"] = "shared"
	var exclusive: Dictionary = ROAD_STYLE.duplicate()
	exclusive["cycle_access"] = "cycle"
	Plan.Roads.paint(data,Vector2i.ZERO,Vector2i(1,0),false,shared)
	Plan.Roads.paint(data,Vector2i(2,0),Vector2i(2,1),false,exclusive)
	Plan.Roads.paint(data,Vector2i(3,1),Vector2i(3,1),false,ROAD_STYLE)
	Plan.Roads.paint(data,Vector2i(-1,3),Vector2i(1,3),false,exclusive)
	var vehicle: Dictionary = placed(BIKE,center(Vector2i.ZERO),"90","Park bicycle")
	var rack: Dictionary = placed(RACK[mode],center(Vector2i(2,1))+Vector2(1.8,3.7),"SE" if mode == "2d" else "0","Meadow rack")
	var other: Dictionary = placed(SCOOTER,center(Vector2i(-1,3)),"90","Park scooter")
	var other_rack: Dictionary = placed(RACK[mode],center(Vector2i(1,3))+Vector2(2.4,3.7),"SE" if mode == "2d" else "0","Creek rack")
	studio.changed()
	world = studio.worlds[mode]
	driver = world.exploration.driving
	course = world.exploration.cycling
	driver.set_physics_process(false)
	course.set_physics_process(false)
	tools = studio.cycling_tools
	return {"bike":vehicle["uid"],"rack":rack["uid"],"npc":other["uid"],"other_rack":other_rack["uid"]}

func author(uid: String, rack_uid: String, auto: bool = false) -> void:
	studio.selected_uid = uid
	studio.selected_uids.assign([uid])
	studio._command("cycling",null)
	tools.opt_in.button_pressed = true
	tools.npc.button_pressed = auto
	for index in tools.rack.item_count:
		if tools.rack.get_item_metadata(index) == rack_uid:
			tools.rack.select(index)
			break
	tools.apply.pressed.emit()

func walk() -> void:
	studio.set_walking(true)
	world.player.set_physics_process(false)
	await settle()

func at(point: Vector2) -> void:
	var target: Variant = world.to_global(Drive.world(point,studio.mode,.11))
	world.player.teleport_to(world.player.get_parent().to_local(target))
	await physics_frame

func board(uid: String) -> bool:
	var item: Dictionary = studio.current().object(uid)
	var point: Vector2 = Drive.center(item,studio.library,studio.mode)
	for offset in [Vector2(0,1.25),Vector2(0,-1.25),Vector2(-1.65,0)]:
		await at(point+offset)
		var prompt: String = world.exploration.interaction_prompt()
		if not prompt.contains("Mount"): continue
		world.exploration.interact()
		return check(driver.cycling(),"The normal E command mounts a supported cycle "+studio.mode+" "+driver.notice)
	return check(false,"Walk displays Mount at a clear approach "+studio.mode+" "+world.exploration.prompt())

func drive_frames(count: int, input: Vector2, brake: bool = false) -> void:
	for frame in count: driver.step(1.0/60,input,brake)

func advance_guidance(count: int) -> void:
	for frame in count:
		course.time += 1.0/60
		course.step_guide(driver,1.0/60,Vector2.ZERO,false)
		if driver.active.is_empty(): break

func run() -> void:
	studio = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	while not studio.enhancements_ready: await process_frame
	studio.consumer_shell.dismiss_welcome()
	for id in Plan.definitions()["assets"]:
		check(studio.library.assets.has(id),"The supported cycle scene exists "+id)
	for mode in ["2d","3d"]: await outdoor(mode)
	await pixel_variants()
	studio.free()
	await process_frame
	print("CYCLING WORKFLOW: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func outdoor(mode: String) -> void:
	var ids: Dictionary = setup(mode)
	var doc: RefCounted = studio.current()
	check(not Plan.enabled(doc.data) and Plan.profile(doc.object(ids["bike"]),doc.data).is_empty(),"Cycling is disabled by default "+mode)
	studio._command("cycling",null)
	tools.enabled.button_pressed = true
	tools.city.pressed.emit()
	author(ids["bike"],ids["rack"])
	author(ids["npc"],ids["other_rack"],true)
	check(Plan.enabled(doc.data) and doc.object(ids["bike"])["cycling"]["rack"] == ids["rack"],"The normal UI authors a vehicle and rack "+mode)
	studio._command("undo",null)
	check(not doc.object(ids["npc"]).has("cycling"),"Undo restores the exact previous vehicle record "+mode)
	studio._command("redo",null)
	check(doc.object(ids["npc"])["cycling"]["npc"],"Redo restores the preview rider assignment "+mode)
	var graph: Dictionary = course.plan
	check(graph["edges"].has("1,0>2,0") and not Plan.Traffic.build(doc.data)["edges"].has("1,0>2,0"),
		"Cycle-only connections are available to riders and excluded from motor routing "+mode)
	check(not graph["edges"].has("2,1>3,1"),"Untagged road art does not grant route access "+mode)
	var bike: Dictionary = doc.object(ids["bike"])
	var profile: Dictionary = Plan.profile(bike,doc.data)
	var extent: Vector2 = Drive.dimensions(bike,studio.library,mode,profile)
	var start: Vector2 = center(Vector2i.ZERO)
	var route: Dictionary = Plan.rack_route(doc.data,graph,bike,profile,extent,start,studio.library)
	if not check(route["reason"].is_empty() and route["sections"].size() == 4,"The player route reaches a real rack through a turn "+mode+" "+str(route)): return
	var economy: Dictionary = doc.data.get("economy_account",{}).duplicate(true)
	await capture_authoring(ids["bike"])
	await walk()
	if not await board(ids["bike"]): return
	var pose: Dictionary = driver.rider_pose.saved.duplicate(true)
	check(world.player.visible and world.player.has_meta("cycling_rider") and not world.player.is_physics_processing()
		and (world.player.action == "sit" if mode == "2d" else not world.player.limbs[0].transform.is_equal_approx(pose["limbs"][0])),
		"The mounted rider uses the supported visible pose "+mode)
	if not await capture_riding("bicycle",ids["bike"]): return
	pose = driver.rider_pose.saved.duplicate(true)
	drive_frames(90,Vector2.UP*-1)
	check(driver.active["point"].x > start.x+1.5 and driver.speed > 0,"The normal driving controls advance the narrow cycle "+mode)
	check(not driver.exit_vehicle() and driver.notice.contains("Brake"),"A moving cycle needs to stop before dismounting "+mode)
	drive_frames(55,Vector2.ZERO,true)
	studio.control_settings.execute("business")
	check(course.routes.has(driver.get_instance_id()),"The ordinary shortcut starts rack guidance "+mode)
	advance_guidance(1600)
	if not check(driver.active.is_empty() and driver.notice == "Parked at the bicycle rack.",
		"Guidance travels to the rack and safely dismounts "+mode+" "+driver.notice+" "+str(driver.active.get("point"))): return
	var finish: Vector2 = driver.parked[ids["bike"]]["point"]
	check(finish.distance_to(route["finish"]) < .12 and world.player.visible and not world.player.has_meta("cycling_rider")
		and (world.player.interaction_visual_offset == pose["offset"] if mode == "2d" else world.player.body.transform.is_equal_approx(pose["body"])),
		"The parked cycle and released rider have their exact expected positions and pose "+mode)
	await at(center(Vector2i(-3,-2)))
	var rider_position: Variant
	var seen_scooter: bool = false
	for frame in 1600:
		course.step(1.0/60)
		if not is_instance_valid(course.runner): continue
		if course.runner.cycling():
			rider_position = course.runner.operator().global_position
			if not seen_scooter and "--capture" in OS.get_cmdline_user_args():
				seen_scooter = true
				await at(course.runner.active["point"]+Vector2(2.3,1.4))
				if mode == "2d": world.camera.zoom = Vector2.ONE * 2.65
				else: world.camera.fov = 48
				await settle()
				capture("preview_scooter",false,1480)
				if mode == "2d": world.camera.zoom = Vector2.ONE
				else: world.camera.fov = 75
				await at(center(Vector2i(-3,-2)))
		if course.attempted.get(ids["npc"]) == "completed" and course.departure.is_empty(): break
	check(course.attempted.get(ids["npc"]) == "completed" and is_instance_valid(course.runner.operator())
		and not course.runner.operator().has_meta("cycling_rider") and course.runner.operator().visible
		and rider_position != course.runner.operator().global_position,"An actual preview rider cycles to the other rack, dismounts and walks away "+mode+" "+course.latest)
	studio.set_walking(false)
	check(driver.parked.is_empty() and course.visitors.is_empty() and course.routes.is_empty(),"Build releases both previews "+mode)
	check(doc.data.get("economy_account",{}) == economy,"Player and preview rides leave the authored treasury exact "+mode)
	var path: String = OUTPUT+"/cycling_"+mode+("_capture" if "--capture" in OS.get_cmdline_user_args() else "")
	check(studio.write_project(path+".isocity.json",false),"Normal Save writes cycle settings and route access "+mode)
	var repair: RefCounted = Repair.new(studio.library)
	var saved: Dictionary = repair.read(path+".isocity.json")
	check(saved["ok"] and repair.issues.is_empty() and Plan.enabled(saved["content"]["documents"][mode]),"Normal Save reopens without repair "+mode)
	if "--portable" in OS.get_cmdline_user_args():
		var result: Dictionary = Portable.new().save(world,doc.data,studio.library,path+".zip")
		check(result["ok"],"The allowed project packages both routes and their assets "+mode+" "+result.get("message",""))
	check(studio.load_project(path+".isocity.json") and course.visitors.is_empty() and driver.active.is_empty(),
		"Reopen restores authored settings and fresh preview state "+mode)
	await safety(ids)

func safety(ids: Dictionary) -> void:
	var mode: String = studio.mode
	var doc: RefCounted = studio.current()
	var saved: Dictionary = doc.data.duplicate(true)
	var start: Vector2 = center(Vector2i.ZERO)
	var second: Dictionary = doc.object(ids["npc"])
	var heading: String = "270"
	var meet: Vector2 = center(Vector2i(1,0))+Vector2(1.2,0)
	second["position"] = Plan.Traffic.world(meet-Plan.Roads.center_offset(studio.library,second["asset"],heading,1.0,mode)*(2 if mode == "2d" else 1),mode)
	second["direction"] = heading
	var cross: Dictionary = Plan.Roads.lookup(doc.data)["1,0"]
	cross["crossing"] = true
	studio.changed()
	await walk()
	await at(start+Vector2(0,1.65))
	var original_frames: int = world.player.sprite.hframes if mode == "2d" else 0
	var original_limbs: Array = world.player.limbs.duplicate() if mode == "3d" else []
	if mode == "2d": world.player.sprite.hframes = 4
	else: world.player.limbs.pop_back()
	check(not driver.interact(driver.nearby(ids["bike"])) and (driver.notice.contains("frame") or driver.notice.contains("rig")),
		"An incompatible rider pose blocks mounting with a reason "+mode+" "+driver.notice)
	if mode == "2d": world.player.sprite.hframes = original_frames
	else: world.player.limbs.assign(original_limbs)
	if not await board(ids["bike"]): return
	var walker: Node = course.make_visitor(world,center(Vector2i(1,0))+Vector2(-3.0,-5.0),0.0,Vector2.ONE)
	if not check(is_instance_valid(walker),"A real pedestrian starts by the crossing "+mode): return
	walker.global_position = world.to_global(Drive.world(center(Vector2i(1,0))+Vector2(0,2.0),mode,.13))
	driver.traffic.pedestrians.append(walker)
	course.time = 3.0
	drive_frames(300,Vector2.DOWN)
	check(driver.notice.contains("Pedestrian crossing") and driver.active["point"].x < start.x+4.0,
		"A cyclist yields before an occupied crossing "+mode+" "+driver.notice)
	driver.traffic.pedestrians.erase(walker)
	course.visitors.erase(walker)
	walker.free()
	course.ensure_runner()
	var profile: Dictionary = Plan.profile(second,doc.data)
	var extent: Vector2 = Drive.dimensions(second,studio.library,mode,profile)
	var actor: Node = course.make_visitor(world,meet,Drive.yaw(second,profile),extent)
	if check(is_instance_valid(actor),"The oncoming preview rider has a clear mount "+mode):
		course.runner.rider = actor
		course.runner.traffic = driver.traffic
		check(course.runner.interact({"item":second,"node":world.instances[ids["npc"]],"profile":profile,"point":meet,
			"yaw":Drive.yaw(second,profile),"extent":extent,"world":world,"data":doc.data}),"An actual rider occupies the oncoming cycle "+mode)
		drive_frames(300,Vector2.DOWN)
		check(driver.notice.contains("Traffic ahead") and driver.active["point"].distance_to(meet)>1.35
			and course.occupants().size() == 2,"Head-on cycles keep safe separation "+mode+" "+driver.notice)
		course.runner.exit_vehicle(true)
	driver.speed = 0
	check(driver.exit_vehicle(),"A waiting rider can dismount to a clear walking spot "+mode)
	studio.set_walking(false)
	doc.data = saved.duplicate(true)
	studio.changed()
	await walk()
	if not await board(ids["bike"]): return
	var barrier_a: Node = barrier(start+Vector2(2,1.2),Vector2(.35,1.8))
	var barrier_b: Node = barrier(start+Vector2(2,-1.2),Vector2(.35,1.8))
	await settle()
	drive_frames(180,Vector2.DOWN)
	check(driver.active["point"].x < start.x+2.0 and driver.notice.contains("blocked"),
		"Swept collision refuses a gap narrower than the mounted cycle "+mode+" "+driver.notice)
	barrier_a.free()
	barrier_b.free()
	await settle()
	if mode == "3d":
		var curb: Node = barrier(start+Vector2(2,0),Vector2(.7,5.6),2,.38)
		await settle()
		drive_frames(180,Vector2.DOWN)
		check(driver.notice.contains("Curb") and driver.active["point"].x < start.x+2.0,"A real raised curb blocks the cycle before its front axle reaches it.")
		curb.free()
		await settle()
	driver.speed = 0
	check(course.guide() and course.routes.has(driver.get_instance_id()),"A linked rack starts a new guidance run "+mode)
	doc.data["objects"].erase(doc.object(ids["rack"]))
	studio.changed()
	course.step_guide(driver,.05,Vector2.ZERO,false)
	check(not course.routes.has(driver.get_instance_id()) and is_zero_approx(driver.speed) and driver.notice.contains("rack"),
		"Removing a rack cancels live guidance and stops the cycle "+mode)
	drive_frames(900,Vector2.DOWN)
	check(driver.notice.contains("Cycle route ends") and driver.active["point"].x < start.x+19,
		"Manual cycling stops before leaving the marked route "+mode+" "+driver.notice)
	check(driver.exit_vehicle(),"Dismount still finds a safe walking spot when the rack is gone "+mode)
	studio.set_walking(false)
	doc.data = saved.duplicate(true)
	var house: Dictionary = placed(HOUSE[mode],Vector2(-12,-12),"SE" if mode == "2d" else "0","Cycle storage")
	var room: Dictionary = Templates.make(mode,"blank")
	room["interior_room"] = true
	var stored: Dictionary = doc.object(ids["bike"]).duplicate(true)
	stored["position"] = Plan.Traffic.world(Vector2.ZERO,mode)
	room["objects"] = [stored]
	house["interior"] = room
	studio.changed()
	await walk()
	world.exploration.enter_preview(house,room,"ground",Vector2(0,15) if mode == "2d" else Vector3(0,.05,1.4))
	await settle()
	check(world.exploration.interior != null and driver.nearby().is_empty() and driver.active.is_empty(),
		"A cycle left indoors remains a parked prop "+mode)
	studio.set_walking(false)
	var damaged: Dictionary = saved.duplicate(true)
	damaged["cycling"]["enabled"] = "broken"
	damaged["roads"][0]["cycle_access"] = "broken"
	Plan.object(damaged,ids["bike"])["cycling"]["npc"] = []
	var repaired: Dictionary = Repair.new(studio.library).world(damaged,mode,"cycling",0)
	check(not Plan.enabled(repaired) and not repaired["roads"][0].has("cycle_access")
		and not Plan.object(repaired,ids["bike"])["cycling"]["enabled"],"Repair disables damaged cycle settings and retains the road and vehicle "+mode)

func barrier(point: Vector2, extent: Vector2, layer: int = 1, height: float = 1.2) -> Node:
	if studio.mode == "2d":
		var body := StaticBody2D.new()
		body.collision_layer = layer
		var shape := ConvexPolygonShape2D.new()
		var points := PackedVector2Array()
		for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]: points.append(Drive.world(corner*extent*.5,"2d"))
		shape.points = points
		var collider := CollisionShape2D.new()
		collider.shape = shape
		body.add_child(collider)
		world.objects.add_child(body)
		body.global_position = world.to_global(Drive.world(point,"2d"))
		return body
	var body := StaticBody3D.new()
	body.collision_layer = layer
	var shape := BoxShape3D.new()
	shape.size = Vector3(extent.x,height,extent.y)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	world.objects.add_child(body)
	body.global_position = world.to_global(Drive.world(point,"3d",height*.5))
	return body

func pixel_variants() -> void:
	setup("2d")
	var doc: RefCounted = studio.current()
	doc.data["objects"] = []
	doc.data["cycling"] = {"enabled":true}
	var start: Vector2 = center(Vector2i.ZERO)
	for id in ["2d:Bicycle","2d:Electric_Scooter"]:
		doc.data["objects"] = []
		var item: Dictionary = placed(id,start,"SE","Pixel rider fixture")
		item["cycling"] = {"enabled":true}
		studio.changed()
		await walk()
		if not await board(item["uid"]): return
		drive_frames(60,Vector2.DOWN)
		check(driver.active["point"].x > start.x+.5 and world.player.visible
			and world.player.action == ("sit" if id.ends_with("Bicycle") else "idle"),"The native Pixel cycle has a calibrated rider pose and moves "+id)
		if id.ends_with("Scooter"):
			check(is_instance_valid(driver.rider_pose.foreground) and driver.rider_pose.foreground.z_index > world.player.z_index,
				"The standing rider leaves the actual scooter front visible.")
		if "--capture" in OS.get_cmdline_user_args():
			world.camera.zoom = Vector2.ONE*3.1
			await settle()
			capture("pixel_"+id.get_slice(":",1).to_lower(),false,1480)
			world.camera.zoom = Vector2.ONE
		studio.set_walking(false)

func capture_authoring(uid: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	studio.selected_uid = uid
	studio.selected_uids.assign([uid])
	for simple in [false,true]:
		studio.consumer_shell.set_active(simple,false)
		studio.consumer_shell.dismiss_welcome()
		for size in [Vector2i(1480,900),Vector2i(960,640)]:
			root.size = size
			studio.accessibility_settings.restore({"text_scale":1.5,"high_contrast":true,"large_targets":true} if size.x == 960 else {})
			studio._command("cycling",null)
			await settle()
			tools.apply.grab_focus()
			await settle()
			check(tools.apply.has_focus() and tools.panel.get_global_rect().encloses(tools.apply.get_global_rect())
				and Rect2(Vector2.ZERO,Vector2(size)).encloses(tools.apply.get_global_rect()),"Cycle authoring controls fit and take keyboard focus "+str([studio.mode,simple,size]))
			capture("authoring",simple,size.x)
			tools.apply.release_focus()
	restore_layout()

func capture_riding(kind: String, uid: String) -> bool:
	if not "--capture" in OS.get_cmdline_user_args(): return true
	for simple in [false,true]:
		studio.consumer_shell.set_active(simple,false)
		studio.consumer_shell.dismiss_welcome()
		if not driver.cycling():
			await walk()
			if not await board(uid): return false
		for size in [Vector2i(1480,900),Vector2i(960,640)]:
			root.size = size
			studio.accessibility_settings.restore({"text_scale":1.5,"high_contrast":true,"large_targets":true} if size.x == 960 else {})
			if studio.mode == "2d": world.camera.zoom = Vector2.ONE*(2.4 if size.x == 1480 else 1.9)
			else: world.camera.fov = 53
			await settle()
			capture(kind,simple,size.x)
	restore_layout()
	if studio.mode == "2d": world.camera.zoom = Vector2.ONE
	else: world.camera.fov = 75
	if driver.cycling(): return true
	await walk()
	return await board(uid)

func capture(phase: String, simple: bool, width: int) -> void:
	RenderingServer.force_draw(false)
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(OUTPUT+"/%s_%s_%s_%d.png" % [phase,studio.mode,"simple" if simple else "precision",width]) == OK,
		"Captured the actual cycling workflow.")

func restore_layout() -> void:
	root.size = Vector2i(1480,900)
	studio.accessibility_settings.restore({})
	studio.consumer_shell.set_active(false,false)
