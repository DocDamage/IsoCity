extends RefCounted

const Plan = preload("res://scripts/builder/connector_plan.gd")
const Layers = preload("res://scripts/builder/layers.gd")
const Protection = preload("res://scripts/builder/cooperative_plan.gd")
const RADIUS = 28.0

var studio: Control
var enabled: CheckButton
var utility: CheckButton
var markers_visible: CheckButton
var source_choice: OptionButton
var status: Label
var assets_stamp: String = ""
var cached_document: Variant
var frames: Array[Dictionary] = []
var heights: Dictionary = {}
var occupied: Dictionary = {}
var object_index: Dictionary = {}
var projected: Dictionary = {}
var blocking_instances: Dictionary = {}
var clearance := SphereShape3D.new()
var camera_stamp: Variant
var choices: Array = []
var selected: String = ""
var previewed: String = ""
var presented: Array = []
var presented_at: Vector2 = Vector2.INF
var presented_scope: Array = []

func _init(host: Control, panel: ScrollContainer) -> void:
	studio = host
	clearance.radius = .055
	var root := VBoxContainer.new()
	var box: Control = panel.get_child(0)
	box.add_child(root)
	box.move_child(root, 0)
	panel.follow_focus = true
	studio.label(root, "Modular sockets", 14)
	enabled = CheckButton.new()
	enabled.text = "Snap to sockets"
	enabled.accessibility_name = "Snap to compatible modular sockets"
	root.add_child(enabled)
	enabled.toggled.connect(func(_value: bool): selected = "")
	utility = CheckButton.new()
	utility.text = "Save pipe link"
	utility.accessibility_name = "Record a semantic pipe connection when placing"
	root.add_child(utility)
	markers_visible = CheckButton.new()
	markers_visible.text = "Connection markers"
	markers_visible.accessibility_name = "Show connection markers"
	markers_visible.button_pressed = true
	root.add_child(markers_visible)
	source_choice = OptionButton.new()
	source_choice.accessibility_name = "Source socket"
	source_choice.fit_to_longest_item = false
	source_choice.clip_text = true
	root.add_child(source_choice)
	source_choice.item_selected.connect(func(_index: int): selected = "")
	for step in [-1, 1]:
		var button := Button.new()
		button.text = "Previous socket" if step < 0 else "Next socket"
		root.add_child(button)
		button.pressed.connect(cycle.bind(step))
	status = studio.label(root, "Choose a calibrated module. Place its first piece, then hover near an open end.", 12)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.accessibility_name = "Socket placement status"

func show() -> void:
	if studio.walking:
		return
	studio.workspace_layout.inspector_toggle.button_pressed = true
	studio.workspace_layout.tabs.current_tab = studio.arrange_tools.panel.get_index()
	enabled.grab_focus()
	refresh_source(studio.placement_record())

func invalidate() -> void:
	cached_document = null
	camera_stamp = null
	choices.clear()
	selected = ""
	previewed = ""

func refresh_source(item: Dictionary) -> void:
	var stamp: String = studio.mode + "|" + item.get("asset", "") + "|" + item.get("direction", "")
	if stamp == assets_stamp:
		return
	assets_stamp = stamp
	source_choice.clear()
	source_choice.add_item("Nearest source end")
	source_choice.set_item_metadata(0, "")
	for socket in Plan.sockets(item, studio.mode):
		source_choice.add_item("Source end " + socket["id"].to_upper())
		source_choice.set_item_metadata(source_choice.item_count - 1, socket["id"])
	source_choice.select(0)
	selected = ""

func build_index(data: Dictionary) -> void:
	if not is_same(cached_document, data):
		cached_document = data
		camera_stamp = null
		frames.clear()
		object_index.clear()
		blocking_instances.clear()
		var objects: Dictionary = studio.worlds[studio.mode].instances
		heights = Plan.Terrain.lookup(data) if studio.mode == "2d" and Plan.Terrain.settings(data)["enabled"] else {}
		occupied = Plan.occupancy(data)
		for edge in data.get("utility_edges", []):
			for side in ["from", "to"]:
				occupied[Plan.socket_key(edge[side])] = true
		for item in data["objects"]:
			var node: Node = objects.get(item["uid"])
			if is_instance_valid(node) and Layers.layer(item, studio.library) != "Ground":
				blocking_instances[node.get_instance_id()] = item["uid"]
			if Plan.sockets(item, studio.mode).is_empty(): continue
			if not studio.library.assets.has(item["asset"]) or studio.library.assets[item["asset"]].get("unavailable", false):
				continue
			if not item.get("visible", true) or not Layers.shown(data, Layers.layer(item, studio.library)):
				continue
			object_index[item["uid"]] = item
			var rise: float = Plan.terrain_height(data, item, studio.mode, heights)
			frames.append_array(Plan.frames(item, studio.mode, rise))
	var world: Node = studio.worlds[studio.mode]
	var stamp: Variant = studio.viewport.get_canvas_transform() if studio.mode == "2d" else [world.camera.global_transform, world.camera.size, world.camera.fov, world.camera.projection, studio.viewport.size]
	if camera_stamp == stamp:
		return
	camera_stamp = stamp
	var visible: Array = []
	for frame in frames:
		if studio.mode == "3d" and world.camera.is_position_behind(frame["point"]):
			continue
		var projected_frame: Dictionary = frame.duplicate()
		projected_frame["screen"] = project(frame["point"])
		visible.append(projected_frame)
	projected = Plan.index(visible)

