extends Node2D

const IsoMath = preload("res://scripts/iso_math.gd")
const Catalog = preload("res://scripts/catalog.gd")
const IsoObject = preload("res://scripts/iso_object.gd")
const IsoCharacter = preload("res://scripts/iso_character.gd")

@onready var camera: Camera2D = $Camera2D
@onready var world: Node2D = $World
@onready var tilemap: TileMapLayer = $World/TileMapLayer
@onready var objects_container: Node2D = $World/Objects
@onready var canvas_modulate: CanvasModulate = $World/CanvasModulate
@onready var ghost: Node2D = $Ghost
@onready var ghost_sprite: Sprite2D = $Ghost/Sprite2D

# UI Nodes
@onready var category_option: OptionButton = $UI/Panel/VBox/CategoryOption
@onready var search_input: LineEdit = $UI/Panel/VBox/SearchInput
@onready var item_grid: GridContainer = $UI/Panel/VBox/Scroll/ItemGrid
@onready var status_label: Label = $UI/BottomBar/StatusLabel
@onready var mode_btn: Button = $UI/TopBar/HBox/ModeBtn
@onready var rotate_btn: Button = $UI/TopBar/HBox/RotateBtn
@onready var day_night_btn: Button = $UI/TopBar/HBox/DayNightBtn
@onready var elev_up_btn: Button = $UI/TopBar/HBox/ElevUpBtn
@onready var elev_down_btn: Button = $UI/TopBar/HBox/ElevDownBtn
@onready var save_btn: Button = $UI/TopBar/HBox/SaveBtn
@onready var load_btn: Button = $UI/TopBar/HBox/LoadBtn
@onready var clear_btn: Button = $UI/TopBar/HBox/ClearBtn

var hovered_tile: Vector2i = Vector2i.ZERO
var active_item_id: String = ""
var current_dir: String = "SE"
var night_mode: bool = false
var current_elevation: int = 0
var editor_mode: String = "build" # "build" or "explore"

var is_panning: bool = false
var pan_start_pos: Vector2 = Vector2.ZERO
var zoom_target: float = 1.5

# Player character for Explore mode
var player_character: IsoCharacter = null

# History for Undo / Redo
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []

# Store placed objects: tile_pos -> Array[Node2D]
var placed_items: Dictionary = {}
var tile_lookup: Dictionary = {}
var status_message: String = ""
var status_message_until: int = 0

func _ready() -> void:
	_init_tile_lookup()
	_setup_camera()
	_populate_categories()
	_populate_items("Buildings")
	_connect_ui()
	_generate_starter_map()
	_update_ghost()

func _init_tile_lookup() -> void:
	var reg: Dictionary = Catalog.get_registry()
	var tilesets: Dictionary = reg.get("tilesets", {})
	
	var city_tiles: Dictionary = tilesets.get("Tilesets/City_Ground_Iso_Tileset_32x16.png", {})
	for tname in city_tiles:
		var coords: Array = city_tiles[tname]
		tile_lookup[tname] = {
			"source": 0,
			"atlas": Vector2i(int(coords[0]) / 32, int(coords[1]) / 16)
		}
		
	var anim_key: String = ""
	for k in tilesets.keys():
		if "Animated_Tiles" in k:
			anim_key = k
			break
	if not anim_key.is_empty():
		var anim_tiles: Dictionary = tilesets[anim_key]
		for tname in anim_tiles:
			var coords: Array = anim_tiles[tname]
			tile_lookup[tname] = {
				"source": 1,
				"atlas": Vector2i(0, int(coords[1]) / 16)
			}

func _setup_camera() -> void:
	camera.position = Vector2(0, 0)
	camera.zoom = Vector2(1.5, 1.5)
	zoom_target = 1.5

func _populate_categories() -> void:
	category_option.clear()
	category_option.add_item("All Categories")
	var cats: Array = Catalog.get_categories()
	for cat in cats:
		category_option.add_item(cat)
	
	for idx in range(category_option.item_count):
		if category_option.get_item_text(idx) == "Buildings":
			category_option.select(idx)
			break

