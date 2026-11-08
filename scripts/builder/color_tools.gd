extends RefCounted

const Parts = preload("res://scripts/builder/part_colors.gd")
const Selection = preload("res://scripts/builder/piece_selection.gd")
const Patterns = preload("res://scripts/builder/tile_patterns.gd")
var studio: Control
var tabs: TabContainer
var panel: VBoxContainer
var mode: OptionButton
var tolerance: SpinBox
var picker: ColorPickerButton
var note: Label
var preview: TextureRect
var selection: Dictionary = {}
var base_selection: Dictionary = {}
var expansion: SpinBox
var protect_visible: CheckBox
var tile_transform := Transform2D.IDENTITY
var tile_rect := Rect2()
var tile_sprite_frame: Vector2i
var tile_texture_size: Vector2i
var tile_angle_value: float = 0
var tile_grid_frame: int = 0
var guarded_uid: String = ""
var guarded_cell: Variant = null
var guarded_asset: String = ""
var selected_uid: String = ""
var selected_cell: Variant = null
var selected_mode: String = ""
var page: ScrollContainer
var tile_source: Dictionary = {}
var tile_name: Label
var tile_preview: TextureRect
var tile_size: SpinBox
var tile_angle: SpinBox
var tile_x: SpinBox
var tile_y: SpinBox
var tile_projection: OptionButton
var tile_dialog: AcceptDialog
var tile_search: LineEdit
var tile_list: ItemList
var tile_all: CheckBox

func _init(host: Control, inspector_tabs: TabContainer) -> void:
	studio = host
	tabs = inspector_tabs
	page = ScrollContainer.new()
	page.name = "Colors"
	page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(page)
	panel = VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(panel)
	var intro: Label = studio.label(panel, "Pick a piece, then choose its color", 13)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var choose := Button.new()
	choose.text = "Pick piece on canvas"
	choose.pressed.connect(func(): studio._command("tool", "color"); tabs.current_tab = page.get_index())
	panel.add_child(choose)
	mode = OptionButton.new()
	mode.add_item("Connected piece / region")
	mode.add_item("Single triangle / pixel")
	panel.add_child(mode)
	studio.label(panel, "Expand / shrink selection · border rings", 12)
	expansion = studio.spin(panel, -8, 8, 1, 0)
	expansion.value_changed.connect(func(_value: float): update_selection())
	protect_visible = CheckBox.new()
	protect_visible.text = "Protect visible surfaces"
	protect_visible.button_pressed = true
	protect_visible.tooltip_text = "Visible protected objects block picks. Selection masks exclude hidden pixels and faces, and are checked again when applying paint."
	panel.add_child(protect_visible)
	protect_visible.toggled.connect(func(_value: bool): update_selection())
	studio.label(panel, "Color tolerance · lower is finer", 12)
	tolerance = studio.spin(panel, 0, 100, 1, 8)
	tolerance.suffix = "%"
	note = studio.label(panel, "Click the roof, body panel, wall, or other area you want to change.", 12)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview = TextureRect.new()
	preview.custom_minimum_size = Vector2(180, 140)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	panel.add_child(preview)
	picker = ColorPickerButton.new()
	picker.color = Color("35bdb0")
	picker.edit_alpha = false
	picker.custom_minimum_size.y = 40
	panel.add_child(picker)
	var apply_button := Button.new()
	apply_button.text = "Apply color to selected piece"
	apply_button.pressed.connect(apply_color)
	panel.add_child(apply_button)
	panel.add_child(HSeparator.new())
	studio.label(panel, "Paint with a 2D tile", 14)
	tile_name = studio.label(panel, "Choose a tile or artwork source", 12)
	tile_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var source_button := Button.new()
	source_button.text = "Choose tile…"
	source_button.pressed.connect(open_tiles)
	panel.add_child(source_button)
	tile_preview = TextureRect.new()
	tile_preview.custom_minimum_size = Vector2(100, 75)
	tile_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tile_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	panel.add_child(tile_preview)
	studio.label(panel, "Tile size · 32 px / 1 model unit", 12)
	tile_size = studio.spin(panel, 0.05, 64, 0.05, 1)
	studio.label(panel, "Tile rotation", 12)
	tile_angle = studio.spin(panel, -360, 360, 1, 0)
	studio.label(panel, "Tile offset X / Y", 12)
	tile_x = studio.spin(panel, -100, 100, 0.05, 0)
	tile_y = studio.spin(panel, -100, 100, 0.05, 0)
	studio.label(panel, "Sprite surface · models map by face", 12)
	tile_projection = OptionButton.new()
	for text in ["Artwork", "Roof", "Left wall", "Right wall"]: tile_projection.add_item(text)
	panel.add_child(tile_projection)
	var paint_tile := Button.new()
	paint_tile.text = "Apply tile to selected piece"
	paint_tile.pressed.connect(apply_tile)
	panel.add_child(paint_tile)
	var reset_button := Button.new()
	reset_button.text = "Restore original appearance"
	reset_button.pressed.connect(reset_colors)
	panel.add_child(reset_button)
	var help: Label = studio.label(panel, "Connected selection follows touching faces or pixels of similar original color. Single mode gives exact face/pixel control. Sprite edits affect the picked view and animation frame. Ctrl+Z undoes each application.", 12)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func target() -> Dictionary:
	if studio.mode != selected_mode: return {}
	if selected_cell is Vector2i:
		for tile in studio.current().data["tiles"]:
			if tile["cell"] == [selected_cell.x, selected_cell.y]: return tile
		return {}
	return studio.current().object(selected_uid)

