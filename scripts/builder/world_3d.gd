extends Node3D

const Bounds = preload("res://scripts/model_bounds.gd")
const Player = preload("res://scripts/builder/player_3d.gd")
const Layers = preload("res://scripts/builder/layers.gd")
const Roads = preload("res://scripts/builder/roads.gd")
var library: RefCounted
var presentation: Node
var data_state: Dictionary = {}
var detail_view_active: bool=false
var editor_focus: Dictionary={}
var terrain_traversal: Node
var exploration: Node
var objects: Node3D
var camera: Camera3D
var sun: DirectionalLight3D
var player: CharacterBody3D
var instances: Dictionary = {}
var applied_records: Dictionary = {}
var last_apply_updates: int = 0
var last_apply_tile_updates: int = 0
var target := Vector3.ZERO
var yaw: float = 45.0
var pitch: float = 48.0
var distance: float = 38.0
var ghost: Node3D
var ghost_id: String = ""
var selection: MeshInstance3D
var walking: bool = false
var grid: MeshInstance3D
var road_node: Node3D
var road_signature: int = -1
var terrain: Node3D
var floor_surface: Node3D
var floor_stack: Node3D
var surface_snapping: bool = false
var placement_exclusions: Array[RID] = []
var surface_feedback: String = ""

func _ready() -> void:
	presentation = preload("res://scripts/builder/asset_presentation.gd").new()
	add_child(presentation)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("1c2b3b")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c6d7ed")
	environment.ambient_light_energy = 0.35
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment_node.environment = environment
	add_child(environment_node)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor_body := StaticBody3D.new()
	floor_body.name = "Foundation"
	floor_body.collision_layer = 2
	var floor_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(160, 0.4, 160)
	floor_mesh.mesh = box
	floor_mesh.position.y = -0.2
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("58695f")
	material.roughness = 1
	floor_mesh.material_override = material
	floor_body.add_child(floor_mesh)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	collision.shape = shape
	collision.position.y = -0.2
	floor_body.add_child(collision)
	add_child(floor_body)
	terrain=preload("res://scripts/builder/terrain_surface_3d.gd").new(); terrain.name="Terrain"; add_child(terrain)
	grid = MeshInstance3D.new()
	var grid_lines := ImmediateMesh.new()
	var grid_material := StandardMaterial3D.new()
	grid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	grid_material.albedo_color = Color(0.65, 0.8, 0.75, 0.06)
	grid_lines.surface_begin(Mesh.PRIMITIVE_LINES, grid_material)
	for index in range(-80, 81):
		grid_lines.surface_add_vertex(Vector3(index, 0.02, -80))
		grid_lines.surface_add_vertex(Vector3(index, 0.02, 80))
		grid_lines.surface_add_vertex(Vector3(-80, 0.02, index))
		grid_lines.surface_add_vertex(Vector3(80, 0.02, index))
	grid_lines.surface_end()
	grid.mesh = grid_lines
	grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(grid)
	objects = Node3D.new()
	objects.name = "Objects"
	add_child(objects)
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.current = true
	add_child(camera)
	player = CharacterBody3D.new()
	player.set_script(Player)
	player.name = "Player"
	player.collision_mask = 3
	player.position = Vector3(0, 0.1, 9)
	player.visible = false
	player.collision_layer = 0
	add_child(player)
	terrain_traversal=preload("res://scripts/builder/terrain_traversal.gd").new(); add_child(terrain_traversal)
	selection = MeshInstance3D.new()
	selection.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(selection)
	update_camera()

