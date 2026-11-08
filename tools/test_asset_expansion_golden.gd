extends SceneTree

const FIXTURES = "res://tools/fixtures/asset_expansion"
const OUTPUT = "res://output/verification/asset_expansion/P7/golden"
const VIEWS = {
	"modern_block": [Vector3(22, 0, 0), 58.0],
	"interior_activity_floor": [Vector3(1, 0, -1), 18.0],
	"utility_shortage": [Vector3(42, 0, 7), 74.0],
	"construction_site": [Vector3(7, 0, 12), 52.0],
	"waterfront": [Vector3(10, 0, 7), 32.0],
	"space_outpost": [Vector3(-4, 0, 20), 68.0],
}
const Document = preload("res://scripts/builder/document.gd")
const Templates = preload("res://scripts/builder/templates.gd")
const Traffic = preload("res://scripts/builder/traffic_plan.gd")
const Citizens = preload("res://scripts/builder/citizen_plan.gd")
const Transit = preload("res://scripts/builder/transit_plan.gd")
const School = preload("res://scripts/builder/school_plan.gd")
const Services = preload("res://scripts/builder/service_plan.gd")
const Floors = preload("res://scripts/builder/floor_plan.gd")
const FloorDocument = preload("res://scripts/builder/floor_document.gd")
const Copy = preload("res://scripts/builder/owned_room_copy.gd")
const Activities = preload("res://scripts/builder/resident_activity_plan.gd")
const Laundry = preload("res://scripts/builder/laundry_plan.gd")
const Cooking = preload("res://scripts/builder/cooking_plan.gd")
const Utility = preload("res://scripts/builder/utility_plan.gd")
const Construction = preload("res://scripts/builder/construction_plan.gd")
const Blueprints = preload("res://scripts/builder/blueprint_plan.gd")
const Cooperation = preload("res://scripts/builder/cooperative_plan.gd")
const Harbor = preload("res://scripts/builder/harbor_plan.gd")
const Outpost = preload("res://scripts/builder/space_outpost_plan.gd")
const Repair = preload("res://scripts/builder/project_repair.gd")
const Store = preload("res://scripts/builder/project_store.gd")
const Portable = preload("res://scripts/builder/portable_export.gd")

var studio: Control
var library: RefCounted
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", message)
	return ok

func object_at(data: Dictionary, id: String) -> Dictionary:
	for object in data["objects"]:
		if object["uid"] == id: return object
	return {}

func modern_block(data: Dictionary, seed: int) -> void:
	var network: Dictionary = Traffic.build(data)
	var crossing: Dictionary = network["sections"].get(Traffic.Roads.key(Vector2i.ZERO), {})
	check(crossing.get("neighbors", []).size() == 4 and network["controls"]["active"].size() == 2,
		"Modern block has a four-way junction with active signals")
	var people: Dictionary = Citizens.build(data, library)
	check(data["citizens"]["seed"] == seed and people["residents"].size() == 2 and Citizens.build(data, library) == people,
		"Modern block seeds residents deterministically")
	var transit: Dictionary = Transit.build(data, library)
	check(transit["lines"].has("school_line") and School.enabled(object_at(data, "school"))
		and School.required_bus(data) == School.bus_asset("3d"), "Modern block has an active school bus and assigned stops")
	var service: Dictionary = Services.build(data, library)
	check(Services.choose(service, "fire", "cafe", {}, "golden_dispatch", "fire_station")["ok"],
		"Modern block has a real fire response route to the cafe")

