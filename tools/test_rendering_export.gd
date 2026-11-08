extends SceneTree

const Budget = preload("res://scripts/builder/rendering_budget.gd")
const SHIP = "3d:Supplemental_Spaceships_II/hammerhead_cruiser"
var checks: int
var failures: int

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: "+message)

func drawn() -> void:
	for frame in 9: await RenderingServer.frame_post_draw
	await process_frame

func run() -> void:
	var scene: Node = load("res://city.tscn").instantiate()
	root.add_child(scene)
	await drawn()
	scene.walking = false
	scene._set_mode()
	var instance: Node = scene.city_instances["hero"]
	var document: Dictionary = scene.studio_data.duplicate(true)
	var profile: Dictionary = Budget.profile(scene.exploration.library.assets[SHIP])
	check(not profile.is_empty() and ResourceLoader.exists(profile["low"]["path"]) and ResourceLoader.exists(profile["full"]["path"]),
		"Both packaged visual editions resolve without the Studio checkout.")
	if scene.dimension == "2d":
		scene.camera.position = Vector2.ZERO
		scene.camera.zoom = Vector2.ONE*2.2
	else:
		scene.target = Vector3.ZERO
		scene.zoom = 19.0
	await drawn()
	if scene.dimension == "2d":
		check(instance.sprite.texture is ImageTexture and scene.city_instances["matching"].sprite.texture == instance.sprite.texture
			and instance.viewport == null,"The standalone Pixel world shares its actual rendered image.")
	else:
		check(instance.get_node("Model").visible and scene.presentation.tracked["hero"]["detail"] == null,
			"The standalone Model world starts on the low-detail edition.")
	var photo: Node = scene.exploration.photo
	check(photo.start(),"The portable Photo action starts.")
	await drawn()
	if scene.dimension == "2d":
		check(instance.photo_quality and instance.photo_profile["full"]["sha256"] == profile["full"]["sha256"]
			and instance.sprite.texture is ImageTexture,"The portable Pixel photo uses the packaged full mesh.")
	else:
		check(is_instance_valid(scene.presentation.tracked["hero"]["detail"]) and not instance.get_node("Model").visible,
			"The portable Model photo displays the packaged full mesh.")
	photo.stop()
	await drawn()
	check((not instance.photo_quality if scene.dimension == "2d" else instance.get_node("Model").visible)
		and scene.studio_data == document,"Leaving Photo restores regular presentation and preserves the serialized city.")
	scene.free()
	await process_frame
	print("PORTABLE RENDERING: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
