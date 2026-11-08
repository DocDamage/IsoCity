extends "res://tools/test_traffic_controls.gd"

const ServicePlan=preload("res://scripts/builder/service_plan.gd")
const Entrance=preload("res://scripts/builder/entrance_anchors.gd")

func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled=false
	root.add_child(studio)
	await settle()
	ServicePlan.load_catalog()
	for mode in ["2d","3d"]:
		await live_city(mode)
	studio.free()
	await settle()
	print("FOUR-WAY TRAFFIC: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func live_city(mode: String) -> void:
	studio.switch_mode(mode)
	var doc:=Doc.new()
	doc.data=fixture(mode)
	doc.data["roads"]=[]
	for index in range(-9,10):
		doc.data["roads"].append({"cell":[index,0],"crossing":index==0})
		if index!=0: doc.data["roads"].append({"cell":[0,index]})
	for index in 2:
		var asset: String="2d:Bus_Stop_Sign" if mode=="2d" else "3d:HanX_Traffic/Bus_Stop"
		var item: Dictionary=doc.add(asset,Plan.world(Plan.center(Vector2i(-6+index*12,0),mode)+Vector2(0,8),mode),studio.library.directions(asset)[0])
		item["uid"]="stop_"+str(index)
	var station_id: String=""
	for id in ServicePlan.catalog["stations"]:
		if ServicePlan.catalog["stations"][id]=="fire":
			station_id=id
			if id.begins_with(mode+":"): break
	var station: Dictionary=doc.add(station_id,Plan.world(Vector2(-12,-40),mode),studio.library.directions(station_id)[0],studio.library.assets[station_id]["data"].get("default_scale",1.0))
	station["city_service"]={"kind":"fire","radius":160,"units":1,"task_seconds":2}
	var target_asset: String="2d:House_Blue" if mode=="2d" else "3d:HanX_City/Row_Houses_A"
	var target: Dictionary=doc.add(target_asset,Plan.world(Vector2(12,40),mode),"SE" if mode=="2d" else "90")
	doc.data["traffic"]={"enabled":true,"seed":9,"population":1}
	doc.data["transit"]={"enabled":true,"automatic":false}
	doc.data["transit_lines"]=[{"uid":"axis_line","stops":["stop_0","stop_1"],"headway":180,"capacity":2}]
	doc.data["services"]={"enabled":true,"automatic":false}
	studio.documents[mode]=doc
	studio.changed()
	await settle()
	var world: Node=studio.worlds[mode]
	for desired in [[station,Vector2(-12,-40)],[target,Vector2(12,40)]]:
		var item: Dictionary=desired[0]
		var entrance: Variant=Entrance.position_for(world.instances[item["uid"]],item,mode,studio.library)
		var actual: Vector2=Plan.metric([entrance.x,entrance.y,0] if mode=="2d" else [entrance.x,entrance.y,entrance.z],mode)
		item["position"]=Plan.world(Plan.metric(item["position"],mode)+desired[1]-actual,mode)
	studio.changed()
	await settle()
	var car: Node=studio.traffic_tools.managers[mode]
	var bus: Node=studio.transit_tools.managers[mode]
	var service: Node=studio.service_tools.managers[mode]
	for manager in [car,bus,service]: manager.set_physics_process(false)
	check(bus.passengers.plan["lines"].size()==1 and car.vehicles.size()==1,"An ordinary car and a real bus line share the four-way city: "+mode)
	var requested: Dictionary=service.dispatch.request("fire",target["uid"])
	check(requested["ok"],"A real service dispatch routes across the perpendicular arm: "+mode+" "+str(requested.get("reason","")))
	if not requested["ok"]: return
	var job: Dictionary=requested["job"]
	var walker: Node=Instance.make(studio.library,"2d:Office_Worker",mode)
	world.objects.add_child(walker)
	var walk_at: Array=Plan.world(Plan.center(Vector2i.ZERO,mode),mode)
	walker.position=Vector2(walk_at[0],walk_at[1]) if mode=="2d" else Vector3(walk_at[0],0,walk_at[2])
	car.pedestrians.append(walker)
	var seen: Dictionary={}
	var stopped_for_pedestrian: bool=false
	var conflicting: bool=false
	var crossed_after_wait: bool=false
	var authored: Dictionary=doc.data.duplicate(true)
	var duration: int=0
	for frame in 18000:
		duration=frame
		car.step(1.0/60)
		bus.step(1.0/60)
		service.step(1.0/60)
		var owner: String=car.gates.owners.get("0,0","")
		if not owner.is_empty():
			var kind: String="car" if owner.begins_with("traffic_") else "bus" if owner.begins_with("bus_") else "service"
			seen[kind]=true
			conflicting=conflicting or walker.visible
			crossed_after_wait=crossed_after_wait or stopped_for_pedestrian
		if walker.visible:
			var statuses: Array=car.vehicles.map(func(v: Dictionary):return v["status"])
			statuses.append_array(bus.buses.values().map(func(v: Dictionary):return v["status"]))
			statuses.append(job["reason"])
			if "Pedestrian crossing occupied" in statuses:
				stopped_for_pedestrian=true
				walker.hide()
		if seen.size()==3 and job["state"]=="complete" and stopped_for_pedestrian: break
	walker.free()
	var summary: String="%s after %d frames, %s, car %s, bus %s, service %s"%( [mode,duration,seen,car.vehicles.map(func(v:Dictionary):return [v["status"],v["point"]]),bus.buses.values().map(func(v:Dictionary):return [v["status"],v["vehicle"]["point"]]),[job["state"],job["reason"]]] )
	print("FOUR-WAY TRACE: "+summary)
	check(stopped_for_pedestrian and crossed_after_wait and not conflicting,"Vehicles yield to the real pedestrian before releasing any movement: "+mode)
	check(seen.size()==3,"The ordinary car, real timetable bus and service crew all acquire the same physical junction: "+summary)
	check(job["state"]=="complete" and job["fulfilled"],"The real service crew completes its visit and returns: "+summary)
	check(doc.data==authored,"The live junction, vehicle queues and current phase leave authored data unchanged: "+mode)
