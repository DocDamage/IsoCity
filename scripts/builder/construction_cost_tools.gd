extends RefCounted

const Costs = preload("res://scripts/builder/construction_cost.gd")
const Economy = preload("res://scripts/builder/economy_plan.gd")
const Palette = preload("res://scripts/builder/asset_palette_policy.gd")
const Protection = preload("res://scripts/builder/cooperative_plan.gd")
const Floors = preload("res://scripts/builder/floor_plan.gd")
const Rooms = preload("res://scripts/builder/interiors.gd")
const Document = preload("res://scripts/builder/document.gd")
const Budget = preload("res://scripts/builder/rendering_budget.gd")
const Behavior = preload("res://scripts/builder/asset_behavior.gd")
const Repair = preload("res://scripts/builder/repair_assets.gd")
const Rotation = preload("res://scripts/builder/rotation.gd")
const Defaults = preload("res://scripts/builder/catalog_defaults.gd")
const Comparison = preload("res://scripts/builder/construction_cost_comparison.gd")
const MODEL_CRATE = "3d:HanX_Shop/Bottle_Crate"
const SPRITE_CRATE = "2d:crate"
const STATIC_FIELDS = ["uid", "asset", "position", "direction", "scale", "angle", "tilt",
	"name", "layer", "locked", "visible", "group", "notes", "colors"]

var studio: Control
var panel: ScrollContainer
var operation: OptionButton
var quote: Label
var estimate: Label
var review_button: Button
var comparison: RefCounted
var scan: RefCounted
var elapsed: float = 0.0
var provisional: int = 0
var used_ids: Dictionary = {}
var comparison_stamp: String = ""
var last_inputs: Array = []

func _init(host: Control) -> void:
	studio = host
	scan = Costs.new(studio.library)
	panel = ScrollContainer.new()
	panel.name = "Construction costs"
	panel.follow_focus = true
	panel.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	studio.workspace_layout.tabs.add_child(panel)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(box)
	operation = OptionButton.new()
	operation.accessibility_name = "Operation to quote"
	operation.fit_to_longest_item = false
	for title in ["Active canvas tool", "Duplicate selection", "Demolish selection", "Create starter interior"]:
		operation.add_item(title)
	box.add_child(operation)
	operation.item_selected.connect(func(_index: int): refresh())
	quote = result_label(box, "Exact economy quote")
	estimate = result_label(box, "Approximate render cost")
	review_button = Button.new()
	review_button.text = "Compare appearances"
	review_button.clip_text = true
	review_button.pressed.connect(review_comparison)
	box.add_child(review_button)
	var help: Label = studio.label(box,
		"Point at the canvas to update the tool quote. Outside the canvas it uses the center. For other actions, select objects and choose the operation above. Blueprints include their own construction review. Comparison uses the selected object, or the asset ready to place.", 12)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	comparison = Comparison.new(studio, apply_replacement)

func result_label(box: VBoxContainer, title: String) -> Label:
	var label: Label = studio.label(box, "", 13)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.accessibility_name = title
	label.focus_mode = Control.FOCUS_ALL
	return label

func show() -> void:
	studio.workspace_presets.set_focus(false)
	if studio.walking: studio.set_walking(false)
	if studio.get_viewport_rect().size.x < 1100 and not studio.consumer_shell.active:
		studio.workspace_layout.library_toggle.button_pressed = false
	studio.workspace_layout.inspector_toggle.button_pressed = true
	studio.workspace_layout.tabs.current_tab = panel.get_index()
	refresh()
	operation.grab_focus()

func tick(delta: float) -> void:
	if not panel.is_visible_in_tree() or comparison.dialog.visible: return
	elapsed += delta
	if elapsed < .3: return
	elapsed = 0.0
	var at: Vector2 = quote_pointer()
	if last_inputs != inputs(at): refresh()

func quote_pointer() -> Vector2:
	var pointer: Vector2 = studio.canvas_pointer()
	return pointer if Rect2(Vector2.ZERO, studio.canvas.size).has_point(pointer) else studio.canvas.size * .5

