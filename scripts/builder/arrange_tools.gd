extends RefCounted

const Fit = preload("res://scripts/builder/grid_fit.gd")
var studio: Control
var panel: ScrollContainer
var snap_target: OptionButton
var pivot_mode: OptionButton
var pivot_fields: Array[SpinBox] = []
var reference_mode: OptionButton
var reference_choice: OptionButton
var axis: OptionButton
var gap: SpinBox
var context: Label
var picking_pivot: bool = false
var updating: bool = false

func _init(owner_control: Control, tabs: TabContainer) -> void:
	studio = owner_control
	panel = ScrollContainer.new()
	panel.name = "Arrange"
	panel.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(panel)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(box)
	studio.label(box, "Placement anchor", 14)
	snap_target = choice(box, Fit.TARGET_LABELS)
	snap_target.tooltip_text = "Choose the point on the asset that meets the grid or surface. Edges and corners follow the asset's rotation. Base minimum preserves the original grid behavior."
	studio.label(box, "Surface destinations use Surface snap.\nCustom anchors take priority over car lanes.", 12).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	studio.label(box, "Transform pivot", 14)
	pivot_mode = choice(box, ["Group center", "Each object's origin", "Custom pivot"])
	pivot_mode.item_selected.connect(func(_index: int): refresh())
	for name in ["Pivot X", "Pivot Y", "Pivot Z"]:
		studio.label(box, name, 12)
		var field: SpinBox = studio.spin(box, -1000000, 1000000, 0.1, 0)
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pivot_fields.append(field)
	var use_origin := Button.new()
	use_origin.text = "Use selected origin as pivot"
	box.add_child(use_origin)
	use_origin.pressed.connect(func():
		var items: Array = studio.selection_items()
		if not items.is_empty(): set_custom(items[0]["position"])
	)
	var pick := Button.new()
	pick.text = "Pick pivot on canvas"
	box.add_child(pick)
	pick.pressed.connect(func():
		picking_pivot = true
		studio.status.text = "Click the canvas to set the custom pivot. Escape cancels."
	)
	studio.label(box, "Alignment and spacing", 14)
	axis = choice(box, ["X / horizontal", "Y or Z / depth", "Height"])
	reference_mode = choice(box, ["Use selection bounds", "Use reference object"])
	reference_mode.item_selected.connect(func(_index: int): refresh())
	reference_choice = choice(box, [])
	for entry in [["Align left / minimum", "min"], ["Align centers", "center"], ["Align right / maximum", "max"], ["Distribute centers evenly", "centers"], ["Distribute equal gaps", "gaps"]]:
		var action := Button.new()
		action.text = entry[0]
		box.add_child(action)
		action.pressed.connect(func(): apply_alignment(entry[1]))
	studio.label(box, "Gap between adjacent bases", 12)
	gap = studio.spin(box, -10000, 10000, 0.1, 1)
	var spacing := Button.new()
	spacing.text = "Match this spacing"
	box.add_child(spacing)
	spacing.pressed.connect(func(): apply_alignment("spacing"))
	context = studio.label(box, "", 12)
	context.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func choice(parent: Node, labels: Array) -> OptionButton:
	var control := OptionButton.new()
	control.fit_to_longest_item = false
	control.clip_text = true
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for text in labels: control.add_item(text)
	parent.add_child(control)
	return control

func target() -> String:
	var value: String = Fit.TARGETS[maxi(0, snap_target.selected)]
	return "center" if value == "top" and studio.mode == "2d" else value

func refresh() -> void:
	if updating or studio.documents.is_empty(): return
	updating = true
	var items: Array = studio.selection_items()
	var previous: String = str(reference_choice.get_item_metadata(reference_choice.selected)) if reference_choice.selected >= 0 else ""
	reference_choice.clear()
	for item in items:
		reference_choice.add_item(item.get("name", studio.library.assets[item["asset"]]["name"]))
		reference_choice.set_item_metadata(reference_choice.item_count - 1, item["uid"])
		if item["uid"] == previous: reference_choice.select(reference_choice.item_count - 1)
	reference_choice.disabled = reference_mode.selected == 0 or items.is_empty()
	for field in pivot_fields: field.editable = pivot_mode.selected == 2
	snap_target.set_item_disabled(Fit.TARGETS.find("top"), studio.mode == "2d")
	if studio.mode == "2d" and snap_target.selected == Fit.TARGETS.find("top"): snap_target.select(Fit.TARGETS.find("center"))
	snap_target.disabled = studio.mode == "2d" and studio.worlds["2d"].tile_lookup.has(studio.asset_id)
	context.text = "%d editable objects. X/Y are canvas pixels in 2D; X/Z are world units in 3D. Distribution keeps the first and last base fixed. Group center is the mean of object origins." % items.size()
	updating = false

func pivot(items: Array) -> Vector3:
	if pivot_mode.selected == 2: return Vector3(pivot_fields[0].value, pivot_fields[1].value, pivot_fields[2].value)
	var value := Vector3.ZERO
	for item in items: value += Vector3(item["position"][0], item["position"][1], item["position"][2])
	return value / items.size() if not items.is_empty() else value

func orbit_enabled(items: Array) -> bool:
	return not items.is_empty() and pivot_mode.selected != 1 and (items.size() > 1 or pivot_mode.selected == 2)

func set_custom(values: Array) -> void:
	for i in 3: pivot_fields[i].set_value_no_signal(float(values[i]))
	pivot_mode.select(2)
	picking_pivot = false
	refresh()

