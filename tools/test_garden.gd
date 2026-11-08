extends SceneTree

const Plan = preload("res://scripts/builder/garden_plan.gd")
const Templates = preload("res://scripts/builder/templates.gd")
const Doc = preload("res://scripts/builder/document.gd")
const Repair = preload("res://scripts/builder/project_repair.gd")
const Portable = preload("res://scripts/builder/portable_export.gd")
const BED = {"2d":"2d:Planter_Box", "3d":"3d:HanX_City/Planter_Box"}
const SHARE = {"2d":"2d:Produce_Stand", "3d":"3d:HanX_Shop/Stall_Vegetable"}
const RAISED = "2d:Supplemental_Garden_greenhouse_kit_raised_bed_39ed9dc1"
const GREENHOUSE = "2d:Supplemental_Garden_greenhouse_kit_greenhouse_814e7d66"
const SOIL = "2d:Supplemental_Garden_greenhouse_kit_soil_bag_a0a327e9"
const COMPOST = "2d:Supplemental_Garden_greenhouse_kit_compost_bin_1bac2ef7"
const SEEDS = "2d:Supplemental_Garden_greenhouse_kit_seed_trays_f52de2d2"
const CAN = "2d:Supplemental_Garden_greenhouse_kit_watering_can_701d8b78"
const WELL = "2d:Added_Well_Well_Wall_03fb84ee"
const OUTPUT = "res://output/verification/asset_expansion/N06"

var studio: Control
var tools: RefCounted
var runtime: Node
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + message)

func settle() -> void:
	for frame in 6: await process_frame
	await physics_frame

func placed(id: String, at: Vector2) -> String:
	return studio.current().add(id, Plan.Traffic.world(at, studio.mode), str(studio.library.directions(id)[0]), 1.0)["uid"]

func author(uid: String, crop: int = 0, irrigate: bool = false) -> void:
	studio.selected_uid = uid
	studio.selected_uids.assign([uid])
	tools.refresh()
	tools.site_enabled.button_pressed = true
	tools.crop.select(crop)
	tools.irrigation.button_pressed = irrigate
	tools.site_button.pressed.emit()

func begin_walk() -> void:
	studio.set_walking(true)
	studio.worlds[studio.mode].player.set_physics_process(false)
	await settle()

func arrive(uid: String) -> void:
	var world: Node = studio.worlds[studio.mode]
	var site: Dictionary = runtime.sites[uid]
	var node: Node = world.instances[uid]
	var point: Vector2 = Plan.Utility.side_point(site["rect"],"south",.6)
	world.player.teleport_to(runtime.world_point(node,point,site["item"]))
	await physics_frame

func use(uid: String, word: String) -> bool:
	var exploration: Node = studio.worlds[studio.mode].exploration
	var text: String = exploration.interaction_prompt()
	if exploration.nearby.get("garden", "") != uid or not word in text:
		check(false, "Expected %s at %s, found %s" % [word,uid,text])
		return false
	exploration.interact()
	return true

func seconds(value: int) -> void:
	for tick in value * 4: runtime.advance(.25)

