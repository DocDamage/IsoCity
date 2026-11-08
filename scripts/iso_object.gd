@tool
class_name IsoObject
extends Node2D

const IsoMath = preload("res://scripts/iso_math.gd")
const Catalog = preload("res://scripts/catalog.gd")
const TileRotation = preload("res://scripts/iso_tile_rotation.gd")
var terrain_visual_offset:=Vector2.ZERO:
	set(value):
		terrain_visual_offset=value
		if has_node("Sprite2D"): $Sprite2D.offset=-origin_offset+value

## Isometric Object supporting 2:1 projection, directions, day/night, elevation and full animation playback.

@export var item_id: String = "":
	set(val):
		item_id = val
		_load_from_catalog()
		_update_visuals()

@export var category: String = ""
@export var kind: String = ""

@export_enum("SE", "SW", "NW", "NE", "Left", "Right", "Corner") var direction: String = "SE":
	set(val):
		direction = val
		_apply_direction()

@export var night_mode: bool = false:
	set(val):
		night_mode = val
		_update_frame()

@export_enum("idle", "walk", "sit", "wave") var action: String = "idle":
	set(val):
		action = val
		_anim_timer = 0.0
		_anim_frame_idx = 0
		_update_frame()

@export var playing: bool = true
@export var animation_fps: float = 4.0

@export var footprint: Vector2i = Vector2i(1, 1):
	set(val):
		footprint = val
		_update_collision()
		queue_redraw()

@export var has_collision: bool = true:
	set(val):
		has_collision = val
		_update_collision()

@export var origin_offset: Vector2 = Vector2.ZERO:
	set(val):
		origin_offset = val
		if has_node("Sprite2D"):
			$Sprite2D.offset = -origin_offset+terrain_visual_offset
		queue_redraw()

@export var total_frames: int = 1:
	set(val):
		total_frames = val
		if has_node("Sprite2D"):
			$Sprite2D.hframes = max(1, total_frames)

@export var directions_data: Dictionary = {}

@export var grid_pos: Vector2i = Vector2i.ZERO:
	set(val):
		grid_pos = val
		position = IsoMath.tile_to_world(grid_pos, elevation)

@export var elevation: int = 0:
	set(val):
		elevation = val
		position = IsoMath.tile_to_world(grid_pos, elevation)

@export var show_debug_footprint: bool = false:
	set(val):
		show_debug_footprint = val
		queue_redraw()

var _anim_timer: float = 0.0
var _anim_frame_idx: int = 0
var _blink_timer: float = 0.0

func _ready() -> void:
	y_sort_enabled = true
	if not has_node("Sprite2D"):
		var sp := Sprite2D.new()
		sp.name = "Sprite2D"
		sp.centered = false
		add_child(sp)
		sp.owner = self
	
	if directions_data.is_empty() and not item_id.is_empty():
		_load_from_catalog()
	_apply_direction()
	_update_collision()

func _update_collision() -> void:
	# Export setters run before a PackedScene has attached its saved children.
	if not is_node_ready():
		return
	if not has_collision or kind == "tile" or category == "Wall Decor":
		if has_node("StaticBody2D"):
			$StaticBody2D.queue_free()
		return
		
	var sb: StaticBody2D
	if has_node("StaticBody2D"):
		sb = $StaticBody2D
	else:
		sb = StaticBody2D.new()
		sb.name = "StaticBody2D"
		add_child(sb)
		sb.owner = self
		
	var cp: CollisionPolygon2D
	if sb.has_node("CollisionPolygon2D"):
		cp = sb.get_node("CollisionPolygon2D")
	else:
		cp = CollisionPolygon2D.new()
		cp.name = "CollisionPolygon2D"
		sb.add_child(cp)
		cp.owner = self
		
	cp.polygon = IsoMath.get_footprint_diamond(Vector2i.ZERO, footprint, 0)

func _load_from_catalog() -> void:
	if item_id.is_empty():
		return
	var item: Dictionary = Catalog.get_item(item_id)
	if item.is_empty():
		return
	category = item.get("category", category)
	kind = item.get("kind", kind)
	total_frames = item.get("frames", total_frames)
	var dirs: Dictionary = item.get("directions", {})
	if not dirs.is_empty():
		directions_data = dirs

