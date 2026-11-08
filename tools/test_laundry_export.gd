extends SceneTree

const Plan = preload("res://scripts/builder/laundry_plan.gd")
const Props = preload("res://scripts/builder/prop_plan.gd")
const Utility = preload("res://scripts/builder/utility_profiles.gd")
var scene: Node
var checks: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + message)

func frames(count: int) -> void:
	for frame in count: await physics_frame

func arrive(role: String) -> bool:
	var exploration: Node = scene.exploration
	var context: Dictionary = Props.context(exploration)
	for station in exploration.laundry.station_list(context["data"]).values():
		if station["setting"]["role"] != role: continue
		var item: Dictionary = station["item"]
		var node: Node = context["instances"][item["uid"]]
		var bounds: Rect2 = Utility.footprint(item, exploration.library, scene.dimension)
		var point: Array = Utility.Traffic.world(Utility.side_point(bounds, "south", .65), scene.dimension)
		var at: Variant = node.get_parent().to_global(Vector2(point[0],point[1])) if scene.dimension == "2d" \
			else node.get_parent().to_global(Vector3(point[0],node.position.y,point[2]))
		scene.player.teleport_to(scene.player.get_parent().to_local(at))
		await physics_frame
		exploration.interaction_prompt()
		return exploration.nearby.get("laundry", "") == item["uid"]
	return false

func finish() -> void:
	scene.free()
	await process_frame
	print("PORTABLE LAUNDRY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func run() -> void:
	scene = load("res://city.tscn").instantiate()
	root.add_child(scene)
	await frames(8)
	var walk: Node = scene.exploration
	var laundry: Node = walk.laundry
	var host: String = scene.studio_data["objects"][0]["uid"]
	check(Plan.enabled(scene.studio_data) and laundry.facilities.is_empty(),
		"The isolated project has authored stations and no session orders.")
	scene.walking = true
	scene._set_mode()
	scene.player.set_physics_process(false)
	scene.player.teleport_to(walk.entrance(scene.city_instances[host]))
	await frames(4)
	walk.interact()
	await frames(7)
	check(walk.interior_uid == host, "The isolated player enters the actual authored room.")
	if walk.interior_uid != host: await finish(); return
	scene.player.set_physics_process(false)
	var reached: bool = await arrive("counter")
	check(reached, "The exported counter is reachable.")
	if not reached: await finish(); return
	walk.interact()
	var site: Dictionary = laundry.counter_site()
	check(not site.is_empty(), "The exported counter opens its actual order controls.")
	if site.is_empty(): await finish(); return
	laundry.view.rows["alex"]["primary"].pressed.emit()
	laundry.view.rows["jules"]["primary"].pressed.emit()
	check(site["orders"].size() == 2, "Two identified customers are received through the controls.")
	if site["orders"].size() != 2: await finish(); return
	var order: Dictionary = site["orders"].values()[0]
	var tags: Array = order["items"].duplicate(true)
	await frames(30)
	check(not order["station"].is_empty() and order["stage"] == "wash"
		and site["orders"].values()[1]["station"].is_empty(), "Real frames assign the oldest load to one washer.")
	check(await arrive("fold"), "The folding table is reachable in the exported room.")
	await frames(720)
	check(order["stage"] == "fold" and order["items"] == tags and laundry.counter.is_empty(),
		"Unattended wash and dry finish on real physics frames with exact tags.")
	walk.interact()
	await frames(205)
	check(order["stage"] == "return" and order["condition"] == "Folded", "Timed folding enables claim pickup.")
	check(await arrive("counter"), "The attendant can return to the counter.")
	walk.interact()
	var rejected: Dictionary = laundry.return_load(order["id"], "jules")
	laundry.view.rows["alex"]["primary"].pressed.emit()
	var receipt: Dictionary = site["account"]["receipts"].get(order["id"], {})
	check(not rejected["ok"] and receipt.get("state") == "completed" and receipt.get("items") == tags
		and receipt.get("customer") == "alex", "Pickup checks customer identity and issues one exact receipt.")
	await finish()
