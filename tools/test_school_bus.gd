extends "res://tools/test_school_life.gd"

const Traffic=preload("res://scripts/builder/traffic_plan.gd")

func sample(citizens: Node,bus: Node) -> void:
	await physics_frame
	citizens.step(1.0/60)
	bus.step(1.0/60)

func withdrawn_bus_check(citizens: Node,bus: Node,stops: Array[String],mode: String) -> void:
	var actor: Node=citizens.residents[0]["actor"]
	var source: Vector2=bus.actor_point(actor)
	var school: Vector2=citizens.schools.sites["school"]["point"]
	var position: Array=preload("res://scripts/builder/citizen_plan.gd").world(school,mode)
	var destination: Vector2=Traffic.metric(position,mode)
	var itinerary: Dictionary=Transit.school_journey(bus.passengers.plan,source,destination,bus.elapsed,bus.helper.obstacles,
		"school_line",stops[0],stops[1],School.bus_asset(mode))
	var model=preload("res://scripts/builder/transit_passengers.gd").new()
	model.configure(bus.passengers.plan,true)
	var result: Dictionary=model.request(itinerary)
	check(result["ok"] and result["job"]["required_bus"]==School.bus_asset(mode),"An assigned pupil only books the native school bus: "+mode)
	if not result["ok"]: return
	var replacement: Dictionary=bus.passengers.plan.duplicate(true)
	replacement["lines"]["school_line"]["school_bus"]=false
	model.configure(replacement,true)
	check(result["job"]["state"]=="cancelled" and result["job"]["reason"].contains("no longer operating"),"Changing the assigned route to a standard bus releases an unboarded school passenger: "+mode)