func project(point: Vector3) -> Vector2:
	if studio.mode == "2d":
		return studio.viewport.get_canvas_transform() * Vector2(point.x, point.y)
	return studio.worlds[studio.mode].camera.unproject_position(point)

func denied(target: Dictionary, data: Dictionary) -> String:
	var item: Dictionary = object_index[target["object_uid"]]
	if not Layers.editable(data, item, studio.library):
		return "The target socket belongs to a locked object or layer."
	var session: Node = studio.cooperative_tools.session
	if not session.connected or session.role != "client":
		return ""
	var outer: RefCounted = studio.interior_tools.root_document(studio.mode)
	var host: Dictionary = outer.object(studio.interior_tools.uid) if studio.interior_tools.editing() else item
	if host.is_empty():
		return "The target room is unavailable."
	var footprint: Rect2 = Protection.object_rect(host, studio.mode, studio.library)
	for area in outer.data.get("protected_areas", []):
		if area["owner"] != session.local_id and Protection.rect(area).intersects(footprint):
			return "Protected socket · " + area["name"]
	return ""

func obstruction(target: Dictionary) -> String:
	var world: Node = studio.worlds[studio.mode]
	var at: Vector3 = target["point"]
	var hits: Array
	if studio.mode == "2d":
		var query := PhysicsPointQueryParameters2D.new()
		query.position = Vector2(at.x, at.y)
		hits = world.get_world_2d().direct_space_state.intersect_point(query, 16)
	else:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = clearance
		query.transform.origin = at
		hits = world.get_world_3d().direct_space_state.intersect_shape(query, 16)
	for hit in hits:
		var node: Node = hit.get("collider")
		while is_instance_valid(node) and node != world:
			var uid: String = blocking_instances.get(node.get_instance_id(), "")
			if not uid.is_empty():
				if uid != target["object_uid"]:
					return "Another object blocks the socket."
				break
			node = node.get_parent()
	return ""

func cycle(step: int) -> void:
	if choices.is_empty() or not enabled.button_pressed or studio.walking or studio.tool != "place" or studio.worlds[studio.mode].exploration.photo.active or studio.modal_visible():
		return
	var index: int = choices.find(selected if choices.has(selected) else previewed)
	selected = choices[posmod(index + step if index >= 0 else (0 if step > 0 else -1), choices.size())]
	status.text = "Target %d of %d" % [choices.find(selected) + 1, choices.size()]

func scope() -> Array:
	return [studio.mode, studio.interior_tools.uid, studio.current().get("floor_uid")] if studio.interior_tools.editing() else [studio.mode]

func signature(choice: Dictionary) -> Array:
	if choice.get("target", {}).is_empty(): return []
	var target: Dictionary=choice["target"]
	var source: Dictionary=choice.get("source", {})
	return [target["object_uid"],target["socket"],target["point"],target["normal"],target["kind"],
		source.get("socket"),source.get("point"),choice.get("pose"),choice.get("blocked",false),choice.get("save",false)]

func present(at: Vector2, choice: Dictionary) -> void:
	presented=signature(choice) if markers_visible.button_pressed else []
	presented_at=at
	presented_scope=scope() if not presented.is_empty() else []

func preview_changed(at: Vector2,choice: Dictionary) -> bool:
	return (markers_visible.button_pressed and not presented.is_empty() and presented_scope==scope()
		and presented_at.distance_squared_to(at)<=1.0 and presented!=signature(choice))

