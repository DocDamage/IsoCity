extends Node

signal harvested(receipt: Dictionary)

const Plan = preload("res://scripts/builder/garden_plan.gd")
const Props = preload("res://scripts/builder/prop_plan.gd")
const Weather = preload("res://scripts/builder/weather_plan.gd")
const Economy = preload("res://scripts/builder/economy_plan.gd")
const Factory = preload("res://scripts/builder/asset_instance.gd")

var exploration: Node
var water_network: Node
var weather_runtime: Node
var sites: Dictionary = {}
var crops: Dictionary = {}
var account: Dictionary = {}
var source: Dictionary = {}
var notice: String = ""
var paused: bool = false
var show_status: bool = false
var elapsed: float = 0.0
var last_water_tick: int = 0
var sequence: int = 0
var budget: bool = false
var signature: int = 0
var interior_view: bool = false
var displayed_season: String = ""
var displayed_zoom: Vector2 = Vector2.ONE
var views_visible: bool = false
var notice_uid: String = ""
var notice_seconds: float = 0.0
var markers: Dictionary = {}
var artwork: Dictionary = {}

func configure(data: Dictionary) -> void:
	interior_view = data.get("interior_room", false)
	if interior_view:
		refresh_views()
		return
	source = data
	var use_budget: bool = Economy.settings(data)["enabled"]
	if account.is_empty() or budget != use_budget:
		budget = use_budget
		reset()
	var enabled: bool = Plan.settings(data)
	var records: Array = Plan.selected_records(data) if enabled else []
	var next: int = hash([data.get("layers", {}), data.get("terrain", {}),
		data.get("terrain_vertices", []), data.get("water_cells", []), records]) if enabled else -1
	if next == signature:
		refresh_views()
		return
	signature = next
	sites = Plan.compile(data, exploration.library)
	for uid in crops.keys():
		var site: Dictionary = sites.get(uid, {})
		if site.is_empty() or not site["reason"].is_empty() or site["identity"] != crops[uid]["site_identity"]:
			crops.erase(uid)
			notice = "A changed garden site lost its preview crop. No harvest was paid."
	refresh_views()

func reset() -> void:
	crops.clear()
	account = Plan.fresh_account(budget)
	elapsed = 0.0
	paused = false
	notice = ""
	notice_uid = ""
	notice_seconds = 0.0
	last_water_tick = water_network.tick_count if is_instance_valid(water_network) else 0
	refresh_views()

func season() -> String:
	if is_instance_valid(weather_runtime) and weather_runtime.current_state.get("enabled", false):
		return weather_runtime.current_state["effective_season"]
	var value: Dictionary = Weather.state(source)
	return value["effective_season"] if value["enabled"] else "summer"

func active() -> bool:
	return exploration.enabled and not exploration.interior and not exploration.entering \
		and not interior_view and exploration.editor_scope.is_empty() and not exploration.photo.active and Plan.settings(source)

func advance(delta: float) -> void:
	if not active() or paused:
		if is_instance_valid(water_network): last_water_tick = water_network.tick_count
		return
	if crops.is_empty():
		if is_instance_valid(water_network): last_water_tick = water_network.tick_count
		return
	if not is_finite(delta) or delta <= 0.0: return
	if is_instance_valid(water_network) and water_network.tick_count != last_water_tick:
		last_water_tick = water_network.tick_count
		if water_network.graph.get("enabled", false) and not water_network.forecast:
			for uid in crops:
				if not sites[uid]["config"]["irrigation"] or is_ripe(crops[uid]): continue
				var served: int = water_network.served(uid)
				if served > 0: crops[uid]["moisture"] = mini(Plan.MAX_MOISTURE, crops[uid]["moisture"] + served)
	elapsed += minf(delta, .25)
	if elapsed < 1.0: return
	elapsed -= 1.0
	var current: String = season()
	for uid in crops:
		var crop: Dictionary = crops[uid]
		if is_ripe(crop) or crop["moisture"] == 0: continue
		crop["moisture"] -= 1
		if Plan.in_season(sites[uid], current): crop["growth"] += 1
	refresh_views()

