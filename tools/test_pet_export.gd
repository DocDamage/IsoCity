extends SceneTree

const Plan = preload("res://scripts/builder/pet_plan.gd")
var checks: int
var failures: int
var scene: Node
var pet: Node

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: "+message)
	return ok

func frames(count: int) -> void:
	for frame in count: await physics_frame

func visit() -> void:
	var config: Dictionary = Plan.settings(scene.studio_data)
	if not check(config["enabled"] and Plan.supported(config["asset"],scene.exploration.library),"The isolated project resolves the selected companion."): return
	scene.walking = true
	scene._set_mode()
	scene.player.set_physics_process(false)
	await frames(20)
	if not check(is_instance_valid(pet.actor.body) and pet.actor.source.is_pet and pet.actor.source.sprite.frame == 5,
		"The playable project spawns the supplied pet at its home."): return
	var home: Vector2 = pet.nav.metric(pet.actor.body.global_position)
	scene.player.teleport_to(scene.player.get_parent().to_local(pet.nav.position(home+Vector2(-1,0))))
	await frames(3)
	check(scene.exploration.interaction_prompt().contains("commands"),"The isolated E interaction recognizes its companion.")
	scene.exploration.interact()
	if not check(pet.has_menu() and pet.view.buttons["follow"].has_focus(),"The keyboard command menu opens with focus."): return
	pet.view.buttons["follow"].pressed.emit()
	scene.player.teleport_to(scene.player.get_parent().to_local(pet.nav.position(Vector2(5,0))))
	var animated: bool = false
	var around: bool = false
	for frame in 720:
		await physics_frame
		var point: Vector2 = pet.nav.metric(pet.actor.body.global_position)
		animated = animated or (pet.actor.action == "walk" and pet.actor.source.sprite.frame in [2,3,4])
		around = around or absf(point.y-home.y) > .65
		if point.x > 3.4: break
	check(animated and around and pet.nav.metric(pet.actor.body.global_position).x > 3.4,"The isolated runtime animates and walks around the actual barrier.")
	pet.command("rest")
	await frames(650)
	check(pet.motion == "stay" and pet.actor.source.sprite.frame == 5
		and pet.nav.metric(pet.actor.body.global_position).distance_to(home) < .35,"The isolated pet walks back home and rests.")
	check(scene.dimension == "2d" or (pet.actor.card.mesh.position.y > 0 and pet.actor.card.material.albedo_texture != null),
		"The Model-world companion uses the supplied Pixel animation above the ground.")

func run() -> void:
	scene = load("res://city.tscn").instantiate()
	root.add_child(scene)
	await frames(8)
	pet = scene.exploration.pet
	await visit()
	scene.free()
	await process_frame
	print("PORTABLE PET: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
