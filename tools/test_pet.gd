extends SceneTree

const Plan = preload("res://scripts/builder/pet_plan.gd")
const Props = Plan.Props
const Templates = preload("res://scripts/builder/templates.gd")
const Repair = preload("res://scripts/builder/project_repair.gd")
const Portable = preload("res://scripts/builder/portable_export.gd")
const DOG = "2d:Dog_Golden"
const CAT = "2d:Cat_Orange"
const MAT = "2d:Rug_Round_Pink"
const STATION = "3d:HanX_Park/Dog_Station"
const WALL = "3d:HanX_Park/Bench_Park"
const HOUSE = {"2d":"2d:Apartment_Brick","3d":"3d:HanX_City/Apartment_4F_A"}
const CAR = {"2d":"2d:Police_Car","3d":"3d:HanX_Traffic/Car_Hatchback"}
const OUTPUT = "res://output/verification/asset_expansion/N13"

var studio: Control
var world: Node
var pet: Node
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

func placed(id: String, point: Vector2, title: String) -> Dictionary:
	var mode: String = studio.mode
	var record: Dictionary = studio.current().add(id,Plan.Utility.Traffic.world(Plan.terrain_point(point,mode),mode),
		str(studio.library.directions(id)[0]),1.0)
	record["name"] = title
	return record

func select(control: OptionButton, value: Variant) -> void:
	for index in control.item_count:
		if control.get_item_metadata(index) == value:
			control.select(index)
			control.item_selected.emit(index)
			return

func setup(mode: String) -> Dictionary:
	studio.switch_mode(mode)
	studio.current().data = Templates.make(mode,"blank")
	studio.current().data["economy"] = {"enabled":true,"starting_cash":50000}
	var mat: Dictionary = placed(MAT,Vector2(-5,0),"Home resting mat")
	var station: Dictionary = placed(STATION,Vector2(3,4),"Park dog station")
	var wall: Dictionary = placed(WALL,Vector2.ZERO,"Garden barrier")
	studio.changed()
	world = studio.worlds[mode]
	pet = world.exploration.pet
	pet.set_physics_process(false)
	tools = studio.pet_tools
	return {"mat":mat["uid"],"station":station["uid"],"wall":wall["uid"]}

func author(asset: String, home: Array, station: String = "") -> void:
	studio._command("pet",null)
	tools.enabled.button_pressed = true
	select(tools.species,asset)
	select(tools.home,home)
	select(tools.station,station)
	tools.apply.pressed.emit()

func begin_walk() -> void:
	studio.set_walking(true)
	world.player.set_physics_process(false)
	await settle()
	pet.step(.016)

func player_at(point: Vector2) -> void:
	var target: Variant = pet.nav.position(point)
	world.player.teleport_to(world.player.get_parent().to_local(target))
	await physics_frame

func menu(point: Vector2, action: String, word: String = "commands") -> bool:
	await player_at(point)
	var prompt: String = world.exploration.interaction_prompt()
	if not check(word in prompt,"The normal E prompt reads '%s', got '%s'." % [word,prompt]): return false
	world.exploration.interact()
	if not check(pet.has_menu() and pet.view.buttons[action].visible,"The command overlay exposes "+action): return false
	pet.view.buttons[action].pressed.emit()
	return check(not pet.has_menu(),"The command returns to walking.")

func walk_until_stay(limit: int = 700) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for frame in limit:
		pet.step(1.0/60)
		points.append(pet.nav.metric(pet.actor.body.global_position))
		if pet.motion in ["stay","blocked"]: break
	return points

