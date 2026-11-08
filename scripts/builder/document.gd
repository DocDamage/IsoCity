extends RefCounted

var data: Dictionary = {"title": "Untitled", "mode": "2d", "objects": [], "tiles": [], "night": false}
var undo_history: Array[Dictionary] = []
var redo_history: Array[Dictionary] = []

const HISTORY_LIMIT: int = 300
# Only the in-progress gesture keeps a baseline. Finished history contains changes.
var pending_before: Dictionary = {}
var content_library: RefCounted
var economy_library: RefCounted
var economy_accepted: Dictionary = {}
var economy_complimentary: Dictionary = {}
var economy_error: String = ""
var pending_redo: Array[Dictionary] = []

func checkpoint() -> void:
	finish_checkpoint()
	pending_before = data.duplicate(true)
	pending_redo.assign(redo_history)
	economy_accepted = {}; economy_complimentary = {}; economy_error = ""
	undo_history.append({"pending": true})
	if undo_history.size() > HISTORY_LIMIT: undo_history.pop_front()
	redo_history.clear()

func finish_checkpoint(discard_empty: bool=false) -> void:
	if undo_history.is_empty() or not undo_history.back().has("pending"):
		pending_before = {}
		economy_accepted = {}; economy_complimentary = {}
		return
	if economy_library: reconcile_economy(economy_library)
	elif content_library: reconcile_content(content_library)
	var change: Dictionary=preload("res://scripts/builder/document_delta.gd").between(pending_before, data)
	if (discard_empty or (economy_library and preload("res://scripts/builder/economy_plan.gd").settings(pending_before)["enabled"]) or preload("res://scripts/builder/asset_palette_policy.gd").restricted(content_library if content_library else economy_library)) and change["fields"].is_empty() and change["collections"].is_empty():
		undo_history.pop_back(); redo_history.assign(pending_redo)
	else: undo_history[-1]=change
	pending_before = {}
	pending_redo.clear()
	economy_accepted = {}; economy_complimentary = {}

func reconcile_content(library: RefCounted,remember: bool=true) -> bool:
	if pending_before.is_empty():return true
	var content: Dictionary=preload("res://scripts/builder/asset_palette_policy.gd").check(pending_before,data,library)
	if not content["ok"]:
		economy_error=content["reason"];data=(pending_before if economy_accepted.is_empty() else economy_accepted).duplicate(true);return false
	if remember and preload("res://scripts/builder/asset_palette_policy.gd").restricted(library):economy_accepted=data.duplicate(true)
	economy_error="";return true

func reconcile_economy(library: RefCounted) -> bool:
	economy_library=library
	if pending_before.is_empty():return true
	if not reconcile_content(library,false):return false
	if not preload("res://scripts/builder/economy_plan.gd").settings(pending_before)["enabled"]:
		if preload("res://scripts/builder/asset_palette_policy.gd").restricted(library):economy_accepted=data.duplicate(true)
		economy_error="";return true
	if not data.has("economy"): data["economy"]=pending_before["economy"].duplicate(true)
	var quote: Dictionary=preload("res://scripts/builder/economy_plan.gd").quote(pending_before,data,library,economy_complimentary)
	if not quote["ok"]:
		economy_error=quote["reason"]
		data=(pending_before if economy_accepted.is_empty() else economy_accepted).duplicate(true)
		return false
	data["economy_account"]=quote["account"]
	economy_accepted=data.duplicate(true); economy_error=""
	return true

# Automatically supplied starter rooms are free. Later furnishing edits and
# duplicated buildings pay normally, including copied room contents.
func complimentary_room(uid: String,library: RefCounted) -> void:
	economy_complimentary.merge(preload("res://scripts/builder/economy_plan.gd").starter_holdings(data, uid, library), true)

func undo() -> bool:
	finish_checkpoint()
	if undo_history.is_empty(): return false
	var change: Dictionary = undo_history.pop_back()
	preload("res://scripts/builder/document_delta.gd").apply(data, change, false)
	redo_history.append(change)
	return true

