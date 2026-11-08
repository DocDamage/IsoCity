extends RefCounted

const Parts = preload("res://scripts/builder/part_colors.gd")
const Patterns = preload("res://scripts/builder/tile_patterns.gd")
const Store = preload("res://scripts/builder/project_store.gd")
var studio: Control
var page: ScrollContainer
var panel: VBoxContainer
var copied: Dictionary = {}
var topology_cache: Dictionary = {}
var name_input: LineEdit
var preset_list: ItemList
var presets: Array = []
var storage_path: String = "user://studio_material_presets.json"

func _init(owner_control: Control, tabs: TabContainer) -> void:
	studio = owner_control
	page = ScrollContainer.new()
	page.name = "Appearance"
	page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(page)
	panel = VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(panel)
	studio.label(panel, "Reuse object appearance", 14)
	add_button("Copy selected appearance", copy_appearance)
	add_button("Paste to compatible selection", func(): paste_appearance(copied))
	studio.label(panel, "Object copies preserve exact piece masks. Compatible targets share the source asset, sprite sheets, or model geometry. Placement and original resources stay unchanged.", 12).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_input = LineEdit.new()
	name_input.placeholder_text = "Preset name"
	name_input.max_length = 80
	panel.add_child(name_input)
	add_button("Save object appearance preset", func(): save_preset("object"))
	add_button("Save current color as material", func(): save_preset("color"))
	add_button("Save current tile as material", func(): save_preset("tile"))
	preset_list = ItemList.new()
	preset_list.custom_minimum_size.y = 140
	preset_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(preset_list)
	add_button("Apply selected preset", apply_selected)
	add_button("Remove selected preset", remove_selected)
	studio.label(panel, "Color and tile materials apply to the piece picked in Colors, so they can be reused on different objects. Object presets replace the complete appearance of compatible selected objects. Presets persist between sessions.", 12).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if studio.storage_enabled: reload_presets()

