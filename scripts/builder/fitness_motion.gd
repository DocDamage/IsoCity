extends RefCounted

const Anim = preload("res://scripts/character_animation.gd")
const SpriteView = preload("res://scripts/sprite_view.gd")
const Colors = Color("8be2cf")

var saved: Dictionary = {}
var line: Node

static func support(player: Node, action: String) -> Dictionary:
	if player is Node3D:
		return {"reason":""} if is_instance_valid(player.body) and player.limbs.size() == 4 \
			else {"reason":"This character has no compatible exercise rig."}
	if not player is IsoCharacter or player.is_pet:
		return {"reason":"This character has no compatible exercise pose."}
	if not player.authored_animation:
		return {"reason":"", "note":"Walk frames on the moving belt." if action == "run" else "Seated pose with equipment motion."}
	var animator: RefCounted = player.authored_animation
	var resolved: Dictionary = Anim.resolve_pose(animator.clips,animator.actions,action)
	var clip: Dictionary = animator.clips.get(resolved["clip"],{})
	if not resolved["available"] or resolved["clip"] == animator.actions.get("idle",{}).get("clip","idle"):
		return {"reason":"No supported %s pose for this character." % action}
	var views: Dictionary = clip.get("directions",{})
	if views.is_empty() or views.values().any(func(view: Dictionary) -> bool:
		return SpriteView.texture(view) == null or (action == "run" and int(view.get("frames",1)) < 2)):
		return {"reason":"The %s frames needed for this station are unavailable." % action}
	return {"reason":"", "note":resolved["reason"]}

func hold(player: Node, approach: Variant, equipment: bool) -> void:
	saved = {"physics":player.is_physics_processing(), "position":player.global_position}
	if player is IsoCharacter:
		saved.merge({"action":player.action, "direction":player.direction, "offset":player.interaction_visual_offset})
	else:
		saved["body"] = player.body.transform
		saved["limbs"] = player.limbs.map(func(limb: Node3D) -> Transform3D: return limb.transform)
	player.set_physics_process(false)
	player.teleport_to(player.get_parent().to_local(approach))
	if not equipment: return
	if player is Node2D:
		var overlay := Line2D.new()
		overlay.z_index = 9
		overlay.width = 1.7
		overlay.default_color = Colors
		line = overlay
	else:
		var overlay := MeshInstance3D.new()
		overlay.mesh = ImmediateMesh.new()
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Colors
		overlay.material_override = material
		line = overlay
	player.get_parent().add_child(line)

func release(player: Node) -> void:
	if is_instance_valid(line): line.free()
	line = null
	if saved.is_empty(): return
	if is_instance_valid(player):
		player.set_physics_process(saved["physics"])
		if player is IsoCharacter:
			player.interaction_visual_offset = saved["offset"]
			player.action = saved["action"]
			player.direction = saved["direction"]
		else:
			player.body.transform = saved["body"]
			for index in player.limbs.size(): player.limbs[index].transform = saved["limbs"][index]
	saved.clear()

static func pixel(value: Array) -> Vector2:
	return Vector2(value[0],value[1])

static func contact(node: Node, point: Vector2) -> Variant:
	var source: Node = node.source if node is Node3D else node
	var sprite: Sprite2D = source.get_node("Sprite2D")
	if node is Node2D: return sprite.to_global(point + sprite.offset)
	var in_card: Vector2 = sprite.transform * (point - source.origin_offset)
	var from_center: Vector2 = (in_card-node.card_rect.get_center())/node.PIXELS_PER_UNIT
	var card: Node3D = node.mesh
	var camera: Camera3D = node.get_viewport().get_camera_3d()
	var right: Vector3 = camera.global_basis.x.normalized() if camera else Vector3.RIGHT
	var scale: Vector3 = card.global_basis.get_scale()
	return card.global_position+right*from_center.x*scale.x-Vector3.UP*from_center.y*scale.y

