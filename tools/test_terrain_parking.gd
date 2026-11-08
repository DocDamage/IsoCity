extends SceneTree
const Plan=preload("res://scripts/builder/traffic_plan.gd")
const Roads=preload("res://scripts/builder/roads.gd")
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
	var studio: Control=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio); await settle()
	for mode in ["2d","3d"]:
		studio.switch_mode(mode)
		var doc=preload("res://scripts/builder/document.gd").new(); doc.data=preload("res://scripts/builder/templates.gd").make(mode,"blank"); doc.data["objects"]=[]; doc.data["roads"]=[]; doc.data["terrain"]={"enabled":true,"bounds":[-16,-16,32,32]}; doc.data["terrain_vertices"]=[]; doc.data["water_cells"]=[]
		for x in range(-16,17):
			for z in range(-16,17): doc.data["terrain_vertices"].append({"cell":[x,z],"height":2})
		for x in range(-3,4): doc.data["roads"].append({"cell":[x,0]})
		var asset: String="2d:Parking_Accessible" if mode=="2d" else "3d:HanX_Traffic/Road_Parking"; var scale: float=2 if mode=="2d" else .5; var direction: String="SE" if mode=="2d" else "0"
		var point: Vector2=Plan.center(Vector2i(1,0),mode)+Vector2(0,5.5); var correction: Vector2=Roads.center_offset(studio.library,asset,direction,scale,mode)*(2 if mode=="2d" else 1)
		var bay: Dictionary=doc.add(asset,Plan.world(point-correction,mode,0 if mode=="2d" else 2),direction,scale); bay["traffic_parking"]=true
		doc.data["traffic"]={"enabled":true,"population":1,"seed":8,"speed":4,"parking_seconds":120}; var fixture: Dictionary=doc.data.duplicate(true)
		studio.documents[mode]=doc; studio.changed(); await settle(); var world: Node=studio.worlds[mode]; var manager: Node=studio.traffic_tools.managers[mode]; manager.set_physics_process(false)
		for change in ["unchanged","moved","deleted"]:
			doc.data=fixture.duplicate(true); studio.changed(); manager.reset(); manager.configure(doc.data,studio.library,world.instances,world.objects)
			check(manager.bays.size()==1,"Raised terrain accepts a supported parking space: "+mode+" / "+change)
			if manager.vehicles.is_empty(): check(false,"A parking vehicle must spawn: "+mode); continue
			var vehicle: Dictionary=manager.vehicles[0]
			for frame in 6000:
				manager.step(1.0/60)
				if vehicle["phase"]=="parked": break
			check(vehicle["phase"]=="parked" and vehicle["bay"]==bay["uid"],"Actual traffic enters the elevated bay: "+mode+" / "+change)
			var parked_point: Vector2=vehicle["point"]
			var parked_actor: int=vehicle["actor"].get_instance_id()
			var parked_timer: float=vehicle["timer"]
			for x in range(-16,16):
				for z in range(-4,4): doc.data["water_cells"].append({"cell":[x,z],"level":8})
			studio.changed(); manager.configure(doc.data,studio.library,world.instances,world.objects)
			check(vehicle["phase"]=="blocked" and manager.route_checkpoint(vehicle)=="parked"
				and manager.bay_owners.is_empty() and vehicle["point"]==parked_point,
				"Flooding suspends the parked vehicle in place and releases its claim: "+mode+" / "+change)
			if change=="moved":
				var item: Dictionary=doc.data["objects"][0]; var next: Array=Plan.world(point-correction+Vector2(8,0),mode,0 if mode=="2d" else 2); item["position"]=next
			elif change=="deleted": doc.data["objects"]=[]
			studio.changed(); manager.configure(doc.data,studio.library,world.instances,world.objects)
			doc.data["water_cells"]=[]; studio.changed(); manager.configure(doc.data,studio.library,world.instances,world.objects)
			check(vehicle["point"]==parked_point and vehicle["actor"].get_instance_id()==parked_actor,
				"Draining keeps the original actor at its physical position: "+mode+" / "+change)
			if change=="unchanged":
				check(vehicle["phase"]=="parked" and vehicle["timer"]==parked_timer
					and manager.bay_owners.get(bay["uid"])==vehicle["id"],
					"Draining restores the unchanged bay, remaining parking time and exclusive owner: "+mode)
			else:
				check(vehicle["phase"]=="parking_out" and vehicle["bay"].is_empty() and manager.bay_owners.is_empty(),
					"Draining never restores a moved or deleted bay claim: "+mode+" / "+change)
				var continuous := true
				for frame in 900:
					var before: Vector2=vehicle["point"]
					manager.step(1.0/60)
					continuous=continuous and before.distance_to(vehicle["point"])<=.07
					if vehicle["phase"]!="parking_out": break
				check(continuous and vehicle["phase"] in ["edge","turn"] and vehicle["actor"].get_instance_id()==parked_actor,
					"The same car reverses onto the clear lane without a position jump: "+mode+" / "+change)
	studio.free(); print("TERRAIN PARKING: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
