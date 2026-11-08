extends "res://scripts/builder/interface.gd"

const Library = preload("res://scripts/builder/asset_library.gd")
const Document = preload("res://scripts/builder/document.gd")
const Templates = preload("res://scripts/builder/templates.gd")
const Builder2D = preload("res://scripts/builder/world_2d.gd")
const Builder3D = preload("res://scripts/builder/world_3d.gd")
const Exporter = preload("res://scripts/builder/exporter.gd")
const TileRotation = preload("res://scripts/iso_tile_rotation.gd")

var library := Library.new()
var documents: Dictionary = {}
var worlds: Dictionary = {}
var mode: String = "2d"
var tool: String = "place"
var asset_id: String = ""
var selected_uid: String = ""
var selected_cell: Variant = null
var direction: String = "SE"
var favorites: Array = []
var page: int = 0
var walking: bool = false
var updating_controls: bool = false
var stroke: bool = false
var moved_selection: bool = false
var selection_press := Vector2.ZERO
var selection_origin: Array = []
var stroke_cells: Dictionary = {}
var panning: bool = false
var orbiting: bool = false
var dirty: bool = false
var autosave_pending: bool = false
var project_path: String = ""
var file_action: String = ""
var thumbnail_size: int = 128
var pack_filter: String = ""
var storage_enabled: bool = not "--test" in OS.get_cmdline_user_args()

func _ready() -> void:
	build_interface()
	get_window().min_size = Vector2i(960, 640)
	for key in ["2d", "3d"]:
		var document := Document.new()
		document.data = Templates.make(key, "city")
		documents[key] = document
	worlds["2d"] = Builder2D.new()
	worlds["3d"] = Builder3D.new()
	for world in worlds.values():
		world.library = library
		viewport.add_child(world)
	if storage_enabled:
		DirAccess.make_dir_recursive_absolute("res://creations")
		var settings: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://studio_favorites.json")) if FileAccess.file_exists("user://studio_favorites.json") else []
		if settings is Array:
			favorites = settings
		var recovery: String = startup_recovery_path()
		if not recovery.is_empty(): load_project(recovery)
	command.connect(_command)
	canvas.gui_input.connect(_canvas_input)
	canvas.asset_dropped.connect(drop_asset)
	file_dialog.file_selected.connect(_file_selected)
	var timer := Timer.new()
	timer.wait_time = 5
	timer.autostart = true
	timer.timeout.connect(func():
		if autosave_pending and storage_enabled:
			if autosave():
				autosave_pending = false
	)
	add_child(timer)
	get_tree().auto_accept_quit = false
	refresh_worlds()
	worlds["2d"].reset_camera()
	worlds["3d"].reset_camera()
	switch_mode(mode)
	status.text = "Welcome! Start with a template, or choose an asset and click the canvas. Your work autosaves."
	# Container sizes settle after _ready; fitting earlier can shrink the world to a dot.
	await get_tree().process_frame
	await get_tree().process_frame
	for key in worlds:
		worlds[key].reset_camera(documents[key].data.get("template", "city"))
	DisplayServer.window_set_title("IsoCity Studio v" + STUDIO_VERSION + " · " + current().data["title"])

func current() -> RefCounted:
	return documents[mode]

func startup_recovery_path() -> String:
	return "user://studio_autosave.json" if FileAccess.file_exists("user://studio_autosave.json") else ""

func autosave() -> bool:
	return write_project("user://studio_autosave.json",false)

func drop_asset(id: String, at: Vector2) -> void:
	if not library.assets.has(id):
		return
	select_asset(id)
	current().checkpoint()
	stroke_cells.clear()
	paint(at)
	clear_placement()
	status.text = "Placed %s. Choose another asset to place more." % library.assets[id]["name"]

func clear_placement() -> void:
	asset_id = ""
	selected_uid = ""
	selected_cell = null
	stroke = false
	moved_selection = false
	stroke_cells.clear()
	set_tool("select")
	worlds[mode].preview("", [0, 0, 0], "", 1.0, false)
	refresh_controls()

