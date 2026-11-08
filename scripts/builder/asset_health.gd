extends RefCounted
const Preview=preload("res://scripts/builder/model_preview.gd")
const Content=preload("res://scripts/builder/asset_content.gd")
const View=preload("res://scripts/sprite_view.gd")
const STATUSES=["static_sprite","directional_sprite","animated_sprite","static_mesh","posed_mesh","rigged_without_clips","animated_mesh"]
var library: RefCounted
var ids: Array=[]
var issues: Dictionary={}
var images: Dictionary={}
var dependencies: Dictionary={}
var checked: Dictionary={}
var cursor: int=0
var revision: int=0
var active: bool=false
var status: String="not_scanned"
var missing_marker: String=""
var elapsed_usec: int=0

static func number(value: Variant,minimum: float,maximum: float,integral: bool=false) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value>=minimum and value<=maximum and (not integral or value==roundf(value))

static func vector(value: Variant,count: int,minimum: float,maximum: float,integral: bool=false) -> bool:
	if not value is Array or value.size()!=count:return false
	for component in value:
		if not number(component,minimum,maximum,integral):return false
	return true

static func preview_path(asset: Dictionary) -> String:
	var data: Variant=asset.get("data",{})
	if not data is Dictionary:return ""
	var supplied: Variant=data.get("preview_path","")
	if supplied is String and not supplied.is_empty():return supplied
	return "res://resources/previews_3d/"+str(asset.get("id","")).trim_prefix("3d:")+".png" if asset.get("mode")=="3d" and not data.has("preview_path") else ""

func begin(host: RefCounted) -> void:
	library=host;ids=library.assets.keys().filter(func(id: String):return id not in ["2d:__missing_object__","2d:__missing_tile__","3d:__missing_object__"]);ids.sort();issues.clear();images.clear();dependencies.clear();checked.clear();cursor=0;elapsed_usec=0
	revision=library.families.revision;status="scanning";active=true
	missing_marker=FileAccess.get_sha256("res://assets/editor/missing_object.png")

func cancel() -> void:
	if active:active=false;status="cancelled"

func add(id: String,code: String,severity: String,title: String,path: String,detail: String,repair: String="") -> void:
	var key: String=code+"|"+severity+"|"+path
	if not issues.has(key):issues[key]={"code":code,"severity":severity,"title":title,"path":path,"affected_ids":[],"details":{},"repair":repair}
	var issue: Dictionary=issues[key]
	if id not in issue["affected_ids"]:issue["affected_ids"].append(id)
	if not issue["details"].has(id):issue["details"][id]=[]
	if detail not in issue["details"][id] and issue["details"][id].size()<16:issue["details"][id].append(detail)

func image_info(path: String,model: bool=false) -> Dictionary:
	if images.has(path) and (not model or images[path].has("meaningful")):return images[path]
	var image: Image=Preview.read_image(path)
	var result: Dictionary={"exists":FileAccess.file_exists(path),"valid":image!=null,"size":Vector2i.ZERO}
	if image:
		result["size"]=image.get_size()
		if model:result["meaningful"]=Preview.meaningful_image(image) and FileAccess.get_sha256(path)!=missing_marker
	images[path]=result;return result

