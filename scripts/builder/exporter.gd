extends RefCounted

const Runtime = preload("res://scripts/builder/play_scene.gd")
const Player3D = preload("res://scripts/builder/player_3d.gd")

static func save_scene(world: Node, data: Dictionary, library: RefCounted, path: String,project_palette: Variant=null) -> Error:
	var policy: Dictionary=library.project_palette if project_palette==null else project_palette
	if not policy.is_empty() and not preload("res://scripts/builder/asset_collections.gd").project_valid(policy):return ERR_INVALID_DATA
	# An owned-room editor or an interior visit can suspend the source world's
	# ground and lighting. Build that snapshot from the requested document.
	if "data_state" in world and (not is_same(world.data_state,data) or (world.exploration and world.exploration.interior)):
		if not world.is_inside_tree(): return ERR_UNCONFIGURED
		var viewport:=SubViewport.new(); viewport.size=Vector2i(64,64); viewport.own_world_3d=true; viewport.world_2d=World2D.new(); viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
		world.get_tree().root.add_child(viewport)
		var clean: Node=load("res://scripts/builder/world_"+str(data["mode"])+".gd").new(); clean.library=library; viewport.add_child(clean); clean.apply(data)
		var result: Error=save_scene(clean,data,library,path,policy); viewport.free(); return result
	var mode: String = data["mode"]
	var scene_root: Node = Node2D.new() if mode == "2d" else Node3D.new()
	scene_root.name = "MyCity" if mode == "2d" else "MyCity3D"
	scene_root.set_script(Runtime)
	scene_root.set("dimension", mode)
	scene_root.set("studio_data", data.duplicate(true))
	# PackedScene text rounds doubles, and JSON decodes integer records as
	# floats. A tagged Variant payload preserves both without resource paths.
	scene_root.set("studio_source_base64", Runtime.SOURCE_PREFIX + Marshalls.variant_to_base64(data))
	if not policy.is_empty():scene_root.set("project_palette",policy.duplicate(true))
	if mode == "2d":
		scene_root.y_sort_enabled = true
		var ground: TileMapLayer = world.ground.duplicate()
		ground.visible = true
		scene_root.add_child(ground)
		own_branch(ground, scene_root)
		var light := CanvasModulate.new()
		light.name = "Lighting"
		light.color = world.lighting.color
		scene_root.add_child(light)
		light.owner = scene_root
	else:
		for child in world.get_children():
			if child is WorldEnvironment or child is DirectionalLight3D or child.name == "Foundation":
				var copy: Node = child.duplicate()
				scene_root.add_child(copy)
				own_branch(copy, scene_root)
	var objects: Node = Node2D.new() if mode == "2d" else Node3D.new()
	objects.name = "Objects"
	if objects is Node2D:
		objects.y_sort_enabled = true
	scene_root.add_child(objects)
	objects.owner = scene_root
	for item in data["objects"]:
		var instance: Node = preload("res://scripts/builder/asset_instance.gd").make(library, item["asset"], mode)
		instance.name = item.get("name", library.assets[item["asset"]]["name"]).replace(" ", "_")
		objects.add_child(instance, true)
		instance.owner = scene_root
		instance.set_meta("builder_uid", item["uid"])
		if mode == "2d":
			preload("res://scripts/builder/asset_instance.gd").pose(instance, item, data["night"])
			instance.position = Vector2(item["position"][0], item["position"][1] - item["position"][2] * 8)
			instance.scale = Vector2.ONE * float(item["scale"])
			if instance is IsoObject:
				instance.night_mode = data["night"]
		else:
			instance.position = Vector3(item["position"][0], item["position"][1], item["position"][2])
			preload("res://scripts/builder/asset_instance.gd").pose(instance, item, data["night"])
			instance.scale = Vector3.ONE * float(item["scale"])
		instance.visible=preload("res://scripts/builder/layers.gd").shown(data,preload("res://scripts/builder/layers.gd").layer(item,library)) and item.get("visible",true)
		preload("res://scripts/builder/layers.gd").collision_visibility(instance,instance.visible)
	if mode == "3d" and not data.get("roads", []).is_empty():
		var roads: Node3D = preload("res://scripts/builder/roads.gd").make_3d(data)
		scene_root.add_child(roads)
		own_branch(roads, scene_root)
	var camera: Node = Camera2D.new() if mode == "2d" else Camera3D.new()
	camera.name = "Camera2D" if mode == "2d" else "Camera3D"
	if mode == "2d":
		camera.zoom = Vector2(2, 2)
	else:
		camera.current = true
	scene_root.add_child(camera)
	camera.owner = scene_root
	var player: Node
	var spawn: Array = data.get("spawn", [0, 60, 0] if mode == "2d" else [0, 0.2, 9])
	if mode == "2d":
		player = load("res://scenes/items/Characters/Office_Worker.tscn").instantiate()
		player.position = Vector2(spawn[0], spawn[1])
	else:
		player = CharacterBody3D.new()
		player.set_script(Player3D)
		player.collision_mask = 3
		player.position = Vector3(spawn[0], spawn[1], spawn[2])
	player.name = "Player"
	scene_root.add_child(player)
	player.owner = scene_root
	var packed := PackedScene.new()
	var result: Error = packed.pack(scene_root)
	if result == OK:
		result = ResourceSaver.save(packed, path)
	scene_root.free()
	return result

static func own_branch(node: Node, scene_root: Node) -> void:
	node.owner = scene_root
	for child in node.get_children():
		own_branch(child, scene_root)
