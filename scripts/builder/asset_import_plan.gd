extends RefCounted
const Custom=preload("res://scripts/builder/custom_assets.gd")
const Bounds=preload("res://scripts/model_bounds.gd")
const TYPES=["Decorations","Furniture","Buildings","Nature","Vehicles"]
const IMAGE_TYPES=["png","jpg","jpeg","webp"]
const MODEL_TYPES=["glb","gltf"]
static func defaults() -> Dictionary:
	return {"name":"My asset","category":"Decorations","author":"","license":"","source_url":"","anchor":[0.0,0.0,0.0],"footprint":[1,1],"height":1.0,"model_scale":1.0,"collision":true,"contact":[0.0,0.0]}
static func valid(config: Variant) -> bool:
	if not config is Dictionary: return false
	for key in ["name","author","license","source_url"]:
		if not config.get(key) is String or config[key].length()>2048: return false
	if config["name"].strip_edges().is_empty() or not config.get("category") in TYPES or not config.get("collision") is bool: return false
	for key in ["anchor","footprint","contact"]:
		if not config.get(key) is Array or config[key].size()!=(3 if key=="anchor" else 2): return false
		for value in config[key]:
			if not number(value) or absf(value)>100000: return false
	for value in config["footprint"]:
		if value<1 or value>64 or float(value)!=roundf(value): return false
	return number(config.get("height")) and config["height"]>=.05 and config["height"]<=256 and number(config.get("model_scale")) and config["model_scale"]>=.001 and config["model_scale"]<=1000
static func number(value: Variant) -> bool: return (value is int or value is float) and is_finite(float(value))
static func source_files(path: String,json: Dictionary={}) -> Dictionary:
	var files: Dictionary={path:FileAccess.get_sha256(path)}
	for record in json.get("buffers",[])+json.get("images",[]):
		var uri: String=record.get("uri","")
		if uri.is_empty() or uri.begins_with("data:"): continue
		var dependency: String=path.get_base_dir().path_join(uri.uri_decode()).simplify_path()
		files[dependency]=FileAccess.get_sha256(dependency)
	return files
static func fingerprint(files: Dictionary) -> String:
	# Hash file content in source order, including external glTF buffers/textures.
	return JSON.stringify(files.values()).sha256_text()
