extends RefCounted

const Anchors = preload("res://scripts/builder/entrance_anchors.gd")
const Grid = preload("res://scripts/builder/grid_fit.gd")
const SpriteView = preload("res://scripts/sprite_view.gd")
const DISTANCE = 6.4
const STANCE = 7.65
const SPEED = 8.8
const GRAVITY = 10.0
const RADIUS = .18
const START = Vector3(0, RADIUS, DISTANCE)

var frame: Dictionary = {}
var ball: Node
var guide: Node
var position := START
var velocity := Vector3.ZERO
var flying: bool = false

static func sprite_point(node: Node2D, pixel: Vector2) -> Vector2:
	var sprite: Sprite2D = node.get_node("Sprite2D")
	return sprite.to_global(pixel + sprite.offset)

static func frame_for(candidate: Dictionary, walk: Node) -> Dictionary:
	var item: Dictionary = candidate["item"]
	var profile: Dictionary = candidate["profile"]
	var node: Node = candidate["node"]
	if profile.has("posts"):
		var posts: Array = profile["posts"].get(item["direction"], [])
		if posts.size() != 2: return {}
		var a: Vector2 = sprite_point(node, Vector2(posts[0][0], posts[0][1]))
		var b: Vector2 = sprite_point(node, Vector2(posts[1][0], posts[1][1]))
		var screen: Vector2 = b-a
		var across := Vector2(screen.x/32 + screen.y/16, -screen.x/32 + screen.y/16)
		var width: float = across.length()
		if width < .5: return {}
		var depth: Vector2 = across.normalized().orthogonal()
		if Grid.pixels(depth).y < 0: depth = -depth
		return {"origin": a.lerp(b,.5), "right": screen/width, "front": Grid.pixels(depth),
			"up": Vector2(0,-8), "half": width*.5, "height": 1.65}
	var center := Vector3(0,0,profile["front"])
	var origin: Variant = source_point(node,item,walk,center)
	var right: Variant = source_point(node,item,walk,center+Vector3.RIGHT)-origin
	var front: Variant = source_point(node,item,walk,center+Vector3.BACK)-origin
	var up: Variant = source_point(node,item,walk,center+Vector3.UP)-origin
	# Width in world metres. The mixed projection uses the same physical scale
	# as the model; each basis vector carries the projection, not the scale.
	var size: float = float(item["scale"])
	return {"origin":origin, "right":right/size, "front":front/size, "up":up/size,
		"half":float(profile["mouth"][0])*size, "height":float(profile["mouth"][1])*size}

static func source_point(node: Node, item: Dictionary, walk: Node, point: Vector3) -> Variant:
	var projected: Variant = Anchors.source_position(node, item, walk.dimension, walk.library, point)
	return node.get_parent().to_global(projected)

static func world_point(basis: Dictionary, point: Vector3) -> Variant:
	return basis["origin"] + basis["right"]*point.x + basis["up"]*point.y + basis["front"]*point.z

static func scores(basis: Dictionary, crossing: Vector3) -> bool:
	return absf(crossing.x) <= float(basis["half"])-RADIUS and crossing.y >= RADIUS*.8 \
		and crossing.y <= float(basis["height"])-RADIUS

static func ball_texture(library: RefCounted, asset: String) -> Texture2D:
	if not library.assets.has(asset): return null
	var directions: Dictionary = library.assets[asset]["data"].get("directions",{})
	if directions.is_empty(): return null
	var texture: Texture2D = SpriteView.texture(directions.get("SE",directions.values()[0]))
	if texture == null: return null
	var image: Image = texture.get_image()
	if image == null or image.is_empty(): return null
	var rect: Rect2i = image.get_used_rect()
	return ImageTexture.create_from_image(image.get_region(rect)) if rect.has_area() else null

func build(basis: Dictionary, walk: Node, texture: Texture2D) -> void:
	frame = basis
	position = START
	velocity = Vector3.ZERO
	flying = false
	if walk.dimension == "2d":
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.scale = Vector2.ONE*6.5/float(texture.get_width())
		sprite.z_index = 15
		ball = sprite
		var line := Line2D.new()
		line.width = 1.5
		line.default_color = Color("a0f3e1")
		line.z_index = 14
		guide = line
	else:
		var sprite := Sprite3D.new()
		sprite.texture = texture
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.pixel_size = .36/float(texture.get_width())
		ball = sprite
		var line := MeshInstance3D.new()
		line.mesh = ImmediateMesh.new()
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color("a0f3e1")
		line.material_override = material
		guide = line
	var parent: Node = walk.player.get_parent()
	parent.add_child(guide)
	parent.add_child(ball)
	present(0)