func pose(player: Node, station: Dictionary, definition: Dictionary, elapsed: float, delta: float) -> void:
	var node: Node = station["node"]
	var view: Array = station["profile"]["views"][station["item"]["direction"]]
	var seat: Vector2 = pixel(view[0])
	var handle: Vector2 = pixel(view[1])
	var rest: Vector2 = pixel(view[2])
	var cycle: float = elapsed*definition["rate"]*TAU
	var first: Vector2 = rest
	var second: Vector2 = rest
	var kind: String = station["setting"]["kind"]
	match kind:
		"cycle":
			var crank := Vector2(3.5*cos(cycle),4.5*sin(cycle))
			first += crank
			second -= crank
			seat.y -= .7*(1.0-cos(cycle*2))
		"row":
			var travel: float = (1-cos(cycle))*.5
			var rail: Vector2 = (seat-rest).normalized()
			seat += rail*lerpf(-4,7,travel)
			first = handle
			second = handle.lerp(seat,.15+.48*travel)+Vector2(0,-2)
		"treadmill":
			seat.y -= 1.5*absf(sin(cycle))
			var stride: Vector2 = (handle-rest).normalized()
			first += stride*(4+4*sin(cycle))
			second = first - stride*6
	var anchor: Variant = contact(node,seat)
	var reach: Variant = contact(node,handle if kind != "row" else second)
	var foot_a: Variant = contact(node,first if kind == "cycle" else rest)
	var foot_b: Variant = contact(node,second if kind == "cycle" else rest)
	if player is IsoCharacter:
		player.direction = str(view[3])
		player.action = definition["action"]
		var sprite: Sprite2D = player.get_node("Sprite2D")
		var feet: Vector2 = anchor if kind == "treadmill" else anchor+Vector2(0,6.8)
		player.interaction_visual_offset = sprite.global_transform.affine_inverse().basis_xform(feet-player.global_position)-player.terrain_visual_offset
		player._update_animation(delta)
	else:
		var hip: float = 0.0 if kind == "treadmill" else .85
		player.body.global_position = anchor-Vector3.UP*hip
		face(player,reach-anchor,str(view[3]))
		if kind == "treadmill":
			for index in player.limbs.size():
				player.limbs[index].rotation.x = sin(cycle + (PI if index in [1,2] else 0))* (.65 if index >= 2 else .48)
		else:
			var lateral: Vector3 = player.body.global_basis.x.normalized()
			limb_to(player,0,reach-lateral*.13,.53)
			limb_to(player,1,reach+lateral*.13,.53)
			limb_to(player,2,foot_a-lateral*.1,.69)
			limb_to(player,3,foot_b+lateral*.1,.69)
	draw_motion(contact(node,first),contact(node,second))

static func face(player: Node3D, direction: Vector3, view: String = "NE") -> void:
	var camera: Camera3D = player.get_viewport().get_camera_3d()
	if camera and absf(direction.dot(camera.global_basis.x)) < .05:
		direction = camera.global_basis.z * (-1.0 if view in ["NE","NW"] else 1.0)
	if Vector2(direction.x,direction.z).length() > .01:
		player.body.global_rotation.y = atan2(-direction.x,-direction.z)

static func limb_to(player: Node3D, index: int, point: Vector3, natural: float) -> void:
	var limb: Node3D = player.limbs[index]
	var aim: Vector3 = player.body.to_local(point)-limb.position
	var length: float = aim.length()
	if length < .02: return
	limb.basis = Basis(Quaternion(Vector3.DOWN,aim/length)).scaled_local(Vector3(1,clampf(length/natural,.38,1.35),1))

func draw_motion(a: Variant,b: Variant) -> void:
	if line is Line2D:
		line.points = PackedVector2Array([line.to_local(a),line.to_local(b)])
	elif line is MeshInstance3D:
		var mesh: ImmediateMesh = line.mesh
		mesh.clear_surfaces()
		mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		mesh.surface_add_vertex(line.to_local(a))
		mesh.surface_add_vertex(line.to_local(b))
		mesh.surface_end()

func kick_pose(player: Node, goal: Variant, progress: float, delta: float) -> void:
	if player is IsoCharacter:
		var gap: Vector2 = goal-player.global_position
		player.direction = ("NE" if gap.y < 0 else "SE") if gap.x >= 0 else ("NW" if gap.y < 0 else "SW")
		player.action = "walk" if progress > 0 else "idle"
		player._update_animation(delta)
	elif player is Node3D:
		var direction: Vector3 = goal-player.global_position
		if Vector2(direction.x,direction.z).length() > .01: player.body.global_rotation.y = atan2(-direction.x,-direction.z)
		player.limbs[3].rotation.x = -sin(PI*progress)*1.05
		player.limbs[0].rotation.x = sin(PI*progress)*.55
