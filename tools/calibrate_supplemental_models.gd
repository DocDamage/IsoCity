extends SceneTree
const Bounds=preload("res://scripts/model_bounds.gd")
const Store=preload("res://scripts/builder/project_store.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var path: String="res://resources/catalog/supplemental_registry.json"; var registry: Dictionary=Store.read_json(path,{})
	var cache: Dictionary={"version":1,"bounds_by_sha256":{}}; var count: int=0
	for id in registry["models"]:
		var descriptor: Dictionary=registry["models"][id]; var data: Dictionary=descriptor["data"]
		var model_path: String=data["preview_path"].get_base_dir().path_join(descriptor["path"].get_file().get_basename()+".glb")
		var visual: Node3D=load(model_path).instantiate(); var source: AABB=visual.transform*Bounds.get_bounds(visual)
		if source.size.length()<.001: visual.free(); push_error("No imported geometry: "+id); quit(1); return
		var old_low:=Vector3(data["source_bounds"][0][0],data["source_bounds"][0][1],data["source_bounds"][0][2]); var old_high:=Vector3(data["source_bounds"][1][0],data["source_bounds"][1][1],data["source_bounds"][1][2]); var old_size: Vector3=old_high-old_low
		var category: String=descriptor["category"]; var tree: bool=category=="Supplemental Nature"; var furniture: bool=category=="Supplemental Furniture"
		var target: float=old_size.y*float(data["prepared_scale"]) if tree or furniture else maxf(old_size.x,maxf(old_size.y,old_size.z))*float(data["prepared_scale"])
		target=float(data.get("target_size",snappedf(target,.001)))
		var scale_value: float=target/source.size.y if tree or furniture else target/maxf(source.size.x,maxf(source.size.y,source.size.z))
		var size: Vector3=source.size*scale_value; var offset:=Vector3(-source.get_center().x,-source.position.y,-source.get_center().z)*scale_value
		var root_node:=StaticBody3D.new(); root_node.name=id.get_file().validate_node_name(); root_node.collision_layer=1 if tree or furniture else 0; root_node.collision_mask=0
		var model:=Node3D.new(); model.name="Model"; model.position=offset; model.scale=Vector3.ONE*scale_value; root_node.add_child(model); model.owner=root_node
		visual.name="Source"; model.add_child(visual); visual.owner=root_node
		var collision:=CollisionShape3D.new(); collision.name="CollisionShape3D"; collision.disabled=not (tree or furniture)
		if tree:
			var shape:=CylinderShape3D.new(); shape.radius=.25; shape.height=2; collision.shape=shape; collision.position.y=1
		else:
			var shape:=BoxShape3D.new(); shape.size=size.max(Vector3.ONE*.01); collision.shape=shape; collision.position.y=size.y*.5
		root_node.add_child(collision); collision.owner=root_node
		var footprint: Vector3=Vector3(.7,size.y,.7) if tree else size
		root_node.set_meta("authored_footprint",[-footprint.x*.5,0.0,-footprint.z*.5,footprint.x,footprint.y,footprint.z])
		var packed:=PackedScene.new(); var error: Error=packed.pack(root_node)
		if error==OK: error=ResourceSaver.save(packed,descriptor["path"])
		root_node.free()
		if error!=OK: push_error("Could not save calibrated prefab: "+id); quit(1); return
		var low: Vector3=source.position; var high: Vector3=source.end
		data["source_bounds"]=[[low.x,low.y,low.z],[high.x,high.y,high.z]]; data["prepared_scale"]=scale_value; data["model_file"]=model_path; data["engine_calibrated"]=true
		data["target_size"]=target; data["target_dimension"]="height" if tree or furniture else "span"
		cache["bounds_by_sha256"][FileAccess.get_sha256(model_path)]={"min":[low.x,low.y,low.z],"max":[high.x,high.y,high.z]}
		count+=1; await process_frame
	if not Store.write_json(path,registry) or not Store.write_json("res://resources/catalog/supplemental_model_bounds.json",cache): push_error("Model calibration metadata could not be saved"); quit(1); return
	Store.write_json("res://output/supplemental_assets/prepared_manifest.json",registry)
	print("Calibrated %d supplemental model pivots and collision shapes against imported geometry" % count); quit()