func apply(data: Dictionary) -> void:
	var changed_instances: Array[Node]=[]
	data_state = data
	last_apply_updates = 0
	last_apply_tile_updates = 0
	if not exploration:
		exploration = preload("res://scripts/builder/exploration.gd").new()
		exploration.dimension = "3d"
		exploration.library = library
		exploration.player = player
		add_child(exploration)
	exploration.reconcile_source(data)
	if exploration.interior==null:
		preload("res://scripts/builder/city_foundation.gd").configure(get_node("Foundation"),data)
		terrain.configure(data)
		var sculpted: bool=preload("res://scripts/builder/terrain_plan.gd").settings(data)["enabled"]
		var foundation_active: bool=not sculpted and floor_surface==null
		get_node("Foundation").visible=foundation_active; get_node("Foundation").collision_layer=2 if foundation_active else 0; grid.visible=foundation_active
	var signature: int = hash([data.get("roads", []),data.get("terrain",{}),data.get("terrain_vertices",[])])
	if signature != road_signature:
		road_node = Roads.update_3d(road_node,data)
		if road_node.get_parent()!=self: add_child(road_node)
		road_signature = signature
	if road_node:
		road_node.visible = Layers.shown(data, "Ground")
		Layers.collision_visibility(road_node, road_node.visible)
	var keep: Dictionary = {}
	for item in data["objects"]:
		var uid: String = item["uid"]
		keep[uid] = true
		var rendered: Dictionary = item.duplicate()
		rendered.erase("interior")
		var state: Dictionary = {"item": rendered, "night": data["night"], "visible": (Layers.shown(data, Layers.layer(item, library)) and item.get("visible", true))}
		if applied_records.has(uid) and applied_records[uid] == state: continue
		if instances.has(uid) and applied_records.get(uid, {}).get("item", {}).get("asset") != item["asset"]:
			instances[uid].free()
			instances.erase(uid)
		if not instances.has(uid):
			var instance: Node3D = preload("res://scripts/builder/asset_instance.gd").make(library, item["asset"], "3d")
			instance.set_meta("builder_uid", uid)
			objects.add_child(instance)
			instances[uid] = instance
			preload("res://scripts/builder/walk_geometry.gd").prepare(instance, item["asset"], library)
		var instance: Node3D = instances[uid]
		if floor_surface: floor_surface.restore_instance(instance)
		instance.position = Vector3(item["position"][0], item["position"][1], item["position"][2])
		preload("res://scripts/builder/asset_instance.gd").pose(instance, item, data["night"])
		preload("res://scripts/builder/part_colors.gd").apply(instance, item)
		instance.scale = Vector3.ONE * float(item["scale"])
		instance.visible = (Layers.shown(data, Layers.layer(item, library)) and item.get("visible", true))
		Layers.collision_visibility(instance, instance.visible)
		applied_records[uid] = state.duplicate(true)
		changed_instances.append(instance)
		last_apply_updates += 1
		exploration.door_states.erase(uid)
	for uid in instances.keys():
		if not keep.has(uid):
			instances[uid].free()
			instances.erase(uid)
			applied_records.erase(uid)
			last_apply_updates += 1
	exploration.records = data["objects"]
	terrain_traversal.configure(data,objects,player,exploration)
	# Owned-room changes can move or rename entrances without changing exterior geometry.
	exploration.update(data, instances)
	presentation.configure(data,instances,library)
	sun.light_energy = 0.15 if data["night"] else 0.8
	if floor_surface: floor_surface.rebuild()
	if floor_stack: floor_stack.update_visibility(true)
	apply_editor_focus()
	for instance in changed_instances:exploration.suspend_changed_instance(instance)

func set_editor_focus(ids: Array) -> void:
	var next: Dictionary={}
	for uid in ids:next[uid]=true
	if next==editor_focus:return
	editor_focus=next
	apply_editor_focus()
func apply_editor_focus() -> void:
	for uid in instances:
		instances[uid].visible=applied_records.get(uid,{}).get("visible",true) and (editor_focus.is_empty() or editor_focus.has(uid))

func point(at: Vector2, snap: bool, elevation: float) -> Array:
	var ray: Vector3 = camera.project_ray_origin(at)
	var direction: Vector3 = camera.project_ray_normal(at)
	var result: Variant = Plane(Vector3.UP, elevation).intersects_ray(ray, direction)
	var location: Vector3 = result if result is Vector3 else Vector3.ZERO
	if snap:
		location.x = snappedf(location.x, 1.0)
		location.z = snappedf(location.z, 1.0)
	return [location.x, elevation, location.z]

func pick(at: Vector2) -> String:
	if not editor_focus.is_empty():
		var ids: Array[String]=pick_all(at);return "" if ids.is_empty() else ids[0]
	var from: Vector3 = camera.project_ray_origin(at)
	var query := PhysicsRayQueryParameters3D.create(from, from + camera.project_ray_normal(at) * 1000.0, 1)
	for attempt in 32:
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty(): return ""
		var node: Node = hit.get("collider")
		while node:
			if node.has_meta("builder_uid"):
				var uid: String = node.get_meta("builder_uid")
				for item in data_state.get("objects", []):
					if item["uid"] == uid and Layers.editable(data_state, item, library): return uid
				break
			node = node.get_parent()
		query.exclude = query.exclude + [hit["rid"]]
	return ""

func pick_all(at: Vector2) -> Array[String]:
	var result: Array[String] = []
	var records: Dictionary = {}
	for item in data_state.get("objects",[]): records[item["uid"]] = item
	var from: Vector3 = camera.project_ray_origin(at)
	var query := PhysicsRayQueryParameters3D.create(from,from+camera.project_ray_normal(at)*1000,1)
	query.exclude = [player.get_rid()]
	for attempt in records.size()+32:
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty(): break
		var node: Node = hit.get("collider")
		var uid: String = ""
		while node:
			if node.has_meta("builder_uid"): uid = str(node.get_meta("builder_uid")); break
			node = node.get_parent()
		var excluded: Array[RID] = query.exclude
		excluded.append(hit["rid"])
		if instances.has(uid):
			# One asset may contain many collision bodies. Exclude its complete
			# branch so it appears once, then continue along the same ray.
			var instance: Node = instances[uid]
			for body in [instance]+instance.find_children("*","CollisionObject3D",true,false):
				if body is CollisionObject3D and not excluded.has(body.get_rid()): excluded.append(body.get_rid())
		query.exclude = excluded
		if records.has(uid) and not result.has(uid) and Layers.editable(data_state,records[uid],library) and instances[uid].is_visible_in_tree() and (editor_focus.is_empty() or editor_focus.has(uid)): result.append(uid)
	return result

