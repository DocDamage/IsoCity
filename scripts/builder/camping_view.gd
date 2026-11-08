extends RefCounted

const Motion = preload("res://scripts/builder/fitness_motion.gd")
const Props = preload("res://scripts/builder/prop_plan.gd")
const Ash = Color("685950")
const Stone = Color("8f8b84")

var flames: Dictionary = {}
var labels: Dictionary = {}
var poses: Dictionary = {}
var effects = preload("res://scripts/builder/prop_effects.gd").new()
var crackle: AudioStreamWAV

func audio() -> AudioStreamWAV:
	if crackle: return crackle
	var random := RandomNumberGenerator.new()
	random.seed = 411022
	var samples := PackedByteArray()
	var envelope: float = 0
	const COUNT = 22050
	samples.resize(COUNT)
	for index in COUNT:
		if random.randf() < .002: envelope = random.randf_range(12,42)
		var end_fade: float = minf(1.0,minf(index,COUNT-index-1)/400.0)
		samples[index] = clampi(roundi(random.randf_range(-1,1)*envelope*end_fade),-127,127) & 255
		envelope *= .982
	crackle = AudioStreamWAV.new()
	crackle.format = AudioStreamWAV.FORMAT_8_BITS
	crackle.mix_rate = 14700
	crackle.loop_mode = AudioStreamWAV.LOOP_FORWARD
	crackle.loop_end = COUNT
	crackle.data = samples
	return crackle

func bed(node: Node, mode: String) -> Node:
	if mode == "2d":
		var top := Node2D.new()
		top.position = Vector2(0,7)
		node.add_child(top)
		for index in 8:
			var theta: float = index*TAU/8
			var stone := Polygon2D.new()
			stone.color = Stone
			stone.position = Vector2(cos(theta)*8,sin(theta)*4)
			stone.polygon = PackedVector2Array([Vector2(-1.5,-1),Vector2(1.5,-1),Vector2(1.8,.6),Vector2(-1,1.5)])
			top.add_child(stone)
		for angle in [-.35,.35]:
			var log := Line2D.new()
			log.default_color = Ash
			log.width = 3
			log.points = PackedVector2Array([Vector2(-5,0),Vector2(5,0)])
			log.rotation = angle
			top.add_child(log)
		return top
	var top := Node3D.new()
	node.add_child(top)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Stone
	var stone := CylinderMesh.new()
	stone.top_radius = .09
	stone.bottom_radius = .11
	stone.height = .10
	stone.radial_segments = 6
	for index in 8:
		var theta: float = index*TAU/8
		var visual := MeshInstance3D.new()
		visual.mesh = stone
		visual.material_override = mat
		visual.position = Vector3(cos(theta)*.41,.05,sin(theta)*.41)
		top.add_child(visual)
	var log := BoxMesh.new()
	log.size = Vector3(.55,.095,.12)
	var coal := StandardMaterial3D.new()
	coal.albedo_color = Ash
	for angle in [-.42,.42]:
		var visual := MeshInstance3D.new()
		visual.mesh = log
		visual.material_override = coal
		visual.rotation.y = angle
		visual.position.y = .06
		top.add_child(visual)
	return top

