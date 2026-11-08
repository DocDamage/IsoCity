extends SceneTree

const Harbor = preload("res://scripts/builder/harbor_plan.gd")
const Templates = preload("res://scripts/builder/templates.gd")
const Document = preload("res://scripts/builder/document.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + message)

func dock(doc: RefCounted, uid: String, point: Vector2) -> Dictionary:
	var pier: Dictionary = doc.add(Harbor.PIER, Harbor.Traffic.world(point, doc.data["mode"]), "View_01")
	pier["uid"] = uid
	return {"anchor": uid, "land": [0, 0], "water": [0, 2]}

func route_fixture(mode: String) -> void:
	var doc := Document.new()
	doc.data = Templates.make(mode, "blank")
	doc.data["terrain"] = {"enabled": true, "bounds": [-4, -4, 16, 16]}
	var water: Array = []
	for x in 8:
		for y in 4:
			water.append({"cell": [x, y], "level": 1.0})
	doc.data["water_cells"] = water
	var first: Dictionary = dock(doc, "west_pier", Vector2(1, -1))
	var second: Dictionary = dock(doc, "east_pier", Vector2(15, -1))
	var hull: Dictionary = Harbor.hull({"asset": Harbor.VESSEL, "scale": .25})
	var network: Dictionary = Harbor.compile(doc.data)
	var a: Dictionary = Harbor.socket(network, doc.data, first, hull)
	var b: Dictionary = Harbor.socket(network, doc.data, second, hull)
	check(a["ok"] and b["ok"] and a["land"] == Vector2(1, -1) and b["water"] == Vector2(15, 1),
		mode + " dock sockets resolve in shared terrain coordinates")
	var high := {"rect": Rect2(6, 0, 2, 2), "bottom": 2.6, "top": 2.9}
	network["blocks"][Vector2i(3, 0)] = [high]
	check(Harbor.travel(network, Vector2(5, 1), Vector2(9, 1), 1.0, hull), mode + " vessel fits beneath the high span")
	high["bottom"] = 1.65
	check(not Harbor.travel(network, Vector2(5, 1), Vector2(9, 1), 1.0, hull), mode + " swept hull detects low clearance")
	var detour: Dictionary = Harbor.route(network, a, b, hull)
	check(detour["ok"] and detour["points"].any(func(point: Vector2) -> bool: return point.y > 2),
		mode + " connected route travels around a low obstacle")
	var narrow := {"rect": Rect2(4.6, 1.53, .12, .12), "bottom": .3, "top": 2.4}
	network["blocks"][Vector2i(2, 0)] = [narrow]
	check(not Harbor.passable(network, Vector2(5, 1), 1.0, hull), mode + " entire hull intersects small off-center obstructions")
	var large: Dictionary = Harbor.hull({"asset": Harbor.VESSEL, "scale": .9})
	check(not Harbor.socket(network, doc.data, first, large)["ok"], mode + " larger hull cannot claim a narrow berth")
	check(not Harbor.passable(network, Vector2(1, -1), INF, hull), mode + " dry land and invalid water heights never pass")
	doc.data["water_cells"] = water.filter(func(record: Dictionary) -> bool: return record["cell"][0] != 3)
	network = Harbor.compile(doc.data)
	check(not Harbor.route(network, a, b, hull)["ok"], mode + " disconnected water does not produce a route")
	var stepped: Array = water.duplicate(true)
	for record in stepped:
		if record["cell"][0] == 3: record["level"] = 1.25
	doc.data["water_cells"] = stepped
	check(not Harbor.route(Harbor.compile(doc.data), a, b, hull)["ok"], mode + " a band at a different water level stops travel")
	doc.data["water_cells"] = water
	doc.data["terrain_vertices"] = [{"cell": [0, 0], "height": .9}]
	network = Harbor.compile(doc.data)
	check(not Harbor.socket(network, doc.data, first, hull)["ok"], mode + " shallow corner blocks the complete hull")
	doc.data["terrain_vertices"] = []
	water.append({"cell": [0, -1], "level": 1.0})
	network = Harbor.compile(doc.data)
	check(not Harbor.socket(network, doc.data, first, hull)["ok"], mode + " flooded land invalidates disembarking")
	water.pop_back()
	doc.object("east_pier")["visible"] = false
	network = Harbor.compile(doc.data)
	check(not Harbor.socket(network, doc.data, second, hull)["ok"], mode + " hidden dock releases the water connection")
	doc.object("east_pier")["visible"] = true
	doc.data["objects"].erase(doc.object("east_pier"))
	network = Harbor.compile(doc.data)
	check(not Harbor.socket(network, doc.data, second, hull)["ok"], mode + " deleted dock cannot resolve a stale route")
	doc.data["terrain"]["enabled"] = false
	check(not Harbor.compile(doc.data)["ok"], mode + " disabling terrain stops water routing")

func persisted() -> void:
	var library = preload("res://scripts/builder/asset_library.gd").new()
	var repair = preload("res://scripts/builder/project_repair.gd").new(library)
	var policy = preload("res://scripts/builder/cooperative_plan.gd")
	check(library.assets.has(Harbor.VESSEL) and library.assets.has(Harbor.PIER), "The reviewed vessel and pier resolve through the actual asset library")
	var doc := Document.new()
	doc.data = Templates.make("3d", "blank")
	doc.data["terrain"] = {"enabled": true, "bounds": [-4, -4, 16, 16]}
	var water: Array = []
	for x in range(-3, 5):
		for y in range(-3, 5): water.append({"cell": [x, y], "level": 1.0})
	doc.data["water_cells"] = water
	var item: Dictionary = doc.add("3d:HanX_Construction/Shipping_Container", [0, 2.7, 0], "0", .5)
	var point: Vector2 = Harbor.Zone.footprint(item, "3d", library).get_center()
	var vessel: Dictionary = Harbor.hull({"asset": Harbor.VESSEL, "scale": .25})
	check(Harbor.passable(Harbor.compile(doc.data, library), point, 1.0, vessel), "An elevated prepared model leaves its real clearance open")
	item["position"][1] = .6
	check(not Harbor.passable(Harbor.compile(doc.data, library), point, 1.0, vessel), "The actual model bounds close the water route at vessel height")
	var before := {"2d": Templates.make("2d", "blank"), "3d": doc.data.duplicate(true)}
	doc.checkpoint()
	doc.data["harbor"] = {"enabled": true, "pilot": "test_vessel", "interval": 25}
	doc.finish_checkpoint()
	check(Document.valid(doc.data, "3d", library), "Valid harbor settings coexist with a real city document")
	var stored: Dictionary = JSON.parse_string(JSON.stringify(doc.data))
	var fixed: Dictionary = repair.world(stored, "3d", "city", 0)
	check(fixed["harbor"] == stored["harbor"], "Load and repair preserve valid harbor configuration")
	var candidate: Dictionary = before.duplicate(true)
	candidate["3d"] = doc.data
	check("host" in policy.allowed(before, candidate, "guest", library) and policy.allowed(before, candidate, "host", library).is_empty(),
		"Only the host changes the shared harbor configuration")
	check(doc.undo() and not doc.data.has("harbor") and doc.redo() and doc.data["harbor"]["enabled"], "Undo and Redo restore the saved harbor option")
	stored["harbor"]["interval"] = "unreadable"
	check(not Document.valid(stored, "3d", library), "Document validation rejects a malformed schedule")
	fixed = repair.world(stored, "3d", "city", 0)
	check(not Harbor.enabled(fixed) and repair.issues.any(func(issue: Dictionary) -> bool: return issue["path"] == "city/harbor"),
		"Malformed harbor settings repair to disabled defaults with a recorded issue")

func run() -> void:
	check(not Harbor.enabled({"mode": "2d"}), "Harbors are off by default for existing cities")
	check(not Harbor.enabled({"harbor": {"enabled": true}, "interior_room": true}), "Owned rooms cannot enable harbor movement")
	check(not Harbor.valid({"pilot": "a", "shuttle": "a"}), "The same boat cannot be both manual and scheduled")
	check(not Harbor.valid({"docks": [{"anchor": "pier", "land": [0, INF], "water": [1, 0]}]}), "Reject malformed dock offsets")
	check(Harbor.hull({"asset": "2d:Added_animated_boat_9ee9b341"}).is_empty(), "The baked-water artwork stays scenery")
	check(Harbor.hull({"asset": Harbor.VESSEL, "scale": 4}).is_empty(), "Unreviewed vessel scales are excluded")
	for mode in ["2d", "3d"]: route_fixture(mode)
	persisted()
	print("HARBOR PLAN: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
