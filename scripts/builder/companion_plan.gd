extends RefCounted
const PATH="res://resources/catalog/asset_companions.json"
const Doc=preload("res://scripts/builder/document.gd")
const Grid=preload("res://scripts/builder/grid_fit.gd")
const Rotation=preload("res://scripts/builder/rotation.gd")
const Floors=preload("res://scripts/builder/floor_plan.gd")
const Layers=preload("res://scripts/builder/layers.gd")
const Props=preload("res://scripts/builder/prop_plan.gd")
static var cached: Dictionary={}
static var cached_hash: String="not loaded"
static func failure(reason: String,missing: Array=[]) -> Dictionary:return {"ok":false,"reason":reason,"missing":missing}
static func number(value: Variant,low: float,high: float) -> bool:return (value is int or value is float) and is_finite(float(value)) and float(value)>=low and float(value)<=high
static func vector(value: Variant) -> bool:return value is Array and value.size()==3 and value.all(func(n: Variant):return number(n,-64,64))
static func valid_recipe(value: Variant) -> bool:
	if not value is Dictionary or not value.get("source") is String or value["source"].length()>512:return false
	for field in ["label","source_set","note"]:
		if not value.get(field) is String or value[field].is_empty() or value[field].length()>320:return false
	if not value.get("related_overlap") is bool or not value.get("companions") is Array or value["companions"].is_empty() or value["companions"].size()>4 or not value.get("clearance") is Array or value["clearance"].size()>16:return false
	for point in value["clearance"]:
		if not vector(point):return false
	if value.has("coverage_box"):
		var coverage: Variant=value["coverage_box"]
		if not coverage is Dictionary or not coverage.get("half_span") is Array or coverage["half_span"].size()!=2 or not coverage["half_span"].all(func(n: Variant):return number(n,.01,64)) or not number(coverage.get("height"),.01,64):return false
	for item in value["companions"]:
		if not item is Dictionary or not item.get("asset") is String or item["asset"].length()>512 or item["asset"]==value["source"] or not vector(item.get("offset")) or not number(item.get("yaw"),-360,360) or not Props.valid(item.get("prop",{})):return false
	return true
static func definitions() -> Dictionary:
	var hash: String=FileAccess.get_sha256(PATH) if FileAccess.file_exists(PATH) else ""
	if hash==cached_hash:return cached
	cached_hash=hash;cached={"version":1,"relationships":{}}
	if hash.is_empty():return cached
	var file:=FileAccess.open(PATH,FileAccess.READ)
	if not file or file.get_length()>262144:return cached
	var raw: Variant=JSON.parse_string(file.get_as_text())
	if not raw is Dictionary or not number(raw.get("version"),1,1) or not raw.get("relationships") is Dictionary or raw["relationships"].size()>32:return cached
	var seen: Dictionary={}
	for key in raw["relationships"]:
		var value: Variant=raw["relationships"][key]
		if not key is String or key.length()>80 or not valid_recipe(value) or seen.has(value["source"]):continue
		cached["relationships"][key]=value;seen[value["source"]]=true
	return cached
static func for_asset(id: String) -> String:
	for key in definitions()["relationships"]:
		if definitions()["relationships"][key]["source"]==id:return key
	return ""
static func object(data: Dictionary,uid: String) -> Dictionary:
	for item in data.get("objects",[]):
		if item.get("uid")==uid:return item
	return {}
static func room(root: Dictionary,scope: Dictionary) -> Dictionary:
	if scope.get("owner","").is_empty():return root
	return Floors.room(object(root,scope["owner"]).get("interior",{}),scope.get("floor","ground"))
static func fingerprint(data: Dictionary) -> String:return JSON.stringify(data).sha256_text()
static func unique(used: Dictionary,prefix: String) -> String:
	var id: String=prefix;var serial: int=0
	while used.has(id):serial+=1;id=prefix+"_"+str(serial)
	used[id]=true;return id
static func project(point: Vector3) -> Vector2:
	var view:=Basis.from_euler(Vector3(deg_to_rad(-30),deg_to_rad(45),0)).inverse()*point
	return Vector2(view.x,-view.y)*22.627417
