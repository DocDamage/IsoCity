extends SceneTree

const Plan = preload("res://scripts/builder/ambience_plan.gd")
const Bank = preload("res://scripts/builder/ambience_bank.gd")
const Props = preload("res://scripts/builder/prop_plan.gd")
const Probe = preload("res://tools/ambience_audio_probe.gd")
const Templates = preload("res://scripts/builder/templates.gd")
const Document = preload("res://scripts/builder/document.gd")
const Portable = preload("res://scripts/builder/portable_export.gd")
const Repair = preload("res://scripts/builder/project_repair.gd")
const OUTPUT = "res://output/verification/asset_expansion/I18"
const PIER = "2d:Added_piers_pier_f248daea"
const CABINET = "2d:Arcade_Machine_Red"

var studio: Control
var world: Node
var visit: Node
var ambience: RefCounted
var runtime: Node
var checks: int
var failures: int

func _initialize() -> void: call_deferred("run")

func check(ok: bool, text: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: "+text)
	return ok

func settle() -> void:
	for frame in 8: await process_frame
	await physics_frame

func place(uid: String, asset: String, at: Vector2, scale_value: float = .72) -> Dictionary:
	var item: Dictionary = studio.current().add(asset,Plan.Traffic.world(at,studio.mode),studio.library.directions(asset)[0],scale_value)
	item["uid"] = uid
	item["name"] = uid.capitalize()
	return item

func reset_city(mode: String) -> RefCounted:
	studio.set_walking(false)
	studio.switch_mode(mode)
	var doc := Document.new()
	doc.data = Templates.make(mode,"blank")
	studio.documents[mode] = doc
	doc.data["title"] = "Place ambience fixture"
	world = studio.worlds[mode]
	visit = world.exploration
	ambience = studio.ambience_tools
	runtime = ambience.managers[mode]
	ambience.reset()
	return doc

func mix(frames: int = 180) -> void:
	for frame in frames: ambience.tick(1.0/60)

func sounds(kind: String) -> Array:
	return runtime.selected.filter(func(value: Dictionary)->bool: return value["kind"] == kind)

func quiet(kind: String) -> bool:
	return sounds(kind).is_empty() and runtime.voices.values().all(func(value: Dictionary)->bool: return value["kind"] != kind)

func at(point: Vector2) -> void:
	var spot: Array = Plan.Traffic.world(point,studio.mode,.08)
	world.player.teleport_to(Vector2(spot[0],spot[1]) if studio.mode == "2d" else Vector3(spot[0],spot[1],spot[2]))
	await physics_frame

func record(kind: String) -> void:
	if "--audio-proof" not in OS.get_cmdline_user_args(): return
	check(await Probe.record(studio,kind,OUTPUT+"/runtime_"+kind+"_"+studio.mode+".wav") == OK,
		"Record audible "+kind+" from the real spatial bus "+studio.mode)

func key(code: Key) -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	studio = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	while not studio.enhancements_ready: await process_frame
	if studio.consumer_shell: studio.consumer_shell.dismiss_welcome()
	for mode in ["2d","3d"]:
		await outdoor(mode)
		await arcade_room(mode)
	mixer_edges()
	studio.ambience_tools.reset()
	studio.free()
	OS.delay_msec(120)
	await process_frame
	print("PLACE AMBIENCE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func outdoor(mode: String) -> void:
	var doc: RefCounted = reset_city(mode)
	var market: Dictionary = place("market","2d:Supermarket" if mode == "2d" else "3d:HanX_Shop/Shop_Grocery",Vector2(0,-16),.6)
	market["business"] = {"kind":"none"}
	market["market"] = {"enabled":true,"offset_z":16.0,"capacity":3,"queue":2,"vendors":[{"kind":"fruit","stock":3,"price":5}]}
	var smith: Dictionary = place("smith","3d:HanX_Construction/Tool_Box",Vector2(24,-2))
	smith["village"] = {"enabled":true}
	doc.data["village"] = {"enabled":true}
	var pier: Dictionary = place("pier",PIER,Vector2(42,0))
	doc.data["terrain"] = {"enabled":true,"bounds":[-28,-28,60,56]}
	doc.data["water_cells"] = []
	studio.changed()
	await settle()
	var businesses: Node = studio.business_tools.managers[mode]
	businesses.set_physics_process(false)
	businesses.hour = 2
	businesses.step(.016,false)
	var village: Node = visit.village
	village.set_physics_process(false)
	studio.set_walking(true)
	world.player.set_physics_process(false)
	await settle()
	await at(Vector2(0,0))
	mix()
	check(quiet("market") and businesses.market.active.is_empty(),"Closed market art has no activity sound "+mode)
	businesses.hour = 12
	businesses.step(.016,false)
	mix()
	check(businesses.market.active.has("market") and sounds("market").size() == 1,
		"Actual market opening activates exactly one sound at the event "+mode+" "+str(businesses.market.notices))
	if not sounds("market").is_empty():
		var position: Vector3 = sounds("market")[0]["position"]
		var area: Rect2 = businesses.market.active["market"]["site"]["area"]
		check(Vector2(position.x,position.z).is_equal_approx(area.get_center()),"Market audio comes from the offset vendor row "+mode)
	await record("market")
	businesses.hour = 2
	businesses.step(.016,false)
	mix()
	check(quiet("market"),"Closing a real market releases its voice "+mode)
	if check(village.book.sites.has("smith") and not village.book.sites["smith"]["points"].is_empty(),"Forge has an actual approach "+mode):
		world.player.teleport_to(world.player.get_parent().to_local(village.position(village.book.sites["smith"]["points"][0])))
		await physics_frame
		mix()
		check(quiet("workshop"),"Idle forge has no workshop loop "+mode)
		visit.interact()
		if check(village.selected == "smith","E opens the village forge at its valid approach "+mode):
			village.view.buttons["forge"].pressed.emit()
			village.close()
			village.step(.25)
			mix()
			check(village.book.batches.has("smith") and sounds("workshop").size() == 1,"A real smith recipe produces localized work audio "+mode)
			await record("workshop")
			for step in 52: village.step(.25)
			mix()
			check(village.book.stock("smith","tools") == 2 and quiet("workshop"),"Completed forge orders stop the workshop loop "+mode)
	await at(Vector2(40,0))
	mix()
	check(quiet("harbor"),"Dry decorative pier does not sound like a harbor "+mode)
	doc.data["water_cells"] = [{"cell":[21,0],"level":.75}]
	studio.changed()
	await settle()
	mix()
	check(quiet("harbor"),"A lone wet cell cannot start a harbor sound "+mode)
	doc.data["water_cells"].append({"cell":[21,1],"level":.75})
	studio.changed()
	await settle()
	mix()
	check(sounds("harbor").size() == 1 and sounds("harbor")[0]["position"].y > .75,"Connected wet shoreline activates the pier's spatial sound "+mode)
	await record("harbor")
	if "--portable" in OS.get_cmdline_user_args():
		var data: Dictionary = doc.data.duplicate(true)
		for item in data["objects"]:
			if item["uid"] == "market": item["market"]["goods_style"] = "hanx"
			if item["uid"] != "pier": continue
			item["asset"] = "2d:crate"
			item["direction"] = studio.library.directions(item["asset"])[0]
			item["audio"] = {"kind":"harbor","range":18,"volume":.8}
		var result: Dictionary = Portable.new().save(world,data,studio.library,OUTPUT+"/place_"+mode+".zip")
		check(result["ok"],"The allowed shoreline fixture packages all sound dependencies "+mode+" "+result.get("message",""))
	pier["visible"] = false
	studio.changed()
	await settle()
	mix()
	check(quiet("harbor"),"Hidden shoreline anchors retire the harbor voice "+mode)
	pier["visible"] = true
	doc.data["water_cells"].clear()
	studio.changed()
	await settle()
	mix()
	check(quiet("harbor"),"Draining terrain clears shoreline audio through cache invalidation "+mode)
	studio.set_walking(false)
	await author_settings(mode,doc)

func author_settings(mode: String, doc: RefCounted) -> void:
	studio.selected_uid = "pier"
	studio.selected_uids.assign(["pier"])
	studio._command("ambience",null)
	ambience.categories["harbor"].value = 83
	ambience.apply_mix.pressed.emit()
	var sound: OptionButton = ambience.source_kind
	for index in sound.item_count:
		if sound.get_item_metadata(index) == "harbor": sound.select(index)
	ambience.source_volume.value = 62
	ambience.source_range.value = 17
	ambience.apply_source.pressed.emit()
	var data: Dictionary = doc.data.duplicate(true)
	check(data["ambience"]["harbor"] == .83 and doc.object("pier")["audio"].get("kind") == "harbor" and
		doc.object("pier")["audio"]["range"] == 17 and Document.valid(data,mode,studio.library),"City and source audio controls author valid place settings "+mode)
	studio._command("undo",null)
	check(not doc.object("pier").has("audio"),"Undo restores automatic pier sound "+mode)
	studio._command("redo",null)
	check(doc.data == data,"Redo restores exact authored audio overrides "+mode)
	await capture_settings(mode)
	var path: String = OUTPUT+"/place_"+mode+("_capture" if "--capture" in OS.get_cmdline_user_args() else "")+".isocity.json"
	check(studio.write_project(path,false),"Normal Save writes place audio settings "+mode)
	var repair: RefCounted = Repair.new(studio.library)
	var saved: Dictionary = repair.read(path)
	var restored: Dictionary = saved.get("content",{}).get("documents",{}).get(mode,{})
	check(saved["ok"] and repair.issues.is_empty() and restored["ambience"]["harbor"] == .83 and
		restored["objects"].filter(func(item: Dictionary)->bool: return item["uid"] == "pier")[0]["audio"]["range"] == 17,
		"Normal reopen keeps sound settings without serializing voices "+mode)

func capture_settings(mode: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	for simple in [false,true]:
		studio.consumer_shell.set_active(simple,false)
		studio.consumer_shell.dismiss_welcome()
		for size in [Vector2i(1480,900),Vector2i(960,640)]:
			root.size = size
			studio.accessibility_settings.restore({"text_scale":1.5,"high_contrast":true,"large_targets":true} if size.x == 960 else {})
			studio._command("ambience",null)
			await settle()
			var field: LineEdit = ambience.categories["harbor"].get_line_edit()
			field.grab_focus()
			await settle()
			check(field.has_focus() and ambience.page.get_global_rect().encloses(field.get_global_rect())
				and field.accessibility_name == "Harbor shores (%)","Place sliders take focus and fit "+str([mode,simple,size,field.get_global_rect(),ambience.page.get_global_rect(),ambience.page.scroll_horizontal]))
			RenderingServer.force_draw(false)
			RenderingServer.force_draw(false)
			var path: String = OUTPUT+"/settings_%s_%s_%d.png" % [mode,"simple" if simple else "precision",size.x]
			check(root.get_texture().get_image().save_png(path) == OK,"Captured the actual ambience controls "+path)
			field.release_focus()
	root.size = Vector2i(1480,900)
	studio.accessibility_settings.restore({})
	studio.consumer_shell.set_active(false,false)

func arcade_room(mode: String) -> void:
	var doc: RefCounted = reset_city(mode)
	var host: Dictionary = place("venue","2d:Arcade" if mode == "2d" else "3d:HanX_Shop/Shop_Grocery",Vector2.ZERO,.75)
	host["business"] = {"kind":"none"}
	doc.data["arcade"] = {"enabled":true}
	studio.changed()
	studio.interior_tools.start("venue","ground","empty")
	studio.current().data["objects"] = []
	var machine: Dictionary = place("cabinet",CABINET,Vector2(-3,-3))
	machine["arcade"] = {"enabled":true,"game":"signals"}
	studio.changed()
	var floors: RefCounted = studio.interior_tools.floor_tools
	floors.new_name.text = "Upstairs arcade"
	floors.new_height.value = 3
	floors.add_floor()
	var upper: String = studio.current().floor_uid
	studio.current().data["objects"] = [machine.duplicate(true)]
	studio.changed()
	studio.interior_tools.leave()
	await settle()
	studio.set_walking(true)
	world.player.set_physics_process(false)
	var arcade: Node = visit.arcade
	arcade.set_physics_process(false)
	var previous: Dictionary = studio.control_settings.bindings.duplicate(true)
	studio.control_settings.bindings = studio.control_settings.default_bindings()
	check(studio.control_settings.assign("ambience_mute",0,KEY_F9).is_empty(),"A real mute binding can be remapped "+mode)
	var budget: Dictionary = doc.data.duplicate(true)
	for turn in 3:
		world.player.teleport_to(visit.entrance(world.instances["venue"]))
		await settle()
		visit.interact()
		await settle()
		if not check(visit.interior_uid == "venue","Walk enters the actual cabinet room "+mode): break
		world.player.set_physics_process(false)
		var floor: String = upper if turn == 1 else "ground"
		if floor != "ground":
			if mode == "2d": visit.interior.floor_stack.switch_floor(floor)
			else: world.player.teleport_to(Vector3(0,3.1,2.5))
			await settle()
		check(visit.active_floor() == floor,"Repeated visits can select the intended owned floor "+mode)
		var station: Dictionary = arcade.local_station("cabinet")
		if not check(not station.is_empty(),"Cabinet is playable on the actual floor "+mode): break
		var approach: Variant = Props.ground_point(station,visit,"approach")
		world.player.teleport_to(world.player.get_parent().to_local(approach))
		await physics_frame
		visit.interact()
		mix()
		if not check(arcade.session.get("phase") == "ready" and quiet("arcade"),"Ready cabinet art is silent before the game starts "+mode): break
		arcade.primary()
		mix()
		var audible: Array = sounds("arcade")
		check(audible.size() == 1 and audible[0]["uid"] == "room:venue:"+floor+":cabinet:place:arcade","Playing state activates only the actual room cabinet "+mode)
		if turn == 0:
			await record("arcade")
			await key(KEY_F9)
			mix()
			check(ambience.muted and quiet("arcade") and arcade.session.get("phase") == "playing","Remapped mute works inside arcade gameplay "+mode)
			await key(KEY_F9)
			mix()
			check(not ambience.muted and sounds("arcade").size() == 1,"Remapped unmute restores the running game loop "+mode)
		arcade.primary()
		mix()
		check(arcade.session.get("phase") == "paused" and quiet("arcade"),"Paused games stop their place audio "+mode)
		arcade.primary()
		mix()
		arcade.close("Ended audio test visit.")
		visit.leave_interior()
		await settle()
		mix()
		check(runtime.voices.keys().all(func(uid: String)->bool:return not uid.begins_with("room:venue:")) and
			runtime.stage.get_child_count() == runtime.voices.size()+1,"Leaving retires all native room voices without leaks "+mode)
	studio.control_settings.bindings = previous
	studio.control_settings.persist()
	check(doc.data == budget,"Live activity and mute leave authored records exact "+mode)
	studio.set_walking(false)

func mixer_edges() -> void:
	var sound: Dictionary = Plan.definitions()["kinds"]["workshop"].duplicate()
	sound.merge({"uid":"working","position":Vector3.ZERO,"kind":"workshop"})
	var source: Array = []
	for index in 50:
		var value: Dictionary = sound.duplicate()
		value["uid"] = "forge_%03d" % index
		value["position"] = Vector3(float(index/10)*2,0,0)
		source.append(value)
	source.append(source[0])
	check(Plan.mix(source,Vector3.ZERO,Plan.defaults()).size() == Plan.PLACE_VOICES,"Colocated and repeated busy emitters share a bounded voice budget")
	check(Bank.load_loop("res://assets/audio/missing_fixture.wav") == null and
		Bank.load_loop("res://resources/catalog/ambience.json") == null,"Missing and unsupported audio resources fall silent")
	var old: AudioStreamWAV = Bank.stream("workshop")
	Bank.streams["workshop"] = null
	var valid: Dictionary = Plan.definitions()["kinds"]["interior"].duplicate()
	valid.merge({"uid":"room","position":Vector3.ZERO,"kind":"interior"})
	runtime.step(.25,[sound,valid],Vector3.ZERO,Plan.defaults())
	check(runtime.voices.has("room") and not runtime.voices.has("working"),"An unavailable high-priority stream never starves a playable source")
	Bank.streams["workshop"] = old
	var doc: RefCounted = studio.current()
	var authored: Dictionary = doc.object("venue")
	authored["audio"] = {"kind":"workshop","range":12,"volume":.4}
	var work: Dictionary = Plan.emitters(doc.data,studio.library,12,0,"city:",world.instances,{"venue":{"workshop":.7,"market":1.0}})[0]
	check(work["kind"] == "workshop" and work["range"] == 12 and is_equal_approx(work["gain"],.7*.4*.7),"Explicit sound, gain and range take precedence over competing activity")
	check(Plan.emitters(doc.data,studio.library).is_empty(),"An activity override cannot invent an inactive workshop")
	authored["audio"]["kind"] = "none"
	check(Plan.emitters(doc.data,studio.library,12,0,"city:",world.instances,{"venue":{"workshop":1}}).is_empty(),"Silent override wins over activity")
	authored.erase("audio")