func fire(key: String, candidate: Dictionary, walk: Node, lit: bool, audible: bool) -> void:
	var node: Node = candidate["node"]
	if flames.has(key) and flames[key]["node"].get_ref() != node: remove_fire(key)
	if not flames.has(key):
		var art: Node = node.get_node_or_null("Sprite2D") if walk.dimension == "2d" else node.mesh
		if not is_instance_valid(art): return
		flames[key] = {"node":weakref(node),"art":weakref(art),"visible":art.visible,
			"bed":bed(node,walk.dimension),"sound":null}
	var value: Dictionary = flames[key]
	var art: Node = value["art"].get_ref()
	if is_instance_valid(art): art.visible = lit and value["visible"]
	if is_instance_valid(value["bed"]): value["bed"].visible = not lit
	if lit:
		var profile: Dictionary = Props.definitions()["kinds"]["appliance"].duplicate()
		profile["kind"] = "appliance"
		profile["effect"] = "light"
		candidate["profile"] = profile
		effects.apply(key,candidate,walk,true,"Campfire")
	else:
		effects.release(key)
	if lit and audible and not is_instance_valid(value["sound"]):
		var sound: Node = AudioStreamPlayer2D.new() if walk.dimension == "2d" else AudioStreamPlayer3D.new()
		sound.name = "CampfireSound"
		sound.stream = audio()
		sound.volume_db = -24
		sound.max_distance = 260.0 if walk.dimension == "2d" else 16.0
		node.add_child(sound)
		sound.play()
		value["sound"] = sound
	if not lit or not audible: stop_sound(value)

func stop_sound(value: Dictionary) -> void:
	var sound: Node = value["sound"]
	if is_instance_valid(sound):
		sound.stop()
		sound.free()
	value["sound"] = null

func remove_fire(key: String) -> void:
	if not flames.has(key): return
	var value: Dictionary = flames[key]
	stop_sound(value)
	var art: Node = value["art"].get_ref()
	if is_instance_valid(art): art.visible = value["visible"]
	if is_instance_valid(value["bed"]): value["bed"].free()
	effects.release(key)
	flames.erase(key)

func marker(key: String, node: Node, mode: String, text: String) -> void:
	if is_instance_valid(labels.get(key)) and labels[key].get_parent() != node: remove_marker(key)
	if not is_instance_valid(labels.get(key)):
		var label: Node
		if mode == "2d":
			label = Label.new()
			label.z_index = 100
			label.position = Vector2(-24,-58)/node.scale
			label.add_theme_font_size_override("font_size",14)
			label.add_theme_color_override("font_outline_color",Color.BLACK)
			label.add_theme_constant_override("outline_size",4)
		else:
			label = Label3D.new()
			label.position.y = 3.5
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.font_size = 32
			label.pixel_size = .012
			label.outline_size = 8
			label.no_depth_test = true
		node.add_child(label)
		labels[key] = label
	labels[key].text = text

func remove_marker(key: String) -> void:
	if is_instance_valid(labels.get(key)): labels[key].free()
	labels.erase(key)

func rest(id: String, actor: Node) -> String:
	if poses.has(id): return poses[id]["label"]
	var saved: Dictionary = {"actor":weakref(actor),"physics":actor.is_physics_processing()}
	actor.set_physics_process(false)
	actor.velocity = Vector2.ZERO if actor is Node2D else Vector3.ZERO
	if actor is IsoCharacter:
		saved["action"] = actor.action
		if actor.authored_animation and actor.authored_animation.actions.has("sleep") and Motion.support(actor,"sleep")["reason"].is_empty():
			actor.action = "sleep"
			saved["label"] = "Sleeping"
		else:
			actor.action = "sit" if Motion.support(actor,"sit")["reason"].is_empty() else "idle"
			saved["label"] = "Quiet rest · no sleeping pose"
	else:
		saved["transform"] = actor.body.transform
		actor.body.rotation = Vector3(PI*.5,0,0)
		actor.body.position.y = .35
		saved["label"] = "Sleeping"
	poses[id] = saved
	return saved["label"]

func wake(id: String) -> void:
	if not poses.has(id): return
	var saved: Dictionary = poses[id]
	var actor: Node = saved["actor"].get_ref()
	if is_instance_valid(actor):
		if actor is IsoCharacter: actor.action = saved["action"]
		else: actor.body.transform = saved["transform"]
		actor.set_physics_process(saved["physics"])
	poses.erase(id)

func clear_views() -> void:
	for key in flames.keys(): remove_fire(key)
	for key in labels.keys(): remove_marker(key)

func reset() -> void:
	clear_views()
	for id in poses.keys(): wake(id)
	crackle = null