func choose(at: Vector2, item: Dictionary, data: Dictionary) -> Dictionary:
	if not enabled.button_pressed or studio.walking or studio.tool != "place" or studio.worlds[studio.mode].exploration.photo.active:
		return {}
	refresh_source(item)
	var source_frames: Array[Dictionary] = Plan.frames(item, studio.mode)
	if source_frames.is_empty():
		choices.clear()
		previewed = ""
		status.text = "This source view has no calibrated socket."
		return {}
	build_index(data)
	var targets: Array = Plan.nearby(projected, at, RADIUS)
	previewed = ""
	var source_id: String = source_choice.get_item_metadata(source_choice.selected)
	var accepted: Dictionary = {}
	var first_reason: String = ""
	var first_target: Dictionary = {}
	var first_source: Dictionary = {}
	choices.clear()
	for target in targets:
		var key: String = Plan.socket_key(target)
		var rejection: String = denied(target, data)
		if rejection.is_empty() and occupied.has(key):
			rejection = "This socket is already connected."
		if rejection.is_empty():
			rejection = obstruction(target)
		if rejection.is_empty() and data.get("connections", []).size() >= Plan.LIMIT and (target["kind"] == "structure" or utility.button_pressed):
			rejection = "This floor has reached its connection limit."
		var best: Dictionary = {}
		var best_distance: float = INF
		var closest: Dictionary = {}
		var closest_distance: float = INF
		var blocked: bool=not rejection.is_empty()
		for source in source_frames:
			if not source_id.is_empty() and source["socket"] != source_id:
				continue
			var distance: float = project(source["point"]).distance_squared_to(target["screen"])
			if distance < closest_distance:
				closest=source
				closest_distance=distance
			if not blocked:
				var candidate: Dictionary = Plan.solve(item, source, target, studio.mode, data, heights)
				if not candidate["ok"]:
					rejection = candidate["reason"]
					continue
				if distance < best_distance:
					best = candidate
					best_distance = distance
		if best.is_empty():
			if first_reason.is_empty():
				first_reason = rejection
				first_target = target
				first_source = closest
			continue
		accepted[key] = best
		choices.append(key)
	if accepted.is_empty():
		selected = ""
		status.text = "Place a first piece or move within 28 pixels of a socket." if first_reason.is_empty() else first_reason
		return {"blocked": not first_reason.is_empty(), "reason": status.text, "target": first_target, "source": first_source}
	var nearest: String = Plan.socket_key(targets[0])
	if not accepted.has(selected) and not accepted.has(nearest):
		status.text = first_reason + " Use Next socket to choose another target."
		return {"blocked": true, "reason": status.text, "target": first_target, "source": first_source}
	var key: String = selected if accepted.has(selected) else nearest
	previewed = key
	var result: Dictionary = accepted[key]
	result["blocked"] = false
	var target: Dictionary = result["target"]
	result["save"] = target["kind"] == "structure" or utility.button_pressed
	var name: String = studio.library.assets[object_index[target["object_uid"]]["asset"]]["name"]
	status.text = "%s source %s → %s target %s · Face ends together · %d/%d" % [
		str(target["kind"]).capitalize(), result["source"]["socket"].to_upper(), name.replace("_"," "),
		target["socket"].to_upper(), choices.find(key)+1, choices.size()]
	if target["kind"] != "structure":
		status.text += " · " + ("link will be saved" if utility.button_pressed else "visual snap")
	result["reason"] = status.text
	return result

func record(data: Dictionary, item: Dictionary, choice: Dictionary) -> void:
	if not choice.get("ok", false):
		return
	var target: Dictionary = choice["target"]
	if not choice.get("save", target["kind"]=="structure" or utility.button_pressed):
		return
	if not data.has("connections"):
		data["connections"] = []
	data["connections"].append({
		"uid": "joint_" + Crypto.new().generate_random_bytes(16).hex_encode(),
		"kind": target["kind"],
		"from": {"object_uid": item["uid"], "socket": choice["source"]["socket"]},
		"to": {"object_uid": target["object_uid"], "socket": target["socket"]}
	})

func markers(choice: Dictionary) -> Array:
	if not markers_visible.button_pressed: return []
	var target: Dictionary = choice.get("target", {})
	if target.is_empty():
		return []
	var point: Vector2 = project(target["point"])
	var direction: Vector2 = project(target["point"] + target["normal"] * (12 if studio.mode == "2d" else .65)) - point
	var result: Array = [{"at": point, "direction": direction, "kind": target["kind"], "label": "Target " + target["socket"].to_upper(), "blocked": choice.get("blocked", false)}]
	var source: Dictionary = choice.get("source",{})
	if not source.is_empty():
		var source_at: Vector2=project(source["point"])
		var outward: Vector2=project(source["point"]+source["normal"]*(12 if studio.mode=="2d" else .65))-source_at
		result.append({"at": source_at, "direction": outward, "kind": source["kind"], "label": "Source " + source["socket"].to_upper(), "blocked": false, "source": true})
	return result
