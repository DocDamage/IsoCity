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
	var id: String = "2d:Supplemental_Characters_Businessman_Idle_7faeca34_Character"
	check(library.assets.has(id), "Selected character ID is available independently")
	var actor: Node = load(library.assets[id]["path"]).instantiate(); root.add_child(actor)
	var definitions: Dictionary = preload("res://scripts/character_actions.gd").for_asset(id)
	check(definitions.get("run", {}).get("clip") == "running", "Portable semantic metadata identifies the supplied run")
	for action in ["idle", "walk", "run"]:
		actor.action = action; actor._apply_direction(); actor._update_animation(.1)
		var clip: Dictionary = library.assets[id]["data"]["animations"][definitions[action]["clip"]]
		check(actor.authored_animation.current["directions"] == clip["directions"], "Relocated actor selects the correct " + action + " source")
		var texture: Texture2D = actor.get_node("Sprite2D").texture
		check(texture is AtlasTexture and texture.atlas != null, "Unspawned action dependency loads from the package")
	actor.action = "sit"; actor._apply_direction()
	check(str(actor.get_meta("animation_fallback", "")).contains("No supported sit"), "Unsupported pose remains an honest fallback after relocation")
	actor.free(); scene.free(); await process_frame; await process_frame
	print("Relocated character actions: %d checks, %d failures" % [checks, failures]); quit(1 if failures else 0)
