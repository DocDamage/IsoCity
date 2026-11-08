extends RefCounted

const FORMAT="IsoCity asset collections"
const MAX_BYTES=4*1024*1024
const MAX_COLLECTIONS=64
const MAX_ENTRIES=8192
const MAX_FAMILY_MEMBERS=512
const MAX_MEMBERS=16384

static func failure(reason: String) -> Dictionary:return {"ok":false,"reason":reason}
static func text(value: Variant,limit: int) -> bool:
	if not value is String or value.strip_edges().is_empty() or value.length()>limit:return false
	for index in value.length():
		var code: int=value.unicode_at(index)
		if code<32 or (code>=127 and code<=159):return false
	return true
static func id_valid(value: Variant) -> bool:return text(value,512) and value==value.strip_edges() and value.length()>3 and (value.begins_with("2d:") or value.begins_with("3d:"))
static func name_valid(value: Variant) -> bool:return text(value,80) and value==value.strip_edges()
static func uid_valid(value: Variant) -> bool:return text(value,80) and not "/" in value and not "\\" in value
static func keys(value: Dictionary,allowed: Array) -> bool:return value.keys().all(func(key: Variant):return key is String and key in allowed)
static func version(value: Variant) -> bool:return (value is int or value is float) and is_finite(float(value)) and float(value)==1
static func member_valid(value: Variant) -> bool:return value is Dictionary and keys(value,["id","name"]) and id_valid(value.get("id")) and text(value.get("name"),160)
static func entry_valid(value: Variant) -> bool:
	if not value is Dictionary or not text(value.get("name"),160):return false
	if value.get("kind")=="asset":return keys(value,["kind","id","name"]) and id_valid(value.get("id"))
	if value.get("kind")!="family" or not keys(value,["kind","id","name","members"]) or not text(value.get("id"),160) or not value.get("members") is Array or value["members"].is_empty() or value["members"].size()>MAX_FAMILY_MEMBERS:return false
	var seen: Dictionary={}
	for member in value["members"]:
		if not member_valid(member) or seen.has(member["id"]):return false
		seen[member["id"]]=true
	return true
static func collection_valid(value: Variant) -> bool:
	if not value is Dictionary or not keys(value,["uid","name","entries"]) or not uid_valid(value.get("uid")) or not name_valid(value.get("name")) or not value.get("entries") is Array or value["entries"].size()>MAX_ENTRIES:return false
	var seen: Dictionary={};var count: int=0
	for entry in value["entries"]:
		if not entry_valid(entry):return false
		var key: String=entry["kind"]+":"+entry["id"]
		if seen.has(key):return false
		seen[key]=true;count+=entry["members"].size() if entry["kind"]=="family" else 1
		if count>MAX_MEMBERS:return false
	return true
static func empty() -> Dictionary:return {"version":1,"collections":[],"selected":"","favorites_migrated":false}
static func state_valid(value: Variant) -> bool:
	if not value is Dictionary or not keys(value,["version","collections","selected","favorites_migrated"]) or not version(value.get("version")) or not value.get("collections") is Array or value["collections"].size()>MAX_COLLECTIONS or not value.get("selected") is String or not value.get("favorites_migrated") is bool:return false
	var names: Dictionary={};var ids: Dictionary={}
	for collection in value["collections"]:
		if not collection_valid(collection) or collection["uid"] in ["project","project_palette"] or names.has(collection["name"].to_lower()) or ids.has(collection["uid"]):return false
		names[collection["name"].to_lower()]=true;ids[collection["uid"]]=true
	if value["selected"]!="" and value["selected"]!="project" and not ids.has(value["selected"]):return false
	return JSON.stringify(value).to_utf8_buffer().size()<=MAX_BYTES
static func project_empty() -> Dictionary:return {"version":1,"collection":{"uid":"project_palette","name":"Project palette","entries":[]},"restricted":false}
static func project_valid(value: Variant) -> bool:
	return value is Dictionary and keys(value,["version","collection","restricted"]) and version(value.get("version")) and collection_valid(value.get("collection")) and value["collection"]["uid"]=="project_palette" and value.get("restricted") is bool and JSON.stringify(value).to_utf8_buffer().size()<=MAX_BYTES
static func fingerprint(value: Dictionary) -> String:return JSON.stringify(value).sha256_text()
static func parse(raw: String) -> Variant:
	var parser:=JSON.new();return parser.data if parser.parse(raw)==OK else null
static func fresh_uid() -> String:return "collection_"+Crypto.new().generate_random_bytes(16).hex_encode()
static func member(id: String,library: RefCounted) -> Dictionary:return {"id":id,"name":str(library.assets.get(id,{}).get("name",id)).left(160)}
static func asset_entry(id: String,library: RefCounted) -> Dictionary:
	if not id_valid(id):return failure("Choose a concrete asset identity.")
	var value: Dictionary=member(id,library);value["kind"]="asset"
	return {"ok":true,"entry":value} if entry_valid(value) else failure("The asset name cannot be stored in a collection.")
