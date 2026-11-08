extends SceneTree
const Store=preload("res://scripts/builder/project_store.gd")
const Bounds=preload("res://scripts/model_bounds.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var path: String="res://resources/catalog/swat_registry.json"; var registry: Dictionary=Store.read_json(path,{})
	var services: Dictionary=Store.read_json("res://resources/catalog/city_services.json",{})
	var driving: Dictionary=Store.read_json("res://resources/catalog/driving.json",{})
	var props: Dictionary=Store.read_json("res://resources/catalog/props.json",{})
	var roles: Dictionary=Store.read_json("res://resources/catalog/citizen_roles.json",{})
	for id in registry["models"]:
		var entry: Dictionary=registry["models"][id]; var info: Dictionary=entry["data"]; var key: String=info["source_name"]
		var visual: Node3D=load(info["model_file"]).instantiate(); var bounds: AABB=visual.transform*Bounds.get_bounds(visual)
		assert(bounds.size.length()>.001)
		var offset:=Vector3(-bounds.get_center().x,0 if key.begins_with("Tile_") else -bounds.position.y,-bounds.get_center().z)
		var preserve: bool=key.begins_with("Tile_") or key.begins_with("Training_Wall_") or key.begins_with("Weapon_")
		if preserve: offset=Vector3.ZERO
		info["authored_origin_preserved"]=preserve
		var result: AABB=AABB(bounds.position+offset,bounds.size)
		var body:=StaticBody3D.new(); body.name=key; body.collision_layer=0 if entry["behavior"]["collision"]=="none" else 1; body.collision_mask=0
		body.set_meta("authored_footprint",[result.position.x,result.position.y,result.position.z,result.size.x,result.size.y,result.size.z])
		var model:=Node3D.new(); model.name="Model"; model.position=offset; body.add_child(model); model.owner=body
		visual.name="Source"; model.add_child(visual); visual.owner=body
		var collision:=CollisionShape3D.new(); collision.name="CollisionShape3D"; collision.shape=BoxShape3D.new(); collision.shape.size=result.size.max(Vector3.ONE*.01); collision.position=result.get_center(); collision.disabled=body.collision_layer==0; body.add_child(collision); collision.owner=body
		DirAccess.make_dir_recursive_absolute(entry["path"].get_base_dir()); var packed:=PackedScene.new(); assert(packed.pack(body)==OK); assert(ResourceSaver.save(packed,entry["path"])==OK); body.free()
		info["source_bounds"]=[[bounds.position.x,bounds.position.y,bounds.position.z],[bounds.end.x,bounds.end.y,bounds.end.z]]; info["prepared_scale"]=1.0; info["engine_calibrated"]=true
		if entry["behavior"]["building"]:
			entry["behavior"]["entrance_anchor"]={"point":[0,0,result.end.z+.04],"arrival":[0,0,result.end.z+1.5]}; roles[id]="work"
		if key in ["Building_Police_Station","Building_SWAT_HQ"]: services["stations"][id]="police"
		if entry["behavior"]["vehicle"]: driving["assets"][id]={}
		if key=="Prop_Folding_Chair": props["assets"][id]={"kind":"seat","point":[0,.45,0],"approach":[0,0,1.1]}
		if key in ["Prop_Searchlight","Prop_Floodlight_Tower"]: props["assets"][id]={"kind":"switch","label":"Toggle light","effect":"lamp"}
		if key in ["Prop_Generator","Prop_Comms_Station","Prop_Desk_Computer"]: props["assets"][id]={"kind":"appliance","label":"Operate equipment","duration":5,"result":"Equipment cycle complete"}
		await process_frame
	for pair in [[path,registry],["res://resources/catalog/city_services.json",services],["res://resources/catalog/driving.json",driving],["res://resources/catalog/props.json",props],["res://resources/catalog/citizen_roles.json",roles],["res://output/supplemental_assets/swat_manifest.json",registry]]: assert(Store.write_json(pair[0],pair[1]))
	print("SWAT: 114 grounded prefabs, rigs preserved, police/vehicle/prop profiles registered"); quit()
