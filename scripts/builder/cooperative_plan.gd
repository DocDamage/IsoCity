extends RefCounted
const Fit=preload("res://scripts/builder/grid_fit.gd")
const Traffic=preload("res://scripts/builder/traffic_plan.gd")
const VehicleCare=preload("res://scripts/builder/vehicle_service_plan.gd")
const Deliveries=preload("res://scripts/builder/delivery_plan.gd")
const Markets=preload("res://scripts/builder/market_plan.gd")
const Zone=preload("res://scripts/builder/zone_plan.gd")
const Blueprint=preload("res://scripts/builder/blueprint_plan.gd")
const MAX_AREAS=128
static func valid_areas(value: Variant) -> bool:
	if not value is Array or value.size()>MAX_AREAS: return false
	var ids: Dictionary={}
	for area in value:
		if not area is Dictionary or not area.get("uid") is String or area["uid"].is_empty() or area["uid"].length()>128 or ids.has(area["uid"]): return false
		ids[area["uid"]]=true
		if not area.get("name") is String or area["name"].length()>128 or not area.get("owner") is String or area["owner"].length()>128: return false
		if not area.get("rect") is Array or area["rect"].size()!=4: return false
		for number in area["rect"]:
			if not (number is int or number is float) or not is_finite(float(number)) or absf(number)>100000: return false
		if area["rect"][2]<1 or area["rect"][3]<1 or area["rect"][2]>4096 or area["rect"][3]>4096: return false
	return true
static func rect(area: Dictionary) -> Rect2: return Rect2(area["rect"][0],area["rect"][1],area["rect"][2],area["rect"][3])
static func index(values: Array,key: String="uid") -> Dictionary:
	var result: Dictionary={}
	for value in values: result[str(value[key])]=value
	return result
static func changed_records(before: Dictionary,after: Dictionary,key: String,identity: String="uid") -> Array:
	var old: Dictionary=index(before.get(key,[]),identity); var next: Dictionary=index(after.get(key,[]),identity); var keys: Dictionary=old.duplicate(); keys.merge(next); var result: Array=[]
	for id in keys:
		if old.get(id)==next.get(id): continue
		if old.has(id): result.append(old[id])
		if next.has(id): result.append(next[id])
	return result
static func object_rect(item: Dictionary,mode: String,library: RefCounted) -> Rect2:
	var result: Rect2=Zone.footprint(item,mode,library)
	return result.grow(.1) if result.size.length()>.001 else Rect2(Traffic.metric(item["position"],mode)-Vector2.ONE*.3,Vector2.ONE*.6)