func _process(delta: float) -> void:
	advance(delta)
	if notice_seconds > 0.0: notice_seconds -= delta
	var should_show: bool = showing()
	if should_show != views_visible or (should_show and not sites.is_empty() \
		and (displayed_season != season() or displayed_zoom != canvas_zoom())):
		refresh_views()

func prompt(uid: String) -> String:
	var text: String = "E · " + action(uid)
	if notice_uid == uid and notice_seconds > 0.0: text += " · " + notice
	return text

func is_ripe(crop: Dictionary) -> bool:
	var seconds: int = int(Plan.crops()[crop["kind"]]["seconds"]) - (2 if crop["composted"] else 0)
	return crop["growth"] >= seconds

func status(uid: String) -> String:
	var site: Dictionary = sites.get(uid, {})
	if site.is_empty(): return "Site unavailable"
	if not site["reason"].is_empty(): return site["reason"]
	if not Plan.growing_site(site["profile"]["role"]): return supply_action(site)
	var kind: String = site["config"]["crop"]
	var info: Dictionary = Plan.crops()[kind]
	var crop: Dictionary = crops.get(uid, {})
	if crop.is_empty():
		return "%s · empty" % info["name"] if Plan.in_season(site, season()) else "%s · out of season" % info["name"]
	if is_ripe(crop): return "%s · ready to harvest" % info["name"]
	var progress: String = "%d/%d s" % [crop["growth"], int(info["seconds"]) - (2 if crop["composted"] else 0)]
	if not Plan.in_season(site, season()): return "%s · dormant · %s" % [info["name"], progress]
	return "%s · %s · %s" % [info["name"], "dry" if crop["moisture"] == 0 else "growing", progress]

func supply_action(site: Dictionary) -> String:
	match site["profile"]["role"]:
		"seeds": return "Restock %s seeds" % Plan.crops()[site["config"]["crop"]]["name"].to_lower()
		"water": return "Fill watering can"
		"soil": return "Collect potting soil"
		"compost": return "Collect compost"
		"share": return "Share harvested produce"
	return ""

func action(uid: String) -> String:
	var site: Dictionary = sites[uid]
	if not site["reason"].is_empty(): return site["reason"]
	if paused: return "Garden preview paused"
	if not Plan.growing_site(site["profile"]["role"]): return supply_action(site)
	var crop: Dictionary = crops.get(uid, {})
	if crop.is_empty():
		return "Plant " + Plan.crops()[site["config"]["crop"]]["name"].to_lower() if Plan.in_season(site, season()) else status(uid)
	if is_ripe(crop): return "Harvest " + Plan.crops()[crop["kind"]]["name"].to_lower()
	if not Plan.in_season(site, season()): return status(uid)
	if crop["moisture"] <= 2: return "Water " + Plan.crops()[crop["kind"]]["name"].to_lower()
	if not crop["composted"] and account["stock"]["compost"] > 0: return "Work compost into bed"
	return status(uid)

func world_point(node: Node, point: Vector2, item: Dictionary) -> Variant:
	var mode: String = exploration.dimension
	var values: Array = Plan.Traffic.world(point, mode)
	if mode == "2d": return node.get_parent().to_global(Vector2(values[0], values[1]))
	var height: float = float(item["position"][1]) + float(node.get_meta("terrain_height", 0.0))
	return node.get_parent().to_global(Vector3(values[0], height, values[2]))

func nearby() -> Dictionary:
	if not active() or not is_instance_valid(exploration.player): return {}
	var best: Dictionary = {}
	var distance: float = INF
	var actor: Node = exploration.player
	for uid in sites:
		var site: Dictionary = sites[uid]
		var node: Node = exploration.instances.get(uid)
		if not is_instance_valid(node) or not node.is_visible_in_tree(): continue
		var bounds: Rect2 = site["rect"]
		if not bounds.has_area(): continue
		for side in Plan.Utility.SIDES:
			var point: Variant = world_point(node, Plan.Utility.side_point(bounds, side, .6), site["item"])
			var difference: Variant = point - actor.global_position
			var d: float = difference.length()
			if exploration.dimension == "2d":
				if Vector2(difference.x / 8.0, difference.y / 4.0).length() > 2.6: continue
			elif absf(difference.y) > 1.2 or Vector2(difference.x, difference.z).length() > 2.3:
				continue
			if d >= distance or not Props.reachable(exploration, node, point): continue
			distance = d
			best = {"uid": uid, "distance": d, "point": point}
	return best

