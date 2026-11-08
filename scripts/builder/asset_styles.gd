extends RefCounted
const RULES="res://resources/catalog/asset_style_rules.json"
const MODELS="res://resources/catalog/asset_style_models.json"
const MATERIALS=["albedo_texture","custom_shader","default_material","lit_pbr","metallic","nearest_texture","rough_surface","smooth_surface","solid_color","transparent","unlit","vertex_color","baked_raster"]
const PROJECTIONS=["isometric","top_down","frontal","unknown"]
const THEME_LABELS={"hanx_modern":"HanX modern","pixel_city":"Pixel City","village":"Village","industrial":"Industrial","space":"Space","historical":"Historical"}
const MATERIAL_LABELS={"albedo_texture":"textured surfaces","lit_pbr":"lit mesh materials","metallic":"metallic finish","rough_surface":"rough finish","smooth_surface":"smooth finish","solid_color":"solid colors","transparent":"transparency/cutouts","unlit":"unlit surfaces","vertex_color":"vertex colors","nearest_texture":"nearest-filtered textures","baked_raster":"baked sprite artwork","default_material":"default mesh material"}
var index: Dictionary={}
var evidence: Dictionary={}
var rules: Dictionary={}
var hashes: Dictionary={}
var revision: int=0

static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):return {}
	var value: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary and value.get("version")==1 else {}

static func span_valid(value: Variant) -> bool:
	if not value is Array or value.size()!=2:return false
	for number in value:
		if not (number is int or number is float) or not is_finite(float(number)) or number<=0 or number>100000:return false
	return true

static func material_values(value: Variant) -> Array[String]:
	var result: Array[String]=[]
	if value is Array:
		for tag in MATERIALS:
			if value.has(tag):result.append(tag)
	return result

static func import_parameters(path: String) -> String:
	var config:=ConfigFile.new()
	if not FileAccess.file_exists(path+".import") or config.load(path+".import")!=OK:return ""
	var params: Dictionary={}
	if config.has_section("params"):
		for key in config.get_section_keys("params"):params[key]=config.get_value("params",key)
	return JSON.stringify(params,"",true).sha256_text()

func sources_valid(entry: Dictionary) -> bool:
	var sources: Variant=entry.get("sources")
	if not sources is Dictionary or sources.is_empty():return false
	for path in sources:
		var stamp: Variant=sources[path]
		if not path is String or not stamp is Dictionary or not stamp.get("sha256") is String or stamp["sha256"].length()!=64 or not FileAccess.file_exists(path):return false
		for letter in stamp["sha256"]:
			if letter not in "0123456789abcdef":return false
		var file:=FileAccess.open(path,FileAccess.READ)
		if not file:return false
		if file.get_length()!=stamp.get("size"):return false
		if not hashes.has(path):hashes[path]=FileAccess.get_sha256(path)
		if hashes[path]!=stamp["sha256"]:return false
		if stamp.has("import_parameters") and import_parameters(path)!=stamp["import_parameters"]:return false
	return true

func build(library: RefCounted) -> void:
	index.clear();evidence.clear();hashes.clear()
	var supplied: Variant=read(RULES).get("packs",{})
	rules=supplied if supplied is Dictionary else {}
	var models: Variant=read(MODELS).get("assets",{})
	if not models is Dictionary:models={}
	for id in library.assets:
		var asset: Dictionary=library.assets[id];var data: Dictionary=asset.get("data",{})
		var pack: String=library.pack_name(asset)
		var rule: Variant={} if id.contains(":Custom/") else rules.get(pack,{})
		if not rule is Dictionary:rule={}
		var info: Dictionary={"id":id,"themes":library.themes.tags(asset).duplicate(),"palette":"","projection":"mesh" if asset["mode"]=="3d" else "unknown","materials":[],"span":[],"layer":asset.get("behavior",{}).get("layer","Decorations"),"note":"Partial style metadata; appearance still needs checking.","kind":asset["mode"],"default_scale":data.get("default_scale",1.0)}
		if not (info["default_scale"] is int or info["default_scale"] is float) or not is_finite(float(info["default_scale"])) or info["default_scale"]<=0:info["default_scale"]=1.0
		if data.get("appearance_group") is String and data.get("palette_id") is String and not data["appearance_group"].is_empty() and not data["palette_id"].is_empty():info["palette"]=data["appearance_group"]+"/"+data["palette_id"]
		if asset["mode"]=="2d":
			if rule.get("projection") in PROJECTIONS:info["projection"]=rule["projection"]
			info["materials"]=["baked_raster"]
			var views: Variant=data.get("directions",{})
			if views is Dictionary and not views.is_empty() and preload("res://scripts/builder/asset_content.gd").kind(asset)=="object":
				var view: Variant=views.get("SE",views.values()[0])
				if view is Dictionary and span_valid(view.get("footprint")):info["span"]=view["footprint"].duplicate()
		else:
			var entry: Variant=models.get(id,{})
			if entry is Dictionary and entry.get("scene")==asset.get("path") and entry.get("verified") is bool and entry["verified"] and sources_valid(entry):
				info["materials"]=material_values(entry.get("materials"));info["span"]=entry["span"].duplicate() if span_valid(entry.get("span")) else []
				info["note"]=entry.get("note","");evidence[id]=entry
		# Custom metadata is explicit and optional. Unknown fields never become
		# source-name guesses or a reason to hide an import.
		if id.contains(":Custom/") and data.get("style_profile") is Dictionary:
			var custom: Dictionary=data["style_profile"]
			if asset["mode"]=="2d" and custom.get("projection") in PROJECTIONS:info["projection"]=custom["projection"]
			if custom.get("palette_family") is String and custom["palette_family"].length()<=120:info["palette"]=custom["palette_family"]
			if not material_values(custom.get("materials")).is_empty():info["materials"]=material_values(custom["materials"])
			if span_valid(custom.get("span")):info["span"]=custom["span"].duplicate()
			info["note"]="Custom-provided style metadata; partial evidence is allowed."
		index[id]=info
	revision+=1