static func touched(before: Dictionary,after: Dictionary,library: RefCounted) -> Array[Rect2]:
	var result: Array[Rect2]=[]; var mode: String=before["mode"]
	var previous_objects: Dictionary=index(before["objects"])
	var next_objects: Dictionary=index(after["objects"])
	var changed_objects: Array=changed_records(before,after,"objects")
	for item in changed_objects:
		result.append(object_rect(item,mode,library))
		if item.has("market"):
			var area: Rect2=Markets.protected_area(item,mode,library)
			if area.has_area(): result.append(area)
		if item.has("vehicle_bay"):
			var uid: String=item["uid"]
			var previous: Dictionary=previous_objects.get(uid,{})
			var next: Dictionary=next_objects.get(uid,{})
			var area: Rect2=VehicleCare.protected_area(item,mode,library)
			if area.has_area() and (previous.get("vehicle_bay")!=next.get("vehicle_bay") or VehicleCare.protected_area(previous,mode,library)!=VehicleCare.protected_area(next,mode,library)):
				result.append(area)
		if item.has("delivery_site") or item.has("delivery_contract"):
			var uid: String=item["uid"]
			var previous: Dictionary=previous_objects.get(uid,{})
			var next: Dictionary=next_objects.get(uid,{})
			var old_contract: Dictionary=previous.get("delivery_contract",{})
			var new_contract: Dictionary=next.get("delivery_contract",{})
			var previous_pad: Rect2=Deliveries.protected_area(previous,mode,library)
			var next_pad: Rect2=Deliveries.protected_area(next,mode,library)
			if old_contract!=new_contract or previous_pad!=next_pad or previous.get("delivery_site")!=next.get("delivery_site"):
				var pad: Rect2=Deliveries.protected_area(item,mode,library)
				if pad.has_area(): result.append(pad)
			if old_contract!=new_contract:
				for record in [previous_objects.get(old_contract.get("destination",""),{}),next_objects.get(new_contract.get("destination",""),{})]:
					if record.is_empty(): continue
					result.append(object_rect(record,mode,library))
					var pad: Rect2=Deliveries.protected_area(record,mode,library)
					if pad.has_area(): result.append(pad)
		var control: Dictionary=item.get("traffic_control",{})
		if Traffic.Signals.valid(control):
			var center: Vector2=Traffic.center(Vector2i(control["cell"][0],control["cell"][1]),mode)
			result.append(Rect2(center-Vector2.ONE*4,Vector2.ONE*8))
			var approach: Vector2=Vector2(Traffic.Roads.STEPS[int(control["side"])])*8
			result.append(Rect2(center+approach-Vector2.ONE*4,Vector2.ONE*8))
			if control["kind"]=="one_way":
				result.append(Rect2(center-approach-Vector2.ONE*4,Vector2.ONE*8))
	var roads=preload("res://scripts/builder/roads.gd"); var network: Dictionary=roads.lookup(before); network.merge(roads.lookup(after)); var road_cells: Dictionary={}
	for entry in changed_records(before,after,"roads","cell"):
		var cell:=Vector2i(entry["cell"][0],entry["cell"][1]); road_cells[roads.key(cell)]=cell
		for step in roads.STEPS:
			if network.has(roads.key(cell+step)): road_cells[roads.key(cell+step)]=cell+step
	for cell in road_cells.values(): result.append(Rect2(Vector2(cell)*8-Vector2.ONE*5,Vector2.ONE*10))
	for key in ["tiles","terrain_vertices","water_cells"]:
		for entry in changed_records(before,after,key,"cell"):
			var center:=Vector2(entry["cell"][0],entry["cell"][1])*2
			if key=="terrain_vertices": result.append(Rect2(center-Vector2.ONE*2,Vector2.ONE*4))
			else: result.append(Rect2(center,Vector2.ONE*2).grow(.01))
	if mode=="2d": result.append_array(connected_ground_touched(before,after,roads))
	var old_floors: Dictionary=index(before.get("floors",[])); var next_floors: Dictionary=index(after.get("floors",[]))
	for id in old_floors:
		if next_floors.has(id): result.append_array(touched(old_floors[id]["room"],next_floors[id]["room"],library))
	for lot in changed_records(before,after,"zones"): result.append(Zone.rectangle(lot))
	for proposal in changed_records(before,after,"blueprints"): result.append_array(Blueprint.rectangles(proposal,mode,library))
	for room in changed_records(before,after,"modular_rooms"):
		for item in before["objects"] + after["objects"]:
			if item.get("group") == room["uid"]: result.append(object_rect(item,mode,library))
	for node in changed_records(before,after,"utility_nodes"):
		for items in [previous_objects,next_objects]:
			var uid: String=node["object_uid"]
			if items.has(uid): result.append(object_rect(items[uid],mode,library))
	var changed_links: Array = changed_records(before, after, "connections")+changed_records(before,after,"utility_edges")
	if not changed_links.is_empty():
		for link in changed_links:
			for side in ["from", "to"]:
				var uid: String = link[side]["object_uid"]
				for items in [previous_objects, next_objects]:
					if items.has(uid): result.append(object_rect(items[uid], mode, library))
	for item in changed_objects:
		var uid: String=item["uid"]
		var first: Dictionary=previous_objects.get(uid,{}).get("school",{})
		var second: Dictionary=next_objects.get(uid,{}).get("school",{})
		if first==second: continue
		for scope in [previous_objects,next_objects]:
			for config in [first,second]:
				for key in ["playground","home_stop","school_stop"]:
					var target: String=config.get(key,"")
					if scope.has(target): result.append(object_rect(scope[target],mode,library))
	for line in changed_records(before,after,"transit_lines"):
		for data in [before,after]:
			for item in data["objects"]:
				if item["uid"] in line["stops"]: result.append(object_rect(item,mode,library))
	return result
