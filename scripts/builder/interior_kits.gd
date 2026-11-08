extends RefCounted

const PATH="res://resources/catalog/interior_kits.json"
const Grid=preload("res://scripts/builder/grid_fit.gd")
static var catalog: Dictionary={}
static var catalog_hash: String=""
static var sequence: int=0

static func definitions() -> Dictionary:
	var current: String=FileAccess.get_sha256(PATH) if FileAccess.file_exists(PATH) else ""
	if catalog.is_empty() or current!=catalog_hash:
		var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		catalog=raw if raw is Dictionary and raw.get("version")==1 and raw.get("kits") is Dictionary and raw.get("buildings") is Dictionary else {"version":1,"kits":{},"buildings":{}}
		catalog_hash=current
	return catalog

static func default_for(asset: String) -> String:
	return str(definitions().get("buildings",{}).get(asset,""))

static func valid_definition(value: Variant,mode: String,library: RefCounted) -> bool:
	if not value is Dictionary or not value.get("name") is String or value["name"].is_empty() or value["name"].length()>160:return false
	if not preload("res://scripts/builder/asset_health.gd").number(value.get("revision"),1,100000,true):return false
	if not value.get("dimensions") is Dictionary or not preload("res://scripts/builder/asset_health.gd").vector(value["dimensions"].get(mode),2,1,128):return false
	if not value.get("objects") is Array or value["objects"].size()>256:return false
	for record in value["objects"]:
		if not record is Dictionary or not record.get("asset") is String or not record.get("direction") is String:return false
		if not preload("res://scripts/builder/asset_health.gd").vector(record.get("position"),3,-64,64):return false
		if not preload("res://scripts/builder/asset_health.gd").number(record.get("scale",1),.05,10):return false
		if library.assets.has(record["asset"]) and not library.valid_direction(record["asset"],record["direction"]):return false
		if record.has("prop") and not preload("res://scripts/builder/prop_plan.gd").valid(record["prop"]):return false
	return true

# Read-only preflight. No scene instantiation, generated UIDs, history or rooms.
static func plan(key: String,mode: String,library: RefCounted) -> Dictionary:
	var definition: Variant=definitions().get("kits",{}).get(key,{})
	if mode not in ["2d","3d"] or not valid_definition(definition,mode,library):return {"ok":false,"id":key,"missing":[{"name":"Interior kit","reason":"Unavailable or invalid kit definition."}],"message":"This interior kit is unavailable."}
	var result: Dictionary=definition.duplicate(true);result["id"]=key;result["missing"]=[];result["dependencies"]=[]
	var health: RefCounted=preload("res://scripts/builder/asset_health.gd").new()
	for record in definition["objects"]:
		var id: String=record["asset"]
		if id in result["dependencies"]:continue
		result["dependencies"].append(id)
		var asset: Dictionary=library.assets.get(id,{})
		if asset.is_empty() or asset.get("unavailable",false):result["missing"].append({"id":id,"name":asset.get("name",id),"reason":"Asset pack unavailable."});continue
		var errors: Array=health.dependency_errors(asset["path"],{}).filter(func(issue: Dictionary):return issue.get("severity","defect")=="defect")
		if not errors.is_empty():result["missing"].append({"id":id,"name":asset["name"],"reason":"Prepared source dependency unavailable."})
	result["dependencies"].sort();result["ok"]=result["missing"].is_empty()
	result["message"]="Starter furnishings are complimentary; later edits and duplicated furnishings use ordinary construction prices." if result["ok"] else "Some kit assets are unavailable. A clear empty shell will be created instead."
	return result

static func dependencies_for(asset: String,mode: String,library: RefCounted) -> Array:
	var key: String=default_for(asset)
	if key.is_empty():return []
	var checked: Dictionary=plan(key,mode,library)
	return checked.get("dependencies",[]) if checked["ok"] else []

static func furnish(base: Dictionary,key: String,library: RefCounted) -> Dictionary:
	var checked: Dictionary=plan(key,base["mode"],library);var room: Dictionary=base.duplicate(true)
	# Keep the tested room shell and replace only its starter furniture. Exterior
	# scale has no effect on these independently editable room-local coordinates.
	room["objects"]=room["objects"].filter(func(item: Dictionary):return item["asset"] in ["2d:Wall_White","3d:HanX_Shop/Floor_Tile_Store","3d:HanX_Shop/Wall_Store_Segment"])
	room["starter_kit"]={"id":key if checked["ok"] else "empty","revision":int(checked.get("revision",1))}
	if not checked["ok"]:
		room["starter_kit"]["requested"]=key;room["starter_kit"]["missing"]=checked["missing"].duplicate(true);return room
	for record in checked["objects"]:
		sequence+=1
		room["objects"].append(placed(record,base["mode"],library,"kit_"+Crypto.new().generate_random_bytes(16).hex_encode()))
	return room

# The same source-space placement for private deterministic proposals and actual
# starter creation. The caller owns identity allocation; previewing allocates none.
static func placed(record: Dictionary,mode: String,library: RefCounted,uid: String) -> Dictionary:
	var raw: Array=record["position"];var ground: Array=Grid.pixel_values([raw[0],raw[2]])
	var item: Dictionary={"uid":uid,"asset":record["asset"],"direction":record["direction"],"scale":float(record.get("scale",1)),"position":[ground[0],ground[1],float(raw[1])] if mode=="2d" else [float(raw[0]),float(raw[1])+.12,float(raw[2])]}
	item["name"]=str(record.get("zone",""))+" · "+library.assets[item["asset"]]["name"]
	if record.has("prop"):item["prop"]=record["prop"].duplicate(true)
	return item
