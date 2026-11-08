extends SceneTree

const Plan = preload("res://scripts/builder/fitness_plan.gd")
const Court = preload("res://scripts/builder/fitness_court.gd")
const Props = preload("res://scripts/builder/prop_plan.gd")
const Utility = preload("res://scripts/builder/utility_profiles.gd")
const Reservations = preload("res://scripts/builder/activity_reservations.gd")
const Templates = preload("res://scripts/builder/templates.gd")
const Doc = preload("res://scripts/builder/document.gd")
const Repair = preload("res://scripts/builder/project_repair.gd")
const Portable = preload("res://scripts/builder/portable_export.gd")
const ActorAnimation = preload("res://scripts/character_animation.gd")
const OUTPUT = "res://output/verification/asset_expansion/N10"
const HOST = {"2d":"2d:Supermarket","3d":"3d:HanX_School/Gym_Building"}
const GOAL = {"2d":"2d:Reviewed_village_soccer_goal_0","3d":"3d:HanX_School/Soccer_Goal"}
const EQUIPMENT = {
	"cycle":"2d:Supplemental_Gym_fitness_kit_exercise_bike_bd2e7760",
	"treadmill":"2d:Supplemental_Gym_fitness_kit_treadmill_4ecc12e0",
	"row":"2d:Supplemental_Gym_fitness_kit_rowing_machine_5c906166"}

var studio: Control
var tools: RefCounted
var world: Node
var fitness: Node
var clock: Node
var site: String
var stations: Dictionary = {}
var checks: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: "+text)

func settle() -> void:
	for i in 7: await process_frame
	await physics_frame

func place(asset: String, at: Vector2, dir: String = "") -> String:
	if dir.is_empty(): dir = str(studio.library.directions(asset)[0])
	return studio.current().add(asset,Utility.Traffic.world(at,studio.mode),dir,
		float(studio.library.assets[asset]["data"].get("default_scale",1)))["uid"]

func select(uid: String) -> void:
	studio.selected_uid = uid
	studio.selected_uids.assign([uid])
	tools.refresh()

func author(uid: String, open: float = 0, close: float = 0, enabled: bool = true) -> void:
	select(uid)
	tools.station_enabled.button_pressed = enabled
	tools.opening.value = open
	tools.closing.value = close
	tools.apply_station.pressed.emit()

func blank(mode: String) -> void:
	studio.set_walking(false)
	studio.switch_mode(mode)
	studio.current().data = Templates.make(mode,"blank")
	studio.current().data["economy"] = {"enabled":true,"starting_cash":60000}
	studio.changed()
	world = studio.worlds[mode]
	fitness = world.exploration.fitness
	fitness.set_physics_process(false)
	fitness.reset()
	clock = studio.business_tools.managers[mode]
	clock.set_physics_process(false)
	clock.hour = 10
	studio._command("fitness",null)
	check(not Plan.enabled(studio.current().data) and not tools.enabled.button_pressed,"Sports starts disabled in "+mode)
	tools.enabled.button_pressed = true
	tools.apply_city.pressed.emit()
	check(Plan.enabled(studio.current().data),"The city sports switch commits in "+mode)

func setup_gym(mode: String) -> void:
	await blank(mode)
	site = place(HOST[mode],Vector2.ZERO)
	studio.current().object(site)["business"] = {"kind":"none"}
	studio.changed()
	studio.interior_tools.start(site,"ground","empty")
	studio.current().data["objects"] = []
	stations = {
		"cycle":place(EQUIPMENT["cycle"],Vector2(-8,-6),"315"),
		"treadmill":place(EQUIPMENT["treadmill"],Vector2(0,-6),"0"),
		"row":place(EQUIPMENT["row"],Vector2(8,-6),"90"),
		"ordinary":place(EQUIPMENT["treadmill"],Vector2(15,-12),"135"),
	}
	studio.changed()
	studio._command("fitness",null)
	author(stations["cycle"],9,16)
	author(stations["treadmill"],9,16)
	author(stations["row"],9,16)
	studio._command("undo",null)
	check(Plan.station(studio.current().object(stations["row"]),mode).is_empty(),"Undo restores the previous rower setting.")
	studio._command("redo",null)
	check(not Plan.station(studio.current().object(stations["row"]),mode).is_empty(),"Redo restores the reviewed rower.")
	await capture_authoring(mode)
	studio.interior_tools.leave()
	await settle()
	check(Doc.valid(studio.current().data,mode,studio.library),"Nested sports profiles validate in "+mode)

