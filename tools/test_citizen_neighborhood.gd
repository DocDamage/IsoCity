extends SceneTree
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for i in 6: await process_frame
	await physics_frame
func capture(name: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await settle(); await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://output/"+name+".png")
func run() -> void:
	root.size=Vector2i(1480,900)
	var studio: Control=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio); await settle()
	for mode in ["2d","3d"]:
		studio.switch_mode(mode)
		var doc: RefCounted=preload("res://scripts/builder/document.gd").new()
		doc.data=preload("res://scripts/builder/templates.gd").make(mode,"blank")
		doc.data["title"]="Daily routines neighborhood"
		var assets: Array=["2d:Apartment_Brick","2d:Office_Tower","2d:Coffee_Shop","2d:Park_Bench"] if mode=="2d" else ["3d:HanX_City/Apartment_4F_A","3d:HanX_City/Office_Tower","3d:HanX_City/Cafe_Small","3d:HanX_Park/Bench_Park"]
		var positions: Array=[[-160,-96,0],[160,-96,0],[160,96,0],[-160,96,0]] if mode=="2d" else [[-14,0,-12],[14,0,-12],[14,0,12],[-14,0,12]]
		for i in 4: doc.add(assets[i],positions[i],("SW" if i==0 else "SE") if mode=="2d" else ("90" if i==0 else "0"))
		doc.data["citizens"]={"enabled":true,"population":3,"seed":5,"day_length":3600,"start_hour":9}
		studio.documents[mode]=doc; studio.changed(); studio.citizen_tools.dirty=true; studio.citizen_tools.show(); await settle()
		var manager: Node=studio.citizen_tools.managers[mode]; manager.set_physics_process(false)
		check(manager.plan["destinations"].values().all(func(values: Array):return values.size()==1),"Authored catalog roles populate a real four-destination neighborhood: "+mode)
		var home: Dictionary=manager.plan["destinations"]["home"][0]
		check(home["point"].distance_to(preload("res://scripts/builder/citizen_plan.gd").metric(positions[0],mode))>.5,"Rotated building entrances provide actual exterior approaches: "+mode)
		if mode=="2d":
			var box:=Rect2(); var first: bool=true
			for node in studio.worlds[mode].instances.values():
				var sprite: Sprite2D=node.get_node_or_null("Sprite2D")
				if not sprite: continue
				var rect: Rect2=sprite.global_transform*sprite.get_rect()
				box=rect if first else box.merge(rect); first=false
			box=box.grow(64); studio.worlds[mode].camera.position=box.get_center(); studio.worlds[mode].camera.zoom=Vector2.ONE*minf(studio.canvas.size.x/box.size.x,studio.canvas.size.y/box.size.y)*.9
		else: studio.worlds[mode].target=Vector3(0,5,0); studio.worlds[mode].distance=75; studio.worlds[mode].update_camera()
		var animated: bool=false
		for activity in [[9,"work"],[12.5,"shop"],[17.5,"park"],[21.5,"home"]]:
			manager.hour=activity[0]
			var arrived: bool=false
			for frame in 3000:
				manager.step(1.0/60)
				var actor: Node=manager.residents[0]["actor"]
				if actor.visible and (actor.get_node("Sprite2D").frame in [2,3,4,5] if mode=="2d" else actor.phase>0): animated=true
				if frame==120:
					studio.citizen_tools.tick(.5); await capture("citizen_neighborhood_walking_"+mode)
				if manager.residents.all(func(r: Dictionary):return not r["target"].is_empty() and manager.plan["lookup"][r["target"]]["role"]==activity[1] and r["index"]>=r["path"].size() and r["status"].begins_with("At ")): arrived=true; break
			check(arrived,"Residents arrive at a real "+activity[1]+" site: "+mode+" · "+str(manager.residents.map(func(r: Dictionary):return r["status"])))
			if activity[1]=="park":
				check(manager.residents.all(func(r: Dictionary):return r["actor"].visible),"Residents remain visible while visiting the park: "+mode)
				studio.citizen_tools.tick(.5); await capture("citizen_neighborhood_park_"+mode)
		check(animated,"Residents use real walking animation during their routes: "+mode)
		check(manager.residents.all(func(r: Dictionary):return not r["actor"].visible),"Residents wait indoors between home activities: "+mode)
	studio.queue_free(); await process_frame
	print("CITIZEN NEIGHBORHOOD: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