func run() -> void:
	studio = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	while not studio.enhancements_ready: await process_frame
	studio.consumer_shell.dismiss_welcome()
	for kind in Plan.definitions()["species"]:
		for id in Plan.definitions()["species"][kind]:
			check(Plan.supported(id,studio.library),"Reviewed "+kind+" supports four explicit animation views: "+id)
	check(not Plan.supported("3d:Supplemental_SWAT/SWAT_K9_Dog_Stand",studio.library),"Static SWAT K9 does not qualify as a pet.")
	for mode in ["2d","3d"]: await outdoor(mode)
	for mode in ["2d","3d"]: await indoor(mode)
	await world_switch()
	studio.free()
	await process_frame
	print("PET WORKFLOW: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func outdoor(mode: String) -> void:
	var ids: Dictionary = setup(mode)
	var doc: RefCounted = studio.current()
	check(not Plan.settings(doc.data)["enabled"] and not is_instance_valid(pet.actor.body),"The pet preview is disabled by default "+mode)
	author(DOG,["","ground",ids["mat"]],ids["station"])
	var settings: Dictionary = Plan.settings(doc.data)
	if not check(settings["enabled"] and settings["asset"] == DOG and settings["home"] == ids["mat"],
		"Normal controls save the selected pet and mat "+mode+" "+tools.notice.text): return
	studio._command("undo",null)
	check(not Plan.settings(doc.data)["enabled"],"Undo restores the disabled setting "+mode)
	studio._command("redo",null)
	check(Plan.settings(doc.data) == settings,"Redo restores exact companion ownership settings "+mode)
	await capture_authoring()
	await begin_walk()
	if not check(is_instance_valid(pet.actor.body),"The real pet scene spawns "+mode+" "+pet.status): return
	var budget: Dictionary = doc.data.get("economy_account",{}).duplicate(true)
	var body: Node = pet.actor.body
	var origin: Vector2 = pet.nav.metric(body.global_position)
	check(body.collision_layer == 0 and body.collision_mask == 1 and body.get_meta("pet_owner") == "local",
		"The owned companion respects barriers without blocking pedestrians "+mode)
	check(pet.actor.source.is_pet and pet.actor.source.sprite.frame == 5,"Pet starts in its supplied resting pose "+mode)
	await capture_commands(origin+Vector2(-.9,0))
	if not await menu(origin+Vector2(-.9,0),"follow"): return
	await player_at(Vector2(5,0))
	var walked: bool = false
	var around: bool = false
	var caught_up: bool = false
	var longest_step: float = 0
	var previous: Vector2 = origin
	for frame in 600:
		pet.step(1.0/60)
		var current: Vector2 = pet.nav.metric(body.global_position)
		walked = walked or (pet.actor.action == "walk" and pet.actor.source.sprite.frame in [2,3,4])
		around = around or absf(current.y-origin.y) > .65
		caught_up = caught_up or pet.status == "Catching up."
		longest_step = maxf(longest_step,previous.distance_to(current))
		previous = current
		if current.distance_to(Vector2(5,0)) < 1.6: break
	check(walked and around and previous.x > 3.0 and longest_step < .13 and caught_up,
		"Follow uses actual walking frames and goes around the barrier without a teleport "+mode+" "+str([pet.status,previous,longest_step,around]))
	if not await menu(previous+Vector2(0,1),"stay"): return
	await player_at(Vector2(5,1))
	var stayed: Variant = body.global_position
	for frame in 120: pet.step(1.0/60)
	check(body.global_position == stayed and pet.motion == "stay","Stay holds position while the owner leaves "+mode)
	await player_at(previous+Vector2(0,1.8))
	if not await menu(previous+Vector2(0,1.8),"come"): return
	await player_at(Vector2(6,2.5))
	walk_until_stay()
	check(pet.motion == "stay" and pet.nav.metric(body.global_position).distance_to(Vector2(6,2.5)) < 1.7,
		"Come reaches the owner and waits "+mode+" "+pet.status)
	var station: Variant = pet.fixture(Props.context(world.exploration),"park")
	if not check(station != null,"The dog equipment has a clear approach "+mode): return
	if not await menu(station,"practice","Dog station"): return
	walk_until_stay()
	check(pet.pose == "sit" and pet.status.contains("dog station") and pet.nav.metric(body.global_position).distance_to(station) < .4,
		"Park practice reaches the actual dog equipment and sits "+mode+" "+str([pet.status,pet.nav.metric(body.global_position),station]))
	if not await menu(station+Vector2(.2,0),"rest","Dog station"): return
	walk_until_stay()
	check(pet.pose == "sit" and pet.nav.metric(body.global_position).distance_to(origin) < .4 and pet.status == "Resting at home.",
		"Rest returns to the mat and uses the supported sit pose "+mode+" "+pet.status)
	if not await menu(origin+Vector2(-.9,0),"follow"): return
	await player_at(Vector2(28,0))
	pet.step(.06)
	check(pet.status.contains("Out of range") and pet.nav.metric(body.global_position).distance_to(origin) < .4,
		"Leash limits keep the pet on its side of a long gap "+mode)
	await player_at(Vector2(-2,0))
	for frame in 200: pet.step(1.0/60)
	check(pet.nav.metric(body.global_position).distance_to(Vector2(-2,0)) < 1.6,"Follow resumes when the owner comes into range "+mode)
	pet.command("home")
	walk_until_stay()
	check(pet.motion == "stay" and pet.pose == "idle" and pet.nav.metric(body.global_position).distance_to(origin) < .4,
		"Return home walks to the mat and waits standing "+mode)
	check(doc.data.get("economy_account",{}) == budget,"All commands leave the project treasury unchanged "+mode)
	studio.set_walking(false)
	var path: String = OUTPUT+"/pet_"+mode+("_capture" if "--capture" in OS.get_cmdline_user_args() else "")
	check(studio.write_project(path+".isocity.json",false),"Normal Save writes authored companion settings "+mode)
	var repair: RefCounted = Repair.new(studio.library)
	var saved: Dictionary = repair.read(path+".isocity.json")
	check(saved["ok"] and repair.issues.is_empty() and Plan.settings(saved["content"]["documents"][mode]) == settings,
		"Reopening preserves settings without preview actor state "+mode)
	if "--portable" in OS.get_cmdline_user_args():
		var result: Dictionary = Portable.new().save(world,doc.data,studio.library,path+".zip")
		check(result["ok"],"Portable project includes the selected companion "+mode+" "+result.get("message",""))
	check(studio.load_project(path+".isocity.json"),"The editor can reopen the companion project "+mode)
	check(not is_instance_valid(pet.actor.body),"Reload clears the local preview actor "+mode)
	await safety(ids)

func safety(ids: Dictionary) -> void:
	var mode: String = studio.mode
	var doc: RefCounted = studio.current()
	var initial: Dictionary = doc.data.duplicate(true)
	var car: Dictionary = placed(CAR[mode],Vector2(-6,4),"Pet owner's car")
	var building: Dictionary = placed(HOUSE[mode],Vector2(-12,4),"Pet owner's home")
	studio.changed()
	await begin_walk()
	if not check(is_instance_valid(pet.actor.body),"The saved pet spawns again in Walk "+mode): return
	var body: Node = pet.actor.body
	var position: Variant = body.global_position
	var walk: Node = world.exploration
	pet.command("follow")
	var drive: Node = walk.driving
	var board: Dictionary = {}
	var car_point: Vector2 = Vector2(-6,4)
	for offset in [Vector2(2,0),Vector2(-2,0),Vector2(0,2),Vector2(0,-2)]:
		await player_at(car_point+offset)
		board = drive.nearby(car["uid"])
		if not board.is_empty(): break
	if check(not board.is_empty() and drive.interact(board),"Owner boards a real vehicle "+mode):
		for frame in 40: pet.step(1.0/60)
		check(pet.status.contains("vehicle") and body.global_position == position,"Pet waits safely outside while the vehicle is occupied "+mode)
		check(drive.exit_vehicle(true),"Owner leaves the vehicle safely "+mode)
	var entry: Variant = walk.entrance(world.instances[building["uid"]])
	world.player.teleport_to(entry)
	await settle()
	walk.interact()
	await settle()
	pet.step(.05)
	check(walk.interior != null and pet.status.contains("outdoors") and body.global_position == position
		and not body.is_visible_in_tree(),"Entering a building keeps the pet at its outdoor spot "+mode)
	if walk.interior: walk.leave_interior()
	await settle()
	pet.step(.05)
	check(pet.actor.body == body and body.is_visible_in_tree(),"Returning outside recovers the same companion body "+mode)
	var target := Vector2(4,0)
	var middle: Vector2i = Vector2i((Plan.terrain_point(target,mode)/Plan.Terrain.CELL_SIZE).floor())
	var water: Array = []
	for x in range(-2,3):
		for y in range(-2,3): water.append({"cell":[middle.x+x,middle.y+y],"level":2.0})
	doc.data["terrain"] = {"enabled":true,"bounds":[-20,-20,40,40]}
	doc.data["water_cells"] = water
	studio.changed()
	await settle()
	pet.step(.016)
	await player_at(target)
	pet.command("come")
	var before: Variant = body.global_position
	walk_until_stay()
	check(not pet.nav.safe(target) and pet.motion == "blocked" and pet.retries == pet.RETRY_LIMIT
		and body.global_position == before and pet.status.contains("clear route"),"Deep water yields a visible and bounded retry without warping "+mode+" "+pet.status)
	doc.data = initial
	studio.changed()
	await settle()
	pet.step(.016)
	await physical_stall()
	var sprite: Sprite2D = pet.actor.source.sprite
	var frame_count: int = sprite.hframes
	sprite.hframes = 2
	pet.actor.animate("walk",.1)
	check(pet.actor.missing and sprite.frame == 0,"Missing animation frames use a supported idle fallback "+mode)
	sprite.hframes = frame_count
	var identity: Callable = pet.owner_key
	pet.owner_key = func()->String: return ""
	pet.step(.016)
	check(not is_instance_valid(pet.actor.body) and pet.status.contains("owner"),"An unavailable owner releases the local actor "+mode)
	pet.owner_key = identity
	pet.step(.016)
	check(is_instance_valid(pet.actor.body) and pet.actor.body.get_meta("pet_owner") == "local","Owner return recreates only its own pet "+mode)
	var damaged: Dictionary = initial.duplicate(true)
	damaged["pet"]["leash"] = -3
	damaged["pet"]["future"] = "retained"
	var repaired: Dictionary = Repair.new(studio.library).world(damaged,mode,"damaged_pet",0)
	check(not Plan.settings(repaired)["enabled"] and repaired["pet"]["future"] == "retained"
		and repaired["pet"]["home"] == ids["mat"],"Repair disables malformed settings and preserves valid authored fields "+mode)
	studio.set_walking(false)

func physical_stall() -> void:
	var mode: String = studio.mode
	pet.command("rest")
	walk_until_stay()
	var start: Vector2 = pet.nav.metric(pet.actor.body.global_position)
	var obstruction: Node
	var barrier: Variant = pet.nav.position(start+Vector2(1.0,0))
	if mode == "2d":
		obstruction = StaticBody2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(6,150)
		var collider := CollisionShape2D.new()
		collider.shape = shape
		obstruction.add_child(collider)
	else:
		obstruction = StaticBody3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(.35,1.4,18)
		var collider := CollisionShape3D.new()
		collider.shape = shape
		obstruction.add_child(collider)
		barrier += Vector3.UP*.5
	world.objects.add_child(obstruction)
	obstruction.global_position = barrier
	await player_at(start+Vector2(3,0))
	pet.command("come")
	var samples: Array[Vector2] = walk_until_stay()
	check(pet.motion == "blocked" and pet.retries == pet.RETRY_LIMIT
		and samples.all(func(point: Vector2)->bool: return point.x < start.x+1.0),
		"A physical obstruction stops the pet on its own side after bounded retries "+mode+" "+str([pet.status,pet.retries,samples.back()]))
	obstruction.free()
	await physics_frame
	pet.command("come")
	walk_until_stay()
	check(pet.motion == "stay" and pet.nav.metric(pet.actor.body.global_position).x > start.x+1.0,
		"A new Come command resumes walking when the obstacle is gone "+mode)

func indoor(mode: String) -> void:
	setup(mode)
	var doc: RefCounted = studio.current()
	var host: Dictionary = placed(HOUSE[mode],Vector2(4,5),"Cat's home")
	var room: Dictionary = Templates.make(mode,"blank")
	room["interior_room"] = true
	room["exit"] = [-100,80,0] if mode == "2d" else [-5,.05,6]
	room["objects"] = [{"uid":"cat_mat","asset":MAT,"position":Plan.Utility.Traffic.world(Vector2(-5,-3),mode),
		"direction":"SE","scale":1.0}]
	var upstairs: Dictionary = room.duplicate(true)
	room["floors"] = [{"uid":"top","name":"Top","height":3.0,"room":upstairs}]
	room["floor_links"] = [{"uid":"lift","kind":"elevator","lower":"ground","upper":"top","start":[0,0],"end":[0,0],"width":1.4}]
	host["interior"] = room
	studio.changed()
	author(CAT,[host["uid"],"ground","cat_mat"])
	check(Plan.settings(doc.data)["asset"] == CAT and tools.station.disabled,"Indoor cat uses a scoped mat with no dog station "+mode)
	await begin_walk()
	check(not is_instance_valid(pet.actor.body) and pet.status.contains("assigned floor"),"Indoor pet stays on its assigned floor "+mode)
	var walk: Node = world.exploration
	walk.enter_preview(host,room,"ground",Vector2(0,45) if mode == "2d" else Vector3(0,.05,2.5))
	await settle()
	pet.step(.05)
	if not check(walk.interior != null and is_instance_valid(pet.actor.body) and pet.actor.source.item_id == "Cat_Orange",
		"The actual Cat Orange sprite spawns only on the authored floor "+mode+" "+pet.status): return
	var body: Node = pet.actor.body
	var spot: Variant = body.global_position
	var local_spot: Vector2 = pet.nav.metric(spot)
	var lift: Node = walk.interior.floor_stack.lifts.get("lift")
	if not check(is_instance_valid(lift),"The authored room creates a real elevator "+mode): return
	world.player.teleport_to(Vector2.ZERO if mode == "2d" else Vector3(0,.05,0))
	await settle()
	walk.interact()
	if not check(lift.menu.visible,"E opens the normal elevator floor chooser "+mode): return
	lift.choose("top")
	pet.step(.05)
	check(lift.rider and pet.status.contains("change floors") and body.global_position == spot,
		"The pet waits at its current mat during actual elevator travel "+mode)
	for frame in 1600:
		await physics_frame
		if lift.phase == "idle" and lift.last_stop == "top": break
	pet.step(.05)
	check(walk.active_floor() == "top" and not body.is_visible_in_tree() and pet.status.contains("assigned floor"),
		"The identically named mat upstairs does not move or duplicate the pet "+mode)
	walk.leave_interior()
	await settle()
	walk.enter_preview(host,room,"ground",Vector2(0,45) if mode == "2d" else Vector3(0,.05,2.5))
	await settle()
	pet.step(.05)
	check(is_instance_valid(pet.actor.body) and pet.nav.metric(pet.actor.body.global_position).distance_to(local_spot) < .05,
		"Returning to the assigned room restores the same resting location "+mode)
	studio.set_walking(false)

func world_switch() -> void:
	var ids: Dictionary = setup("2d")
	author(DOG,["","ground",ids["mat"]])
	await begin_walk()
	var body: Node = pet.actor.body
	studio.switch_mode("3d")
	var other: Node = studio.worlds["3d"].exploration.pet
	check(not studio.walking and is_instance_valid(body) and not body.is_visible_in_tree()
		and Plan.settings(studio.current().data)["asset"] == CAT and not is_instance_valid(other.actor.body),
		"Switching to the Model world retains its own cat settings and hides the Pixel dog.")
	studio.switch_mode("2d")
	await begin_walk()
	check(pet.actor.body == body and body.is_visible_in_tree() and Plan.settings(studio.current().data)["asset"] == DOG,
		"Returning to the Pixel world resumes the same dog without moving an actor between worlds.")
	studio.set_walking(false)

func native() -> bool:
	return "--capture" in OS.get_cmdline_user_args()

func capture_authoring() -> void:
	if not native(): return
	for simple in [false,true]:
		studio.consumer_shell.set_active(simple,false)
		studio.consumer_shell.dismiss_welcome()
		for size in [Vector2i(1480,900),Vector2i(960,640)]:
			root.size = size
			studio.accessibility_settings.restore({"text_scale":1.5,"high_contrast":true,"large_targets":true} if size.x == 960 else {})
			studio._command("pet",null)
			await settle()
			tools.apply.grab_focus()
			await settle()
			check(tools.apply.has_focus() and tools.panel.get_global_rect().encloses(tools.apply.get_global_rect())
				and Rect2(Vector2.ZERO,Vector2(size)).encloses(tools.apply.get_global_rect()),"Authoring Apply stays keyboard reachable "+str([studio.mode,simple,size]))
			capture("authoring",simple,size.x)
			tools.apply.release_focus()
	restore_layout()

func capture_commands(point: Vector2) -> void:
	if not native(): return
	await player_at(point)
	await settle()
	capture("companion",false,1480)
	for simple in [false,true]:
		studio.consumer_shell.set_active(simple,false)
		studio.consumer_shell.dismiss_welcome()
		for size in [Vector2i(1480,900),Vector2i(960,640)]:
			root.size = size
			studio.accessibility_settings.restore({"text_scale":1.5,"high_contrast":true,"large_targets":true} if size.x == 960 else {})
			await settle()
			world.exploration.interact()
			await settle()
			var follow: Button = pet.view.buttons["follow"] if pet.has_menu() else null
			if check(is_instance_valid(follow) and follow.has_focus() and Rect2(Vector2.ZERO,Vector2(size)).encloses(follow.get_global_rect())
				and (size.x != 960 or follow.get_theme_font_size("font_size") == 23),"Walk commands keep visible scaled keyboard focus "+str([studio.mode,simple,size])):
				capture("commands",simple,size.x)
			pet.close()
	restore_layout()

func capture(phase: String, simple: bool, width: int) -> void:
	RenderingServer.force_draw(false)
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(OUTPUT+"/%s_%s_%s_%d.png" % [phase,studio.mode,"simple" if simple else "precision",width]) == OK,
		"Captured the actual pet workflow.")

func restore_layout() -> void:
	root.size = Vector2i(1480,900)
	studio.accessibility_settings.restore({})
	studio.consumer_shell.set_active(false,false)