func redo() -> bool:
	finish_checkpoint()
	if redo_history.is_empty(): return false
	var change: Dictionary = redo_history.pop_back()
	preload("res://scripts/builder/document_delta.gd").apply(data, change, true)
	undo_history.append(change)
	return true

func record_completed_change(before: Dictionary,financial_transaction: bool=false) -> bool:
	finish_checkpoint()
	var policy: Dictionary=preload("res://scripts/builder/asset_palette_policy.gd").check(before,data,content_library if content_library else economy_library)
	if not policy["ok"]:economy_error=policy["reason"];data=before.duplicate(true);return false
	if economy_library and not financial_transaction:
		var quote: Dictionary=preload("res://scripts/builder/economy_plan.gd").quote(before,data,economy_library)
		if not quote["ok"]: economy_error=quote["reason"]; data=before.duplicate(true); return false
		if quote.get("enabled",false): data["economy_account"]=quote["account"]
	var change: Dictionary=preload("res://scripts/builder/document_delta.gd").between(before,data)
	if change["fields"].is_empty() and change["collections"].is_empty(): return false
	undo_history.append(change)
	if undo_history.size()>HISTORY_LIMIT: undo_history.pop_front()
	redo_history.clear()
	return true

func object(uid: String) -> Dictionary:
	for item in data["objects"]:
		if item["uid"] == uid:
			return item
	return {}

func add(asset: String, position: Array, direction: String, scale_value: float = 1.0) -> Dictionary:
	var item: Dictionary = placement_item(new_uid(), asset, position, direction, scale_value)
	data["objects"].append(item)
	return item

static func new_uid() -> String:
	return str(Time.get_ticks_usec()) + "_" + str(randi())

static func placement_item(uid: String, asset: String, position: Array, direction: String, scale_value: float) -> Dictionary:
	var item: Dictionary = {"uid": uid, "asset": asset,
		"position": [float(position[0]), float(position[1]), float(position[2])], "direction": direction, "scale": scale_value}
	preload("res://scripts/builder/catalog_defaults.gd").stamp(item)
	return item

