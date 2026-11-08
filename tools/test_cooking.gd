extends SceneTree

const Plan = preload("res://scripts/builder/cooking_plan.gd")
const Props = preload("res://scripts/builder/prop_plan.gd")
const Templates = preload("res://scripts/builder/templates.gd")
const Traffic = preload("res://scripts/builder/traffic_plan.gd")
const Utility = preload("res://scripts/builder/utility_profiles.gd")
const Doc = preload("res://scripts/builder/document.gd")
const Repair = preload("res://scripts/builder/project_repair.gd")
const Portable = preload("res://scripts/builder/portable_export.gd")
const OUTPUT = "res://output/verification/asset_expansion/N08"
const CAFE = {"2d":"2d:Coffee_Shop","3d":"3d:HanX_Shop/Shop_Cafe"}
const COUNTER = {"2d":"2d:Cafe_Counter","3d":"3d:HanX_Shop/Cafe_Counter"}
const RECIPE = "tomato_pan_bread"
const DISH = "dish/tomato_pan_bread"
const PAN = "2d:Supplemental_Kitchen_cookware_kit_cast_skillet_eea39bdc"

var studio: Control
var tools: RefCounted
var world: Node
var cook: Node
var business: Node
var cafe: String
var stations: Dictionary = {}
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: "+message)

func settle() -> void:
	for frame in 7: await process_frame
	await physics_frame

func place(asset: String, at: Vector2) -> String:
	return studio.current().add(asset,Traffic.world(at,studio.mode),str(studio.library.directions(asset)[0]),1.0)["uid"]

func author(uid: String, power: bool = false, choice: int = 0, enabled: bool = true) -> void:
	studio.selected_uid = uid
	studio.selected_uids.assign([uid])
	tools.refresh()
	tools.station_enabled.button_pressed = enabled
	tools.recipe.select(choice)
	tools.require_power.button_pressed = power
	tools.apply_station.pressed.emit()

func setup(mode: String, power: bool = false, oven: bool = false) -> void:
	studio.set_walking(false)
	studio.switch_mode(mode)
	var root_doc: RefCounted = studio.current()
	root_doc.data = Templates.make(mode,"blank")
	root_doc.data["economy"] = {"enabled":true,"starting_cash":50000}
	cafe = place(CAFE[mode],Vector2.ZERO)
	root_doc.object(cafe)["business"] = {"kind":"cafe","open_hour":0.0,"close_hour":0.0}
	studio.changed()
	world = studio.worlds[mode]
	cook = world.exploration.cooking
	cook.set_physics_process(false)
	cook.reset()
	business = studio.business_tools.managers[mode]
	business.set_physics_process(false)
	studio._command("cooking",null)
	check(not Plan.enabled(root_doc.data),"Cooking begins disabled in "+mode)
	tools.enabled.button_pressed = true
	tools.apply_city.pressed.emit()
	studio.interior_tools.start(cafe,"ground","empty")
	var doc: RefCounted = studio.current()
	doc.data["objects"] = []
	stations = {
		"prep":place("2d:Kitchen_Island",Vector2(-8,-6)),
		"cook":place("2d:Stove_Oven" if oven else "2d:Stove_Cooking",Vector2(0,-6)),
		"serve":place(COUNTER[mode],Vector2(8,-6)),
		"pantry":place("2d:Fridge_White",Vector2(-8,4))}
	studio.changed()
	studio._command("cooking",null)
	for role in stations: author(stations[role],power and role == "cook")
	check(Plan.enabled(root_doc.data) and Doc.valid(root_doc.data,mode,studio.library),"The Kitchen panel authors valid owned-floor stations in "+mode)
	studio._command("undo",null)
	check(Plan.station(doc.object(stations["pantry"])).is_empty(),"Undo removes the pantry role in "+mode)
	studio._command("redo",null)
	check(not Plan.station(doc.object(stations["pantry"])).is_empty(),"Redo restores the pantry role in "+mode)
	if not power and not oven: await capture_authoring(mode)
	studio.interior_tools.leave()
	await settle()

func enter() -> bool:
	studio.set_walking(true)
	world.player.set_physics_process(false)
	world.player.teleport_to(world.exploration.entrance(world.instances[cafe]))
	await settle()
	world.exploration.interact()
	await settle()
	check(world.exploration.interior_uid == cafe,"Normal Walk enters the café.")
	if world.exploration.interior_uid != cafe: return false
	world.player.set_physics_process(false)
	business.hour = 12.0
	return true

