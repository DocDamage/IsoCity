extends Node2D

const RenderingBudget = preload("res://scripts/builder/rendering_budget.gd")
const Library = preload("res://scripts/builder/asset_library.gd")
const TileRotation = preload("res://scripts/iso_tile_rotation.gd")
const Layers = preload("res://scripts/builder/layers.gd")
const Roads = preload("res://scripts/builder/roads.gd")
const Families=preload("res://scripts/builder/terrain_family_plan.gd")
const Patterns=preload("res://scripts/builder/tile_patterns.gd")
var library: RefCounted
var presentation: Node
var projection_pool: Node
var data_state: Dictionary = {}
var detail_view_active: bool=false
var editor_focus: Dictionary={}
var exploration: Node
var ground: TileMapLayer
var objects: Node2D
var camera: Camera2D
var lighting: CanvasModulate
var player: CharacterBody2D
var instances: Dictionary = {}
var applied_records: Dictionary = {}
var last_apply_updates: int = 0
var last_apply_tile_updates: int = 0
var tile_lookup: Dictionary = {}
var ghost: Node2D
var ghost_id: String = ""
var selection: Line2D
var grid: Node2D
var rotation_tiles: Dictionary = {}
var painted_tiles: Dictionary = {}
var applied_tiles: Dictionary = {}
var ground_input: Dictionary = {}
var family_levels: Dictionary={}
var family_variants: Dictionary={}
var family_sources: Dictionary={}
var family_warnings: Dictionary={}
var terrain: Node2D
var terrain_tiles: Dictionary={}
var terrain_tiles_dirty: bool=true
var terrain_outside: TileMapLayer
var terrain_outside_stamp: int=0
var terrain_presentation: Node
var terrain_traversal: Node
var floor_stack: Node2D

func _ready() -> void:
	presentation = preload("res://scripts/builder/asset_presentation.gd").new()
	add_child(presentation)
	projection_pool = RenderingBudget.projection_pool(self)
	ground = TileMapLayer.new()
	ground.name = "Ground"
	ground.position.x = -16
	ground.z_index = -5
	ground.tile_set = load("res://resources/tilesets/city_ground_tileset.tres").duplicate(true)
	var floors: TileSet = load("res://resources/tilesets/floors_tileset.tres")
	ground.tile_set.add_source(floors.get_source(0).duplicate(true), 2)
	for source_index in ground.tile_set.get_source_count():
		var source: TileSetAtlasSource = ground.tile_set.get_source(ground.tile_set.get_source_id(source_index))
		# Rotation samples the original atlas; nearest filtering needs no padded copy.
		source.use_texture_padding = false
		for tile_index in source.get_tiles_count():
			var coords: Vector2i = source.get_tile_id(tile_index)
			for turns in range(1, 4):
				if not source.has_alternative_tile(coords, turns):
					source.create_alternative_tile(coords, turns)
				source.get_tile_data(coords, turns).material = TileRotation.material_for(TileRotation.DIRECTIONS[turns], coords, 4 if source_index == 1 else 1)
	add_child(ground)
	terrain=preload("res://scripts/builder/terrain_surface_2d.gd").new(); terrain.name="Terrain"; terrain.z_index=-5; add_child(terrain)
	terrain_outside=TileMapLayer.new(); terrain_outside.name="TerrainOutside"; terrain_outside.hide(); add_child(terrain_outside)
	grid = Node2D.new()
	grid.set_script(preload("res://scripts/builder/grid_2d.gd"))
	grid.z_index = -4
	add_child(grid)
	objects = Node2D.new()
	objects.name = "Objects"
	objects.y_sort_enabled = true
	add_child(objects)
	terrain_presentation=preload("res://scripts/builder/terrain_presentation_2d.gd").new(); add_child(terrain_presentation)
	terrain_traversal=preload("res://scripts/builder/terrain_traversal.gd").new(); add_child(terrain_traversal)
	camera = Camera2D.new()
	camera.name = "Camera2D"
	camera.zoom = Vector2(2, 2)
	add_child(camera)
	lighting = CanvasModulate.new()
	add_child(lighting)
	selection = Line2D.new()
	selection.width = 1.5
	selection.default_color = Color("5debd3")
	selection.z_index = 100
	add_child(selection)
	var registry: Dictionary = Catalog.get_registry()["tilesets"]
	for key in registry:
		var source: int = 2 if "Floors" in key else (1 if "Animated" in key else 0)
		for id in registry[key]:
			var coords: Array = registry[key][id]
			tile_lookup["2d:" + id] = {"source": source, "atlas": Vector2i(int(coords[0]) / 32, int(coords[1]) / 16)}
			if source == 1:
				tile_lookup["2d:" + id]["atlas"].x = 0
	player = load("res://scenes/items/Characters/Office_Worker.tscn").instantiate()
	player.name = "Player"
	player.position = Vector2(0, 60)
	player.visible = false
	player.collision_layer = 0
	player.collision_mask = 0
	objects.add_child(player)

