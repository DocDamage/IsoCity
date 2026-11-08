extends SceneTree

const Plan = preload("res://scripts/builder/camping_plan.gd")
const Props = preload("res://scripts/builder/prop_plan.gd")
const Templates = preload("res://scripts/builder/templates.gd")
const Repair = preload("res://scripts/builder/project_repair.gd")
const Portable = preload("res://scripts/builder/portable_export.gd")
const OwnedCopy = preload("res://scripts/builder/owned_room_copy.gd")
const OUTPUT = "res://output/verification/asset_expansion/N12"
const SHELTER = "3d:HanX_Park/Gazebo"
const TENT = "2d:Supplemental_Camping_gear_kit_dome_tent_ae1e2dc1"
const FIRE = "2d:Reviewed_myart_campfire"
const PARK = {"2d":"2d:Park_Bench","3d":"3d:HanX_Park/Bench_Park"}
const PICNIC = {"2d":"2d:Picnic_Table","3d":"3d:HanX_Park/Picnic_Table"}
const HOME = {"2d":"2d:Apartment_Brick","3d":"3d:HanX_City/Apartment_4F_A"}
const CITY = "city:"

var studio: Control
var tools: RefCounted
var world: Node
var camp: Node
var clock: Node
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
	for frame in 7: await process_frame
	await physics_frame

func placed(id: String, at: Vector2, title: String = "") -> String:
	var item: Dictionary = studio.current().add(id,Plan.Traffic.world(at,studio.mode),str(studio.library.directions(id)[0]),1.0)
	if not title.is_empty(): item["name"] = title
	return item["uid"]

func choose(control: OptionButton, uid: String) -> void:
	for index in control.item_count:
		if control.get_item_metadata(index) == uid:
			control.select(index)
			return

func author(ids: Dictionary, slots: int = 1, overnight: bool = false) -> void:
	studio.selected_uid = ids["site"]
	studio.selected_uids.assign([ids["site"]])
	tools.refresh()
	tools.site_enabled.button_pressed = true
	tools.capacity.value = slots
	tools.opening.value = 16
	tools.closing.value = 22
	tools.checkout.value = 8
	tools.overnight.button_pressed = overnight
	choose(tools.park,ids["park"])
	choose(tools.activity,ids["activity"])
	tools.apply_site.pressed.emit()

func fixture(mode: String) -> Array[Dictionary]:
	studio.switch_mode(mode)
	studio.current().data = Templates.make(mode,"blank")
	studio.current().data["economy"] = {"enabled":true,"starting_cash":50000}
	studio.current().data["ambience"] = {"enabled":true}
	var fire: Dictionary = {
		"site":placed(SHELTER,Vector2(-11,-2),"Creek campsite"),
		"park":placed(PARK[mode],Vector2(-12,8),"Creek park"),
		"activity":placed(FIRE,Vector2(-4,-4),"Creek campfire")}
	var picnic: Dictionary = {
		"site":placed(SHELTER,Vector2(11,-2),"Meadow campsite"),
		"park":placed(PARK[mode],Vector2(13,8),"Meadow park"),
		"activity":placed(PICNIC[mode],Vector2(18,-4),"Meadow picnic")}
	studio.changed()
	tools = studio.camping_tools
	world = studio.worlds[mode]
	camp = world.exploration.camping
	clock = studio.business_tools.managers[mode]
	camp.set_physics_process(false)
	clock.set_physics_process(false)
	return [fire,picnic]

func begin_walk() -> void:
	studio.set_walking(true)
	world.player.set_physics_process(false)
	await settle()

func at(point: Vector2) -> void:
	var target: Variant = camp.world_point(point,Props.context(world.exploration))
	world.player.teleport_to(world.player.get_parent().to_local(target))
	await physics_frame

func use(point: Vector2, word: String) -> bool:
	await at(point)
	var prompt: String = world.exploration.interaction_prompt()
	if not check(word in prompt,"Expected '%s', saw '%s' in %s at %s" % [word,prompt,studio.mode,point]): return false
	world.exploration.interact()
	return true