func transport_city(mode: String) -> void:
	studio.switch_mode(mode)
	var doc:=Doc.new()
	doc.data=Templates.make(mode,"blank")
	doc.data["roads"]=[]
	studio.documents[mode]=doc
	for x in range(-4,13):
		doc.data["roads"].append({"cell":[x,0]})
	var stops: Array[String]=[]
	for index in 2:
		var asset: String="2d:Bus_Stop_Sign" if mode=="2d" else "3d:HanX_Traffic/Bus_Stop"
		var location: Vector2=Traffic.center(Vector2i(index*8,0),mode)+Vector2(0,8)
		var item: Dictionary=doc.add(asset,Traffic.world(location,mode),studio.library.directions(asset)[0])
		item["uid"]="neighborhood_stop" if index==0 else "school_stop"
		item["name"]="Neighborhood stop" if index==0 else "School stop"
		stops.append(item["uid"])
	var house: Dictionary=doc.add("2d:House_Blue",Traffic.world(Vector2(-6,14),mode),"SE",.45)
	house["uid"]="home"
	house["citizen_role"]="home"
	var building: Dictionary=doc.add("3d:HanX_School/School_Building",Traffic.world(Vector2(58,13) if mode=="2d" else Vector2(59,18),mode),"0",.16 if mode=="2d" else .2)
	building["uid"]="school"
	building["entrance_anchor"]={"point":[0,0,8],"arrival":[0,0,32] if mode=="2d" else [0,0,12]}
	doc.data["citizens"]={"enabled":true,"population":2,"seed":42,"day_length":2000,"start_hour":8.15}
	doc.data["transit"]={"enabled":true,"automatic":false,"speed":4,"population":4}
	doc.data["transit_lines"]=[{"uid":"school_line","name":"School bus","stops":Array(stops),"headway":160,"offset":25,"dwell":5,"capacity":1}]
	studio.changed()
	await settle()
	var citizens: Node=studio.citizen_tools.managers[mode]
	var bus: Node=studio.transit_tools.managers[mode]
	citizens.set_physics_process(false)
	bus.set_physics_process(false)
	var ui: RefCounted=studio.transit_tools
	studio._command("transit",null)
	ui.selected="school_line"
	ui.load_line()
	ui.school_bus.button_pressed=true
	ui.save_line()
	await settle()
	check(doc.data["transit_lines"][0].get("school_bus",false) and bus.school_pool.size()==1,"The route inspector opts into the reviewed native school bus: "+mode+" "+str(bus.passengers.plan.get("notices",[])))
	if bus.school_pool.is_empty() or not bus.passengers.plan["lines"].has("school_line"): return
	studio.selected_uid=building["uid"]
	studio.selected_uids.assign([building["uid"]])
	studio._command("schools",null)
	var school_ui: RefCounted=studio.school_tools
	school_ui.enabled.button_pressed=true
	school_ui.capacity.value=2
	school_ui.route.select(1)
	school_ui.refresh_stops(stops[0],stops[1])
	school_ui.save()
	await settle()
	check(doc.object(building["uid"]).get("school",{}).get("home_stop","")==stops[0] and citizens.schools.enrolled.size()==2,"The school inspector links both real stops to its enrolled pupils: "+mode)
	if citizens.schools.enrolled.size()!=2: return
	var world: Node=studio.worlds[mode]
	world.player.set_physics_process(false)
	var off_road: Array=Traffic.world(Vector2(-16,30),mode)
	world.player.teleport_to(Vector2(off_road[0],off_road[1]) if mode=="2d" else Vector3(off_road[0],0,off_road[2]))
	var ids: Array=citizens.residents.map(func(resident: Dictionary)->int:return resident["actor"].get_instance_id() if is_instance_valid(resident["actor"]) else 0)
	var source: Dictionary=doc.data.duplicate(true)
	if "--packages" in OS.get_cmdline_user_args():
		var exporter=preload("res://scripts/builder/portable_export.gd").new()
		var package: Dictionary=exporter.save(world,doc.data,studio.library,output+"/school_"+mode+".zip")
		check(package["ok"],"The school and native bus can be packaged from normal authored source: "+mode+" "+str(package.get("message","")))
		if "--package-only" in OS.get_cmdline_user_args(): return
	withdrawn_bus_check(citizens,bus,stops,mode)
	var late: bool=false
	var occupied: bool=false
	var wait_for_seat: bool=false
	var capacity_ok: bool=true
	var arrived: bool=false
	var bus_id: int=0
	if "--trace" in OS.get_cmdline_user_args():
		var first: Dictionary=citizens.residents[0]
		var source_point: Vector2=bus.actor_point(first["actor"])
		var target: Vector2=citizens.schools.sites[building["uid"]]["point"]
		var rendered: Array=preload("res://scripts/builder/citizen_plan.gd").world(target,mode)
		var to: Vector2=Traffic.metric(rendered,mode)
		var itinerary: Dictionary=Transit.school_journey(bus.passengers.plan,source_point,to,bus.elapsed,bus.helper.obstacles,"school_line",stops[0],stops[1],School.bus_asset(mode))
		var stop_a: Vector2=bus.passengers.plan["stops"][stops[0]]["platform"]
		var stop_b: Vector2=bus.passengers.plan["stops"][stops[1]]["platform"]
		print("SCHOOL TRIP ",mode," ",source_point," to ",to," ",itinerary.get("reason","bookable"),
			" access ",Transit.walking(source_point,stop_a,bus.helper.obstacles).get("reason","ok"),
			" egress ",Transit.walking(stop_b,to,bus.helper.obstacles).get("reason","ok")," ",stop_a," ",stop_b)
	for frame in 20000:
		await sample(citizens,bus)
		if frame%900==0 and "--trace" in OS.get_cmdline_user_args():
			print("SCHOOL RIDE ",mode," ",frame," ",bus.elapsed," ",states(citizens)," ",bus.passengers.jobs.map(func(job: Dictionary)->Array:return [job["state"],job["reason"]])," ",bus.buses.values().map(func(entry: Dictionary)->String:return entry["status"]))
		for entry in bus.buses.values():
			var vehicle: Dictionary=entry["vehicle"]
			var rider: Dictionary=bus.passengers.vehicles[vehicle["id"]]
			capacity_ok=capacity_ok and rider["manifest"].size()+rider["reserved"].size()<=1
			if not rider["manifest"].is_empty():
				occupied=occupied or vehicle["asset"]==School.bus_asset(mode)
				bus_id=vehicle["actor"].get_instance_id()
				wait_for_seat=wait_for_seat or bus.passengers.jobs.any(func(job: Dictionary)->bool:return job["state"]=="waiting")
		late=late or citizens.hour>=8.25 and seated(citizens)==0 and citizens.schools.attendance.is_empty() and not citizens.schools.trips.is_empty()
		if seated(citizens)==2:
			arrived=true
			break
	check(late and occupied and wait_for_seat and capacity_ok,"A late bus grants no attendance and its one-seat limit queues the other rider: "+mode+" "+str([late,occupied,wait_for_seat,capacity_ok]))
	check(arrived and bus.passengers.completed==2 and citizens.residents.map(func(resident: Dictionary)->int:return resident["actor"].get_instance_id())==ids,"Both original pupils alight and walk to actual desks: "+mode+" "+str([citizens.hour,states(citizens),bus.passengers.jobs.map(func(job: Dictionary)->Array:return [job["state"],job["reason"]]),bus.summary()]))
	if not arrived: return
	citizens.hour=15.0
	var back: bool=false
	for frame in 24000:
		await sample(citizens,bus)
		if bus.passengers.completed==4 and citizens.schools.trips.is_empty() and citizens.residents.all(func(pupil: Dictionary)->bool:return pupil["status"].begins_with("At home")):
			back=true
			break
	check(back and citizens.activities.scheduler.reservations.entries.is_empty() and bus.passengers.vehicles.values().all(func(v: Dictionary)->bool:return v["manifest"].is_empty() and v["reserved"].is_empty()),"Dismissal releases desks and completes both safe return rides: "+mode+" "+str([states(citizens),bus.summary()]))
	check(doc.data==source and bus_id>0 and citizens.residents.map(func(resident: Dictionary)->int:return resident["actor"].get_instance_id())==ids,"The school-day transit handoff preserves authored data and actor identity: "+mode)

func run() -> void:
	if OS.has_environment("ISOCITY_SCHOOL_OUTPUT"): output=OS.get_environment("ISOCITY_SCHOOL_OUTPUT")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	studio=load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled=false
	root.add_child(studio)
	await settle()
	if studio.consumer_shell: studio.consumer_shell.dismiss_welcome()
	for mode in ["2d","3d"]: await transport_city(mode)
	studio.free()
	await settle()
	print("SCHOOL BUS: %d checks, %d failures"%[count,failures])
	quit(1 if failures else 0)