static func contact_offset(item: Dictionary,mode: String,library: RefCounted) -> Vector3:
	if not item["asset"].begins_with("3d:"):return Grid.anchor(item,mode,library,"center")
	# Assemblies attach to one authored source point. A tilted model's larger
	# render bounds must not replace that point with a different box center.
	var box: AABB=Grid.bounds_for(item["asset"],library,true)
	var point:=Vector3(box.get_center().x,box.position.y,box.get_center().z)
	return Basis.from_euler(Rotation.euler(item)*PI/180.0)*point*float(item["scale"])
static func centered_offset(item: Dictionary,mode: String,library: RefCounted) -> Vector2:
	var value: Vector3=contact_offset(item,mode,library)
	# ModelIn2D uses set_angles for the source model; its wrapper does not apply
	# the legacy sprite angle field. Retain that saved field without inventing
	# a second rotation that the ordinary placement factory does not render.
	if item["asset"].begins_with("3d:"):return project(value)
	return Grid.pixels(Vector2(value.x,value.z))
static func centered_3d(item: Dictionary,library: RefCounted) -> Vector3:
	var value: Vector3=contact_offset(item,"3d",library)
	# SpriteIn3D's source-point adapter includes its small card lift. Different
	# default scales must still align the actual source anchors, not their boxes.
	if item["asset"].begins_with("2d:"):value+=Grid.sprite_basis(item,library)*Vector3(0,.02,0)*float(item["scale"])
	return value
static func relative_point(source: Dictionary,raw: Array,mode: String,library: RefCounted) -> Variant:
	var original: float=float(library.assets[source["asset"]]["data"].get("default_scale",1));var ratio: float=float(source["scale"])/original
	var value:=Vector3(raw[0],raw[1],raw[2])*ratio
	if source["asset"].begins_with("3d:"):
		value=Basis.from_euler(Rotation.euler(source)*PI/180.0)*value
		return project(value) if mode=="2d" else value
	if mode=="3d":return Grid.sprite_basis(source,library)*value
	return (Grid.pixels(Vector2(value.x,value.z))+Vector2(0,-value.y*8)).rotated(deg_to_rad(float(source.get("angle",0))))
static func companion(source: Dictionary,spec: Dictionary,mode: String,library: RefCounted) -> Dictionary:
	var base: float=float(library.assets[source["asset"]]["data"].get("default_scale",1));var size: float=float(library.assets[spec["asset"]]["data"].get("default_scale",1))*float(source["scale"])/base
	var result: Dictionary={"asset":spec["asset"],"scale":size,"position":[0,0,0]}
	if spec["asset"].begins_with("3d:"):
		var rotation: Vector3=(Basis.from_euler(Rotation.euler(source)*PI/180.0)*Basis(Vector3.UP,deg_to_rad(float(spec["yaw"])))).get_euler()*180/PI
		result["direction"]=Rotation.angle_text(wrapf(rotation.y,0,360))
		if absf(rotation.x)>.00001 or absf(rotation.z)>.00001:result["tilt"]=[rotation.x,rotation.z]
		if source.has("angle") and mode=="2d":result["angle"]=source["angle"]
	else:
		result["direction"]=source["direction"]
		var angle: float=float(source.get("angle",0))+float(spec["yaw"])
		if not is_zero_approx(angle):result["angle"]=angle
		if source.has("tilt"):result["tilt"]=source["tilt"].duplicate()
	var raw: Array=source["position"];var offset: Variant=relative_point(source,spec["offset"],mode,library)
	if mode=="2d":
		var point: Vector2=Vector2(raw[0],raw[1])+centered_offset(source,mode,library)+offset-centered_offset(result,mode,library)
		result["position"]=[point.x,point.y,raw[2]]
	else:
		var point: Vector3=Vector3(raw[0],raw[1],raw[2])+centered_3d(source,library)+offset-centered_3d(result,library)
		result["position"]=[point.x,point.y,point.z]
	if spec.has("prop"):result["prop"]=spec["prop"].duplicate(true)
	preload("res://scripts/builder/catalog_defaults.gd").stamp(result)
	return result
static func nearby(data: Dictionary,item: Dictionary,mode: String,tolerance: float) -> Dictionary:
	for candidate in data["objects"]:
		if candidate["asset"]!=item["asset"]:continue
		var a: Array=item["position"];var b: Array=candidate["position"]
		var distance: float=Grid.grid(Vector2(a[0]-b[0],a[1]-b[1])).length() if mode=="2d" else Vector3(a[0]-b[0],a[1]-b[1],a[2]-b[2]).length()
		if distance<=tolerance and absf(float(candidate["scale"])-float(item["scale"]))<=float(item["scale"])*.25 and (mode!="2d" or absf(float(a[2])-float(b[2]))<.2):return candidate
	return {}