func profile(id: String) -> Dictionary:return index.get(id,{}).duplicate(true)

static func presentation(info: Dictionary,mode: String) -> String:
	if info.get("kind") not in ["2d","3d"]:return "unknown"
	if info.get("kind")=="3d":return "isometric" if mode=="2d" else "volume_mesh"
	if mode=="3d":return "flat_card"
	return info.get("projection","unknown")

static func presentation_label(value: String) -> String:
	return {"volume_mesh":"3D meshes","flat_card":"flat sprite cards","isometric":"isometric presentation","top_down":"top-down artwork","frontal":"front-facing artwork"}.get(value,"unknown projection")

static func compare(candidate: Dictionary,context: Dictionary,mode: String) -> Dictionary:
	var reasons: PackedStringArray=[];var cautions: PackedStringArray=[];var score: int=0;var strong: bool=false
	if candidate.is_empty() or context.is_empty() or candidate.get("id")==context.get("id") and not str(context.get("id","")).is_empty():return {"score":0,"suggested":false,"reasons":reasons,"cautions":cautions}
	var shared: Array=[]
	for theme in candidate.get("themes",[]):
		if theme in context.get("themes",[]):shared.append(theme)
	if not shared.is_empty():score+=60+mini(2,shared.size()-1)*3;strong=true;reasons.append("Shared theme: "+", ".join(shared.map(func(key: String):return THEME_LABELS.get(key,key))))
	if not str(candidate.get("palette","")).is_empty() and candidate.get("palette")==context.get("palette"):score+=30;strong=true;reasons.append("Same authored palette family: "+candidate["palette"])
	elif not str(context.get("palette","")).is_empty():cautions.append("Palette family differs or is unknown.")
	var projection: String=presentation(candidate,mode);var other: String=presentation(context,mode)
	if projection==other and projection!="unknown":score+=15;reasons.append("Matching presentation: "+presentation_label(projection))
	elif projection!="unknown" and other!="unknown":score-=8;cautions.append("Presentation differs: "+presentation_label(projection)+".")
	else:cautions.append("Source projection is only partially known.")
	var materials: Array=[]
	for tag in candidate.get("materials",[]):
		if tag in context.get("materials",[]) and tag!="custom_shader":materials.append(tag)
	if not materials.is_empty():score+=mini(12,materials.size()*4);reasons.append("Material conventions: "+", ".join(materials.map(func(key: String):return MATERIAL_LABELS.get(key,key))))
	else:cautions.append("Material conventions differ or are unknown.")
	if span_valid(candidate.get("span")) and span_valid(context.get("span")):
		var a: float=maxf(candidate["span"][0],candidate["span"][1])*float(candidate.get("default_scale",1))
		var b: float=maxf(context["span"][0],context["span"][1])*float(context.get("scale",context.get("default_scale",1)))
		if candidate.get("layer")==context.get("layer"):
			var ratio: float=maxf(a,b)/maxf(.00001,minf(a,b))
			if ratio<=2:score+=12;reasons.append("Similar prepared ground span in this object layer.")
			elif ratio<=4:score+=5;reasons.append("Comparable prepared ground span; compare placement size.")
			else:score-=8;cautions.append("Ground spans differ substantially; compare placement size.")
		else:score+=2;reasons.append("Both have declared ground size; different object roles need a scale check.")
	else:cautions.append("Size evidence is partial; compare placement size.")
	if mode=="3d" and candidate.get("kind")=="2d":cautions.append("This remains a flat sprite card in 3D.")
	return {"score":score,"suggested":strong and score>=60,"reasons":reasons,"cautions":cautions}

func subset(ids: Dictionary) -> Dictionary:
	var result: Dictionary={}
	for id in ids:
		if evidence.has(id):result[id]=evidence[id]
	return {"version":1,"assets":result}