func finish_stroke() -> void:
	if not stroke:
		return
	stroke = false
	if tool == "place" and not asset_id.is_empty() and not repeat_input.button_pressed:
		var placed_name: String = library.assets[asset_id]["name"]
		clear_placement()
		status.text = "Placed %s. Choose another asset to place more." % placed_name

func refresh_worlds() -> void:
	for key in worlds:
		worlds[key].apply(documents[key].data)

func selected_tile() -> Dictionary:
	if mode != "2d" or not selected_cell is Vector2i:
		return {}
	for tile in current().data["tiles"]:
		if tile["cell"] == [selected_cell.x, selected_cell.y]:
			return tile
	return {}

func switch_mode(value: String) -> void:
	if walking:
		set_walking(false)
	mode = value
	asset_id = ""
	selected_uid = ""
	selected_cell = null
	for key in worlds:
		worlds[key].visible = key == mode
	worlds["2d"].camera.enabled = mode == "2d"
	dimension.select(0 if mode == "2d" else 1)
	brush_input.editable = mode == "2d"
	populate_categories()
	for index in category.item_count:
		if category.get_item_text(index) == ("Buildings" if mode == "2d" else "City"):
			category.select(index)
	template_choice.select(["city", "room", "blank"].find(current().data.get("template", "city")))
	search.text = ""
	page = 0
	set_tool("place")
	refresh_library()
	refresh_controls()

func refresh_library() -> void:
	for child in cards.get_children():
		cards.remove_child(child)
		child.queue_free()
	var matches: Array[Dictionary] = library_matches()
	var pages: int = maxi(1, ceili(matches.size() / 30.0))
	page = clampi(page, 0, pages - 1)
	asset_count.text = "%d assets · click ★ to keep a favorite" % matches.size()
	page_label.text = "%d / %d" % [page + 1, pages]
	for index in range(page * 30, mini((page + 1) * 30, matches.size())):
		var asset: Dictionary = matches[index]
		var card := Button.new()
		card.set_script(preload("res://scripts/builder/asset_card.gd"))
		card.asset_id = asset["id"]
		card.preview_texture = library.icon(asset["id"])
		card.custom_minimum_size = Vector2(thumbnail_size, thumbnail_size+17)
		card.clip_contents = true
		card.focus_mode = Control.FOCUS_ALL
		card.tooltip_text = asset["name"] + " · " + asset["mode"].to_upper() + " · " + asset["category"] + "\nClick to choose, or drag onto either world's canvas."
		card.pressed.connect(func(): select_asset(asset["id"]))
		cards.add_child(card)
		var image := TextureRect.new()
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.texture = card.preview_texture
		image.position = Vector2(10, 8)
		image.size = Vector2(thumbnail_size-20, thumbnail_size-28)
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(image)
		card.artwork = image
		var name_label := Label.new()
		name_label.text = card_name(asset)
		name_label.position = Vector2(8, thumbnail_size-18)
		name_label.size = Vector2(thumbnail_size-16, 30)
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(name_label)
		card.caption = name_label
		var capabilities := Label.new()
		capabilities.text=library.capabilities.compact(asset["id"])
		capabilities.add_theme_font_size_override("font_size",12)
		capabilities.mouse_filter=Control.MOUSE_FILTER_IGNORE
		capabilities.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		capabilities.clip_text=true
		card.add_child(capabilities);card.capability_note=capabilities
		card.tooltip_text+="\n"+library.capabilities.describe(asset["id"],library)
		var favorite := Button.new()
		favorite.text = "★" if favorites.has(asset["id"]) else "☆"
		favorite.position = Vector2(thumbnail_size-36, 2)
		favorite.size = Vector2(32, 30)
		favorite.add_theme_font_size_override("font_size", 15)
		favorite.tooltip_text = "Keep / remove favorite"
		favorite.pressed.connect(func(): toggle_favorite(asset["id"]))
		card.add_child(favorite)
		card.favorite_button = favorite
		card.reflow(thumbnail_size)