func scale_selection(value: float) -> void:
	var items: Array = studio.selection_items()
	if items.is_empty(): return
	var ratio: float = value / float(items[0]["scale"])
	if is_equal_approx(ratio, 1): return
	for item in items:
		if float(item["scale"]) * ratio < 0.1 or float(item["scale"]) * ratio > 8:
			studio.status.text = "Scaling would put an object outside the supported size range (0.1–8)."
			studio.refresh_controls()
			return
	var origin: Vector3 = pivot(items)
	studio.current().checkpoint()
	for item in items:
		item["scale"] = float(item["scale"]) * ratio
		if orbit_enabled(items):
			var position := Vector3(item["position"][0], item["position"][1], item["position"][2])
			position = origin + (position - origin) * ratio
			item["position"] = [position.x, position.y, position.z]
	studio.changed()
	studio.status.text = "Scaled %d objects around %s." % [items.size(), pivot_mode.get_item_text(pivot_mode.selected)]

func bounds(item: Dictionary) -> AABB:
	var position: Array = item["position"]
	if studio.mode == "3d":
		var box: AABB = Fit.footprint_bounds(item, studio.mode, studio.library)
		box.position += Vector3(position[0], position[1], position[2])
		return box
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for corner in ["corner_0", "corner_x", "corner_z", "corner_xz"]:
		var point: Array = Fit.anchor_position(item, "2d", studio.library, corner)
		low = low.min(Vector2(point[0], point[1]))
		high = high.max(Vector2(point[0], point[1]))
	return AABB(Vector3(low.x, low.y, position[2]), Vector3(high.x - low.x, high.y - low.y, 0))

func alignment_plan(operation: String) -> Dictionary:
	var items: Array = studio.selection_items()
	if items.size() < (3 if operation in ["centers", "gaps"] else 2): return {}
	var component: int = 0 if axis.selected == 0 else ((1 if studio.mode == "2d" else 2) if axis.selected == 1 else (2 if studio.mode == "2d" else 1))
	var entries: Array = []
	var total: AABB
	for item in items:
		var box: AABB = bounds(item)
		total = box if entries.is_empty() else total.merge(box)
		entries.append({"item": item, "low": box.position[component], "high": box.end[component], "size": box.size[component], "center": box.get_center()[component]})
	var reference_uid: String = str(reference_choice.get_item_metadata(reference_choice.selected)) if reference_mode.selected == 1 and reference_choice.selected >= 0 else ""
	var reference_box: AABB = total
	for entry in entries:
		if entry["item"]["uid"] == reference_uid: reference_box = bounds(entry["item"])
	var plan: Dictionary = {}
	if operation in ["min", "center", "max"]:
		var key: String = {"min": "low", "center": "center", "max": "high"}[operation]
		var destination: float = reference_box.position[component] if operation == "min" else (reference_box.end[component] if operation == "max" else reference_box.get_center()[component])
		for entry in entries:
			var values: Array = entry["item"]["position"].duplicate()
			values[component] += destination - entry[key]
			plan[entry["item"]["uid"]] = values
	else:
		entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var key: String = "center" if operation == "centers" else "low"
			return a[key] < b[key] if not is_equal_approx(a[key], b[key]) else a["item"]["uid"] < b["item"]["uid"]
		)
		var interval: float = gap.value
		if operation == "gaps":
			var occupied: float = 0
			for entry in entries: occupied += entry["size"]
			interval = (entries.back()["high"] - entries.front()["low"] - occupied) / (entries.size() - 1)
		var cursor: float = entries.front()["low"]
		var fixed: int = 0
		if operation == "spacing":
			for i in entries.size():
				if entries[i]["item"]["uid"] == reference_uid: fixed = i
			cursor = entries[fixed]["low"]
			for i in fixed: cursor -= entries[i]["size"] + interval
		for i in entries.size():
			var entry: Dictionary = entries[i]
			var destination: float = lerpf(entries.front()["center"], entries.back()["center"], float(i) / (entries.size() - 1)) if operation == "centers" else cursor
			var values: Array = entry["item"]["position"].duplicate()
			values[component] += destination - entry["center" if operation == "centers" else "low"]
			plan[entry["item"]["uid"]] = values
			cursor += entry["size"] + interval
	return plan

func apply_alignment(operation: String) -> void:
	var plan: Dictionary = alignment_plan(operation)
	if plan.is_empty():
		studio.status.text = "Select at least %d editable objects first." % (3 if operation in ["centers", "gaps"] else 2)
		return
	var changed: bool = false
	for uid in plan:
		if studio.current().object(uid)["position"] != plan[uid]: changed = true
	if not changed: return
	studio.current().checkpoint()
	for uid in plan: studio.current().object(uid)["position"] = plan[uid]
	studio.changed()
	studio.status.text = "Arranged %d objects. Undo restores the previous layout." % plan.size()

func settings() -> Dictionary:
	return {"snap_target": target(), "pivot_mode": pivot_mode.selected, "pivot": [pivot_fields[0].value, pivot_fields[1].value, pivot_fields[2].value], "axis": axis.selected, "gap": gap.value}

func restore(value: Dictionary) -> void:
	snap_target.select(maxi(0, Fit.TARGETS.find(value.get("snap_target", "base"))))
	pivot_mode.select(clampi(int(value.get("pivot_mode", 0)), 0, 2))
	var coordinates: Variant = value.get("pivot", [0, 0, 0])
	if preload("res://scripts/builder/document.gd").numbers(coordinates, 3):
		for i in 3: pivot_fields[i].set_value_no_signal(clampf(coordinates[i], -1000000, 1000000))
	axis.select(clampi(int(value.get("axis", 0)), 0, 2))
	gap.set_value_no_signal(clampf(float(value.get("gap", 1)), -10000, 10000))
	picking_pivot = false
	refresh()
