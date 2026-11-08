extends SceneTree

const Walker = preload("res://scripts/builder/player_3d.gd")
const Geometry = preload("res://scripts/builder/walk_geometry.gd")
const Fit = preload("res://scripts/builder/grid_fit.gd")
const Factory = preload("res://scripts/builder/asset_instance.gd")
var checks: int = 0
var failures: int = 0
var rig: Node3D
var player: CharacterBody3D
var library: RefCounted

func _init() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func box(size: Vector3, position: Vector3, layer: int = 1) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = position
	body.collision_layer = layer
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = size
	body.add_child(shape)
	preload("res://scripts/builder/roads.gd").box(body, size, Vector3.ZERO, preload("res://scripts/builder/roads.gd").material(Color("8290a0")))
	rig.add_child(body)
	return body

func setup(position: Vector3 = Vector3(-2, 0.02, 0)) -> void:
	if rig: rig.free()
	rig = Node3D.new()
	root.add_child(rig)
	box(Vector3(40, 1, 12), Vector3(0, -0.5, 0), 2)
	player = Walker.new()
	player.position = position
	player.collision_mask = 3
	rig.add_child(player)
	player.set_physics_process(false)

func advance(direction: Vector3, count: int, jump_at: int = -1) -> Dictionary:
	var max_height: float = player.position.y
	var max_rise: float = 0
	var previous: float = player.position.y
	for i in count:
		await physics_frame
		player.move_character(1.0 / Engine.physics_ticks_per_second, direction, i == jump_at)
		max_height = maxf(max_height, player.position.y)
		max_rise = maxf(max_rise, player.position.y - previous)
		previous = player.position.y
	return {"max_height": max_height, "max_rise": max_rise}