func pick(at: Vector2) -> void:
	selection = {}
	base_selection = {}
	selected_uid = ""
	selected_cell = null
	selected_mode = studio.mode
	var world: Node = studio.worlds[studio.mode]
	var best: float = INF
	var order: Array = world.instances.keys()
	if studio.mode == "2d": order.sort_custom(func(a: String, b: String): return draw_in_front(world.instances[a], world.instances[b]))
	for uid in order:
		var item: Dictionary = studio.current().object(uid)
		if not world.instances[uid].visible: continue
		if not protect_visible.button_pressed and not studio.Layers.editable(studio.current().data, item, studio.library): continue
		var instance: Node = world.instances[uid]
		var hit: Dictionary = pick_instance(instance, item, at, true)
		if hit.is_empty(): continue
		var distance: float = hit.get("distance", 0)
		if distance >= best: continue
		best = distance
		selection = hit
		selected_uid = uid
		if studio.mode == "2d": break
	if not selected_uid.is_empty() and not studio.Layers.editable(studio.current().data, studio.current().object(selected_uid), studio.library):
		note.text = "The visible surface is protected. Show and unlock it before painting."
		selection = {}
		selected_uid = ""
		return
	if not selected_uid.is_empty(): selection = pick_instance(world.instances[selected_uid], studio.current().object(selected_uid), at)
	if selection.is_empty() and studio.mode == "2d": pick_tile(at)
	if selection.is_empty():
		note.text = "No editable piece at that point. Try an opaque part of an unlocked object."
		return
	base_selection = selection.duplicate(true)
	guarded_uid = selected_uid
	guarded_cell = selected_cell
	guarded_asset = target().get("asset", "")
	update_selection()
	if not Selection.nonempty(selection): return
	studio.selected_uid = selected_uid
	studio.selected_uids.clear()
	if not selected_uid.is_empty(): studio.selected_uids.append(selected_uid)
	studio.selected_cell = selected_cell
	studio.refresh_controls()
	tabs.current_tab = page.get_index()
	var color: Array = selection["color"]
	picker.color = Color(color[0], color[1], color[2], 1)
	studio.status.text = "Piece selected. Choose a color in Colors, then Apply."

static func draw_in_front(a: Node2D, b: Node2D) -> bool:
	if a.z_index != b.z_index: return a.z_index > b.z_index
	if not is_equal_approx(a.position.y, b.position.y): return a.position.y > b.position.y
	return a.get_index() > b.get_index()