func library_matches() -> Array[Dictionary]:
	return library.find(library_mode(), category.get_item_text(maxi(0, category.selected)), search.text, favorites, favorites_only.button_pressed,pack_filter)

func card_name(asset: Dictionary) -> String:
	return asset["name"]

func toggle_favorite(id: String) -> void:
	if favorites.has(id):
		favorites.erase(id)
	else:
		favorites.append(id)
	if storage_enabled:
		var file := FileAccess.open("user://studio_favorites.json", FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(favorites))
	refresh_library()

func library_mode() -> String:
	return ["all", "2d", "3d", "added"][asset_type.selected]

func populate_categories() -> void:
	category.clear()
	category.add_item("All assets")
	for text in library.categories(library_mode()): category.add_item(text)

func select_asset(id: String) -> void:
	if not library.assets.has(id):
		return
	library.families.remember(library.assets[id])
	if walking:
		set_walking(false)
	asset_id = id
	selected_uid = ""
	selected_cell = null
	direction = str(library.directions(id)[0])
	updating_controls = true
	height_input.value = 0
	scale_input.value = float(library.assets[id]["data"].get("default_scale", 1.0))
	updating_controls = false
	set_tool("place")
	refresh_controls()
	status.text = "Ready to place %s. R rotates. Enable Repeat placement to keep it active." % library.assets[id]["name"]

func set_tool(value: String) -> void:
	tool = value
	for key in tools:
		tools[key].button_pressed = key == value

func refresh_controls() -> void:
	updating_controls = true
	title_input.text = current().data["title"]
	var item: Dictionary = current().object(selected_uid)
	var tile: Dictionary = selected_tile()
	var id: String = tile.get("asset", item.get("asset", asset_id))
	if library.assets.has(id):
		asset_picture.texture = library.icon(id)
		asset_picture.material = TileRotation.material_for(direction) if library.is_ground_tile(id) else null
		selected_name.text = library.assets[id]["name"]
		selection_note.text = ("Ground tile · rotate or remove" if not tile.is_empty() else ("Editing placed object" if not item.is_empty() else "Ready to place")) + " · " + library.assets[id]["category"]
	else:
		asset_picture.texture = null
		asset_picture.material = null
		selected_name.text = "Choose an asset"
		selection_note.text = "Pick a card from your library, or select an object in the canvas."
	if not item.is_empty():
		direction = item["direction"]
		height_input.set_value_no_signal(item["position"][2 if mode == "2d" else 1])
		scale_input.set_value_no_signal(item["scale"])
	if not tile.is_empty():
		direction = tile.get("direction", "SE")
	if library.is_ground_tile(id):
		asset_picture.material = TileRotation.material_for(direction)
	height_input.editable = tile.is_empty() and (mode == "3d" or not worlds["2d"].tile_lookup.has(id))
	scale_input.editable = height_input.editable
	var choices: Array = library.directions(id)
	rotation_button.disabled = choices.size() < 2
	rotation_button.text = "Rotate ↻ · " + direction if choices.size() > 1 else ("Rotate ↻" if id.is_empty() else "Single view")
	rotation_button.tooltip_text = "Cycle the available directions · R" if choices.size() > 1 else ("Choose an asset or select a placed tile first." if id.is_empty() else "This asset has only one supplied view.")
	undo_button.disabled = current().undo_history.is_empty()
	redo_button.disabled = current().redo_history.is_empty()
	worlds[mode].show_selection(selected_uid)
	if not tile.is_empty():
		worlds[mode].show_tile_selection(selected_cell)
	updating_controls = false

func changed() -> void:
	dirty = true
	autosave_pending = true
	worlds[mode].apply(current().data)
	refresh_controls()
	DisplayServer.window_set_title("IsoCity Studio v" + STUDIO_VERSION + " · " + current().data["title"] + " *")

