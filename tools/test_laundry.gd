extends SceneTree

const Plan = preload("res://scripts/builder/laundry_plan.gd")
const Props = preload("res://scripts/builder/prop_plan.gd")
const Utility = preload("res://scripts/builder/utility_profiles.gd")
const Reservations = preload("res://scripts/builder/activity_reservations.gd")
const Templates = preload("res://scripts/builder/templates.gd")
const Doc = preload("res://scripts/builder/document.gd")
const Repair = preload("res://scripts/builder/project_repair.gd")
const Portable = preload("res://scripts/builder/portable_export.gd")
const OUTPUT = "res://output/verification/asset_expansion/N09"
const HOST = {"2d":"2d:Supermarket", "3d":"3d:HanX_Shop/Shop_Grocery"}
const COUNTER = {"2d":"2d:Checkout_Counter", "3d":"3d:HanX_Shop/Checkout_Counter"}
const SUPPLY = {"2d":"2d:Binder_Shelf", "3d":"3d:HanX_Shop/Shelf_Wall"}
const WASH = "2d:Washing_Machine"
const DRY = "2d:Clothes_Dryer"
const STACK = "2d:Supplemental_Laundromat_kit_washer_dryer_stack_96577eed"

var studio: Control
var tools: RefCounted
var world: Node
var laundry: Node
var host_uid: String
var stations: Dictionary = {}
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
	for frame in 7: await process_frame
	await physics_frame

func place(asset: String, at: Vector2) -> String:
	return studio.current().add(asset, Utility.Traffic.world(at, studio.mode),
		str(studio.library.directions(asset)[0]), 1.0)["uid"]

func author(uid: String, capacity: int = 4, power: bool = false, water: bool = false) -> void:
	studio.selected_uid = uid
	studio.selected_uids.assign([uid])
	tools.refresh()
	tools.station_enabled.button_pressed = true
	tools.capacity.value = capacity
	tools.require_power.button_pressed = power
	tools.require_water.button_pressed = water
	tools.apply_station.pressed.emit()

func setup(mode: String, utilities: bool = false, stack: bool = false) -> void:
	studio.set_walking(false)
	studio.switch_mode(mode)
	var doc: RefCounted = studio.current()
	doc.data = Templates.make(mode, "blank")
	doc.data["economy"] = {"enabled": true, "starting_cash": 50000}
	host_uid = place(HOST[mode], Vector2.ZERO)
	doc.object(host_uid)["business"] = {"kind": "none"}
	studio.changed()
	world = studio.worlds[mode]
	laundry = world.exploration.laundry
	laundry.set_physics_process(false)
	laundry.reset()
	studio._command("laundry", null)
	check(not Plan.enabled(doc.data) and not tools.enabled.button_pressed, "Laundry begins disabled in " + mode)
	tools.enabled.button_pressed = true
	tools.apply_city.pressed.emit()
	studio.interior_tools.start(host_uid, "ground", "empty")
	var room: RefCounted = studio.current()
	room.data["objects"] = []
	stations = {
		"counter": place(COUNTER[mode], Vector2(-8,-5)),
		"wash": place(STACK if stack else WASH, Vector2(0,-7)),
		"fold": place("2d:Supplemental_Laundromat_kit_folding_table_3b3f1c1f" if stack else "2d:Clothes_Display_Table", Vector2(8,-6)),
		"basket": place("2d:Supplemental_Laundromat_kit_laundry_basket_049231c7" if stack else "2d:Laundry_Basket", Vector2(7,3)),
		"supply": place("2d:Supplemental_Laundromat_kit_detergent_bottle_c7fc54c8" if stack else SUPPLY[mode], Vector2(-8,4)),
	}
	if not stack: stations["dry"] = place(DRY, Vector2(4,-7))
	stations["ordinary"] = place(WASH, Vector2(16,-12))
	studio.changed()
	studio._command("laundry", null)
	for role in stations:
		if role == "ordinary": continue
		author(stations[role], 4, utilities and role in ["wash","dry"], utilities and role == "wash")
	check(Plan.enabled(doc.data) and Doc.valid(doc.data, mode, studio.library), "Laundry controls author valid owned-room settings in " + mode)
	studio._command("undo", null)
	check(Plan.station(room.object(stations["supply" if stack else "dry"])).is_empty(), "Undo restores the previous station configuration.")
	studio._command("redo", null)
	check(not Plan.station(room.object(stations["supply" if stack else "dry"])).is_empty(), "Redo restores the laundry station.")
	if not utilities and not stack: await capture_authoring(mode)
	studio.interior_tools.leave()
	await settle()