static func covered_by(data: Dictionary,item: Dictionary,source: Dictionary,coverage: Dictionary,mode: String,library: RefCounted) -> Dictionary:
	if not source["asset"].begins_with("3d:") or not item["asset"].begins_with("3d:"):return {}
	if mode=="2d" and not is_zero_approx(float(source.get("angle",0))):return {}
	var raw: Array=source["position"];var source_at: Vector3=Vector3(raw[0],raw[1],raw[2])
	if mode=="2d":
		var at: Vector2=Grid.grid(Vector2(raw[0],raw[1]));source_at=Vector3(at.x,raw[2],at.y)
	var pose:=Transform3D(Basis.from_euler(Rotation.euler(source)*PI/180.0).scaled(Vector3.ONE*float(source["scale"])),source_at)
	var box: AABB=Grid.bounds_for(source["asset"],library,false)
	for candidate in data["objects"]:
		if candidate["asset"]!=item["asset"] or (mode=="2d" and not is_zero_approx(float(candidate.get("angle",0)))):continue
		var target_raw: Array=candidate["position"];var target_at:=Vector3(target_raw[0],target_raw[1],target_raw[2])
		if mode=="2d":
			var at: Vector2=Grid.grid(Vector2(target_raw[0],target_raw[1]));target_at=Vector3(at.x,target_raw[2],at.y)
		var inverse:=Transform3D(Basis.from_euler(Rotation.euler(candidate)*PI/180.0).scaled(Vector3.ONE*float(candidate["scale"])),target_at).affine_inverse();var fits: bool=true
		for corner in 8:
			var local: Vector3=inverse*(pose*box.get_endpoint(corner))
			if absf(local.x)>float(coverage["half_span"][0]) or absf(local.z)>float(coverage["half_span"][1]) or local.y<-.1 or local.y>float(coverage["height"]):fits=false;break
		if fits:return candidate
	return {}
