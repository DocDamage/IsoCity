extends RefCounted
const Kits=preload("res://scripts/builder/interior_kits.gd")
const Floors=preload("res://scripts/builder/floor_plan.gd")
const Doc=preload("res://scripts/builder/document.gd")
const Layers=preload("res://scripts/builder/layers.gd")
const SHELLS="res://resources/catalog/interior_shells.json"

static func failure(reason: String) -> Dictionary:return {"ok":false,"reason":reason,"missing":[]}
static func fingerprint(value: Dictionary) -> String:return JSON.stringify(value).sha256_text()
static func owner(source: Dictionary,uid: String) -> Dictionary:
	for item in source.get("objects",[]):
		if item.get("uid")==uid:return item
	return {}

static func shell(mode: String,library: RefCounted=null) -> Dictionary:
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(SHELLS)) if FileAccess.file_exists(SHELLS) else null
	if not raw is Dictionary or raw.get("version")!=1 or not raw.get("sources") is Dictionary or not raw.get("rooms") is Dictionary or not raw["rooms"].get(mode) is Dictionary:return {}
	for path in raw["sources"]:
		if not path is String or not raw["sources"][path] is String or FileAccess.get_sha256(path)!=raw["sources"][path]:return {}
	var result: Dictionary=raw["rooms"][mode].duplicate(true)
	return result if result.get("objects") is Array and result.get("tiles") is Array and (not library or Doc.valid(result,mode,library)) else {}

static func unique_id(used: Dictionary,prefix: String) -> String:
	var candidate: String=prefix;var serial: int=0
	while used.has(candidate):serial+=1;candidate=prefix+"_"+str(serial)
	used[candidate]=true;return candidate

