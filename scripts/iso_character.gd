@tool
class_name IsoCharacter
extends CharacterBody2D

const IsoMath = preload("res://scripts/iso_math.gd")
const Catalog = preload("res://scripts/catalog.gd")
var terrain_motion_filter: Callable
var terrain_position_safe: Callable
var terrain_visual_offset:=Vector2.ZERO:
	set(value):
		terrain_visual_offset=value
		if has_node("Sprite2D"): $Sprite2D.offset=-origin_offset+value+interaction_visual_offset

var interaction_visual_offset:=Vector2.ZERO:
	set(value):
		interaction_visual_offset=value
		if has_node("Sprite2D"): $Sprite2D.offset=-origin_offset+terrain_visual_offset+value

@export var item_id: String = "Office_Worker":
	set(val):
		item_id = val
		_update_character_data()

@export_enum("SE", "SW", "NW", "NE") var direction: String = "SE":
	set(val):
		if direction == val:
			return
		direction = val
		_apply_direction()

@export_enum("idle", "walk", "run", "sit", "wave") var action: String = "idle":
	set(val):
		if action == val:
			return
		action = val
		_anim_timer = 0.0
		_anim_frame_idx = 0
		_update_frame()

@export var is_player_controlled: bool = false
@export var move_speed: float = 80.0
@export var acceleration: float = 650.0
@export var braking: float = 850.0
@export var elevation: int = 0:
	set(val):
		elevation = val
		position = IsoMath.tile_to_world(grid_pos, elevation)

@export var grid_pos: Vector2i = Vector2i.ZERO:
	set(val):
		grid_pos = val
		position = IsoMath.tile_to_world(grid_pos, elevation)

@export var directions_data: Dictionary = {}
@export var origin_offset: Vector2 = Vector2.ZERO
@export var is_pet: bool = false

var _anim_timer: float = 0.0
var _anim_frame_idx: int = 0
var _blink_timer: float = 0.0
var authored_animation: RefCounted
var safe_positions: Array[Vector2] = []
var stalled_time: float = 0
var overlap_time: float = 0
var recovery_count: int = 0
var last_move_position := Vector2.ZERO
var recover_held: bool = false
var recovery_initialized: bool = false

@onready var sprite: Sprite2D = $Sprite2D
@onready var col_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	y_sort_enabled = true
	if not has_node("Sprite2D"):
		var sp := Sprite2D.new()
		sp.name = "Sprite2D"
		sp.centered = false
		add_child(sp)
		sp.owner = self
		
	if not has_node("CollisionShape2D"):
		var col := CollisionShape2D.new()
		col.name = "CollisionShape2D"
		var circle := CircleShape2D.new()
		circle.radius = 4.0
		col.shape = circle
		col.position = Vector2(0, 0)
		add_child(col)
		col.owner = self
		
	if directions_data.is_empty():
		_update_character_data()
	_apply_direction()

func _update_character_data() -> void:
	var item: Dictionary = Catalog.get_item(item_id)
	if item.is_empty():
		return
	var clips: Dictionary=item.get("animations",{})
	authored_animation=preload("res://scripts/character_animation.gd").new(self,clips,float(item.get("default_scale",1)),preload("res://scripts/character_actions.gd").for_asset(item_id)) if not clips.is_empty() else null
	is_pet = (item.get("category", "") == "Pets" or item.get("kind", "") == "pet")
	var dirs: Dictionary = item.get("directions", {})
	if not dirs.is_empty():
		directions_data = dirs
	_apply_direction()

func _apply_direction() -> void:
	if authored_animation: authored_animation.apply_view(); return
	if not has_node("Sprite2D"):
		return
	var s: Sprite2D = $Sprite2D
	s.centered = false
	
	if directions_data.is_empty():
		return
		
	var dir_key: String = direction
	if not directions_data.has(dir_key):
		dir_key = "SE" if directions_data.has("SE") else str(directions_data.keys()[0])
		
	var dinfo: Dictionary = directions_data[dir_key]
	var file_path: String = dinfo.get("file", "")
	if not file_path.is_empty():
		var full_path: String = "res://assets/pixel_isometric/" + file_path
		if ResourceLoader.exists(full_path):
			s.texture = load(full_path)
			
	var orig: Array = dinfo.get("origin", [10, 28])
	origin_offset = Vector2(orig[0], orig[1])
	s.offset = -origin_offset+terrain_visual_offset+interaction_visual_offset
	
	s.hframes = 6 if is_pet else 9
	_update_frame()

var control_input: Callable

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
		
	if is_player_controlled:
		var input := Vector2(float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
			float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)))
		var recover: bool = Input.is_key_pressed(KEY_X)
		if control_input.is_valid():
			input=Vector2(float(control_input.call("move_right"))-float(control_input.call("move_left")),float(control_input.call("move_down"))-float(control_input.call("move_up")))
			recover=control_input.call("recover")
		move_character(delta, input, recover and not recover_held)
		recover_held = recover
	else:
		velocity = Vector2.ZERO
		recover_held = false

	_update_animation(delta)

func clear_at(point: Vector2) -> bool:
	var shape: CollisionShape2D = get_node_or_null("CollisionShape2D")
	if not shape or not shape.shape: return false
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape.shape
	query.transform = global_transform
	query.transform.origin = point
	query.transform = query.transform * shape.transform
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()