static func connected_ground_touched(before: Dictionary,after: Dictionary,roads: Script) -> Array[Rect2]:
	var result: Array[Rect2]=[]
	var families=preload("res://scripts/builder/terrain_family_plan.gd")
	var has_family: bool=before["tiles"].any(func(tile: Dictionary)->bool:return tile.has("family")) or after["tiles"].any(func(tile: Dictionary)->bool:return tile.has("family"))
	var sculpted: bool=before.get("terrain",{}).get("connected_shores",false) or after.get("terrain",{}).get("connected_shores",false)
	if not has_family and not sculpted: return result
	var old_levels: Dictionary=families.water_levels(before.get("water_cells",[])) if before.get("terrain",{}).get("enabled",false) else {}
	var next_levels: Dictionary=families.water_levels(after.get("water_cells",[])) if after.get("terrain",{}).get("enabled",false) else {}
	var water_edits: Dictionary=families.affected(old_levels,next_levels)
	if has_family:
		var old: Dictionary=families.by_cell(roads.tiles(before))
		var next: Dictionary=families.by_cell(roads.tiles(after))
		var affected: Dictionary=families.affected(old,next)
		affected.merge(water_edits,true)
		for cell in affected:
			var a: Dictionary=families.ground_variant(old.get(cell,{}),cell,old,old_levels)
			var b: Dictionary=families.ground_variant(next.get(cell,{}),cell,next,next_levels)
			if a!=b: result.append(Rect2(Vector2(cell)*2,Vector2.ONE*2).grow(.01))
	if sculpted:
		for cell in water_edits:
			if not old_levels.has(cell) or not next_levels.has(cell): continue
			if families.shoreline(cell,old_levels)!=families.shoreline(cell,next_levels):
				result.append(Rect2(Vector2(cell)*2,Vector2.ONE*2).grow(.01))
	return result

static func allowed(before: Dictionary,after: Dictionary,actor: String,library: RefCounted) -> String:
	if actor=="host": return ""
	if before.get("project_palette",{})!=after.get("project_palette",{}):return "The host manages shared project recommendations and content restrictions."
	for mode in ["2d","3d"]:
		var old: Dictionary=before[mode]; var next: Dictionary=after[mode]
		if old.get("protected_areas",[])!=next.get("protected_areas",[]): return "Only the host can assign or change protected areas."
		for key in ["economy","scenario"]:
			if old.get(key)!=next.get(key): return "The host manages shared treasury and challenge settings."
		if old.get("garden",{})!=next.get("garden",{}): return "The host manages the shared garden setting."
		if old.get("cooking",{})!=next.get("cooking",{}): return "The host manages the shared cooking setting."
		if old.get("laundry",{})!=next.get("laundry",{}): return "The host manages the shared laundry setting."
		if old.get("fitness",{})!=next.get("fitness",{}): return "The host manages the shared sports setting."
		if old.get("arcade",{})!=next.get("arcade",{}): return "The host manages the shared arcade setting."
		if old.get("camping",{})!=next.get("camping",{}): return "The host manages the shared camping setting."
		if old.get("pet",{})!=next.get("pet",{}): return "The host manages the shared companion setting."
		if old.get("cycling",{})!=next.get("cycling",{}): return "The host manages the shared cycling setting."
		if old.get("harbor", {}) != next.get("harbor", {}): return "The host manages shared harbor settings."
		if old.get("space_outpost", {}) != next.get("space_outpost", {}): return "The host manages shared space outpost settings."
		if old.get("village",{})!=next.get("village",{}): return "The host manages the shared village setting."
		if old.get("utilities",{})!=next.get("utilities",{}): return "The host manages shared utility simulation settings."
		var guarded: Array=old.get("protected_areas",[]).filter(func(area: Dictionary):return area["owner"]!=actor)
		if guarded.is_empty(): continue
		if floor_configuration_changed(old,next): return "Floor configuration affects protected areas; ask the host to change it."
		if old.get("layers",{})!=next.get("layers",{}): return "Layer settings affect protected areas; ask the host to change them."
		if old.get("terrain",{})!=next.get("terrain",{}): return "Terrain settings affect protected areas; ask the host to change them."
		var boxes: Array[Rect2]=touched(old,next,library)
		for area in guarded:
			var bounds: Rect2=rect(area).grow(.001)
			for box in boxes:
				if bounds.intersects(box): return "Protected area · "+area["name"]+". The host can assign editing access."
	return ""
static func floor_configuration_changed(before: Dictionary,after: Dictionary) -> bool:
	for key in ["floor_links","floor_entrances"]:
		if before.get(key,[])!=after.get(key,[]): return true
	var old: Dictionary=index(before.get("floors",[])); var next: Dictionary=index(after.get("floors",[]))
	if old.size()!=next.size(): return true
	for id in old:
		if not next.has(id): return true
		var old_meta: Dictionary=old[id].duplicate(); var next_meta: Dictionary=next[id].duplicate(); old_meta.erase("room"); next_meta.erase("room")
		if old_meta!=next_meta: return true
		for key in ["terrain","layers"]:
			if old[id]["room"].get(key,{})!=next[id]["room"].get(key,{}): return true
		if floor_configuration_changed(old[id]["room"],next[id]["room"]): return true
	return false