# Source is the exterior document; floor selection is an explicit input. Every
# returned dictionary is private. Stable temporary IDs make equivalent previews
# comparable; fresh saved identities are allocated only when applying a proposal.
static func propose(source: Dictionary,owner_uid: String,floor_uid: String,key: String,action: String,offset: Array,library: RefCounted,new_name: String="New floor",height: float=3) -> Dictionary:
	if source.get("mode") not in ["2d","3d"] or not preload("res://scripts/builder/asset_health.gd").vector(offset,2,-64,64):return failure("Choose a valid room offset.")
	if action not in ["create","add","replace","floor"]:return failure("Choose a room action.")
	var host: Dictionary=owner(source,owner_uid)
	if host.is_empty() or not preload("res://scripts/builder/exploration.gd").has_room(host,library):return failure("Select a building with an editable interior.")
	if not Layers.editable(source,host,library):return failure("Show and unlock the building before changing its interior.")
	var mode: String=source["mode"];var checked: Dictionary=Kits.plan(key,mode,library)
	if not checked["ok"]:return {"ok":false,"reason":"This kit has unavailable assets. Install or repair its dependencies before applying it.","missing":checked["missing"]}
	var owned: Dictionary=host.get("interior",{});var fresh: bool=owned.is_empty()
	if fresh and action!="create":return failure("Create the first room before adding furnishings or another floor.")
	if not fresh and action=="create":return failure("This building already owns a room. Choose Add, Replace or New floor.")
	if not fresh and Floors.room(owned,floor_uid).is_empty():return failure("The selected floor no longer exists.")
	var data: Dictionary=source.duplicate(true);var target: Dictionary=owner(data,owner_uid);var root: Dictionary=owned.duplicate(true);var selected: String="ground" if fresh else floor_uid
	var room: Dictionary=shell(mode,library) if fresh or action in ["replace","floor"] else Floors.room(root,floor_uid)
	if room.is_empty():return failure("The room shell is unavailable or outdated. Restore the installed assets, or add furnishings to an existing room.")
	var original: Dictionary={} if fresh else Floors.room(root,floor_uid)
	var removed: Array=[]
	if action=="replace":
		for item in original["objects"]:
			if not Layers.editable(original,item,library):return failure("Replacement includes hidden or locked objects. Show and unlock the affected room, or use Add.")
			removed.append(item["uid"])
		# Replace the visible layout, preserving room settings, exit, other floors
		# and connection identities. The preview includes the changed shell/tiles.
		var objects: Array=room["objects"];var tiles: Array=room["tiles"];room=original.duplicate(true);room["objects"]=objects;room["tiles"]=tiles
	if fresh:room["title"]=host.get("name",library.assets[host["asset"]]["name"])+" · Interior"
	if action=="floor":
		if not Floors.named(new_name) or not is_finite(height):return failure("Choose a valid floor name and height.")
		var floor_ids: Dictionary={"ground":true}
		for floor in root.get("floors",[]):floor_ids[floor["uid"]]=true
		selected=unique_id(floor_ids,"kit_floor_preview");room["title"]=new_name.strip_edges()+" · Interior"
	var used: Dictionary={};var created: Array=[]
	for item in room["objects"]:used[item["uid"]]=true
	if action!="add":
		# Every replacement shell object is also new, even when a temporary ID
		# coincides with one in a previously created room.
		for item in room["objects"]:item["uid"]=unique_id(used,"preview_shell_"+str(created.size()));created.append(item["uid"])
	for record in checked["objects"]:
		var shifted: Dictionary=record.duplicate(true);shifted["position"][0]+=float(offset[0]);shifted["position"][2]+=float(offset[1])
		var item: Dictionary=Kits.placed(shifted,mode,library,unique_id(used,"preview_kit_"+str(created.size())))
		if Layers.locked(room,Layers.layer(item,library)) or not Layers.shown(room,Layers.layer(item,library)):return failure("Show and unlock the kit's destination layers before applying it.")
		room["objects"].append(item);created.append(item["uid"])
	if fresh or action=="floor":room["starter_kit"]={"id":key,"revision":int(checked["revision"])}
	if fresh:root=room
	elif action=="floor":
		var added: Dictionary=Floors.put_floor(root,{"uid":selected,"name":new_name.strip_edges(),"height":height,"room":room})
		if not added["ok"]:return failure(added["error"])
		root=added["data"]
	elif selected=="ground":root=room
	else:
		for floor in root.get("floors",[]):
			if floor["uid"]==selected:floor["room"]=room
	target["interior"]=root
	if not Doc.valid(data,mode,library):return failure("The proposed layout exceeds the document or floor limits.")
	var health: RefCounted=preload("res://scripts/builder/asset_health.gd").new();var assets: Dictionary={};var missing: Array=[]
	for item in room["objects"]:assets[item["asset"]]=true
	for tile in room["tiles"]:assets[tile["asset"]]=true
	for id in assets:
		if not library.assets.has(id) or library.assets[id].get("unavailable",false):missing.append({"name":id,"reason":"Prepared asset unavailable."});continue
		for issue in health.dependency_errors(library.assets[id]["path"],{}):
			if issue.get("severity","defect")=="defect":missing.append({"name":library.assets[id]["name"],"reason":issue["detail"]})
	if not missing.is_empty():return {"ok":false,"reason":"The affected room has unavailable dependencies.","missing":missing}
	for path in health.dependencies:
		if not preload("res://scripts/builder/model_preview.gd").import_current(path):missing.append({"name":path.get_file(),"reason":"Prepared source needs an up-to-date Godot import. Reimport changed resources before reviewing this layout."})
	if not missing.is_empty():return {"ok":false,"reason":"Import the changed or newly installed room resources before applying a layout.","missing":missing}
	var dependencies: Dictionary={}
	for path in health.dependencies:dependencies[path]=FileAccess.get_sha256(path)
	for path in [Kits.PATH,SHELLS,"res://resources/catalog/props.json","res://resources/catalog/model_grid_bounds.json","res://resources/catalog/economy.json","res://resources/catalog/asset_behavior.json"]:
		if FileAccess.file_exists(path):dependencies[path]=FileAccess.get_sha256(path)
	var allowances: Dictionary=preload("res://scripts/builder/cooperative_plan.gd").complimentary_rooms(source,data,library)
	var quote: Dictionary=preload("res://scripts/builder/economy_plan.gd").quote(source,data,library,allowances)
	return {"ok":true,"source_hash":fingerprint(source),"data":data,"owner_uid":owner_uid,"floor_uid":selected,"previous_floor":floor_uid,"room":room,"root":root,"kit":key,"action":action,"created":created,"removed":removed,"quote":quote,"allowances":allowances,"dependencies":dependencies,"dimensions":checked["dimensions"][mode],"contents":checked["objects"],"missing":[],"geometry_checked":false,"issues":[]}