func inputs(at: Vector2) -> Array:
	var doc: RefCounted = studio.interior_tools.root_document(studio.mode)
	var camera: Node = studio.worlds[studio.mode].camera
	var view: Array = []
	if operation.selected == 0:
		view = [at, camera.get_global_transform(), camera.zoom if camera is Camera2D else camera.size,
			studio.canvas.size, studio.tool, studio.stroke, studio.road_drawing, studio.road_last, studio.ground_brush.drawing,
			studio.asset_id, studio.direction, studio.placement_angle, studio.placement_tilt, studio.scale_input.value,
			studio.snap_input.button_pressed, studio.height_input.value, studio.surface_input.button_pressed,
			studio.lanes_input.button_pressed, studio.connector_tools.enabled.button_pressed, studio.arrange_tools.target(),
			studio.brush_input.value, studio.ground_brush.operation.selected, studio.ground_brush.enabled_input.button_pressed,
			studio.ground_brush.replace_only.button_pressed, studio.ground_brush.family(), studio.road_settings.settings(),
			studio.assembly_active.get("name", "")]
	return [studio.mode, studio.current().get_instance_id(), studio.interior_tools.uid,
		studio.current().get("floor_uid") if studio.interior_tools.editing() else "", studio.editor_feedback.revision,
		studio.cooperative_tools.session.revision, studio.library.project_palette_revision, studio.library.families.revision,
		doc.data.get("economy_account", {}).get("cash", 0), operation.selected,
		studio.selected_uid, studio.selected_uids.duplicate(), studio.selected_cell, view]

func uid() -> String:
	provisional += 1
	var value := "cost_preview_%d" % provisional
	while used_ids.has(value):
		provisional += 1
		value = "cost_preview_%d" % provisional
	return value

func scoped(root: Dictionary) -> Dictionary:
	if not studio.interior_tools.editing(): return root
	for item in root["objects"]:
		if item["uid"] == studio.interior_tools.uid:
			return Floors.room(item["interior"], studio.current().floor_uid)
	return {}

func changed_candidate(kind: int, at: Vector2) -> Dictionary:
	var doc: RefCounted = studio.interior_tools.root_document(studio.mode)
	var active: bool = kind == 0 and (studio.stroke or studio.road_drawing or studio.ground_brush.drawing)
	var before: Dictionary = doc.pending_before if active and not doc.pending_before.is_empty() else doc.data
	var after: Dictionary = doc.data.duplicate(true)
	var scope: Dictionary = scoped(after)
	if scope.is_empty(): return {"reason": "Finish opening the interior before quoting."}
	var selection: Array = studio.selection_items()
	var allowances: Dictionary = {}
	provisional = 0
	used_ids.clear()
	for item in scope["objects"]: used_ids[item["uid"]] = true
	var caption: String = operation.get_item_text(kind)
	match kind:
		0:
			var reason: String = apply_tool(scope, at)
			if not reason.is_empty(): return {"reason": reason}
			caption = "Active gesture total" if active else "Next canvas action"
		1:
			if selection.is_empty(): return {"reason": "Select editable objects to quote their duplication."}
			for item in selection: scope["objects"].append(studio.offset_copy(item, uid(), studio.duplicate_offset(), uid))
		2:
			var removed: Dictionary = {}
			for item in selection: removed[item["uid"]] = true
			if removed.is_empty() and studio.selected_tile().is_empty(): return {"reason": "Select editable objects or a ground tile to quote demolition."}
			if removed.is_empty():
				if studio.Layers.locked(scope, "Ground") or not studio.Layers.shown(scope, "Ground"): return {"reason": "Show and unlock Ground to remove the tile."}
				scope["tiles"].erase(studio.selected_tile())
			else:
				scope["objects"] = scope["objects"].filter(func(item: Dictionary) -> bool: return not removed.has(item["uid"]))
		3:
			if studio.interior_tools.editing() or selection.size() != 1 or selection[0].has("interior") or not Behavior.for_asset(selection[0]["asset"], studio.library).get("building", false):
				return {"reason": "Select one exterior building without an owned interior."}
			var item: Dictionary = scope["objects"][scope["objects"].find(selection[0])]
			var room: Dictionary = Rooms.creation_check(item, studio.mode, studio.library)
			if not room["ok"]: return {"reason": room["reason"]}
			item["interior"] = room["room"]
			allowances = Economy.starter_holdings(after, item["uid"], studio.library)
	return finish_quote(before, after, caption, allowances)

func finish_quote(before: Dictionary, after: Dictionary, caption: String, allowances: Dictionary = {}) -> Dictionary:
	var policy: Dictionary = Palette.check(before, after, studio.library)
	if not policy["ok"]: return {"reason": policy["reason"]}
	var reason: String = shared_restriction(before, after)
	if not reason.is_empty(): return {"reason": reason}
	var value: Dictionary = Economy.quote(before, after, studio.library, allowances)
	return {"before": before, "after": after, "quote": value, "caption": caption}

