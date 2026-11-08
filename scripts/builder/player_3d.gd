extends CharacterBody3D
var terrain_motion_filter: Callable
var terrain_position_safe: Callable

@export var active: bool = false
@export var move_speed: float = 5.0
@export var acceleration: float = 22.0
@export var braking: float = 28.0
@export var air_acceleration: float = 8.0
@export var step_height: float = 0.35
@export var jump_speed: float = 7.0
@export var gravity: float = 20.0
@export var camera_path: NodePath = NodePath("../Camera3D")

var body: Node3D
var limbs: Array[Node3D] = []
var phase: float = 0.0
var capsule: CollisionShape3D
var clearance_shape: CapsuleShape3D
var embedded_shape: CapsuleShape3D
var safe_positions: Array[Vector3] = []
var stalled_time: float = 0.0
var overlap_time: float = 0.0
var recovery_count: int = 0
var step_count: int = 0
var last_position := Vector3.ZERO
var jump_buffer: float = 0
var coyote_time: float = 0
var jump_held: bool = false
var recover_held: bool = false
const SKIN: float = 0.003

func _ready() -> void:
	body = Node3D.new()
	body.name = "Character"
	add_child(body)
	part(body, Vector3(0.52, 0.55, 0.28), Vector3(0, 1.1, 0), Color("37b9ab"))
	part(body, Vector3(0.40, 0.40, 0.38), Vector3(0, 1.59, 0), Color("e6b38b"))
	part(body, Vector3(0.43, 0.14, 0.41), Vector3(0, 1.79, 0.015), Color("49392f"))
	for x in [-0.1, 0.1]: part(body, Vector3(0.055, 0.06, 0.025), Vector3(x, 1.61, -0.2), Color("233242"))
	for index in 4:
		var limb := Node3D.new()
		var arm: bool = index < 2
		var side: float = -1 if index % 2 == 0 else 1
		limb.position = Vector3(side * (0.35 if arm else 0.15), 1.32 if arm else 0.85, 0)
		body.add_child(limb)
		limbs.append(limb)
		part(limb, Vector3(0.16 if arm else 0.2, 0.53 if arm else 0.68, 0.2), Vector3(0, -0.26 if arm else -0.34, 0), Color("e6b38b") if arm else Color("273c5a"))
		if not arm: part(limb, Vector3(0.22, 0.16, 0.35), Vector3(0, -0.71, -0.05), Color("d3dedf"))
	var shape := CollisionShape3D.new()
	capsule = shape
	var collision := CapsuleShape3D.new()
	collision.radius = 0.28
	collision.height = 1.8
	clearance_shape = collision.duplicate()
	clearance_shape.radius -= 0.005
	clearance_shape.height -= 0.01
	embedded_shape = collision.duplicate()
	embedded_shape.radius -= 0.03
	embedded_shape.height -= 0.12
	shape.shape = collision
	shape.position.y = 0.9
	add_child(shape)
	floor_snap_length = step_height + 0.08
	floor_constant_speed = true
	floor_stop_on_slope = true
	floor_max_angle = deg_to_rad(46)
	safe_margin = 0.001
	max_slides = 6
	last_position = global_position