func result(uid: String, message: String, ok: bool = true) -> Dictionary:
	notice = message
	notice_uid = uid
	notice_seconds = 3.0
	refresh_views()
	return {"ok": ok, "reason": message, "site": uid}

func commit(uid: String, kind: String, changes: Dictionary, credits: int, ticket: String = "") -> Dictionary:
	if ticket.is_empty():
		sequence += 1
		ticket = "garden/%d" % sequence
	var update: Dictionary = Plan.exchange(account, ticket, changes, credits, {"site": uid, "kind": kind})
	if update["ok"]: account = update["account"]
	return update

func interact(uid: String) -> Dictionary:
	var candidate: Dictionary = nearby()
	if candidate.get("uid", "") != uid:
		return result(uid, "Move to the marked garden site first.", false)
	if paused: return result(uid, "Garden preview paused.", false)
	var site: Dictionary = sites[uid]
	if not site["reason"].is_empty(): return result(uid, site["reason"], false)
	var role: String = site["profile"]["role"]
	if not Plan.growing_site(role): return supply(uid, site)
	var crop: Dictionary = crops.get(uid, {})
	var kind: String = site["config"]["crop"]
	if not crop.is_empty() and is_ripe(crop): return harvest(uid, crop["token"])
	if not Plan.in_season(site, season()): return result(uid, status(uid), false)
	if crop.is_empty():
		var update: Dictionary = commit(uid, "plant", {"seed/" + kind: -1, "soil": -1}, 0)
		if not update["ok"]: return result(uid, "Planting needs a seed and potting soil.", false)
		crops[uid] = {"kind": kind, "token": update["receipt"]["id"], "growth": 0, "moisture": 0,
			"composted": false, "site_identity": site["identity"]}
		return result(uid, "Planted %s. Water it to start growth." % Plan.crops()[kind]["name"].to_lower())
	if crop["moisture"] <= 2:
		var update: Dictionary = commit(uid, "water", {"water": -1}, 0)
		if not update["ok"]: return result(uid, "Watering can empty. Fill it at a garden water station.", false)
		crop["moisture"] = mini(Plan.MAX_MOISTURE, crop["moisture"] + Plan.WATER_DOSE)
		return result(uid, "Watered. Growth continues while the soil is moist.")
	if not crop["composted"] and account["stock"]["compost"] > 0:
		var update: Dictionary = commit(uid, "compost", {"compost": -1}, 0)
		if not update["ok"]: return result(uid, update["reason"], false)
		crop["composted"] = true
		return result(uid, "Added compost. This crop needs two fewer wet seconds.")
	return result(uid, status(uid), false)

func harvest(uid: String, token: String) -> Dictionary:
	var ticket: String = token + "/harvest"
	var prior: Dictionary = account["receipts"].get(ticket, {})
	if not prior.is_empty() and prior["site"] == uid: return prior.duplicate(true)
	var crop: Dictionary = crops.get(uid, {})
	if crop.get("token", "") != token or crop.is_empty() or not is_ripe(crop) or paused or nearby().get("uid", "") != uid:
		return Plan.failure("This crop cannot be harvested here.")
	var kind: String = crop["kind"]
	var info: Dictionary = Plan.crops()[kind]
	var update: Dictionary = commit(uid, "harvest", {"produce/" + kind: int(info["yield"])}, int(info["harvest_credit"]), ticket)
	if not update["ok"]: return result(uid, update["reason"], false)
	crops.erase(uid)
	var receipt: Dictionary = update["receipt"]
	result(uid, "Harvested %d %s%s." % [info["yield"], info["name"].to_lower(),
		" · +%d preview credits" % receipt["credits"] if receipt["credits"] > 0 else ""])
	harvested.emit(receipt.duplicate(true))
	return receipt

