extends SceneTree

const Plan = preload("res://scripts/builder/emergency_training_plan.gd")
const Templates = preload("res://scripts/builder/templates.gd")
const Dispatch = preload("res://scripts/builder/service_dispatch.gd")
const Scenario = preload("res://scripts/builder/scenario_plan.gd")
var checks: int = 0
var failures: int = 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: " + text)

func run() -> void:
	var library = preload("res://scripts/builder/asset_library.gd").new()
	for mode in ["2d", "3d"]:
		for id in ["fire_drill", "medical_drill"]:
			var source: Dictionary = Templates.make(mode, "blank")
			var draft: Dictionary = Plan.practice(source, library, id, "reviewed_attempt")
			check(draft["ok"], mode + " " + id + " " + draft.get("reason", "practice route ready"))
			if not draft["ok"]: continue
			var data: Dictionary = draft["data"]
			var settings: Dictionary = data["scenario"]
			check(Scenario.valid(settings) and not source.has("scenario"), "Bounded drill settings leave the input untouched")
			var plan: Dictionary = Plan.inspect(data, library)
			check(plan["ok"] and plan["trip"]["station"] == settings["station"], "Drill uses the selected station and a real outbound and return route")
			check(plan["steps"].has("kit") == (id == "medical_drill"), "Medical drill adds a distinct kit stage")
			var bad: Dictionary = settings.duplicate(true)
			bad["script"] = "res://unsafe.gd"
			check(not Scenario.valid(bad), "Saved drill definitions reject extra executable fields")
			bad = settings.duplicate(true)
			bad["perimeter"][0] = bad["subject"]
			check(not Scenario.valid(bad), "One placement cannot be both a participant and a perimeter point")
			var participant: Dictionary = data["objects"].filter(func(item: Dictionary) -> bool: return item["uid"] == settings["subject"])[0]
			var descriptor: Dictionary = library.assets[participant["asset"]]
			var old_unavailable: bool = descriptor.get("unavailable", false)
			descriptor["unavailable"] = true
			var missing_art: Dictionary = Plan.inspect(data, library)
			descriptor["unavailable"] = old_unavailable
			check(not missing_art["ok"] and "prepared subject" in missing_art["reason"], "Missing required artwork rejects a drill before dispatch")
			var blocked: Dictionary = data.duplicate(true)
			blocked["roads"] = []
			check(not Plan.inspect(blocked, library)["ok"], "Deleting the response roads invalidates the drill")
			blocked = data.duplicate(true)
			blocked["objects"] = blocked["objects"].filter(func(item: Dictionary) -> bool: return item["uid"] != settings["subject"])
			check(not Plan.inspect(blocked, library)["ok"], "Deleting the participant invalidates the drill")
			var ordinary: Dictionary = Plan.Service.build(data, library)
			var dispatch := Dispatch.new()
			dispatch.configure(ordinary)
			var normal: Dictionary = dispatch.request(plan["service"], settings["incident"])
			var training: Dictionary = dispatch.request(plan["service"], settings["incident"], settings["station"], settings["attempt"])
			check(normal["ok"] and training["ok"] and normal["job"]["id"] != training["job"]["id"], "A drill request is separate from a real city service request")
			dispatch.cancel(training["job"], "Drill stopped")
			check(normal["job"]["state"] == "waiting" and training["job"]["state"] == "cancelled", "Drill stop never cancels an ordinary request")
	print("EMERGENCY TRAINING PLAN: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