func run() -> void:
	library = preload("res://scripts/builder/asset_library.gd").new()
	setup()
	await advance(Vector3.ZERO, 15)
	player.move_character(1.0 / 60, Vector3.RIGHT)
	check(player.velocity.x > 0 and player.velocity.x < player.move_speed * 0.2, "Walking accelerates rather than jumping to full speed")
	await advance(Vector3.RIGHT, 25)
	check(is_equal_approx(player.velocity.x, player.move_speed), "Acceleration reaches the configured speed")
	await advance(Vector3.ZERO, 20)
	check(Vector2(player.velocity.x, player.velocity.z).length() < 0.01, "Braking comes to a dependable stop")
	check(not player.safe_positions.is_empty(), "Clear standing positions are retained for recovery")
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	rig.add_child(camera)
	camera.position = Vector3(4, 6, 4)
	camera.look_at(Vector3.ZERO)
	var right: Vector3 = player.input_direction(Vector2.RIGHT)
	var diagonal: Vector3 = player.input_direction(Vector2.ONE)
	check(is_equal_approx(right.length(), 1) and is_equal_approx(diagonal.length(), 1) and is_zero_approx(diagonal.y), "Camera-relative movement has equal cardinal/diagonal speed on the ground")
	setup()
	box(Vector3(1.2, 0.2, 3), Vector3(0, 0.1, 0))
	await advance(Vector3.ZERO, 12)
	var curb: Dictionary = await advance(Vector3.RIGHT, 70)
	check(player.position.x > 2 and curb["max_height"] > 0.19, "Walker crosses a curb without jumping")
	check(player.step_count > 0, "Curb crossing exercises explicit step probes")
	setup()
	for i in 8:
		var height: float = (i + 1) * 0.24
		box(Vector3(0.5, height, 3), Vector3(i * 0.5 + 0.25, height * 0.5, 0))
	for i in 7:
		var height: float = (7 - i) * 0.24
		box(Vector3(0.5, height, 3), Vector3(4.25 + i * 0.5, height * 0.5, 0))
	await advance(Vector3.ZERO, 12)
	var stairs: Dictionary = await advance(Vector3.RIGHT, 155)
	check(stairs["max_height"] > 1.8 and player.position.x > 8, "Walker ascends and descends a full staircase")
	check(stairs["max_rise"] <= player.step_height + 0.02, "Step rises stay inside the configured limit")
	check(absf(player.position.y) < 0.03, "Descending stairs returns cleanly to the ground")
	setup()
	box(Vector3(0.4, 1.2, 3), Vector3(0, 0.6, 0))
	await advance(Vector3.ZERO, 12)
	await advance(Vector3.RIGHT, 120)
	check(player.position.x < -0.4, "A tall wall cannot be stepped through")
	check(player.recovery_count == 0 and player.stalled_time > 0.8, "Pushing a wall offers recovery without teleporting automatically")
	check(not player.movement_hint().is_empty(), "A stalled character gets a recovery hint")
	setup()
	box(Vector3(1, 0.25, 3), Vector3(0.5, 0.125, 0))
	box(Vector3(3.5, 0.2, 3), Vector3(0.5, 2.05, 0))
	await advance(Vector3.ZERO, 12)
	await advance(Vector3.RIGHT, 85)
	check(player.position.x < 0.2 and player.position.y < 0.2, "A low ceiling prevents an unsafe step-up")
	for width in [0.66, 0.5]:
		setup(Vector3(-4, 0.02, 0))
		for side in [-1, 1]: box(Vector3(5, 2.2, 0.2), Vector3(0, 1.1, side * (width * 0.5 + 0.1)))
		await advance(Vector3.ZERO, 12)
		await advance(Vector3.RIGHT, 110)
		check(player.position.x > 3 if width > 0.6 else player.position.x < -2.5, "Narrow passage respects the capsule's actual width: " + str(width))
	setup()
	await advance(Vector3.ZERO, 12)
	var jump: Dictionary = await advance(Vector3.RIGHT, 65, 0)
	check(jump["max_height"] > 0.9 and absf(player.position.y) < 0.03, "Buffered jump rises and lands on the ground")
	setup()
	await advance(Vector3.ZERO, 12)
	await advance(Vector3.RIGHT, 20)
	var safe: Vector3 = player.position
	player.position.y = -30
	player.last_position = player.position
	await advance(Vector3.ZERO, 1)
	check(player.recovery_count == 1 and player.position.y > -0.01 and player.position.distance_to(safe) < 1, "Falling out of the world recovers to a verified standing position")
	player.teleport_to(Vector3(15, 0.02, 0))
	check(player.safe_positions.is_empty(), "Teleporting to another location clears stale recovery points")
	await advance(Vector3.ZERO, 12)
	check(player.safe_positions.all(func(point: Vector3) -> bool: return point.x > 14), "New recovery points belong to the new location")
	setup()
	await advance(Vector3.ZERO, 12)
	box(Vector3(4, 4, 4), Vector3(0, 2, 0))
	player.position = Vector3(0, 0.02, 0)
	player.last_position = player.position
	await advance(Vector3.ZERO, 35)
	check(player.clear_at(player.global_transform) and player.position.distance_to(Vector3(0, 0.02, 0)) > 0.5, "A character embedded by changed geometry escapes to clear space automatically")
	await test_mixed_geometry()
	await test_2d_movement()
	await test_studio_modes()
	if rig: rig.free()
	print("EXPLORATION MOTION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func test_mixed_geometry() -> void:
	setup(Vector3(-2, 0.02, 0.65))
	var tree: Node3D = Factory.make(library, "2d:Tree_Oak", "3d")
	rig.add_child(tree)
	check(tree.collision.shape is CylinderShape3D, "Sprite trees use authored trunk collision rather than an entire square footprint")
	tree.walk_profile = {}
	tree.last_frame = ""
	tree.update_visual()
	Geometry.prepare(tree, "2d:Tree_Oak", library)
	check(tree.collision.shape is CylinderShape3D, "Older exported sprite wrappers inherit the improved collision profile")
	await advance(Vector3.ZERO, 12)
	await advance(Vector3.RIGHT, 65)
	check(player.position.x > 2, "Walker can pass the visible tree's footprint corners")
	var arch := StaticBody3D.new()
	for center in [Vector3(-1.1, 1, 0), Vector3(1.1, 1, 0), Vector3(0, 2.1, 0)]:
		var size: Vector3 = Vector3(2.55, 0.2, 0.35) if center.y > 2 else Vector3(0.35, 2, 0.35)
		var mesh := MeshInstance3D.new()
		mesh.mesh = BoxMesh.new()
		mesh.mesh.size = size
		mesh.position = center
		arch.add_child(mesh)
		mesh.owner = arch
	var rough := CollisionShape3D.new()
	rough.shape = BoxShape3D.new()
	rough.shape.size = Vector3(2.55, 2.2, 0.35)
	rough.position.y = 1.1
	arch.add_child(rough)
	rough.owner = arch
	var packed := PackedScene.new()
	packed.pack(arch)
	ResourceSaver.save(packed, "res://output/walk_arch_fixture.tscn")
	arch.free()
	library.assets["3d:Probe/WalkArch"] = {"id": "3d:Probe/WalkArch", "mode": "3d", "path": "res://output/walk_arch_fixture.tscn", "name": "Walk arch", "category": "Buildings", "data": {}, "behavior": {"collision": "mesh", "layer": "Buildings", "ground": false}}
	setup(Vector3(0, 0.02, 2))
	arch = Factory.make(library, "3d:Probe/WalkArch", "3d")
	rig.add_child(arch)
	Geometry.prepare(arch, "3d:Probe/WalkArch", library)
	var generated: Array = arch.get_children().filter(func(node: Node) -> bool: return node is CollisionShape3D and node.get_meta("walk_surface", false) and not node.disabled)
	check(generated.size() == 3, "Every mesh's collision stays enabled when an asset has multiple mesh parts")
	await advance(Vector3.ZERO, 12)
	await advance(Vector3.FORWARD, 65)
	check(player.position.z < -2, "Model-shaped collision preserves the walkable arch opening in 3D")
	for side in [-1.1, 1.1]:
		player.teleport_to(Vector3(side, 0.02, 2))
		await advance(Vector3.ZERO, 12)
		await advance(Vector3.FORWARD, 55)
		check(player.position.z > 0, "Both sides of a multi-mesh doorway remain solid: " + str(side))
	var plane := Node2D.new()
	root.add_child(plane)
	var mixed: Node2D = Factory.make(library, "3d:Probe/WalkArch", "2d")
	plane.add_child(mixed)
	check(mixed.walk_shape != null and mixed.collision.disabled and mixed.walk_shape.shape is ConcavePolygonShape2D, "Models in 2D use height-band geometry instead of a filled bounding diamond")
	mixed.configure_walk_collision(false)
	Geometry.prepare_2d(mixed, "3d:Probe/WalkArch", library)
	check(mixed.walk_collision and mixed.collision.disabled and not mixed.walk_shape.disabled, "Older exported model wrappers inherit opening-preserving 2D collision")
	var avatar: CharacterBody2D = load("res://scenes/items/Characters/Office_Worker.tscn").instantiate()
	avatar.collision_mask = 1
	avatar.collision_layer = 0
	plane.add_child(avatar)
	avatar.set_physics_process(false)
	avatar.position = Fit.pixels(Vector2(0, 2))
	for i in 65:
		await physics_frame
		avatar.move_character(1.0 / 60, Fit.pixels(Vector2(0, -1)).normalized())
	check(Fit.grid(avatar.position).y < -2, "The same arch opening remains walkable when the model is used in 2D")
	plane.free()
	var door: Node3D = Factory.make(library, "2d:Door_White", "3d")
	rig.add_child(door)
	check(door.collision.shape is BoxShape3D and door.collision.shape.size.z < 0.2, "Sprite doors have authored thin collision rather than a full-depth block")
	var bench: Node3D = Factory.make(library, "3d:HanX_Park/Bench_Park", "3d")
	rig.add_child(bench)
	Geometry.prepare(bench, "3d:HanX_Park/Bench_Park", library)
	check(bench.get_meta("precise_collision", false), "Open furniture now uses mesh-shaped collision")
	for asset in ["3d:HanX_Park/Tree_Oak", "3d:HanX_Park/Tree_Pine", "3d:HanX_City/Street_Tree"]:
		var model: Node3D = Factory.make(library, asset, "3d")
		rig.add_child(model)
		Geometry.prepare(model, asset, library)
		check(model.get_meta("precise_collision", false), "Native tree collision follows the trunk and canopy mesh: " + asset)

func test_2d_movement() -> void:
	var plane := Node2D.new()
	root.add_child(plane)
	var avatar: CharacterBody2D = load("res://scenes/items/Characters/Office_Worker.tscn").instantiate()
	avatar.collision_mask = 1
	avatar.collision_layer = 0
	plane.add_child(avatar)
	avatar.set_physics_process(false)
	await physics_frame
	avatar.move_character(1.0 / 60, Vector2.RIGHT)
	check(avatar.velocity.x > 0 and avatar.velocity.x < avatar.move_speed * 0.2, "2D walking also accelerates smoothly")
	for i in 25:
		await physics_frame
		avatar.move_character(1.0 / 60, Vector2.RIGHT)
	check(avatar.position.x > 20 and not avatar.safe_positions.is_empty(), "2D walking remains continuous and records safe positions")
	var safe: Vector2 = avatar.position
	var obstacle := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	shape.shape.size = Vector2(20, 20)
	obstacle.add_child(shape)
	obstacle.position = safe + Vector2(30, 0)
	plane.add_child(obstacle)
	await physics_frame
	avatar.position = obstacle.position
	check(avatar.recover_to_safe() and avatar.clear_at(avatar.global_position), "2D recovery returns a stuck character to clear space")
	avatar.teleport_to(Vector2(500, 500))
	check(avatar.safe_positions.is_empty(), "2D interior teleports clear stale recovery history")
	plane.free()

func test_studio_modes() -> void:
	var studio: Control = load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled = false
	root.add_child(studio)
	for i in 5: await process_frame
	studio.switch_mode("3d")
	var count: int = studio.current().data["objects"].size()
	studio.selected_uid = studio.current().data["objects"][0]["uid"]
	studio.selected_uids.assign([studio.selected_uid])
	studio.refresh_controls()
	studio.set_walking(true)
	check(studio.mode_badge.text.begins_with("WALK MODE") and not studio.mode_inspector.visible and not studio.mode_library.visible and not studio.overlay.visible, "Walk mode clearly labels controls and hides editing panels/overlays")
	var remove := InputEventKey.new()
	remove.keycode = KEY_DELETE
	remove.pressed = true
	studio._unhandled_key_input(remove)
	check(studio.current().data["objects"].size() == count, "Build editing shortcuts do not change the city while walking")
	studio.set_walking(false)
	check(studio.mode_badge.text.begins_with("BUILD MODE") and studio.mode_inspector.visible and studio.mode_library.visible and studio.overlay.visible, "Returning to Build restores the editing controls")
	studio.set_walking(true)
	studio._command("tool", "select")
	check(not studio.walking and studio.mode_badge.text.begins_with("BUILD MODE"), "Choosing a build command returns from Walk mode automatically")
	var path: String = "user://motion_export_test.tscn"
	check(preload("res://scripts/builder/exporter.gd").save_scene(studio.worlds["3d"], studio.current().data, studio.library, path) == OK, "Updated movement and collision export with a playable scene")
	var exported: Node = load(path).instantiate()
	root.add_child(exported)
	var walker: CharacterBody3D = exported.get_node("Player")
	walker.set_physics_process(false)
	walker.teleport_to(Vector3(50, 0.02, 50))
	for i in 12:
		await physics_frame
		walker.move_character(1.0 / 60, Vector3.ZERO)
	for i in 30:
		await physics_frame
		walker.move_character(1.0 / 60, Vector3.RIGHT)
	check(walker.position.x > 51 and not walker.safe_positions.is_empty(), "Exported scenes use the improved controller and recovery history")
	exported.free()
	DirAccess.remove_absolute(path)
	if "--capture" in OS.get_cmdline_user_args():
		studio.set_walking(true)
		for i in 10: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://output/editor_walk_mode.png")
		studio.set_walking(false)
	studio.free()