func shared_restriction(before: Dictionary, after: Dictionary) -> String:
	var session: Node = studio.cooperative_tools.session
	if not session.connected or session.role != "client": return ""
	var other: String = "3d" if studio.mode == "2d" else "2d"
	var base: Dictionary = {other: studio.interior_tools.root_document(other).data, studio.mode: before}
	var proposed: Dictionary = base.duplicate(false)
	proposed[studio.mode] = after
	return Protection.allowed(base, proposed, session.local_id, studio.library)

func apply_tool(scope: Dictionary, at: Vector2) -> String:
	var tool: String = studio.tool
	if tool == "place":
		if studio.asset_id.is_empty(): return "Choose an asset to quote placement."
		if not studio.assembly_active.is_empty(): return "Review this assembly in Blueprints to quote all of its contents."
		if not Palette.allowed(studio.asset_id, studio.library): return Palette.excluded(studio.asset_id, studio.library)
		var reason: String = studio.editor_feedback.blocked_reason()
		if not reason.is_empty(): return reason
		if studio.ground_brush.active():
			studio.ground_brush.propose(scope, at, uid)
			return ""
		var pose: Dictionary = studio.placement(at)
		var diagnostic: Dictionary = studio.editor_feedback.diagnostics(at, pose)
		if diagnostic.get("blocked", false): return diagnostic["text"]
		var stroke_key: String = str(pose["position"]) + ":" + pose["direction"] + ":" + str(studio.placement_tilt) + ":" + str(studio.placement_angle)
		if not studio.stroke or not studio.stroke_cells.has(stroke_key):
			scope["objects"].append(studio.proposed_placement(pose, uid()))
		return ""
	if tool in ["road", "road_erase", "crossing"]:
		var diagnostic: Dictionary = studio.editor_feedback.diagnostics(at, {})
		if diagnostic.get("blocked", false): return diagnostic["text"]
		var cell: Vector2i = studio.Roads.cell_at(studio.worlds[studio.mode].point(at, false, 0), studio.mode)
		if tool == "crossing":
			var network: Dictionary = studio.Roads.lookup(scope)
			var record: Dictionary = network.get(studio.Roads.key(cell), {})
			if not record.is_empty(): record["crossing"] = not record.get("crossing", false)
		else:
			studio.Roads.paint(scope, studio.road_last if studio.road_drawing else cell, cell, tool == "road_erase", studio.road_settings.settings())
		return ""
	if tool == "erase":
		var target: String = studio.worlds[studio.mode].pick(at)
		if not target.is_empty():
			scope["objects"] = scope["objects"].filter(func(item: Dictionary) -> bool: return item["uid"] != target)
		elif studio.mode == "2d" and studio.Layers.shown(scope, "Ground") and not studio.Layers.locked(scope, "Ground"):
			var point: Array = studio.worlds[studio.mode].point(at, true, 0)
			var cell: Vector2i = IsoMath.world_to_tile(Vector2(point[0], point[1]))
			scope["tiles"] = scope["tiles"].filter(func(tile: Dictionary) -> bool: return tile["cell"] != [cell.x, cell.y])
		return ""
	return "Choose a placement, ground, road or eraser tool, or select a different operation."

func refresh() -> void:
	var at: Vector2 = quote_pointer()
	last_inputs = inputs(at)
	var draft: Dictionary = changed_candidate(operation.selected, at)
	quote.text = "Exact economy quote"
	estimate.text = ""
	if draft.has("quote"):
		quote.text = draft["caption"] + "\n" + Costs.quote_text(draft["quote"])
		estimate.text = scan.render_text(draft["before"], draft["after"])
	else: quote.text += "\n" + draft["reason"]
	review_button.disabled = comparison_options().is_empty()

func preview_item() -> Dictionary:
	var selected: Array = studio.selection_items()
	if selected.size() == 1: return selected[0]
	if studio.library.assets.has(studio.asset_id):
		return studio.proposed_placement({"position": [0, 0, 0], "direction": studio.direction}, "")
	return {}

func comparison_options() -> Dictionary:
	var item: Dictionary = preview_item()
	if item.is_empty(): return {}
	var asset: Dictionary = studio.library.assets.get(item["asset"], {})
	if asset.is_empty() or not Repair.available(item["asset"], studio.library, {}): return {}
	var profile: Dictionary = Budget.profile(asset)
	if not profile.is_empty() and ResourceLoader.exists(profile["full"]["path"], "PackedScene"):
		return {"source": item, "profile": profile}
	var replacement: Dictionary = alternative(item)
	return {} if replacement.is_empty() else {"source": item, "replacement": replacement}

