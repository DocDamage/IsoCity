extends Node2D

const Budget = preload("res://scripts/builder/rendering_budget.gd")
const Bounds = preload("res://scripts/model_bounds.gd")
const PIXELS_PER_UNIT: float = 22.627417
@export var collidable: bool = true
@export var walk_collision: bool = false
@export var inherit_walk_profile: bool = true
@export var walk_step_height: float = 0.35
@export var walk_body_height: float = 1.8
var walk_shape: CollisionShape2D
var walk_scale: float = 1
var walk_key: String = ""
@export var asset_path: String = ""
@export var direction: String = "0":
	set(value):
		if direction == value: return
		direction = value
		if is_node_ready(): update_projection()
@export var night_mode: bool = false
@export var tilt := Vector2.ZERO
var footprint := Vector2i.ONE
var model: Node3D
var source_scene: PackedScene
var projection_pool: Node
var model_storage: Node3D
var projection: Dictionary = {}
var projection_key: String = ""
var projection_queued: bool = false
var projection_failed: bool = false
var static_source: bool = false
var photo_quality: bool = false
var photo_profile: Dictionary = {}
var viewport: SubViewport
var camera: Camera3D
var sprite: Sprite2D
var terrain_visual_offset:=Vector2.ZERO:
	set(value):
		terrain_visual_offset=value
		if is_instance_valid(sprite): sprite.offset=value
var collision: CollisionPolygon2D

func set_projection_pool(value: Node) -> void:
	projection_pool = value
	if is_node_ready():
		check_static_source()
		update_projection()

func set_photo_projection(enabled: bool, profile: Dictionary) -> void:
	var detail: Dictionary = profile if enabled else {}
	if photo_quality == enabled and photo_profile == detail: return
	photo_quality = enabled
	photo_profile = detail
	if is_node_ready(): update_projection()

func _ready() -> void:
	source_scene = load(asset_path)
	model = source_scene.instantiate()
	model_storage = Node3D.new()
	model_storage.hide()
	add_child(model_storage)
	sprite = Sprite2D.new()
	sprite.name = "Sprite2D"
	add_child(sprite)
	if projection_pool: check_static_source()
	if can_share():
		model_storage.add_child(model)
		for node in [model]+model.find_children("*","CollisionObject3D",true,false):
			if node is CollisionObject3D:
				node.collision_layer = 0
				node.collision_mask = 0
	else:
		viewport = create_view(self,model)
		camera = viewport.get_node("ProjectionCamera")
		sprite.texture = viewport.get_texture()
	var body := StaticBody2D.new()
	body.collision_layer = 1 if collidable else 0
	body.collision_mask = 0
	add_child(body)
	collision = CollisionPolygon2D.new()
	body.add_child(collision)
	set_notify_local_transform(true)
	update_projection()

func update_projection() -> void:
	model.rotation_degrees = Vector3(tilt.x, float(direction), tilt.y)
	var bounds: AABB = model.transform * Bounds.get_bounds(model)
	var base_bounds: AABB=model.transform * Bounds.contact_bounds(model) if model.has_meta("authored_footprint") else bounds
	footprint = Vector2i(maxi(1, ceili(snappedf(base_bounds.size.x,.0001))), maxi(1, ceili(snappedf(base_bounds.size.z,.0001))))
	# A 30-degree camera gives the same 2:1 diamond as the pixel world.
	var view_basis := Basis.from_euler(Vector3(deg_to_rad(-30), deg_to_rad(45), 0))
	var projected := Rect2()
	for index in 8:
		var point: Vector3 = view_basis.inverse() * bounds.get_endpoint(index)
		var pixel := Vector2(point.x, -point.y) * PIXELS_PER_UNIT
		projected = Rect2(pixel, Vector2.ZERO) if index == 0 else projected.expand(pixel)
	projected = projected.grow(12 if photo_quality else 4)
	var render_size := Vector2i(maxi(8, ceili(projected.size.x)), maxi(8, ceili(projected.size.y)))
	# Cap large source models while keeping their world size and origin.
	var edge_limit: float = 1536.0 if photo_quality else 1024.0
	var density: float = 2.0 if photo_quality else 1.0
	var render_scale: float = minf(density,edge_limit/maxf(render_size.x,render_size.y))
	sprite.scale = Vector2.ONE / render_scale
	sprite.position = projected.get_center()
	var center: Vector3 = view_basis * Vector3(projected.get_center().x / PIXELS_PER_UNIT, -projected.get_center().y / PIXELS_PER_UNIT, 0)
	var target := Vector2i(Vector2(render_size)*render_scale)
	projection = {
		"size":target,
		"position":center+view_basis*Vector3(0,0,maxf(100,bounds.size.length()*3)),
		"basis":view_basis, "far":maxf(1000,bounds.size.length()*10),
		"height":float(target.y)/(PIXELS_PER_UNIT*render_scale),
	}
	var points := PackedVector2Array()
	for p in [Vector3(base_bounds.position.x, 0, base_bounds.position.z), Vector3(base_bounds.end.x, 0, base_bounds.position.z), Vector3(base_bounds.end.x, 0, base_bounds.end.z), Vector3(base_bounds.position.x, 0, base_bounds.end.z)]:
		var v: Vector3 = view_basis.inverse() * p
		points.append(Vector2(v.x, -v.y) * PIXELS_PER_UNIT)
	collision.polygon = points
	rebuild_walk_collision()
	if not can_share():
		show_live()
	elif not projection_queued:
		projection_queued = true
		refresh_projection.call_deferred()

func check_static_source() -> void:
	static_source = Budget.static_visual(model)

func can_share() -> bool:
	return static_source and is_instance_valid(projection_pool) and not projection_failed and model.get_meta("paint_signature","") in ["","[]"]

