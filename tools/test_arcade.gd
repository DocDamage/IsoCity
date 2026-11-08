extends SceneTree

const Plan = preload("res://scripts/builder/arcade_plan.gd")
const Props = preload("res://scripts/builder/prop_plan.gd")
const Utility = preload("res://scripts/builder/utility_profiles.gd")
const Reservations = preload("res://scripts/builder/activity_reservations.gd")
const Templates = preload("res://scripts/builder/templates.gd")
const Doc = preload("res://scripts/builder/document.gd")
const Repair = preload("res://scripts/builder/project_repair.gd")
const Portable = preload("res://scripts/builder/portable_export.gd")
const Race = preload("res://scripts/builder/arcade_sprint.gd")
const Signals = preload("res://scripts/builder/arcade_signals.gd")
const OUTPUT = "res://output/verification/asset_expansion/N11"
const HOST = {"2d":"2d:Arcade","3d":"3d:HanX_Shop/Shop_Grocery"}
const RACER = "3d:Supplemental_Arcade/13_arcade_13_racer_blue"
const SIGNAL = "3d:Supplemental_Arcade/19_arcade_19_dance_machine"
const DEMO = "3d:Supplemental_Arcade/08_arcade_08_fighting_cabinet_2p"
const PIXEL = "2d:Arcade_Machine_Red"

var studio: Control
var tools: RefCounted
var world: Node
var arcade: Node
var building: String
var cabinets: Dictionary = {}
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

func place(asset: String, position: Vector2, direction: String = "") -> String:
	if direction.is_empty(): direction = str(studio.library.directions(asset)[0])
	return studio.current().add(asset,Utility.Traffic.world(position,studio.mode),direction,
		float(studio.library.assets[asset]["data"].get("default_scale",1)))["uid"]

func select(uid: String) -> void:
	studio.selected_uid = uid
	studio.selected_uids.assign([uid])
	tools.refresh()

func author(uid: String, game_id: String) -> void:
	select(uid)
	tools.game.select(tools.OPTIONS.find(game_id))
	tools.apply_cabinet.pressed.emit()

func setup(mode: String) -> void:
	studio.set_walking(false)
	studio.switch_mode(mode)
	studio.current().data = Templates.make(mode,"blank")
	studio.current().data["economy"] = {"enabled":true,"starting_cash":60000}
	building = place(HOST[mode],Vector2.ZERO)
	studio.current().object(building)["business"] = {"kind":"none"}
	studio.changed()
	world = studio.worlds[mode]
	arcade = world.exploration.arcade
	arcade.set_physics_process(false)
	arcade.reset()
	studio._command("arcade",null)
	check(not Plan.enabled(studio.current().data) and not tools.enabled.button_pressed,"Arcade begins disabled in "+mode)
	tools.enabled.button_pressed = true
	tools.apply_city.pressed.emit()
	check(Plan.enabled(studio.current().data),"The city arcade switch is authored.")
	studio.interior_tools.start(building,"ground","empty")
	studio.current().data["objects"] = []
	cabinets = {
		"sprint":place(RACER,Vector2(-8,-6),"0"),
		"signals":place(SIGNAL,Vector2(1,-6),"0"),
		"demo":place(DEMO,Vector2(10,-6),"0"),
		"pixel":place(PIXEL,Vector2(-9,5),"SE"),
	}
	studio.changed()
	studio._command("arcade",null)
	author(cabinets["sprint"],"auto")
	author(cabinets["signals"],"signals")
	author(cabinets["demo"],"auto")
	author(cabinets["pixel"],"signals")
	studio._command("undo",null)
	check(Plan.game(studio.current().object(cabinets["pixel"])).is_empty(),"Undo restores the decorative sprite cabinet.")
	studio._command("redo",null)
	check(Plan.game(studio.current().object(cabinets["pixel"]))=="signals","Redo restores its explicit minigame.")
	await capture_authoring(mode)
	studio.interior_tools.leave()
	await settle()
	check(Doc.valid(studio.current().data,mode,studio.library),"Owned-room cabinet settings validate in "+mode)

func enter() -> bool:
	if not studio.walking: studio.set_walking(true)
	world.player.set_physics_process(false)
	world.player.teleport_to(world.exploration.entrance(world.instances[building]))
	await settle()
	world.exploration.interact()
	await settle()
	var ok: bool = world.exploration.interior_uid == building
	check(ok,"Normal exploration enters the actual arcade room in "+studio.mode)
	if ok: world.player.set_physics_process(false)
	return ok

func current_object(uid: String) -> Dictionary:
	for item in Props.context(world.exploration)["data"]["objects"]:
		if item["uid"] == uid: return item
	return {}