func alternative(item: Dictionary) -> Dictionary:
	var id: String = item["asset"]
	var source: Dictionary = studio.library.assets[id]
	var candidates: Array = []
	if studio.mode == "2d" and id == MODEL_CRATE: candidates.append(SPRITE_CRATE)
	for variant in studio.library.families.options(source, studio.library.assets):
		candidates.append(variant["id"])
	for next in candidates:
		if next == id or not studio.library.assets.has(next) or not Repair.available(next, studio.library, {}): continue
		var result: Dictionary = item.duplicate(true)
		result["asset"] = next
		if next == SPRITE_CRATE and id == MODEL_CRATE:
			var direction: String = Rotation.compass_name(float(item["direction"]))
			var views: Array = studio.library.directions(next)
			result["direction"] = direction if direction in views else str(views[0])
			result.erase("angle")
			result.erase("tilt")
		elif not studio.library.valid_direction(next, item["direction"]): continue
		return result
	return {}

func replacement_draft(source: Dictionary, target: Dictionary) -> Dictionary:
	if source.get("uid", "").is_empty(): return {"reason": "Place the asset to replace an existing instance."}
	if not source.get("colors", []).is_empty(): return {"reason": "Custom paint belongs to the original artwork. Compare the source appearances here."}
	if source["asset"] == MODEL_CRATE and not Vector2(source.get("tilt", [0, 0])[0], source.get("tilt", [0, 0])[1]).is_zero_approx():
		return {"reason": "The sprite cannot keep model tilt. Level the model before replacing it."}
	for key in source:
		if key not in STATIC_FIELDS: return {"reason": "This object has authored settings. Its existing asset remains in use."}
	var before: Dictionary = studio.interior_tools.root_document(studio.mode).data
	var after: Dictionary = before.duplicate(true)
	var scope: Dictionary = scoped(after)
	if scope.is_empty() or not scope["objects"].has(source): return {"reason": "Select the source object again."}
	var from: String = source["asset"]
	var to: String = target["asset"]
	if Behavior.for_asset(from, studio.library) != Behavior.for_asset(to, studio.library) or Defaults.reviewed(to) or studio.library.is_ground_tile(to):
		return {"reason": "These appearances have different placement behavior."}
	if not studio.Layers.editable(scope, source, studio.library) or not studio.Layers.editable(scope, target, studio.library):
		return {"reason": "Show and unlock both assets’ layers before replacement."}
	scope["objects"][scope["objects"].find(source)] = target.duplicate(true)
	if not Document.valid(after, studio.mode, studio.library): return {"reason": "This replacement would leave invalid city references."}
	return finish_quote(before, after, "Replace selected instance")

func review_comparison() -> void:
	var options: Dictionary = comparison_options()
	if options.is_empty(): return
	comparison_stamp = ""
	var source: Dictionary = options["source"]
	var target: Dictionary = options.get("replacement", {})
	var profile: Dictionary = options.get("profile", {})
	if not profile.is_empty():
		comparison.open(source, source, profile, scan, "The lighter edition is already used in regular views. Photo can show the full-detail edition.", false)
		return
	var draft: Dictionary = replacement_draft(source, target)
	var allowed: bool = draft.has("quote") and draft["quote"]["ok"]
	var text: String = Costs.quote_text(draft["quote"]) if draft.has("quote") else draft["reason"]
	if allowed: comparison_stamp = stamp(draft)
	comparison.open(source, target, {}, scan, text, allowed)

func stamp(draft: Dictionary) -> String:
	return JSON.stringify([studio.mode, studio.current().get_instance_id(), studio.library.project_palette_revision,
		studio.cooperative_tools.session.revision, draft["before"], draft["after"]]).sha256_text()

func apply_replacement(source: Dictionary, target: Dictionary) -> void:
	studio.finish_edit(studio.canvas_pointer())
	var draft: Dictionary = replacement_draft(source, target)
	if not draft.has("quote") or not draft["quote"]["ok"] or comparison_stamp != stamp(draft):
		comparison.note.text = "The city or quote changed. Close the comparison and review again."
		comparison.replace.disabled = true
		return
	var doc: RefCounted = studio.current()
	doc.checkpoint()
	doc.data["objects"][doc.data["objects"].find(source)] = target.duplicate(true)
	studio.changed()
	comparison.dialog.hide()
	studio.status.text = "Replaced the selected appearance. Undo restores the original."
	refresh()