func _command(action: String, value: Variant) -> void:
	match action:
		"asset_type":
			populate_categories()
			page = 0
			refresh_library()
		"dimension": switch_mode("2d" if value == 0 else "3d")
		"filter":
			page = 0
			refresh_library()
		"page":
			page += int(value)
			refresh_library()
		"tool":
			set_walking(false)
			set_tool(value)
		"title":
			if not updating_controls:
				current().data["title"] = value
				dirty = true
				autosave_pending = true
		"undo", "redo":
			if current().call(action):
				selected_uid = ""
				selected_cell = null
				changed()
		"home": worlds[mode].reset_camera("room" if template_choice.selected == 1 else "city")
		"walk": set_walking(not walking)
		"night":
			current().checkpoint()
			current().data["night"] = not current().data["night"]
			changed()
		"template":
			set_walking(false)
			current().checkpoint()
			current().data = Templates.make(mode, ["city", "room", "blank"][template_choice.selected])
			selected_uid = ""
			selected_cell = null
			changed()
			worlds[mode].reset_camera(["city", "room", "blank"][template_choice.selected])
			status.text = "Template opened. Make it yours! Undo restores your previous layout."
		"height", "scale":
			if not updating_controls and not current().object(selected_uid).is_empty():
				current().checkpoint()
				var item: Dictionary = current().object(selected_uid)
				if action == "height":
					item["position"][2 if mode == "2d" else 1] = float(value)
				else:
					item["scale"] = float(value)
				changed()
		"rotate": rotate_selection()
		"duplicate": duplicate_selection()
		"remove":
			if not selected_tile().is_empty():
				current().checkpoint()
				current().data["tiles"].erase(selected_tile())
				selected_cell = null
				changed()
			elif not current().object(selected_uid).is_empty():
				current().checkpoint()
				current().data["objects"].erase(current().object(selected_uid))
				selected_uid = ""
				changed()
		"save", "open", "export": show_file_dialog(action)

func rotate_selection() -> void:
	var item: Dictionary = current().object(selected_uid)
	var tile: Dictionary = selected_tile()
	var id: String = tile.get("asset", item.get("asset", asset_id))
	if not library.assets.has(id):
		return
	var choices: Array = library.directions(id)
	if choices.size() < 2:
		status.text = "This asset has only one supplied view."
		return
	direction = str(choices[(choices.find(direction) + 1) % choices.size()])
	if not tile.is_empty():
		current().checkpoint()
		tile["direction"] = direction
		changed()
	elif not item.is_empty():
		current().checkpoint()
		item["direction"] = direction
		changed()
	refresh_controls()
	status.text = "Direction: " + direction

func duplicate_selection() -> void:
	var item: Dictionary = current().object(selected_uid)
	if item.is_empty():
		status.text = "Use Select / move, then click an object to duplicate it."
		return
	current().checkpoint()
	var position_values: Array = item["position"].duplicate()
	position_values[0] += 16 if mode == "2d" else 1
	if mode == "2d":
		position_values[1] += 8
	var copy: Dictionary = current().add(item["asset"], position_values, item["direction"], item["scale"])
	var copied: Dictionary=preload("res://scripts/builder/owned_room_copy.gd").item(item,copy["uid"],position_values)
	copy.clear();copy.merge(copied,true)
	selected_uid = copy["uid"]
	changed()

func set_walking(enabled: bool) -> void:
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus:
		focus.release_focus()
	walking = enabled
	walk_button.button_pressed = enabled
	walk_button.text = "Back to building" if enabled else "Walk around"
	worlds[mode].walk(enabled)
	status.text = "WASD / arrows to walk. Space jumps in 3D. X recovers your position. Tab returns to building." if enabled else "Building camera · WASD to pan, middle-drag to pan, wheel to zoom."