func interior_activity_floor(data: Dictionary) -> void:
	var room: Dictionary = object_at(data, "community_school")["interior"]
	var plan: Dictionary = Activities.compile(room, library)
	check(plan["floors"].size() == 2 and plan["links"].size() == 1 and plan["links"][0]["kind"] == "elevator",
		"Activity floor has two compiled floors and an elevator connection")
	var lower_seats: Array = plan["stations"].filter(func(station: Dictionary) -> bool:
		return station["uid"] in ["seat_a", "seat_b"] and station["floor"] == "ground")
	check(lower_seats.size() == 2, "Activity floor exposes both classroom seats")
	check(Laundry.profile(object_at(room, "washer")).get("role") == "wash"
		and Laundry.profile(object_at(room, "dryer")).get("role") == "dry"
		and Cooking.profile(object_at(room, "prep")).get("role") == "prep"
		and Cooking.profile(object_at(room, "range")).get("role") == "cook",
		"Activity floor uses real laundry and kitchen station profiles")
	var copied: Dictionary = Copy.room(room)
	check(Floors.valid(copied) and copied["floors"][0]["uid"] != room["floors"][0]["uid"],
		"Copying the activity room preserves floor links and remaps ownership")
	var edit := FloorDocument.new()
	edit.configure(room.duplicate(true))
	if not check(edit.switch_floor("upper"), "The upper room opens in the owned floor document"): return
	edit.checkpoint()
	edit.object("upper_seat")["position"][0] += 1
	check(edit.switch_floor("ground") and edit.object("upper_seat").is_empty(),
		"The upper seat stays in its own scope when switching floors")
	check(edit.undo() and edit.floor_uid == "upper" and edit.object("upper_seat")["position"][0] == -4,
		"Undo restores the upper placement and reopens its floor")
	check(edit.redo() and edit.object("upper_seat")["position"][0] == -3,
		"Redo moves only the upper seat")
	var interrupted: Dictionary = room.duplicate(true)
	interrupted["objects"] = interrupted["objects"].filter(func(item: Dictionary) -> bool:
		return item["uid"] != "seat_a")
	var revised: Dictionary = Activities.compile(interrupted, library)
	check(revised["semantic_revision"] != plan["semantic_revision"] and revised["stations"].all(
		func(station: Dictionary) -> bool: return station["uid"] != "seat_a"),
		"Removing an activity seat invalidates its compiled assignment")

func utility_shortage(data: Dictionary) -> void:
	var graph: Dictionary = Utility.compile(data, library, "water")
	check(graph["components"].size() == 2 and graph["links"].values().all(func(link: Dictionary) -> bool: return link["reason"].is_empty()),
		"Utility shortage has two real disconnected networks and valid runs")
	var result: Dictionary = Utility.allocate(graph, {})
	check(result["allocations"] == {"west_home":5, "west_shop":1, "east_home":5, "east_shop":4},
		"Utility shortage prioritizes the west home and leaves the east supply independent")
	var balance: Dictionary = result["balance"]
	check(balance["opening"] + balance["production"] == balance["delivered"] + balance["closing"] + balance["spill"],
		"Utility shortage conserves all produced and stored units")
	var disconnected: Dictionary = data.duplicate(true)
	var west_feed: Dictionary = disconnected["utility_edges"].pop_front()
	var reduced: Dictionary = Utility.allocate(Utility.compile(disconnected, library, "water"), {})
	check(reduced["allocations"]["west_home"] == 0 and reduced["allocations"]["east_home"] == 5,
		"Interrupting the west feed does not interrupt the east service")
	disconnected["utility_edges"].push_front(west_feed)
	var restored: Dictionary = Utility.allocate(Utility.compile(disconnected, library, "water"), {})
	check(restored == result, "Reconnecting the west feed restores the deterministic allocation and balance")

func construction_site(data: Dictionary) -> void:
	var contract: Dictionary = Construction.inspect(data, library)
	check(contract["ok"], "Construction site has a viable material contract: " + contract.get("reason", ""))
	var plan: Dictionary = Blueprints.construct(data, ["staging_assembly"], library)
	check(plan["ok"] and plan.get("quote", {}).get("construction", 0) > 0
		and plan.get("data", {}).get("objects", []).size() == data["objects"].size() + 2,
		"Building the complete staging assembly quotes both placed objects: " + plan.get("reason", ""))
	if plan["ok"]:
		var joints: Array = plan["data"].get("connections", [])
		check(joints.size() == 1 and joints[0]["kind"] == "structure"
			and not object_at(plan["data"], joints[0]["from"]["object_uid"]).is_empty()
			and not object_at(plan["data"], joints[0]["to"]["object_uid"]).is_empty()
			and joints[0]["from"]["object_uid"] != "staging_scaffold",
			"The built staging assembly remaps its structural joint to the placed scaffold bays")
	var before := {"2d":Templates.make("2d", "blank"), "3d":data}
	var guest: Dictionary = before.duplicate(true)
	object_at(guest["3d"], "scaffold")["position"][0] += 1
	check(not Cooperation.allowed(before, guest, "guest", library).is_empty()
		and Cooperation.allowed(before, guest, "foreperson", library).is_empty(),
		"Only the site owner or host can move the protected scaffold")