static func current(proposal: Dictionary,source: Dictionary) -> bool:
	if not proposal.get("ok",false) or proposal.get("source_hash")!=fingerprint(source):return false
	for path in proposal["dependencies"]:
		if FileAccess.get_sha256(path)!=proposal["dependencies"][path]:return false
	return true

# Standalone room templates use ordinary document history. Their multi-storey
# traversal is not an owned building; additional floors stay with owned rooms.
static func propose_room(source: Dictionary,key: String,action: String,offset: Array,library: RefCounted) -> Dictionary:
	if not source.get("interior_room",false) and source.get("template")!="room":return failure("Choose a room template or an owned interior.")
	if action not in ["add","replace"]:return failure("Create additional floors while editing an owned building's interior.")
	if library.assets.is_empty():return failure("The asset library is unavailable.")
	if source.get("mode") not in ["2d","3d"] or not Doc.valid(source,source["mode"],library):return failure("The room document is invalid.")
	var base: Dictionary=source.duplicate(true);base["interior_room"]=true;base.erase("protected_areas")
	var wrapper: Dictionary={"mode":source["mode"],"title":"Private room proposal","night":false,"tiles":[],"objects":[{"uid":"room_proposal","asset":library.assets.keys()[0],"layer":"Buildings","position":[0,0,0],"direction":str(library.directions(library.assets.keys()[0])[0]),"scale":1.0,"interior":base}]}
	var result: Dictionary=propose(wrapper,"room_proposal","ground",key,action,offset,library)
	if not result["ok"]:return result
	var room: Dictionary=result["root"]
	if not source.has("interior_room"):room.erase("interior_room")
	if source.has("protected_areas"):room["protected_areas"]=source["protected_areas"].duplicate(true)
	if not Doc.valid(room,source["mode"],library):return failure("The proposed room document is invalid.")
	result["scope"]="standalone";result["owner_uid"]="";result["data"]=room;result["root"]=room;result["room"]=room;result["source_hash"]=fingerprint(source);result["allowances"]={}
	result["quote"]=preload("res://scripts/builder/economy_plan.gd").quote(source,room,library)
	return result

static func materialize(proposal: Dictionary) -> Dictionary:
	var data: Dictionary=proposal["data"].duplicate(true);var standalone: bool=proposal.get("scope")=="standalone";var host: Dictionary={} if standalone else owner(data,proposal["owner_uid"]);var selected: String=proposal["floor_uid"]
	var room: Dictionary=data if standalone else Floors.room(host["interior"],selected);var mapping: Dictionary={}
	for item in room["objects"]:
		if item["uid"] in proposal["created"]:mapping[item["uid"]]="kit_"+Crypto.new().generate_random_bytes(16).hex_encode();item["uid"]=mapping[item["uid"]]
	for item in room["objects"]:preload("res://scripts/builder/owned_room_copy.gd").remap_target(item,mapping)
	if proposal["action"]=="floor":
		for floor in host["interior"]["floors"]:
			if floor["uid"]==selected:floor["uid"]="floor_"+Crypto.new().generate_random_bytes(16).hex_encode();selected=floor["uid"]
	return {"data":data,"root":data if standalone else host["interior"],"floor_uid":selected,"ids":mapping}