static func used_assets(data: Dictionary,result: Dictionary={}) -> Dictionary:
	result=result.duplicate()
	var pet_asset: String=preload("res://scripts/builder/pet_plan.gd").required(data)
	if not pet_asset.is_empty(): result[pet_asset]=true
	var citizens: Variant=data.get("citizens",{})
	if citizens is Dictionary and citizens.get("appearance","") is String and not citizens.get("appearance","").is_empty(): result[citizens["appearance"]]=true
	for item in data.get("objects",[]):
		result[item["asset"]]=true
		if item.has("interior"): result.merge(used_assets(item["interior"]))
	for tile in data.get("tiles",[]): result[tile["asset"]]=true
	for floor in data.get("floors",[]): result.merge(used_assets(floor["room"]))
	for lot in data.get("zones",[]):
		if lot.get("proposal") is Dictionary and not lot["proposal"].is_empty():result[lot["proposal"]["asset"]]=true
	for proposal in data.get("blueprints",[]):
		for item in Blueprint.proposal_objects(proposal):
			result[item["asset"]]=true
			if item.get("interior") is Dictionary:result.merge(used_assets(item["interior"]))
	return result
static func complimentary_rooms(before: Dictionary,after: Dictionary,library: RefCounted) -> Dictionary:
	var result: Dictionary={}; var old: Dictionary=index(before["objects"]); var economy=preload("res://scripts/builder/economy_plan.gd")
	for item in after["objects"]:
		if not old.has(item["uid"]) or old[item["uid"]].has("interior") or not item.has("interior") or old[item["uid"]]["asset"]!=item["asset"]: continue
		if not preload("res://scripts/builder/asset_behavior.gd").for_asset(item["asset"],library).get("building",false): continue
		var starter: Dictionary=preload("res://scripts/builder/interiors.gd").make_for(item,after["mode"],library); var allowances: Dictionary={}
		for unit in economy.inventory(starter,library).values(): allowances[unit["token"]]=int(allowances.get(unit["token"],0))+1
		var actual: Dictionary=economy.inventory(item["interior"],library,["object",item["uid"],"interior"],1,{})
		for key in actual:
			var token: String=actual[key]["token"]
			if allowances.get(token,0)>0: result[key]=token; allowances[token]-=1
	return result

# Include concrete defaults for rooms that have not been created. Customized
# rooms depend only on their saved furnishings, never a newer catalog mapping.
static func required_assets(data: Dictionary,library: RefCounted) -> Dictionary:
	var result: Dictionary=used_assets(data);var future: Dictionary={}
	for asset in preload("res://scripts/builder/construction_plan.gd").required_assets(data): result[asset]=true
	for asset in preload("res://scripts/builder/village_plan.gd").required_delivery_art(data): result[asset]=true
	for asset in preload("res://scripts/builder/garden_plan.gd").required_assets(data): result[asset]=true
	for asset in preload("res://scripts/builder/cooking_plan.gd").required_art(data): result[asset]=true
	for asset in preload("res://scripts/builder/fitness_plan.gd").required_art(data): result[asset]=true
	for asset in preload("res://scripts/builder/space_outpost_plan.gd").required(data): result[asset]=true
	var roles: Array=[]
	if data.get("traffic",{}).get("enabled",false): roles.append("traffic")
	if data.get("transit",{}).get("enabled",false): roles.append("transit")
	if data.get("services",{}).get("enabled",false):
		var services=preload("res://scripts/builder/service_plan.gd")
		for item in data.get("objects",[]):
			var kind: String=services.profile(item)["kind"]
			if kind!="none" and kind not in roles: roles.append(kind)
	result.merge(Traffic.Fleet.required(data,roles))
	var school_bus: String=preload("res://scripts/builder/school_plan.gd").required_bus(data)
	if not school_bus.is_empty(): result[school_bus]=true
	for item in data.get("objects",[]):
		if item.get("interior") is Dictionary:result.merge(required_assets(item["interior"],library))
		else:future[item["asset"]]=true
	for floor in data.get("floors",[]):result.merge(required_assets(floor["room"],library))
	for proposal in data.get("blueprints",[]):
		for item in Blueprint.proposal_objects(proposal):
			if item.get("interior") is Dictionary:result.merge(required_assets(item["interior"],library))
			else:future[item["asset"]]=true
	if Zone.settings(data)["enabled"]:
		for lot in data.get("zones",[]):
			for id in Zone.definitions()[lot["kind"]][data["mode"]]:result[id]=true;future[id]=true
	for id in future:
		for dependency in preload("res://scripts/builder/interior_kits.gd").dependencies_for(id,data["mode"],library):result[dependency]=true
	return result
