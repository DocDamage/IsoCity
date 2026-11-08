extends RefCounted

const Rotation = preload("res://scripts/builder/rotation.gd")
var studio: Control
var choice: OptionButton
var note: Label
var caption: Label

func _init(owner_control: Control, parent: VBoxContainer, angle_label: Label) -> void:
	studio = owner_control
	caption = angle_label
	choice = OptionButton.new()
	choice.fit_to_longest_item = false
	choice.clip_text = true
	for title in ["Automatic · legacy behavior", "Source view only", "World rotation", "Camera-relative rotation"]: choice.add_item(title)
	parent.add_child(choice)
	parent.move_child(choice, 0)
	note = studio.label(parent, "", 12)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.move_child(note, 1)
	choice.item_selected.connect(func(_index: int): studio.refresh_controls())

func camera_reference(item: Dictionary) -> float:
	if studio.mode == "2d" and item.get("asset", "").begins_with("2d:"): return studio.worlds["2d"].camera.rotation_degrees
	if studio.library.is_ground_tile(item.get("asset", "")): return 45 - studio.model_view_yaw()
	return studio.model_view_yaw() + (180 if item.get("asset", "").begins_with("3d:") else -45)

func clockwise_positive(item: Dictionary) -> bool:
	return (studio.mode == "2d" and item.get("asset", "").begins_with("2d:")) or studio.library.is_ground_tile(item.get("asset", ""))

func to_world(value: float, item: Dictionary) -> float:
	if choice.selected != 3: return value
	return wrapf(camera_reference(item) + value if clockwise_positive(item) else camera_reference(item) - value, 0, 360)

func displayed(item: Dictionary) -> float:
	var heading: float = Rotation.heading(item, studio.library)
	if choice.selected != 3: return heading
	return wrapf(heading - camera_reference(item) if clockwise_positive(item) else camera_reference(item) - heading, 0, 360)

func active_record() -> Dictionary:
	var items: Array = studio.selection_items()
	if not items.is_empty(): return items[0]
	var tile: Dictionary = studio.selected_tile()
	return tile if not tile.is_empty() else studio.placement_record()

func set_displayed(value: float) -> void:
	var active: Dictionary = active_record()
	if not studio.library.assets.has(active.get("asset", "")): return
	if choice.selected != 3: studio.set_rotation_value("angle", value); return
	var items: Array = studio.selection_items()
	var tile: Dictionary = studio.selected_tile() if items.is_empty() else {}
	if not tile.is_empty() and not studio.Layers.editable(studio.current().data, tile, studio.library): return
	var delta: float = value - displayed(active)
	var targets: Array = items if not items.is_empty() else [active]
	if not items.is_empty() or not tile.is_empty(): studio.current().checkpoint()
	var pivot: Vector3 = studio.arrange_tools.pivot(items)
	for item in targets:
		Rotation.set_heading(item, to_world(displayed(item) + delta, item), studio.library)
		if studio.arrange_tools.orbit_enabled(items): item["position"] = Rotation.orbit_position(item["position"], pivot, delta if studio.mode == "2d" else -delta, studio.mode)
	studio.direction = active["direction"]
	studio.rotation_manual = true
	if items.is_empty() and tile.is_empty():
		studio.placement_angle = active.get("angle", 0)
		studio.refresh_controls()
	else: studio.changed()

func refresh(item: Dictionary) -> void:
	var id: String = item.get("asset", "")
	var valid: bool = studio.library.assets.has(id)
	caption.text = "Camera angle" if choice.selected == 3 else ("World angle / yaw" if choice.selected == 2 else "Angle / yaw")
	studio.angle_input.editable = valid and choice.selected != 1
	if valid: studio.angle_input.set_value_no_signal(displayed(item))
	match choice.selected:
		0: note.text = "R cycles supplied sprite views at 90° when no artwork angle is set; otherwise it rotates the world angle. Choose an explicit mode for one consistent action."
		1: note.text = "R changes supplied object artwork only. Positions, world angles, pitch and roll are preserved. Models and ground tiles have no selectable object source view; choose World rotation."
		2: note.text = "R changes the world angle by Rotate step. Source artwork stays fixed. Pitch and roll use world axes."
		3: note.text = "Angle 0 follows the current camera reference; positive angles turn clockwise on screen. R uses Rotate step. Source artwork stays fixed; pitch and roll use world axes."
	if choice.selected == 1: studio.rotation_button.text = "Next source view · R"
	elif choice.selected > 1: studio.rotation_button.text = "Rotate %s · %s°" % ["camera" if choice.selected == 3 else "world", str(studio.rotation_step.value)]

func rotate(step: int, reset: bool) -> bool:
	if choice.selected == 0: return false
	var active: Dictionary = active_record()
	if not studio.library.assets.has(active.get("asset", "")): return true
	if choice.selected == 1:
		var items: Array = studio.selection_items()
		var targets: Array = items if not items.is_empty() else [active]
		var changes: Array = []
		for item in targets:
			if not item["asset"].begins_with("2d:") or studio.library.is_ground_tile(item["asset"]) or not studio.Layers.editable(studio.current().data, item, studio.library): continue
			var views: Array = studio.library.assets[item["asset"]]["data"].get("directions", {}).keys()
			if views.is_empty(): continue
			var next: String = str(views[0 if reset else posmod(views.find(item["direction"]) + step, views.size())])
			if item["direction"] != next: changes.append([item, next])
		if changes.is_empty(): studio.status.text = "No different supplied sprite view is available for this selection."; return true
		if not items.is_empty() or not studio.selected_tile().is_empty(): studio.current().checkpoint()
		for pair in changes: pair[0]["direction"] = pair[1]
		studio.direction = active["direction"]
		studio.rotation_manual = true
		if items.is_empty() and studio.selected_tile().is_empty(): studio.refresh_controls()
		else: studio.changed()
		studio.status.text = "Changed supplied artwork for %d objects; world transforms were preserved." % changes.size()
		return true
	var value: float = 0.0 if reset else displayed(active) + studio.rotation_step.value * step
	set_displayed(value)
	return true
