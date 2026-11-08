extends RefCounted

const Plan = preload("res://scripts/builder/pet_plan.gd")
var body: Node
var source: IsoCharacter
var card: Node
var timer: float = 0
var action: String = ""
var missing: bool = false
var dimension: String = ""

func create(asset: Dictionary, parent: Node, mode: String) -> Node:
	dimension = mode
	if mode == "2d":
		body = load(asset["path"]).instantiate()
		source = body
	else:
		var walker := CharacterBody3D.new()
		var collider := CollisionShape3D.new()
		var shape := CapsuleShape3D.new()
		shape.radius = .17
		shape.height = .42
		collider.shape = shape
		collider.position.y = .23
		walker.add_child(collider)
		card = preload("res://scripts/builder/sprite_in_3d.gd").new()
		card.asset_path = asset["path"]
		card.collidable = false
		walker.add_child(card)
		body = walker
	body.name = "CompanionPet"
	body.collision_layer = 0
	body.collision_mask = 1
	parent.add_child(body)
	body.set_physics_process(false)
	if card:
		source = card.source
		card.set_process(false)
	source.set_physics_process(false)
	return body

func animate(pose: String, delta: float, movement: Vector2 = Vector2.ZERO) -> void:
	if not is_instance_valid(source): return
	if not movement.is_zero_approx():
		var angle: Vector2 = movement if dimension == "2d" else Vector2(movement.x-movement.y,movement.x+movement.y)
		var heading: String = ("NE" if angle.y < 0 else "SE") if angle.x >= 0 else ("NW" if angle.y < 0 else "SW")
		if card:
			if card.direction != heading: card.direction = heading
		elif source.direction != heading: source.direction = heading
	if action != pose:
		action = pose
		timer = 0
	timer += delta
	var clip: Dictionary = Plan.definitions()["actions"][pose]
	var frames: Array = clip["frames"]
	var sprite: Sprite2D = source.sprite
	missing = not is_instance_valid(sprite.texture) or frames.back() >= sprite.hframes
	if is_instance_valid(sprite.texture):
		sprite.frame = 0 if missing else frames[floori(timer/clip["interval"])%frames.size()]
	if card:
		card.update_visual()
		card.mesh.position.y = card.card_rect.size.y*.5/card.PIXELS_PER_UNIT