func update_selection() -> void:
	if base_selection.is_empty() or target().is_empty(): return
	if target().get("asset") != guarded_asset:
		selection = {}
		note.text = "This object changed. Pick its piece again."
		return
	selection = base_selection.duplicate(true)
	var temporary: Node
	var instance: Node = studio.worlds[selected_mode].instances.get(selected_uid)
	if selected_cell is Vector2i:
		temporary = load(studio.library.assets[target()["asset"]]["path"]).instantiate()
		temporary.direction = target().get("direction", "SE")
		instance = temporary
	if not instance: selection = {}; return
	if selection["kind"] == "pixels": selection = Selection.grow_pixels(selection, Parts.sprite_for(instance), int(expansion.value))
	else: selection = Selection.grow_faces(selection, Parts.model_root(instance), int(expansion.value))
	if temporary: temporary.free()
	if protect_visible.button_pressed and Selection.nonempty(selection): selection = visible_mask(selection)
	if not Selection.nonempty(selection):
		note.text = "No visible pixels or faces remain. Reduce shrink or pick a visible piece."
		preview.texture = null
	else: refresh_preview()
	studio.overlay.queue_redraw()

func usable_selection() -> Dictionary:
	if not base_selection.is_empty() and selected_uid == guarded_uid and selected_cell == guarded_cell and (target().is_empty() or target().get("asset") != guarded_asset): return {}
	var result: Dictionary = selection.duplicate(true)
	if protect_visible.button_pressed and not base_selection.is_empty() and selected_uid == guarded_uid and selected_cell == guarded_cell and Selection.nonempty(result): result = visible_mask(result)
	return result if Selection.nonempty(result) else {}

func occluders() -> Array:
	var world: Node = studio.worlds[selected_mode]
	var order: Array = world.instances.keys()
	if selected_mode == "2d": order.sort_custom(func(a: String, b: String): return draw_in_front(world.instances[a], world.instances[b]))
	var result: Array = []
	for uid in order:
		if uid == selected_uid:
			if selected_mode == "2d": break
			continue
		if not world.instances[uid].visible: continue
		result.append({"node": world.instances[uid], "item": studio.current().object(uid), "rect": pick_bounds(uid)})
	if selected_mode == "3d":
		var target_rect: Rect2 = pick_bounds(selected_uid)
		var roots: Array = [world.get_node_or_null("Foundation")]
		if world.road_node and world.road_node.visible: roots.append_array(world.road_node.get_children())
		for root in roots:
			if not root or not root.visible: continue
			var box: AABB = root.global_transform * preload("res://scripts/model_bounds.gd").get_bounds(root)
			var rect := Rect2()
			for i in 8:
				var pixel: Vector2 = world.camera.unproject_position(box.get_endpoint(i))
				rect = Rect2(pixel, Vector2.ZERO) if i == 0 else rect.expand(pixel)
			if rect.intersects(target_rect): result.append({"node": root, "rect": rect, "external": true})
	return result

func pick_bounds(uid: String) -> Rect2:
	var instance: Node = studio.worlds[selected_mode].instances.get(uid)
	if selected_mode != "3d" or not instance or not instance.has_method("mixed_bounds"): return studio.screen_bounds(uid)
	var camera: Camera3D = studio.worlds["3d"].camera
	var mesh: MeshInstance3D = instance.mesh
	var billboard: bool = not instance.ground_tile and instance.material.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED
	var right: Vector3 = camera.global_basis.x.normalized() if billboard else mesh.global_basis.x.normalized()
	var up: Vector3 = Vector3.UP if billboard else mesh.global_basis.y.normalized()
	var rect := Rect2()
	var first: bool = true
	for offset in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]:
		var point: Vector3 = mesh.global_position + right * offset.x * mesh.mesh.size.x * mesh.global_basis.x.length() + up * offset.y * mesh.mesh.size.y * mesh.global_basis.y.length()
		var pixel: Vector2 = camera.unproject_position(point)
		rect = Rect2(pixel, Vector2.ZERO) if first else rect.expand(pixel)
		first = false
	return rect