func _populate_items(category_filter: String, search_text: String = "") -> void:
	for child in item_grid.get_children():
		child.queue_free()
		
	var items_to_show: Array = []
	var reg: Dictionary = Catalog.get_registry()
	var all_items: Dictionary = reg.get("items", {})
	
	if category_filter == "All Categories":
		for iid in all_items:
			items_to_show.append(all_items[iid])
	else:
		var cat_items: Array = Catalog.get_items_in_category(category_filter)
		for iid in cat_items:
			if all_items.has(iid):
				items_to_show.append(all_items[iid])
				
	var query: String = search_text.to_lower().strip_edges()
	for it in items_to_show:
		var iname: String = it.get("name", "")
		var dname: String = it.get("display_name", iname)
		if not query.is_empty():
			if not (query in iname.to_lower() or query in dname.to_lower()):
				continue
				
		_create_item_button(it)

func _create_item_button(item_data: Dictionary) -> void:
	var btn: Button = Button.new()
	var iname: String = item_data.get("name", "")
	var dname: String = item_data.get("display_name", iname).replace("_", " ")
	
	btn.text = dname
	btn.tooltip_text = "%s (%s)\nClick or Drag to place" % [dname, item_data.get("category", "")]
	btn.custom_minimum_size = Vector2(140, 36)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.clip_text = true
	btn.focus_mode = Control.FOCUS_NONE
	
	var icon_tex: Texture2D = _get_item_icon(item_data)
	if icon_tex:
		btn.icon = icon_tex
		btn.expand_icon = true
		
	btn.pressed.connect(func():
		select_item(iname)
	)
	
	btn.set_script(preload("res://scripts/draggable_item_button.gd"))
	btn.set("item_id", iname)
	
	item_grid.add_child(btn)

func _get_item_icon(item_data: Dictionary) -> Texture2D:
	var dirs: Dictionary = item_data.get("directions", {})
	if dirs.is_empty():
		return null
	var pref: String = "SE" if dirs.has("SE") else dirs.keys()[0]
	var file_rel: String = dirs[pref].get("file", "")
	if not file_rel.is_empty():
		# Try pixel_isometric direct path first
		var full_res: String = "res://assets/pixel_isometric/" + file_rel
		if ResourceLoader.exists(full_res):
			return load(full_res)
		# Try stripping relative prefix (RPG world items use "../../isometric_rpg_world/...")
		full_res = "res://assets/" + file_rel.replace("../../", "")
		if ResourceLoader.exists(full_res):
			return load(full_res)
		# Try absolute asset-relative path as-is
		full_res = "res://assets/" + file_rel.lstrip("/")
		if ResourceLoader.exists(full_res):
			return load(full_res)
	return null

func _connect_ui() -> void:
	for button in [mode_btn, rotate_btn, day_night_btn, elev_up_btn, elev_down_btn, save_btn, load_btn, clear_btn]:
		button.focus_mode = Control.FOCUS_NONE
	category_option.item_selected.connect(func(idx: int):
		var cat: String = category_option.get_item_text(idx)
		_populate_items(cat, search_input.text)
	)
	search_input.text_changed.connect(func(query: String):
		var cat: String = category_option.get_item_text(category_option.selected)
		_populate_items(cat, query)
	)
	mode_btn.pressed.connect(func():
		toggle_mode()
	)
	rotate_btn.pressed.connect(func():
		_cycle_direction()
	)
	day_night_btn.pressed.connect(func():
		toggle_day_night()
	)
	elev_up_btn.pressed.connect(func():
		change_elevation(1)
	)
	elev_down_btn.pressed.connect(func():
		change_elevation(-1)
	)
	save_btn.pressed.connect(func():
		save_city()
	)
	load_btn.pressed.connect(func():
		load_city()
	)
	clear_btn.pressed.connect(func():
		clear_placed_objects()
	)

