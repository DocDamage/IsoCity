extends SceneTree
const Plan=preload("res://scripts/builder/zone_plan.gd")
const Fit=preload("res://scripts/builder/grid_fit.gd")
const Terrain=preload("res://scripts/builder/terrain_plan.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for frame in 6: await process_frame
	await physics_frame
func run() -> void:
	root.size=Vector2i(1480,900)
	var studio: Control=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio); await settle()
	for mode in ["2d","3d"]:
		studio.switch_mode(mode)
		for height in [2.0,-2.0]:
			var doc=preload("res://scripts/builder/document.gd").new(); doc.data=preload("res://scripts/builder/templates.gd").make(mode,"blank"); doc.data["objects"]=[]; doc.data["roads"]=[]; doc.data["terrain"]={"enabled":true,"bounds":[-24,-24,48,64]}; doc.data["terrain_vertices"]=[]; doc.data["water_cells"]=[]
			for x in range(-24,25):
				for z in range(-24,41): doc.data["terrain_vertices"].append({"cell":[x,z],"height":height})
			for x in range(-4,5): doc.data["roads"].append({"cell":[x,0]})
			doc.data["zoning"]={"enabled":true,"stage_seconds":2,"seed":7}; doc.data["zones"]=[{"uid":"terrain_lot","kind":"residential","rect":[-24,8,48,32],"stage":0}]
			var context: String=mode+" / height "+str(height); var source: Dictionary=doc.data.duplicate(true); var lot: Dictionary=doc.data["zones"][0]; var state: Dictionary=Plan.evaluate(doc.data,lot,studio.library)
			check(state["ok"] and doc.data==source,"Clear raised/depressed lots plan without changing authored terrain: "+context+state["reason"])
			if not state["ok"]: continue
			var proposal: Dictionary=state["proposal"]; var box: Rect2=Plan.footprint(proposal,mode,studio.library)
			check(absf(proposal["position"][1]+Fit.footprint_bounds(proposal,mode,studio.library).position.y-height)<.001 if mode=="3d" else proposal["position"][2]==0,"Generated building contact matches its terrain surface: "+context)
			var first: Dictionary=Plan.advance(doc.data,lot["uid"],studio.library,"terrain_building"); doc.data=first["data"]; studio.documents[mode]=doc; studio.changed(); var world: Node=studio.worlds[mode]; var manager: Node=studio.zone_tools.managers[mode]; manager.paused=true; manager.configure(doc.data,studio.library,world.objects); await settle()
			var marker: Node=manager.visuals[lot["uid"]]
			if mode=="2d":
				var p: Vector2=marker.points(box)[0]; var raw: Array=Plan.Traffic.world(box.position,mode); check(absf(p.y-(raw[1]-height*8))<.001,"Lot and construction artwork follows isometric terrain height: "+context)
			else:
				var mesh: MeshInstance3D=marker.find_children("*","MeshInstance3D",true,false)[0]; var vertices: PackedVector3Array=mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]; var low: float=INF
				for vertex in vertices: low=minf(low,vertex.y)
				check(absf(low-(height+.0475))<.002,"3D lot overlay follows physical terrain height: "+context)
			if height==2:
				var portable: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(world,doc.data,studio.library,"res://output/terrain_zoning_"+mode+".zip"); check(portable["ok"],"Terrain construction stages export with future building dependencies: "+context)
				if "--capture" in OS.get_cmdline_user_args():
					studio.zone_tools.selected=lot["uid"]; studio.zone_tools.fields_stamp=0; studio.zone_tools.show()
					if mode=="3d": world.target=Vector3(0,height,24); world.distance=70; world.update_camera()
					else: world.camera.position=Vector2(-192,96-height*8); world.camera.zoom=Vector2.ONE*1.2
					await settle(); RenderingServer.force_draw(false); RenderingServer.force_draw(false); root.get_texture().get_image().save_png("res://output/terrain_zoning_"+mode+".png")
			studio.set_walking(true); world.player.set_physics_process(false); var at: Array=Plan.Traffic.world(box.get_center(),mode,height+.01); world.player.teleport_to(Vector2(at[0],at[1]) if mode=="2d" else Vector3(at[0],at[1],at[2])); var people: Array[Vector2]=studio.zone_tools.occupied(mode)
			check(not Plan.evaluate(doc.data,doc.data["zones"][0],studio.library,people)["ok"],"An actual character on raised land protects the future building footprint: "+context); studio.set_walking(false); world.player.teleport_to(Vector2(10000,10000) if mode=="2d" else Vector3(1000,0,1000))
			var marker_id: int=marker.get_instance_id()
			for vertex in doc.data["terrain_vertices"]:
				if vertex["cell"]==[-20,-20]: vertex["height"]+=1
			studio.changed(); manager.configure(doc.data,studio.library,world.objects); check(manager.visuals[lot["uid"]].get_instance_id()==marker_id,"Distant terrain edits retain unchanged lot presentation: "+context)
			for vertex in doc.data["terrain_vertices"]: vertex["height"]=height+1
			var second: Dictionary=Plan.advance(doc.data,lot["uid"],studio.library); check(second["ok"],"Pending development adapts to a new flat surface height: "+context)
			if not second["ok"]: continue
			doc.data=second["data"]; var finishing: Dictionary=Plan.advance(doc.data,lot["uid"],studio.library)
			check(finishing["ok"] and finishing["data"]["zones"][0]["stage"]==Plan.Stage.FINISHING and finishing["data"]["objects"].is_empty(),"Terrain development retains its surface through finishing: "+context)
			var final: Dictionary=Plan.advance(finishing["data"],lot["uid"],studio.library); check(final["ok"] and final["data"]["objects"].size()==1,"Terrain development completes into an editable building: "+context)
			doc.data=final["data"]; studio.changed(); await settle(); var grown: Dictionary=doc.data["objects"][0]
			check(absf(grown["position"][1]+Fit.footprint_bounds(grown,mode,studio.library).position.y-height-1)<.001 if mode=="3d" else absf(world.instances[grown["uid"]].get_meta("terrain_height",0)-height-1)<.001,"Completed building retains its updated terrain contact: "+context)
			var unsafe: Dictionary=source.duplicate(true); var cell:=Vector2i((box.get_center()/2).floor()); unsafe["water_cells"]=[{"cell":[cell.x,cell.y],"level":height+2}]; var wet: Dictionary=Plan.evaluate(unsafe,unsafe["zones"][0],studio.library)
			check(not wet["ok"] and "water" in wet["reason"],"Flooded foundation footprints pause development: "+context)
			unsafe["water_cells"]=[]
			for vertex in unsafe["terrain_vertices"]:
				if vertex["cell"]==[cell.x,cell.y]: vertex["height"]+=3
			var steep: Dictionary=Plan.evaluate(unsafe,unsafe["zones"][0],studio.library); check(not steep["ok"] and "flatten" in steep["reason"],"Uneven foundations explain how to restore development: "+context)
	studio.free(); print("TERRAIN ZONING: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