func blocked(screen: Vector2, distance: float, candidates: Array) -> bool:
	for candidate in candidates:
		if not candidate["rect"].has_point(screen): continue
		var hit: Dictionary
		if candidate.get("external", false):
			var camera: Camera3D = studio.worlds["3d"].camera
			hit = Parts.ray_pick(candidate["node"], camera.project_ray_origin(screen), camera.project_ray_normal(screen))
		else: hit = pick_instance(candidate["node"], candidate["item"], screen, true)
		if not hit.is_empty() and (selected_mode == "2d" or hit.get("distance", INF) + 0.00001 < distance): return true
	return false

func sprite_pixel_point(instance: Node3D, pixel: Vector2, edit: Dictionary) -> Vector3:
	var sprite: Sprite2D = Parts.sprite_for(instance)
	var mesh: MeshInstance3D = instance.mesh
	var uv: Vector2
	if instance.ground_tile:
		var view: Dictionary = instance.source.directions_data.get(instance.direction, instance.source.directions_data.values()[0])
		var base: Array = view.get("alignment_base", [])
		if base.size() == 3:
			var back := Vector2(base[0][0] + base[2][0] - base[1][0], base[0][1] + base[2][1] - base[1][1])
			uv = Transform2D(Vector2(base[2][0], base[2][1]) - back, Vector2(base[0][0], base[0][1]) - back, back).affine_inverse() * pixel
		else:
			uv = pixel / sprite.get_rect().size
			if instance.diamond_ground: uv = Vector2(uv.x + uv.y - 0.5, uv.y - uv.x + 0.5)
		uv = (uv - Vector2.ONE * 0.5).rotated(deg_to_rad(preload("res://scripts/iso_tile_rotation.gd").degrees(instance.direction))) + Vector2.ONE * 0.5
	else:
		var local: Vector2 = sprite.get_rect().position + pixel
		uv = (sprite.transform * local - instance.card_rect.position) / instance.card_rect.size
	var billboard: bool = not instance.ground_tile and instance.material.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED
	var right: Vector3 = studio.worlds["3d"].camera.global_basis.x.normalized() if billboard else mesh.global_basis.x.normalized()
	var up: Vector3 = Vector3.UP if billboard else mesh.global_basis.y.normalized()
	return mesh.global_position + right * (uv.x - 0.5) * mesh.mesh.size.x * mesh.global_basis.x.length() + up * (0.5 - uv.y) * mesh.mesh.size.y * mesh.global_basis.y.length()