func enter() -> bool:
	if not studio.walking: studio.set_walking(true)
	world.player.set_physics_process(false)
	world.player.teleport_to(world.exploration.entrance(world.instances[site]))
	await settle()
	world.exploration.interact()
	await settle()
	var ok: bool = world.exploration.interior_uid == site
	check(ok,"The normal Walk entry reaches the gym in "+studio.mode)
	if ok: world.player.set_physics_process(false)
	return ok

func at_position(point: Variant) -> void:
	world.player.teleport_to(world.player.get_parent().to_local(point))
	await physics_frame

func arrive(which: String) -> bool:
	var station: Dictionary = fitness.local_station(stations[which])
	if station.is_empty():
		check(false,"Missing sports fixture · "+which)
		return false
	var node: Node = station["node"]
	var point: Variant
	if station["setting"]["kind"] == "penalty":
		point = Court.world_point(Court.frame_for(station,world.exploration),Vector3(0,0,Court.STANCE))
	else:
		var bounds: Rect2 = Utility.footprint(station["item"],studio.library,studio.mode)
		var data: Array = Utility.Traffic.world(Utility.side_point(bounds,"south",.65),studio.mode)
		point = node.get_parent().to_global(Vector2(data[0],data[1])) if studio.mode == "2d" \
			else node.get_parent().to_global(Vector3(data[0],node.position.y,data[2]))
	await at_position(point)
	var prompt: String = world.exploration.interaction_prompt()
	var ok: bool = world.exploration.nearby.get("fitness") == stations[which]
	check(ok,"Walk recognizes "+which+" at its actual approach · "+prompt)
	return ok

func menu(which: String) -> bool:
	if not await arrive(which): return false
	world.exploration.interact()
	var ok: bool = fitness.menu.get("uid") == stations[which]
	check(ok,"Interact opens the selected sports booking.")
	return ok

func reserve_and_start() -> bool:
	fitness.view.primary.pressed.emit()
	check(not fitness.booking.is_empty(),"Reserve uses a shared station slot · "+fitness.notice)
	if fitness.booking.is_empty(): return false
	fitness.view.primary.pressed.emit()
	var ok: bool = not fitness.session.is_empty()
	check(ok,"Check in starts "+studio.mode+" "+fitness.label_for(fitness.local_station(fitness.menu["uid"]))+" · "+fitness.notice)
	return ok

func step(seconds: float) -> void:
	for i in ceili(seconds/.05): fitness.step(.05)

func visual() -> Variant:
	return world.player.get_node("Sprite2D").frame if studio.mode == "2d" else world.player.limbs[3].transform