static func inspect(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {"ok":false,"reason":"Choose an existing image or glTF model."}
	var file:=FileAccess.open(path,FileAccess.READ)
	if not file: return {"ok":false,"reason":"The source file cannot be read."}
	var size: int=file.get_length(); file.close()
	if size==0 or size>128*1024*1024: return {"ok":false,"reason":"Choose a nonempty source smaller than 128 MiB."}
	var extension: String=path.get_extension().to_lower()
	var config: Dictionary=defaults(); config["name"]=path.get_file().get_basename().replace("_"," ")
	if extension in IMAGE_TYPES:
		var picture:=Image.new(); var logging: bool=Engine.print_error_messages; Engine.print_error_messages=false; var result: Error=picture.load(path); Engine.print_error_messages=logging
		if result!=OK or picture.is_empty(): return {"ok":false,"reason":"The image could not be decoded."}
		if picture.get_width()>8192 or picture.get_height()>8192: return {"ok":false,"reason":"Images may be at most 8192 pixels on each side."}
		picture.convert(Image.FORMAT_RGBA8); config["anchor"]=[picture.get_width()*.5,float(picture.get_height()),0.0]; config["contact"]=[picture.get_width()*.5,float(picture.get_height())]; config["height"]=maxf(.05,picture.get_height()/32.0)
		return {"ok":true,"mode":"2d","image":picture,"config":config,"source":path,"files":source_files(path)}
	if extension in MODEL_TYPES:
		var document:=GLTFDocument.new(); var state:=GLTFState.new(); state.handle_binary_image=GLTFState.HANDLE_BINARY_IMAGE_MODE_EMBED_AS_UNCOMPRESSED
		var logging: bool=Engine.print_error_messages; Engine.print_error_messages=false; var result: Error=document.append_from_file(path,state); Engine.print_error_messages=logging
		if result!=OK: return {"ok":false,"reason":"The glTF model could not be decoded. Check its buffers and textures."}
		var model: Node=document.generate_scene(state)
		if not model is Node3D:
			if model: model.free()
			return {"ok":false,"reason":"The model does not contain a 3D scene."}
		var bounds: AABB=Bounds.get_bounds(model)
		if bounds.size.length()<.001 or not bounds.position.is_finite() or not bounds.size.is_finite(): model.free(); return {"ok":false,"reason":"The model must contain visible mesh geometry."}
		config["anchor"]=[bounds.get_center().x,bounds.position.y,bounds.get_center().z]; config["footprint"]=[clampi(ceili(bounds.size.x),1,64),clampi(ceili(bounds.size.z),1,64)]; config["height"]=clampf(bounds.size.y,.05,256)
		var clips: Array[String] = []
		for index in mini(256, state.json.get("animations", []).size()): clips.append(str(state.json["animations"][index].get("name", "Clip " + str(index + 1))).left(128))
		var status: String = "animated_mesh" if not clips.is_empty() else "rigged_without_clips" if not state.json.get("skins", []).is_empty() else "static_mesh"
		return {"ok":true,"mode":"3d","model":model,"config":config,"source":path,"bounds":bounds,"files":source_files(path,state.json),"animation_metadata":{"animation_status":status,"supplied_clips":clips}}
	return {"ok":false,"reason":"Supported sources: PNG, JPEG, WebP, GLB and glTF."}
static func release(source: Dictionary) -> void:
	if is_instance_valid(source.get("model")): source["model"].free()
	source.clear()
static func own(node: Node,root: Node) -> void:
	for child in node.get_children(): child.owner=root; own(child,root)
static func embed(value: Variant,seen: Dictionary) -> void:
	if value is Resource:
		if seen.has(value.get_instance_id()): return
		seen[value.get_instance_id()]=true
		value.resource_path=""
		for property in value.get_property_list():
			if property["usage"] & PROPERTY_USAGE_STORAGE: embed(value.get(property["name"]),seen)
	elif value is Array:
		for child in value: embed(child,seen)
	elif value is Dictionary:
		for child in value.values(): embed(child,seen)
static func embed_node(node: Node,seen: Dictionary) -> void:
	for property in node.get_property_list():
		if property["usage"] & PROPERTY_USAGE_STORAGE: embed(node.get(property["name"]),seen)
	for child in node.get_children(): embed_node(child,seen)
static func model_scene(source: Dictionary,config: Dictionary) -> Node3D:
	var root:=Node3D.new(); root.name="CustomModel"
	var content:=Node3D.new(); content.name="Anchor"; root.add_child(content); content.scale=Vector3.ONE*config["model_scale"]; content.position=-Vector3(config["anchor"][0],config["anchor"][1],config["anchor"][2])*config["model_scale"]
	content.add_child(source["model"].duplicate()); embed_node(content,{})
	for camera in content.find_children("*","Camera3D",true,false): camera.current=false
	# Import only authored visuals; collision comes from the explicit footprint.
	for node in content.find_children("*","CollisionObject3D",true,false): node.collision_layer=0; node.collision_mask=0
	var foot: Array=config["footprint"]; root.set_meta("authored_footprint",[-foot[0]*.5,0,-foot[1]*.5,float(foot[0]),config["height"],float(foot[1])])
	if config["collision"]:
		var body:=StaticBody3D.new(); body.name="FootprintCollision"; body.collision_layer=1; body.collision_mask=0; root.add_child(body)
		var shape:=CollisionShape3D.new(); var box:=BoxShape3D.new(); box.size=Vector3(foot[0],config["height"],foot[1]); shape.shape=box; shape.position.y=config["height"]*.5; body.add_child(shape)
	own(root,root); return root
static func sprite_scene(config: Dictionary,view: Dictionary,texture_path: String) -> Node2D:
	var root:=IsoObject.new(); root.name="CustomSprite"; root.category=config["category"]; root.kind="object"; root.directions_data={"SE":view}; root.origin_offset=Vector2(config["anchor"][0],config["anchor"][1]); root.footprint=Vector2i(config["footprint"][0],config["footprint"][1]); root.has_collision=config["collision"]
	var sprite:=Sprite2D.new(); sprite.name="Sprite2D"; sprite.centered=false; sprite.texture=load(texture_path); sprite.offset=-root.origin_offset; root.add_child(sprite); sprite.owner=root
	return root
static func behavior(config: Dictionary,mode: String) -> Dictionary:
	var category: String=config["category"]; var result: Dictionary={"layer":category,"building":category=="Buildings","vehicle":category=="Vehicles","door":false,"ground":false,"collision":"box" if config["collision"] else "none","walk":{"height":config["height"]}}
	if category=="Buildings":
		var width: float=config["footprint"][0]; var depth: float=config["footprint"][1]
		result["entrance_anchor"]={"views":{"SE":{"point":[width*.5,depth],"arrival":[width*.5,depth+1]}}} if mode=="2d" else {"point":[0,0,depth*.5],"arrival":[0,0,depth*.5+1]}
	return result
static func install(source: Dictionary,config: Dictionary,thumbnail: Image) -> Dictionary:
	if not source.get("ok",false) or not valid(config) or thumbnail==null or thumbnail.is_empty(): return {"ok":false,"reason":"Load a source, check its geometry settings and generate a thumbnail first."}
	var catalog: Dictionary=Custom.read_registry()
	if not catalog["ok"]: return catalog
	for path in source.get("files",{}):
		if not FileAccess.file_exists(path) or FileAccess.get_sha256(path)!=source["files"][path]: return {"ok":false,"reason":"The source or one of its dependencies changed. Choose the source again before importing."}
	var mode: String=source["mode"]; var token: String=("prepared-v2"+fingerprint(source["files"])+JSON.stringify(config)).sha256_text().substr(0,24); var id: String=mode+":Custom/"+token
	if catalog["assets"].has(id) and Custom.descriptor_valid(id,catalog["assets"][id]) and preload("res://scripts/builder/repair_assets.gd").available(id,preload("res://scripts/builder/asset_library.gd").new(),{}):
		var existing: Dictionary = catalog["assets"][id].duplicate(true)
		var evidence: Dictionary = source.get("animation_metadata", {"animation_status":"static_sprite"})
		existing["data"].merge(evidence, true)
		if existing != catalog["assets"][id]:
			catalog["assets"][id] = existing
			if Custom.save_registry(catalog["assets"]) != OK: return {"ok":false,"reason":"Could not refresh the custom animation metadata."}
		return {"ok":true,"asset":existing,"existing":true}
	var folder: String=Custom.ROOT+"/"+token; var error: Error=DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	if error!=OK: return {"ok":false,"reason":"The project asset folder is not writable: "+error_string(error)}
	var data: Dictionary={"category":config["category"],"display_name":config["name"],"frames":1,"source_pack":"Custom imports","preview_path":folder+"/thumbnail.tres","author":config["author"],"license":config["license"],"source_url":config["source_url"],"source_name":source["source"].get_file(),"import_settings":config.duplicate(true)}
	data.merge(source.get("animation_metadata", {"animation_status":"static_sprite"}), true)
	var node: Node
	if mode=="2d":
		var texture:=ImageTexture.create_from_image(source["image"]); error=ResourceSaver.save(texture,folder+"/sprite.tres")
		var view: Dictionary={"file":"../../custom_assets/"+token+"/sprite.tres","frame_width":source["image"].get_width(),"frame_height":source["image"].get_height(),"frames":1,"origin":config["anchor"].slice(0,2),"footprint":config["footprint"].duplicate(),"grid_contact":config["contact"].duplicate()}
		data["directions"]={"SE":view}; node=sprite_scene(config,view,folder+"/sprite.tres") if error==OK else Node2D.new()
	else: node=model_scene(source,config)
	var packed:=PackedScene.new()
	if error==OK: error=packed.pack(node)
	node.free()
	if error==OK: error=ResourceSaver.save(packed,folder+"/asset.tscn")
	if error==OK: error=ResourceSaver.save(ImageTexture.create_from_image(thumbnail),data["preview_path"])
	var attribution: String="Name: %s\nAuthor: %s\nLicense: %s\nSource: %s\nOriginal filename: %s\n" % [config["name"],config["author"],config["license"],config["source_url"],data["source_name"]]
	if error==OK:
		var notice:=FileAccess.open(folder+"/LICENSE.txt",FileAccess.WRITE)
		if notice: notice.store_string(attribution); error=notice.get_error(); notice.close()
		else: error=FileAccess.get_open_error()
	if error!=OK: return {"ok":false,"reason":"The prepared asset could not be saved: "+error_string(error)}
	var asset: Dictionary={"id":id,"mode":mode,"name":config["name"].strip_edges(),"category":config["category"],"path":folder+"/asset.tscn","data":data,"behavior":behavior(config,mode)}
	catalog["assets"][id]=asset; error=Custom.save_registry(catalog["assets"])
	if error!=OK: return {"ok":false,"reason":"The custom catalog could not be saved: "+error_string(error)}
	return {"ok":true,"asset":asset,"existing":false}