func arrive(role: String) -> void:
	var context: Dictionary = Props.context(world.exploration)
	var candidate: Dictionary = cook.station_list(context)[stations[role]]
	var node: Node = candidate["node"]
	var point: Vector2 = Utility.side_point(candidate["bounds"],"south",.65)
	var at: Array = Traffic.world(point,studio.mode)
	var global_point: Variant = node.get_parent().to_global(Vector2(at[0],at[1])) if studio.mode == "2d" \
		else node.get_parent().to_global(Vector3(at[0],node.position.y,at[2]))
	world.player.teleport_to(world.player.get_parent().to_local(global_point))
	await physics_frame

func interact(role: String, word: String) -> bool:
	var prompt: String = world.exploration.interaction_prompt()
	var selected: String = world.exploration.nearby.get("cooking","")
	check(selected == stations[role] and word in prompt,"Walk interaction reaches "+role+" with "+word+" · "+prompt)
	if selected != stations[role]: return false
	world.exploration.interact()
	return true

func seconds(value: float) -> void:
	for tick in ceili(value*4.0): cook.advance(.25)

func stock() -> Dictionary:
	return cook.stock_for(Props.scope(world.exploration))

func capture_authoring(mode: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	studio.selected_uid = stations["prep"]
	studio.selected_uids.assign([stations["prep"]])
	for simple in [false,true]:
		studio.consumer_shell.set_active(simple,false)
		studio.consumer_shell.dismiss_welcome()
		for size in [Vector2i(1480,900),Vector2i(960,640)]:
			root.size = size
			studio.accessibility_settings.restore({"text_scale":1.5,"high_contrast":true,"large_targets":true} if size.x==960 else {})
			studio._command("cooking",null)
			await settle()
			if mode=="2d":
				world.camera.position = Vector2(135 if simple else 0,-43 if simple else -20)
				world.camera.zoom = Vector2.ONE * ((1.4 if simple else 1.65) if size.x==960 else 2.05)
			else:
				world.distance = 24
				world.target = world.camera.global_basis.x * (6.0 if simple else 0.0)
				world.update_camera()
			tools.apply_station.grab_focus()
			await settle()
			check(tools.apply_station.has_focus() and Rect2(Vector2.ZERO,Vector2(size)).encloses(tools.apply_station.get_global_rect()),
				"Kitchen authoring stays keyboard-reachable at "+str([mode,simple,size]))
			await save_capture("kitchen_"+mode,simple,size.x)
			tools.apply_station.release_focus()
	restore_capture()

func capture_business(mode: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	for simple in [false,true]:
		studio.consumer_shell.set_active(simple,false)
		studio.consumer_shell.dismiss_welcome()
		for size in [Vector2i(1480,900),Vector2i(960,640)]:
			root.size = size
			studio.accessibility_settings.restore({"text_scale":1.5,"high_contrast":true,"large_targets":true} if size.x==960 else {})
			await settle()
			business.update_ui()
			var order: Button
			for control in business.buttons.get_children():
				if control.text.contains("Order tomato pan bread"): order = control
			check(is_instance_valid(order) and order.icon != null,"A cooked dish has a real food icon in the existing café menu.")
			if order: order.grab_focus()
			await settle()
			check(is_instance_valid(order) and order.has_focus() and Rect2(Vector2.ZERO,Vector2(size)).encloses(order.get_global_rect()),
				"The cooked dish order stays keyboard-reachable at "+str([mode,simple,size]))
			await save_capture("cafe_"+mode,simple,size.x)
			if order: order.release_focus()
	restore_capture()
	await arrive("serve")

func save_capture(prefix: String, simple: bool, width: int) -> void:
	RenderingServer.force_draw(false)
	RenderingServer.force_draw(false)
	var path: String = OUTPUT+"/%s_%s_%d.png" % [prefix,"simple" if simple else "precision",width]
	check(root.get_texture().get_image().save_png(path)==OK,"Captured native cooking presentation.")

func restore_capture() -> void:
	root.size = Vector2i(1480,900)
	studio.accessibility_settings.restore({})
	studio.consumer_shell.set_active(false,false)

func run() -> void:
	studio = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	while not studio.enhancements_ready: await process_frame
	studio.consumer_shell.dismiss_welcome()
	tools = studio.cooking_tools
	for asset in Plan.definitions()["stations"]:
		check(studio.library.assets.has(asset),"Reviewed kitchen asset resolves · "+asset)
	for mode in ["2d","3d"]:
		await normal(mode)
	await cookware()
	await interruptions()
	studio.free()
	await process_frame
	print("COOKING WORKFLOW: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func normal(mode: String) -> void:
	await setup(mode)
	if not await enter(): return
	var root_doc: RefCounted = studio.current()
	var treasury: Dictionary = root_doc.data.get("economy_account",{}).duplicate(true)
	await arrive("cook")
	interact("cook","Start at the preparation")
	check(cook.player_job().is_empty(),"Cooking cannot skip preparation in "+mode)
	await arrive("prep")
	if not interact("prep","Prepare tomato pan bread"): return
	check(cook.player_job().get("phase") == "preparing" and stock().get("flour") == 2 and stock().get("tomato") == 3,
		"Preparation reserves two flour and one tomato in "+mode+" · "+cook.notice)
	if cook.player_job().is_empty(): return
	if mode == "2d":
		var second := CharacterBody2D.new()
		second.collision_layer = 0
		second.collision_mask = 3
		world.player.get_parent().add_child(second)
		second.global_position = world.player.global_position
		var refused: Dictionary = cook.request(second,stations["prep"])
		check(not refused["ok"] and refused["reason"].contains("already in use") and stock().get("flour") == 2,
			"A second cook cannot acquire the occupied preparation station.")
		second.free()
	cook.cancel_player()
	check(stock().get("flour") == 4 and stock().get("tomato") == 4,"Cancelling active preparation refunds the exact inputs in "+mode)
	interact("prep","Prepare tomato")
	seconds(2)
	check(cook.player_job().get("phase") == "prepared","Preparation completes as a separate stage in "+mode)
	cook.cancel_player()
	check(stock().get("flour") == 4,"Cancelling while carrying unheated prep refunds it in "+mode)
	interact("prep","Prepare tomato")
	seconds(2)
	await arrive("serve")
	interact("serve","go to the stove")
	check(cook.player_job().get("phase") == "prepared" and stock().get(DISH,0) == 0,"Plating cannot skip heat in "+mode)
	await arrive("cook")
	interact("cook","Cook tomato")
	check(cook.player_job().get("phase") == "cooking","A different station starts timed heat in "+mode)
	seconds(1)
	check(not cook.effects.entries.is_empty(),"Heat uses existing appliance visual feedback in "+mode)
	cook.cancel_player()
	check(stock().get("flour") == 2 and stock().get("tomato") == 3 and stock().get(DISH,0) == 0,
		"Cancelling after heat discards ingredients and clears the visual effect in "+mode)
	await arrive("prep")
	interact("prep","Prepare tomato")
	seconds(2)
	await arrive("cook")
	interact("cook","Cook tomato")
	seconds(5)
	check(cook.player_job().get("phase") == "cooked" and stock().get(DISH,0) == 0,"Cooked food still needs plating in "+mode)
	await arrive("serve")
	interact("serve","Plate tomato")
	seconds(1)
	check(cook.player_job().is_empty() and stock().get(DISH,0) == 1 and stock().get("flour") == 0 and stock().get("tomato") == 2,
		"One complete recipe puts one identified dish on the counter in "+mode)
	business.step(0.0,false)
	await arrive("prep")
	var distant: Dictionary = business.request_player(cafe,DISH)
	check(not distant["ok"] and distant["reason"].contains("counter"),"The café requires its physical serving counter in "+mode)
	await arrive("serve")
	business.update_ui()
	check(business.dish_approach_hint.is_empty() and not business.caption.text.contains("Approach the serving counter"),
		"The counter approach hint clears when the player reaches the counter in "+mode)
	await capture_business(mode)
	var accepted: Dictionary = business.request_player(cafe,DISH)
	var compete: Dictionary = business.service.request(cafe,"another_customer",DISH,12.0)
	check(accepted["ok"] and not compete["ok"] and compete["reason"].contains("reserved"),"The café reserves one ready dish against two orders in "+mode)
	business.cancel_activity()
	check(stock().get(DISH) == 1,"Cancelling service releases the reserved plate in "+mode)
	accepted = business.request_player(cafe,DISH)
	business.step(2.0,false)
	var visit: Dictionary = business.service.result("player")
	check(accepted["ok"] and visit.get("state") == "complete" and visit.get("result_id") == RECIPE and stock().get(DISH) == 0
		and business.service.inventory["player"].get("Tomato pan bread",0) == 1 and cook.serve_visit(visit),
		"The existing café visit settles one real dish and retries leave the counter unchanged in "+mode)
	business.step(0.0,false)
	check(not business.request_player(cafe,DISH)["ok"] and business.service.history.size() == 1,
		"An empty menu cannot award a second serving in "+mode)
	check(root_doc.data.get("economy_account",{}) == treasury,"The recipe leaves the saved treasury unchanged in "+mode)
	await arrive("prep")
	interact("prep","Prepare tomato")
	check(cook.player_job().is_empty() and cook.notice.contains("Missing flour"),"Missing ingredients refuse a new job in "+mode)
	await arrive("pantry")
	interact("pantry","Restock")
	check(stock().get("flour") == 3,"The configured pantry restocks finite ingredients in "+mode)
	studio.set_walking(false)
	var path: String = OUTPUT+"/kitchen_"+mode
	check(studio.write_project(path+".isocity.json",false),"Authored kitchen saves in "+mode)
	var repair: RefCounted = Repair.new(studio.library)
	var opened: Dictionary = repair.read(path+".isocity.json")
	check(opened["ok"] and repair.issues.is_empty() and Plan.enabled(opened["content"]["documents"][mode]),
		"Clean reopening retains authored configuration in "+mode)
	var damaged: Dictionary = root_doc.data.duplicate(true)
	damaged["cooking"]["enabled"] = "invalid"
	for item in damaged["objects"]:
		if item["uid"] == cafe: item["interior"]["objects"][0]["cooking"]["recipe"] = "invalid"
	var recovered: Dictionary = Repair.new(studio.library).world(damaged,mode,"broken_kitchen",0)
	check(not Plan.enabled(recovered) and Plan.station(recovered["objects"][0]["interior"]["objects"][0]).is_empty(),
		"Repair disables malformed kitchen metadata and keeps its fixtures in "+mode)
	if "--portable" in OS.get_cmdline_user_args():
		var package: Dictionary = Portable.new().save(world,root_doc.data,studio.library,path+".zip")
		check(package["ok"],"Permitted kitchen exports future serving art in "+mode+" · "+package.get("message",""))
	check(studio.load_project(path+".isocity.json") and cook.kitchens.is_empty() and cook.jobs.is_empty()
		and Plan.enabled(studio.current().data),"Opening the saved project restores authored stations with fresh preview stock in "+mode)

func cookware() -> void:
	await setup("2d",false,true)
	if not await enter(): return
	await arrive("prep")
	interact("prep","Prepare tomato")
	check(cook.player_job().is_empty() and cook.notice.contains("reviewed pan"),"A bare stove refuses to start a batch without a utensil.")
	studio.set_walking(false)
	studio.interior_tools.start(cafe,"ground","empty")
	var pan: String = place(PAN,Vector2(2,-9))
	studio.changed()
	studio._command("cooking",null)
	author(pan)
	studio.interior_tools.leave()
	if not await enter(): return
	await arrive("prep")
	interact("prep","Prepare tomato")
	check(cook.player_job().get("phase") == "preparing","The supplied skillet enables cooking at a bare stove.")
	seconds(2)
	seconds(25)
	check(cook.player_job().is_empty() and stock().get("flour") == 4,"Abandoned unheated preparation expires and refunds once.")
	await arrive("prep")
	world.exploration.interact()
	seconds(2)
	await arrive("pantry")
	world.exploration.interact()
	world.exploration.interact()
	cook.cancel_player()
	check(stock().get("flour") == Plan.MAX_STOCK and stock().get("tomato") == Plan.MAX_STOCK,
		"Pantry refills leave space for an unheated batch's full refund.")
	await heat()
	seconds(.5)
	check(cook.player_job().get("phase")=="cooking" and not cook.effects.entries.is_empty(),
		"A static oven without animation still runs timed heat and readable feedback.")
	cook.cancel_player()
	studio.set_walking(false)
	if "--portable" in OS.get_cmdline_user_args():
		var package: Dictionary = Portable.new().save(world,studio.current().data,studio.library,OUTPUT+"/restricted.zip")
		check(not package["ok"] and package["message"].contains("restricts redistributing"),"Restricted cookware honors existing source-export policy.")

func heat() -> void:
	await arrive("prep")
	world.exploration.interact()
	seconds(2)
	await arrive("cook")
	world.exploration.interact()

func interruptions() -> void:
	await setup("3d",true)
	var doc: RefCounted = studio.current()
	var generator: String = place("3d:HanX_Construction/Generator",Vector2(-14,0))
	doc.data["utilities"] = {"power":true}
	doc.data["utility_nodes"] = [
		{"uid":"source","kind":"power","object_uid":generator,"enabled":true,"quantity":20},
		{"uid":"kitchen","kind":"power","object_uid":cafe,"enabled":true}]
	doc.data["utility_edges"] = [{"uid":"supply","kind":"power","enabled":true,
		"from":{"object_uid":generator,"socket":"output"},"to":{"object_uid":cafe,"socket":"input"}}]
	studio.changed()
	if not await enter(): return
	var power: Node = world.exploration.power
	check(power.served(cafe) >= 7 and power.graph["nodes"][cafe]["quantity"] >= 7,
		"The real grid includes the owned stove's standing load.")
	doc.data["utility_edges"][0]["enabled"] = false
	power.configure(doc.data,studio.library,true)
	await heat()
	check(cook.player_job().get("phase") == "prepared" and cook.notice.contains("electricity"),
		"An outage before heat leaves the reserved inputs refundable.")
	cook.cancel_player()
	check(stock().get("flour") == 4,"An unheated outage returns exact ingredients on cancel.")
	doc.data["utility_edges"][0]["enabled"] = true
	power.configure(doc.data,studio.library,true)
	await heat()
	check(cook.player_job().get("phase") == "cooking","Restored power enables a fresh cooking stage.")
	doc.data["utility_edges"][0]["enabled"] = false
	power.configure(doc.data,studio.library,true)
	seconds(.25)
	check(cook.player_job().is_empty() and stock().get("flour") == 2 and stock().get(DISH,0) == 0,
		"An outage after heat discards the batch and produces no dish.")
	doc.data["utility_edges"][0]["enabled"] = true
	power.configure(doc.data,studio.library,true)
	cook.reset()
	await heat()
	seconds(5)
	seconds(25)
	check(cook.player_job().is_empty() and stock().get("flour") == 2 and stock().get(DISH,0) == 0,
		"Abandoned cooked food expires without returning heated inputs.")
	cook.reset()
	await heat()
	seconds(5)
	await arrive("serve")
	world.exploration.interact()
	check(cook.player_job().get("phase") == "plating","The counter holds an active plating reservation.")
	cook.cancel_player()
	check(cook.player_job().is_empty() and stock().get("flour") == 2 and stock().get(DISH,0) == 0,
		"Cancelling active plating produces no plate or refund.")
	cook.reset()
	await arrive("prep")
	world.exploration.interact()
	var context: Dictionary = Props.context(world.exploration)
	for item in context["data"]["objects"]:
		if item["uid"] == stations["prep"]: item["cooking"]["recipe"] = "herb_pan_bread"
	seconds(.25)
	check(cook.player_job().is_empty() and stock().get("flour") == 4,
		"Changing a recipe during prep cancels the previous recipe and returns its exact inputs.")
	await heat()
	var changed_job: Dictionary = cook.player_job()
	check(changed_job.get("recipe") == "herb_pan_bread" and changed_job.get("phase") == "cooking",
		"The edited herb recipe uses its own ingredients and stage timing.")
	context = Props.context(world.exploration)
	for item in context["data"]["objects"].duplicate():
		if item["uid"] == stations["cook"]: context["data"]["objects"].erase(item)
	seconds(.25)
	check(cook.player_job().is_empty() and stock().get("flour") == 3 and stock().get("herbs") == 2 and stock().get("dish/herb_pan_bread",0) == 0,
		"Deleting the active stove releases its reservation and loses only the heated herb batch.")
	studio.set_walking(false)