func enter() -> bool:
	if not studio.walking: studio.set_walking(true)
	world.player.set_physics_process(false)
	world.player.teleport_to(world.exploration.entrance(world.instances[host_uid]))
	await settle()
	world.exploration.interact()
	await settle()
	check(world.exploration.interior_uid == host_uid, "The normal Walk entrance leads to the laundry room.")
	if world.exploration.interior_uid != host_uid: return false
	world.player.set_physics_process(false)
	return true

func arrive(role: String) -> void:
	var context: Dictionary = Props.context(world.exploration)
	var uid: String = stations[role]
	for item in context["data"]["objects"]:
		if item["uid"] != uid: continue
		var node: Node = context["instances"][uid]
		var bounds: Rect2 = Utility.footprint(item, studio.library, studio.mode)
		var point: Array = Utility.Traffic.world(Utility.side_point(bounds, "south", .65), studio.mode)
		var global_point: Variant = node.get_parent().to_global(Vector2(point[0],point[1])) if studio.mode == "2d" \
			else node.get_parent().to_global(Vector3(point[0],node.position.y,point[2]))
		world.player.teleport_to(world.player.get_parent().to_local(global_point))
		break
	await physics_frame

func use(role: String, label_text: String) -> bool:
	var prompt: String = world.exploration.interaction_prompt()
	var uid: String = world.exploration.nearby.get("laundry", "")
	check(uid == stations[role] and label_text in prompt, "Walk reaches " + role + " · " + prompt)
	if uid != stations[role]: return false
	world.exploration.interact()
	return true

func counter() -> Dictionary:
	await arrive("counter")
	if laundry.counter.is_empty() and not use("counter", "Laundry orders"): return {}
	laundry.advance(0)
	return laundry.counter_site()

func advance(seconds: float) -> void:
	for tick in ceili(seconds*4): laundry.advance(.25)

func object(role: String) -> Dictionary:
	return Props.context(world.exploration)["data"]["objects"].filter(func(item: Dictionary) -> bool:
		return item["uid"] == stations[role])[0]

func root_room() -> Dictionary:
	return studio.interior_tools.root_document(studio.mode).object(host_uid)["interior"]

func order(site: Dictionary, customer: String) -> Dictionary:
	for record in site.get("orders", {}).values():
		if record["customer"] == customer: return record
	return {}

func receive_with_button(customer: String) -> Dictionary:
	laundry.view.rows[customer]["primary"].pressed.emit()
	var record: Dictionary = order(laundry.counter_site(), customer)
	check(not record.is_empty(), "Counter button receives the correct customer · " + customer + " · " + laundry.notice)
	return record