func refresh_projection() -> void:
	projection_queued = false
	if not can_share():
		show_live()
		return
	var key: String = var_to_str([asset_path,source_scene.get_instance_id(),model.rotation_degrees,night_mode,
		projection["size"],photo_quality,photo_profile.get("full",{}).get("sha256","")])
	var texture: Texture2D = projection_pool.request(key,make_cached_view,self)
	if not texture:
		show_live()
		return
	projection_key = key
	sprite.texture = texture
	if is_instance_valid(viewport):
		model.reparent(model_storage,false)
		viewport.free()
		viewport = null
		camera = null

func finish_projection(key: String, texture: Texture2D) -> void:
	if key != projection_key: return
	if texture:
		sprite.texture = texture
	else:
		projection_failed = true
		show_live()

func make_cached_view(parent: Node) -> SubViewport:
	var subject: Node3D = Budget.make_detail(photo_profile) if photo_quality else null
	if not subject: subject = source_scene.instantiate()
	subject.rotation_degrees = model.rotation_degrees
	var view := create_view(parent,subject)
	place_camera(view,view.get_node("ProjectionCamera"))
	return view

func show_live() -> void:
	projection_key = ""
	if not is_instance_valid(viewport):
		viewport = create_view(self,model)
		camera = viewport.get_node("ProjectionCamera")
		sprite.texture = viewport.get_texture()
	place_camera(viewport,camera)

func create_view(parent: Node, subject: Node3D) -> SubViewport:
	var view := SubViewport.new()
	view.name = "ModelView"
	view.own_world_3d = true
	view.transparent_bg = true
	view.gui_disable_input = true
	view.msaa_3d = Viewport.MSAA_2X
	parent.add_child(view)
	if subject.get_parent(): subject.reparent(view,false)
	else: view.add_child(subject)
	for node in [subject] + subject.find_children("*", "CollisionObject3D", true, false):
		if node is CollisionObject3D:
			node.collision_layer = 0
			node.collision_mask = 0
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	view.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50,-30,0)
	light.light_energy = 0.8
	view.add_child(light)
	var viewpoint := Camera3D.new()
	viewpoint.name = "ProjectionCamera"
	viewpoint.projection = Camera3D.PROJECTION_ORTHOGONAL
	viewpoint.keep_aspect = Camera3D.KEEP_HEIGHT
	viewpoint.current = true
	view.add_child(viewpoint)
	return view

func place_camera(view: SubViewport, viewpoint: Camera3D) -> void:
	view.size = projection["size"]
	viewpoint.position = projection["position"]
	viewpoint.basis = projection["basis"]
	viewpoint.far = projection["far"]
	viewpoint.size = projection["height"]
	view.render_target_update_mode = SubViewport.UPDATE_ONCE

func projection_size() -> Vector2:
	return Vector2(viewport.size if is_instance_valid(viewport) else projection["size"])

func project_ray_origin(pixel: Vector2) -> Vector3:
	if is_instance_valid(camera): return camera.project_ray_origin(pixel)
	var size: Vector2 = projection_size()
	var offset: Vector2 = (pixel-size*.5)*float(projection["height"])/size.y
	return projection["position"]+projection["basis"]*Vector3(offset.x,-offset.y,-.05)

func project_ray_normal(pixel: Vector2) -> Vector3:
	if is_instance_valid(camera): return camera.project_ray_normal(pixel)
	return -projection["basis"].z

func unproject_position(point: Vector3) -> Vector2:
	if is_instance_valid(camera): return camera.unproject_position(point)
	var local: Vector3 = projection["basis"].inverse()*(point-projection["position"])
	var size: Vector2 = projection_size()
	return size*.5+Vector2(local.x,-local.y)*size.y/float(projection["height"])

func ground_polygon() -> PackedVector2Array:
	return collision.polygon if collision else PackedVector2Array()

func set_angles(value: Vector3) -> void:
	var next := Vector2(value.x, value.z)
	if tilt == next: return
	tilt = next
	if is_node_ready(): update_projection()

func _notification(what: int) -> void:
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED and is_node_ready() and not is_equal_approx(walk_scale, absf(scale.x)):
		rebuild_walk_collision()

func rebuild_walk_collision() -> void:
	if not walk_collision or not model or not collision: return
	walk_scale = maxf(0.01, absf(scale.x))
	var key: String = asset_path + str(model.rotation_degrees) + str(walk_scale)
	if key == walk_key: return
	walk_key = key
	var bounds: AABB = model.transform * Bounds.get_bounds(model)
	var geometry = preload("res://scripts/builder/walk_geometry.gd")
	if not geometry.sections.has(key):
		if geometry.sections.size() >= 256: geometry.sections.erase(geometry.sections.keys()[0])
		var basis_value := Basis.from_euler(Vector3(deg_to_rad(-30), deg_to_rad(45), 0))
		geometry.sections[key] = geometry.projected_segments(model, bounds.position.y + walk_step_height / walk_scale, bounds.position.y + walk_body_height / walk_scale, basis_value, PIXELS_PER_UNIT)
	if not walk_shape:
		walk_shape = CollisionShape2D.new()
		walk_shape.name = "WalkSection"
		collision.get_parent().add_child(walk_shape)
	var shape := ConcavePolygonShape2D.new()
	shape.segments = geometry.sections[key]
	walk_shape.shape = shape
	collision.disabled = true
	set_meta("walk_collision_kind", "height_band")

func configure_walk_collision(enabled: bool) -> void:
	walk_collision = enabled
	if walk_shape: walk_shape.disabled = not enabled
	if collision: collision.disabled = enabled
	if enabled: rebuild_walk_collision()
