extends RefCounted

const Motion = preload("res://scripts/builder/fitness_motion.gd")

var saved: Dictionary = {}
var phase: float = 0
var foreground: Sprite2D

static func support(rider: Node, profile: Dictionary) -> String:
	if rider is Node3D:
		return Motion.support(rider,"sit")["reason"]
	if not rider is IsoCharacter or rider.is_pet or not is_instance_valid(rider.sprite) or not rider.sprite.texture:
		return "This character needs a supported riding pose."
	if profile["pose"] == "sit":
		var issue: String = Motion.support(rider,"sit")["reason"]
		if not issue.is_empty(): return issue
		if not rider.authored_animation and rider.sprite.hframes < 7: return "This character has no seated riding frame."
	return ""

func capture(rider: Node) -> void:
	phase = 0
	if rider is IsoCharacter:
		saved = {"action":rider.action,"direction":rider.direction,"offset":rider.interaction_visual_offset,"z":rider.z_index}
	else:
		saved = {"body":rider.body.transform,"limbs":rider.limbs.map(func(limb: Node3D)->Transform3D: return limb.transform)}

func release(rider: Node) -> void:
	if is_instance_valid(foreground): foreground.free()
	foreground = null
	if saved.is_empty() or not is_instance_valid(rider):
		saved.clear()
		return
	if rider is IsoCharacter:
		rider.direction = saved["direction"]
		rider.action = saved["action"]
		rider.interaction_visual_offset = saved["offset"]
		rider.z_index = saved["z"]
		rider._update_frame()
	else:
		rider.body.transform = saved["body"]
		for index in rider.limbs.size(): rider.limbs[index].transform = saved["limbs"][index]
	saved.clear()

func position(values: Array) -> Vector3:
	return Vector3(values[0],values[1],values[2])

func heading(direction: Vector2) -> String:
	var pixel := Vector2(direction.x-direction.y,direction.x+direction.y)
	return ("NE" if pixel.y < 0 else "SE") if pixel.x >= 0 else ("NW" if pixel.y < 0 else "SW")

func pixel_seat(node: Node, profile: Dictionary, direction: String) -> Vector2:
	if profile.has("pixel"):
		var point: Array = profile["pixel"][direction]
		var sprite: Sprite2D = node.get_node("Sprite2D")
		return sprite.to_global(Vector2(point[0],point[1])+sprite.offset)
	var model_point: Vector3 = node.model.transform * position(profile["seat"])
	var local: Vector3 = node.camera.basis.inverse() * model_point
	return node.to_global(Vector2(local.x,-local.y)*node.PIXELS_PER_UNIT+node.terrain_visual_offset)

func show_scooter_front(node: Node2D, span: Array) -> void:
	var sprite: Sprite2D = node.get_node("Sprite2D")
	if not is_instance_valid(foreground):
		foreground = Sprite2D.new()
		foreground.name = "ScooterFront"
		foreground.centered = false
		foreground.region_enabled = true
		foreground.z_as_relative = false
		node.add_child(foreground)
	foreground.z_index = node.z_index+2
	foreground.transform = sprite.transform
	foreground.texture = sprite.texture
	foreground.offset = sprite.offset+Vector2(span[0],0)
	foreground.region_rect = Rect2(span[0],0,span[1],sprite.texture.get_height())

func apply(rider: Node, cycle: Dictionary, forward: Vector2, direction: String, delta: float, speed: float) -> void:
	var node: Node = cycle["node"]
	var profile: Dictionary = cycle["profile"]
	phase = fposmod(phase+delta*absf(speed)*4,TAU)
	if rider is IsoCharacter:
		rider.direction = heading(forward)
		rider.action = profile["pose"]
		rider.z_index = node.z_index+1
		var seat: Vector2 = pixel_seat(node,profile,direction)
		var foot: Vector2 = seat+Vector2(0,5.5) if profile["pose"] == "sit" else seat
		rider.interaction_visual_offset = rider.sprite.global_transform.affine_inverse().basis_xform(foot-rider.global_position)-rider.terrain_visual_offset
		rider._update_frame()
		if profile.has("foreground"): show_scooter_front(node,profile["foreground"][direction])
		return
	var seat: Vector3 = node.to_global(position(profile["seat"]))
	var hands: Vector3 = node.to_global(position(profile["hands"]))
	var feet: Vector3 = node.to_global(position(profile["feet"]))
	var right: Vector3 = node.global_basis.x.normalized()
	var axis: Vector3 = node.global_basis.z.normalized()
	rider.body.global_position = seat-Vector3.UP*.85 if profile["pose"] == "sit" else feet
	rider.body.global_rotation.y = atan2(-axis.x,-axis.z)
	rider.body.rotation.x = -.09
	var pedal: Vector3 = (Vector3.UP*sin(phase)+axis*cos(phase))*.12 if profile["pose"] == "sit" else axis*.12
	Motion.limb_to(rider,0,hands-right*.23,.53)
	Motion.limb_to(rider,1,hands+right*.23,.53)
	Motion.limb_to(rider,2,feet-right*.14+pedal,.69)
	Motion.limb_to(rider,3,feet+right*.14-pedal,.69)