func dependency_node(path: String) -> Dictionary:
	if dependencies.has(path):return dependencies[path]
	var result: Array=[];var children: Array=[]
	if path.is_empty() or not FileAccess.file_exists(path):result.append({"code":"missing_dependency","path":path,"detail":"A prepared resource dependency is missing. A previously loaded instance may remain visible, but a fresh independent import needs this file."})
	elif path.get_extension().to_lower() in ["tscn","tres"]:
		var pattern:=RegEx.new();pattern.compile('\\[ext_resource[^\\n]*path="([^"]+)"')
		for match_value in pattern.search_all(FileAccess.get_file_as_string(path)):children.append(match_value.get_string(1))
	elif path.get_extension().to_lower() in ["gltf","glb"]:
		var text: String="";var parse_source: bool=true
		if path.get_extension().to_lower()=="gltf":text=FileAccess.get_file_as_string(path)
		else:
			var file:=FileAccess.open(path,FileAccess.READ)
			if not file or file.get_length()<20 or file.get_32()!=0x46546c67 or file.get_32()!=2:
				result.append({"code":"invalid_model_source","path":path,"detail":"Prepared GLB header is invalid."});parse_source=false
			else:
				var declared: int=file.get_32();var length: int=file.get_32();var kind: int=file.get_32()
				if declared>file.get_length() or length>file.get_length()-20 or kind!=0x4e4f534a:result.append({"code":"invalid_model_source","path":path,"detail":"Prepared GLB JSON chunk is invalid."});parse_source=false
				elif length>8*1024*1024:result.append({"code":"source_review_limit","path":path,"detail":"Large model JSON exceeds the bounded dependency-review limit; inspect this source separately.","severity":"review"});parse_source=false
				else:text=file.get_buffer(length).get_string_from_utf8()
		if parse_source:
			var json:=JSON.new()
			if json.parse(text)!=OK or not json.data is Dictionary:result.append({"code":"invalid_model_source","path":path,"detail":"Prepared model JSON cannot be read."})
			else:
				for field in ["buffers","images"]:
					var entries: Variant=json.data.get(field,[])
					if not entries is Array:result.append({"code":"invalid_model_source","path":path,"detail":"Prepared model "+field+" must be an array."});continue
					for entry in entries:
						if not entry is Dictionary or not entry.get("uri","") is String:result.append({"code":"invalid_model_source","path":path,"detail":"Prepared model has an invalid external resource descriptor."});continue
						var uri: String=entry.get("uri","")
						if uri.is_empty() or uri.begins_with("data:"):continue
						if "://" in uri:result.append({"code":"missing_dependency","path":uri,"detail":"A model depends on an external URI; a portable source dependency is required."})
						else:children.append(path.get_base_dir().path_join(uri.uri_decode()).simplify_path())
	dependencies[path]={"errors":result,"children":children};return dependencies[path]

func dependency_errors(path: String,visited: Dictionary) -> Array:
	if visited.has(path):
		return [{"code":"dependency_cycle","path":path,"severity":"review","detail":"External resource cycle found; inspect the prepared references before automatic repair."}] if visited[path]=="active" else []
	visited[path]="active"
	var node: Dictionary=dependency_node(path);var result: Array=node["errors"].duplicate(true)
	for child in node["children"]:result.append_array(dependency_errors(child,visited))
	visited[path]="done";return result

func check_view(id: String,view: Variant,defaults: Dictionary,label: String) -> void:
	if not view is Dictionary:add(id,"invalid_view","defect","Invalid direction/frame definition",id,label+": view must be an object.");return
	if not view.get("file") is String or view["file"].is_empty():add(id,"invalid_view","defect","Invalid direction/frame definition",id,label+": source image path is absent or invalid.");return
	var path: String=View.path(view);var info: Dictionary=image_info(path)
	if not info["valid"]:
		add(id,"missing_dependency" if not info["exists"] else "unreadable_image","defect","Missing or unreadable sprite source",path,label+": supplied frame image cannot be read.");return
	var area: Rect2=Rect2(Vector2.ZERO,Vector2(info["size"]))
	if view.has("region"):
		if not vector(view["region"],4,0,1000000,true) or view["region"][2]<=0 or view["region"][3]<=0:add(id,"invalid_region","defect","Invalid atlas region",path,label+": region must have finite nonnegative integer coordinates and positive size.");return
		area=Rect2(view["region"][0],view["region"][1],view["region"][2],view["region"][3])
		if not Rect2(Vector2.ZERO,Vector2(info["size"])).encloses(area):add(id,"invalid_region","defect","Atlas region exceeds source image",path,label+": declared region "+str(area)+" exceeds "+str(info["size"])+".")
	var width: Variant=view.get("frame_width",area.size.x);var height: Variant=view.get("frame_height",area.size.y)
	var frames: Variant=view.get("frames",defaults.get("frames",1));var fps: Variant=view.get("fps",defaults.get("fps",8))
	if not number(width,1,1000000,true) or not number(height,1,1000000,true) or not number(frames,1,65536,true):add(id,"invalid_frames","defect","Invalid frame dimensions/count",path,label+": frame dimensions and count must be finite positive integers.");return
	if width*frames>area.size.x or height>area.size.y:add(id,"invalid_frames","defect","Frame strip exceeds source region",path,label+": %s × %s frames of %s px do not fit region %s."%[width,frames,height,area.size])
	if not number(fps,0,1000) or frames>1 and fps<=0:add(id,"invalid_frames","defect","Invalid animation frame rate",path,label+": animated strips need a finite positive frame rate.")
	for field in ["origin","grid_contact"]:
		if view.has(field) and not vector(view[field],2,-1000000,1000000):add(id,"invalid_anchor","defect","Invalid sprite anchor",path,label+": "+field+" must contain two finite coordinates.")
	if view.has("footprint") and not vector(view["footprint"],2,.00001,1000000):add(id,"invalid_footprint","defect","Invalid sprite footprint",path,label+": footprint must contain two finite positive dimensions.")

