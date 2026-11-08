extends "res://tools/test_local_deliveries.gd"

func signals(doc: RefCounted,mode: String) -> void:
	for cell in [Vector2i(-1,2),Vector2i(1,2)]: doc.data["roads"].append({"cell":[cell.x,cell.y]})
	var center: Vector2=Plan.Traffic.center(Vector2i(0,2),mode)
	var asset: String="2d:Traffic_Light" if mode=="2d" else "3d:HanX_Traffic/Traffic_Light_Red"
	var specs: Array=[[Vector2(4.2,-4.6),"SE" if mode=="2d" else "90",0],
		[Vector2(-4.6,4.2),"SW" if mode=="2d" else "0",1]]
	for spec in specs:
		var record: Dictionary=doc.add(asset,Plan.Traffic.world(center+spec[0],mode),spec[1])
		record["traffic_control"]={"kind":"signal","cell":[0,2],"side":spec[2],"timing":{"green":4,"walk":3,"clear":2}}

func workflow(mode: String) -> void:
	var data: Dictionary=await fixture(mode)
	var driver: Node=data["driver"]
	var traffic: Node=driver.traffic
	signals(data["doc"],mode)
	studio.changed()
	await settle()
	traffic.set_physics_process(false)
	var section: String="0,2"
	check(traffic.gates.phase_start.has(section),"The real signal heads bind the delivery junction: "+mode+" "+str(traffic.plan["controls"]))
	if not traffic.gates.phase_start.has(section): return
	var epoch: float=traffic.gates.phase_start[section]
	await enter_car("van")
	studio.control_settings.execute("delivery_cargo")
	tick(driver,16)
	check(driver.delivery.job.get("phase")=="carrying","The original vehicle loads before using the shared junction: "+mode)
	traffic.junction_time=epoch+2.1
	for frame in 250: driver.step(1.0/60,Vector2.DOWN)
	check(driver.delivery.section_at(driver.active["point"])!=section and driver.notice.contains("red") and driver.delivery.job.get("loaded")==3,"The actual loaded van stops at the perpendicular red phase: "+mode+" "+str([driver.active.get("point"),driver.notice]))
	traffic.junction_time=epoch+9.2
	for frame in 180:
		driver.step(1.0/60,Vector2.DOWN)
		if driver.delivery.section_at(driver.active["point"])==section: break
	check(traffic.gates.owners.get(section)=="delivery:van","On green the same physical van acquires the shared junction lease: "+mode+" "+str(traffic.gates.owners))
	check(drive_to(driver,data["finish"]) and not traffic.gates.owners.has(section),"The van clears the junction and releases its lease en route to the shop: "+mode)
	studio.control_settings.execute("delivery_cargo")
	tick(driver,16)
	check(driver.delivery.reward_total==45 and driver.delivery.inventory("drop").get("parcels")==3,"The routed van finishes its original delivery after the shared signal: "+mode)
	studio.set_walking(false)