func capture(uid: String, prefix: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	studio.set_walking(false)
	studio.selected_uid = uid
	studio.selected_uids.assign([uid])
	runtime.show_status = true
	for simple in [false, true]:
		studio.consumer_shell.set_active(simple,false)
		studio.consumer_shell.dismiss_welcome()
		for size in [Vector2i(1480,900), Vector2i(960,640)]:
			root.size = size
			studio.accessibility_settings.restore({"text_scale":1.5,"high_contrast":true,"large_targets":true} if size.x == 960 else {})
			studio._command("garden",null)
			await settle()
			var world: Node = studio.worlds[studio.mode]
			if studio.mode == "2d":
				world.camera.position = Vector2(165 if simple else 40, 18)
				world.camera.zoom = Vector2.ONE * (1.85 if size.x == 1480 else 1.3)
			else:
				world.distance = 13
				world.target = world.camera.global_basis.x * (3.1 if simple else 0.0)
				world.update_camera()
			runtime.refresh_views()
			tools.site_button.grab_focus()
			await settle()
			check(tools.site_button.has_focus() and Rect2(Vector2.ZERO,Vector2(size)).encloses(tools.site_button.get_global_rect()),
				"Garden site controls remain reachable at " + str([prefix,simple,size]))
			RenderingServer.force_draw(false)
			RenderingServer.force_draw(false)
			check(root.get_texture().get_image().save_png(OUTPUT+"/%s_%s_%d.png" % [prefix,"simple" if simple else "precision",size.x]) == OK,
				"Captured the actual garden artwork and controls.")
			tools.site_button.release_focus()
	root.size = Vector2i(1480,900)
	studio.accessibility_settings.restore({})
	studio.consumer_shell.set_active(false,false)
	runtime.show_status = false
	await begin_walk()
	await arrive(uid)

func ledger() -> void:
	var account: Dictionary = Plan.fresh_account(true)
	account["stock"]["produce/tomato"] = 14
	var before: Dictionary = account.duplicate(true)
	var rejected: Dictionary = Plan.exchange(account, "overflow", {"produce/lettuce":3}, 6, {})
	check(not rejected["ok"] and account == before, "Full storage rejects the entire output and reward.")
	var first: Dictionary = Plan.exchange(account, "seed", {"seed/lettuce":1}, -2, {"kind":"seed"})
	var again: Dictionary = Plan.exchange(first["account"], "seed", {"seed/lettuce":1}, -2, {"kind":"seed"})
	check(first["account"]["cash"] == 38 and again["replayed"] and again["account"] == first["account"],
		"A replay returns the existing seed receipt and charges once.")
	var dry: Dictionary = Plan.exchange(account, "too_many", {"water":-12}, -2, {})
	check(not dry["ok"] and account == before, "Missing supplies cannot debit the preview wallet.")

func run() -> void:
	ledger()
	studio = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	while not studio.enhancements_ready: await process_frame
	studio.consumer_shell.dismiss_welcome()
	tools = studio.garden_tools
	for asset in Plan.definitions()["sites"]:
		check(studio.library.assets.has(asset), "Reviewed garden asset resolves: " + asset)
	for entry in Plan.crops().values():
		check(studio.library.assets.has(entry["art"]), "Reviewed mature crop art resolves: " + entry["name"])
	for mode in ["2d", "3d"]:
		await outdoor(mode)
	await supplied_kit()
	studio.free()
	await process_frame
	print("GARDEN WORKFLOW: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func outdoor(mode: String) -> void:
	studio.switch_mode(mode)
	var doc: RefCounted = studio.current()
	doc.data = Templates.make(mode,"blank")
	doc.data["economy"] = {"enabled":true,"starting_cash":50000}
	var bed: String = placed(BED[mode], Vector2.ZERO)
	var share: String = placed(SHARE[mode], Vector2(12,5))
	var decorative: String = placed(BED[mode], Vector2(16,-7))
	studio.changed()
	runtime = studio.worlds[mode].exploration.garden
	runtime.set_process(false)
	runtime.reset()
	studio._command("garden",null)
	check(not Plan.settings(doc.data) and runtime.sites.is_empty(), "Gardening starts disabled in " + mode)
	tools.enabled.button_pressed = true
	tools.settings_button.pressed.emit()
	author(share)
	author(bed)
	check(runtime.sites.has(bed) and not runtime.sites.has(decorative) and Doc.valid(doc.data,mode,studio.library),
		"Only the selected and explicitly enabled bed grows in " + mode)
	if not runtime.sites.has(bed): return
	var budget: Dictionary = doc.data.get("economy_account", {}).duplicate(true)
	await begin_walk()
	await arrive(bed)
	if not use(bed,"Plant lettuce"): return
	check(runtime.crops.has(bed) and runtime.account["stock"]["seed/lettuce"] == 1 and runtime.account["stock"]["soil"] == 3,
		"Planting consumes one seed and one soil unit in " + mode)
	seconds(2)
	check(runtime.crops[bed]["growth"] == 0, "Dry soil does not grow in " + mode)
	use(bed,"Water lettuce")
	runtime.advance(600)
	check(runtime.crops[bed]["growth"] == 0, "A long frame cannot fast-forward the garden in " + mode)
	seconds(7)
	check(runtime.crops[bed]["growth"] == 6 and runtime.crops[bed]["moisture"] == 0 and not runtime.is_ripe(runtime.crops[bed]),
		"Manual water supports six wet seconds then growth stalls in " + mode)
	var attempt: String = runtime.crops[bed]["token"]
	check(not runtime.harvest(bed,attempt).get("ok",false), "Incomplete crops never pay a harvest in " + mode)
	use(bed,"Water lettuce")
	runtime.paused = true
	seconds(4)
	check(runtime.crops[bed]["growth"] == 6, "Preview pause freezes elapsed growth in " + mode)
	runtime.paused = false
	await arrive(share)
	seconds(2)
	check(runtime.is_ripe(runtime.crops[bed]) and not runtime.harvest(bed,attempt).get("ok",false),
		"Growth continues away from the bed while distant harvest is refused in " + mode)
	await arrive(bed)
	if mode == "3d": await capture(bed,"model_garden")
	runtime.account["stock"]["produce/tomato"] = 14
	use(bed,"Harvest lettuce")
	check(runtime.crops.has(bed) and runtime.account["cash"] == 40 and runtime.notice.contains("basket full"),
		"Overflow leaves the ripe crop and wallet intact in " + mode)
	await arrive(share)
	use(share,"Share harvested produce")
	await arrive(bed)
	use(bed,"Harvest lettuce")
	var receipt: Dictionary = runtime.harvest(bed,attempt)
	check(receipt.get("credits") == 6 and runtime.account["cash"] == 46 and runtime.account["stock"]["produce/lettuce"] == 3
		and not runtime.crops.has(bed) and doc.data.get("economy_account",{}) == budget,
		"One harvest and its retry yield three units and six preview credits while treasury stays exact in " + mode)
	use(bed,"Plant lettuce")
	studio.set_walking(false)
	var before: Dictionary = runtime.crops.get(bed,{}).duplicate(true)
	seconds(3)
	check(not before.is_empty() and runtime.crops.get(bed) == before, "Returning to Build pauses the crop in " + mode)
	studio._command("undo",null)
	check(not runtime.crops.has(bed) and not runtime.sites.has(bed) and runtime.account["cash"] == 46,
		"Undo removes the authored bed role and its preview crop without a second reward in " + mode)
	studio._command("redo",null)
	check(runtime.sites.has(bed) and not runtime.crops.has(bed), "Redo restores configuration with an empty bed in " + mode)
	var path: String = OUTPUT + "/garden_" + mode
	check(studio.write_project(path + ".isocity.json",false), "Normal save writes authored settings in " + mode)
	var repair: RefCounted = Repair.new(studio.library)
	var saved: Dictionary = repair.read(path + ".isocity.json")
	check(saved["ok"] and repair.issues.is_empty() and Plan.settings(saved["content"]["documents"][mode])
		and not saved["content"]["documents"][mode].has("garden_account"), "Reopening retains settings and excludes preview inventory in " + mode)
	var damaged: Dictionary = doc.data.duplicate(true)
	damaged["garden"]["enabled"] = "invalid"
	for item in damaged["objects"]:
		if item["uid"] == bed: item["garden"]["crop"] = "missing"
	var repaired: Dictionary = Repair.new(studio.library).world(damaged,mode,"damaged_garden",0)
	check(not Plan.settings(repaired) and not Plan.site_config(repaired["objects"][0])["enabled"],
		"Repair disables damaged metadata and keeps objects in " + mode)
	if "--portable" in OS.get_cmdline_user_args():
		var result: Dictionary = Portable.new().save(studio.worlds[mode],doc.data,studio.library,path + ".zip")
		check(result["ok"],"Allowed garden exports include their future runtime dependencies in " + mode + " " + result.get("message",""))
	check(studio.load_project(path + ".isocity.json"), "The normal editor reopens the saved garden in " + mode)
	check(runtime.crops.is_empty() and runtime.account["cash"] == 40 and runtime.account["stock"].get("produce/lettuce",0) == 0,
		"Reopening resets the preview account together with all receipts in " + mode)

func supplied_kit() -> void:
	studio.switch_mode("2d")
	var doc: RefCounted = studio.current()
	doc.data = Templates.make("2d","blank")
	doc.data["garden"] = {"enabled":true}
	doc.data["economy"] = {"enabled":true,"starting_cash":50000}
	var raised: String = placed(RAISED,Vector2.ZERO)
	var greenhouse: String = placed(GREENHOUSE,Vector2(20,0))
	var overlap: String = placed(RAISED,Vector2.ZERO)
	var soil: String = placed(SOIL,Vector2(4,7))
	var compost: String = placed(COMPOST,Vector2(8,7))
	var seeds: String = placed(SEEDS,Vector2(12,7))
	var water: String = placed(CAN,Vector2(16,7))
	var well: String = placed(WELL,Vector2(-12,0))
	studio.changed()
	runtime = studio.worlds["2d"].exploration.garden
	runtime.set_process(false)
	runtime.reset()
	studio._command("garden",null)
	author(raised,0,true)
	author(overlap)
	check(not runtime.sites.has(overlap) and tools.status.text.contains("overlap"), "Overlapping enabled beds are rejected by authoring.")
	for uid in [greenhouse,soil,compost,seeds,water]: author(uid)
	doc.data["utilities"] = {"water":true}
	doc.data["utility_nodes"] = [
		{"uid":"well_port","kind":"water","object_uid":well,"enabled":true},
		{"uid":"garden_port","kind":"water","object_uid":raised,"enabled":true}]
	doc.data["utility_edges"] = [{"uid":"garden_water","kind":"water","enabled":true,
		"from":{"object_uid":well,"socket":"outlet"},"to":{"object_uid":raised,"socket":"inlet"}}]
	studio.changed()
	await begin_walk()
	await arrive(seeds)
	use(seeds,"Restock lettuce")
	await arrive(soil)
	use(soil,"Collect potting soil")
	await arrive(compost)
	use(compost,"Collect compost")
	await arrive(water)
	use(water,"Fill watering can")
	check(runtime.account["cash"] == 38 and runtime.account["stock"]["seed/lettuce"] == 3
		and runtime.account["stock"]["soil"] == 8 and runtime.account["stock"]["compost"] == 1 and runtime.account["stock"]["water"] == 12,
		"Supplied kit stations stock the preview bag and charge a seed purchase once.")
	await arrive(raised)
	if not use(raised,"Plant lettuce"): return
	var network: Node = runtime.water_network
	check(network.graph["enabled"] and network.served(raised) == 2,"The actual Water graph serves the linked bed two units.")
	network.elapsed = 1.95
	network.step(.12)
	seconds(1)
	check(runtime.crops[raised]["growth"] == 1 and runtime.account["stock"]["water"] == 12,
		"Delivered water advances crops without draining the manual watering can.")
	use(raised,"Water lettuce")
	use(raised,"Work compost")
	check(runtime.crops[raised]["composted"] and runtime.account["stock"]["compost"] == 0,"Compost is a one-use input for this crop.")
	doc.data["weather"] = {"enabled":true,"season":"winter"}
	studio.changed()
	await settle()
	seconds(2)
	check(runtime.crops[raised]["growth"] == 1 and runtime.status(raised).contains("dormant"),
		"Outdoor crops go dormant in the actual winter weather state.")
	await arrive(greenhouse)
	use(greenhouse,"Plant lettuce")
	use(greenhouse,"Water lettuce")
	seconds(2)
	check(runtime.crops.get(greenhouse,{}).get("growth") == 2 and runtime.crops[raised]["growth"] == 1,
		"The greenhouse continues to grow during winter.")
	doc.data["weather"]["season"] = "summer"
	studio.changed()
	await settle()
	await arrive(raised)
	for tick in 8:
		if runtime.is_ripe(runtime.crops[raised]): break
		if runtime.crops[raised]["moisture"] <= 2: use(raised,"Water lettuce")
		seconds(1)
	check(runtime.is_ripe(runtime.crops[raised]) and runtime.artwork.has(raised) and runtime.status(raised).contains("ready"),
		"The supplied mature crop art appears only when the resumed crop is ripe.")
	await capture(raised,"pixel_garden")
	var stopped: String = runtime.crops[raised]["token"]
	doc.object(raised)["position"][0] += 20.0
	studio.changed()
	check(not runtime.crops.has(raised) and not runtime.harvest(raised,stopped).get("ok",false),
		"Moving an active bed invalidates its crop token and reward.")
	doc.data["objects"].erase(doc.object(greenhouse))
	studio.changed()
	check(not runtime.crops.has(greenhouse) and runtime.account["cash"] == 38,
		"Deleting a growing greenhouse pays nothing.")
	studio.set_walking(false)
	check(Plan.required_assets(doc.data).has(Plan.crops()["lettuce"]["art"]), "Shared layouts declare future crop artwork.")
	if "--portable" in OS.get_cmdline_user_args():
		var denied: Dictionary = Portable.new().save(studio.worlds["2d"],doc.data,studio.library,OUTPUT+"/restricted.zip")
		check(not denied["ok"] and denied["message"].contains("restricts redistributing"), "Restricted kit source remains excluded from ZIP exports.")