func toggle_mode() -> void:
	if editor_mode == "build":
		editor_mode = "explore"
		if mode_btn:
			mode_btn.text = "Explore Mode [Space]"
		_enter_explore_mode()
	else:
		editor_mode = "build"
		if mode_btn:
			mode_btn.text = "Build Mode [Space]"
		_exit_explore_mode()
	_update_ghost()

func _enter_explore_mode() -> void:
	ghost.visible = false
	if not player_character:
		# Spawn player character
		var char_scene := preload("res://scenes/items/Characters/Office_Worker.tscn")
		player_character = char_scene.instantiate() as IsoCharacter
		player_character.is_player_controlled = true
		player_character.position = IsoMath.tile_to_world(Vector2i(0, 0), 0)
		objects_container.add_child(player_character)
	else:
		player_character.is_player_controlled = true
		player_character.visible = true

func _exit_explore_mode() -> void:
	if player_character:
		player_character.is_player_controlled = false
	_update_ghost()

func change_elevation(amount: int) -> void:
	current_elevation = clampi(current_elevation + amount, 0, 10)
	if elev_up_btn:
		elev_up_btn.text = "Elev: %d [+/-]" % current_elevation
	_update_ghost()

func select_item(item_id: String) -> void:
	active_item_id = item_id
	var directions: Dictionary = Catalog.get_item(item_id).get("directions", {})
	if not directions.is_empty() and not directions.has(current_dir):
		current_dir = str(directions.keys()[0])
	rotate_btn.text = "Rot: %s [R]" % current_dir
	if editor_mode == "explore":
		toggle_mode()
	_update_ghost()

func _cycle_direction() -> void:
	var directions: Dictionary = Catalog.get_item(active_item_id).get("directions", {})
	var choices: Array = directions.keys() if not directions.is_empty() else ["SE", "SW", "NW", "NE"]
	current_dir = str(choices[(choices.find(current_dir) + 1) % choices.size()])
	if rotate_btn:
		rotate_btn.text = "Rot: %s [R]" % current_dir
	_update_ghost()

func toggle_day_night() -> void:
	night_mode = not night_mode
	if day_night_btn:
		day_night_btn.text = "Night [N]" if night_mode else "Day [N]"
	
	if canvas_modulate:
		canvas_modulate.color = Color(0.42, 0.46, 0.72) if night_mode else Color(1.0, 1.0, 1.0)
	
	for obj_list in placed_items.values():
		for obj in obj_list:
			if obj is IsoObject:
				obj.night_mode = night_mode
	_update_ghost()

func clear_placed_objects() -> void:
	_clear_history()
	for child in objects_container.get_children():
		if child != player_character:
			objects_container.remove_child(child)
			child.queue_free()
	placed_items.clear()
	_update_status()

func _clear_history() -> void:
	# Undone placements and erased objects are detached from the scene tree.
	var detached: Dictionary = {}
	for op in undo_stack + redo_stack:
		var node: Node = op.get("node")
		if is_instance_valid(node) and node.get_parent() == null:
			detached[node.get_instance_id()] = node
	for node in detached.values():
		node.free()
	undo_stack.clear()
	redo_stack.clear()

func _discard_redo() -> void:
	for op in redo_stack:
		var node: Node = op.get("node")
		if is_instance_valid(node) and node.get_parent() == null:
			node.free()
	redo_stack.clear()

func _exit_tree() -> void:
	_clear_history()

