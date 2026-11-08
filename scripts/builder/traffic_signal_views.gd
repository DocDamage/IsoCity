extends RefCounted

const Signals = preload("res://scripts/builder/traffic_control_plan.gd")
var heads: Dictionary = {}
var library: RefCounted
var variants: Dictionary = {}

func synchronize(data: Dictionary, instances: Dictionary, assets: RefCounted) -> void:
	if library != assets:
		variants.clear()
		library = assets
	var next: Dictionary = {}
	for item in data["objects"]:
		var binding: Dictionary = item.get("traffic_control", {})
		if binding.get("kind") != "signal" or Signals.profile(item["asset"]).get("kind") != "signal":
			continue
		var uid: String = item["uid"]
		var node: Node = instances.get(uid)
		if not is_instance_valid(node):
			continue
		var state: Dictionary = heads.get(uid, {})
		if state.get("node") != node:
			release(state)
			state = {"node": node, "side": int(binding["side"]), "uid": uid, "color": ""}
			if node is IsoObject:
				state["playing"] = node.playing
				node.playing = false
			else:
				var host: Node = node if node is Node3D else node.model
				var model: Node = host.get_node_or_null("Model") if is_instance_valid(host) else null
				if not is_instance_valid(model):
					continue
				state["model"] = model
				state["visible"] = model.visible
		state["side"] = int(binding["side"])
		next[uid] = state
	for uid in heads:
		if not next.has(uid):
			release(heads[uid])
	heads = next

func draw(plan: Dictionary, gates: RefCounted, now: float) -> void:
	var active: Dictionary = plan.get("controls", {}).get("active", {})
	var phases: Dictionary = {}
	for uid in heads:
		var state: Dictionary = heads[uid]
		if not is_instance_valid(state["node"]):
			continue
		var key: String = active.get(uid, "")
		var color: String = "red"
		if not key.is_empty():
			if not phases.has(key):
				phases[key] = gates.phase(plan, key, now)
			var axis: String = "x" if state["side"] % 2 == 0 else "y"
			if phases[key] == axis:
				color = "green"
			elif phases[key] == "amber_" + axis:
				color = "amber"
		apply(state, color)

func apply(state: Dictionary, color: String) -> void:
	var node: Node = state["node"]
	if node is IsoObject:
		var sprite: Sprite2D = node.get_node_or_null("Sprite2D")
		if is_instance_valid(sprite):
			var index: int = Signals.profile("2d:" + node.item_id)["frames"][color]
			if index < sprite.hframes:
				sprite.frame = index
		state["color"] = color
		return
	if state["color"] == color or not is_instance_valid(state["model"]):
		return
	var id: String = Signals.definitions().get("models", {}).get(color, "")
	if not library.assets.has(id):
		return
	if not variants.has(id):
		variants[id] = load(library.assets[id]["path"])
	var packed: PackedScene = variants[id]
	var variant: Node = packed.instantiate() if packed else null
	if not is_instance_valid(variant):
		return
	var model: Node = variant.get_node_or_null("Model")
	if is_instance_valid(model):
		if is_instance_valid(state.get("variant")):
			state["variant"].free()
		model.owner = null
		variant.remove_child(model)
		state["model"].get_parent().add_child(model)
		model.visible = state["visible"]
		state["model"].hide()
		state["variant"] = model
		state["color"] = color
		refresh_projection(node)
	variant.free()

func refresh_projection(node: Node) -> void:
	if node is Node2D and not node is IsoObject and is_instance_valid(node.viewport):
		node.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func release(state: Dictionary) -> void:
	if not is_instance_valid(state.get("node")):
		return
	var node: Node = state["node"]
	if node is IsoObject:
		node.playing = state.get("playing", true)
		node._update_frame()
	else:
		if is_instance_valid(state.get("variant")):
			state["variant"].free()
		if is_instance_valid(state.get("model")):
			state["model"].visible = state["visible"]
		refresh_projection(node)

func clear() -> void:
	for state in heads.values():
		release(state)
	heads.clear()
	variants.clear()
