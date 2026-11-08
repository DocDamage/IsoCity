extends SceneTree
const Plan=preload("res://scripts/builder/driving_plan.gd")
var checks: int=0
var failures: int=0
var studio: Control
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for frame in 5: await physics_frame
	await process_frame
func tick(runtime: Node,seconds: float,input: Vector2,brake: bool=false) -> void:
	for frame in ceili(seconds*60): runtime.step(1.0/60,input,brake)
func capture(mode: String,stage: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	for frame in 5: await process_frame
	RenderingServer.force_draw(false); RenderingServer.force_draw(false); root.get_texture().get_image().save_png("res://output/driving_"+mode+"_"+stage+".png")
func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio); await settle()
	for asset in Plan.definitions()["assets"]: check(studio.library.assets.has(asset),"Explicit driving asset exists: "+asset)
	for raw in [null,[],{"enabled":1},{"max_speed":0},{"reverse_speed":INF},{"steering":NAN},{"reach":7},{"acceleration":21}]: check(not Plan.valid(raw),"Unsafe driving settings rejected: "+str(raw))
	check(Plan.profile({"asset":"2d:bus_stop_benches"}).is_empty() and Plan.profile({"asset":"2d:Sedan_Blue","driving":{"enabled":false}}).is_empty(),"Unclassified and disabled objects do not become driveable")
	for variant in [["2d","2d:Sedan_Blue"],["3d","3d:HanX_Traffic/Car_Sedan"],["2d","3d:HanX_Traffic/Car_Sedan"],["3d","2d:Sedan_Blue"]]:
		var mode: String=variant[0]
		studio.switch_mode(mode); var city: RefCounted=studio.current(); city.data=preload("res://scripts/builder/templates.gd").make(mode,"blank")
		var asset: String=variant[1]
		var car: Dictionary={"uid":"drive_car","asset":asset,"position":[0,0,0],"direction":"NE" if asset.begins_with("2d:") else "0","scale":1.0}
		city.data["objects"]=[car]; studio.changed(); await settle()
		var world: Node=studio.worlds[mode]; var exploration: Node=world.exploration; var runtime: Node=exploration.driving; var player: Node=world.player; var node: Node=world.instances["drive_car"]
		var center: Vector2=Plan.center(car,studio.library,mode); var extent: Vector2=Plan.dimensions(car,studio.library,mode); var start: Variant=Plan.world(center+Vector2(extent.x+.5,0),mode)
		studio.set_walking(true); player.teleport_to(start); player.set_physics_process(false); runtime.set_physics_process(false); await settle()
		var before: Dictionary=city.data.duplicate(true); var original: Variant=node.transform; var history: int=city.undo_history.size()
		check(exploration.prompt().contains("Drive"),"Normal exploration offers a nearby vehicle: "+mode)
		exploration.interact()
		check(not runtime.active.is_empty() and not player.visible and not player.is_physics_processing() and not exploration.walk_allowed(),"Actual Interact enters vehicle and transfers movement control: "+mode)
		if runtime.active.is_empty(): continue
		tick(runtime,1.5,Vector2(0,1)); var moved: Vector2=runtime.active["point"]
		check(moved.distance_to(center)>4 and runtime.speed>5 and node.transform!=original,"Acceleration moves the actual placed vehicle through the city: "+mode)
		check(player.global_position.distance_to(world.to_global(Plan.world(moved,mode)))<.01,"Camera/listener player follows driven vehicle: "+mode)
		var nobody: Array[Vector2]=[]
		check(runtime.traffic.obstructed({"id":"ai_probe","half_length":1.0},moved,Plan.heading(runtime.active["yaw"]),nobody)=="Waiting for vehicle clearance","Actual traffic collision planning yields to the driven vehicle at its moved position: "+mode)
		check(runtime.vehicle_states()[0]["phase"]=="drive" and runtime.vehicle_states()[0]["speed"]>0,"Driven vehicles expose movement to ambient traffic audio: "+mode)
		exploration.interact(); check(not runtime.active.is_empty() and runtime.notice.contains("stop"),"Moving exits require braking: "+mode)
		tick(runtime,1,Vector2.ZERO,true); var heading: float=runtime.active["yaw"]; tick(runtime,1,Vector2(1,1)); check(absf(runtime.active["yaw"]-heading)>.3,"Steering changes actual travel heading: "+mode)
		tick(runtime,2,Vector2.ZERO,true); await capture(mode,"driving_"+asset.left(2)); exploration.interact()
		check(runtime.active.is_empty() and player.visible and player.collision_mask>0,"Stopped exit restores the visible walking controller at a safe destination: "+mode)
		check(city.data==before and city.undo_history.size()==history,"Driving and parking leave source layout and history unchanged: "+mode)
		var parked: Vector2=runtime.parked["drive_car"]["point"]; check(parked.distance_to(center)>4,"Parked session vehicle retains its destination: "+mode)
		await settle(); check(exploration.prompt().contains("Drive"),"Parked vehicle can be entered again at its destination: "+mode); exploration.interact()
		check(not runtime.active.is_empty(),"Repeated entry uses parked session pose: "+mode)
		if not runtime.active.is_empty():
			runtime.active["yaw"]=0; runtime.active["point"]=center; runtime.pose(); runtime.speed=0
			var wall: Node=StaticBody2D.new() if mode=="2d" else StaticBody3D.new(); var collision: Node=CollisionShape2D.new() if mode=="2d" else CollisionShape3D.new(); wall.collision_layer=1
			if mode=="2d": collision.shape=RectangleShape2D.new(); collision.shape.size=Vector2(200,20)
			else: collision.shape=BoxShape3D.new(); collision.shape.size=Vector3(20,3,.5)
			wall.add_child(collision); world.add_child(wall); wall.position=Plan.world(center+Vector2(0,extent.y+3),mode,1.5); await settle(); tick(runtime,3,Vector2(0,1))
			check(runtime.active["point"].y<center.y+extent.y+3 and runtime.speed==0 and runtime.notice.contains("blocked"),"Continuous footprint collision prevents driving through a wall: "+mode)
			wall.free(); await physics_frame
			var reverse_from: Vector2=runtime.active["point"]; tick(runtime,1,Vector2(0,-1)); check(runtime.speed<0 and runtime.active["point"].y<reverse_from.y-1,"Reverse input backs away from an obstruction: "+mode); tick(runtime,1,Vector2.ZERO,true)
			var barrier: Node=StaticBody2D.new() if mode=="2d" else StaticBody3D.new(); var solid: Node=CollisionShape2D.new() if mode=="2d" else CollisionShape3D.new(); barrier.collision_layer=1
			if mode=="2d": solid.shape=RectangleShape2D.new(); solid.shape.size=Vector2(500,500)
			else: solid.shape=BoxShape3D.new(); solid.shape.size=Vector3(30,5,30)
			barrier.add_child(solid); world.add_child(barrier); barrier.global_position=player.global_position; await settle(); exploration.interact()
			check(not runtime.active.is_empty() and not player.visible and runtime.notice.contains("blocked"),"Blocked exit retains driving control and explains the obstruction: "+mode)
			barrier.free(); await physics_frame; exploration.interact(); check(runtime.active.is_empty() and player.visible,"Exit succeeds after blocked space clears: "+mode)
			await settle(); exploration.interact()
			if not runtime.active.is_empty():
				var target: Vector2=runtime.active["point"]; var actor: Node=Node2D.new() if mode=="2d" else Node3D.new(); world.add_child(actor)
				runtime.traffic.vehicles.append({"id":"test_car","actor":actor,"point":target+Vector2(0,extent.y+2),"heading":Vector2.DOWN,"half_width":1.0,"half_length":1.0,"phase":"parked"})
				runtime.active["yaw"]=0; tick(runtime,2,Vector2(0,1)); check(runtime.speed==0 and runtime.notice.contains("Traffic"),"Driven vehicle stops for moving-traffic footprints: "+mode)
				runtime.traffic.vehicles.clear(); actor.free(); runtime.active["data"]["terrain"]={"enabled":true,"bounds":[-20,-20,40,40]}; var at: Vector2=runtime.active["point"]; var wet: Vector2=at+Vector2(0,extent.y+.6); var cell:=Vector2i((wet/2).floor())
				runtime.active["data"]["water_cells"]=[{"cell":[cell.x,cell.y],"level":2}]; runtime.waters=preload("res://scripts/builder/terrain_plan.gd").lookup(runtime.active["data"],true)
				tick(runtime,2,Vector2(0,1)); check(runtime.speed==0 and runtime.notice.contains("water"),"Full vehicle footprint stops before deep water: "+mode)
				runtime.active["data"].erase("water_cells"); runtime.waters.clear(); runtime.active["data"]["terrain_vertices"]=[]
				for x in range(-20,21):
					for z in range(-20,21): runtime.active["data"]["terrain_vertices"].append({"cell":[x,z],"height":float(x)})
				runtime.heights=preload("res://scripts/builder/terrain_plan.gd").lookup(runtime.active["data"]); tick(runtime,1,Vector2(0,1)); check(runtime.speed==0 and runtime.notice.contains("steep"),"Full footprint rejects a steep terrain bank: "+mode)
				for vertex in runtime.active["data"]["terrain_vertices"]: vertex["height"]=3+vertex["cell"][0]*.2
				runtime.heights=preload("res://scripts/builder/terrain_plan.gd").lookup(runtime.active["data"]); runtime.step(1.0/60,Vector2(0,1)); var surface: Dictionary=runtime.surface(runtime.active["point"])
				check(runtime.speed>0 and (is_equal_approx(float(player.get_meta("terrain_height",0)),surface["height"]) if mode=="2d" else absf(player.position.y-surface["height"])<.01),"Vehicle and camera follow supported elevated terrain: "+mode)
				if mode=="3d" and asset.begins_with("3d:"): check(node.basis.y.normalized().dot(surface["normal"])>.999,"Native vehicle wheels follow the slope normal")
				runtime.active["data"].erase("terrain"); runtime.active["data"].erase("terrain_vertices"); runtime.heights.clear()
		studio.set_walking(false)
		check(runtime.active.is_empty() and runtime.parked.is_empty() and node.transform==original and not player.visible,"Build return restores authored vehicle pose and clears session movement: "+mode)
		check(city.data==before,"Build cleanup leaves authored content intact: "+mode)
	studio.free(); await process_frame
	print("DRIVING FOUNDATION: %d/%d checks passed"%[checks-failures,checks]); quit(0 if failures==0 else 1)
