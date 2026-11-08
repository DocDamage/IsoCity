extends RefCounted

const Cells = preload("res://scripts/builder/brush_cells.gd")
const Fit = preload("res://scripts/builder/grid_fit.gd")
const Layers = preload("res://scripts/builder/layers.gd")
const Families=preload("res://scripts/builder/terrain_family_plan.gd")
const Protection=preload("res://scripts/builder/cooperative_plan.gd")
var studio: Control
var panel: ScrollContainer
var operation: OptionButton
var family_choice: OptionButton
var enabled_input: CheckBox
var replace_only: CheckBox
var info: Label
var drawing: bool = false
var start := Vector2i.ZERO
var last := Vector2i.ZERO
var end := Vector2i.ZERO
var surfaces: Dictionary = {}
var step := Vector2.ONE
var elevation: float = 0
var seed_asset: String = ""
var visited: Dictionary = {}
var changed_count: int = 0
var limited: bool = false
var last_pointer := Vector2.ZERO
var native_records: Dictionary={}
var guarded_cells: Array[Rect2]=[]
var native_levels: Dictionary={}
var skipped_protected: int=0

func _init(owner_control: Control, tabs: TabContainer = null) -> void:
	studio = owner_control
	if not tabs: return
	panel = ScrollContainer.new()
	panel.name = "Ground"
	panel.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	panel.follow_focus=true
	tabs.add_child(panel)
	var box:=VBoxContainer.new()
	box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	panel.add_child(box)
	studio.label(box, "Ground painting", 14)
	family_choice=OptionButton.new()
	family_choice.accessibility_name="Connected terrain family"
	family_choice.fit_to_longest_item=false
	family_choice.add_item("Manual tiles")
	family_choice.set_item_metadata(0,"")
	for id in ["shore","path"]:
		family_choice.add_item(Families.profile(id)["label"])
		family_choice.set_item_metadata(family_choice.item_count-1,id)
	family_choice.item_selected.connect(choose_family)
	box.add_child(family_choice)
	enabled_input = CheckBox.new()
	enabled_input.text = "Paint ground cells"
	enabled_input.button_pressed = true
	enabled_input.tooltip_text = "Turn off to place 3D or imported ground objects individually with the Arrange anchor. Native 2D tile maps always paint cells."
	box.add_child(enabled_input)
	operation = OptionButton.new()
	for text in ["Brush stroke", "Straight line", "Rectangle fill", "Flood fill"]: operation.add_item(text)
	box.add_child(operation)
	replace_only = CheckBox.new()
	replace_only.text = "Replace matching only"
	replace_only.accessibility_name = "Replace matching surfaces only"
	replace_only.tooltip_text = "Only change surfaces matching the one under the first click. Empty cells and protected objects are preserved."
	box.add_child(replace_only)
	info = studio.label(box, "", 12)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	studio.label(box, "Choose Manual tiles to paint an override. Use Terrain to connect sculpted banks and rock faces. Fills are limited to 16,384 cells. Each gesture is one Undo step.", 12).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func show() -> void:
	studio.workspace_presets.set_focus(false)
	if studio.walking: studio.set_walking(false)
	studio.workspace_layout.inspector_toggle.button_pressed=true
	studio.workspace_layout.tabs.current_tab=panel.get_index()
	refresh()
	family_choice.grab_focus()

func choose_family(index: int) -> void:
	var id: String=family_choice.get_item_metadata(index)
	if not id.is_empty() and studio.mode=="2d":
		studio.select_asset(Families.profile(id)["asset"])
		if studio.consumer_shell: studio.consumer_shell.prepare_command("ground_families")
		show()
	refresh()

func family() -> String:
	var id: String=family_choice.get_item_metadata(family_choice.selected)
	return id if studio.mode=="2d" and studio.asset_id==Families.profile(id).get("asset","") else ""

func active() -> bool:
	return studio.tool == "place" and studio.library.assets.has(studio.asset_id) and studio.library.is_ground_tile(studio.asset_id) and (enabled_input.button_pressed or native_tiles())

func refresh() -> void:
	info.text = "Choose a ground/floor asset to paint in either world." if not active() else ("Painting 2D tile cells." if native_tiles() else "Painting selectable ground surfaces on a level plane. Height sets the plane; Surface snap can pick its starting height in 3D.")
	family_choice.disabled=studio.mode!="2d"
	if family_choice.disabled: info.text+="\nConnected tile artwork is available in the Pixel world."
	elif not family().is_empty(): info.text=Families.profile(family())["label"]+" · neighboring cells choose the artwork."
	enabled_input.disabled = native_tiles()