static func family_entry(id: String,library: RefCounted) -> Dictionary:
	var asset: Dictionary=library.assets.get(id,{});var family: String=asset.get("data",{}).get("family_id","")
	if family.is_empty() or not library.families.members.has(family):return failure("This asset has no reviewed family. Add the concrete member instead.")
	var ids: Array=library.families.members[family].duplicate();ids.sort();var members: Array=[]
	for ident in ids:members.append(member(ident,library))
	var value: Dictionary={"kind":"family","id":family,"name":str(asset["data"].get("family_name",asset["name"])).left(160),"members":members}
	return {"ok":true,"entry":value} if entry_valid(value) else failure("This family is too large or has unreadable member metadata.")
static func collection(state: Dictionary,uid: String) -> Dictionary:
	for item in state.get("collections",[]):
		if item.get("uid")==uid:return item
	return {}
static func rename(value: Dictionary,name: String,others: Array=[]) -> Dictionary:
	if not collection_valid(value) or not name_valid(name):return failure("Choose a collection name of 1–80 characters without surrounding whitespace or control characters.")
	for item in others:
		if item.get("uid")!=value["uid"] and str(item.get("name","")).to_lower()==name.to_lower():return failure("A collection already uses that name. Choose a different name.")
	var result: Dictionary=value.duplicate(true);result["name"]=name;return {"ok":true,"data":result,"changed":result!=value}
static func create(name: String,others: Array=[]) -> Dictionary:
	if others.size()>=MAX_COLLECTIONS:return failure("Keep up to 64 personal collections. Export or remove one before adding another.")
	return rename({"uid":fresh_uid(),"name":"New collection","entries":[]},name,others)
static func put(value: Dictionary,entry: Dictionary,index: int=-1) -> Dictionary:
	if not collection_valid(value) or not entry_valid(entry) or index < -1 or index>=value["entries"].size():return failure("Choose a valid collection member to add or replace.")
	var result: Dictionary=value.duplicate(true)
	for at in result["entries"].size():
		var other: Dictionary=result["entries"][at]
		if at!=index and other["kind"]==entry["kind"] and other["id"]==entry["id"]:return failure("That exact asset or family is already listed.")
	if index<0:result["entries"].append(entry.duplicate(true))
	else:result["entries"][index]=entry.duplicate(true)
	return {"ok":true,"data":result,"changed":result!=value} if collection_valid(result) else failure("The collection exceeds its supported size.")
static func replace_member(value: Dictionary,index: int,member_index: int,replacement: Dictionary) -> Dictionary:
	if not collection_valid(value) or not member_valid(replacement) or index<0 or index>=value["entries"].size():return failure("Choose an existing member and a concrete replacement.")
	var result: Dictionary=value.duplicate(true);var entry: Dictionary=result["entries"][index]
	if entry["kind"]!="family" or member_index<0 or member_index>=entry["members"].size():return failure("Choose a member within the saved family snapshot.")
	entry["members"][member_index]=replacement.duplicate(true)
	return {"ok":true,"data":result,"changed":result!=value} if collection_valid(result) else failure("That replacement is already in this family snapshot.")
static func remove(value: Dictionary,index: int,member_index: int=-1) -> Dictionary:
	if not collection_valid(value) or index<0 or index>=value["entries"].size():return failure("Choose an existing collection entry.")
	var result: Dictionary=value.duplicate(true);var entry: Dictionary=result["entries"][index]
	if member_index>=0:
		if entry["kind"]!="family" or member_index>=entry["members"].size():return failure("Choose an existing member within this family snapshot.")
		entry["members"].remove_at(member_index)
		if entry["members"].is_empty():result["entries"].remove_at(index)
	else:result["entries"].remove_at(index)
	return {"ok":true,"data":result,"changed":true}
static func available(id: String,library: RefCounted) -> bool:
	var asset: Dictionary=library.assets.get(id,{})
	return not asset.is_empty() and not asset.get("unavailable",false) and not asset.get("hidden",false) and asset.get("path") is String and FileAccess.file_exists(asset["path"]) and ResourceLoader.exists(asset["path"])
