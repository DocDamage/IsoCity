extends RefCounted
const PATH="res://resources/catalog/zoning_candidates.json"
const Economy=preload("res://scripts/builder/economy_plan.gd")
const Availability=preload("res://scripts/builder/asset_collections.gd")
const Policy=preload("res://scripts/builder/asset_palette_policy.gd")
const DENSITIES=["any","low","medium","high"]
static var cached: Dictionary={}
static var error: String=""
static var prepared_sources: Dictionary={}

static func definitions() -> Dictionary:
	if not cached.is_empty():return cached
	var file:=FileAccess.open(PATH,FileAccess.READ)
	if not file or file.get_length()>4*1024*1024:error="The zoning candidate catalog is missing or exceeds 4 MB.";return {}
	var parser:=JSON.new()
	if not FileAccess.file_exists(PATH) or parser.parse(file.get_as_text())!=OK or not valid(parser.data):error="The reviewed zoning candidate catalog is unreadable. Restore it before planning new growth.";return {}
	cached=parser.data;return cached
static func text(value: Variant,limit: int) -> bool:return value is String and not value.is_empty() and value.length()<=limit and not value.contains("\n") and not value.contains("\r")
static func pair(value: Variant,low: float,high: float) -> bool:
	return value is Array and value.size()==2 and value.all(func(n: Variant):return (n is int or n is float) and is_finite(float(n)) and n>=low and n<=high)
static func valid(value: Variant) -> bool:
	if not value is Dictionary or not Economy.integer(value.get("version"),1,1) or value.get("selection_version")!="family_weighted_v1" or not text(value.get("revision"),64) or value["revision"].length()!=64:return false
	if not value.get("themes") is Dictionary or not value.get("families") is Array or value["families"].size()>128:return false
	for key in ["native","any","pixel_city","hanx_modern","village","historical","industrial","korean_street"]:
		if not value["themes"].get(key) is Dictionary or not text(value["themes"][key].get("label"),80) or not text(value["themes"][key].get("note"),512):return false
	var seen: Dictionary={};var members: Dictionary={}
	for entry in value["families"]:
		if not entry is Dictionary or not text(entry.get("id"),512) or seen.has(entry["id"]) or not entry.get("zone") in ["residential","commercial","civic"]:return false
		seen[entry["id"]]=true
		if not Economy.integer(entry.get("weight"),1,1000) or not entry.get("density") in DENSITIES.slice(1) or not entry.get("requires_entrance") is bool or not entry["requires_entrance"]:return false
		if not pair(entry.get("footprint_limit"),.1,128) or not pair(entry.get("price_range"),0,1000000000) or entry["price_range"][0]>entry["price_range"][1]:return false
		if not entry.get("modes") is Array or entry["modes"].is_empty() or not entry["modes"].all(func(mode: Variant):return mode in ["2d","3d"]):return false
		if not entry.get("themes") is Array or entry["themes"].is_empty() or not entry["themes"].all(func(theme: Variant):return theme is String and value["themes"].has(theme) and not theme in ["native","any"]):return false
		if not entry.get("members") is Array or entry["members"].is_empty() or entry["members"].size()>512:return false
		for id in entry["members"]:
			if not Availability.id_valid(id) or members.has(id):return false
			members[id]=true
	return true
static func options(lot: Dictionary) -> Dictionary:
	return {"theme":lot.get("theme","native") if lot.get("theme","native") is String else "native","density":lot.get("density","any") if lot.get("density","any") in DENSITIES else "any","max_price":int(lot.get("max_price",0)) if Economy.integer(lot.get("max_price",0),0,1000000000) else 0}
static func valid_options(lot: Dictionary) -> bool:
	var data: Dictionary=definitions()
	return not data.is_empty() and lot.get("theme","native") is String and data["themes"].has(lot.get("theme","native")) and lot.get("density","any") in DENSITIES and Economy.integer(lot.get("max_price",0),0,1000000000)
static func theme(lot: Dictionary,mode: String) -> String:
	var selected: String=options(lot)["theme"]
	return ("pixel_city" if mode=="2d" else "hanx_modern") if selected=="native" else selected
static func selection_valid(value: Variant) -> bool:
	return value is Dictionary and value.size()==7 and Economy.integer(value.get("version"),1,1) and text(value.get("family"),512) and text(value.get("revision"),64) and value["revision"].length()==64 and text(value.get("theme"),80) and value.get("density") in DENSITIES.slice(1) and Economy.integer(value.get("price"),0,1000000000) and value.get("representation") in ["native","model_in_2d","flat_sprite_in_3d"]
static func source_ready(path: String,force: bool=true) -> bool:
	if prepared_sources.has(path):
		if not force and Time.get_ticks_usec()-int(prepared_sources[path].get("checked_at",0))<1000000:return prepared_sources[path]["ok"]
		var current: bool=true
		for dependency in prepared_sources[path]["files"]:
			var file:=FileAccess.open(dependency,FileAccess.READ)
			if not file:return false
			var stamp: Array=[FileAccess.get_modified_time(dependency),file.get_length()]
			if stamp!=prepared_sources[path]["files"][dependency]:current=false;break
		if current:prepared_sources[path]["checked_at"]=Time.get_ticks_usec();return prepared_sources[path]["ok"]
	var health=preload("res://scripts/builder/asset_health.gd").new();var issues: Array=health.dependency_errors(path,{});var files: Dictionary={};var ready: bool=issues.all(func(issue: Dictionary):return issue.get("severity","defect")!="defect")
	for dependency in health.dependencies:
		var file:=FileAccess.open(dependency,FileAccess.READ)
		if not file:ready=false;continue
		files[dependency]=[FileAccess.get_modified_time(dependency),file.get_length()]
		if not preload("res://scripts/builder/model_preview.gd").import_current(dependency):ready=false
		if dependency.get_extension().to_lower() in ["glb","gltf","png","jpg","jpeg","webp","svg","tga","bmp"] and FileAccess.file_exists(dependency+".import"):
			var config:=ConfigFile.new()
			if config.load(dependency+".import")==OK:
				var imported: Variant=config.get_value("remap","path","")
				if not imported is String or imported.is_empty():ready=false;continue
				for path_value in [dependency+".import",imported,imported.get_basename()+".md5"]:
					var imported_file:=FileAccess.open(path_value,FileAccess.READ)
					if not imported_file:ready=false;continue
					files[path_value]=[FileAccess.get_modified_time(path_value),imported_file.get_length()]
	# Failed sources are retried so installing the missing file/import can recover
	# without restarting the editor. Successful dependency graphs are cached;
	# actual files remain required even when Godot holds an in-memory resource.
	if ready:prepared_sources[path]={"ok":true,"files":files,"checked_at":Time.get_ticks_usec()}
	else:prepared_sources.erase(path)
	return ready