func native_tiles() -> bool:
	return studio.mode == "2d" and studio.worlds["2d"].tile_lookup.has(studio.asset_id)

func configure_grid(at: Vector2) -> void:
	var record: Dictionary = studio.placement_record()
	record["scale"] = studio.scale_input.value
	step = Vector2.ONE
	if not native_tiles():
		var bounds: AABB = Fit.footprint_bounds(record, studio.mode, studio.library)
		step = Vector2(maxf(0.1, bounds.size.x), maxf(0.1, bounds.size.z))
	elevation = studio.height_input.value
	if studio.mode == "3d" and studio.surface_input.button_pressed:
		studio.worlds["3d"].surface_snapping = true
		var excluded: Array = []
		for item in studio.current().data["objects"]:
			if studio.library.is_ground_tile(item["asset"]): excluded.append(item["uid"])
		elevation = studio.worlds["3d"].surface_point(at, false, elevation, excluded)[1]

func setup(at: Vector2, data: Dictionary = {}) -> void:
	if data.is_empty(): data = studio.current().data
	configure_grid(at)
	surfaces = surface_index(data)
	native_records=Families.by_cell(data["tiles"]) if native_tiles() else {}
	start = cell_at(at)
	last = start
	end = start
	seed_asset = surfaces.get(start, {}).get("asset", "")
	visited.clear()
	changed_count = 0
	limited = false
	skipped_protected=0

func position_for(cell: Vector2i) -> Array:
	var record: Dictionary = studio.placement_record()
	record["scale"] = studio.scale_input.value
	var p: Vector2 = Vector2(cell) * step
	var pixel: Vector2 = Fit.pixels(p)
	var values: Array = [pixel.x, pixel.y, elevation] if studio.mode == "2d" else [p.x, elevation, p.y]
	return values if native_tiles() else Fit.place(values, record, studio.mode, studio.library)

func preview_position(at: Vector2) -> Dictionary:
	if not drawing: configure_grid(at)
	return {"position": position_for(cell_at(at)), "direction": studio.direction, "ground_cell": true, "tile_cell": native_tiles()}

func cell_at(at: Vector2) -> Vector2i:
	var values: Array = studio.worlds[studio.mode].point(at, false, elevation)
	var location: Vector2 = Fit.grid(Vector2(values[0], values[1])) if studio.mode == "2d" else Vector2(values[0], values[2])
	return Vector2i((location / step).floor())

func surface_index(data: Dictionary = {}) -> Dictionary:
	if data.is_empty(): data = studio.current().data
	var result: Dictionary = {}
	if native_tiles():
		for tile in data["tiles"]:
			result[Vector2i(tile["cell"][0], tile["cell"][1])] = {"asset": tile["asset"], "tile": tile, "editable": true}
		return result
	for item in data["objects"]:
		if not studio.library.is_ground_tile(item["asset"]): continue
		var base: Array = Fit.anchor_position(item, studio.mode, studio.library)
		var height: float = item["position"][2] if studio.mode == "2d" else base[1]
		if not is_equal_approx(height, elevation): continue
		var location: Vector2 = Fit.grid(Vector2(base[0], base[1])) if studio.mode == "2d" else Vector2(base[0], base[2])
		var cell := Vector2i((location / step + Vector2.ONE * 0.00001).floor())
		var entry: Dictionary = {"asset": item["asset"], "item": item, "editable": Layers.editable(studio.current().data, item, studio.library)}
		# A protected surface blocks painting even when another surface shares the cell.
		if not result.has(cell) or not entry["editable"]: result[cell] = entry
	return result

func begin(at: Vector2) -> void:
	last_pointer = at
	setup(at, studio.current().data)
	drawing = true
	if operation.selected == 0: apply_cells(Cells.stamp(start, int(studio.brush_input.value)))
	elif operation.selected == 3:
		var cells: Array[Vector2i] = Cells.flood(start, surfaces)
		if cells.is_empty(): studio.status.text = "Flood fill needs an existing, editable surface under the first click."
		else: apply_cells(cells)

func move(at: Vector2) -> void:
	if not drawing: return
	last_pointer = at
	end = cell_at(at)
	if operation.selected == 0 and end != last:
		apply_cells(Cells.line(last, end, int(studio.brush_input.value)))
		last = end