static func resolve(value: Dictionary,library: RefCounted) -> Dictionary:
	var result: Dictionary={"ok":collection_valid(value),"ids":{},"available":{},"missing":[],"rows":[],"missing_families":[]};var missing_ids: Dictionary={}
	if not result["ok"]:return result
	for index in value["entries"].size():
		var entry: Dictionary=value["entries"][index];var members: Array=entry["members"] if entry["kind"]=="family" else [{"id":entry["id"],"name":entry["name"]}]
		if entry["kind"]=="family" and not library.families.members.has(entry["id"]):result["missing_families"].append(entry["id"])
		for at in members.size():
			var item: Dictionary=members[at];var present: bool=available(item["id"],library)
			var row: Dictionary={"entry":index,"member":at if entry["kind"]=="family" else -1,"id":item["id"],"name":str(library.assets[item["id"]]["name"]) if present else item["name"],"available":present,"family":entry["name"] if entry["kind"]=="family" else ""}
			result["rows"].append(row);result["ids"][item["id"]]=true
			if present:result["available"][item["id"]]=true
			elif not missing_ids.has(item["id"]):result["missing"].append(row.duplicate(true));missing_ids[item["id"]]=true
	return result
static func package(values: Array) -> Dictionary:
	return {"format":FORMAT,"version":1,"collections":values.duplicate(true)}
static func package_valid(value: Variant) -> bool:
	if not value is Dictionary or not keys(value,["format","version","collections"]) or value.get("format")!=FORMAT or not version(value.get("version")) or not value.get("collections") is Array or value["collections"].is_empty() or value["collections"].size()>MAX_COLLECTIONS:return false
	return value["collections"].all(collection_valid) and JSON.stringify(value).to_utf8_buffer().size()<=MAX_BYTES
static func unique_name(name: String,values: Array) -> String:
	var result: String=name;var suffix: int=1;var used: Dictionary={}
	for value in values:used[value["name"].to_lower()]=true
	while used.has(result.to_lower()):suffix+=1;var end: String=" ("+str(suffix)+")";result=name.left(80-end.length())+end
	return result
static func import_plan(state: Dictionary,raw: String) -> Dictionary:
	if not state_valid(state):return failure("The current personal collections are invalid. Export a recovery copy before replacing them.")
	if raw.to_utf8_buffer().size()>MAX_BYTES:return failure("Collection files must be 4 MB or smaller.")
	var parsed: Variant=parse(raw)
	if not package_valid(parsed):return failure("Choose a version 1 IsoCity collection file containing valid asset references.")
	if state["collections"].size()+parsed["collections"].size()>MAX_COLLECTIONS:return failure("Import would exceed 64 personal collections. Export or remove an existing collection first.")
	var result: Dictionary=state.duplicate(true);var changes: Array=[]
	for incoming in parsed["collections"]:
		var item: Dictionary=incoming.duplicate(true);var used: Dictionary={}
		for existing in result["collections"]:used[existing["uid"]]=true
		var uid: String="import_preview_"+str(result["collections"].size())
		while used.has(uid):uid+="_"
		item["uid"]=uid;item["name"]=unique_name(item["name"],result["collections"]);result["collections"].append(item)
		changes.append({"from":incoming["name"],"to":item["name"],"uid":uid})
	if not state_valid(result):return failure("Imported collections exceed the supported reference-data size.")
	return {"ok":true,"data":result,"source_hash":fingerprint(state),"changes":changes,"review_hash":JSON.stringify([result,changes]).sha256_text()}
static func materialize_import(plan: Dictionary,state: Dictionary) -> Dictionary:
	if not plan.get("ok",false) or plan.get("source_hash")!=fingerprint(state) or not state_valid(plan.get("data")) or plan.get("review_hash")!=JSON.stringify([plan.get("data"),plan.get("changes")]).sha256_text():return failure("Personal collections or the reviewed import changed. Review the import again.")
	var result: Dictionary=plan["data"].duplicate(true)
	for change in plan["changes"]:
		var item: Dictionary=collection(result,change["uid"])
		if item.is_empty():return failure("The reviewed import no longer has the expected collections.")
		item["uid"]=fresh_uid()
	return {"ok":true,"data":result,"changed":result!=state}
static func migrate_favorites(state: Dictionary,favorites: Array,library: RefCounted) -> Dictionary:
	if not state_valid(state):return failure("Restore valid personal preferences before copying favorites.")
	if state["favorites_migrated"]:return {"ok":true,"changed":false,"data":state.duplicate(true),"skipped":[]}
	var result: Dictionary=state.duplicate(true);var entries: Array=[];var seen: Dictionary={};var skipped: Array=[]
	for id in favorites:
		if not id_valid(id):skipped.append(id);continue
		if seen.has(id):continue
		var entry: Dictionary=asset_entry(id,library)
		if not entry["ok"]:return entry
		entries.append(entry["entry"]);seen[id]=true
	if not entries.is_empty():
		var created: Dictionary=create(unique_name("Favorites copy",result["collections"]),result["collections"])
		if not created["ok"]:return created
		created["data"]["entries"]=entries;result["collections"].append(created["data"])
	result["favorites_migrated"]=true
	return {"ok":true,"changed":result!=state,"data":result,"skipped":skipped} if state_valid(result) else failure("Favorites exceed the supported collection size. The original favorites remain unchanged.")