func apply(data: Dictionary) -> void:
	var changed_instances: Array[Node]=[]
	data_state = data
	last_apply_updates = 0
	last_apply_tile_updates = 0
	if not exploration:
		exploration = preload("res://scripts/builder/exploration.gd").new()
		exploration.dimension = "2d"
		exploration.library = library
		exploration.player = player
		add_child(exploration)
	exploration.reconcile_source(data)
	if exploration.interior==null: ground.visible = Layers.shown(data, "Ground")
	apply_ground(data)
	if exploration.interior==null:
		var sculpted: bool=preload("res://scripts/builder/terrain_plan.gd").settings(data)["enabled"]
		if sculpted and terrain_tiles_dirty:
			terrain_tiles=preload("res://scripts/builder/terrain_tiles_2d.gd").descriptions(ground,applied_tiles); terrain_tiles_dirty=false
		terrain.configure(data,terrain_tiles if sculpted else {})
		terrain_outside.visible=sculpted and Layers.shown(data,"Ground")
		if sculpted:
			var outside_stamp: int=hash([preload("res://scripts/builder/terrain_plan.gd").bounds(data),ground_input,family_levels])
			if outside_stamp!=terrain_outside_stamp: preload("res://scripts/builder/terrain_tiles_2d.gd").update_outside(terrain_outside,ground,preload("res://scripts/builder/terrain_plan.gd").bounds(data)); terrain_outside_stamp=outside_stamp
		ground.visible=Layers.shown(data,"Ground") and not sculpted; grid.visible=not sculpted
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
			var instance: Node2D = preload("res://scripts/builder/asset_instance.gd").make(library,item["asset"],"2d",true,projection_pool)
			objects.add_child(instance)
			instances[uid] = instance
		var instance: Node2D = instances[uid]
		preload("res://scripts/builder/asset_instance.gd").pose(instance, item, data["night"])
		preload("res://scripts/builder/part_colors.gd").apply(instance, item)
		if instance is IsoObject:
			instance.night_mode = data["night"]
		instance.position = position_for(item["position"])
		instance.scale = Vector2.ONE * float(item["scale"])
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
	terrain_presentation.configure(data,objects,instances,exploration)
	terrain_traversal.configure(data,objects,player,exploration)
	# Owned-room changes can move or rename entrances without changing exterior geometry.
	exploration.update(data, instances)
	presentation.configure(data,instances,library)
	lighting.color = Color(0.48, 0.55, 0.78) if data["night"] else Color.WHITE
	if floor_stack: floor_stack.after_apply()
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

func apply_ground(data: Dictionary) -> void:
	var input: Dictionary={"tiles":data["tiles"],"roads":data.get("roads",[])}
	var sculpted: bool=data.get("terrain",{}).get("enabled",false)
	var levels: Dictionary=Families.water_levels(data.get("water_cells",[])) if sculpted else {}
	var dirty: Dictionary={}
	var next_tiles: Dictionary=applied_tiles
	if input!=ground_input:
		next_tiles=Families.by_cell(Roads.tiles(data)).duplicate(true)
		dirty=Families.affected(applied_tiles,next_tiles)
		ground_input=input.duplicate(true)
	if levels!=family_levels:
		dirty.merge(Families.affected(family_levels,levels),true)
		family_levels=levels
	for cell in dirty:
		if not next_tiles.has(cell):
			if applied_tiles.has(cell):
				ground.erase_cell(cell)
				last_apply_tile_updates+=1
			family_variants.erase(cell)
			family_warnings.erase(cell)
			continue
		var tile: Dictionary=next_tiles[cell]
		var variant: Dictionary=Families.ground_variant(tile,cell,next_tiles,levels)
		if applied_tiles.get(cell)==tile and family_variants.get(cell,{})==variant: continue
		if not tile_lookup.has(tile["asset"]): continue
		var info: Dictionary=tile_lookup[tile["asset"]]
		var direction: String=tile.get("direction","SE")
		family_warnings.erase(cell)
		if not variant.is_empty():
			var source: int=family_source(variant)
			if source>=0:
				info={"source":source,"atlas":Vector2i.ZERO}
				direction="SE"
				var warning: String=Families.warning(variant)
				if not warning.is_empty(): family_warnings[cell]=warning
			else: family_warnings[cell]="No reviewed terrain piece for this connection"
			family_variants[cell]=variant
		else:
			family_variants.erase(cell)
			if not tile.get("colors",[]).is_empty(): info=painted_tile_info(tile,info)
		ground.set_cell(cell,info["source"],info["atlas"],tile_alternative(info,direction))
		last_apply_tile_updates+=1
	applied_tiles=next_tiles
	terrain_tiles_dirty=terrain_tiles_dirty or last_apply_tile_updates>0