func paint(at: Vector2) -> void:
	if asset_id.is_empty():
		status.text = "Choose an asset from the library first."
		return
	var position_values: Array = worlds[mode].point(at, snap_input.button_pressed, height_input.value)
	var key: String = str(position_values) + ":" + direction
	if stroke_cells.has(key):
		return
	stroke_cells[key] = true
	if mode == "2d" and worlds[mode].tile_lookup.has(asset_id):
		var cell: Vector2i = IsoMath.world_to_tile(Vector2(position_values[0], position_values[1]))
		var radius: int = int(brush_input.value) / 2
		for x in range(cell.x - radius, cell.x + radius + 1):
			for y in range(cell.y - radius, cell.y + radius + 1):
				var replaced: bool = false
				for tile in current().data["tiles"]:
					if tile["cell"] == [x, y]:
						tile["asset"] = asset_id
						tile["direction"] = direction
						replaced = true
						break
				if not replaced:
					current().data["tiles"].append({"cell": [x, y], "asset": asset_id, "direction": direction})
	else:
		current().add(asset_id, position_values, direction, scale_input.value)
	changed()

func erase(at: Vector2) -> void:
	var uid: String = worlds[mode].pick(at)
	if not uid.is_empty():
		current().data["objects"].erase(current().object(uid))
		selected_uid = ""
	elif mode == "2d":
		var point_values: Array = worlds[mode].point(at, true, 0)
		var cell: Vector2i = IsoMath.world_to_tile(Vector2(point_values[0], point_values[1]))
		for tile in current().data["tiles"].duplicate():
			if tile["cell"] == [cell.x, cell.y]:
				current().data["tiles"].erase(tile)
	changed()

func _canvas_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			panning = event.pressed
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			orbiting = event.pressed and mode == "3d"
			panning = event.pressed and mode == "2d"
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var factor: float = 1.12 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12
			if mode == "2d":
				worlds[mode].camera.zoom = (worlds[mode].camera.zoom * factor).clamp(Vector2.ONE * (0.1 if worlds[mode].detail_view_active else 0.4), Vector2.ONE * (64 if worlds[mode].detail_view_active else 7))
			else:
				worlds[mode].distance = clampf(worlds[mode].distance / factor, .08 if worlds[mode].detail_view_active else 5, 120)
		elif event.button_index == MOUSE_BUTTON_LEFT and not walking:
			var focus: Control = get_viewport().gui_get_focus_owner()
			if focus:
				focus.release_focus()
			if not event.pressed:
				finish_stroke()
				return
			stroke = true
			stroke_cells.clear()
			moved_selection = false
			if tool == "select":
				selected_uid = worlds[mode].pick(event.position)
				selected_cell = null
				if selected_uid.is_empty() and mode == "2d":
					var location: Array = worlds[mode].point(event.position, true, 0)
					selected_cell = IsoMath.world_to_tile(Vector2(location[0], location[1]))
				selection_press = event.position
				selection_origin = current().object(selected_uid).get("position", []).duplicate()
				refresh_controls()
			else:
				current().checkpoint()
				if tool == "place":
					paint(event.position)
				else:
					erase(event.position)
	elif event is InputEventMouseMotion:
		if panning:
			if mode == "2d":
				worlds[mode].camera.position -= event.relative / worlds[mode].camera.zoom
			else:
				worlds[mode].target -= (worlds[mode].camera.basis.x * event.relative.x - Vector3(worlds[mode].camera.basis.z.x, 0, worlds[mode].camera.basis.z.z) * event.relative.y) * worlds[mode].distance / maxf(canvas.size.y, 1)
		if orbiting:
			worlds[mode].yaw -= event.relative.x * 0.4
			worlds[mode].pitch = clampf(worlds[mode].pitch + event.relative.y * 0.3, 15, 80)
		if stroke and not walking:
			if tool == "place":
				paint(event.position)
			elif tool == "erase":
				erase(event.position)
			elif not current().object(selected_uid).is_empty():
				if not moved_selection:
					if event.position.distance_to(selection_press) < 6.0:
						return
					current().checkpoint()
					moved_selection = true
				var item: Dictionary = current().object(selected_uid)
				var press_point: Array = worlds[mode].point(selection_press, snap_input.button_pressed, height_input.value)
				var drag_point: Array = worlds[mode].point(event.position, snap_input.button_pressed, height_input.value)
				item["position"] = [selection_origin[0] + drag_point[0] - press_point[0],
					selection_origin[1] + drag_point[1] - press_point[1], selection_origin[2] + drag_point[2] - press_point[2]]
				changed()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		if not get_viewport().gui_get_focus_owner() is LineEdit and not file_dialog.visible:
			set_walking(not walking)
			get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			finish_stroke()
		if event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			panning = false
			orbiting = false

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.ctrl_pressed:
		match event.keycode:
			KEY_Z: _command("undo", null)
			KEY_Y: _command("redo", null)
			KEY_D: duplicate_selection()
			KEY_S: show_file_dialog("save")
	else:
		match event.keycode:
			KEY_R: rotate_selection()
			KEY_DELETE: _command("remove", null)
			KEY_TAB: set_walking(not walking)
			KEY_ESCAPE:
				if walking:
					set_walking(false)
				else:
					asset_id = ""
					selected_uid = ""
					selected_cell = null
					refresh_controls()

