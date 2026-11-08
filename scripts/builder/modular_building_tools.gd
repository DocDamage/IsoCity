extends RefCounted

const Plan = preload("res://scripts/builder/modular_building_plan.gd")
const Cutouts = preload("res://scripts/builder/floor_cutouts_3d.gd")
const Economy = preload("res://scripts/builder/economy_plan.gd")
const Palette = preload("res://scripts/builder/asset_palette_policy.gd")
const Protection = preload("res://scripts/builder/cooperative_plan.gd")
const Factory = preload("res://scripts/builder/asset_instance.gd")

var studio: Control
var panel: ScrollContainer
var rooms: OptionButton
var kits: OptionButton
var bays: OptionButton
var kinds: OptionButton
var x: SpinBox
var z: SpinBox
var draw_button: Button
var add_button: Button
var close_button: Button
var opening_button: Button
var review_button: Button
var apply_button: Button
var detach_button: Button
var message: Label
var context: Array = []
var rooms_stamp: int = 0
var request: Dictionary = {}
var reviewed: Dictionary = {}
var bay_geometry: Dictionary = {}
var drawing: bool = false
var ghosts: Node3D

func _init(host: Control) -> void:
	studio = host
	panel = ScrollContainer.new()
	panel.name = "Rooms"
	panel.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.follow_focus = true
	studio.workspace_layout.tabs.add_child(panel)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	panel.add_child(body)
	studio.label(body, "Modular rooms", 17)
	var intro: Label = studio.label(body, "Fit Model world walls and openings to a drawn outline.", 12)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rooms = choice(body, "Room to edit")
	rooms.item_selected.connect(select_room)
	kits = choice(body, "Module kit")
	for id in Plan.kits():
		kits.add_item(Plan.kits()[id]["name"])
		kits.set_item_metadata(kits.item_count - 1, id)
	kits.item_selected.connect(func(_index: int):
		request["kit"] = chosen(kits)
		invalidate()
		refresh_bays())
	draw_button = button(body, "Draw room outline", begin_outline)
	var coordinates := HBoxContainer.new()
	body.add_child(coordinates)
	x = coordinate(coordinates, "Corner X")
	z = coordinate(coordinates, "Corner Z")
	add_button = button(body, "Add corner", func(): add_corner(Vector2(x.value, z.value)))
	close_button = button(body, "Close outline", close_outline)
	button(body, "Undo last corner", remove_corner)
	bays = choice(body, "Wall bay")
	kinds = choice(body, "Opening type")
	for title in ["Solid wall", "Open doorway", "Window"]: kinds.add_item(title)
	bays.item_selected.connect(func(_index: int): sync_opening())
	opening_button = button(body, "Set opening", set_opening)
	button(body, "Clear draft openings", func():
		request["openings"] = {}
		invalidate()
		refresh_bays())
	review_button = button(body, "Review room", review)
	message = studio.label(body, "", 13)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	apply_button = button(body, "Build reviewed room", apply)
	detach_button = button(body, "Detach from outline", detach)
	var note: Label = studio.label(body, "Click corners on the canvas or enter coordinates. Close the outline, choose any doorway or window bays, then review. Detaching keeps your parts and joints.", 12)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	update_buttons()

func button(parent: Node, title: String, action: Callable) -> Button:
	var control := Button.new()
	control.text = title
	control.clip_text = true
	parent.add_child(control)
	control.pressed.connect(action)
	return control

func choice(parent: Node, title: String) -> OptionButton:
	studio.label(parent, title, 12)
	var control := OptionButton.new()
	control.fit_to_longest_item = false
	control.clip_text = true
	control.accessibility_name = title
	parent.add_child(control)
	return control

func coordinate(parent: Node, title: String) -> SpinBox:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	studio.label(column, title, 12)
	var field: SpinBox = studio.spin(column, -10000, 10000, 2, 0)
	field.accessibility_name = title
	field.get_line_edit().custom_minimum_size.x = 35
	return field

func chosen(control: OptionButton) -> String:
	return str(control.get_item_metadata(control.selected)) if control.selected >= 0 else ""

func floor_uid() -> String:
	return studio.current().floor_uid if studio.interior_tools.editing() else "ground"

func scope() -> Array:
	return [studio.mode, studio.current(), studio.interior_tools.uid, floor_uid()]

func show() -> void:
	studio.workspace_presets.set_focus(false)
	if studio.walking: studio.set_walking(false)
	studio.workspace_layout.inspector_toggle.button_pressed = true
	studio.workspace_layout.tabs.current_tab = panel.get_index()
	studio.workspace_layout.tabs.get_tab_bar().call_deferred("ensure_tab_visible", panel.get_index())
	synchronize()
	var item: Dictionary = studio.current().object(studio.selected_uid)
	var group: String = item.get("group", "")
	for index in range(1, rooms.item_count):
		if rooms.get_item_metadata(index) != group: continue
		rooms.select(index)
		select_room(index)
		break