func _update_ghost() -> void:
	if editor_mode == "explore" or active_item_id.is_empty():
		ghost.visible = false
		return
		
	ghost.visible = true
	var item: Dictionary = Catalog.get_item(active_item_id)
	if item.is_empty():
		ghost.visible = false
		return
		
	var dirs: Dictionary = item.get("directions", {})
	var dir_key: String = current_dir
	if not dirs.has(dir_key):
		dir_key = "SE" if dirs.has("SE") else (dirs.keys()[0] if dirs.size() > 0 else "")
		
	if not dir_key.is_empty() and dirs.has(dir_key):
		var dinfo: Dictionary = dirs[dir_key]
		var rel_path: String = dinfo.get("file", "")
		var tex_res: String = "res://assets/pixel_isometric/" + rel_path
		if not ResourceLoader.exists(tex_res):
			tex_res = "res://assets/" + rel_path.replace("../../", "")
			
		if ResourceLoader.exists(tex_res):
			ghost_sprite.texture = load(tex_res)
		var orig: Array = dinfo.get("origin", [0, 0])
		ghost_sprite.centered = false
		ghost_sprite.offset = -Vector2(orig[0], orig[1])
		ghost_sprite.modulate = Color(1, 1, 1, 0.7)
		var frames: int = item.get("frames", 1)
		ghost_sprite.hframes = max(1, frames)
		ghost_sprite.frame = 1 if (night_mode and frames > 1 and item.get("kind") == "build") else 0
		
		var fp: Array = dinfo.get("footprint", [1, 1])
		ghost.set_meta("footprint", Vector2i(fp[0], fp[1]))
		ghost.queue_redraw()