func finish(at: Vector2) -> void:
	if not drawing: return
	if operation.selected == 0: move(at)
	end = cell_at(at)
	if operation.selected == 1: apply_cells(Cells.line(start, end, int(studio.brush_input.value)))
	elif operation.selected == 2: apply_cells(Cells.rectangle(start, end))
	drawing = false
	if changed_count==0 and not family().is_empty() and not studio.interior_tools.editing():
		studio.current().finish_checkpoint(true)
	if changed_count > 0: studio.status.text = "Painted %d ground cells. Undo reverses the gesture." % changed_count
	elif replace_only.button_pressed: studio.status.text = "No editable surfaces matched the first clicked surface."
	if limited: studio.status.text += " Cell limit reached (16,384); split larger fills into smaller gestures."
	if skipped_protected>0: studio.status.text += " Protected terrain skipped."

func paint_once(at: Vector2) -> void:
	begin(at)
	finish(at)

func propose(data: Dictionary, at: Vector2, allocate: Callable) -> void:
	var brush: RefCounted = get_script().new(studio)
	brush.family_choice = family_choice
	brush.operation = operation
	brush.replace_only = replace_only
	var cells: Array[Vector2i] = []
	if drawing:
		brush.step = step
		brush.elevation = elevation
		brush.seed_asset = seed_asset
		brush.visited = visited.duplicate()
		brush.surfaces = brush.surface_index(data)
		if native_tiles(): brush.native_records = Families.by_cell(data["tiles"])
		cells = preview_cells(at)
		if operation.selected == 0:
			cells = Cells.line(last, cell_at(at), int(studio.brush_input.value))
	else:
		brush.setup(at, data)
		if operation.selected == 3: cells = Cells.flood(brush.start, brush.surfaces)
		elif operation.selected == 2: cells = [brush.start]
		else: cells = Cells.stamp(brush.start, int(studio.brush_input.value))
	brush.apply_cells(cells, data, allocate)

func apply_cells(cells: Array[Vector2i], preview_data: Dictionary = {}, allocate: Callable = Callable()) -> void:
	var preview: bool = allocate.is_valid()
	var data: Dictionary = preview_data if preview else studio.current().data
	var count: int = 0
	var recent_cell: Variant=null;var recent_uid: String=""
	var style: String=family()
	if native_tiles(): update_protection()
	for cell in cells:
		if visited.has(cell): continue
		visited[cell] = true
		var existing: Dictionary = surfaces.get(cell, {})
		if not existing.get("editable", true): continue
		if replace_only.button_pressed and (seed_asset.is_empty() or existing.get("asset", "") != seed_asset): continue
		if native_tiles():
			var tile: Dictionary = existing.get("tile", {})
			var next: Dictionary=tile.duplicate(true)
			if tile.get("asset")!=studio.asset_id or not style.is_empty(): next.erase("colors")
			next.merge({"cell":[cell.x,cell.y],"asset":studio.asset_id,"direction":studio.direction if style.is_empty() else "SE"},true)
			if style.is_empty(): next.erase("family")
			else: next["family"]=style
			if next==tile: continue
			if not native_editable(cell,next):
				skipped_protected+=1
				continue
			if tile.is_empty(): data["tiles"].append(tile)
			tile.assign(next)
			native_records[cell]=tile
			surfaces[cell] = {"asset": studio.asset_id, "tile": tile, "editable": true}
		else:
			var record: Dictionary = studio.placement_record()
			record["scale"] = studio.scale_input.value
			var values: Array = position_for(cell)
			var item: Dictionary = existing.get("item", {})
			if not item.is_empty() and item["asset"] == studio.asset_id and item["direction"] == studio.direction and item.get("angle", 0) == record.get("angle", 0) and item.get("tilt", [0, 0]) == record.get("tilt", [0, 0]) and item["position"] == values and item["scale"] == record["scale"]: continue
			if item.is_empty():
				if preview:
					item = preload("res://scripts/builder/document.gd").placement_item(allocate.call(), studio.asset_id, values, studio.direction, record["scale"])
					data["objects"].append(item)
				else: item = studio.current().add(studio.asset_id, values, studio.direction, record["scale"])
			else:
				if item["asset"] != studio.asset_id: item.erase("colors")
				item["asset"] = studio.asset_id
				item["position"] = values
				item["direction"] = studio.direction
				item["scale"] = record["scale"]
			for property in ["angle", "tilt"]:
				if record.has(property): item[property] = record[property].duplicate() if record[property] is Array else record[property]
				else: item.erase(property)
			surfaces[cell] = {"asset": studio.asset_id, "item": item, "editable": true}
		count += 1
		recent_cell=[cell.x,cell.y] if native_tiles() else null
		recent_uid=surfaces[cell].get("item",{}).get("uid","")
	changed_count += count
	if count and not preview:
		studio.changed()
		if studio.asset_browser and studio.asset_browser.recents:
			studio.asset_browser.recents.placed(studio.asset_id,recent_uid,recent_cell)
	if cells.size() == Cells.LIMIT: limited = true