static func propose(root: Dictionary,scope: Dictionary,key: String,source_uid: String,draft: Dictionary,library: RefCounted) -> Dictionary:
	if root.get("mode") not in ["2d","3d"] or not scope.get("owner","") is String or not scope.get("floor","ground") is String:return failure("The selected world or floor is unavailable.")
	var recipe: Dictionary=definitions()["relationships"].get(key,{})
	if recipe.is_empty():return failure("No reviewed companion set is available for this asset.")
	var current: Dictionary=room(root,scope)
	if current.is_empty():return failure("The selected room or floor no longer exists.")
	if not Doc.valid(root,root["mode"],library):return failure("Repair the current document before placing a companion group.")
	if not scope.get("owner","").is_empty() and not Layers.editable(root,object(root,scope["owner"]),library):return failure("Show and unlock the owning building before adding companions.")
	var source: Dictionary=(object(current,source_uid) if not source_uid.is_empty() else draft).duplicate(true)
	if source.is_empty() or source.get("asset")!=recipe["source"]:return failure("Select the reviewed source asset again.")
	var ids: Array=[source["asset"]]
	for spec in recipe["companions"]:ids.append(spec["asset"])
	var missing: Array=[];var health=preload("res://scripts/builder/asset_health.gd").new()
	for id in ids:
		if not library.assets.has(id) or library.assets[id].get("unavailable",false):missing.append({"name":id,"reason":"Prepared source unavailable."});continue
		if not library.assets[id].get("data") is Dictionary or not number(library.assets[id]["data"].get("default_scale",1),.000001,64):missing.append({"name":id,"reason":"The prepared size metadata is invalid."});continue
		for issue in health.dependency_errors(library.assets[id]["path"],{}):
			if issue.get("severity","defect")=="defect":missing.append({"name":library.assets[id]["name"],"reason":issue["detail"]})
	if not missing.is_empty():return failure("This companion set has unavailable dependencies. Restore its source assets before reviewing it.",missing)
	for path in health.dependencies:
		if not preload("res://scripts/builder/model_preview.gd").import_current(path):return failure("Reimport the changed prepared source before reviewing this group.")
	var used: Dictionary={}
	for item in current["objects"]:used[item["uid"]]=true
	if source_uid.is_empty():source["uid"]=unique(used,"preview_companion_source");preload("res://scripts/builder/catalog_defaults.gd").stamp(source)
	var test: Dictionary={"mode":root["mode"],"title":"Companion source","night":false,"objects":[source],"tiles":[]}
	if not Doc.valid(test,root["mode"],library):return failure("The source's scale, angle or settings are invalid. Repair it before adding companions.")
	if not Layers.editable(current,source,library):return failure("Show and unlock the source and its destination layer before adding companions.")
	if source_uid.is_empty() and not nearby(current,source,root["mode"],.2).is_empty():return failure("A matching source is already here. Select it to add only missing companions, or move this group.")
	var data: Dictionary=root.duplicate(true);var target: Dictionary=room(data,scope);var created: Array=[];var duplicates: Array=[];var focus: Array=[source["uid"]]
	if source_uid.is_empty():target["objects"].append(source);created.append(source["uid"])
	var ratio: float=float(source["scale"])/float(library.assets[source["asset"]]["data"].get("default_scale",1))
	for spec in recipe["companions"]:
		var item: Dictionary=companion(source,spec,root["mode"],library)
		if not Layers.editable(target,item,library):return failure("Show and unlock the companion's destination layer before placing the set.")
		var present: Dictionary=nearby(current,item,root["mode"],maxf(.1,.35*ratio))
		if present.is_empty() and recipe.has("coverage_box"):present=covered_by(current,item,source,recipe["coverage_box"],root["mode"],library)
		if not present.is_empty():duplicates.append({"uid":present["uid"],"asset":present["asset"],"name":present.get("name",library.assets[present["asset"]]["name"])});focus.append(present["uid"]);continue
		item["uid"]=unique(used,"preview_companion_"+str(created.size()));target["objects"].append(item);created.append(item["uid"]);focus.append(item["uid"])
	if not Doc.valid(data,root["mode"],library):return failure("The set would exceed the document limits or the companion's permitted scale. Adjust the source before reviewing it.")
	var dependencies: Dictionary={}
	for path in health.dependencies:dependencies[path]=FileAccess.get_sha256(path)
	for path in [PATH,Props.PATH,"res://resources/catalog/asset_behaviors.json","res://resources/catalog/model_grid_bounds.json","res://resources/catalog/functional_defaults.json","res://resources/catalog/economy.json"]:dependencies[path]=FileAccess.get_sha256(path)
	var descriptors: Dictionary={}
	for id in ids:descriptors[id]=fingerprint(library.assets[id])
	return {"ok":true,"changed":not created.is_empty(),"source_hash":fingerprint(root),"data":data,"room":target,"scope":scope.duplicate(true),"recipe":key,"source_uid":source_uid,"source":source,"created":created,"duplicates":duplicates,"focus":focus,"dependencies":dependencies,"descriptors":descriptors,"quote":preload("res://scripts/builder/economy_plan.gd").quote(root,data,library),"geometry_checked":false,"issues":[]}
static func current(proposal: Dictionary,root: Dictionary,library: RefCounted) -> bool:
	if not proposal.get("ok",false) or proposal["source_hash"]!=fingerprint(root):return false
	for path in proposal["dependencies"]:
		if not FileAccess.file_exists(path) or FileAccess.get_sha256(path)!=proposal["dependencies"][path]:return false
	for id in proposal["descriptors"]:
		if not library.assets.has(id) or fingerprint(library.assets[id])!=proposal["descriptors"][id]:return false
	return true
static func materialize(proposal: Dictionary) -> Dictionary:
	var data: Dictionary=proposal["data"].duplicate(true);var selected: Dictionary=room(data,proposal["scope"]);var mapping: Dictionary={};var group: String="companion_"+Crypto.new().generate_random_bytes(16).hex_encode()
	for item in selected["objects"]:
		if item["uid"] in proposal["created"]:mapping[item["uid"]]="companion_"+Crypto.new().generate_random_bytes(16).hex_encode();item["uid"]=mapping[item["uid"]];item["group"]=group
	for item in selected["objects"]:
		if item["uid"] in mapping.values():preload("res://scripts/builder/owned_room_copy.gd").remap_target(item,mapping)
	return {"data":data,"room":selected,"ids":mapping}