func _process(delta: float) -> void:
	camera.zoom = camera.zoom.lerp(Vector2(zoom_target, zoom_target), delta * 15.0)
	
	if editor_mode == "explore" and player_character:
		# Smooth camera tracking player
		camera.position = camera.position.lerp(player_character.position, delta * 10.0)
	elif not search_input.has_focus():
		# Free panning in build mode
		var pan_vec: Vector2 = Vector2.ZERO
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			pan_vec.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			pan_vec.x += 1
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			pan_vec.y -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			pan_vec.y += 1
		if pan_vec != Vector2.ZERO:
			camera.position += pan_vec.normalized() * (400.0 / camera.zoom.x) * delta
			
	if editor_mode == "build":
		var mouse_world: Vector2 = get_global_mouse_position()
		hovered_tile = IsoMath.world_to_tile(mouse_world, current_elevation)
		ghost.position = IsoMath.tile_to_world(hovered_tile, current_elevation)
		
	_update_status()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_target = clampf(zoom_target * 1.15, 0.4, 4.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_target = clampf(zoom_target / 1.15, 0.4, 4.0)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				is_panning = true
				pan_start_pos = mb.position
			else:
				is_panning = false
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if editor_mode == "build" and not active_item_id.is_empty():
				place_object_at(hovered_tile, active_item_id)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if editor_mode == "build":
				erase_object_at(hovered_tile)
				
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		if is_panning:
			camera.position -= mm.relative / camera.zoom.x
			
	elif event is InputEventKey:
		var ke: InputEventKey = event as InputEventKey
		if ke.pressed and not ke.echo:
			if ke.keycode == KEY_SPACE:
				toggle_mode()
			elif ke.keycode == KEY_R:
				_cycle_direction()
			elif ke.keycode == KEY_N:
				toggle_day_night()
			elif ke.keycode == KEY_EQUAL:
				change_elevation(1)
			elif ke.keycode == KEY_MINUS:
				change_elevation(-1)
			elif ke.keycode == KEY_Z and ke.ctrl_pressed:
				undo()
			elif ke.keycode == KEY_Y and ke.ctrl_pressed:
				redo()
			elif ke.keycode == KEY_ESCAPE:
				active_item_id = ""
				_update_ghost()

func place_object_at(tile: Vector2i, item_id: String, state: Dictionary = {}, record_history: bool = true) -> void:
	var item: Dictionary = Catalog.get_item(item_id)
	if item.is_empty():
		return
		
	# Check if this is a ground/floor tile
	if item.get("kind", "") == "tile" and tile_lookup.has(item_id):
		var prev_source: int = tilemap.get_cell_source_id(tile)
		var prev_atlas: Vector2i = tilemap.get_cell_atlas_coords(tile)
		
		var tinfo: Dictionary = tile_lookup[item_id]
		tilemap.set_cell(tile, tinfo["source"], tinfo["atlas"])
		
		# Record for undo
		if record_history:
			_discard_redo()
			undo_stack.append({
				"type": "tile",
				"tile": tile,
				"prev_source": prev_source,
				"prev_atlas": prev_atlas,
				"new_source": tinfo["source"],
				"new_atlas": tinfo["atlas"]
			})
		_update_status()
		return
		
	# Place as Node2D scene instance
	var scene_path: String = Catalog.get_scene_path(item_id)
		
	if not ResourceLoader.exists(scene_path):
		return
			
	var scn: PackedScene = load(scene_path)
	if not scn:
		return
		
	var inst: Node2D = scn.instantiate()
	var place_direction: String = state.get("direction", current_dir)
	var place_elevation: int = int(state.get("elevation", current_elevation))
	inst.position = IsoMath.tile_to_world(tile, place_elevation)
	
	if inst is IsoObject:
		var iso_obj: IsoObject = inst as IsoObject
		iso_obj.direction = place_direction
		iso_obj.night_mode = night_mode
		iso_obj.grid_pos = tile
		iso_obj.elevation = place_elevation
		iso_obj.action = state.get("action", "idle")
		iso_obj.playing = true
	elif inst is IsoCharacter:
		var iso_char: IsoCharacter = inst as IsoCharacter
		iso_char.direction = place_direction
		iso_char.grid_pos = tile
		iso_char.elevation = place_elevation
		iso_char.action = state.get("action", "idle")
		
	objects_container.add_child(inst)
	if not placed_items.has(tile):
		placed_items[tile] = []
	placed_items[tile].append(inst)
	
	# Record for undo
	if record_history:
		_discard_redo()
		undo_stack.append({
			"type": "object_placed",
			"tile": tile,
			"node": inst
		})
	_update_status()

func erase_object_at(tile: Vector2i) -> void:
	if placed_items.has(tile) and placed_items[tile].size() > 0:
		var obj: Node2D = placed_items[tile].pop_back()
		if is_instance_valid(obj):
			objects_container.remove_child(obj)
			_discard_redo()
			undo_stack.append({
				"type": "object_erased",
				"tile": tile,
				"node": obj
			})
		if placed_items[tile].is_empty():
			placed_items.erase(tile)
	else:
		var prev_source: int = tilemap.get_cell_source_id(tile)
		var prev_atlas: Vector2i = tilemap.get_cell_atlas_coords(tile)
		if prev_source != -1:
			tilemap.erase_cell(tile)
			_discard_redo()
			undo_stack.append({
				"type": "tile",
				"tile": tile,
				"prev_source": prev_source,
				"prev_atlas": prev_atlas,
				"new_source": -1,
				"new_atlas": Vector2i(-1, -1)
			})
	_update_status()

func undo() -> void:
	if undo_stack.is_empty():
		return
	var op: Dictionary = undo_stack.pop_back()
	redo_stack.append(op)
	
	if op["type"] == "tile":
		var tile: Vector2i = op["tile"]
		var ps: int = op["prev_source"]
		if ps == -1:
			tilemap.erase_cell(tile)
		else:
			tilemap.set_cell(tile, ps, op["prev_atlas"])
	elif op["type"] == "object_placed":
		var node: Node2D = op["node"]
		var tile: Vector2i = op["tile"]
		if is_instance_valid(node):
			objects_container.remove_child(node)
			if placed_items.has(tile):
				placed_items[tile].erase(node)
	elif op["type"] == "object_erased":
		var node: Node2D = op["node"]
		var tile: Vector2i = op["tile"]
		if is_instance_valid(node):
			objects_container.add_child(node)
			if not placed_items.has(tile):
				placed_items[tile] = []
			placed_items[tile].append(node)
	_update_status()

func redo() -> void:
	if redo_stack.is_empty():
		return
	var op: Dictionary = redo_stack.pop_back()
	undo_stack.append(op)
	
	if op["type"] == "tile":
		var tile: Vector2i = op["tile"]
		var ns: int = op["new_source"]
		if ns == -1:
			tilemap.erase_cell(tile)
		else:
			tilemap.set_cell(tile, ns, op["new_atlas"])
	elif op["type"] == "object_placed":
		var node: Node2D = op["node"]
		var tile: Vector2i = op["tile"]
		if is_instance_valid(node):
			objects_container.add_child(node)
			if not placed_items.has(tile):
				placed_items[tile] = []
			placed_items[tile].append(node)
	elif op["type"] == "object_erased":
		var node: Node2D = op["node"]
		var tile: Vector2i = op["tile"]
		if is_instance_valid(node):
			objects_container.remove_child(node)
			if placed_items.has(tile):
				placed_items[tile].erase(node)
	_update_status()

func save_city(path: String = "user://city_layout.json") -> bool:
	var save_data: Dictionary = {
		"version": 1,
		"night_mode": night_mode,
		"tiles": [],
		"objects": []
	}
	for cell in tilemap.get_used_cells():
		save_data["tiles"].append({
			"pos": [cell.x, cell.y],
			"source": tilemap.get_cell_source_id(cell),
			"atlas": [tilemap.get_cell_atlas_coords(cell).x, tilemap.get_cell_atlas_coords(cell).y]
		})
	for child in objects_container.get_children():
		if child != player_character and (child is IsoObject or child is IsoCharacter):
			save_data["objects"].append({
				"id": child.item_id,
				"grid_pos": [child.grid_pos.x, child.grid_pos.y],
				"direction": child.direction,
				"elevation": child.elevation,
				"action": child.action
			})
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(save_data, "\t"))
		f.close()
		_show_message("Saved city layout to %s" % path)
		return true
	_show_message("Could not save city: %s" % error_string(FileAccess.get_open_error()))
	return false