func synchronize() -> void:
	if studio.documents.is_empty(): return
	var active: Array = scope()
	var data: Dictionary = studio.current().data
	var stamp: int = hash([data.get("modular_rooms", []), data.get("group_names", {})])
	if active == context and stamp == rooms_stamp: return
	var previous: String = chosen(rooms) if active == context else ""
	context = active
	rooms_stamp = stamp
	rooms.clear()
	rooms.add_item("New modular room")
	rooms.set_item_metadata(0, "")
	var selected: int = 0
	for record in data.get("modular_rooms", []):
		var uid: String = record["uid"]
		rooms.add_item(data.get("group_names", {}).get(uid, "Modular room"))
		rooms.set_item_metadata(rooms.item_count - 1, uid)
		if uid == previous: selected = rooms.item_count - 1
	rooms.select(selected)
	select_room(selected)

func select_room(_index: int) -> void:
	invalidate()
	drawing = false
	var uid: String = chosen(rooms)
	request = {"uid": Plan.new_identity(), "kit": chosen(kits), "outline": [], "openings": {}}
	for saved in studio.current().data.get("modular_rooms", []):
		if saved["uid"] == uid: request = saved.duplicate(true)
	for index in kits.item_count:
		if kits.get_item_metadata(index) == request["kit"]: kits.select(index)
	refresh_bays()
	if studio.mode != "3d":
		message.text = "Switch to Model world. This kit needs native geometry for both faces and openings."
	elif uid.is_empty():
		message.text = "Draw a room on the 2-unit grid. Walls fit whole 4-unit bays between corners."
	else:
		message.text = "Review the saved outline, or redraw it to resize. Your manual edits stay in place."
	update_buttons()

func refresh_bays() -> void:
	var selected: String = chosen(bays)
	bays.clear()
	if request.is_empty(): return
	var kit: Dictionary = Plan.kits().get(request["kit"], {})
	var geometry: Dictionary = Plan.layout(kit, request["outline"], {})
	bay_geometry = geometry.get("bays", {})
	if geometry["ok"]:
		var keys: Array = geometry["bays"].keys()
		keys.sort()
		for key in request["openings"]:
			if not keys.has(key): keys.append(key)
		var next: int = 0
		for key in keys:
			var parts: PackedStringArray = key.split("/")
			var label: String = "%s at %s, %s" % [parts[0].to_upper(), parts[1], parts[2]] if parts.size() == 3 else key
			if not geometry["bays"].has(key): label += " · moved"
			bays.add_item(label)
			bays.set_item_metadata(bays.item_count - 1, key)
			if selected == key: next = bays.item_count - 1
		if not keys.is_empty(): bays.select(next)
	sync_opening()
	update_buttons()

func sync_opening() -> void:
	kinds.select(["wall", "door", "window"].find(request.get("openings", {}).get(chosen(bays), "wall")))

func set_opening() -> void:
	var key: String = chosen(bays)
	if key.is_empty(): return
	if kinds.selected == 0: request["openings"].erase(key)
	else: request["openings"][key] = ["wall", "door", "window"][kinds.selected]
	invalidate()
	refresh_bays()
	message.text = "Opening updated in the draft. Review clearance before building."

func begin_outline() -> void:
	if studio.mode != "3d" or chosen(kits).is_empty(): return
	studio.finish_edit(studio.canvas_pointer())
	studio.set_tool("modular_room")
	studio.clear_assembly()
	request["outline"] = []
	invalidate()
	drawing = true
	message.text = "Click successive right-angle corners, or add them by coordinates."
	refresh_bays()

func point_at(screen: Vector2) -> Vector2:
	var at: Array = studio.worlds["3d"].point(screen, false, 0.0)
	return Vector2(at[0], at[2]).snapped(Vector2.ONE * 2)

func add_corner(at: Vector2) -> void:
	if not drawing: return
	var outline: Array = request["outline"]
	var pair: Array = [roundi(at.x), roundi(at.y)]
	if not Plan.point(pair): return
	if not outline.is_empty():
		if pair == outline[0] and outline.size() >= 4: close_outline(); return
		var last: Array = outline[-1]
		if pair == last or (pair[0] != last[0] and pair[1] != last[1]):
			message.text = "Choose a new corner along the same X or Z axis."
			return
	if outline.size() >= Plan.MAX_CORNERS: return
	outline.append(pair)
	message.text = "%d corners. Close the outline when the boundary is ready." % outline.size()
	studio.status.text = message.text
	update_buttons()