func recover_to_safe() -> bool:
	var candidates: Array[Vector2] = []
	for i in range(safe_positions.size() - 1, -1, -1): candidates.append(safe_positions[i])
	for radius in [12.0, 24.0, 40.0]:
		for turn in 8: candidates.append(global_position + Vector2.RIGHT.rotated(turn * TAU / 8) * radius)
	for candidate in candidates:
		if candidate.distance_to(global_position) < 8: continue
		if not clear_at(candidate): continue
		if terrain_position_safe.is_valid() and not terrain_position_safe.call(candidate): continue
		global_position = candidate
		velocity = Vector2.ZERO
		last_move_position = global_position
		stalled_time = 0
		overlap_time = 0
		recovery_count += 1
		return true
	return false

func teleport_to(destination: Vector2) -> void:
	position = destination
	velocity = Vector2.ZERO
	safe_positions.clear()
	last_move_position = global_position
	recovery_initialized = true
	stalled_time = 0
	overlap_time = 0

func movement_hint() -> String:
	if not str(get_meta("terrain_blocked","")).is_empty(): return get_meta("terrain_blocked")
	return "X · Recover to a clear position" if stalled_time > 0.8 or overlap_time > 0.05 else ""

func move_character(delta: float, input: Vector2, recover: bool = false) -> void:
	if delta <= 0: return
	if not recovery_initialized or global_position.distance_to(last_move_position) > 128:
		safe_positions.clear()
		recovery_initialized = true
	var desired: Vector2 = input.limit_length(1) * move_speed
	velocity = velocity.move_toward(desired, (braking if desired.is_zero_approx() else acceleration) * delta)
	if terrain_motion_filter.is_valid(): velocity=terrain_motion_filter.call(global_position,velocity*delta)/delta
	var before: Vector2 = global_position
	if not velocity.is_zero_approx(): move_and_slide()
	var distance: float = global_position.distance_to(before)
	stalled_time = stalled_time + delta if not desired.is_zero_approx() and distance < move_speed * delta * 0.05 else 0
	var clear: bool = clear_at(global_position)
	overlap_time = 0 if clear else overlap_time + delta
	if clear and (not terrain_position_safe.is_valid() or terrain_position_safe.call(global_position)) and (safe_positions.is_empty() or safe_positions.back().distance_to(global_position) > 8):
		safe_positions.append(global_position)
		if safe_positions.size() > 40: safe_positions.pop_front()
	if recover or overlap_time > 0.25: recover_to_safe()
	last_move_position = global_position
	if distance > 0.01:
		action = "walk"
		if velocity.x > 0: direction = "NE" if velocity.y < 0 else "SE"
		elif velocity.x < 0: direction = "NW" if velocity.y < 0 else "SW"
		else: direction = "NW" if velocity.y < 0 else "SE"
	else:
		if action in ["walk", "run"]: action = "idle"
	# Keep the grid index without snapping continuous movement to its cell.
	var moved_position: Vector2 = position
	grid_pos = IsoMath.world_to_tile(position, elevation)
	position = moved_position

func _update_animation(delta: float) -> void:
	if not is_finite(delta) or delta <= 0: return
	if authored_animation: authored_animation.tick(delta); return
	if not has_node("Sprite2D"):
		return
	var s: Sprite2D = $Sprite2D
	
	if not is_pet:
		# Human Character: 0: idle, 1: blink, 2-5: walk, 6: sit, 7-8: wave
		if action in ["walk", "run"]:
			_anim_timer += delta
			if _anim_timer >= 0.16:
				_anim_timer = 0.0
				_anim_frame_idx = (_anim_frame_idx + 1) % 4
				s.frame = 2 + _anim_frame_idx
		elif action == "wave":
			_anim_timer += delta
			if _anim_timer >= 0.25:
				_anim_timer = 0.0
				_anim_frame_idx = (_anim_frame_idx + 1) % 2
				s.frame = 7 + _anim_frame_idx
		elif action == "sit":
			s.frame = 6
		else: # idle
			_blink_timer += delta
			if _blink_timer > 3.0:
				s.frame = 1
				if _blink_timer > 3.15:
					s.frame = 0
					_blink_timer = 0.0
			else:
				s.frame = 0
	else:
		# Pet: 0: idle, 1: idle2, 2-4: walk, 5: sit
		if action in ["walk", "run"]:
			_anim_timer += delta
			if _anim_timer >= 0.18:
				_anim_timer = 0.0
				_anim_frame_idx = (_anim_frame_idx + 1) % 3
				s.frame = 2 + _anim_frame_idx
		elif action == "sit":
			s.frame = 5
		else:
			_anim_timer += delta
			if _anim_timer >= 0.8:
				_anim_timer = 0.0
				_anim_frame_idx = (_anim_frame_idx + 1) % 2
				s.frame = _anim_frame_idx

func _update_frame() -> void:
	if authored_animation: authored_animation.apply_view(); return
	if not has_node("Sprite2D"):
		return
	var s: Sprite2D = $Sprite2D
	if not is_pet:
		if action == "sit":
			s.frame = 6
		elif action in ["walk", "run"]:
			s.frame = 2
		elif action == "wave":
			s.frame = 7
		else:
			s.frame = 0
	else:
		if action == "sit":
			s.frame = 5
		elif action in ["walk", "run"]:
			s.frame = 2
		else:
			s.frame = 0