func arrive(which: String, playable: bool = true) -> bool:
	var context: Dictionary = Props.context(world.exploration)
	var uid: String = cabinets[which]
	var item: Dictionary = current_object(uid)
	var node: Node = context["instances"].get(uid)
	if item.is_empty() or not is_instance_valid(node):
		check(false,"The room contains "+which)
		return false
	var candidate: Dictionary = context.duplicate()
	candidate.merge({"item":item,"node":node,"profile":Plan.operator_profile(item,studio.library) if playable else Props.profile(item)})
	var point: Variant = Props.ground_point(candidate,world.exploration,"approach")
	world.player.teleport_to(world.player.get_parent().to_local(point))
	await physics_frame
	var prompt: String = world.exploration.interaction_prompt()
	var reached: bool = world.exploration.nearby.get("arcade") == uid if playable else \
		world.exploration.nearby.get("prop",{}).get("item",{}).get("uid") == uid and "cabinet demo" in prompt
	check(reached,"Walk recognizes "+which+" · "+prompt)
	return reached

func open(which: String) -> bool:
	if not await arrive(which): return false
	world.exploration.interact()
	var ok: bool = arcade.session.get("uid") == cabinets[which] and arcade.view.overlay.visible
	check(ok,"Interact opens the configured cabinet · "+which+" · "+arcade.notice)
	return ok

func step(ticks: int) -> void:
	for tick in ticks: arcade.step(1.0/60.0)

func key(code: int, with_ctrl: bool = false) -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		event.ctrl_pressed = with_ctrl
		Input.parse_input_event(event)
		await process_frame

func camera_pose() -> Array:
	return [world.camera.transform,world.camera.zoom] if studio.mode=="2d" else [world.camera.transform,world.camera.size,world.camera.fov]