func waterfront(data: Dictionary) -> void:
	var plan: Dictionary = Harbor.compile(data, library)
	var config: Dictionary = Harbor.settings(data)
	var boat: Dictionary = object_at(data, config["pilot"])
	var hull: Dictionary = Harbor.hull(boat)
	var start: Dictionary = Harbor.socket(plan, data, config["docks"][0], hull)
	var finish: Dictionary = Harbor.socket(plan, data, config["docks"][1], hull)
	check(Harbor.moored_at(plan, Traffic.metric(boat["position"], "3d"), start, hull) and finish["ok"],
		"Waterfront vessel can board from a dry landing and exit at the second berth")
	var route: Dictionary = Harbor.route(plan, start, finish, hull)
	check(route["ok"] and route.get("points", []).size() > 2, "Waterfront plots a physical water route around its dry island")
	if finish["ok"]:
		var blocked: Dictionary = data.duplicate(true)
		var cell: Vector2i = Harbor.cell(finish["water"])
		blocked["water_cells"] = blocked["water_cells"].filter(func(water: Dictionary) -> bool:
			return Vector2i(water["cell"][0], water["cell"][1]) != cell)
		var repaired_plan: Dictionary = Harbor.compile(blocked, library)
		check(not Harbor.socket(repaired_plan, blocked, config["docks"][1], hull)["ok"],
			"Draining the second berth immediately blocks docking there")

func space_outpost(data: Dictionary) -> void:
	var plan: Dictionary = Outpost.inspect(data, library)
	check(plan["ok"] and plan["docks"].has("outpost_dock") and plan["orbital"],
		"Space outpost landing strip is dry and clear with the supplied orbital model")
	var dependencies: Array[String] = Outpost.required(data)
	var allowed: bool = not dependencies.is_empty()
	for id in dependencies:
		allowed = allowed and library.assets.has(id) and library.assets[id].get("data", {}).get("source_export_allowed", true)
	check(allowed and data["group_names"].has("mission_room"), "Space outpost includes its mission room and all permitted supply dependencies")
	var supply: Dictionary = Construction.inspect(data, library)
	check(supply["ok"], "Space outpost has a viable surface supply contract beside its landing strip: " + supply.get("reason", ""))
	if "--packages" in OS.get_cmdline_user_args():
		var result: Dictionary = Portable.new().save(studio.worlds["3d"], data, library, OUTPUT + "/space_outpost.zip")
		check(result["ok"], "Space outpost creates a portable project with the room and supply art: " + result.get("message", ""))

func capture(id: String) -> void:
	if id == "interior_activity_floor":
		studio.interior_tools.start("community_school")
		if not check(studio.interior_tools.editing(), "Studio opens the classroom for capture"): return
	for step in range(5): await process_frame
	var world: Node = studio.worlds["3d"]
	world.target = VIEWS[id][0]
	world.distance = VIEWS[id][1]
	world.yaw = 12
	world.pitch = 55
	world.update_camera()
	for step in range(3): await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image.get_size() == Vector2i(1480, 900) and image.save_png(OUTPUT + "/" + id + ".png") == OK,
		id + " renders and saves a 1480 x 900 native Studio capture")
	if id == "interior_activity_floor": studio.interior_tools.leave()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var captures := "--capture" in OS.get_cmdline_user_args()
	if captures:
		if DisplayServer.get_name() == "headless":
			print("FAIL: Golden scenario screenshots require a graphical display")
			quit(1)
			return
		root.size = Vector2i(1480, 900)
	studio = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	while not studio.enhancements_ready: await process_frame
	if studio.consumer_shell: studio.consumer_shell.dismiss_welcome()
	library = studio.library
	for id in ["modern_block", "interior_activity_floor", "utility_shortage", "construction_site", "waterfront", "space_outpost"]:
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + "/" + id + ".json"))
		if not check(raw is Dictionary and raw.get("version") == 1 and raw.get("scenario") == id and raw.get("seed") == 42
			and raw.get("document") is Dictionary, id + " is a versioned seeded fixture"): continue
		var data: Dictionary = raw["document"]
		if not check(Document.valid(data, "3d", library), id + " passes the current document validator"): continue
		var session := {"version":1, "grid_version":2, "active_mode":"3d",
			"documents":{"2d":Templates.make("2d", "blank"), "3d":data}}
		var repaired: Dictionary = Repair.new(library).session(session)
		if not check(repaired["ok"] and not repaired.get("changed", true),
			id + " opens without repair warnings: " + str(repaired.get("report", {}))): continue
		var file: String = OUTPUT + "/" + id + ".isocity.json"
		if not check(Store.write_json(file, session) and studio.load_project(file), id + " opens through Studio"): continue
		for step in range(5): await process_frame
		var world: Node = studio.worlds["3d"]
		if not check(world.instances.size() == data["objects"].size(), id + " instantiates the authored placements"): continue
		match id:
			"modern_block": modern_block(data, int(raw["seed"]))
			"interior_activity_floor": interior_activity_floor(data)
			"utility_shortage": utility_shortage(data)
			"construction_site": construction_site(data)
			"waterfront": waterfront(data)
			"space_outpost": space_outpost(data)
		if captures: await capture(id)
	studio.free()
	await process_frame
	print("GOLDEN SCENARIOS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