func show_grid() -> bool:
	return snap_input.button_pressed and not walking and not preload("res://scripts/builder/terrain_plan.gd").settings(current().data)["enabled"]

func pointer_in_canvas() -> bool:
	return canvas.get_global_rect().has_point(get_global_mouse_position())

func _process(delta: float) -> void:
	if worlds.is_empty():
		return
	if worlds[mode].exploration.photo and worlds[mode].exploration.photo.active:
		if mode=="3d": worlds[mode].player.active=false
		else: worlds[mode].player.is_player_controlled=false
		return
	var text_focused: bool = get_viewport().gui_get_focus_owner() is LineEdit or get_viewport().gui_get_focus_owner() is TextEdit or file_dialog.visible
	var inside: bool = pointer_in_canvas() and not file_dialog.visible
	worlds[mode].grid.visible = show_grid()
	if mode == "3d":
		worlds[mode].player.active = walking and not text_focused and worlds[mode].terrain_traversal.walk_allowed() and worlds[mode].exploration.walk_allowed()
		worlds[mode].update_camera()
	else:
		worlds[mode].player.is_player_controlled = walking and not text_focused and worlds[mode].terrain_traversal.walk_allowed() and worlds[mode].exploration.walk_allowed()
		if walking:
			var foot: Vector2=worlds[mode].player.position+Vector2(0,-(float(worlds[mode].player.get_meta("terrain_height",0))+float(worlds[mode].player.get_meta("floor_travel_height",0)))*8)
			worlds[mode].camera.position = worlds[mode].camera.position.lerp(foot, minf(delta * 10, 1))
	if not walking and not text_focused:
		var movement: Vector2 = camera_movement()
		if mode == "2d":
			worlds[mode].camera.position += movement * delta * 300 / worlds[mode].camera.zoom.x
		else:
			var direction_vector: Vector3 = worlds[mode].camera.basis.x * movement.x + worlds[mode].camera.basis.z * movement.y
			direction_vector.y = 0
			worlds[mode].target += direction_vector * delta * (minf(25,worlds[mode].distance) if worlds[mode].detail_view_active else 25)
	var position_values: Array = worlds[mode].point(canvas.get_local_mouse_position(), snap_input.button_pressed, height_input.value)
	worlds[mode].preview(asset_id, position_values, direction, scale_input.value, inside and tool == "place" and not walking)

func camera_movement() -> Vector2:
	return Vector2(float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))-float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))-float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))