func visible_mask(edit: Dictionary) -> Dictionary:
	var result: Dictionary = edit.duplicate(true)
	var candidates: Array = occluders()
	var instance: Node = studio.worlds[selected_mode].instances.get(selected_uid)
	if edit["kind"] == "pixels":
		var texture: Texture2D = Parts.edit_texture(edit)
		var sprite: Sprite2D = Parts.sprite_for(instance) if instance else null
		var frame_size: Vector2i = Vector2i(texture.get_width() / sprite.hframes, texture.get_height() / sprite.vframes) if sprite else tile_sprite_frame
		var frame: int = int(edit.get("frame", sprite.frame if sprite else tile_grid_frame))
		var columns: int = texture.get_width() / frame_size.x
		var origin: Vector2 = Vector2(frame % columns, frame / columns) * Vector2(frame_size)
		var kept: Array[int] = []
		for index in edit["pixels"]:
			var pixel := Vector2(int(index) % texture.get_width(), int(index) / texture.get_width()) + Vector2.ONE * 0.5 - origin
			var screen: Vector2
			var distance: float = INF
			if selected_mode == "3d":
				var point: Vector3 = sprite_pixel_point(instance, pixel, edit)
				screen = studio.worlds["3d"].camera.unproject_position(point)
				distance = studio.worlds["3d"].camera.project_ray_origin(screen).distance_squared_to(point)
			elif sprite: screen = studio.viewport.canvas_transform * (sprite.global_transform * (sprite.get_rect().position + pixel))
			else:
				var point: Vector2 = tile_rect.position + pixel
				var center: Vector2 = tile_rect.get_center()
				var offset: Vector2 = point - center
				offset.y *= 2
				offset = offset.rotated(deg_to_rad(tile_angle_value))
				offset.y *= 0.5
				screen = tile_transform * (center + offset)
			if not blocked(screen, distance, candidates): kept.append(int(index))
		result["pixels"] = kept
		return result
	if not instance: return {}
	var root: Node3D = Parts.model_root(instance)
	var mesh: MeshInstance3D = root.get_node_or_null(edit["mesh"])
	if not mesh or int(edit["surface"]) >= Parts.original_mesh(mesh).get_surface_count(): return {}
	var arrays: Array = Parts.original_mesh(mesh).surface_get_arrays(int(edit["surface"]))
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = Parts.indices_for(arrays)
	var kept: Array[int] = []
	var camera: Node = studio.worlds["3d"].camera if selected_mode == "3d" else instance
	for face in edit["faces"]:
		if int(face) * 3 + 2 >= indices.size(): continue
		var triangle: Array[Vector3] = []
		for corner in 3: triangle.append(mesh.global_transform * vertices[indices[int(face) * 3 + corner]])
		var center: Vector3 = (triangle[0] + triangle[1] + triangle[2]) / 3
		var visible: bool = true
		for point in [center, triangle[0].lerp(center, 0.05), triangle[1].lerp(center, 0.05), triangle[2].lerp(center, 0.05)]:
			var pixel: Vector2 = camera.unproject_position(point)
			var from: Vector3 = camera.project_ray_origin(pixel)
			var own: Dictionary = Parts.ray_pick(root,from,camera.project_ray_normal(pixel),selected_mode == "2d" and instance.viewport == null)
			if own.is_empty() or own["mesh"] != edit["mesh"] or own["surface"] != edit["surface"] or own["face"] != int(face): visible = false; break
			var screen: Vector2 = pixel
			if selected_mode == "2d":
				var sprite: Sprite2D = instance.get_node("Sprite2D")
				screen = studio.viewport.canvas_transform * sprite.to_global(sprite.get_rect().position + pixel / instance.projection_size() * sprite.get_rect().size)
			if blocked(screen, from.distance_squared_to(point), candidates): visible = false; break
		if visible: kept.append(int(face))
	result["faces"] = kept
	return result

func refresh_preview() -> void:
	if not Selection.nonempty(selection) or target().is_empty(): return
	note.text = ("%d triangles" % selection["faces"].size()) if selection["kind"] == "faces" else ("%d pixels · frame %d" % [selection["pixels"].size(), selection["frame"]])
	preview.texture = studio.library.directional_icon(target()["asset"], target().get("direction", "SE"))
	if selection["kind"] == "pixels":
		var texture: Texture2D = Parts.edit_texture(selection)
		var picture: Image = texture.get_image().duplicate()
		picture.convert(Image.FORMAT_RGBA8)
		for y in picture.get_height():
			for x in picture.get_width():
				var base: Color = picture.get_pixel(x, y)
				picture.set_pixel(x, y, Color(base.r * 0.35, base.g * 0.35, base.b * 0.35, base.a))
		for index in selection["pixels"]: picture.set_pixel(int(index) % picture.get_width(), int(index) / picture.get_width(), Color("6fffe0"))
		preview.texture = ImageTexture.create_from_image(picture)

func open_tiles() -> void:
	if not tile_dialog:
		tile_dialog = AcceptDialog.new()
		tile_dialog.title = "Choose tile paint"
		tile_dialog.min_size = Vector2i(620, 520)
		studio.add_child(tile_dialog)
		var column := VBoxContainer.new()
		tile_dialog.add_child(column)
		tile_search = LineEdit.new()
		tile_search.placeholder_text = "Search tiles by name or pack…"
		tile_search.text_changed.connect(func(_value: String): refresh_tiles())
		column.add_child(tile_search)
		tile_all = CheckBox.new()
		tile_all.text = "Include all 2D artwork"
		tile_all.toggled.connect(func(_value: bool): refresh_tiles())
		column.add_child(tile_all)
		tile_list = ItemList.new()
		tile_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		tile_list.fixed_icon_size = Vector2i(48, 40)
		tile_list.item_selected.connect(func(index: int):
			set_tile_source(tile_list.get_item_metadata(index))
			tile_dialog.hide()
		)
		column.add_child(tile_list)
	refresh_tiles()
	tile_dialog.popup_centered()