func check_directions(id: String,views: Variant,defaults: Dictionary,label: String) -> void:
	if not views is Dictionary or views.is_empty():add(id,"invalid_directions","defect","Missing direction definitions",id,label+": no usable direction definitions supplied.");return
	for direction in views:
		if not direction is String or direction.is_empty() or direction.length()>64:add(id,"invalid_directions","defect","Invalid direction key",id,label+": direction names must be nonempty bounded strings.");continue
		check_view(id,views[direction],defaults,label+" / "+direction)

func inspect(id: String) -> void:
	checked[id]=true
	if not library.assets.has(id):add(id,"removed_during_scan","review","Asset removed during audit",id,"Rescan the changed catalog.");return
	var asset: Dictionary=library.assets[id]
	if id in ["2d:__missing_object__","2d:__missing_tile__","3d:__missing_object__"]:return
	var data: Variant=asset.get("data",{})
	if not data is Dictionary:add(id,"invalid_metadata","defect","Invalid asset metadata",id,"Metadata must be an object.");return
	var scene: Variant=asset.get("path","")
	var errors: Array=dependency_errors(scene,{}) if scene is String else [{"code":"invalid_metadata","path":id,"detail":"Prepared scene path must be a string."}]
	for error in errors:add(id,error["code"],error.get("severity","defect"),"Prepared source dependency",error["path"],error["detail"])
	if data.has("preview_path") and (not data["preview_path"] is String or data["preview_path"].is_empty()):add(id,"invalid_preview_path","defect","Invalid preview path",id,"Supplied preview path is empty or not a string.")
	var preview: String=preview_path(asset)
	if asset.get("mode")=="3d" or not preview.is_empty():
		var info: Dictionary=image_info(preview,asset.get("mode")=="3d")
		var repair: String="model_preview" if asset.get("mode")=="3d" else ""
		if not info["exists"]:add(id,"preview_missing","defect","Missing asset preview",preview,"Prepared art may still be usable; its browser thumbnail is missing.",repair)
		elif not info["valid"]:add(id,"preview_corrupt","defect","Unreadable asset preview",preview,"The supplied preview image cannot be decoded.",repair)
		elif asset.get("mode")=="3d" and not info["meaningful"]:add(id,"preview_placeholder","defect","Placeholder model preview",preview,"Uniform/empty model preview or explicit missing-art marker. Flat sprite tiles are exempt.",repair)
	if asset.get("mode")=="2d":
		check_directions(id,data.get("directions"),data,"Default art")
		var animations: Variant=data.get("animations",{})
		if not animations is Dictionary:add(id,"invalid_animation","defect","Invalid animation descriptors",id,"Animations must be an object.")
		else:
			for clip in animations:
				var definition: Variant=animations[clip]
				if not definition is Dictionary:add(id,"invalid_animation","defect","Invalid animation descriptors",id,str(clip)+": animation must be an object.");continue
				var defaults: Dictionary=data.duplicate();defaults.merge(definition,true);check_directions(id,definition.get("directions"),defaults,str(clip))
		var actions: Variant=data.get("runtime_actions",{})
		if not actions is Dictionary:add(id,"invalid_actions","defect","Invalid action descriptors",id,"Runtime action metadata must be an object.")
		elif animations is Dictionary:
			for action in actions:
				var entry: Variant=actions[action]
				if not entry is Dictionary:add(id,"invalid_actions","defect","Invalid action descriptors",id,str(action)+": action must be an object.");continue
				if entry.has("clip") and (not entry["clip"] is String or not animations.has(entry["clip"])):add(id,"missing_action_clip","defect","Unavailable action artwork",id,str(action)+": configured source clip is absent.")
				if entry.has("first_frame"):
					if not number(entry["first_frame"],0,65535,true) or not number(entry.get("frame_count"),1,65536,true) or not number(data.get("frames",1),1,65536,true) or entry["first_frame"]+entry["frame_count"]>data.get("frames",1):add(id,"invalid_action_frames","defect","Action exceeds supplied frames",id,str(action)+": action frame range exceeds the supplied strip.")
	if Content.kind(asset) in ["atlas","reference","background","showcase"]:
		var path: String=preview
		var directions: Variant=data.get("directions",{})
		if directions is Dictionary and not directions.is_empty() and directions.values()[0] is Dictionary and directions.values()[0].get("file") is String:path=View.path(directions.values()[0])
		add(id,"reference_content","review","Atlas, reference or scenery content",path,"Explicit content kind: "+Content.kind(asset)+". This is a review note, not evidence of broken art.")
	var group: String="Custom imports" if id.contains(":Custom/") else library.pack_name(asset)
	if not data.get("animation_status","") in STATUSES:add(id,"unresolved_metadata","review","Partial descriptive metadata",group,"Animation/source description is partial; this does not grant or remove behavior.")
	if library.themes.tags(asset).is_empty():add(id,"unclassified_theme","review","Unclassified theme metadata",group,"No reviewed theme assigned. Intentional mixed-style placement remains allowed.")
	var sources: Variant=data.get("source_files",[])
	if sources is Array and errors.is_empty():
		for source in sources:
			if source is String and not source.is_empty() and not FileAccess.file_exists(source):add(id,"optional_source_unavailable","review","Original source unavailable",source,"Prepared dependencies remain present. The optional original/intake source is unavailable; prepared placement is not disabled.")
	elif not sources is Array:add(id,"unresolved_source_metadata","review","Partial original-source metadata",group,"Original-source descriptors are not an array. Prepared source checks remain separate.")

func step(max_assets: int=4,budget_usec: int=4000) -> void:
	if not active:return
	if max_assets<=0 or budget_usec<=0:return
	if library.families.revision!=revision:active=false;status="stale";return
	var started: int=Time.get_ticks_usec();var processed: int=0
	while cursor<ids.size() and processed<max_assets:
		inspect(ids[cursor]);cursor+=1;processed+=1
		if Time.get_ticks_usec()-started>=budget_usec:break
	elapsed_usec+=Time.get_ticks_usec()-started
	if cursor>=ids.size():active=false;status="complete"

func report() -> Dictionary:
	var entries: Array=issues.values().duplicate(true)
	for entry in entries:entry["affected_ids"].sort()
	entries.sort_custom(func(a: Dictionary,b: Dictionary):
		if a["severity"]!=b["severity"]:return a["severity"]=="defect"
		return (a["code"]+"|"+a["path"])<(b["code"]+"|"+b["path"]))
	return {"version":1,"status":status,"assets_total":maxi(ids.size(),checked.size()),"assets_scanned":checked.size(),"catalog_revision":revision,"scan_work_ms":elapsed_usec/1000.0,"issues":entries,"note":"Snapshot audit. Rescan after external source edits. Review notes do not imply broken art or functional behavior."}