# The policy compares authored identities and scoped references. Existing
# content stays editable when a project owner narrows the palette. New copies,
# replacements, nested rooms and planned buildings must use allowed identities.
static func records(world: Dictionary,prefix: Array=[],cooking_enabled: bool=false,fitness_enabled: bool=false) -> Dictionary:
	var result: Dictionary={}
	var gardens=preload("res://scripts/builder/garden_plan.gd")
	var active_garden: bool=gardens.settings(world)
	var cooking=preload("res://scripts/builder/cooking_plan.gd")
	cooking_enabled=cooking_enabled or cooking.enabled(world)
	var fitness=preload("res://scripts/builder/fitness_plan.gd")
	fitness_enabled=fitness_enabled or fitness.enabled(world)
	for item in world.get("objects",[]):
		var path: Array=prefix+["object",item["uid"]];result[JSON.stringify(path)]=item["asset"]
		if active_garden:
			var art: String=gardens.crop_art(item)
			if not art.is_empty(): result[JSON.stringify(path+["garden_crop_art"])]=art
		if cooking_enabled:
			var food: String=cooking.serving_art(item)
			if not food.is_empty(): result[JSON.stringify(path+["cooking_serving_art"])]=food
		if fitness_enabled and fitness.station(item,world.get("mode","2d")).get("kind")=="penalty":
			result[JSON.stringify(path+["sports_ball"])]=fitness.definitions()["ball"]
		if item.get("interior") is Dictionary:result.merge(records(item["interior"],path+["interior"],cooking_enabled,fitness_enabled))
	for tile in world.get("tiles",[]):result[JSON.stringify(prefix+["tile",[int(tile["cell"][0]),int(tile["cell"][1])]])]=tile["asset"]
	for floor in world.get("floors",[]):result.merge(records(floor["room"],prefix+["floor",floor["uid"]],cooking_enabled,fitness_enabled))
	for proposal in world.get("blueprints",[]):
		# Building proposals carry a proposal identity, not an object uid. The
		# ordinary blueprint constructor allocates the built object later.
		if proposal.get("kind")=="building":result[JSON.stringify(prefix+["plan",proposal["uid"],"asset"])]=proposal["item"]["asset"]
		elif proposal.get("kind")=="assembly":
			result.merge(records({"objects":proposal["objects"]},prefix+["plan",proposal["uid"]]))
	for lot in world.get("zones",[]):
		if not lot.get("proposal",{}).is_empty():result[JSON.stringify(prefix+["zone",lot["uid"],"asset"])]=lot["proposal"]["asset"]
	for role in world.get("fleet",{}):
		for entry in world["fleet"][role]:
			result[JSON.stringify(prefix+["fleet",role,entry["asset"]])]=entry["asset"]
	for asset in preload("res://scripts/builder/village_plan.gd").required_delivery_art(world):
		result[JSON.stringify(prefix+["village_delivery",asset])]=asset
	for asset in preload("res://scripts/builder/space_outpost_plan.gd").required(world):
		result[JSON.stringify(prefix+["space_outpost",asset])]=asset
	var pet_asset: String=preload("res://scripts/builder/pet_plan.gd").required(world)
	if not pet_asset.is_empty(): result[JSON.stringify(prefix+["pet_companion"])]=pet_asset
	var appearance: String=world.get("citizens",{}).get("appearance","")
	if not appearance.is_empty():result[JSON.stringify(prefix+["citizen_appearance"])]=appearance
	return result
static func allows(before: Dictionary,after: Dictionary,policy: Dictionary) -> Dictionary:
	if policy.is_empty():return {"ok":true,"blocked":[]}
	if not project_valid(policy):return failure("Review the unreadable project palette before construction.")
	if not policy["restricted"]:return {"ok":true,"blocked":[]}
	var allowed: Dictionary={}
	for entry in policy["collection"]["entries"]:
		if entry["kind"]=="asset":allowed[entry["id"]]=true
		else:
			for item in entry["members"]:allowed[item["id"]]=true
	var old: Dictionary=records(before);var next: Dictionary=records(after);var blocked: Array=[]
	for path in next:
		if next[path]!=old.get(path) and not allowed.has(next[path]):blocked.append({"scope":path,"id":next[path]})
	return {"ok":blocked.is_empty(),"blocked":blocked,"reason":"The project content restriction excludes %d proposed asset references. Add them to the project palette or ask the project owner to change its restriction."%blocked.size() if not blocked.is_empty() else ""}