func refresh_tiles() -> void:
	tile_list.clear()
	for asset in studio.library.find("2d", "All assets", tile_search.text, [], false):
		if not tile_all.button_pressed and not studio.library.is_ground_tile(asset["id"]): continue
		var index: int = tile_list.add_item(asset["name"] + " · " + asset["category"], studio.library.icon(asset["id"]))
		tile_list.set_item_metadata(index, asset["id"])
		if tile_list.item_count >= 100: break

func set_tile_source(id: String) -> void:
	tile_source = Patterns.from_asset(studio.library, id)
	if tile_source.is_empty(): return
	tile_name.text = studio.library.assets[id]["name"]
	tile_preview.texture = Patterns.texture(tile_source)
	tabs.current_tab = page.get_index()

func apply_tile() -> void:
	var item: Dictionary = target()
	if tile_source.is_empty(): studio.status.text = "Choose a 2D tile first."; return
	if item.is_empty() or selection.is_empty() or not studio.Layers.editable(studio.current().data, item, studio.library):
		studio.status.text = "Pick the piece to paint on the canvas first."
		return
	var edit: Dictionary = usable_selection()
	if edit.is_empty(): studio.status.text = "Pick a visible piece before painting."; return
	edit.erase("distance")
	edit["color"] = [1.0, 1.0, 1.0, 1.0]
	var pattern: Dictionary = tile_source.duplicate(true)
	pattern["scale"] = tile_size.value
	pattern["angle"] = tile_angle.value
	pattern["offset"] = [tile_x.value, tile_y.value]
	pattern["projection"] = tile_projection.get_item_text(tile_projection.selected).to_lower()
	edit["pattern"] = pattern
	if not Parts.valid([edit]): return
	studio.current().checkpoint()
	item.erase("family")
	if not item.has("colors"): item["colors"] = []
	item["colors"].append(edit)
	studio.changed()
	studio.status.text = "Painted the selected piece with the tile. Undo reverses the application."

func pick_instance(instance: Node, item: Dictionary, at: Vector2, hit_only: bool = false) -> Dictionary:
	var world: Node = studio.worlds[studio.mode]
	if item["asset"].begins_with("3d:"):
		var root: Node3D = Parts.model_root(instance)
		var camera: Node
		var point: Vector2 = at
		if studio.mode == "2d":
			var sprite: Sprite2D = instance.get_node("Sprite2D")
			var local: Vector2 = studio.viewport.canvas_transform.affine_inverse() * at
			var pixel: Vector2 = sprite.to_local(local)
			if not sprite.get_rect().has_point(pixel): return {}
			point = (pixel - sprite.get_rect().position) / sprite.get_rect().size * instance.projection_size()
			camera = instance
		else: camera = world.camera
		var hit: Dictionary = Parts.ray_pick(root,camera.project_ray_origin(point),camera.project_ray_normal(point),studio.mode == "2d" and instance.viewport == null)
		if hit.is_empty(): return {}
		if hit_only: return hit
		var edit: Dictionary = Parts.connected_faces(root, hit, tolerance.value / 100, mode.selected == 1)
		edit["distance"] = hit["distance"]
		return edit
	var sprite: Sprite2D = Parts.sprite_for(instance)
	if not sprite: return {}
	if studio.mode == "2d":
		var local: Vector2 = studio.viewport.canvas_transform.affine_inverse() * at
		return Parts.pixels(sprite, sprite.to_local(local), tolerance.value / 100, hit_only or mode.selected == 1)
	var hit: Dictionary = sprite_hit(instance, at)
	if hit.is_empty(): return {}
	var edit: Dictionary = Parts.pixels(sprite, sprite.get_rect().position + hit["uv"] * sprite.get_rect().size, tolerance.value / 100, hit_only or mode.selected == 1)
	if not edit.is_empty(): edit["distance"] = hit["distance"]
	return edit

