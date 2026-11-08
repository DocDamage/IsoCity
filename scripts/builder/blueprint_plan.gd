extends RefCounted
const Roads=preload("res://scripts/builder/roads.gd")
const Settings=preload("res://scripts/builder/road_settings.gd")
const Zone=preload("res://scripts/builder/zone_plan.gd")
const Assembly=preload("res://scripts/builder/functional_assembly_plan.gd")
const Traffic=preload("res://scripts/builder/traffic_plan.gd")
const LIMIT=512

static func valid(entries: Variant,mode: String,library: RefCounted) -> bool:
	if not entries is Array or entries.size()>LIMIT: return false
	var seen: Dictionary={}
	var road_sections: int=0
	for entry in entries:
		if not entry is Dictionary or not entry.get("uid") is String or entry["uid"].is_empty() or entry["uid"].length()>128 or seen.has(entry["uid"]): return false
		seen[entry["uid"]]=true
		if entry.get("kind")=="road":
			if not Assembly.road_valid(entry): return false
			road_sections+=Assembly.road_length(entry)
		elif entry.get("kind")=="assembly":
			if not Assembly.valid(entry,mode,library): return false
			for road in entry["roads"]: road_sections+=Assembly.road_length(road)
		elif entry.get("kind")=="building":
			var item: Variant=entry.get("item")
			if not item is Dictionary or not library.assets.has(item.get("asset","")): return false
			if not preload("res://scripts/builder/asset_behavior.gd").for_asset(item["asset"],library).get("building",false): return false
			if item.has("angle") and (not number(item["angle"]) or absf(item["angle"])>360000): return false
			if item.has("tilt"):
				if not item["tilt"] is Array or item["tilt"].size()!=2: return false
				for value in item["tilt"]:
					if not number(value) or absf(value)>360000: return false
			if not item.get("direction") is String or not library.valid_direction(item["asset"],item["direction"]): return false
			if not item.get("position") is Array or item["position"].size()!=3: return false
			for value in item["position"]:
				if not number(value) or absf(value)>100000: return false
			if not number(item.get("scale")) or item["scale"]<.1 or item["scale"]>8: return false
		else: return false
		if road_sections>4096: return false
	return mode in ["2d","3d"]

static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func construct(data: Dictionary,ids: Array,library: RefCounted) -> Dictionary:
	var result: Dictionary=data.duplicate(true)
	if not valid(result.get("blueprints",[]),data["mode"],library): return {"ok":false,"reason":"Repair invalid proposals before construction."}
	var keep: Array=[]
	var placed: Array=[]
	var assembly_roads: Array=[]
	var remaps: Dictionary={}
	var original_ids: Dictionary={}
	for item in data["objects"]: original_ids[item["uid"]]=true
	var changed: bool=false
	for entry in result.get("blueprints",[]):
		if not entry["uid"] in ids: keep.append(entry); continue
		changed=true
		if entry["kind"]=="assembly":
			var assembly: Dictionary=Assembly.append_to(entry,result,original_ids,library)
			if not assembly["ok"]: return assembly
			placed.append_array(assembly["objects"])
			assembly_roads.append_array(assembly["roads"])
			remaps[entry["uid"]]=assembly["remap"]
		elif entry["kind"]=="building":
			var item: Dictionary={}
			for key in ["asset","position","direction","scale","angle","tilt"]:
				if entry["item"].has(key): item[key]=entry["item"][key]
			item=item.duplicate(true); item["uid"]="built_"+entry["uid"]
			preload("res://scripts/builder/catalog_defaults.gd").stamp(item)
			for existing in result["objects"]:
				if existing["uid"]==item["uid"]: return {"ok":false,"reason":"A constructed object already uses this proposal identity."}
			result["objects"].append(item)
		else:
			var occupied: Dictionary=Roads.lookup(result); var added: int=0
			for cell in Roads.path(Vector2i(entry["start"][0],entry["start"][1]),Vector2i(entry["end"][0],entry["end"][1])):
				if not occupied.has(Roads.key(cell)): added+=1
			if occupied.size()+added>4096: return {"ok":false,"reason":"Construction exceeds the road section limit."}
			Roads.paint(result,Vector2i(entry["start"][0],entry["start"][1]),Vector2i(entry["end"][0],entry["end"][1]),false,entry["settings"])
	if not changed: return {"ok":true,"changed":false,"data":result}
	result["blueprints"]=keep
	if not placed.is_empty():
		var reason: String=Assembly.location(result,placed,assembly_roads,library)
		if not reason.is_empty(): return Assembly.failure(reason)
		if not load("res://scripts/builder/document.gd").valid(result,data["mode"],library):
			return Assembly.failure("The assembled city contains an invalid construction component.")
	if result["objects"].size()>20000: return {"ok":false,"reason":"Construction exceeds the object limit."}
	var content: Dictionary=preload("res://scripts/builder/asset_palette_policy.gd").check(data,result,library)
	if not content["ok"]:return content
	var quote: Dictionary=preload("res://scripts/builder/economy_plan.gd").quote(data,result,library)
	if not quote["ok"]:
		return {"ok":false,"reason":quote["reason"],"data":result,"quote":quote}
	return {"ok":true,"changed":true,"data":result,"quote":quote,"remaps":remaps}

static func rectangles(entry: Dictionary,mode: String,library: RefCounted) -> Array[Rect2]:
	var result: Array[Rect2]=[]
	if entry["kind"]=="assembly":
		for item in entry["objects"]:
			if library.assets.has(item["asset"]): result.append(Zone.footprint(item,mode,library))
		for road in entry["roads"]: result.append_array(rectangles({"kind":"road","start":road["start"],"end":road["end"],"settings":road["settings"]},mode,library))
	elif entry["kind"]=="building": result.append(Zone.footprint(entry["item"],mode,library))
	else:
		var radius: float=Settings.outer_half(entry["settings"])
		for cell in Roads.path(Vector2i(entry["start"][0],entry["start"][1]),Vector2i(entry["end"][0],entry["end"][1])):
			var at: Vector2=Vector2(cell)*8; var finish: Vector2=Vector2(entry["end"][0],entry["end"][1])*8
			var next: Vector2=at+Vector2(signf(finish.x-at.x)*8,0) if not is_equal_approx(finish.x,at.x) else at+Vector2(0,signf(finish.y-at.y)*8)
			result.append(Rect2(at.min(next)-Vector2.ONE*radius,(next-at).abs()+Vector2.ONE*radius*2))
	return result

# The visual and policy collectors consume the same authored object records.
static func proposal_objects(entry: Dictionary) -> Array:
	match entry.get("kind",""):
		"building": return [entry["item"]]
		"assembly": return entry["objects"]
	return []

static func moved_assembly(entry: Dictionary, at: Array, mode: String) -> Dictionary:
	var moved: Dictionary=entry.duplicate(true)
	var first: Array=entry["objects"][0]["position"]
	var offset: Array=[at[0]-first[0],at[1]-first[1],at[2]-first[2]]
	if not entry["roads"].is_empty():
		var cells: Vector2i=Roads.cell_at(at,mode)-Roads.cell_at(first,mode)
		var shift: Array=Traffic.world(Vector2(cells)*8.0,mode)
		offset[0]=shift[0]
		offset[1 if mode=="2d" else 2]=shift[1 if mode=="2d" else 2]
		for road in moved["roads"]:
			for key in ["start","end"]:
				road[key]=[road[key][0]+cells.x,road[key][1]+cells.y]
	for item in moved["objects"]:
		for axis in 3: item["position"][axis]+=offset[axis]
	return moved