func _apply_direction() -> void:
	if not has_node("Sprite2D"):
		return
	var s: Sprite2D = $Sprite2D
	s.centered = false
	if (kind == "tile" and TileRotation.supported(category)) or Catalog.get_item(item_id).get("surface") == "ground":
		var size_value: Vector2 = Vector2(32, 16)
		if s.texture: size_value = Vector2(s.texture.get_width() / float(maxi(1, total_frames)), s.texture.get_height())
		s.material = TileRotation.material_for(direction, Vector2i.ZERO, maxi(1, total_frames), size_value)
	
	if directions_data.is_empty() and not item_id.is_empty():
		_load_from_catalog()
	
	if directions_data.is_empty():
		s.offset = -origin_offset+terrain_visual_offset
		s.hframes = max(1, total_frames)
		_update_frame()
		return
	
	var dir_key: String = direction
	if not directions_data.has(dir_key):
		var keys: Array = directions_data.keys()
		if keys.size() > 0:
			dir_key = str(keys[0])
		else:
			return
			
	var dinfo: Dictionary = directions_data[dir_key]
	var file_path: String = dinfo.get("file", "")
	if not file_path.is_empty():
		var tex: Texture2D = preload("res://scripts/sprite_view.gd").texture(dinfo)
		if tex: s.texture = tex
			
	var orig: Array = dinfo.get("origin", [0, 0])
	origin_offset = Vector2(orig[0], orig[1])
	s.offset = -origin_offset+terrain_visual_offset
	
	var fp: Array = dinfo.get("footprint", [1, 1])
	footprint = Vector2i(fp[0], fp[1])
	var alignment: Array = dinfo.get("alignment_transform", [])
	if alignment.size() == 4:
		s.transform = Transform2D(Vector2(alignment[0], alignment[1]), Vector2(alignment[2], alignment[3]), Vector2.ZERO)
		s.set_meta("import_alignment", true)
	elif s.has_meta("import_alignment"):
		s.transform = Transform2D.IDENTITY
		s.remove_meta("import_alignment")
	if alignment.size() == 4 and Catalog.get_item(item_id).get("surface") == "ground":
		# Rotate the calibrated plane itself. Rotating a cropped texture inside
		# its old rectangle clips partial edge tiles and loses their grid phase.
		s.material = null
		var plane := Transform2D(Vector2(16, 8), Vector2(-16, 8), Vector2.ZERO)
		var center: Vector2 = plane * Vector2(footprint) * 0.5
		var turn := Transform2D(0, center) * plane * Transform2D(deg_to_rad(TileRotation.degrees(direction)), Vector2.ZERO) * plane.affine_inverse() * Transform2D(0, -center)
		s.transform = turn * s.transform
	
	total_frames = dinfo.get("frames", total_frames)
	s.hframes = max(1, total_frames)
	
	_update_frame()
	_update_collision()
	queue_redraw()

func _process(delta: float) -> void:
	if not playing:
		return
	if not has_node("Sprite2D"):
		return
	var s: Sprite2D = $Sprite2D
	if s.hframes <= 1:
		return
		
	# Buildings and Street Lights: frame 1 = night, frame 0 = day
	if kind == "build" or item_id.begins_with("Street_Light") or item_id.begins_with("Park_Lamp"):
		s.frame = 1 if night_mode else 0
		return
		
	# General animated props (Fountain, Fireplace, Aquarium, Washing Machine, Arcade, etc.)
	if total_frames > 1:
		_anim_timer += delta
		var speed: float = max(0.5, animation_fps)
		if _anim_timer >= (1.0 / speed):
			_anim_timer = 0.0
			_anim_frame_idx = (_anim_frame_idx + 1) % total_frames
			s.frame = _anim_frame_idx

func _update_frame() -> void:
	if not has_node("Sprite2D"):
		return
	var s: Sprite2D = $Sprite2D
	if kind == "build" or item_id.begins_with("Street_Light") or item_id.begins_with("Park_Lamp"):
		s.frame = 1 if (night_mode and s.hframes > 1) else 0
	else:
		s.frame = 0

func _update_visuals() -> void:
	_apply_direction()

func _draw() -> void:
	if not show_debug_footprint and not Engine.is_editor_hint():
		return
	if show_debug_footprint:
		var poly: PackedVector2Array = IsoMath.get_footprint_diamond(Vector2i.ZERO, footprint, 0)
		draw_colored_polygon(poly, Color(0.2, 0.8, 1.0, 0.25))
		draw_polyline(poly, Color(0.2, 0.8, 1.0, 0.8), 1.0)
		draw_line(poly[3], poly[0], Color(0.2, 0.8, 1.0, 0.8), 1.0)
