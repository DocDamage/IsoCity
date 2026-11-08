extends SceneTree
var checks: int = 0
var failures: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; print("FAIL: " + message)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var scene: Node = load("res://city.tscn").instantiate(); root.add_child(scene)
	for frame in 8: await physics_frame
	var library: RefCounted = scene.exploration.library
	check(preload("res://scripts/builder/document.gd").valid(scene.studio_data, scene.dimension, library), "Packaged ship city validates independently")
	var id: String = "3d:Supplemental_Spaceships_II/belly_bay_bomber"
	check(scene.studio_data["objects"].size() == 1 and scene.studio_data["objects"][0]["asset"] == id, "Stable ship ID survives relocation")
	var texture: Texture2D = library.icon(id)
	check(texture != null and texture.resource_path != "res://assets/editor/missing_object.png" and preload("res://scripts/builder/model_preview.gd").meaningful(texture), "Relocated library resolves the repaired thumbnail")
	var model: Node = load(library.assets[id]["path"]).instantiate()
	check(model != null, "Prepared model loads without original checkout")
	model.free()
	scene.free(); await process_frame; await process_frame
	print("Relocated model previews: %d checks, %d failures" % [checks, failures]); quit(1 if failures else 0)