func part(parent: Node3D, size: Vector3, position_value: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = size
	mesh.mesh = cube
	mesh.position = position_value
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	mesh.material_override = material
	parent.add_child(mesh)

var control_input: Callable

func _physics_process(delta: float) -> void:
	if not active:
		velocity = Vector3.ZERO
		jump_held = false
		recover_held = false
		return
	var input := Vector2(float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	var jump: bool = Input.is_physical_key_pressed(KEY_SPACE)
	var recover: bool = Input.is_physical_key_pressed(KEY_X)
	if control_input.is_valid():
		input=Vector2(float(control_input.call("move_right"))-float(control_input.call("move_left")),float(control_input.call("move_down"))-float(control_input.call("move_up")))
		jump=control_input.call("jump")
		recover=control_input.call("recover")
	move_character(delta, input_direction(input), jump and not jump_held, recover and not recover_held)
	jump_held = jump
	recover_held = recover

func input_direction(input: Vector2) -> Vector3:
	var camera: Camera3D = get_node_or_null(camera_path)
	if not camera: return Vector3(input.x, 0, input.y).limit_length(1)
	var right: Vector3 = camera.global_basis.x
	var forward: Vector3 = camera.global_basis.z
	right.y = 0
	forward.y = 0
	return (right.normalized() * input.x + forward.normalized() * input.y).limit_length(1)

func motion_test(pose: Transform3D, motion: Vector3) -> PhysicsTestMotionResult3D:
	var parameters := PhysicsTestMotionParameters3D.new()
	parameters.from = pose
	parameters.motion = motion
	parameters.margin = safe_margin
	parameters.max_collisions = 8
	var result := PhysicsTestMotionResult3D.new()
	PhysicsServer3D.body_test_motion(get_rid(), parameters, result)
	return result

func clear_at(pose: Transform3D, deep: bool = false) -> bool:
	if not capsule: return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = embedded_shape if deep else clearance_shape
	query.transform = pose * capsule.transform
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	query.margin = 0.0001
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func floor_hit(result: PhysicsTestMotionResult3D) -> bool:
	for i in result.get_collision_count():
		if result.get_collision_normal(i).dot(Vector3.UP) >= cos(floor_max_angle): return true
	return false

func try_step(motion: Vector3) -> bool:
	if motion.length_squared() < 0.000001 or step_height <= 0: return false
	var blocked: PhysicsTestMotionResult3D = motion_test(global_transform, motion)
	var wall: bool = false
	for i in blocked.get_collision_count():
		if blocked.get_collision_normal(i).dot(Vector3.UP) < cos(floor_max_angle): wall = true
	if not wall: return false
	var up: PhysicsTestMotionResult3D = motion_test(global_transform, Vector3.UP * (step_height + SKIN))
	var lift: float = step_height + SKIN if up.get_collision_count() == 0 else up.get_travel().y - SKIN
	if lift <= SKIN: return false
	var raised: Transform3D = global_transform
	raised.origin.y += lift
	var forward: PhysicsTestMotionResult3D = motion_test(raised, motion)
	if forward.get_collision_count() > 0: return false
	raised.origin += motion
	var landing: Transform3D = raised
	var down: PhysicsTestMotionResult3D = motion_test(raised, Vector3.DOWN * (lift + floor_snap_length))
	if floor_hit(down): landing.origin += down.get_travel() + Vector3.UP * SKIN
	if not floor_hit(down) or landing.origin.y-global_position.y<=SKIN:
		# Capsule edges meet a curb before their center can reach its flat tread.
		# Probe beneath the leading foot, then validate the complete landing capsule.
		var floor_point: Variant = null
		for fraction in [0.33, 0.66, 1.0]:
			var from: Vector3 = raised.origin + motion.normalized() * (capsule.shape.radius + SKIN) * fraction
			var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * (lift + floor_snap_length), collision_mask)
			query.exclude = [get_rid()]
			var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
			if hit.is_empty() or hit["normal"].dot(Vector3.UP) < cos(floor_max_angle): continue
			if hit["position"].y - global_position.y > SKIN and hit["position"].y - global_position.y <= lift + SKIN:
				floor_point = hit["position"]
				break
		if not floor_point is Vector3: return false
		landing.origin.y = floor_point.y + SKIN
	var rise: float = landing.origin.y - global_position.y
	if rise <= SKIN or rise > minf(step_height + SKIN * 3, lift + SKIN) or not clear_at(landing): return false
	global_transform = landing
	velocity.y = 0
	step_count += 1
	return true

func remember_safe() -> void:
	var pose: Transform3D = global_transform
	if not is_on_floor() or not clear_at(pose): return
	if terrain_position_safe.is_valid() and not terrain_position_safe.call(global_position): return
	if not safe_positions.is_empty() and safe_positions.back().distance_to(global_position) < 0.35: return
	safe_positions.append(global_position)
	if safe_positions.size() > 40: safe_positions.pop_front()

func supported_position(point: Vector3) -> Variant:
	var pose: Transform3D = global_transform
	pose.origin = point
	var up: PhysicsTestMotionResult3D = motion_test(pose, Vector3.UP * (step_height + SKIN))
	var lift: float = step_height + SKIN if up.get_collision_count() == 0 else maxf(0, up.get_travel().y - SKIN)
	pose.origin.y += lift
	if not clear_at(pose): return null
	var down: PhysicsTestMotionResult3D = motion_test(pose, Vector3.DOWN * (lift + 0.65))
	if not floor_hit(down): return null
	pose.origin += down.get_travel() + Vector3.UP * SKIN
	return pose.origin if clear_at(pose) else null

func recover_to_safe() -> bool:
	var candidates: Array[Vector3] = []
	for i in range(safe_positions.size() - 1, -1, -1): candidates.append(safe_positions[i])
	for radius in [0.5, 1.0, 2.0, 3.0]:
		for turn in 8:
			var angle: float = turn * TAU / 8
			candidates.append(global_position + Vector3(cos(angle) * radius, 0, sin(angle) * radius))
	for candidate in candidates:
		if candidate.distance_to(global_position) < 0.4: continue
		var supported: Variant = supported_position(candidate)
		if not supported is Vector3: continue
		if terrain_position_safe.is_valid() and not terrain_position_safe.call(supported): continue
		global_position = supported
		velocity = Vector3.ZERO
		last_position = global_position
		overlap_time = 0
		stalled_time = 0
		recovery_count += 1
		return true
	return false

func teleport_to(destination: Vector3) -> void:
	position = destination
	velocity = Vector3.ZERO
	safe_positions.clear()
	last_position = global_position
	coyote_time = 0
	jump_buffer = 0
	overlap_time = 0
	stalled_time = 0

func movement_hint() -> String:
	if not str(get_meta("terrain_blocked","")).is_empty(): return get_meta("terrain_blocked")
	return "X · Recover to a clear standing position" if stalled_time > 0.8 or overlap_time > 0.05 else ""

func move_character(delta: float, desired: Vector3, jump: bool = false, recover: bool = false) -> void:
	if delta <= 0: return
	# External teleports must not reuse an old district's or interior's recovery points.
	if global_position.distance_to(last_position) > 8:
		safe_positions.clear()
		last_position = global_position
	# Do not let penetration resolution push an embedded character beneath the
	# floor before recovery can find a supported position at the current height.
	if not clear_at(global_transform, true):
		overlap_time += delta
		velocity = Vector3.ZERO
		if recover or overlap_time > 0.25: recover_to_safe()
		last_position = global_position
		return
	desired.y = 0
	desired = desired.limit_length(1) * move_speed
	var grounded: bool = is_on_floor()
	coyote_time = 0.1 if grounded else maxf(0, coyote_time - delta)
	jump_buffer = 0.12 if jump else maxf(0, jump_buffer - delta)
	var speed: Vector2 = Vector2(velocity.x, velocity.z)
	var rate: float = braking if desired.length_squared() < 0.001 else (acceleration if grounded else air_acceleration)
	speed = speed.move_toward(Vector2(desired.x, desired.z), rate * delta)
	velocity.x = speed.x
	velocity.z = speed.y
	if terrain_motion_filter.is_valid():
		var filtered: Vector3=terrain_motion_filter.call(global_position,Vector3(velocity.x,0,velocity.z)*delta)/delta
		velocity.x=filtered.x; velocity.z=filtered.z
	velocity.y = minf(velocity.y, 0) if grounded else velocity.y
	velocity.y -= gravity * delta
	var jumped: bool = jump_buffer > 0 and coyote_time > 0
	if jumped:
		velocity.y = jump_speed
		jump_buffer = 0
		coyote_time = 0
	floor_snap_length = step_height + 0.08
	var before: Vector3 = global_position
	var horizontal := Vector3(velocity.x, 0, velocity.z) * delta
	# At walking speed the capsule can balance on a rounded tread edge while
	# move_and_slide briefly reports no floor. A nearby flat support permits
	# the same swept step without treating a falling/jumping body as grounded.
	var supported: bool=grounded
	if not supported and velocity.y<=0:
		var query:=PhysicsRayQueryParameters3D.create(global_position+Vector3.UP*SKIN,global_position-Vector3.UP*floor_snap_length,collision_mask,[get_rid()])
		var hit: Dictionary=get_world_3d().direct_space_state.intersect_ray(query)
		supported=not hit.is_empty() and hit["normal"].dot(Vector3.UP)>=cos(floor_max_angle)
	var stepped: bool = supported and not jumped and try_step(horizontal)
	# A successful step already swept the intended horizontal displacement.
	if stepped:
		var saved: Vector3 = velocity
		velocity.x = 0
		velocity.z = 0
		velocity.y = -gravity * delta
		move_and_slide()
		velocity.x = saved.x
		velocity.z = saved.z
	else: move_and_slide()
	if grounded and not jumped and velocity.y <= 0: apply_floor_snap()
	var moved: Vector3 = global_position - before
	var horizontal_distance: float = Vector2(moved.x, moved.z).length()
	stalled_time = stalled_time + delta if desired.length_squared() > 1 and horizontal_distance < move_speed * delta * 0.05 else 0
	var pose: Transform3D = global_transform
	overlap_time = 0 if clear_at(pose) else overlap_time + delta
	remember_safe()
	if recover or overlap_time > 0.25 or global_position.y < -25: recover_to_safe()
	last_position = global_position
	var walking_speed: float = horizontal_distance / delta
	if walking_speed > 0.15:
		body.rotation.y = lerp_angle(body.rotation.y, atan2(-moved.x, -moved.z), minf(1, delta * 14))
		phase += delta * 10 * minf(1, walking_speed / move_speed)
	var amplitude: float = minf(1, walking_speed / move_speed) * 0.55
	for index in limbs.size(): limbs[index].rotation.x = lerpf(limbs[index].rotation.x, sin(phase + (PI if index in [1, 2] else 0.0)) * amplitude, minf(1, delta * 16))