static func valid(value: Variant, mode: String, library: RefCounted, depth: int = 0) -> bool:
	if depth > 4: return false
	if not value is Dictionary or value.get("mode") != mode or not value.get("title") is String:
		return false
	if not value.get("objects") is Array or not value.get("tiles") is Array or not value.get("night", false) is bool:
		return false
	if value.has("terrain") and not preload("res://scripts/builder/terrain_plan.gd").valid_settings(value["terrain"]): return false
	if value.has("modular_rooms") and not preload("res://scripts/builder/modular_building_plan.gd").valid(value["modular_rooms"],mode): return false
	if value.has("protected_areas") and (not preload("res://scripts/builder/cooperative_plan.gd").valid_areas(value["protected_areas"]) or (depth>0 and not value["protected_areas"].is_empty())): return false
	if value.has("blueprints") and not preload("res://scripts/builder/blueprint_plan.gd").valid(value["blueprints"],mode,library): return false
	if value.has("photo") and not preload("res://scripts/builder/photo_plan.gd").valid(value["photo"],mode): return false
	if value.has("terrain_vertices") and not preload("res://scripts/builder/terrain_plan.gd").valid_records(value["terrain_vertices"],value): return false
	if value.has("water_cells") and not preload("res://scripts/builder/terrain_plan.gd").valid_records(value["water_cells"],value,true): return false
	if value.has("citizens") and not preload("res://scripts/builder/citizen_plan.gd").valid_settings(value["citizens"]): return false
	if value.get("citizens",{}).get("appearance","")!="":
		var appearance: String=value["citizens"]["appearance"]
		if mode!="2d" or not library.assets.has(appearance) or library.assets[appearance]["data"].get("kind","")!="char": return false
	if value.has("traffic") and not preload("res://scripts/builder/traffic_plan.gd").valid_settings(value["traffic"]): return false
	if value.has("fleet") and not preload("res://scripts/builder/fleet_plan.gd").valid(value["fleet"]): return false
	if value.has("services") and not preload("res://scripts/builder/service_plan.gd").valid_settings(value["services"]): return false
	if value.has("economy") and not preload("res://scripts/builder/economy_plan.gd").valid_settings(value["economy"]): return false
	if value.has("economy_account") and not preload("res://scripts/builder/economy_plan.gd").valid_account(value["economy_account"]): return false
	if value.has("scenario"):
		if not preload("res://scripts/builder/scenario_plan.gd").valid(value["scenario"]): return false
		var kind: String = value["scenario"]["id"]
		if (kind == "construction" or preload("res://scripts/builder/emergency_training_plan.gd").recognized(kind)) and (depth > 0 or value.get("interior_room", false)): return false
	if value.has("zoning") and not preload("res://scripts/builder/zone_plan.gd").valid_settings(value["zoning"]): return false
	if value.has("zones") and not preload("res://scripts/builder/zone_plan.gd").valid_lots(value["zones"],mode,library): return false
	if value.has("neighborhood_generator") and not preload("res://scripts/builder/neighborhood_plan.gd").valid_settings(value["neighborhood_generator"]): return false
	if value.has("ambience") and not preload("res://scripts/builder/ambience_plan.gd").valid_settings(value["ambience"]): return false
	if value.has("weather") and not preload("res://scripts/builder/weather_plan.gd").valid_settings(value["weather"]): return false
	if value.has("garden") and not preload("res://scripts/builder/garden_plan.gd").valid_settings(value["garden"]): return false
	if value.has("cooking") and not preload("res://scripts/builder/cooking_plan.gd").valid_settings(value["cooking"]): return false
	if value.has("laundry") and not preload("res://scripts/builder/laundry_plan.gd").valid_settings(value["laundry"]): return false
	if value.has("fitness") and not preload("res://scripts/builder/fitness_plan.gd").valid_settings(value["fitness"]): return false
	if value.has("arcade") and not preload("res://scripts/builder/arcade_plan.gd").valid_settings(value["arcade"]): return false
	if value.has("camping") and not preload("res://scripts/builder/camping_plan.gd").valid_settings(value["camping"]): return false
	if value.has("pet") and not preload("res://scripts/builder/pet_plan.gd").valid(value["pet"]): return false
	if value.has("cycling") and not preload("res://scripts/builder/cycling_plan.gd").valid(value["cycling"]): return false
	if value.has("harbor") and not preload("res://scripts/builder/harbor_plan.gd").valid(value["harbor"]): return false
	if value.has("space_outpost") and (value.get("interior_room", false) or not preload("res://scripts/builder/space_outpost_plan.gd").valid(value["space_outpost"])): return false
	if value.has("village") and not preload("res://scripts/builder/village_plan.gd").valid_settings(value["village"]): return false
	if value.has("transit") and not preload("res://scripts/builder/transit_plan.gd").valid_settings(value["transit"]): return false
	if value.has("transit_lines") and not preload("res://scripts/builder/transit_plan.gd").valid_lines(value["transit_lines"]): return false
	var seen: Dictionary = {}
	var school_count: int=0
	var vehicle_bay_count: int=0
	var delivery_count: int=0
	var market_count: int=0
	var markets=preload("res://scripts/builder/market_plan.gd")
	var deliveries=preload("res://scripts/builder/delivery_plan.gd")
	if not preload("res://scripts/builder/floor_plan.gd").valid(value): return false
	for floor in value.get("floors",[]):
		if not valid(floor["room"],mode,library,depth+1): return false
	for item in value["objects"]:
		if not item is Dictionary or not item.get("uid") is String or seen.has(item["uid"]):
			return false
		if item.has("audio") and not preload("res://scripts/builder/ambience_plan.gd").valid_source(item["audio"]): return false
		if item.has("prop") and not preload("res://scripts/builder/prop_plan.gd").valid(item["prop"]): return false
		if item.has("garden") and not preload("res://scripts/builder/garden_plan.gd").valid_site(item["garden"]): return false
		if item.has("cooking") and not preload("res://scripts/builder/cooking_plan.gd").valid_station(item["cooking"]): return false
		if item.has("laundry") and not preload("res://scripts/builder/laundry_plan.gd").valid_station(item["laundry"]): return false
		if item.has("fitness") and not preload("res://scripts/builder/fitness_plan.gd").valid_station(item["fitness"]): return false
		if item.has("arcade") and not preload("res://scripts/builder/arcade_plan.gd").valid_cabinet(item["arcade"]): return false
		if item.has("camping") and not preload("res://scripts/builder/camping_plan.gd").valid_site(item["camping"]): return false
		if item.has("cycling") and not preload("res://scripts/builder/cycling_plan.gd").valid_vehicle(item["cycling"]): return false
		if item.has("village") and not preload("res://scripts/builder/village_plan.gd").valid_site(item["village"]): return false
		if item.has("driving") and not preload("res://scripts/builder/driving_plan.gd").valid(item["driving"]): return false
		if item.has("market"):
			if depth>0 or value.get("interior_room",false) or not markets.valid(item): return false
			if item["market"].get("enabled",false): market_count+=1
			if market_count>markets.MAX_MARKETS: return false
		for field in deliveries.FIELDS:
			if item.has(field) and (depth>0 or value.get("interior_room",false) or not deliveries.valid(item,field)): return false
		if item.get("delivery_site",{}).get("enabled",false):
			delivery_count+=1
			if delivery_count>deliveries.MAX_SITES: return false
		if item.has("vehicle_care") or item.has("vehicle_bay"):
			if depth>0 or value.get("interior_room",false): return false
			var care=preload("res://scripts/builder/vehicle_service_plan.gd")
			if item.has("vehicle_care") and not care.valid_vehicle(item): return false
			if item.has("vehicle_bay"):
				if not care.valid_bay(item): return false
				if item["vehicle_bay"].get("enabled",false): vehicle_bay_count+=1
				if vehicle_bay_count>care.MAX_BAYS: return false
		seen[item["uid"]] = true
		if item.has("zone_uid") and (not item["zone_uid"] is String or item["zone_uid"].length()>128): return false
		if item.has("traffic_parking") and not item["traffic_parking"] is bool: return false
		if item.has("traffic_control") and not preload("res://scripts/builder/traffic_control_plan.gd").valid(item["traffic_control"]): return false
		if item.has("transit_stop") and not item["transit_stop"] is bool: return false
		if item.has("school"):
			var schools=preload("res://scripts/builder/school_plan.gd")
			if depth>0 or not schools.eligible(item) or not schools.valid(item["school"]): return false
			if item["school"].get("enabled",false): school_count+=1
			if school_count>schools.MAX_SCHOOLS: return false
		if item.has("business") and not preload("res://scripts/builder/business_plan.gd").valid(item["business"]): return false
		if item.has("catalog_behavior_revision") and not preload("res://scripts/builder/catalog_defaults.gd").valid_revision(item["catalog_behavior_revision"]): return false
		if item.has("city_service") and not preload("res://scripts/builder/service_plan.gd").valid_profile(item["city_service"]): return false
		if item.has("citizen_role") and (not item["citizen_role"] is String or not item["citizen_role"] in ["home","work","shop","park","none"]): return false
		if item.has("neighborhood_palette_selection") and not preload("res://scripts/builder/neighborhood_palettes.gd").valid_selection(item["neighborhood_palette_selection"]):return false
		if not library.assets.has(item.get("asset")):
			return false
		if not numbers(item.get("position"), 3) or not item.get("direction") is String:
			return false
		if not library.valid_direction(item["asset"], item["direction"]):
			return false
		if not numbers([item.get("scale")], 1) or float(item["scale"]) < 0.1 or float(item["scale"]) > 8.0:
			return false
	for tile in value["tiles"]:
		if not tile is Dictionary or not numbers(tile.get("cell"), 2) or not tile.get("asset") is String:
			return false
		if not library.assets.has(tile["asset"]) or library.assets[tile["asset"]]["mode"] != "2d":
			return false
		if not library.assets[tile["asset"]]["category"] in ["Floors", "City Ground"]:
			return false
		if not preload("res://scripts/builder/terrain_family_plan.gd").valid_tile(tile,mode): return false
		if tile.has("colors") and not preload("res://scripts/builder/part_colors.gd").valid(tile["colors"]): return false
		if not tile.get("direction", "SE") is String or not library.valid_direction(tile["asset"], tile.get("direction", "SE")):
			return false
		if float(tile["cell"][0]) != floor(float(tile["cell"][0])) or float(tile["cell"][1]) != floor(float(tile["cell"][1])):
			return false
	if value.has("spawn") and not numbers(value["spawn"], 3):
		return false
	if value.has("exit") and not numbers(value["exit"], 3): return false
	if value.has("interior_room") and not value["interior_room"] is bool: return false
	if not value.get("roads", []) is Array or value.get("roads", []).size() > 4096: return false
	var road_cells: Dictionary = {}
	for road in value.get("roads", []):
		if not road is Dictionary or not numbers(road.get("cell"), 2) or not road.get("crossing", false) is bool: return false
		if not preload("res://scripts/builder/road_settings.gd").valid(road): return false
		for coordinate in road["cell"]:
			if absf(coordinate) > 100000 or float(coordinate) != floorf(coordinate): return false
		if road_cells.has(str(road["cell"])): return false
		road_cells[str(road["cell"])] = true
	if not value.get("layers", {}) is Dictionary: return false
	for name in value.get("layers", {}):
		if not name in preload("res://scripts/builder/layers.gd").NAMES: return false
		var layer: Variant = value["layers"][name]
		if not layer is Dictionary or not layer.get("visible", true) is bool or not layer.get("locked", false) is bool: return false
	if not value.get("group_names", {}) is Dictionary: return false
	for group in value.get("group_names", {}):
		if not group is String or not value["group_names"][group] is String: return false
	for item in value["objects"]:
		if not item.get("name", "") is String or not item.get("visible", true) is bool or not item.get("locked", false) is bool: return false
		if item.has("angle") and (not numbers([item["angle"]], 1) or absf(item["angle"]) > 360000): return false
		if item.has("tilt") and (not numbers(item["tilt"], 2) or absf(item["tilt"][0]) > 360000 or absf(item["tilt"][1]) > 360000): return false
		if item.has("colors") and not preload("res://scripts/builder/part_colors.gd").valid(item["colors"]): return false
		if item.has("group") and not item["group"] is String: return false
		if item.has("open") and not item["open"] is bool: return false
		if item.has("interior") and not valid(item["interior"],mode,library,depth+1): return false
		if item.has("entrance_anchor") and not preload("res://scripts/builder/entrance_anchors.gd").valid(item["entrance_anchor"], library.assets[item["asset"]]["mode"] == "2d"): return false
		if item.has("layer") and not item["layer"] in preload("res://scripts/builder/layers.gd").NAMES: return false
	if value.has("connections"):
		var links: Variant = value["connections"]
		var connector = preload("res://scripts/builder/connector_plan.gd")
		if not links is Array or links.size() > connector.LIMIT or connector.retained(value, links) != links:
			return false
	return preload("res://scripts/builder/utility_plan.gd").valid(value,library,depth)

static func normalize(value: Dictionary) -> Dictionary:
	for node in value.get("utility_nodes",[]):
		for field in ["quantity","priority"]:
			if node.has(field): node[field]=int(node[field])
	for floor in value.get("floors",[]): floor["room"]=normalize(floor["room"])
	if value.has("economy_account"): value["economy_account"]=preload("res://scripts/builder/economy_plan.gd").normalized_account(value["economy_account"])
	for road in value.get("roads", []):
		road["cell"] = [int(road["cell"][0]), int(road["cell"][1])]
		if road.has("width"): road["width"] = int(road["width"])
	for tile in value["tiles"]:
		tile["cell"] = [int(tile["cell"][0]), int(tile["cell"][1])]
	for item in value["objects"]:
		item["position"] = [float(item["position"][0]), float(item["position"][1]), float(item["position"][2])]
		item["scale"] = float(item["scale"])
		if item.has("interior"): item["interior"] = normalize(item["interior"])
	return value

static func numbers(value: Variant, length: int) -> bool:
	if not value is Array or value.size() != length:
		return false
	for number in value:
		if not (number is int or number is float) or not is_finite(float(number)):
			return false
	return true