func show_selection(uid: String) -> void:
	selection.visible = instances.has(uid)
	if not selection.visible:
		return
	var instance: Node3D = instances[uid]
	var bounds: AABB = instance.transform * Bounds.get_bounds(instance)
	var lines := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("62f4d9")
	lines.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for edge in [[0,1],[0,2],[0,4],[1,3],[1,5],[2,3],[2,6],[3,7],[4,5],[4,6],[5,7],[6,7]]:
		lines.surface_add_vertex(bounds.get_endpoint(edge[0]))
		lines.surface_add_vertex(bounds.get_endpoint(edge[1]))
	lines.surface_end()
	selection.mesh = lines

func preview(id: String, values: Array, direction: String, size: float, show: bool) -> void:
	if id != ghost_id:
		if ghost:
			ghost.free()
		ghost = null
		ghost_id = id
		if library.assets.has(id):
			ghost = preload("res://scripts/builder/asset_instance.gd").make(library, id, "3d")
			add_child(ghost)
			for node in [ghost] + ghost.find_children("*", "CollisionObject3D", true, false):
				if node is CollisionObject3D:
					node.collision_layer = 0
					node.collision_mask = 0
			var material := StandardMaterial3D.new()
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.albedo_color = Color(0.3, 1.0, 0.85, 0.35)
			for mesh in ghost.find_children("*", "MeshInstance3D", true, false):
				if ghost.has_method("mixed_bounds"): mesh.transparency = 0.55
				else: mesh.material_override = material
	if ghost:
		ghost.visible = show
		ghost.position = Vector3(values[0], values[1], values[2])
		preload("res://scripts/builder/asset_instance.gd").orient(ghost, direction)
		ghost.scale = Vector3.ONE * size

func walk(enabled: bool) -> void:
	if exploration: exploration.set_enabled(enabled)
	walking = enabled
	player.active = enabled and (not terrain_traversal or terrain_traversal.ensure_start())
	player.visible = enabled
	player.collision_layer = 1 if enabled else 0
	if ghost:
		ghost.visible = false
	update_camera()

func update_camera() -> void:
	if exploration and exploration.photo and exploration.photo.active: return
	var focus: Vector3 = player.position + Vector3.UP if walking else target
	var rotation_basis := Basis.from_euler(Vector3(deg_to_rad(-pitch), deg_to_rad(yaw), 0))
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE if walking else Camera3D.PROJECTION_ORTHOGONAL
	camera.size = distance
	camera.position = focus + rotation_basis * Vector3(0, 0, 9.0 if walking else (maxf(3,distance) if detail_view_active else distance))
	camera.look_at(focus)

func reset_camera(kind: String = "city") -> void:
	target = Vector3.ZERO
	distance = 14.0 if kind == "room" else 55.0
	yaw = 45
	pitch = 48
	player.position = Vector3(0, 0.2, 2.5 if kind == "room" else 9)
	update_camera()

func surface_point(at: Vector2, snap: bool, elevation: float, excluding: Array = []) -> Array:
	surface_feedback=""
	if not surface_snapping: return point(at, snap, elevation)
	var from: Vector3 = camera.project_ray_origin(at)
	var query := PhysicsRayQueryParameters3D.create(from, from + camera.project_ray_normal(at) * 1000, 3)
	var exclude: Array[RID] = [player.get_rid()]
	for uid in excluding:
		if instances.has(uid) and instances[uid] is CollisionObject3D: exclude.append(instances[uid].get_rid())
	query.exclude = exclude
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		if preload("res://scripts/builder/terrain_plan.gd").settings(data_state)["enabled"] and Layers.shown(data_state,"Ground") and (not exploration or exploration.interior==null):
			var terrain_hit: Dictionary=preload("res://scripts/builder/terrain_plan.gd").raycast(data_state,from,camera.project_ray_normal(at))
			if terrain_hit["ok"]:
				hit={"position":terrain_hit["point"],"normal":terrain_hit["normal"]}
	if hit.is_empty():
		surface_feedback="No surface hit · using the height plane"
		return point(at,snap,elevation)
	if hit["normal"].y < 0.65:
		surface_feedback="Surface is too steep · using the height plane"
		return point(at,snap,elevation)
	var p: Vector3 = hit["position"]
	if snap:
		p.x = snappedf(p.x, 0.5)
		p.z = snappedf(p.z, 0.5)
	return [p.x, p.y + elevation, p.z]
