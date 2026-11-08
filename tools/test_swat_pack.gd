extends SceneTree
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for frame in 6: await physics_frame
	await process_frame
func run() -> void:
	var library=preload("res://scripts/builder/asset_library.gd").new()
	var registry: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/catalog/swat_registry.json"))
	check(registry["models"].size()==114,"114 individual models; aggregate and alternate file formats are not duplicate catalog entries")
	var rigs: int=0
	for id in registry["models"]:
		var descriptor: Dictionary=registry["models"][id]; var info: Dictionary=descriptor["data"]
		check(library.assets.has(id) and library.pack_name(library.assets[id])=="HanX SWAT","Prepared model is filterable by pack: "+id)
		var node: Node3D=load(descriptor["path"]).instantiate(); root.add_child(node)
		var bounds: AABB=preload("res://scripts/model_bounds.gd").get_bounds(node)
		check(bounds.size.length()>.001 and (node.get_node("Model").position.is_zero_approx() if info.get("authored_origin_preserved",false) else absf(bounds.get_center().x)<.001 and absf(bounds.get_center().z)<.001),"Geometry retains modular/grip origins or centred placement: "+id)
		check(node.get_node("Model").position.is_zero_approx() if info.get("authored_origin_preserved",false) else absf(bounds.position.y)<.001,"Modular and grip pivots remain intact; standalone objects sit on ground: "+id)
		check(info["source_export_allowed"]==false and not info["author"].is_empty(),"Supplied license and author are explicit")
		if info["rigged"]:
			rigs+=1; var skeletons: Array=node.find_children("*","Skeleton3D",true,false)
			check(not skeletons.is_empty() and skeletons[0].get_bone_count()==21,"All 21 source bones are preserved without claiming nonexistent animation clips")
		if descriptor["behavior"]["building"]:
			for angle in ["0","90","180","270"]:
				var item: Dictionary={"asset":id,"direction":angle,"scale":1,"position":[0,0,0]}; node.rotation_degrees.y=float(angle)
				var point: Vector3=preload("res://scripts/builder/entrance_anchors.gd").position_for(node,item,"3d",library)
				check(point.is_finite() and point.length()>0,"Authored entrance follows each model heading")
		if info["source_name"]=="Training_Wall_Door":
			preload("res://scripts/builder/walk_geometry.gd").prepare(node,id,library)
			check(node.get_node("CollisionShape3D").disabled and node.find_children("WalkSurface*","CollisionShape3D",true,false).size()>0,"Training doorway uses actual mesh geometry instead of a sealed bounding box")
		node.free(); await process_frame
	check(rigs==3,"Three rigged source characters retained")
	check(preload("res://scripts/builder/service_plan.gd").profile({"asset":"3d:Supplemental_SWAT/Building_SWAT_HQ"})["kind"]=="police","SWAT HQ participates in existing police services")
	var studio: Control=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio)
	while not studio.enhancements_ready: await process_frame
	for mode in ["2d","3d"]:
		studio.switch_mode(mode); var before: Dictionary=studio.current().data.duplicate(true)
		studio._command("swat_showcase",null); await settle()
		check(studio.current().data["objects"].size()==21 and preload("res://scripts/builder/document.gd").valid(studio.current().data,mode,library),"Compound example is editable and validates: "+mode)
		if "--capture" in OS.get_cmdline_user_args():
			for frame in 15: await process_frame
			RenderingServer.force_draw(false); RenderingServer.force_draw(false); root.get_texture().get_image().save_png("res://output/swat_compound_"+mode+".png")
		var export: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(studio.worlds[mode],studio.current().data,library,"res://output/swat_restricted_"+mode+".zip")
		check(not export["ok"] and export["message"].contains("license"),"Source ZIP export honors pack redistribution restrictions")
		var requirements: Array=preload("res://scripts/builder/creation_share.gd").required_assets(studio.current().data,library)
		check(requirements.any(func(entry: Dictionary):return entry["pack"]=="HanX SWAT" and entry["author"]=="HanX Assets"),"Layout sharing retains pack requirements and attribution")
		studio._command("undo",null); check(studio.current().data==before,"Compound example Undo restores previous layout")
		studio.current().data=preload("res://scripts/builder/templates.gd").make(mode,"blank")
		var id: String="3d:Supplemental_SWAT/Vehicle_SWAT_Van"; var car: Dictionary=studio.current().add(id,[0,0,0],"0",1); studio.changed(); await settle()
		var plan=preload("res://scripts/builder/driving_plan.gd"); var world: Node=studio.worlds[mode]; var runtime: Node=world.exploration.driving
		var center: Vector2=plan.center(car,library,mode); var extent: Vector2=plan.dimensions(car,library,mode)
		studio.set_walking(true); world.player.teleport_to(plan.world(center+Vector2(extent.x+.5,0),mode)); world.player.set_physics_process(false); runtime.set_physics_process(false); await settle(); world.exploration.interact()
		check(not runtime.active.is_empty(),"Normal interaction enters SWAT van: "+mode)
		if not runtime.active.is_empty():
			for frame in 90: runtime.step(1.0/60,Vector2(0,1),false)
			check(runtime.active["point"].distance_to(center)>4,"SWAT van accelerates in native and mixed views")
		studio.set_walking(false)
		for key in ["Prop_Folding_Chair","Prop_Searchlight","Prop_Generator"]:
			studio.current().data=preload("res://scripts/builder/templates.gd").make(mode,"blank")
			var item: Dictionary=studio.current().add("3d:Supplemental_SWAT/"+key,[0,0,0],"0",1); studio.changed(); await settle()
			var prop=preload("res://scripts/builder/prop_plan.gd"); var profile: Dictionary=prop.profile(item)
			studio.set_walking(true); world.player.teleport_to(prop.anchor(world.instances[item["uid"]],item,library,mode,profile,"approach")); world.player.set_physics_process(false); await settle()
			check(prop.nearby(world.exploration).get("item",{}).get("uid")==item["uid"],"Supplied furniture/equipment approach is reachable: "+mode+"/"+key)
			world.exploration.interact()
			check(not world.exploration.props.active.is_empty() if profile["kind"]!="switch" else not world.exploration.props.notice.is_empty(),"Normal interaction uses supplied furniture/equipment: "+mode+"/"+key)
			studio.set_walking(false)
	studio.free(); await process_frame; await process_frame
	print("SWAT PACK: %d checks, %d failures"%[checks,failures]); quit(1 if failures else 0)
