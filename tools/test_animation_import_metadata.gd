extends SceneTree
const Plan = preload("res://scripts/builder/asset_import_plan.gd")
const Custom = preload("res://scripts/builder/custom_assets.gd")
const OUTPUT = "res://output/verification/asset_expansion/I06"
var checks: int = 0
var failures: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; print("FAIL: " + message)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var source: Dictionary = Plan.inspect(ProjectSettings.globalize_path("res://tools/fixtures/asset_expansion/animated_triangle.gltf"))
	check(source["ok"], "A minimal original animated glTF decodes")
	if not source["ok"]: print(source); quit(1); return
	check(source["animation_metadata"]["animation_status"] == "animated_mesh" and source["animation_metadata"]["supplied_clips"] == ["Slide"], "Custom inspection reads actual supplied clips")
	var config: Dictionary = source["config"].duplicate(true)
	config["name"] = "I06 original animation fixture"; config["author"] = "IsoCity verification"; config["license"] = "Original verification geometry"
	Custom.registry_override = OUTPUT + "/animation_import_registry.json"
	var thumb: Image = preload("res://scripts/builder/import_thumbnail.gd").make(source, config)
	var installed: Dictionary = Plan.install(source, config, thumb)
	check(installed["ok"], "Animated custom source installs in an isolated test registry")
	if installed["ok"]:
		var id: String = installed["asset"]["id"]
		check(installed["asset"]["data"]["animation_status"] == "animated_mesh", "Installed descriptor retains source animation status")
		var registry: Dictionary = Custom.read_registry()["assets"]
		registry[id]["data"].erase("animation_status"); registry[id]["data"].erase("supplied_clips"); registry[id]["data"]["unrelated_extension"] = "keep"
		check(Custom.save_registry(registry) == OK, "Legacy custom descriptor fixture saves")
		var again: Dictionary = Plan.install(source, config, thumb)
		check(again["ok"] and again["existing"] and again["asset"]["id"] == id, "Reimport refreshes evidence without duplicating or renaming the asset")
		check(again["asset"]["data"]["supplied_clips"] == ["Slide"] and again["asset"]["data"]["unrelated_extension"] == "keep", "Reimport preserves extensions while refreshing clip evidence")
	Plan.release(source); Custom.registry_override = ""
	var rig: Dictionary = Plan.inspect("res://assets/supplemental_models/HanX_SWAT/SWAT_Commander.glb")
	check(rig["ok"] and rig["animation_metadata"]["animation_status"] == "rigged_without_clips" and rig["animation_metadata"]["supplied_clips"].is_empty(), "Imported skinned geometry is not mistaken for supplied animation")
	Plan.release(rig)
	await process_frame; await process_frame
	print("Animation import metadata: %d checks, %d failures" % [checks, failures]); quit(1 if failures else 0)