func sprite_hit(instance: Node3D, at: Vector2) -> Dictionary:
	var camera: Camera3D = studio.worlds["3d"].camera
	var from: Vector3 = camera.project_ray_origin(at)
	var ray: Vector3 = camera.project_ray_normal(at)
	var mesh: MeshInstance3D = instance.mesh
	var center: Vector3 = mesh.global_position
	var billboard: bool = not instance.ground_tile and instance.material.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED
	var right: Vector3 = camera.global_basis.x.normalized() if billboard else mesh.global_basis.x.normalized()
	var up: Vector3 = Vector3.UP if billboard else mesh.global_basis.y.normalized()
	var normal: Vector3 = right.cross(up).normalized()
	var point: Variant = Plane(normal, normal.dot(center)).intersects_ray(from, ray)
	if not point is Vector3: return {}
	var delta: Vector3 = point - center
	var size: Vector2 = mesh.mesh.size
	var uv := Vector2(0.5 + delta.dot(right) / (size.x * mesh.global_basis.x.length()), 0.5 - delta.dot(up) / (size.y * mesh.global_basis.y.length()))
	if not Rect2(Vector2.ZERO, Vector2.ONE).has_point(uv): return {}
	if instance.ground_tile:
		var angle: float = deg_to_rad(preload("res://scripts/iso_tile_rotation.gd").degrees(instance.direction))
		var rotated: Vector2 = (uv - Vector2.ONE * 0.5).rotated(-angle) + Vector2.ONE * 0.5
		uv = Vector2(0.5 + (rotated.x - rotated.y) * 0.5, (rotated.x + rotated.y) * 0.5) if instance.diamond_ground else rotated
		if instance.source is IsoObject:
			var views: Dictionary = instance.source.directions_data
			var view: Dictionary = views.get(instance.direction, views.get("SE", views.values()[0]))
			var base: Array = view.get("alignment_base", [])
			if base.size() == 3:
				var back := Vector2(base[0][0] + base[2][0] - base[1][0], base[0][1] + base[2][1] - base[1][1])
				var source_point: Vector2 = back + rotated.x * (Vector2(base[2][0], base[2][1]) - back) + rotated.y * (Vector2(base[0][0], base[0][1]) - back)
				var sprite: Sprite2D = Parts.sprite_for(instance)
				uv = source_point / sprite.get_rect().size
	else:
		var sprite: Sprite2D = Parts.sprite_for(instance)
		var local: Vector2 = sprite.transform.affine_inverse() * (instance.card_rect.position + uv * instance.card_rect.size)
		uv = (local - sprite.get_rect().position) / sprite.get_rect().size
	return {"uv": uv, "distance": from.distance_squared_to(point)}

func pick_tile(at: Vector2) -> void:
	if not studio.Layers.shown(studio.current().data, "Ground") or studio.Layers.locked(studio.current().data, "Ground"): return
	var local: Vector2 = studio.viewport.canvas_transform.affine_inverse() * at
	var cell: Vector2i = IsoMath.world_to_tile(local)
	for tile in studio.current().data["tiles"]:
		if tile["cell"] != [cell.x, cell.y]: continue
		var node: Node2D = load(studio.library.assets[tile["asset"]]["path"]).instantiate()
		studio.worlds["2d"].add_child(node)
		node.visible = false
		node.position = IsoMath.tile_to_world(cell)
		node.direction = tile.get("direction", "SE")
		var sprite: Sprite2D = node.get_node("Sprite2D")
		var sample: Vector2 = sprite.to_local(local)
		var rect: Rect2 = sprite.get_rect()
		var center: Vector2 = rect.get_center()
		var p: Vector2 = sample - center
		p.y *= 2
		p = p.rotated(-deg_to_rad(preload("res://scripts/iso_tile_rotation.gd").degrees(node.direction)))
		p.y *= 0.5
		selection = Parts.pixels(sprite, center + p, tolerance.value / 100, mode.selected == 1)
		tile_transform = studio.viewport.canvas_transform * sprite.global_transform
		tile_rect = sprite.get_rect()
		tile_sprite_frame = Vector2i(sprite.texture.get_width() / sprite.hframes, sprite.texture.get_height() / sprite.vframes)
		tile_texture_size = Vector2i(sprite.texture.get_width(), sprite.texture.get_height())
		tile_grid_frame = sprite.frame
		tile_angle_value = preload("res://scripts/iso_tile_rotation.gd").degrees(node.direction)
		node.free()
		if not selection.is_empty(): selected_cell = cell
		return