func update_protection() -> void:
	guarded_cells.clear()
	var session: Node=studio.cooperative_tools.session
	if not session.connected or session.role!="client": return
	var root: Dictionary=studio.interior_tools.root_document(studio.mode).data
	for area in root.get("protected_areas",[]):
		if area["owner"]!=session.local_id: guarded_cells.append(Protection.rect(area).grow(.001))
	if not guarded_cells.is_empty():
		native_levels=Families.water_levels(root.get("water_cells",[])) if root.get("terrain",{}).get("enabled",false) else {}

func native_editable(cell: Vector2i,next: Dictionary) -> bool:
	if guarded_cells.is_empty(): return true
	var previous: Dictionary=native_records.get(cell,{})
	for x in range(-1,2):
		for y in range(-1,2):
			var at: Vector2i=cell+Vector2i(x,y)
			var area:=Rect2(Vector2(at)*2,Vector2.ONE*2).grow(.01)
			if not guarded_cells.any(func(guard: Rect2)->bool:return guard.intersects(area)): continue
			if at==cell: return false
			var neighbor: Dictionary=native_records.get(at,{})
			if not neighbor.has("family"): continue
			var old: Dictionary=Families.ground_variant(neighbor,at,native_records,native_levels)
			native_records[cell]=next
			var visual: Dictionary=Families.ground_variant(neighbor,at,native_records,native_levels)
			if previous.is_empty(): native_records.erase(cell)
			else: native_records[cell]=previous
			if old!=visual: return false
	return true

func preview_cells(at: Vector2) -> Array[Vector2i]:
	if drawing and operation.selected == 1: return Cells.line(start, cell_at(at), int(studio.brush_input.value))
	if drawing and operation.selected == 2: return Cells.rectangle(start, cell_at(at))
	return []

func preview_polygon(at: Vector2) -> PackedVector2Array:
	if not drawing: return PackedVector2Array()
	var finish: Vector2i = cell_at(at)
	var radius: int = int(studio.brush_input.value) / 2 if operation.selected != 2 else 0
	var points := PackedVector2Array()
	if operation.selected == 2:
		var low := Vector2(mini(start.x, finish.x), mini(start.y, finish.y))
		var high := Vector2(maxi(start.x, finish.x) + 1, maxi(start.y, finish.y) + 1)
		for corner in [low, Vector2(high.x, low.y), high, Vector2(low.x, high.y)]:
			var p: Vector2 = corner * step
			var pixel: Vector2 = Fit.pixels(p)
			points.append(studio.overlay_position([pixel.x, pixel.y, elevation] if studio.mode == "2d" else [p.x, elevation, p.y]))
		return Geometry2D.convex_hull(points)
	for cell in [start, finish] if operation.selected in [1, 2] else [finish]:
		for corner in [Vector2(-radius, -radius), Vector2(1 + radius, -radius), Vector2(1 + radius, 1 + radius), Vector2(-radius, 1 + radius)]:
			var p: Vector2 = (Vector2(cell) + corner) * step
			var pixel: Vector2 = Fit.pixels(p)
			points.append(studio.overlay_position([pixel.x, pixel.y, elevation] if studio.mode == "2d" else [p.x, elevation, p.y]))
	return Geometry2D.convex_hull(points)

func settings() -> Dictionary:
	return {"enabled": enabled_input.button_pressed, "operation": operation.selected, "replace_only": replace_only.button_pressed, "width": studio.brush_input.value,
		"family":family_choice.get_item_metadata(family_choice.selected)}

func restore(value: Dictionary) -> void:
	operation.select(clampi(int(value.get("operation", 0)), 0, 3))
	enabled_input.set_pressed_no_signal(bool(value.get("enabled", true)))
	replace_only.set_pressed_no_signal(bool(value.get("replace_only", false)))
	studio.brush_input.set_value_no_signal(clampi(int(value.get("width", 1)), 1, 5))
	family_choice.select(0)
	for index in range(1,family_choice.item_count):
		if family_choice.get_item_metadata(index)==value.get("family",""): family_choice.select(index); break
	drawing = false