func load_city(path: String = "user://city_layout.json") -> bool:
	if not FileAccess.file_exists(path):
		_show_message("No save file found at %s" % path)
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		_show_message("Could not open city file")
		return false
	var json_res: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	# Validate everything before clearing the current city.
	if not _valid_city_data(json_res):
		_show_message("Invalid city file; current city kept")
		return false
	clear_placed_objects()
	if player_character:
		player_character.free()
		player_character = null
		if editor_mode == "explore":
			toggle_mode()
	var saved_night: bool = json_res.get("night_mode", false)
	if saved_night != night_mode:
		toggle_day_night()
	tilemap.clear()
	for t in json_res["tiles"]:
		var cell := Vector2i(t["pos"][0], t["pos"][1])
		tilemap.set_cell(cell, int(t["source"]), Vector2i(t["atlas"][0], t["atlas"][1]))
	for o in json_res["objects"]:
		var tile := Vector2i(o["grid_pos"][0], o["grid_pos"][1])
		place_object_at(tile, o["id"], o, false)
	_show_message("Loaded city from %s" % path)
	return true

func _number_pair(value: Variant) -> bool:
	return value is Array and value.size() == 2 and (value[0] is float or value[0] is int) and (value[1] is float or value[1] is int)

func _valid_city_data(data: Variant) -> bool:
	if not data is Dictionary or not data.get("tiles") is Array or not data.get("objects") is Array:
		return false
	if data.get("version", 1) != 1 or not data.get("night_mode", false) is bool:
		return false
	for t in data["tiles"]:
		if not t is Dictionary or not _number_pair(t.get("pos")) or not _number_pair(t.get("atlas")):
			return false
		var source: int = int(t.get("source", -1))
		if not tilemap.tile_set.has_source(source):
			return false
		var atlas: TileSetAtlasSource = tilemap.tile_set.get_source(source) as TileSetAtlasSource
		if not atlas or not atlas.has_tile(Vector2i(t["atlas"][0], t["atlas"][1])):
			return false
	for o in data["objects"]:
		if not o is Dictionary or not o.get("id") is String or not _number_pair(o.get("grid_pos")):
			return false
		if Catalog.get_item(o["id"]).is_empty():
			return false
		if not o.get("direction", "SE") is String or not o.get("action", "idle") is String:
			return false
		if not (o.get("elevation", 0) is int or o.get("elevation", 0) is float):
			return false
	return true