func present(aim: float) -> void:
	if not is_instance_valid(ball): return
	ball.global_position = world_point(frame,position)
	guide.visible = not flying
	if flying: return
	var start: Variant = world_point(frame,Vector3(0,.04,DISTANCE-.35))
	var end: Variant = world_point(frame,Vector3(aim,.04,.22))
	if guide is Line2D:
		guide.points = PackedVector2Array([guide.to_local(start),guide.to_local(end)])
	else:
		var line: ImmediateMesh = guide.mesh
		line.clear_surfaces()
		line.surface_begin(Mesh.PRIMITIVE_LINES)
		line.surface_add_vertex(guide.to_local(start))
		line.surface_add_vertex(guide.to_local(end))
		line.surface_end()

func kick(aim: float) -> void:
	position = START
	velocity = Vector3(aim*SPEED/DISTANCE,4.25,-SPEED)
	flying = true
	present(aim)

func advance(delta: float, walk: Node, goal: Node, spectators: Array) -> String:
	var previous: Vector3 = position
	position += velocity*delta-Vector3.UP*(.5*GRAVITY*delta*delta)
	velocity.y -= GRAVITY*delta
	var ends: bool = position.z <= 0
	if ends: position = previous.lerp(position,previous.z/(previous.z-position.z))
	var result: String = "flight"
	if blocked(walk,goal,previous,position,spectators): result = "blocked"
	elif ends: result = "goal" if scores(frame,position) else "out"
	elif absf(position.x) > float(frame["half"])+2.0 or position.y < 0: result = "out"
	if result != "flight": flying = false
	if is_instance_valid(ball): ball.global_position = world_point(frame,position)
	return result

func blocked(walk: Node, goal: Node, from: Vector3, to: Vector3, spectators: Array) -> bool:
	var player: Node = walk.player
	var exclude: Array[RID] = [player.get_rid()]
	var class_name_text: String = "CollisionObject2D" if walk.dimension == "2d" else "CollisionObject3D"
	for collider in [goal]+goal.find_children("*",class_name_text,true,false):
		if collider is CollisionObject2D or collider is CollisionObject3D: exclude.append(collider.get_rid())
	if walk.dimension == "2d":
		var a: Vector2 = world_point(frame,Vector3(from.x,0,from.z))
		var b: Vector2 = world_point(frame,Vector3(to.x,0,to.z))
		var ray := PhysicsRayQueryParameters2D.create(a,b,1,exclude)
		ray.hit_from_inside = true
		if not player.get_world_2d().direct_space_state.intersect_ray(ray).is_empty(): return true
		var metric_a := Vector2(a.x/16,a.y/8)
		var metric_b := Vector2(b.x/16,b.y/8)
		for actor in spectators:
			var p: Vector2 = actor.global_position
			var metric := Vector2(p.x/16,p.y/8)
			if metric.distance_to(Geometry2D.get_closest_point_to_segment(metric,metric_a,metric_b)) <= .48: return true
	else:
		var a: Vector3 = world_point(frame,from)
		var b: Vector3 = world_point(frame,to)
		var ray := PhysicsRayQueryParameters3D.create(a,b,3,exclude)
		ray.hit_from_inside = true
		if not player.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): return true
		for actor in spectators:
			var p: Vector3 = actor.global_position
			var at: Vector3 = Geometry3D.get_closest_point_to_segment(p+Vector3.UP*.65,a,b)
			if at.y >= p.y and at.y <= p.y+1.65 and Vector2(at.x-p.x,at.z-p.z).length() <= .44: return true
	return false

func reset_ball(aim: float) -> void:
	position = START
	velocity = Vector3.ZERO
	flying = false
	present(aim)

func release() -> void:
	if is_instance_valid(guide): guide.free()
	if is_instance_valid(ball): ball.free()
	guide = null
	ball = null
	frame.clear()