func family_source(variant: Dictionary) -> int:
	var key: Array=Patterns.family_key(variant)
	if family_sources.has(key): return family_sources[key]
	var pattern: Dictionary=Patterns.family_pattern(variant)
	if pattern.is_empty(): return -1
	var source:=TileSetAtlasSource.new()
	source.texture=pattern["atlas"]
	source.texture_region_size=Patterns.CELL
	source.use_texture_padding=false
	source.create_tile(Vector2i.ZERO)
	var frames: int=pattern["textures"].size()
	if frames>1:
		source.set_tile_animation_columns(Vector2i.ZERO,frames)
		source.set_tile_animation_frames_count(Vector2i.ZERO,frames)
		source.set_tile_animation_speed(Vector2i.ZERO,pattern["speed"])
		for i in frames: source.set_tile_animation_frame_duration(Vector2i.ZERO,i,pattern["durations"][i])
	var id: int=ground.tile_set.get_next_source_id()
	ground.tile_set.add_source(source,id)
	family_sources[key]=id
	return id

func tile_alternative(info: Dictionary, direction: String) -> int:
	var angle: float = TileRotation.degrees(direction)
	if is_zero_approx(angle): return 0
	if info["source"] < 3 and is_zero_approx(fposmod(angle, 90)): return TileRotation.quarter_turns(direction)
	var key: String = str(info["source"]) + ":" + str(info["atlas"]) + ":" + str(angle)
	if not rotation_tiles.has(key):
		var source: TileSetAtlasSource = ground.tile_set.get_source(info["source"])
		var alternative: int = source.create_alternative_tile(info["atlas"])
		source.get_tile_data(info["atlas"], alternative).material = TileRotation.material_for(direction, info["atlas"], info.get("frames", 4 if info["source"] == 1 else 1))
		rotation_tiles[key] = alternative
	return rotation_tiles[key]

func painted_tile_info(tile: Dictionary, original: Dictionary) -> Dictionary:
	var key: String = tile["asset"] + JSON.stringify(tile["colors"])
	if not painted_tiles.has(key):
		var directions: Dictionary = library.assets[tile["asset"]]["data"]["directions"]
		var entry: Dictionary = directions.get("SE", directions.values()[0])
		var path: String = "res://assets/pixel_isometric/" + str(entry["file"])
		var texture: Texture2D = load(path)
		var source := TileSetAtlasSource.new()
		source.texture = preload("res://scripts/builder/part_colors.gd").recolored_texture(texture, tile["colors"])
		source.texture_region_size = Vector2i(32, 16)
		source.use_texture_padding = false
		source.create_tile(Vector2i.ZERO)
		var frames: int = texture.get_width() / 32
		if frames > 1:
			source.set_tile_animation_columns(Vector2i.ZERO, frames)
			source.set_tile_animation_frames_count(Vector2i.ZERO, frames)
			source.set_tile_animation_speed(Vector2i.ZERO, 4)
		painted_tiles[key] = {"source": ground.tile_set.add_source(source), "atlas": Vector2i.ZERO, "frames": frames}
	return painted_tiles[key]

static func position_for(values: Array) -> Vector2:
	return Vector2(values[0], values[1] - values[2] * 8.0)

func point(at: Vector2, snap: bool, elevation: float) -> Array:
	var local: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * at
	if preload("res://scripts/builder/terrain_plan.gd").settings(data_state)["enabled"] and exploration.interior==null:
		var hit: Dictionary=terrain.pick(local+Vector2(0,elevation*8))
		if hit["ok"]:
			var flat: Array=preload("res://scripts/builder/traffic_plan.gd").world(hit["point"],"2d")
			local=Vector2(flat[0],flat[1])
			if snap: local=IsoMath.tile_to_world(IsoMath.world_to_tile(local))
			return [local.x,local.y,elevation]
	if snap:
		local = IsoMath.tile_to_world(IsoMath.world_to_tile(local, int(elevation)))
	else:
		local.y += elevation * 8.0
	return [local.x, local.y, elevation]