func run() -> void:
	studio = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	while not studio.enhancements_ready: await process_frame
	studio.consumer_shell.dismiss_welcome()
	tools = studio.arcade_tools
	var reviewed: int = 0
	for id in Props.definitions()["assets"]:
		if not id.begins_with("3d:Supplemental_Arcade/"): continue
		reviewed += 1
		var item: Dictionary = {"asset":id}
		check(Plan.reviewed(item) and studio.library.assets.has(id) and Plan.game(item).is_empty()
			and Props.profile(item)["label"] == "Run cabinet demo","Existing cabinet has an honest opt-in profile · "+id)
	check(reviewed==20 and Plan.recommended({"asset":DEMO})=="demo","All 20 imported cabinets retain reviewed mappings.")
	var board: Array = []
	for index in 20: board = Plan.submit(board,{"id":index+1,"score":index*10})
	board = Plan.submit(board,{"id":20,"score":9999})
	check(board.size()==10 and board[0]["score"]==190 and board.back()["score"]==100,"Leaderboard caps entries and ignores a repeated run ID.")
	var sprint: Control = Race.new()
	sprint.begin()
	for pair in Race.COURSE.slice(0,3):
		sprint.lane = pair.x
		for tick in Race.GAP: sprint.tick()
	check(sprint.finished and sprint.strikes==3 and sprint.score==0 and sprint.section==3,
		"The race has a bounded three-crash ending.")
	sprint.free()
	var signals: Control = Signals.new()
	signals.begin()
	for index in 3:
		for tick in Signals.PATTERNS[index].size()*Signals.SLOT_TICKS + Signals.REPLY_TICKS: signals.tick()
	check(signals.finished and signals.strikes==3 and signals.score==0 and signals.round_index==3,
		"The memory game has a bounded three-timeout ending.")
	signals.free()
	for mode in ["2d","3d"]: await workflow(mode)
	studio.free()
	await process_frame
	print("ARCADE WORKFLOW: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func workflow(mode: String) -> void:
	await setup(mode)
	if not await enter(): return
	if await arrive("demo",false):
		world.exploration.interact()
		check(not world.exploration.props.active.is_empty() and not arcade.active(),"The unassigned cabinet runs its existing timed demo.")
		world.exploration.props.reset(false)
	if not await arrive("sprint"): return
	var registry: RefCounted = Reservations.for_world(world)
	var lock_key: String = Props.scope(world.exploration)+cabinets["sprint"]
	var occupied: int = registry.acquire(lock_key,studio)
	world.exploration.interact()
	check(not arcade.active() and occupied>0 and "reserved" in arcade.notice,"An existing visitor reservation blocks the same cabinet.")
	registry.release(lock_key,occupied)
	world.player.set_physics_process(true)
	var start: Variant = world.player.global_position
	world.exploration.interact()
	check(arcade.active() and not world.player.is_physics_processing() and arcade.locks.size()==2,
		"The playable cabinet holds the actor and both shared scope locks.")
	if not arcade.active(): return
	var frozen: Array = camera_pose()
	var treasury: Dictionary = studio.current().data.get("economy_account",{}).duplicate(true)
	var original_bindings: Dictionary = studio.control_settings.bindings.duplicate(true)
	for spec in [["move_left",KEY_J],["move_right",KEY_L],["interact",KEY_O],["cancel",KEY_K]]:
		check(studio.control_settings.assign(spec[0],0,spec[1]).is_empty(),"Existing control preferences remap "+spec[0])
	arcade.view.refresh()
	check("J" in arcade.view.help.text and "K" in arcade.view.help.text,"The overlay advertises current directional and exit keys.")
	await key(KEY_O)
	check(arcade.session.get("phase")=="playing","The remapped interact key starts Circuit Sprint.")
	await key(KEY_A)
	check(arcade.game.lane==1,"The replaced movement key has no game action.")
	await key(KEY_J)
	check(arcade.game.lane==0,"The remapped left key steers the race car.")
	await key(KEY_L)
	await key(KEY_L)
	check(arcade.game.lane==2,"The remapped right key reaches the first gate.")
	await key(KEY_P)
	await key(KEY_DELETE)
	await key(KEY_TAB)
	check(studio.walking and not world.exploration.photo.active and camera_pose()==frozen \
		and world.player.global_position==start and studio.current().object(building).has("interior"),
		"Other hotkeys, focus navigation and held movement cannot edit or move the city.")
	step(Race.GAP)
	check(arcade.game.score==200 and arcade.game.section==1,"Crossing the first gate awards its exact score.")
	root.focus_exited.emit()
	var ticks: int = arcade.game.ticks
	step(120)
	await key(KEY_L)
	check(arcade.game.ticks==ticks and arcade.session["phase"]=="paused" and arcade.view.primary.disabled,
		"Losing application focus freezes game ticks and rejects input.")
	root.focus_entered.emit()
	step(120)
	check(arcade.game.ticks==ticks and arcade.view.primary.text=="Resume","Regaining focus leaves an explicit resume step.")
	await key(KEY_O)
	check(arcade.session["phase"]=="playing","Resume continues the same run.")
	await capture_play(mode,"race")
	for pair in Race.COURSE.slice(1):
		var difference: int = pair.y-arcade.game.lane
		for change in absi(difference):
			arcade.view.directions["move_right" if difference > 0 else "move_left"].pressed.emit()
		step(Race.GAP)
	check(arcade.session.get("phase")=="result" and arcade.last_result.get("score")==3200
		and arcade.boards["sprint"].size()==1,"The input-driven racer finishes with exactly 3,200 points.")
	step(90)
	check(arcade.boards["sprint"].size()==1,"A result screen cannot resubmit its run.")
	await key(KEY_K)
	check(not arcade.active() and studio.walking and world.player.is_physics_processing()
		and registry.current(lock_key).is_empty(),"Remapped Cancel exits only the cabinet and restores walking.")
	world.player.set_physics_process(false)
	if not await open("signals"): return
	arcade.view.primary.pressed.emit()
	check(arcade.game.stage=="watch" and arcade.game.cue_text()=="Signal · Left","Signal Sequence presents a real directional cue.")
	arcade.view.directions["move_right"].pressed.emit()
	check(arcade.game.score==0 and arcade.game.cursor==0,"Keys during the watch phase do not score.")
	await capture_play(mode,"signal")
	var expected: int = 0
	for index in Signals.PATTERNS.size():
		var pattern: Array = Signals.PATTERNS[index]
		step(Signals.SLOT_TICKS*pattern.size())
		if index==1:
			arcade.view.directions[Signals.ACTIONS[(pattern[0]+1)%4]].pressed.emit()
		else:
			for direction in pattern:
				if index==0 and direction==0: await key(KEY_J)
				else: arcade.view.directions[Signals.ACTIONS[direction]].pressed.emit()
			expected += pattern.size()*100+150
		if index==0:
			check(arcade.game.score==350,"The exact first pattern scores two cues and one bonus.")
		if index==1:
			check(arcade.game.strikes==1 and arcade.game.score==350,"A wrong signal counts as one mistake with no bonus.")
		step(1)
	check(arcade.session.get("phase")=="result" and arcade.last_result.get("score")==expected
		and arcade.boards["signals"].size()==1,"Signal Sequence submits its exact score to a separate leaderboard.")
	await key(KEY_ESCAPE)
	check(not arcade.active() and studio.walking,"Escape closes the focused overlay without returning to Build.")
	check(studio.current().data.get("economy_account",{})==treasury,"Arcade scoring leaves the saved city treasury unchanged.")
	studio.control_settings.restore(original_bindings)
	if await open("pixel"):
		world.player.set_physics_process(false)
		arcade.view.primary.pressed.emit()
		var camera: Array = camera_pose()
		check(world.exploration.photo.start() and not arcade.active() and not arcade.view.overlay.visible
			and arcade.locks.is_empty(),"Entering Photo closes the cabinet before taking camera ownership.")
		world.exploration.photo.stop()
		check(camera_pose()==camera and arcade.boards["signals"].size()==1,"Returning from Photo restores the camera and keeps only completed scores.")
	if not await open("sprint"): return
	arcade.view.primary.pressed.emit()
	var room: Dictionary = studio.current().object(building)["interior"]
	var changed: Dictionary
	for item in room["objects"]:
		if item["uid"] == cabinets["sprint"]: changed = item
	room["objects"].erase(changed)
	studio.changed()
	step(1)
	check(not arcade.active() and not arcade.view.overlay.visible and arcade.locks.is_empty()
		and arcade.boards["sprint"].size()==1,"Deleting an active cabinet releases control without submitting a score.")
	check(world.exploration.interior==null,"An edited room returns the visitor to its real exterior.")
	studio.current().object(building)["interior"]["objects"].append(changed)
	studio.changed()
	await settle()
	if not await enter() or not await open("sprint"): return
	arcade.view.primary.pressed.emit()
	step(20)
	var path: String = OUTPUT+"/arcade_"+mode
	check(studio.write_project(path+".isocity.json",false),"Saving an active cabinet serializes only authored settings.")
	var repair: RefCounted = Repair.new(studio.library)
	var reopened: Dictionary = repair.read(path+".isocity.json")
	check(reopened["ok"] and repair.issues.is_empty() and Plan.enabled(reopened["content"]["documents"][mode]),
		"Saved arcade authoring loads without repair.")
	var broken: Dictionary = studio.current().data.duplicate(true)
	broken["arcade"]["enabled"] = "wrong"
	broken["objects"][0]["interior"]["objects"][0]["arcade"]["game"] = "missing"
	var recovered: Dictionary = Repair.new(studio.library).world(broken,mode,"broken",0)
	check(not Plan.enabled(recovered) and Plan.game(recovered["objects"][0]["interior"]["objects"][0]).is_empty(),
		"Repair disables invalid arcade configuration and leaves the cabinet placed.")
	if "--portable" in OS.get_cmdline_user_args():
		var result: Dictionary = Portable.new().save(world,studio.current().data,studio.library,path+".zip")
		check(result["ok"],"The active layout exports both game scenes and its allowed cabinets · "+result.get("message",""))
	check(studio.load_project(path+".isocity.json") and not arcade.active() and arcade.boards.is_empty()
		and arcade.locks.is_empty() and Plan.enabled(studio.current().data),"Reload releases the cabinet and clears transient scores.")

func capture_authoring(mode: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	select(cabinets["sprint"])
	for simple in [false,true]:
		studio.consumer_shell.set_active(simple,false)
		studio.consumer_shell.dismiss_welcome()
		for size in [Vector2i(1480,900),Vector2i(960,640)]:
			root.size = size
			studio.accessibility_settings.restore({"text_scale":1.5,"high_contrast":true,"large_targets":true} if size.x==960 else {})
			studio._command("arcade",null)
			await settle()
			tools.apply_cabinet.grab_focus()
			await settle()
			check(visible_focus(tools.apply_cabinet,size),"Cabinet authoring remains keyboard reachable · "+str([mode,simple,size]))
			capture("arcade_tools_"+mode,simple,size.x)
			tools.apply_cabinet.release_focus()
	restore_capture()

func capture_play(mode: String, variant: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	for simple in [false,true]:
		studio.consumer_shell.set_active(simple,false)
		studio.consumer_shell.dismiss_welcome()
		for size in [Vector2i(1480,900),Vector2i(960,640)]:
			root.size = size
			studio.accessibility_settings.restore({"text_scale":1.5,"high_contrast":true,"large_targets":true} if size.x==960 else {})
			await settle()
			arcade.view.refresh()
			var action: Button = arcade.view.directions["move_left"]
			action.grab_focus()
			await settle()
			check(visible_focus(action,size) and arcade.view.scroll.get_global_rect().encloses(action.get_global_rect()),
				"Game controls remain keyboard reachable · "+str([mode,simple,size]))
			capture(variant+"_"+mode,simple,size.x)
	restore_capture()
	await settle()

func visible_focus(control: Control, size: Vector2i) -> bool:
	return control.is_visible_in_tree() and control.has_focus() and Rect2(Vector2.ZERO,Vector2(size)).encloses(control.get_global_rect())

func capture(prefix: String, simple: bool, width: int) -> void:
	RenderingServer.force_draw(false)
	RenderingServer.force_draw(false)
	var path: String = OUTPUT+"/%s_%s_%d.png" % [prefix,"simple" if simple else "precision",width]
	check(root.get_texture().get_image().save_png(path)==OK,"Captured the native arcade interface.")

func restore_capture() -> void:
	root.size = Vector2i(1480,900)
	studio.accessibility_settings.restore({})
	studio.consumer_shell.set_active(false,false)