func advance(seconds: int) -> void:
	for tick in seconds*4: camp.step(.25)

func reach_activity(site: Dictionary, action: String) -> bool:
	if not await use(site["entry"],"Reserve"): return false
	if not camp.jobs.has("player"): return false
	if not await use(site["points"][0]["shelter"],"Check in"): return false
	return await use(site["points"][0]["activity"],action)

func capture(site: Dictionary, phase: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	var active: bool = studio.walking
	for simple in [false,true]:
		studio.consumer_shell.set_active(simple,false)
		studio.consumer_shell.dismiss_welcome()
		for size in [Vector2i(1480,900),Vector2i(960,640)]:
			root.size = size
			studio.accessibility_settings.restore({"text_scale":1.5,"high_contrast":true,"large_targets":true} if size.x == 960 else {})
			if not active:
				studio.selected_uid = site["uid"]
				studio.selected_uids.assign([site["uid"]])
				studio._command("camping",null)
			await settle()
			if studio.mode == "2d" and not active:
				world.camera.position = Vector2(-10,-15)
				world.camera.zoom = Vector2.ONE * 1.25
			elif studio.mode == "3d" and not active:
				world.distance = 32
				world.target = Vector3.ZERO
				world.update_camera()
			if not active:
				tools.apply_site.grab_focus()
				await settle()
				check(tools.apply_site.has_focus() and tools.panel.get_global_rect().encloses(tools.apply_site.get_global_rect())
					and Rect2(Vector2.ZERO,Vector2(size)).encloses(tools.apply_site.get_global_rect()),
					"Camping authoring and keyboard focus fit "+str([studio.mode,simple,size]))
			RenderingServer.force_draw(false)
			RenderingServer.force_draw(false)
			check(root.get_texture().get_image().save_png(OUTPUT+"/%s_%s_%s_%d.png" % [phase,studio.mode,"simple" if simple else "precision",size.x]) == OK,
				"Captured the live camping view "+str([studio.mode,simple,size]))
			if not active: tools.apply_site.release_focus()
	root.size = Vector2i(1480,900)
	studio.accessibility_settings.restore({})
	studio.consumer_shell.set_active(false,false)
	await settle()

func run() -> void:
	studio = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	while not studio.enhancements_ready: await process_frame
	studio.consumer_shell.dismiss_welcome()
	for id in Plan.definitions()["shelters"].keys()+Plan.definitions()["activities"].keys():
		check(studio.library.assets.has(id),"Camping catalog resolves "+id)
	check(Plan.due({"open_hour":20.0,"close_hour":3.0,"checkout":8.0,"overnight":true},25.0) == 32.0,
		"A reservation after midnight retains the previous evening's morning checkout.")
	for mode in ["2d","3d"]: await outdoor(mode)
	studio.free()
	await process_frame
	print("CAMPING WORKFLOW: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func outdoor(mode: String) -> void:
	var ids: Array[Dictionary] = fixture(mode)
	var doc: RefCounted = studio.current()
	check(not Plan.enabled(doc.data) and camp.sites(CITY).is_empty(),"Camping defaults disabled "+mode)
	studio._command("camping",null)
	tools.enabled.button_pressed = true
	tools.apply_city.pressed.emit()
	author(ids[0])
	author(ids[1],2,true)
	check(Plan.enabled(doc.data),"Normal city camping control applies "+mode)
	studio._command("undo",null)
	check(not Plan.selected(doc.object(ids[1]["site"])),"Undo removes the campsite configuration "+mode)
	studio._command("redo",null)
	check(Plan.selected(doc.object(ids[1]["site"])),"Redo restores campsite configuration "+mode)
	var sites: Dictionary = camp.sites(CITY)
	if not check(sites.size() == 2,"Both authored campsite records are present "+mode): return
	for site in sites.values():
		if not check(site["reason"].is_empty(),"Campsite routes compile %s %s: %s" % [mode,site["name"],site["reason"]]): return
	var fire: Dictionary = sites[ids[0]["site"]]
	var picnic: Dictionary = sites[ids[1]["site"]]
	await capture(fire,"authoring")
	await begin_walk()
	clock.hour = 17
	clock.preview_day = 0
	camp.step(.1)
	var economy: Dictionary = doc.data.get("economy_account",{}).duplicate(true)
	var services: Array = clock.service.history.duplicate(true)
	if not await reach_activity(fire,"Gather at the campfire"): return
	check(camp.occupied(CITY,fire["uid"]) == 1 and camp.occupied(CITY,picnic["uid"]) == 0,
		"Only the selected campsite is occupied "+mode)
	check(not camp.book("extra",fire,CITY,world.player),"Capacity blocks an additional guest "+mode)
	var flame: Dictionary = camp.view.flames.get(ids[0]["activity"],{})
	check(not flame.is_empty() and not flame["bed"].visible and is_instance_valid(flame["sound"]),
		"The active campfire has visible flame and spatial sound "+mode)
	await capture(fire,"activity")
	doc.data["weather"] = {"enabled":true,"condition":"rain","intensity":.55}
	studio.changed()
	await settle()
	camp.step(.25)
	flame = camp.view.flames.get(ids[0]["activity"],{})
	check(camp.jobs.get("player",{}).get("phase") == "checked_in" and not flame.is_empty()
		and flame["bed"].visible and not is_instance_valid(flame["sound"]),
		"Rain extinguishes the fire and stops sound without completing the activity "+mode)
	doc.data.erase("weather")
	studio.changed()
	await settle()
	if not await use(fire["points"][0]["activity"],"Gather at the campfire"): return
	advance(4)
	if not await use(fire["points"][0]["shelter"],"Rest at the shelter"): return
	check(camp.resting() and not world.player.is_physics_processing(),"Rest holds the player safely "+mode)
	check(camp.prompt().contains("no sleeping pose" if mode == "2d" else "Sleeping"),
		"The rest prompt describes the supplied or fallback pose "+mode)
	advance(4)
	check(not camp.view.poses.has("player") and not is_instance_valid(camp.view.flames[ids[0]["activity"]]["sound"]),
		"Completed rest restores the pose and leaves the fire extinguished "+mode)
	if not await use(fire["entry"],"Check out"): return
	check(camp.jobs.is_empty() and camp.history.back()["state"] == "completed","Park checkout releases the reservation "+mode)
	if not await reach_activity(picnic,"Start the picnic"): return
	check(camp.book("second",picnic,CITY,world.player) and camp.jobs["second"]["slot"] != camp.jobs["player"]["slot"],
		"An overnight shelter assigns separate sleeping slots "+mode)
	camp.finish("second","Test guest left.")
	advance(4)
	if not await use(picnic["points"][0]["shelter"],"Rest at the shelter"): return
	advance(5)
	check(camp.resting() and is_equal_approx(clock.hour,17),"Overnight rest does not advance the shared clock "+mode)
	clock.day_length = 30
	for tick in 80:
		clock.step(.25,true)
		camp.step(.25)
		if not camp.resting(): break
	check(clock.preview_day == 1 and clock.hour >= 8 and clock.hour < 8.3 and camp.jobs.get("player",{}).get("phase") == "departure",
		"Overnight rest ends at natural morning checkout "+mode+" "+str([clock.preview_day,clock.hour]))
	if not await use(picnic["entry"],"Check out"): return
	check(doc.data.get("economy_account",{}) == economy and clock.service.history == services,
		"Neither visit nor the natural rollover pays unrelated rewards "+mode)
	clock.hour = 17
	camp.step(.25)
	if not await use(picnic["entry"],"Reserve"): return
	clock.hour = 12
	camp.step(.25)
	check(camp.jobs.is_empty() and camp.history.back()["state"] == "cancelled","An explicit time jump safely releases reservations "+mode)
	clock.hour = 17
	camp.step(.25)
	if not await use(picnic["entry"],"Reserve"): return
	var path: String = OUTPUT+"/camping_"+mode+("_capture" if "--capture" in OS.get_cmdline_user_args() else "")
	check(studio.write_project(path+".isocity.json",false),"Normal save writes a project while visiting "+mode)
	var repair: RefCounted = Repair.new(studio.library)
	var saved: Dictionary = repair.read(path+".isocity.json")
	check(saved["ok"] and repair.issues.is_empty() and Plan.enabled(saved["content"]["documents"][mode])
		and not saved["content"]["documents"][mode].has("camping_jobs"),"Save retains campsite settings and excludes transient visits "+mode)
	studio.set_walking(false)
	check(camp.jobs.is_empty() and camp.view.flames.is_empty(),"Build cancels and cleans the visit "+mode)
	if "--portable" in OS.get_cmdline_user_args():
		var result: Dictionary = Portable.new().save(world,doc.data,studio.library,path+".zip")
		check(result["ok"],"Allowed camping export "+mode+" "+result.get("message",""))
	var damaged: Dictionary = doc.data.duplicate(true)
	damaged["camping"]["enabled"] = "invalid"
	for item in damaged["objects"]:
		if item["uid"] == fire["uid"]: item["camping"]["capacity"] = -2
	var fixed: Dictionary = Repair.new(studio.library).world(damaged,mode,"damaged_camping",0)
	check(not Plan.enabled(fixed) and not Plan.selected(fixed["objects"][0]),"Repair disables malformed settings and retains the shelter "+mode)
	check(studio.load_project(path+".isocity.json"),"The normal editor reopens the project "+mode)
	check(camp.jobs.is_empty() and camp.view.poses.is_empty(),"Loading restores empty transient camping state "+mode)
	await safety(ids)
	await supplied_shelter(ids)
	await residents(ids)

func safety(ids: Array[Dictionary]) -> void:
	var mode: String = studio.mode
	var doc: RefCounted = studio.current()
	var original: Dictionary = doc.data.duplicate(true)
	var site: Dictionary = camp.sites(CITY)[ids[0]["site"]]
	await begin_walk()
	clock.hour = 17
	if not await reach_activity(site,"Gather at the campfire"): return
	var photo: Node = world.exploration.photo
	check(photo.start(),"Photo can interrupt an active campfire "+mode)
	camp.step(.25)
	check(camp.jobs.is_empty() and camp.view.labels.is_empty() and not is_instance_valid(camp.view.flames[ids[0]["activity"]]["sound"]),
		"Photo cancels the player visit, hides markers and extinguishes the fire "+mode)
	photo.stop()
	if not await reach_activity(site,"Gather at the campfire"): return
	var cell: Vector2i = Vector2i((Plan.terrain_point(site["entry"],mode)/Plan.Terrain.CELL_SIZE).floor())
	doc.data["terrain"] = {"enabled":true,"bounds":[-20,-20,40,40]}
	doc.data["water_cells"] = [{"cell":[cell.x,cell.y],"level":1.5}]
	studio.changed()
	camp.step(.25)
	check("flooded" in camp.sites(CITY)[site["uid"]]["reason"] and camp.jobs.is_empty()
		and not camp.view.poses.has("player"),"A flooded park approach closes the site and releases its active guest "+mode)
	doc.data = original.duplicate(true)
	studio.changed()
	await settle()
	clock.hour = 17
	if not await use(site["entry"],"Reserve"): return
	var blocker: String = placed(SHELTER,Plan.terrain_point(site["entry"],mode))
	studio.changed()
	camp.step(.25)
	check("No safe walking route" in camp.sites(CITY)[site["uid"]]["reason"] and camp.jobs.is_empty(),
		"A blocked park exit cancels the booking without a completed visit "+mode+" "+camp.sites(CITY)[site["uid"]]["reason"])
	doc.data["objects"].erase(doc.object(blocker))
	studio.changed()
	await settle()
	clock.hour = 17
	if not await use(site["entry"],"Reserve"): return
	doc.data["weather"] = {"enabled":true,"condition":"snow","intensity":.9}
	studio.changed()
	camp.step(.25)
	check(camp.jobs.is_empty() and "weather" in camp.history.back()["reason"],"Severe snow closes an occupied campsite "+mode)
	doc.data = original
	studio.changed()
	studio.set_walking(false)
	var room: Dictionary = original.duplicate(true)
	room["objects"] = []
	for key in ["site","park","activity"]: room["objects"].append(doc.object(ids[1][key]).duplicate(true))
	room["objects"][0]["camping"]["overnight"] = false
	var copied: Dictionary = OwnedCopy.room(room)
	var first: Dictionary = Plan.compile(room,studio.library,false)
	var second: Dictionary = Plan.compile(copied,studio.library,false)
	check(first.size() == 1 and second.size() == 1 and first.keys() != second.keys()
		and second.values()[0]["reason"].is_empty(),"Copying a room remaps the entire daytime campsite "+mode)
	var lone: Dictionary = room["objects"][0].duplicate(true)
	Plan.copy_references(lone,{})
	check(not Plan.selected(lone),"Copying an unlinked shelter leaves it disabled "+mode)
	room["interior_room"] = true
	await begin_walk()
	clock.hour = 17
	var scope_keys: Array[String] = []
	var lock_keys: Array[String] = []
	for host_id in ["camp-room-a","camp-room-b"]:
		var host: Dictionary = {"uid":host_id,"asset":HOME[mode],"name":"Camp lodge","position":Plan.Traffic.world(Vector2.ZERO,mode),"direction":"SE" if mode == "2d" else "0","scale":1.0}
		world.exploration.enter_preview(host,room.duplicate(true),"ground",Vector2(0,64) if mode == "2d" else Vector3(0,.05,8))
		await settle()
		var key: String = camp.scope()
		var inside: Dictionary = camp.sites(key).get(room["objects"][0]["uid"],{})
		if check(key.begins_with("room:"+host_id) and not inside.is_empty() and inside["reason"].is_empty(),"The same authored site UID resolves inside "+host_id+" "+mode):
			await use(inside["entry"],"Reserve")
			if check(camp.jobs.has("player"),"The active room owns its reservation "+mode):
				scope_keys.append(key)
				lock_keys.append(camp.jobs["player"]["locks"][0]["key"])
		world.exploration.leave_interior()
		await settle()
		check(camp.jobs.is_empty(),"Leaving a room releases its campsite reservation "+mode)
	check(scope_keys.size() == 2 and scope_keys[0] != scope_keys[1] and lock_keys[0] != lock_keys[1],
		"Identical campsite IDs in two rooms have distinct leases "+mode)
	studio.set_walking(false)

func supplied_shelter(ids: Array[Dictionary]) -> void:
	var mode: String = studio.mode
	var doc: RefCounted = studio.current()
	var original: Dictionary = doc.data.duplicate(true)
	var shelter: Dictionary = doc.object(ids[0]["site"])
	shelter["asset"] = TENT
	shelter["direction"] = studio.library.directions(TENT)[0]
	shelter["camping"]["capacity"] = 4
	studio.changed()
	await settle()
	var site: Dictionary = camp.sites(CITY)[ids[0]["site"]]
	check(site["reason"].is_empty() and site["config"]["capacity"] == 2 and site["points"].size() == 2
		and is_instance_valid(world.instances.get(shelter["uid"])),"The actual supplied dome tent opens with two safe sleeping spaces "+mode+" "+site["reason"])
	if "--portable" in OS.get_cmdline_user_args():
		var blocked: Dictionary = Portable.new().save(world,doc.data,studio.library,OUTPUT+"/restricted_"+mode+".zip")
		check(not blocked["ok"] and "restricts redistributing" in blocked["message"],"The supplied Camping gear license prevents source ZIP redistribution "+mode)
	doc.data = original
	studio.changed()
	await settle()

func residents(ids: Array[Dictionary]) -> void:
	var mode: String = studio.mode
	var doc: RefCounted = studio.current()
	doc.object(ids[1]["site"])["camping"]["overnight"] = false
	for point in [Vector2(-13,20),Vector2(14,21)]: placed(HOME[mode],point)
	doc.data["citizens"] = {"enabled":true,"population":2,"start_hour":17.25,"day_length":3600,"seed":43}
	studio.changed()
	await begin_walk()
	await at(Plan.point(Vector2(0,-24),mode))
	var manager: Node = studio.citizen_tools.managers[mode]
	manager.set_physics_process(false)
	if not check(manager.residents.size() == 2,"Two live residents spawn "+mode): return
	camp.reset()
	manager.residents.sort_custom(func(a: Dictionary,b: Dictionary)->bool: return manager.point(a["actor"]).x < manager.point(b["actor"]).x)
	for index in 2:
		manager.residents[index]["park"] = ids[index]["park"]
		manager.residents[index]["offset"] = 0.0
		manager.residents[index]["target"] = ""
		manager.residents[index]["path"] = PackedVector2Array()
		manager.residents[index]["index"] = 0
	manager.hour = 17.25
	camp.last_time = -1
	if "--trace" in OS.get_cmdline_user_args():
		for index in 2:
			var site: Dictionary = camp.sites(CITY)[ids[index]["site"]]
			var actor: Node = manager.residents[index]["actor"]
			print(mode," route ",index," ",site["reason"]," ",site["entry"]," ",manager.route(manager.point(actor),site["entry"]))
	var simultaneous: bool = false
	var gathering: bool = false
	var photographed: bool = false
	var seen: Dictionary = {}
	for frame in 3600:
		manager.step(1.0/60)
		if frame%12 == 0:
			camp.step(.2)
			if "--trace" in OS.get_cmdline_user_args() and frame%120 == 0:
				for guest in manager.residents:
					var job: Dictionary = camp.jobs.get(guest["id"],{})
					print(mode," ",frame," ",manager.point(guest["actor"])," ",guest["target"]," ",job.get("phase")," ",guest["status"]," path ",guest["index"],"/",guest["path"].size()," visits ",guest["visits"])
			if camp.jobs.size() == 2:
				simultaneous = simultaneous or camp.view.labels.values().all(func(label: Node)->bool: return "1/" in label.text)
				gathering = gathering or camp.jobs.values().all(func(visit: Dictionary)->bool: return visit["phase"] in ["activity","rest"] and visit["arrived"])
				if gathering and not photographed and "--capture" in OS.get_cmdline_user_args():
					photographed = true
					await capture_residents(mode)
			for job in camp.jobs.values(): seen[job["site"]] = true
		if camp.history.filter(func(entry: Dictionary)->bool: return entry["guest"] != "player" and entry["state"] == "completed").size() == 2: break
	check(simultaneous and seen.size() == 2,"Two separate shelters visibly show simultaneous residents "+mode)
	check(gathering,"Residents visibly gather or rest at both configured sites "+mode)
	var completed: Array = camp.history.filter(func(entry: Dictionary)->bool: return entry["guest"] != "player" and entry["state"] == "completed")
	check(completed.size() == 2 and completed[0]["site"] != completed[1]["site"] and camp.jobs.is_empty(),
		"Two residents walk through the complete independent camp routes "+mode+" "+str(camp.history)+" "+str(manager.residents.map(func(r: Dictionary)->String: return r["status"])))
	check(manager.residents.all(func(r: Dictionary)->bool:
		return r["visits"].filter(func(target: String)->bool: return target.begins_with("camp/")).size() == 5),
		"Physical resident arrivals include park, check-in, activity, rest and checkout "+mode)
	studio.set_walking(false)

func capture_residents(mode: String) -> void:
	camp.notice_time = 0
	await process_frame
	if mode == "2d":
		world.camera.zoom = Vector2.ONE * 1.65
		world.camera.global_position = Vector2(-15,25)
		world.camera.force_update_scroll()
		RenderingServer.force_draw(false)
		RenderingServer.force_draw(false)
	else:
		world.walking = false
		world.target = Vector3(0,0,2)
		world.distance = 26.0
		world.update_camera()
		await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUTPUT+"/residents_"+mode+"_1480.png") == OK,
		"Captured two simultaneously occupied campsites in "+mode)
	if mode == "3d":
		world.walking = true
		world.update_camera()