func _show_message(message: String) -> void:
	status_message = message
	status_message_until = Time.get_ticks_msec() + 4000
	_update_status()

func _generate_starter_map() -> void:
	if tilemap.get_used_cells().size() > 0:
		return
		
	var grass_coords: Vector2i = Vector2i(1, 4)
	var road_coords: Vector2i = Vector2i(0, 0)
	var road_line_coords: Vector2i = Vector2i(5, 0)
	var sidewalk_coords: Vector2i = Vector2i(6, 2)
	
	# Create a 24x24 green landscape
	for i in range(-12, 12):
		for j in range(-12, 12):
			tilemap.set_cell(Vector2i(i, j), 0, grass_coords)
			
	# Create a road running along axis i from -12 to 11 at j in [-1, 0, 1]
	for i in range(-12, 12):
		tilemap.set_cell(Vector2i(i, -2), 0, sidewalk_coords)
		tilemap.set_cell(Vector2i(i, -1), 0, road_coords)
		tilemap.set_cell(Vector2i(i, 0), 0, road_line_coords)
		tilemap.set_cell(Vector2i(i, 1), 0, road_coords)
		tilemap.set_cell(Vector2i(i, 2), 0, sidewalk_coords)
		
	# Animate a canal / water channel on the right
	for j in range(-12, 12):
		tilemap.set_cell(Vector2i(8, j), 1, Vector2i(0, 0))
		tilemap.set_cell(Vector2i(9, j), 1, Vector2i(0, 0))
		
	# Place starter demo buildings and objects
	call_deferred("place_object_at", Vector2i(-8, -6), "Coffee_Shop")
	call_deferred("place_object_at", Vector2i(-3, -6), "Apartment_Building")
	call_deferred("place_object_at", Vector2i(3, -6), "Bakery")
	call_deferred("place_object_at", Vector2i(-5, -2), "Street_Light")
	call_deferred("place_object_at", Vector2i(1, -2), "Street_Light")
	call_deferred("place_object_at", Vector2i(-1, 1), "Sedan_Red", {"direction": "SE"})
	call_deferred("place_object_at", Vector2i(5, -1), "Taxi", {"direction": "NW"})
	call_deferred("place_object_at", Vector2i(-7, 4), "Tree_Oak")
	call_deferred("place_object_at", Vector2i(-4, 5), "Park_Bench")
	call_deferred("place_object_at", Vector2i(0, 6), "Tree_Cherry_Blossom")
	call_deferred("place_object_at", Vector2i(3, 4), "Fountain")
	call_deferred("place_object_at", Vector2i(8, 0), "bridge")

func _update_status() -> void:
	if not status_label or not objects_container:
		return
	if Time.get_ticks_msec() < status_message_until:
		status_label.text = status_message
		return
	var total_objects: int = objects_container.get_child_count()
	var item_str: String = active_item_id if not active_item_id.is_empty() else "None"
	if editor_mode == "explore":
		status_label.text = "EXPLORE MODE: WASD / Arrows to Walk | X to Recover | Space to Return to Build Mode"
	else:
		status_label.text = "Tile: (%d, %d) | Elev: %d | Placed: %d | Active: %s (%s) | [Space] Walk [R] Rotate [N] Night [Ctrl+Z] Undo" % [
			hovered_tile.x, hovered_tile.y, current_elevation, total_objects, item_str, current_dir
		]