func supply(uid: String, site: Dictionary) -> Dictionary:
	var role: String = site["profile"]["role"]
	var kind: String = site["config"]["crop"]
	var changes: Dictionary = {}
	var charge: int = 0
	match role:
		"seeds":
			changes["seed/" + kind] = 1
			charge = int(Plan.crops()[kind]["seed_price"])
		"water", "soil", "compost":
			var missing: int = Plan.LIMITS[role] - account["stock"][role]
			if missing == 0: return result(uid, "The garden kit already has a full supply.", false)
			changes[role] = mini(missing, 1 if role == "compost" else 4)
		"share":
			for key in account["stock"]:
				if key.begins_with("produce/") and account["stock"][key] > 0: changes[key] = -int(account["stock"][key])
			if changes.is_empty(): return result(uid, "There is no harvest to share yet.", false)
	var update: Dictionary = commit(uid, role, changes, -charge)
	if not update["ok"]: return result(uid, update["reason"], false)
	return result(uid, "%s · done%s." % [supply_action(site), " · %d preview credits" % charge if budget and charge > 0 else ""])

func showing() -> bool:
	return not interior_view and not exploration.interior and exploration.editor_scope.is_empty() and not exploration.photo.active \
		and (show_status or exploration.enabled)

func marker(uid: String) -> Node:
	if markers.has(uid): return markers[uid]
	var label: Node
	if exploration.dimension == "2d":
		label = Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.z_index = 24
		label.add_theme_color_override("font_outline_color", Color("#16232b"))
		label.add_theme_constant_override("outline_size", 5)
	else:
		label = Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.font_size = 32
		label.outline_size = 9
		label.pixel_size = .023
	add_child(label)
	markers[uid] = label
	return label

func canvas_zoom() -> Vector2:
	var camera: Camera2D = get_viewport().get_camera_2d() if exploration.dimension == "2d" else null
	return camera.zoom if camera else Vector2.ONE

func refresh_views() -> void:
	var shown: Dictionary = {}
	var mature: Dictionary = {}
	views_visible = showing()
	if views_visible:
		displayed_season = season()
		displayed_zoom = canvas_zoom()
		for uid in sites:
			var site: Dictionary = sites[uid]
			var node: Node = exploration.instances.get(uid)
			if not is_instance_valid(node) or not node.is_visible_in_tree() or not Plan.growing_site(site["profile"]["role"]):
				continue
			var label: Node = marker(uid)
			label.text = "Bed blocked" if not site["reason"].is_empty() else status(uid).replace("ready to harvest", "ripe")
			var above: float = float(site["profile"].get("height", 1.4)) * float(site["item"]["scale"])
			if exploration.dimension == "2d":
				label.reset_size()
				label.scale = Vector2.ONE / displayed_zoom
				label.global_position = node.global_position + Vector2(-label.get_minimum_size().x * label.scale.x * .5, -above * 16 - 20)
			else: label.global_position = node.global_position + Vector3.UP * (above + .55)
			shown[uid] = true
			var crop: Dictionary = crops.get(uid, {})
			if site["profile"].get("crop_art", false) and not crop.is_empty() and is_ripe(crop):
				var asset: String = Plan.crops()[crop["kind"]]["art"]
				if not exploration.library.assets.has(asset) or exploration.library.assets[asset].get("unavailable", false): continue
				if not artwork.has(uid):
					var model: Node = Factory.make(exploration.library, asset, exploration.dimension, false)
					add_child(model)
					artwork[uid] = model
					if exploration.dimension == "2d":
						model.scale = Vector2.ONE * .55
						model.z_index = 1
					else: model.scale = Vector3.ONE * .55
				var model: Node = artwork[uid]
				var center: Variant = world_point(node, site["rect"].get_center(), site["item"])
				model.global_position = center + (Vector2(-1,-6) if exploration.dimension == "2d" else Vector3.UP * .48)
				mature[uid] = true
	for uid in markers.keys():
		if not shown.has(uid):
			markers[uid].free()
			markers.erase(uid)
	for uid in artwork.keys():
		if not mature.has(uid):
			artwork[uid].free()
			artwork.erase(uid)

func kit_status() -> String:
	if account.is_empty(): return ""
	var stock: Dictionary = account["stock"]
	var summary: String = "Seeds %d · water %d · soil %d · compost %d\nHarvest %d/%d" % [
		Plan.count(stock, "seed/"), stock["water"], stock["soil"], stock["compost"], Plan.count(stock, "produce/"), Plan.MAX_PRODUCE]
	if budget: summary += " · %d preview credits" % account["cash"]
	return summary
