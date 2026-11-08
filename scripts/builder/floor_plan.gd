extends RefCounted

# Ground remains the original owned room. Additional rooms use their own local
# coordinates. Heights use metres; connection X/Z and widths use native room
# grid cells in 2D and world metres in 3D.
const MAX_FLOORS: int = 8
const MAX_LINKS: int = 32
const MAX_ENTRANCES: int = 16
const MIN_GAP: float = 2.4
const FIELDS: Array = ["floor_name","floors","floor_links","floor_entrances"]

static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func coordinates(value: Variant, size: int, limit: float) -> bool:
	if not value is Array or value.size()!=size: return false
	for part in value:
		if not number(part) or absf(float(part))>limit: return false
	return true

static func identity(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length()>64: return false
	for character in value:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-": return false
	return true

static func named(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty() and value.length()<=80

static func definitions(root: Dictionary) -> Array:
	# References are returned for editing, never inserted into the saved root.
	var result: Array=[{"uid":"ground","name":root.get("floor_name","Ground"),"height":0.0,"room":root}]
	result.append_array(root.get("floors",[]))
	result.sort_custom(func(a: Dictionary,b: Dictionary)->bool: return float(a["height"])<float(b["height"]))
	return result

static func room(root: Dictionary, uid: String) -> Dictionary:
	if uid=="ground": return root
	for floor in root.get("floors",[]):
		if floor["uid"]==uid: return floor["room"]
	return {}

static func floor_record(value: Variant, mode: String) -> bool:
	if not value is Dictionary or not identity(value.get("uid")) or value["uid"]=="ground" or not named(value.get("name")): return false
	if not number(value.get("height")) or value["height"] < -24 or value["height"] > 32 or absf(value["height"])<MIN_GAP: return false
	if not value.get("room") is Dictionary or value["room"].get("mode")!=mode or value["room"].get("interior_room")!=true: return false
	for field in FIELDS:
		if value["room"].has(field): return false
	return true

static func link_record(value: Variant, heights: Dictionary) -> bool:
	if not value is Dictionary or not identity(value.get("uid")) or not value.get("kind") in ["stairs","elevator"]: return false
	if not value.get("lower") is String or not value.get("upper") is String or not heights.has(value["lower"]) or not heights.has(value["upper"]): return false
	var rise: float=heights[value["upper"]]-heights[value["lower"]]
	if rise<MIN_GAP-0.00001 or not coordinates(value.get("start"),2,64) or not coordinates(value.get("end"),2,64): return false
	if not number(value.get("width")) or value["width"]<0.8 or value["width"]>4: return false
	var run: float=Vector2(value["start"][0],value["start"][1]).distance_to(Vector2(value["end"][0],value["end"][1]))
	if value["kind"]=="elevator": return run<=0.01
	if rise>8 or run<rise*1.4-0.00001 or run>32: return false
	for height in heights.values():
		if height>heights[value["lower"]] and height<heights[value["upper"]]: return false
	return true

static func entrance_record(value: Variant, heights: Dictionary) -> bool:
	if not value is Dictionary or not identity(value.get("uid")) or not value.get("floor") is String or not heights.has(value["floor"]): return false
	if not coordinates(value.get("position"),3,4096): return false
	if value.has("arrival") and not coordinates(value["arrival"],3,4096): return false
	return not value.has("view") or value["view"] in ["NE","NW","SE","SW"]

static func compatible_link(value: Dictionary,accepted: Array,heights: Dictionary) -> bool:
	if value["kind"]!="elevator": return true
	for other in accepted:
		if other["kind"]!="elevator": continue
		if heights[value["lower"]]>=heights[other["upper"]]+2.15 or heights[other["lower"]]>=heights[value["upper"]]+2.15: continue
		var radius: float=(float(value["width"])+float(other["width"]))*0.5+0.7
		if absf(value["start"][0]-other["start"][0])<radius and absf(value["start"][1]-other["start"][1])<radius: return false
	return true

static func valid(root: Dictionary) -> bool:
	var authored: bool=false
	for field in FIELDS: authored=authored or root.has(field)
	if not authored: return true
	if root.get("interior_room")!=true or not root.get("mode") in ["2d","3d"]: return false
	if root.has("floor_name") and not named(root["floor_name"]): return false
	var floors: Variant=root.get("floors",[])
	if not floors is Array or floors.size()>=MAX_FLOORS: return false
	var heights: Dictionary={"ground":0.0}
	for floor in floors:
		if not floor_record(floor,root["mode"]) or heights.has(floor["uid"]): return false
		for height in heights.values():
			if absf(height-float(floor["height"]))<MIN_GAP-0.00001: return false
		heights[floor["uid"]]=float(floor["height"])
	for field in ["floor_links","floor_entrances"]:
		var records: Variant=root.get(field,[]); var seen: Dictionary={}; var accepted: Array=[]
		if not records is Array or records.size()>(MAX_LINKS if field=="floor_links" else MAX_ENTRANCES): return false
		for record in records:
			if not (link_record(record,heights) if field=="floor_links" else entrance_record(record,heights)): return false
			if seen.has(record["uid"]): return false
			if field=="floor_links" and not compatible_link(record,accepted,heights): return false
			seen[record["uid"]]=true
			accepted.append(record)
	return true

static func result(source: Dictionary, changed: Dictionary) -> Dictionary:
	if not valid(changed): return {"ok":false,"error":"Floors need unique IDs, supported heights, and valid connections and entrances."}
	return {"ok":true,"data":changed,"changed":changed!=source}

static func put_floor(root: Dictionary, floor: Dictionary) -> Dictionary:
	if not valid(root) or not floor_record(floor,str(root.get("mode",""))): return {"ok":false,"error":"Choose a named floor with a separate room and a supported height."}
	var copy: Dictionary=root.duplicate(true); var floors: Array=copy.get("floors",[]); var found: bool=false
	for index in floors.size():
		if floors[index]["uid"]==floor["uid"]: floors[index]=floor.duplicate(true); found=true; break
	if not found and floors.size()>=MAX_FLOORS-1: return {"ok":false,"error":"A building supports up to 8 floors, including the ground floor. Remove a floor before adding another."}
	if not found: floors.append(floor.duplicate(true))
	copy["floors"]=floors
	return result(root,copy)

static func remove_floor(root: Dictionary, uid: String) -> Dictionary:
	if not valid(root) or uid=="ground" or room(root,uid).is_empty(): return {"ok":false,"error":"Choose an additional floor to remove."}
	var copy: Dictionary=root.duplicate(true)
	copy["floors"]=copy.get("floors",[]).filter(func(value: Dictionary)->bool:return value["uid"]!=uid)
	for field in ["floor_links","floor_entrances"]:
		if copy.has(field): copy[field]=copy[field].filter(func(value: Dictionary)->bool:return value.get("floor")!=uid and value.get("lower")!=uid and value.get("upper")!=uid)
	return result(root,copy)

static func put_record(root: Dictionary, field: String, record: Dictionary) -> Dictionary:
	if not field in ["floor_links","floor_entrances"] or not valid(root): return {"ok":false,"error":"Choose a floor connection or entrance."}
	var copy: Dictionary=root.duplicate(true); var records: Array=copy.get(field,[]); var found: bool=false
	for index in records.size():
		if records[index]["uid"]==record.get("uid"): records[index]=record.duplicate(true); found=true; break
	if not found: records.append(record.duplicate(true))
	copy[field]=records
	return result(root,copy)

static func remove_record(root: Dictionary, field: String, uid: String) -> Dictionary:
	if not field in ["floor_links","floor_entrances"] or not valid(root): return {"ok":false,"error":"Choose a floor connection or entrance."}
	var copy: Dictionary=root.duplicate(true)
	copy[field]=copy.get(field,[]).filter(func(value: Dictionary)->bool:return value["uid"]!=uid)
	return result(root,copy)