func add_button(text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	panel.add_child(button)

func source_item() -> Dictionary:
	var items: Array = studio.selection_items()
	if not items.is_empty(): return items[0]
	return studio.selected_tile()

func snapshot(item: Dictionary) -> Dictionary:
	return {} if item.is_empty() else {"asset": item["asset"], "colors": item.get("colors", []).duplicate(true)}

func copy_appearance() -> void:
	copied = snapshot(source_item())
	studio.status.text = "Copied appearance. Select compatible objects and Paste." if not copied.is_empty() else "Select an object or ground tile to copy its appearance."

func compatible(payload: Dictionary, item: Dictionary) -> bool:
	var source: String = payload.get("asset", "")
	var destination: String = item.get("asset", "")
	if not studio.library.assets.has(source) or not studio.library.assets.has(destination): return false
	if source == destination: return true
	if source.begins_with("2d:") and destination.begins_with("2d:"):
		var paths: Dictionary = {}
		for view in studio.library.assets[destination]["data"].get("directions", {}).values():
			var file: String = view.get("file", "")
			var path: String = "res://assets/" + file.trim_prefix("../../") if file.begins_with("../../") else "res://assets/pixel_isometric/" + file
			paths[path] = true
		for edit in payload.get("colors", []):
			if edit.get("kind") != "pixels" or not paths.has(edit["texture"]): return false
		return not payload.get("colors", []).is_empty()
	if source.begins_with("3d:") and destination.begins_with("3d:"):
		return topology(source) == topology(destination)
	return false

func topology(id: String) -> Array:
	if topology_cache.has(id): return topology_cache[id]
	var node: Node = load(studio.library.assets[id]["path"]).instantiate()
	var result: Array = []
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		if not mesh.mesh: continue
		var surfaces: Array = []
		for surface in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			surfaces.append([arrays[Mesh.ARRAY_VERTEX], Parts.indices_for(arrays)])
		result.append([str(node.get_path_to(mesh)), surfaces])
	node.free()
	topology_cache[id] = result
	return result

func paste_appearance(payload: Dictionary) -> void:
	if payload.is_empty() or not Parts.valid(payload.get("colors")): studio.status.text = "Copy an appearance first."; return
	var targets: Array = studio.selection_items()
	if targets.is_empty() and not studio.selected_tile().is_empty(): targets = [studio.selected_tile()]
	var accepted: Array = []
	var skipped: int = 0
	for item in targets:
		if not studio.Layers.editable(studio.current().data, item, studio.library) or not compatible(payload, item): skipped += 1; continue
		if item.get("colors", []) != payload["colors"]: accepted.append(item)
	if accepted.is_empty(): studio.status.text = "No compatible editable targets need this appearance."; return
	studio.current().checkpoint()
	for item in accepted:
		if payload["colors"].is_empty(): item.erase("colors")
		else: item["colors"] = payload["colors"].duplicate(true)
	studio.changed()
	studio.status.text = "Applied appearance to %d objects; skipped %d incompatible or protected targets." % [accepted.size(), skipped]

func material(kind: String) -> Dictionary:
	var colors: Color = studio.color_editor.picker.color
	if kind == "color": return {"color": [colors.r, colors.g, colors.b, 1.0]}
	var editor: RefCounted = studio.color_editor
	if editor.tile_source.is_empty(): return {}
	var pattern: Dictionary = editor.tile_source.duplicate(true)
	pattern["scale"] = editor.tile_size.value
	pattern["angle"] = editor.tile_angle.value
	pattern["offset"] = [editor.tile_x.value, editor.tile_y.value]
	pattern["projection"] = editor.tile_projection.get_item_text(editor.tile_projection.selected).to_lower()
	return {"color": [1.0, 1.0, 1.0, 1.0], "pattern": pattern}

func save_preset(kind: String) -> void:
	var title: String = name_input.text.strip_edges()
	if title.is_empty(): studio.status.text = "Enter a preset name first."; return
	var payload: Dictionary = snapshot(source_item()) if kind == "object" else material(kind)
	if payload.is_empty(): studio.status.text = "Select an object or choose a tile in Colors first."; return
	var entry: Dictionary = {"name": title, "kind": kind, "payload": payload}
	if not valid_preset(entry): studio.status.text = "This preset could not be saved."; return
	var next: Array = presets.duplicate(true)
	next.append(entry)
	if next.size() > 200: studio.status.text = "The preset library holds 200 entries. Remove an unused preset first."; return
	if studio.storage_enabled and not Store.write_json(storage_path, next): studio.status.text = "Could not write the preset library."; return
	presets = next
	refresh()
	preset_list.select(presets.size() - 1)
	studio.status.text = "Saved preset: " + title

static func valid_preset(entry: Variant) -> bool:
	if not entry is Dictionary or not entry.get("name") is String or entry["name"].length() > 80 or not entry.get("payload") is Dictionary: return false
	var payload: Dictionary = entry["payload"]
	if entry.get("kind") == "object": return payload.get("asset") is String and Parts.valid(payload.get("colors"))
	if entry.get("kind") not in ["color", "tile"]: return false
	var edit: Dictionary = payload.duplicate(true)
	edit.merge({"kind": "faces", "mesh": "", "surface": 0, "faces": [0]})
	return Parts.valid([edit]) and (entry["kind"] != "tile" or payload.has("pattern"))

func reload_presets() -> void:
	var value: Variant = Store.read_json(storage_path, [])
	presets = []
	if value is Array:
		for entry in value:
			if valid_preset(entry) and presets.size() < 200: presets.append(entry)
	refresh()

func refresh() -> void:
	preset_list.clear()
	for entry in presets: preset_list.add_item("%s · %s" % [entry["name"], str(entry["kind"]).capitalize()])

func apply_selected() -> void:
	var chosen: PackedInt32Array = preset_list.get_selected_items()
	if chosen.is_empty(): return
	var entry: Dictionary = presets[chosen[0]]
	if entry["kind"] == "object": paste_appearance(entry["payload"]); return
	var editor: RefCounted = studio.color_editor
	var item: Dictionary = editor.target()
	if item.is_empty() or editor.selection.is_empty() or not studio.Layers.editable(studio.current().data, item, studio.library): studio.status.text = "Pick a piece in Colors before applying a material."; return
	var edit: Dictionary = editor.usable_selection()
	if edit.is_empty(): studio.status.text = "Pick a visible piece before applying a material."; return
	edit.erase("distance")
	edit.merge(entry["payload"], true)
	if not Parts.valid([edit]): return
	studio.current().checkpoint()
	if not item.has("colors"): item["colors"] = []
	item["colors"].append(edit)
	studio.changed()
	studio.status.text = "Applied material preset: " + entry["name"]

func remove_selected() -> void:
	var chosen: PackedInt32Array = preset_list.get_selected_items()
	if chosen.is_empty(): return
	var next: Array = presets.duplicate(true)
	next.remove_at(chosen[0])
	if studio.storage_enabled and not Store.write_json(storage_path, next): studio.status.text = "Could not update the preset library."; return
	presets = next
	refresh()
