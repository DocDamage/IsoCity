extends RefCounted

const Anchors = preload("res://scripts/builder/entrance_anchors.gd")
var studio: Control
var note: Label
var fields: Dictionary = {}
var preview: CheckBox
var reset: Button
var visit: Button
var door_markers: Dictionary = {}

func _init(owner_control: Control, tabs: TabContainer) -> void:
	studio = owner_control
	var panel := VBoxContainer.new()
	panel.name = "Entrance"
	tabs.add_child(panel)
	note = studio.label(panel, "Select one building to edit its entrance.", 12)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for key in ["point", "arrival"]:
		studio.label(panel, "Doorway" if key == "point" else "Standing approach", 13)
		var controls: Array[SpinBox] = []
		for axis in ["X", "Height / depth", "Z"]:
			var row := HBoxContainer.new()
			panel.add_child(row)
			var caption: Label = studio.label(row, axis, 12)
			caption.custom_minimum_size.x = 110
			var input := SpinBox.new()
			input.min_value = -10000
			input.max_value = 10000
			input.step = 0.001
			input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(input)
			controls.append(input)
			input.value_changed.connect(func(_value: float): apply_fields())
		fields[key] = controls
	preview = CheckBox.new()
	preview.text = "Show entrance approaches in Build"
	panel.add_child(preview)
	preview.toggled.connect(func(_value: bool): refresh())
	reset = Button.new()
	reset.text = "Restore catalog entrance"
	panel.add_child(reset)
	reset.pressed.connect(reset_anchor)
	visit = Button.new()
	visit.text = "Walk from this entrance"
	panel.add_child(visit)
	visit.pressed.connect(walk_here)

func active() -> Dictionary:
	var items: Array = studio.selection_items()
	if items.size() != 1: return {}
	var item: Dictionary = items[0]
	return item if preload("res://scripts/builder/exploration.gd").has_room(item, studio.library) else {}

func refresh() -> void:
	var item: Dictionary = active()
	var sprite: bool = not item.is_empty() and item["asset"].begins_with("2d:")
	var profile: Dictionary = Anchors.profile(item, studio.library) if not item.is_empty() else {}
	for key in fields:
		for index in 3:
			var field: SpinBox = fields[key][index]
			field.get_parent().visible = not sprite or index < 2
			if index == 1: field.get_parent().get_child(0).text = "Depth" if sprite else "Y / height"
			field.editable = not item.is_empty() and not item.has("missing_asset")
			field.set_value_no_signal(profile.get(key, [0,0,0])[index] if index < (2 if sprite else 3) else 0)
	reset.disabled = item.is_empty() or not item.has("entrance_anchor")
	visit.disabled = item.is_empty()
	note.text = ("Source-view ground coordinates (X / depth), before world rotation and scale. This override affects only " + item["direction"] + "." if sprite else "Source model coordinates (X / height / Z), before world rotation and scale.") if not item.is_empty() else "Select one editable building to adjust its doorway and clear standing approach."
	if item.has("missing_asset"): note.text = "The building asset is unavailable. Its saved room remains editable; restore or replace the asset to edit doorway anchors."
	var exploration: Node = studio.worlds[studio.mode].exploration
	if exploration.markers: exploration.markers.visible = studio.walking or preview.button_pressed
	if not door_markers.has(studio.mode):
		var marker: Node = Label.new() if studio.mode == "2d" else Label3D.new()
		marker.text = "＋ Doorway"
		marker.modulate = Color("ffd987")
		if studio.mode == "2d": marker.z_index = 100
		else:
			marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			marker.no_depth_test = true
			marker.pixel_size = 0.02
			marker.font_size = 32
		studio.worlds[studio.mode].add_child(marker)
		door_markers[studio.mode] = marker
	var marker: Node = door_markers[studio.mode]
	marker.visible = preview.button_pressed and not studio.walking and not item.is_empty()
	if marker.visible:
		var node: Node = studio.worlds[studio.mode].instances.get(item["uid"])
		if node:
			var point: Variant = Anchors.position_for(node,item,studio.mode,studio.library,false)
			marker.position = point - Vector2(6,14) if studio.mode == "2d" else point + Vector3.UP * .6

func apply_fields() -> void:
	var item: Dictionary = active()
	if item.is_empty(): return
	var sprite: bool = item["asset"].begins_with("2d:")
	var profile: Dictionary = {}
	for key in fields:
		var values: Array = []
		for index in (2 if sprite else 3): values.append(fields[key][index].value)
		profile[key] = values
	if profile == Anchors.profile(item, studio.library): return
	studio.current().checkpoint()
	if sprite:
		if not item.has("entrance_anchor"): item["entrance_anchor"] = {"views": {}}
		item["entrance_anchor"]["views"][item["direction"]] = profile
	else: item["entrance_anchor"] = profile
	studio.changed()

func reset_anchor() -> void:
	var item: Dictionary = active()
	if item.is_empty() or not item.has("entrance_anchor"): return
	studio.current().checkpoint()
	item.erase("entrance_anchor")
	studio.changed()

func walk_here() -> void:
	var item: Dictionary = active()
	if item.is_empty(): return
	var world: Node = studio.worlds[studio.mode]
	var destination: Variant = world.exploration.entrance(world.instances[item["uid"]])
	studio.set_walking(true)
	world.player.teleport_to(destination)
