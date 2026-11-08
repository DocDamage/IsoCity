extends StaticBody3D

signal before_visual_update
signal visual_updated

const PIXELS_PER_UNIT: float = 32.0
@export var collidable: bool = true
@export var walk_profile: Dictionary = {}
@export var inherit_walk_profile: bool = true
@export var asset_path: String = ""
@export var ground_tile: bool = false
@export var diamond_ground: bool = true
@export var free_angles := Vector3.ZERO
@export var direction: String = "SE":
	set(value):
		direction = value
		if source: source.direction = value; update_visual()
@export var night_mode: bool = false:
	set(value):
		night_mode = value
		if source is IsoObject: source.night_mode = value
var source: Node2D
var mesh: MeshInstance3D
var material: StandardMaterial3D
var collision: CollisionShape3D
var visual_bounds := AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)
var last_frame: String = ""
var card_rect := Rect2()

func _ready() -> void:
	source = load(asset_path).instantiate()
	source.name = "SourceSprite"
	source.visible = false
	add_child(source)
	source.direction = direction
	if source is IsoObject: source.night_mode = night_mode
	for node in [source] + source.find_children("*", "CollisionObject2D", true, false):
		if node is CollisionObject2D: node.collision_layer = 0; node.collision_mask = 0
	mesh = MeshInstance3D.new()
	mesh.name = "SpriteMesh"
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.mesh = QuadMesh.new()
	add_child(mesh)
	material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y if not ground_tile else BaseMaterial3D.BILLBOARD_DISABLED
	mesh.material_override = material
	collision = CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	add_child(collision)
	collision_layer = 1 if collidable else 0
	collision_mask = 0
	update_visual()
	set_angles(free_angles)

func _process(_delta: float) -> void:
	if source: update_visual()

func update_visual() -> void:
	if not mesh or not source: return
	var sprite: Sprite2D = source.get_node_or_null("Sprite2D")
	if not sprite or not sprite.texture: return
	var signature: String = str(sprite.texture.get_instance_id()) + ":" + str(sprite.frame) + ":" + direction
	if signature == last_frame: return
	before_visual_update.emit()
	last_frame = signature
	var frame_size := Vector2(sprite.texture.get_width() / float(sprite.hframes), sprite.texture.get_height() / float(sprite.vframes))
	material.albedo_texture = sprite.texture
	material.uv1_scale = Vector3(1.0 / sprite.hframes, 1.0 / sprite.vframes, 1)
	material.uv1_offset = Vector3(float(sprite.frame_coords.x) / sprite.hframes, float(sprite.frame_coords.y) / sprite.vframes, 0)
	var size_value: Vector2 = frame_size / PIXELS_PER_UNIT
	var foot: Vector2i = source.footprint if source is IsoObject else Vector2i.ONE
	if ground_tile:
		mesh.mesh.size = Vector2(foot.x, foot.y)
		mesh.rotation_degrees.x = -90
		mesh.position.y = 0.015
		var tile_material := ShaderMaterial.new()
		tile_material.shader = preload("res://scripts/builder/sprite_ground.gdshader")
		tile_material.set_shader_parameter("sprite_texture", sprite.texture)
		tile_material.set_shader_parameter("frame_region", Vector4(float(sprite.frame_coords.x) / sprite.hframes, float(sprite.frame_coords.y) / sprite.vframes, 1.0 / sprite.hframes, 1.0 / sprite.vframes))
		tile_material.set_shader_parameter("turns", preload("res://scripts/iso_tile_rotation.gd").quarter_turns(direction))
		tile_material.set_shader_parameter("angle_radians", deg_to_rad(preload("res://scripts/iso_tile_rotation.gd").degrees(direction)))
		tile_material.set_shader_parameter("diamond_ground", diamond_ground)
		if source is IsoObject:
			var views: Dictionary = source.directions_data
			var view: Dictionary = views.get(direction, views.get("SE", views.values()[0]))
			var base: Array = view.get("alignment_base", [])
			if base.size() == 3:
				var back := Vector2(base[0][0] + base[2][0] - base[1][0], base[0][1] + base[2][1] - base[1][1])
				tile_material.set_shader_parameter("calibrated_source", true)
				tile_material.set_shader_parameter("source_back", back / frame_size)
				tile_material.set_shader_parameter("source_u", (Vector2(base[2][0], base[2][1]) - back) / frame_size)
				tile_material.set_shader_parameter("source_v", (Vector2(base[0][0], base[0][1]) - back) / frame_size)
		mesh.material_override = tile_material
		visual_bounds = AABB(Vector3(-foot.x * 0.5, 0, -foot.y * 0.5), Vector3(foot.x, 0.03, foot.y))
	else:
		var prepared: Dictionary = preload("res://scripts/builder/sprite_projection.gd").frame(sprite)
		var picture_rect: Rect2 = prepared["rect"]
		card_rect = picture_rect
		material.albedo_texture = prepared["texture"]
		material.uv1_scale = Vector3.ONE
		material.uv1_offset = Vector3.ZERO
		size_value = picture_rect.size / PIXELS_PER_UNIT
		mesh.mesh.size = size_value
		var contact := Vector2.ZERO
		if source is IsoObject:
			var views: Dictionary = source.directions_data
			var view: Dictionary = views.get(direction, views.get("SE", views.values()[0])) if not views.is_empty() else {}
			var raw: Array = view.get("render_contact",view.get("grid_contact", []))
			if raw.size() == 2: contact = sprite.transform * (Vector2(raw[0], raw[1]) - source.origin_offset)
		mesh.position = Vector3((picture_rect.get_center().x - contact.x) / PIXELS_PER_UNIT, (contact.y - picture_rect.get_center().y) / PIXELS_PER_UNIT, 0)
		var width: float = maxf(size_value.x, maxf(foot.x, foot.y))
		visual_bounds = AABB(Vector3(-foot.x * 0.5, 0, -foot.y * 0.5), Vector3(foot.x, maxf(0.1, mesh.position.y + size_value.y * 0.5), foot.y))
	var height: float = float(walk_profile.get("height", visual_bounds.size.y))
	if walk_profile.get("shape", "box") == "cylinder":
		if not collision.shape is CylinderShape3D: collision.shape = CylinderShape3D.new()
		collision.shape.radius = maxf(0.04, minf(foot.x, foot.y) * float(walk_profile.get("radius", 0.22)))
		collision.shape.height = height
	else:
		if not collision.shape is BoxShape3D: collision.shape = BoxShape3D.new()
		collision.shape.size = Vector3(maxf(0.08, foot.x * float(walk_profile.get("width", 1))), height, maxf(0.08, foot.y * float(walk_profile.get("depth", 1))))
	collision.position.y = height * 0.5
	visual_updated.emit()

func mixed_bounds() -> AABB:
	return visual_bounds

func set_angles(value: Vector3) -> void:
	free_angles = value
	rotation_degrees = value
	if not ground_tile and material:
		var free_rotation: bool = not value.is_zero_approx()
		material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED if free_rotation else BaseMaterial3D.BILLBOARD_FIXED_Y
		if free_rotation: rotation_degrees.y += 45

func set_door_open(opened: bool) -> void:
	if source is IsoObject:
		source.playing = false
		source.get_node("Sprite2D").frame = mini(2, source.total_frames - 1) if opened else 0
		update_visual()