func pick(at: Vector2) -> String:
	var local: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * at
	var order: Array = instances.keys()
	order.sort_custom(func(a: String, b: String) -> bool: return instances[a].position.y > instances[b].position.y)
	for uid in order:
		if not editor_focus.is_empty() and not editor_focus.has(uid):continue
		var record: Dictionary = {}
		for item in data_state.get("objects", []):
			if item["uid"] == uid: record = item; break
		if record.is_empty() or not Layers.editable(data_state, record, library): continue
		var sprite: Sprite2D = instances[uid].get_node_or_null("Sprite2D")
		if sprite and sprite.get_rect().has_point(sprite.to_local(local)):
			return uid
	return ""

func show_selection(uid: String) -> void:
	selection.visible = instances.has(uid)
	if selection.visible:
		var instance: Node2D = instances[uid]
		var points: PackedVector2Array = preload("res://scripts/builder/asset_instance.gd").footprint(instance)
		points.append(points[0])
		selection.points = points
		selection.position = instance.position
		selection.position.y-=float(instance.get_meta("terrain_height",0))*8
		selection.scale = instance.scale
		selection.rotation = instance.rotation

func pick_all(at: Vector2) -> Array[String]:
	var local: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * at
	var result: Array[String] = []
	for item in data_state.get("objects",[]):
		var uid: String = item["uid"]
		if not instances.has(uid) or not Layers.editable(data_state,item,library) or not instances[uid].is_visible_in_tree() or not editor_focus.is_empty() and not editor_focus.has(uid): continue
		var sprite: Sprite2D = instances[uid].get_node_or_null("Sprite2D")
		if sprite and sprite.get_rect().has_point(sprite.to_local(local)): result.append(uid)
	result.sort_custom(func(a: String,b: String) -> bool:
		var left: Node2D = instances[a]
		var right: Node2D = instances[b]
		if left.z_index != right.z_index: return left.z_index > right.z_index
		if not is_equal_approx(left.position.y,right.position.y): return left.position.y > right.position.y
		return left.get_index() > right.get_index()
	)
	return result

func show_tile_selection(cell: Vector2i) -> void:
	var points: PackedVector2Array = IsoMath.get_footprint_diamond(Vector2i.ZERO, Vector2i.ONE)
	points.append(points[0])
	selection.points = points
	selection.position = IsoMath.tile_to_world(cell)
	if preload("res://scripts/builder/terrain_plan.gd").settings(data_state)["enabled"]:
		for index in points.size():
			var point: Vector2=points[index]+selection.position; var ground: Vector2=preload("res://scripts/builder/traffic_plan.gd").metric([point.x,point.y,0],"2d")
			points[index].y-=preload("res://scripts/builder/terrain_plan.gd").sample(data_state,ground,terrain_presentation.heights)["height"]*8
		selection.points=points
	selection.scale = Vector2.ONE
	selection.rotation = 0
	selection.visible = true

func preview(id: String, values: Array, direction: String, size: float, show: bool) -> void:
	if id != ghost_id:
		if ghost:
			ghost.free()
		ghost = null
		ghost_id = id
		if library.assets.has(id):
			ghost = preload("res://scripts/builder/asset_instance.gd").make(library, id, "2d")
			ghost.modulate.a = 0.45
			add_child(ghost)
			for node in ghost.find_children("*", "CollisionObject2D", true, false):
				node.collision_layer = 0
				node.collision_mask = 0
			if ghost is CollisionObject2D:
				ghost.collision_layer = 0
				ghost.collision_mask = 0
	if ghost:
		ghost.visible = show
		ghost.position = position_for(values)
		ghost.direction = direction
		ghost.scale = Vector2.ONE * size
		terrain_presentation.present(ghost,float(values[2]))

func walk(enabled: bool) -> void:
	if exploration: exploration.set_enabled(enabled)
	player.visible = enabled
	player.collision_mask = 1 if enabled else 0
	player.is_player_controlled = enabled and (not terrain_traversal or terrain_traversal.ensure_start())
	player.collision_layer = 1 if enabled else 0
	if ghost:
		ghost.visible = false

func reset_camera(kind: String = "city") -> void:
	camera.position = Vector2.ZERO
	var view_size: Vector2 = get_viewport().get_visible_rect().size
	var content_size: Vector2 = Vector2(440, 340) if kind == "room" else Vector2(900, 530)
	camera.zoom = Vector2.ONE * minf(view_size.x / content_size.x, view_size.y / content_size.y) * 0.9
	player.position = Vector2(0, 60)
