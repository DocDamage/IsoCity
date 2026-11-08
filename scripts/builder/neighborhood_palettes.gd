extends RefCounted
const PATH="res://resources/catalog/neighborhood_palettes.json"
const Candidates=preload("res://scripts/builder/zone_candidates.gd")
const Policy=preload("res://scripts/builder/asset_palette_policy.gd")
static var cached: Dictionary={}
static var error: String=""
static var source_hash: String=""
static func valid(value: Variant) -> bool:
	if not value is Dictionary or not preload("res://scripts/builder/economy_plan.gd").integer(value.get("version"),1,1) or not value.get("palettes") is Dictionary or value["palettes"].size()!=5:return false
	for key in ["hanx_modern","korean_street","village","industrial","historical"]:
		var entry: Variant=value["palettes"].get(key)
		if not entry is Dictionary or not Candidates.text(entry.get("label"),120) or not Candidates.text(entry.get("note"),1024) or not Candidates.text(entry.get("revision"),64) or entry["revision"].length()!=64:return false
		if not entry.get("ground") in ["Grass","Sidewalk","Brick_Pavers"] or not entry.get("road_style") in ["asphalt","brick"] or not preload("res://scripts/builder/economy_plan.gd").integer(entry.get("prop_density"),0,100):return false
		if not entry.get("modes") is Array or entry["modes"].is_empty() or not entry["modes"].all(func(mode: Variant):return mode in ["2d","3d"]):return false
		for field in ["families","2d","3d","parks","props"]:
			if not entry.get(field) is Array or entry[field].size()>512 or not entry[field].all(func(id: Variant):return Candidates.text(id,512)):return false
		if entry["families"].is_empty() or entry["families"].size()>128:return false
		if not entry.get("appearances") is Array or entry["appearances"].size()>32:return false
		for appearance in entry["appearances"]:
			if not appearance is Dictionary or appearance.size()!=2 or not Candidates.text(appearance.get("palette_id"),80) or not Candidates.text(appearance.get("lighting_id"),80):return false
		for field in ["2d","3d","parks","props"]:
			if not entry[field].all(func(id: Variant):return preload("res://scripts/builder/asset_collections.gd").id_valid(id)):return false
	return true
static func definitions() -> Dictionary:
	var current_hash: String=FileAccess.get_sha256(PATH)
	if not cached.is_empty() and current_hash==source_hash:return cached
	var file:=FileAccess.open(PATH,FileAccess.READ)
	if not file or file.get_length()>4*1024*1024:error="Restore the reviewed neighborhood palette catalog before generating themed districts.";return {}
	var parsed: Variant=JSON.parse_string(file.get_as_text())
	if not valid(parsed):error="The reviewed neighborhood palette catalog is unreadable.";return {}
	cached=parsed;source_hash=current_hash;error="";return cached
static func palettes() -> Dictionary:return definitions().get("palettes",{})
static func appearance_choice(palette: Dictionary,seed: int) -> Dictionary:
	return {} if palette["appearances"].is_empty() else palette["appearances"][Candidates.draw(seed,"district",palette["revision"],"shared-appearance",palette["appearances"].size())]
static func matches_appearance(id: String,appearance: Dictionary,library: RefCounted) -> bool:
	return appearance.is_empty() or library.assets[id]["data"].get("palette_id")==appearance["palette_id"] and library.assets[id]["data"].get("lighting_id")==appearance["lighting_id"]
static func inventory(theme: String,mode: String,library: RefCounted,appearance: Dictionary={}) -> Dictionary:
	var palette: Dictionary=palettes().get(theme,{})
	if palette.is_empty():return {"ok":false,"reason":error if not error.is_empty() else "Choose a reviewed neighborhood theme."}
	if definitions().get("zoning_revision")!=Candidates.definitions().get("revision"):return {"ok":false,"reason":"The reviewed building catalog changed. Refresh the neighborhood palettes before generating a new district; existing districts are retained."}
	if not mode in palette["modes"]:return {"ok":false,"reason":palette["note"]}
	var groups: Array=[];var reasons: Array=[]
	for zone in ["residential","commercial","civic"]:
		var found: Dictionary=Candidates.groups({"kind":zone,"theme":theme},mode,library)
		if not found["ok"]:reasons.append(found["reason"])
		for group in found["groups"]:
			if group["definition"]["id"] in palette["families"]:
				var members: Array=group["members"].filter(func(id: String):return id in palette[mode] and matches_appearance(id,appearance,library))
				if not members.is_empty():groups.append({"definition":group["definition"],"members":members})
	return {"ok":not groups.is_empty(),"groups":groups,"revision":palette["revision"],"theme":theme,"counts":{},"reason":"No installed, permitted building family matches this district. "+" ".join(reasons) if groups.is_empty() else ""}
static func usable(id: String,library: RefCounted,force: bool=false) -> bool:
	return preload("res://scripts/builder/asset_collections.gd").available(id,library) and Policy.allowed(id,library) and Candidates.source_ready(library.assets[id]["path"],force)
static func valid_selection(value: Variant) -> bool:
	if not value is Dictionary or value.size()!=6 or not preload("res://scripts/builder/economy_plan.gd").integer(value.get("version"),1,1):return false
	return Candidates.text(value.get("theme"),80) and Candidates.text(value.get("revision"),64) and value["revision"].length()==64 and Candidates.text(value.get("family"),512) and preload("res://scripts/builder/asset_collections.gd").id_valid(value.get("member")) and value.get("role") in ["building","park","prop"]
static func dependency_snapshot(before: Dictionary,after: Dictionary,library: RefCounted) -> Dictionary:
	var records=preload("res://scripts/builder/asset_collections.gd");var old: Dictionary=records.records(before);var next: Dictionary=records.records(after);var ids: Dictionary={};var health=preload("res://scripts/builder/asset_health.gd").new()
	for key in next:
		if old.get(key)!=next[key]:ids[next[key]]=true
	for id in ids:
		if not usable(id,library,true):return {"ok":false,"reason":"A proposed asset is missing, changed, unimported or excluded by the project palette. Restore it and preview again."}
		var issues: Array=health.dependency_errors(library.assets[id]["path"],{})
		if issues.any(func(issue: Dictionary):return issue.get("severity","defect")=="defect"):return {"ok":false,"reason":"Restore the proposed district's prepared asset dependencies before adding it."}
	var paths: Array=health.dependencies.keys();paths.append_array([PATH,"res://resources/catalog/neighborhoods.json",Candidates.PATH,"res://resources/catalog/economy.json","res://resources/catalog/asset_metadata.json","res://resources/catalog/asset_behaviors.json"]);var files: Dictionary={}
	for path in paths:
		if not FileAccess.file_exists(path):return {"ok":false,"reason":"Restore the district's reviewed catalog and source dependencies before adding it."}
		files[path]=FileAccess.get_sha256(path)
	return {"ok":true,"files":files}