func remove_corner() -> void:
	if drawing and not request["outline"].is_empty():
		request["outline"].pop_back()
		update_buttons()

func close_outline() -> void:
	if not drawing: return
	var geometry: Dictionary = Plan.layout(Plan.kits().get(request["kit"], {}), request["outline"], {})
	if not geometry["ok"]:
		message.text = geometry["reason"]
		return
	drawing = false
	refresh_bays()
	message.text = "Outline closed. Set openings in the wall bays, then review."
	studio.status.text = message.text

func input(event: InputEvent) -> bool:
	if studio.tool != "modular_room" or studio.mode != "3d": return false
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and drawing: add_corner(point_at(event.position))
			return true
		if event.button_index == MOUSE_BUTTON_RIGHT and drawing:
			if event.pressed: remove_corner()
			return true
	return false

func invalidate() -> void:
	reviewed = {}
	if is_instance_valid(ghosts): ghosts.free()
	ghosts = null
	update_buttons()

func cancel() -> void:
	drawing = false
	invalidate()
	if not request.is_empty(): select_room(rooms.selected)

func update_buttons() -> void:
	var model: bool = studio.mode == "3d"
	draw_button.disabled = not model or chosen(kits).is_empty()
	add_button.disabled = not model or not drawing
	close_button.disabled = not model or not drawing or request.get("outline", []).size() < 4
	opening_button.disabled = not model or drawing or bays.item_count == 0
	review_button.disabled = not model or drawing or request.get("outline", []).size() < 4
	apply_button.disabled = reviewed.is_empty()
	detach_button.disabled = not model or chosen(rooms).is_empty()

func enclosing_plan(next: Dictionary) -> Dictionary:
	var exterior: Dictionary = studio.interior_tools.root_document(studio.mode).data
	if not studio.interior_tools.editing():
		return {"exterior": next, "before": exterior, "root": next}
	var floor: String = floor_uid()
	var root: Dictionary = studio.current().canonical.data.duplicate(true)
	if floor == "ground": root = next
	else:
		for entry in root["floors"]:
			if entry["uid"] == floor: entry["room"] = next
	var changed: Dictionary = exterior.duplicate(true)
	for item in changed["objects"]:
		if item["uid"] == studio.interior_tools.uid: item["interior"] = root
	return {"exterior": changed, "before": exterior, "root": root}

func validate_candidate(next: Dictionary) -> Dictionary:
	var candidate: Dictionary = enclosing_plan(next)
	var before: Dictionary = candidate["before"]
	var after: Dictionary = candidate["exterior"]
	var content: Dictionary = Palette.check(before, after, studio.library)
	if not content["ok"]: return Plan.failure(content["reason"])
	var session: Node = studio.cooperative_tools.session
	if session.connected and session.role == "client":
		var pixel: Dictionary = studio.interior_tools.root_document("2d").data
		var reason: String = Protection.allowed({"2d": pixel, "3d": before}, {"2d": pixel, "3d": after}, session.local_id, studio.library)
		if not reason.is_empty(): return Plan.failure(reason)
	var quote: Dictionary = Economy.quote(before, after, studio.library)
	if not quote["ok"]: return Plan.failure(quote["reason"])
	candidate["quote"] = quote
	candidate["ok"] = true
	return candidate

func prepare() -> Dictionary:
	if scope() != context or studio.mode != "3d": return Plan.failure("The active room or floor changed.")
	var ceiling: float = INF
	var holes: Array = []
	if studio.interior_tools.editing():
		var root: Dictionary = studio.current().canonical.data
		var height: float = 0.0
		for floor in root.get("floors", []):
			if floor["uid"] == floor_uid(): height = float(floor["height"])
		for floor in root.get("floors", []):
			if floor["height"] > height: ceiling = minf(ceiling, floor["height"] - height)
		holes = Cutouts.holes(root, floor_uid())
	var proposal: Dictionary = Plan.propose(studio.current().data, request, studio.library, ceiling, holes)
	if not proposal["ok"]: return proposal
	var candidate: Dictionary = validate_candidate(proposal["data"])
	if not candidate["ok"]: return candidate
	proposal.merge(candidate)
	return proposal