func apply_color() -> void:
	var item: Dictionary = target()
	if item.is_empty() or selection.is_empty() or not studio.Layers.editable(studio.current().data, item, studio.library): return
	var edit: Dictionary = usable_selection()
	if edit.is_empty(): studio.status.text = "Pick a visible piece before painting."; return
	edit.erase("distance")
	edit["color"] = [picker.color.r, picker.color.g, picker.color.b, 1.0]
	studio.current().checkpoint()
	item.erase("family")
	if not item.has("colors"): item["colors"] = []
	item["colors"].append(edit)
	studio.changed()
	studio.status.text = "Applied color to the selected piece. Other objects and source assets are unchanged."

func reset_colors() -> void:
	var item: Dictionary = target()
	if item.is_empty() or not item.has("colors") or not studio.Layers.editable(studio.current().data, item, studio.library): return
	studio.current().checkpoint()
	item.erase("colors")
	studio.changed()
	studio.status.text = "Restored this object's original colors."

func draw_selection(overlay: Control) -> void:
	overlay.part_polygons.clear()
	var item: Dictionary = target()
	if studio.tool != "color" or item.is_empty() or selection.is_empty() or not studio.Layers.editable(studio.current().data, item, studio.library): return
	if not base_selection.is_empty() and selected_uid == guarded_uid and selected_cell == guarded_cell and item.get("asset") != guarded_asset: return
	if selection["kind"] == "pixels":
		if studio.mode == "2d":
			if selected_cell is Vector2i:
				var polygon: PackedVector2Array = IsoMath.get_footprint_diamond(selected_cell, Vector2i.ONE)
				overlay.part_polygons.append(studio.viewport.canvas_transform * polygon)
			else:
				var sprite: Sprite2D = Parts.sprite_for(studio.worlds["2d"].instances[selected_uid])
				var image: Image = Parts.base_texture(sprite).get_image()
				var min_point := Vector2(INF, INF)
				var max_point := Vector2(-INF, -INF)
				for index in selection["pixels"]:
					var point := Vector2(int(index) % image.get_width(), int(index) / image.get_width())
					point -= Vector2(sprite.frame_coords) * sprite.get_rect().size
					point += sprite.get_rect().position
					min_point = min_point.min(point)
					max_point = max_point.max(point + Vector2.ONE)
				var rect := Rect2(min_point, max_point - min_point)
				var polygon := PackedVector2Array([rect.position, rect.position + Vector2(rect.size.x, 0), rect.end, rect.position + Vector2(0, rect.size.y)])
				overlay.part_polygons.append(studio.viewport.canvas_transform * (sprite.global_transform * polygon))
		return
	var instance: Node = studio.worlds[studio.mode].instances.get(selected_uid)
	if not instance: return
	var root: Node3D = Parts.model_root(instance)
	var node: MeshInstance3D = root.get_node_or_null(selection["mesh"])
	if not node: return
	var arrays: Array = Parts.original_mesh(node).surface_get_arrays(selection["surface"])
	var indices: PackedInt32Array = Parts.indices_for(arrays)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for face in selection["faces"]:
		var polygon := PackedVector2Array()
		for corner in 3:
			var point: Vector3 = node.global_transform * vertices[indices[int(face) * 3 + corner]]
			var projected: Vector2
			if studio.mode == "3d": projected = studio.worlds["3d"].camera.unproject_position(point)
			else:
				var sprite: Sprite2D = instance.get_node("Sprite2D")
				var pixel: Vector2 = instance.unproject_position(point)
				projected = studio.viewport.canvas_transform * sprite.to_global(sprite.get_rect().position + pixel / instance.projection_size() * sprite.get_rect().size)
			polygon.append(projected)
		overlay.part_polygons.append(polygon)