static func groups(lot: Dictionary,mode: String,library: RefCounted,policy: Variant=null) -> Dictionary:
	var data: Dictionary=definitions()
	if data.is_empty():return {"ok":false,"reason":error,"groups":[],"counts":{}}
	if policy!=null and (not policy is Dictionary or not policy.is_empty() and not Availability.project_valid(policy)):return {"ok":false,"reason":"Review valid common project restrictions before collecting future assets.","groups":[],"counts":{}}
	var config: Dictionary=options(lot);var selected: String=theme(lot,mode);var result: Array=[];var counts: Dictionary={"zone":0,"theme":0,"density":0,"mode":0,"available":0,"restriction":0,"prepared":0,"price":0,"entrance":0}
	var explicit_ids: Dictionary=Policy.compile(policy) if policy is Dictionary else {}
	var restricted: bool=policy.get("restricted",false) if policy is Dictionary else Policy.restricted(library)
	for family in data["families"]:
		if family["zone"]!=lot.get("kind"):continue
		counts["zone"]+=1
		if selected!="any" and not selected in family["themes"]:continue
		counts["theme"]+=1
		if config["density"]!="any" and config["density"]!=family["density"]:continue
		counts["density"]+=1
		if not mode in family["modes"]:continue
		counts["mode"]+=1;var eligible: Array=[]
		for id in family["members"]:
			if not Availability.available(id,library):continue
			counts["available"]+=1
			if restricted and not (explicit_ids.has(id) if policy is Dictionary else library.project_palette_ids.has(id)):continue
			counts["restriction"]+=1
			if not source_ready(library.assets[id]["path"],false):continue
			counts["prepared"]+=1
			var cost: int=Economy.profile(id,library)["construction"]
			if cost<family["price_range"][0] or cost>family["price_range"][1] or config["max_price"]>0 and cost>config["max_price"]:continue
			counts["price"]+=1
			if not preload("res://scripts/builder/asset_behavior.gd").for_asset(id,library).get("building",false):continue
			var directions: Array=library.directions(id);var count: int=2 if library.assets[id]["mode"]=="2d" else 3
			if not directions.any(func(direction: String):return preload("res://scripts/builder/entrance_anchors.gd").valid_point(preload("res://scripts/builder/entrance_anchors.gd").profile({"asset":id,"direction":direction},library),count)):continue
			eligible.append(id);counts["entrance"]+=1
		if not eligible.is_empty():result.append({"definition":family,"members":eligible})
	var reason: String=""
	if result.is_empty():
		if counts["theme"]==0:reason="No reviewed %s designs in the %s theme. Choose another theme or lot type."%[lot.get("kind","building"),data["themes"].get(selected,{}).get("label",selected)]
		elif counts["density"]==0:reason="No reviewed %s-density designs match this lot's theme and type."%config["density"]
		elif counts["mode"]==0:reason="The reviewed designs do not support automatic construction within this world's lot limits. Manual placement remains available."
		elif counts["available"]==0:reason="The matching building sources are unavailable. Restore their prepared packs."
		elif counts["restriction"]==0:reason="The project content restriction excludes the matching building designs. Ask the project owner to review the palette."
		elif counts["prepared"]==0:reason="The matching prepared resources have missing dependencies or need a fresh Godot import."
		elif counts["price"]==0:reason="No matching building meets this lot's price limit or the reviewed construction-price range."
		else:reason="The matching sources do not offer a reviewed building entrance."
	return {"ok":not result.is_empty(),"groups":result,"counts":counts,"reason":reason,"revision":data["revision"],"theme":selected}
static func draw(seed: int,uid: String,revision: String,salt: String,limit: int) -> int:
	return ("%d|%s|%s|%s"%[seed,uid,revision,salt]).sha256_text().substr(0,8).hex_to_int()%limit if limit>0 else -1
static func choose(groups_value: Array,seed: int,uid: String,revision: String) -> Dictionary:
	var sorted: Array=groups_value.duplicate();sorted.sort_custom(func(a: Dictionary,b: Dictionary):return a["definition"]["id"]<b["definition"]["id"])
	var total: int=0
	for group in sorted:
		if not group["members"].is_empty():total+=int(group["definition"]["weight"])
	if total==0:return {}
	var ticket: int=draw(seed,uid,revision,"family",total)
	for group in sorted:
		if group["members"].is_empty():continue
		ticket-=int(group["definition"]["weight"])
		if ticket>=0:continue
		var members: Array=group["members"].duplicate();members.sort()
		return {"family":group["definition"]["id"],"member":members[draw(seed,uid,revision,"appearance/"+group["definition"]["id"],members.size())],"definition":group["definition"]}
	return {}