func review() -> void:
	if review_button.disabled: return
	invalidate()
	var proposal: Dictionary = prepare()
	if not proposal["ok"]:
		message.text = proposal["reason"]
		return
	if proposal["data"] == studio.current().data:
		message.text = "The saved room matches the draft."
		return
	if studio.tool != "modular_room": studio.set_tool("modular_room")
	reviewed = proposal
	reviewed["stamp"] = studio.content_digest()
	var quote: Dictionary = proposal["quote"]
	message.text = "%d new parts, %d replaced, %d manual edits preserved." % [
		proposal["created"], proposal["removed"], proposal["preserved_edits"]]
	message.text += "\nDoorway access checked." if "door" in request["openings"].values() else "\nThe draft has no doorway."
	if quote["enabled"]: message.text += "\nConstruction %d · refund %d credits." % [quote["construction"], quote["refund"]]
	studio.status.text = "Room preview ready. Review the details before building."
	update_buttons()
	show_ghosts(proposal["data"])

func show_ghosts(data: Dictionary) -> void:
	var existing: Dictionary = {}
	for item in studio.current().data["objects"]: existing[item["uid"]] = true
	ghosts = Node3D.new()
	ghosts.name = "ModularRoomPreview"
	studio.worlds["3d"].add_child(ghosts)
	for item in data["objects"]:
		if existing.has(item["uid"]): continue
		var instance: Node3D = Factory.make(studio.library, item["asset"], "3d", false)
		ghosts.add_child(instance)
		var at: Array = item["position"]
		instance.position = Vector3(at[0], at[1], at[2])
		Factory.pose(instance, item)
		for mesh in instance.find_children("*", "MeshInstance3D", true, false):
			mesh.transparency = .42

func apply() -> void:
	if reviewed.is_empty(): return
	if reviewed["stamp"] != studio.content_digest():
		invalidate()
		message.text = "The layout changed. Review again before building."
		return
	var latest: Dictionary = prepare()
	if not latest["ok"] or latest["data"] != reviewed["data"] or latest["quote"] != reviewed["quote"]:
		invalidate()
		message.text = latest.get("reason", "The room or price changed. Review again before building.")
		return
	commit(latest, "Built the reviewed modular room. Undo restores the previous layout.")

func detach() -> void:
	var uid: String = chosen(rooms)
	if uid.is_empty() or scope() != context: return
	var candidate: Dictionary = validate_candidate(Plan.detached(studio.current().data, uid))
	if not candidate["ok"]: message.text = candidate["reason"]; return
	commit(candidate, "Detached the room outline. All placed modules and joints remain editable.")

func commit(candidate: Dictionary, success: String) -> void:
	var uid: String = request["uid"]
	var doc: RefCounted = studio.current()
	var accepted: bool = false
	invalidate()
	drawing = false
	if studio.interior_tools.editing():
		var floors: RefCounted = studio.interior_tools.floor_tools
		if not floors.prepare(): return
		floors.commit({"ok": true, "changed": true, "data": candidate["root"]}, floor_uid())
		accepted = is_same(doc.canonical.data, candidate["root"])
	else:
		doc.checkpoint()
		doc.data = candidate["exterior"]
		studio.changed()
		doc.finish_checkpoint(true)
		accepted = is_same(doc.data, candidate["exterior"])
	studio.set_tool("select")
	synchronize()
	for index in range(1, rooms.item_count):
		if rooms.get_item_metadata(index) == uid:
			rooms.select(index)
			select_room(index)
			break
	message.text = success if accepted else "The room could not be committed. Check the current project restrictions."
	studio.status.text = message.text

func overlay_paths(inside: bool) -> Array:
	var result: Array = []
	if studio.mode != "3d" or studio.tool != "modular_room" or request.is_empty() or context != scope():
		return result
	var outline := PackedVector2Array()
	for point in request["outline"]: outline.append(studio.overlay_position([point[0], .04, point[1]], 0))
	if drawing and inside and not outline.is_empty():
		var next: Vector2 = point_at(studio.canvas_pointer())
		outline.append(studio.overlay_position([next.x, .04, next.y], 0))
	elif not drawing and not outline.is_empty(): outline.append(outline[0])
	if outline.size() > 1: result.append({"points": outline, "opening": false})
	if not drawing and not request["openings"].is_empty():
		for key in request["openings"]:
			if not bay_geometry.has(key): continue
			var bay: Dictionary = bay_geometry[key]
			var at: Vector2 = bay["position"]
			var direction: Vector2 = Vector2.RIGHT if bay["direction"] == 0 else Vector2.DOWN
			var a: Vector2 = at - direction * .5
			var b: Vector2 = at + direction * .5
			var y: float = .08 if request["openings"][key] == "door" else 1.4
			result.append({"points": PackedVector2Array([studio.overlay_position([a.x,y,a.y], 0),
				studio.overlay_position([b.x,y,b.y], 0)]), "opening": true})
	return result