func run() -> void:
	studio = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	while not studio.enhancements_ready: await process_frame
	studio.consumer_shell.dismiss_welcome()
	tools = studio.laundry_tools
	for id in Plan.definitions()["stations"]:
		check(studio.library.assets.has(id), "Reviewed laundry art resolves · " + id)
	for mode in ["2d", "3d"]:
		await normal(mode)
	await interruption()
	await networks()
	await combined()
	studio.free()
	await process_frame
	print("LAUNDRY WORKFLOW: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func normal(mode: String) -> void:
	await setup(mode)
	if not await enter(): return
	var doc: RefCounted = studio.current()
	var treasury: Dictionary = doc.data.get("economy_account", {}).duplicate(true)
	var context: Dictionary = Props.context(world.exploration)
	var plain: Dictionary = object("ordinary")
	var plain_node: Node = context["instances"][stations["ordinary"]]
	var anchor: Variant = Props.anchor(plain_node, plain, studio.library, mode, Props.profile(plain), "approach")
	world.player.teleport_to(world.player.get_parent().to_local(plain_node.get_parent().to_global(anchor)))
	await physics_frame
	var plain_prompt: String = world.exploration.interaction_prompt()
	var ordinary: Dictionary = world.exploration.nearby.get("prop", {})
	check(ordinary.get("item", {}).get("uid") == stations["ordinary"] and ordinary.get("profile", {}).get("kind") == "appliance",
		"Ordinary washers keep their original appliance interaction in " + mode + " · " + plain_prompt)
	if not ordinary.is_empty():
		world.exploration.interact()
		check(not world.exploration.props.active.is_empty(), "The original washer action starts normally.")
		world.exploration.props.reset(false)
	var site: Dictionary = await counter()
	if site.is_empty(): return
	var alex: Dictionary = receive_with_button("alex")
	var jules: Dictionary = receive_with_button("jules")
	var sam: Dictionary = receive_with_button("sam")
	if alex.is_empty() or jules.is_empty() or sam.is_empty(): return
	check(not laundry.receive("alex")["ok"] and site["orders"].size() == 3, "A customer cannot submit the same active order twice.")
	var tags: Array = alex["items"].duplicate(true)
	check(not laundry.return_load(alex["id"], "alex")["ok"], "The counter refuses an unfinished order.")
	advance(.25)
	check(alex["station"] == stations["wash"] and alex["locks"].size() == 2 and jules["station"].is_empty()
		and sam["station"].is_empty() and site["account"]["stock"]["detergent"] == 2, "The oldest fitting order acquires the washer first and uses one detergent.")
	var registry: RefCounted = Reservations.for_world(world)
	check(registry.acquire(site["scope"] + stations["wash"], studio) == 0, "Other jobs cannot reserve an occupied machine.")
	await arrive("fold")
	advance(.25)
	check(laundry.counter.is_empty() and alex["remaining"] < 6 and not laundry.effects.entries.is_empty(),
		"Walking away closes the counter while the washer runs with visible feedback.")
	world.exploration.leave_interior()
	await settle()
	check(world.exploration.interior == null, "The attendant can leave the facility entirely during a wash.")
	advance(5.75)
	check(alex["stage"] == "dry" and alex["station"] == stations["dry"] and jules["station"] == stations["wash"]
		and sam["station"].is_empty() and alex["condition"] == "Wet", "Unattended wash transfers the same load and the second customer gets the washer.")
	world.exploration.photo.active = true
	var remaining: float = alex["remaining"]
	advance(1)
	check(alex["remaining"] == remaining, "Photo pauses unattended machine timers.")
	world.exploration.photo.active = false
	advance(5)
	check(alex["stage"] == "fold" and alex["condition"] == "Dry" and alex["items"] == tags,
		"Drying preserves the original item identities.")
	if not await enter(): return
	await arrive("fold")
	if not use("fold", "Fold the next"): return
	advance(1)
	await arrive("counter")
	advance(.25)
	check(alex["stage"] == "fold" and alex["station"].is_empty(), "Walking away from a folding table frees it and leaves the load dry.")
	await arrive("fold")
	use("fold", "Fold the next")
	advance(3)
	check(alex["stage"] == "return" and alex["condition"] == "Folded" and alex["station"].is_empty(), "Folding releases the table and makes a claim ticket ready.")
	site = await counter()
	if site.is_empty(): return
	var receipt_count: int = site["account"]["receipts"].size()
	check(not laundry.return_load(alex["id"], "jules")["ok"] and site["account"]["receipts"].size() == receipt_count,
		"A different customer cannot claim a folded load.")
	await capture_counter(mode)
	site = await counter()
	if site.is_empty(): return
	var id: String = alex["id"]
	laundry.view.rows["alex"]["primary"].pressed.emit()
	var receipt: Dictionary = site["account"]["receipts"].get(id, {})
	check(receipt.get("state") == "completed" and receipt.get("items") == tags and receipt.get("customer") == "alex",
		"The correct counter button issues one receipt for those exact items.")
	check(not laundry.return_load(id,"alex")["ok"] and site["account"]["receipts"].size() == receipt_count + 1,
		"Replaying pickup cannot issue another receipt.")
	check(doc.data.get("economy_account", {}) == treasury, "Preview receipts leave the saved treasury unchanged.")
	studio.set_walking(false)
	var path: String = OUTPUT + "/laundry_" + mode
	check(studio.write_project(path + ".isocity.json", false), "Authored facility saves in " + mode)
	var repair: RefCounted = Repair.new(studio.library)
	var reopened: Dictionary = repair.read(path + ".isocity.json")
	check(reopened["ok"] and repair.issues.is_empty() and Plan.enabled(reopened["content"]["documents"][mode]), "A clean reopen retains the laundry setting.")
	var damaged: Dictionary = doc.data.duplicate(true)
	damaged["laundry"] = {"enabled": "yes"}
	var corrupt: Dictionary = damaged["objects"][0]["interior"]["objects"][1]
	corrupt["laundry"]["capacity"] = 100
	var repaired: Dictionary = Repair.new(studio.library).world(damaged, mode, "broken_laundry", 0)
	check(not Plan.enabled(repaired) and Plan.station(repaired["objects"][0]["interior"]["objects"][1]).is_empty()
		and repaired["objects"][0]["interior"]["objects"][1]["uid"] == corrupt["uid"], "Repair disables invalid settings and retains the placed machine.")
	if "--portable" in OS.get_cmdline_user_args():
		var packed: Dictionary = Portable.new().save(world, doc.data, studio.library, path + ".zip")
		check(packed["ok"], "The bundled facility can export as source · " + packed.get("message", ""))
	check(studio.load_project(path + ".isocity.json") and laundry.facilities.is_empty() and registry.entries.is_empty()
		and Plan.enabled(studio.current().data), "Reopen clears active loads and machine reservations but preserves the authored facility.")

func interruption() -> void:
	await setup("2d")
	if not await enter(): return
	var wash: Dictionary = root_room()["objects"].filter(func(item: Dictionary) -> bool: return item["uid"] == stations["wash"])[0]
	wash["laundry"]["capacity"] = 2
	world.exploration.apply_room("ground")
	var site: Dictionary = await counter()
	if site.is_empty(): return
	var rejected: Dictionary = laundry.receive("jules")
	check(not rejected["ok"] and rejected["reason"].contains("4-item") and site["orders"].is_empty(), "An oversized load cannot enter the queue.")
	check(laundry.receive("alex")["ok"], "A smaller order fits the same washer.")
	var alex: Dictionary = order(site, "alex")
	var id: String = alex["id"]
	var cancelled: Dictionary = laundry.return_load(id, "alex", true)
	check(cancelled["ok"] and cancelled["receipt"]["condition"] == "Dirty" and site["account"]["stock"]["detergent"] == 3,
		"Cancellation before washing returns dirty items and frees the reserved detergent.")
	laundry.receive("alex")
	alex = order(site, "alex")
	advance(.25)
	await arrive("wash")
	use("wash", "Switch off")
	advance(2)
	check(alex["station"].is_empty() and alex["stage"] == "wash" and alex["condition"] == "Dirty"
		and site["account"]["stock"]["detergent"] == 2, "Switching off an active washer requeues the same load without double-spending detergent.")
	use("wash", "Switch on")
	advance(.25)
	check(alex["station"] == stations["wash"] and site["account"]["stock"]["detergent"] == 2,
		"Restoring the machine retries the same order without another dose.")
	wash["laundry"]["capacity"] = 1
	world.exploration.apply_room("ground")
	advance(.25)
	check(alex["station"].is_empty() and "fits" in alex["wait"], "Reducing capacity invalidates the active reservation.")
	var clone: Dictionary = wash.duplicate(true)
	clone["uid"] = "washer-clone"
	clone["laundry"]["capacity"] = 2
	clone["position"] = Utility.Traffic.world(Vector2(0,-10),"2d")
	root_room()["objects"].append(clone)
	root_room()["objects"].erase(wash)
	world.exploration.apply_room("ground")
	advance(.25)
	check(alex["station"] == clone["uid"] and alex["items"].size() == 2
		and Reservations.for_world(world).current(site["scope"] + stations["wash"]).is_empty(),
		"A cloned machine has independent capacity and receives a fresh reservation, while the deleted one is free.")
	advance(6)
	check(alex["stage"] == "dry", "Retry reaches drying with the same load.")
	var dryer: Dictionary = root_room()["objects"].filter(func(item: Dictionary) -> bool: return item["uid"] == stations["dry"])[0]
	root_room()["objects"].erase(dryer)
	world.exploration.apply_room("ground")
	advance(.25)
	check(alex["station"].is_empty() and alex["condition"] == "Wet", "Removing a running dryer keeps the load wet and releases its reservation.")
	site = await counter()
	if site.is_empty(): return
	cancelled = laundry.return_load(alex["id"], "alex", true)
	check(cancelled["ok"] and cancelled["receipt"]["condition"] == "Wet" and cancelled["receipt"]["state"] == "cancelled"
		and cancelled["receipt"]["items"] == alex["items"] and site["account"]["stock"]["detergent"] == 2,
		"Post-wash cancellation returns those wet items without refunding the detergent.")
	await arrive("supply")
	use("supply", "Restock detergent")
	check(site["account"]["stock"]["detergent"] == Plan.detergent_capacity("detergent"), "The reviewed detergent station replenishes bounded stock.")
	studio.set_walking(false)

func networks() -> void:
	await setup("2d", true)
	var doc: RefCounted = studio.current()
	var pump: String = place("2d:Added_Well_Well_Wall_03fb84ee", Vector2(-15,2))
	var generator: String = place("3d:HanX_Construction/Generator", Vector2(-15,-3))
	doc.data["utilities"] = {"power": true, "water": true}
	doc.data["utility_nodes"] = [
		{"uid":"plant", "kind":"power", "object_uid":generator, "enabled":true},
		{"uid":"well", "kind":"water", "object_uid":pump, "enabled":true, "quantity":20},
		{"uid":"service-power", "kind":"power", "object_uid":host_uid, "enabled":true},
		{"uid":"service-water", "kind":"water", "object_uid":host_uid, "enabled":true},
	]
	doc.data["utility_edges"] = [
		{"uid":"wire", "kind":"power", "enabled":true, "from":{"object_uid":generator,"socket":"output"}, "to":{"object_uid":host_uid,"socket":"input"}},
		{"uid":"pipe", "kind":"water", "enabled":true, "from":{"object_uid":pump,"socket":"outlet"}, "to":{"object_uid":host_uid,"socket":"inlet"}},
	]
	studio.changed()
	if not await enter(): return
	var power: Node = world.exploration.power
	var water: Node = world.exploration.garden.water_network
	check(power.graph["nodes"][host_uid]["fixtures"] == 9 and water.graph["nodes"][host_uid]["fixtures"] == 3,
		"Real network demand includes the existing appliance and opted-in machines’ power and water.")
	for network in [power,water]:
		for tick in 10: network.step(.25)
	check(power.served(host_uid) == 16 and water.served(host_uid) == 9 and not water.forecast and not power.forecast,
		"Connected networks deliver the configured owned-room loads on real ticks.")
	var site: Dictionary = await counter()
	if site.is_empty(): return
	laundry.receive("alex")
	var alex: Dictionary = order(site,"alex")
	if alex.is_empty(): return
	doc.data["utility_edges"][1]["enabled"] = false
	water.configure(doc.data, studio.library, true)
	advance(.25)
	check(alex["station"].is_empty() and "water" in alex["wait"] and site["account"]["stock"]["detergent"] == 3,
		"A water outage before wash leaves the detergent reserved and unused.")
	doc.data["utility_edges"][1]["enabled"] = true
	water.configure(doc.data, studio.library, true)
	for tick in 10: water.step(.25)
	advance(.25)
	check(alex["station"] == stations["wash"], "Restoring water after a delivery tick starts washing.")
	doc.data["utility_edges"][0]["enabled"] = false
	power.configure(doc.data, studio.library, true)
	advance(.25)
	check(alex["station"].is_empty() and "electricity" in alex["wait"] and alex["condition"] == "Dirty",
		"A power outage interrupts the cycle and preserves the original condition.")
	doc.data["utilities"] = {"power": false, "water": false}
	for network in [power,water]: network.configure(doc.data, studio.library, true)
	advance(.25)
	check(alex["station"] == stations["wash"] and site["account"]["stock"]["detergent"] == 2,
		"With both simulations disabled the existing load can resume using its original detergent dose.")
	studio.set_walking(false)

func combined() -> void:
	await setup("2d", false, true)
	if not await enter(): return
	var site: Dictionary = await counter()
	if site.is_empty(): return
	laundry.receive("alex")
	laundry.receive("jules")
	advance(.25)
	var alex: Dictionary = order(site,"alex")
	var jules: Dictionary = order(site,"jules")
	if alex.is_empty() or jules.is_empty(): return
	check(alex["station"] == stations["wash"] and jules["station"].is_empty(), "A stacked washer/dryer exposes only one physical reservation.")
	advance(6)
	check(alex["stage"] == "dry" and alex["station"].is_empty() and jules["station"] == stations["wash"],
		"The combined machine services the older queued request before a new stage.")
	advance(6)
	check(alex["station"] == stations["wash"] and alex["stage"] == "dry" and jules["station"].is_empty(),
		"The same physical machine can later dry without accepting two loads.")
	studio.set_walking(false)
	if "--portable" in OS.get_cmdline_user_args():
		var packed: Dictionary = Portable.new().save(world, studio.current().data, studio.library, OUTPUT + "/restricted.zip")
		check(not packed["ok"] and packed["message"].contains("restricts redistributing"), "Supplied laundromat art honors the source-export restriction.")

func capture_authoring(mode: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	studio.selected_uid = stations["wash"]
	studio.selected_uids.assign([stations["wash"]])
	for simple in [false, true]:
		studio.consumer_shell.set_active(simple, false)
		studio.consumer_shell.dismiss_welcome()
		for size in [Vector2i(1480,900), Vector2i(960,640)]:
			root.size = size
			studio.accessibility_settings.restore({"text_scale":1.5,"high_contrast":true,"large_targets":true} if size.x == 960 else {})
			studio._command("laundry", null)
			await settle()
			tools.apply_station.grab_focus()
			await settle()
			check(visible_focus(tools.apply_station, size), "Authoring button stays reachable · " + str([mode,simple,size]))
			capture("authoring_" + mode, simple, size.x)
			tools.apply_station.release_focus()
	restore_capture()

func capture_counter(mode: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	for simple in [false, true]:
		studio.consumer_shell.set_active(simple, false)
		studio.consumer_shell.dismiss_welcome()
		for size in [Vector2i(1480,900), Vector2i(960,640)]:
			root.size = size
			studio.accessibility_settings.restore({"text_scale":1.5,"high_contrast":true,"large_targets":true} if size.x == 960 else {})
			await settle()
			var site: Dictionary = await counter()
			if site.is_empty(): return
			laundry.view.refresh()
			var pickup: Button = laundry.view.rows["alex"]["primary"]
			pickup.grab_focus()
			await settle()
			check(visible_focus(pickup, size) and laundry.view.panel.is_visible_in_tree()
				and laundry.view.scroll.get_global_rect().encloses(pickup.get_global_rect()) and pickup.text.begins_with("Return"),
				"Pickup stays reachable · " + str([mode,simple,size,pickup.get_global_rect(),laundry.view.scroll.get_global_rect(),laundry.view.scroll.scroll_vertical]))
			capture("counter_" + mode, simple, size.x)
			pickup.release_focus()
	restore_capture()

func visible_focus(control: Control, size: Vector2i) -> bool:
	return control.has_focus() and Rect2(Vector2.ZERO, Vector2(size)).encloses(control.get_global_rect())

func capture(prefix: String, simple: bool, width: int) -> void:
	RenderingServer.force_draw(false)
	RenderingServer.force_draw(false)
	var path: String = OUTPUT + "/%s_%s_%d.png" % [prefix, "simple" if simple else "precision", width]
	check(root.get_texture().get_image().save_png(path) == OK, "Captured the native laundry surface.")

func restore_capture() -> void:
	root.size = Vector2i(1480,900)
	studio.accessibility_settings.restore({})
	studio.consumer_shell.set_active(false, false)