func session_data() -> Dictionary:
	return {"version": 1, "grid_version": 2, "active_mode": mode, "documents": {"2d": documents["2d"].data, "3d": documents["3d"].data}}

func write_project(path: String, report: bool = true) -> bool:
	var temporary: String = path + "." + str(Time.get_ticks_usec()) + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if not file:
		if report:
			status.text = "Could not save. Choose a writable folder."
		return false
	file.store_string(JSON.stringify(session_data(), "\t"))
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error == OK:
		error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		DirAccess.remove_absolute(temporary)
		if report:
			status.text = "Save failed: " + error_string(error)
		return false
	if report:
		project_path = path
		dirty = false
		status.text = "Saved both layouts to " + path
		DisplayServer.window_set_title("IsoCity Studio v" + STUDIO_VERSION + " · " + current().data["title"])
	return true

func load_project(path: String, prepared: Dictionary = {}) -> bool:
	if not FileAccess.file_exists(path):
		status.text = "Project file was not found. Your current work is unchanged."
		return false
	var content: Variant = prepared
	if prepared.is_empty():
		var parser := JSON.new()
		if parser.parse(FileAccess.get_file_as_string(path)) != OK:
			status.text = "The project JSON could not be read. Current work was preserved."
			return false
		content = parser.data
	if not content is Dictionary or content.get("version") != 1 or not content.get("documents") is Dictionary:
		status.text = "This is not a Studio project. Your current work is unchanged."
		return false
	for key in ["2d", "3d"]:
		if not Document.valid(content["documents"].get(key), key, library):
			status.text = "The project contains invalid or unavailable assets. Your current work is unchanged."
			return false
	var before_grid: Dictionary = content.duplicate(true)
	var grid_changes: int = preload("res://scripts/builder/grid_migration.gd").apply(content, library)
	if grid_changes > 0 and storage_enabled:
		preload("res://scripts/builder/project_store.gd").snapshot(before_grid, "Before library grid alignment", null, true, path)
	var upgraded: bool = grid_changes > 0
	for key in ["2d", "3d"]:
		documents[key].checkpoint()
		documents[key].data = Document.normalize(content["documents"][key])
		upgraded = Templates.upgrade_road_layout(documents[key].data) or upgraded
	mode = "3d" if content.get("active_mode") == "3d" else "2d"
	refresh_worlds()
	if is_node_ready():
		switch_mode(mode)
	project_path = "" if path == "user://studio_autosave.json" else path
	dirty = upgraded
	autosave_pending = upgraded
	status.text = "Opened " + path + (" · updated grid anchors with ground contacts preserved" if grid_changes > 0 else (" · updated untouched starter traffic to its lanes" if upgraded else ""))
	return true

func show_file_dialog(action: String) -> void:
	file_action = action
	if action == "save" and not project_path.is_empty():
		write_project(project_path)
		return
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE if action == "open" else FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.filters = PackedStringArray(["*.tscn ; Godot scene"]) if action == "export" else PackedStringArray(["*.json ; IsoCity Studio project"])
	file_dialog.title = {"save": "Save both Studio layouts", "open": "Open a Studio project", "export": "Export the current layout as a Godot scene"}[action]
	file_dialog.current_dir = ProjectSettings.globalize_path("res://creations")
	file_dialog.current_file = "" if action == "open" else current().data["title"].validate_filename() + ("_" + mode + ".tscn" if action == "export" else ".isocity.json")
	file_dialog.popup_centered()

func _file_selected(path: String) -> void:
	if file_action == "open":
		load_project(path)
	elif file_action == "save":
		write_project(path if path.ends_with(".json") else path + ".json")
	else:
		var result: Error = Exporter.save_scene(worlds[mode], current().data, library, path if path.ends_with(".tscn") else path + ".tscn")
		status.text = "Scene exported. Open it in this Godot project and press F6. Tab switches walk / camera." if result == OK else "Export failed: " + error_string(result)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if storage_enabled and not documents.is_empty():
			autosave()
		get_tree().quit()
