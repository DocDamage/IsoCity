extends SceneTree

const Plan = preload("res://scripts/builder/space_outpost_plan.gd")
const Templates = preload("res://scripts/builder/templates.gd")
const Document = preload("res://scripts/builder/document.gd")
const Terrain = preload("res://scripts/builder/terrain_plan.gd")
const Reservations = preload("res://scripts/builder/activity_reservations.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: " + text)

func run() -> void:
	var library = preload("res://scripts/builder/asset_library.gd").new()
	for mode in ["2d", "3d"]:
		var source: Dictionary = Templates.make(mode, "blank")
		check(Plan.required(source).is_empty() and not Plan.settings(source)["enabled"], mode + " outpost is opt-in")
		var draft: Dictionary = Plan.practice(source, library)
		check(draft["ok"], mode + " " + draft.get("reason", "practice site ready"))
		if not draft["ok"]: continue
		var data: Dictionary = draft["data"]
		var config: Dictionary = data["space_outpost"]
		check(Plan.valid(config) and source["objects"].is_empty(), mode + " template is pure and has bounded settings")
		check(Plan.required(data).size() == 3, mode + " exports cargo and both scheduled hulls")
		var original: Dictionary = Plan.inspect(data, library)
		var dock: Dictionary = original["docks"]["outpost_dock"]
		check(not dock["corridor"].has_point(dock["stand"]) and not dock["corridor"].has_point(dock["cargo"]),
			mode + " stand and unloading area are separate from the approach")
		check(dock["entry"].distance_to(dock["berth"]) == Plan.RUNWAY_LENGTH, mode + " publishes a complete approach")
		config["orbital"] = true
		check(Plan.inspect(data, library)["orbital"] and Plan.required(data).size() == 4, mode + " orbit adds one scenery dependency")
		var bad: Dictionary = config.duplicate(true)
		bad["command"] = "arbitrary action"
		check(not Plan.valid(bad), mode + " rejects additional behavior")
		bad = config.duplicate(true)
		bad["docks"].append(bad["docks"][0])
		check(not Plan.valid(bad), mode + " rejects duplicate dock identities")
		var blocked: Dictionary = data.duplicate(true)
		blocked["objects"].append(Document.placement_item("blocked", Plan.definitions()["habitat"],
			Plan.Zone.Traffic.world(dock["berth"], mode), "SE", .43))
		check(Plan.inspect(blocked, library)["docks"].is_empty(), mode + " a building in the approach invalidates the dock")
		var hidden: Dictionary = data.duplicate(true)
		hidden["objects"][1]["visible"] = false
		check(Plan.inspect(hidden, library)["docks"].is_empty(), mode + " a hidden marker cannot claim a landing")
		var missing: Dictionary = data.duplicate(true)
		missing["objects"].remove_at(1)
		check(Plan.inspect(missing, library)["docks"].is_empty(), mode + " deleting the marker invalidates the landing")
		var flooded: Dictionary = data.duplicate(true)
		var landing := Vector2i((dock["berth"] as Vector2) / Terrain.CELL_SIZE)
		flooded["terrain"] = {"enabled": true, "bounds": [-20, -20, 40, 40]}
		flooded["water_cells"] = [{"cell": [landing.x, landing.y], "level": 1.0}]
		check(Plan.inspect(flooded, library)["docks"].is_empty(), mode + " water makes the approach unsuitable")
		var unavailable_id: String = Plan.definitions()["ships"][0]["asset"]
		var saved: Dictionary = library.assets[unavailable_id]
		library.assets.erase(unavailable_id)
		check(not Plan.inspect(data, library)["ok"], mode + " unavailable model blocks schedule")
		library.assets[unavailable_id] = saved
		config["enabled"] = false
		check(Plan.required(data).is_empty() and Plan.inspect(data, library)["docks"].is_empty(), mode + " disabling releases future requirements")
		check(not Plan.practice(data, library)["ok"], mode + " template preserves existing layouts")
	var world := Node.new()
	var claims: RefCounted = Reservations.for_world(world)
	var first := RefCounted.new()
	var second := RefCounted.new()
	var token: int = claims.acquire("orbit:outpost_dock", first)
	check(token > 0 and claims.acquire("orbit:outpost_dock", second) == 0, "First arrival owns the dock")
	claims.release_owner(first)
	var next: int = claims.acquire("orbit:outpost_dock", second)
	claims.release("orbit:outpost_dock", token)
	check(next > token and claims.current("orbit:outpost_dock")["token"] == next, "A cancelled arrival cannot release the next reservation")
	world.free()
	print("SPACE OUTPOST PLAN: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