func run() -> void:
	studio = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	while not studio.enhancements_ready: await process_frame
	studio.consumer_shell.dismiss_welcome()
	tools = studio.fitness_tools
	for id in Plan.definitions()["stations"]:
		check(studio.library.assets.has(id),"Reviewed sports equipment resolves · "+id)
	var fit: Dictionary = {"asset":EQUIPMENT["treadmill"],"scale":3,"position":[0,0,0]}
	check("scale" in Plan.equipment_reason(fit,studio.library,"2d"),"Oversized equipment reports the contact scale limit.")
	fit["scale"] = studio.library.assets[fit["asset"]]["data"]["default_scale"]
	fit["position"][2] = 2
	check("floor" in Plan.equipment_reason(fit,studio.library,"2d"),"An elevated machine refuses a floor-level booking.")
	fit["position"][2] = 0
	fit["tilt"] = [15,0]
	check("Level" in Plan.equipment_reason(fit,studio.library,"2d"),"Tilted equipment requires a level contact surface.")
	for mode in ["2d","3d"]:
		await gym(mode)
		await court_game(mode)
	studio.free()
	await process_frame
	print("FITNESS WORKFLOW: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func editor_preview() -> void:
	studio.interior_tools.start(site,"ground","empty")
	studio.set_walking(true)
	world.player.set_physics_process(false)
	await settle()
	clock.hour = 10
	if await menu("treadmill"):
		fitness.step(0)
		check(fitness.view.panel.is_visible_in_tree(),"The booking remains visible when Walk starts in the owned-floor editor.")
		fitness.view.primary.pressed.emit()
		check(not fitness.booking.is_empty(),"The floor preview can reserve its actual station · "+fitness.notice)
	studio.interior_tools.leave()
	check(fitness.booking.is_empty() and fitness.locks.is_empty(),"Leaving the floor editor releases its reservation.")

func gym(mode: String) -> void:
	await setup_gym(mode)
	await editor_preview()
	if not await enter(): return
	var ordinary_context: Dictionary = Props.context(world.exploration)
	var old: Dictionary = ordinary_context["data"]["objects"].filter(func(item: Dictionary) -> bool:
		return item["uid"] == stations["ordinary"])[0]
	var ordinary_node: Node = ordinary_context["instances"][old["uid"]]
	var ordinary_point: Variant = Props.anchor(ordinary_node,old,studio.library,mode,Props.profile(old),"approach")
	await at_position(ordinary_node.get_parent().to_global(ordinary_point))
	world.exploration.interaction_prompt()
	check(world.exploration.nearby.get("prop",{}).get("item",{}).get("uid") == old["uid"],
		"An unconfigured treadmill keeps its existing appliance interaction.")
	clock.hour = 18
	if not await menu("treadmill"): return
	check(fitness.view.primary.disabled and not fitness.book()["ok"],"The shared city hour closes booking.")
	clock.hour = 10
	fitness.step(0)
	var registry: RefCounted = Reservations.for_world(world)
	var key: String = Props.scope(world.exploration)+stations["treadmill"]
	var held: int = registry.acquire(key,studio)
	check(held > 0 and not fitness.book()["ok"],"Sports booking respects another system's reservation.")
	registry.release(key,held)
	fitness.view.primary.pressed.emit()
	check(not fitness.booking.is_empty() and registry.acquire(key,studio) == 0,"A held slot prevents competing use.")
	step(15.1)
	check(fitness.booking.is_empty() and registry.current(key).is_empty(),"An unclaimed booking expires and releases its lock.")
	if not await menu("treadmill"): return
	var previous_player: Node = world.exploration.player
	world.exploration.player = null
	check(not fitness.book()["ok"] and "One player" in fitness.notice,"A session requires an actual participant.")
	world.exploration.player = previous_player
	if mode == "2d":
		var animator: RefCounted = world.player.authored_animation
		world.player.authored_animation = ActorAnimation.new(world.player,{"idle":{}},1)
		check(not fitness.book()["ok"] and "No supported run" in fitness.notice,
			"An unavailable animation cannot start a treadmill workout.")
		world.player.authored_animation = animator
	world.player.set_physics_process(true)
	if not reserve_and_start(): return
	check(not world.player.is_physics_processing(),"The active workout takes control from the normal walking input.")
	var before: Variant = visual()
	await capture_motion(mode,"treadmill",1)
	step(.5)
	await capture_motion(mode,"treadmill",2)
	check(visual() != before and is_instance_valid(fitness.motion.line),"Treadmill visibly animates feet and belt.")
	var time: float = fitness.session["remaining"]
	world.exploration.photo.active = true
	step(2)
	check(fitness.session["remaining"] == time and not fitness.view.panel.visible,"Photo pauses the workout and hides its controls.")
	world.exploration.photo.active = false
	step(12)
	check(fitness.session.is_empty() and fitness.last_result.get("status") == "completed"
		and fitness.last_result.get("repetitions",0) > 0 and registry.current(key).is_empty(),
		"The workout completes once and returns the held reservation.")
	check(world.player.is_physics_processing(),"Completing the workout restores normal player physics.")
	world.player.set_physics_process(false)
	for kind in ["cycle","row"]:
		if not await menu(kind) or not reserve_and_start(): return
		var pose: Variant = world.player.interaction_visual_offset if mode == "2d" else world.player.body.global_position
		var rider: Variant = visual()
		await capture_motion(mode,kind,1)
		step(.35)
		await capture_motion(mode,kind,2)
		var now: Variant = world.player.interaction_visual_offset if mode == "2d" else world.player.body.global_position
		check(now != pose or visual() != rider,"Workout has visible equipment contact motion · "+kind)
		if kind == "cycle":
			world.exploration.interact()
			check(fitness.last_result.get("status") == "cancelled" and not is_instance_valid(fitness.motion.line),
				"Interact stops the workout and clears the attached visual.")
		else:
			world.exploration.leave_interior()
			check(fitness.last_result.get("status") == "cancelled" and registry.entries.is_empty(),
				"Leaving the interior clears the held pose and station.")
	studio.set_walking(false)
	if "--portable" in OS.get_cmdline_user_args():
		var blocked: Dictionary = Portable.new().save(world,studio.current().data,studio.library,OUTPUT+"/restricted_"+mode+".zip")
		check(not blocked["ok"] and "restricts redistributing" in blocked["message"],
			"Supplied gym artwork follows its source-package restriction.")

func setup_court(mode: String) -> void:
	await blank(mode)
	stations = {"penalty":place(GOAL[mode],Vector2.ZERO)}
	studio.changed()
	studio._command("fitness",null)
	author(stations["penalty"],20,6)
	studio.set_walking(true)
	world.player.set_physics_process(false)
	clock.hour = 22
	await settle()

func court_game(mode: String) -> void:
	await setup_court(mode)
	var document: RefCounted = studio.current()
	var treasury: Dictionary = document.data.get("economy_account",{}).duplicate(true)
	check(Plan.scheduled(Plan.station(document.object(stations["penalty"]),mode),2) \
		and not Plan.scheduled(Plan.station(document.object(stations["penalty"]),mode),12),
		"One schedule spans midnight on the shared city clock.")
	if not await menu("penalty") or not reserve_and_start(): return
	var center: Variant = fitness.court.ball.global_position
	var start_aim: float = fitness.session["aim"]
	fitness.view.right.pressed.emit()
	check(fitness.session["aim"] > start_aim,"Aim buttons adjust the planned shot.")
	fitness.aim(100)
	fitness.view.primary.pressed.emit()
	step(.3)
	check(fitness.court.ball.global_position != center and fitness.court.flying,"The supplied ball moves along a real shot.")
	step(1.4)
	check(fitness.session.get("score") == 0 and fitness.session["shots"] == 1 and fitness.court.position == Court.START,
		"An out-of-bounds shot misses and returns to its mark.")
	fitness.aim(-fitness.session["aim"])
	var frame: Dictionary = fitness.court.frame
	var point: Variant = Court.world_point(frame,Vector3(0,0,3.2))
	var actor: Node = CharacterBody2D.new() if mode == "2d" else CharacterBody3D.new()
	world.player.get_parent().add_child(actor)
	actor.global_position = point
	var citizens: Node = clock.citizens
	citizens.residents.append({"actor":actor})
	fitness.view.primary.pressed.emit()
	step(.75)
	check(fitness.session.get("score") == 0 and "Shot blocked" in fitness.notice,"A spectator in the lane blocks a real ball flight.")
	citizens.residents.pop_back()
	actor.free()
	step(.85)
	await capture_court(mode)
	for attempt in 3:
		world.exploration.interact()
		step(1.5)
	check(fitness.last_result.get("status") == "completed" and fitness.last_result.get("score") == 3
		and fitness.last_result.get("shots") == 5 and not is_instance_valid(fitness.court.ball),
		"Three valid crossings in five attempts complete the scored drill.")
	check(document.data.get("economy_account",{}) == treasury,"Preview workouts and practice leave the treasury unchanged.")
	if not await menu("penalty") or not reserve_and_start(): return
	var goal: Dictionary = document.object(stations["penalty"])
	var old_pos: Array = goal["position"].duplicate()
	goal["position"] = Utility.Traffic.world(Vector2(2,0),mode)
	studio.changed()
	fitness.step(.05)
	check(fitness.session.is_empty() and fitness.last_result.get("status") == "cancelled"
		and Reservations.for_world(world).entries.is_empty(),"Moving an active goal cancels and releases the session.")
	goal["position"] = old_pos
	studio.changed()
	if not await menu("penalty") or not reserve_and_start(): return
	document.data["objects"].erase(goal)
	studio.changed()
	fitness.step(.05)
	check(fitness.session.is_empty() and not is_instance_valid(fitness.court.ball),"Deleting the goal removes the ball and restores the player.")
	document.data["objects"].append(goal)
	studio.changed()
	if not await menu("penalty"): return
	fitness.view.primary.pressed.emit()
	studio.set_walking(false)
	var path: String = OUTPUT+"/sports_"+mode
	check(studio.write_project(path+".isocity.json",false),"Authored sports schedules save in "+mode)
	var repair: RefCounted = Repair.new(studio.library)
	var reopened: Dictionary = repair.read(path+".isocity.json")
	check(reopened["ok"] and repair.issues.is_empty() and Plan.enabled(reopened["content"]["documents"][mode]),
		"A clean reopen retains sports configuration.")
	var broken: Dictionary = document.data.duplicate(true)
	broken["fitness"]["enabled"] = "invalid"
	broken["objects"][0]["fitness"]["open_hour"] = -1
	var recovered: Dictionary = Repair.new(studio.library).world(broken,mode,"sports",0)
	check(not Plan.enabled(recovered) and Plan.station(recovered["objects"][0],mode).is_empty()
		and recovered["objects"][0]["uid"] == goal["uid"],"Repair preserves the goal and disables invalid settings.")
	if "--portable" in OS.get_cmdline_user_args():
		var package: Dictionary = Portable.new().save(world,document.data,studio.library,path+".zip")
		check(package["ok"],"Allowed court exports the required ball art · "+package.get("message",""))
	check(studio.load_project(path+".isocity.json") and fitness.history.is_empty() and fitness.booking.is_empty()
		and fitness.session.is_empty() and Plan.enabled(studio.current().data),"Reload clears bookings and scores but keeps the authored site.")

func capture_motion(mode: String, kind: String, phase: int) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	studio.consumer_shell.set_active(true,false)
	studio.consumer_shell.dismiss_welcome()
	root.size = Vector2i(1480,900)
	await settle()
	fitness.step(0)
	capture("motion_"+mode+"_"+kind+"_"+str(phase),true,1480)

func capture_authoring(mode: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	select(stations["treadmill"])
	for simple in [false,true]:
		studio.consumer_shell.set_active(simple,false)
		studio.consumer_shell.dismiss_welcome()
		for size in [Vector2i(1480,900),Vector2i(960,640)]:
			root.size = size
			studio.accessibility_settings.restore({"text_scale":1.5,"high_contrast":true,"large_targets":true} if size.x==960 else {})
			studio._command("fitness",null)
			await settle()
			tools.apply_station.grab_focus()
			await settle()
			check(visible_focus(tools.apply_station,size),"Sports authoring remains keyboard reachable · "+str([mode,simple,size]))
			capture("sports_tools_"+mode,simple,size.x)
			tools.apply_station.release_focus()
	restore_capture()

func capture_court(mode: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	for simple in [false,true]:
		studio.consumer_shell.set_active(simple,false)
		studio.consumer_shell.dismiss_welcome()
		for size in [Vector2i(1480,900),Vector2i(960,640)]:
			root.size = size
			studio.accessibility_settings.restore({"text_scale":1.5,"high_contrast":true,"large_targets":true} if size.x==960 else {})
			await settle()
			fitness.step(0)
			fitness.view.primary.grab_focus()
			await settle()
			check(visible_focus(fitness.view.primary,size) and fitness.view.scroll.get_global_rect().encloses(fitness.view.primary.get_global_rect()),
				"Kick is visible and keyboard reachable · "+str([mode,simple,size]))
			capture("penalty_"+mode,simple,size.x)
			fitness.view.primary.release_focus()
	restore_capture()
	await settle()
	fitness.step(0)

func visible_focus(control: Control, size: Vector2i) -> bool:
	return control.is_visible_in_tree() and control.has_focus() and Rect2(Vector2.ZERO,Vector2(size)).encloses(control.get_global_rect())

func capture(prefix: String, simple: bool, width: int) -> void:
	RenderingServer.force_draw(false)
	RenderingServer.force_draw(false)
	var path: String = OUTPUT+"/%s_%s_%d.png" % [prefix,"simple" if simple else "precision",width]
	check(root.get_texture().get_image().save_png(path)==OK,"Captured the native sports UI.")

func restore_capture() -> void:
	root.size = Vector2i(1480,900)
	studio.accessibility_settings.restore({})
	studio.consumer_shell.set_active(false,false)
