extends SceneTree

const Plan=preload("res://scripts/builder/traffic_plan.gd")
const Queue=preload("res://scripts/builder/traffic_route_queue.gd")
const Service=preload("res://scripts/builder/service_plan.gd")
const Repair=preload("res://scripts/builder/project_repair.gd")
const Entrance=preload("res://scripts/builder/entrance_anchors.gd")
const Doc=preload("res://scripts/builder/document.gd")
const Templates=preload("res://scripts/builder/templates.gd")
const SAMPLE_LIMIT=.09
var studio: Control
var checks: int=0
var failures: int=0
var output: String="res://output/reroute_fixture"

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		print("FAIL: "+message)

func settle() -> void:
	for frame in 8: await process_frame
	await physics_frame

func queue_checks() -> void:
	var data: Dictionary={"mode":"3d","roads":[]}
	for x in range(96): data["roads"].append({"cell":[x,0]})
	var from_json: Dictionary=JSON.parse_string(JSON.stringify(data))
	Plan.Roads.paint(from_json,Vector2i(2,0),Vector2i(2,0),true)
	check(not Plan.Roads.lookup(from_json).has("2,0") and from_json["roads"].size()==95,"Road edits match grid coordinates after JSON restores numeric values.")
	var graph: Dictionary=Plan.build(data)
	var empty: Array[Rect2]=[]
	var worker:=Queue.new()
	check(worker.configure(graph,empty) and worker.revision==1,"The first lane graph has a revision.")
	var one: int=worker.request("one","0,0","",{"95,0":[]},{})
	var two: int=worker.request("two","95,0","",{"0,0":[]},{})
	worker.step(2,100000)
	check(worker.expanded==2 and worker.requests["one"]["cursor"]==1 and worker.requests["two"]["cursor"]==1,"Node expansion is bounded and active requests rotate fairly.")
	check(worker.take("one",one).is_empty() and worker.take("two",two).is_empty(),"Neither incomplete route can be consumed.")
	check(not worker.configure(Plan.build(data),empty) and worker.requests.size()==2,"Equivalent topology preserves in-flight requests.")
	var remote: Array[Rect2]=[Rect2(Vector2(40,200),Vector2(1,6))]
	check(not worker.configure(graph,remote) and worker.requests.size()==2,"An obstacle outside the road and its approaches keeps the current revision and requests.")
	var blocked: Array[Rect2]=[Rect2(Vector2(40,-3),Vector2(1,6))]
	check(worker.configure(graph,blocked) and worker.revision==2 and worker.order.is_empty(),"New obstruction geometry invalidates the old revision and its requests.")
	var denied: int=worker.request("one","0,0","",{"95,0":[]},{})
	for tick in 16: worker.step(48,100000)
	var result: Dictionary=worker.take("one",denied)
	check(result.has("route") and result["route"].is_empty(),"The directed search cannot pass a swept-body obstruction.")
	check(worker.take("one",one).is_empty(),"Superseded work cannot be accepted by the same actor.")
	check(worker.configure(graph,empty),"Removing the obstruction publishes another revision.")
	var restored: int=worker.request("one","0,0","",{"95,0":["94,0"]},{})
	for tick in 32: worker.step(48,100000)
	result=worker.take("one",restored)
	check(result.get("route",[]).size()==96 and result["id"]==restored and result["revision"]==worker.revision,"Recovered routes retain their request identity and exact final approach.")
	check(worker.take("one",restored).is_empty() and worker.requests.is_empty(),"A consumed result cannot be applied twice.")
	var profile: Dictionary=Plan.Fleet.definitions()["3d:HanX_Traffic/Truck_Box"]
	var narrow: Dictionary={"mode":"3d","roads":[{"cell":[0,0],"width":2},{"cell":[1,0],"width":2},{"cell":[1,1],"width":2}]}
	worker.configure(Plan.build(narrow),empty)
	var denied_truck: int=worker.request("truck","0,0","",{"1,1":[]},profile)
	worker.step(32,100000)
	check(worker.take("truck",denied_truck)["route"].is_empty(),"The queue uses actual vehicle width and turning limits.")

func stress_queue() -> void:
	var data: Dictionary={"mode":"3d","roads":[]}
	for x in 64:
		for y in 64: data["roads"].append({"cell":[x,y]})
	var graph: Dictionary=Plan.build(data)
	var boxes: Array[Rect2]=[]
	var queue:=Queue.new()
	queue.configure(graph,boxes)
	var requests: Dictionary={}
	for actor in 64:
		var key: String=str(actor)
		var at: String="%d,%d"%[actor%48,actor/16*12+2]
		var goal: String="%d,%d"%[actor%48+6,actor/16*12+2]
		requests[key]=queue.request(key,at,"",{goal:[]},{})
	var samples: Array[int]=[]
	var bounded: bool=true
	while not queue.order.is_empty() and samples.size()<4000:
		var started: int=Time.get_ticks_usec()
		queue.step()
		samples.append(Time.get_ticks_usec()-started)
		bounded=bounded and queue.expanded<=Queue.MAX_EXPANSIONS
	var found: int=0
	for key in requests:
		var result: Dictionary=queue.take(key,requests[key])
		if result.get("route",[]).size()==7: found+=1
	samples.sort()
	print("REROUTE SCHEDULER: %d roads, %d directed edges, %d completed searches, %d frames, median %d us, p95 %d us" % [
		graph["sections"].size(),graph["edges"].size(),found,samples.size(),samples[samples.size()/2],samples[floori(samples.size()*.95)]])
	check(bounded and found==64 and queue.order.is_empty() and queue.completed.is_empty(),"A full 4,096-road graph serves 64 concurrent local requests within the work limit.")

func fixture(mode: String) -> Dictionary:
	var data: Dictionary=Templates.make(mode,"blank")
	data["roads"]=[]
	for x in range(-1,6): data["roads"].append({"cell":[x,0]})
	for x in range(1,4): data["roads"].append({"cell":[x,1]})
	data["traffic"]={"enabled":true,"population":1,"seed":8,"speed":4,"parking_seconds":8}
	var parking: String="2d:Parking_Accessible" if mode=="2d" else "3d:HanX_Traffic/Road_Parking"
	var size: float=2 if mode=="2d" else .5
	var direction: String="SE" if mode=="2d" else "0"
	var offset: Vector2=Plan.Roads.center_offset(studio.library,parking,direction,size,mode)*(2 if mode=="2d" else 1)
	var point: Vector2=Plan.center(Vector2i(4,0),mode)+Vector2(0,5.5)
	data["objects"].append({"asset":parking,"uid":"bay","position":Plan.world(point-offset,mode),"scale":size,"direction":direction,"traffic_parking":true})
	return data

func edit_road(doc: RefCounted,cell: Vector2i,erase: bool=true) -> void:
	doc.checkpoint()
	Plan.Roads.paint(doc.data,cell,cell,erase)
	studio.changed()
	doc.finish_checkpoint()

func capture(mode: String,kind: String,point: Vector2) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	var world: Node=studio.worlds[mode]
	var position: Array=Plan.world(point,mode)
	var compact_simple: bool=studio.consumer_shell and studio.consumer_shell.active
	studio._command(kind,null)
	var controls: RefCounted={"traffic":studio.traffic_tools,"transit":studio.transit_tools,"services":studio.service_tools}[kind]
	controls.elapsed=.4
	for size in [Vector2i(1480,900),Vector2i(960,640)]:
		root.size=size
		studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true} if size.x==960 else {})
		if size.x==960: studio.workspace_layout.library_toggle.button_pressed=false
		if mode=="2d":
			world.camera.position=Vector2(position[0]+(150 if size.x==960 and compact_simple else 0),position[1])
			world.camera.zoom=Vector2.ONE*1.4
		else:
			world.target=Vector3(position[0],0,position[2])
			world.distance=26
			if size.x==960 and compact_simple: world.target+=world.camera.global_basis.x*6
			world.update_camera()
		await settle()
		RenderingServer.force_draw(false)
		RenderingServer.force_draw(false)
		check(root.get_texture().get_image().save_png(output+"/%s_%s_%d.png"%[kind,mode,size.x])==OK,"Captured the live journey inspector: "+kind+" "+mode+" "+str(size))
		controls.paused.grab_focus()
		await settle()
		var focused: Rect2=controls.paused.get_global_rect()
		check(controls.paused.has_focus() and Rect2(Vector2.ZERO,Vector2(size)).encloses(focused),"Keyboard focus scrolls the pause control fully into the current window: "+kind+" "+str(size))
		controls.paused.release_focus()
	root.size=Vector2i(1480,900)
	studio.accessibility_settings.restore({})
	await settle()

func drive_until(manager: Node,vehicle: Dictionary,condition: Callable,frames: int=6000) -> Dictionary:
	var continuous: bool=true
	for frame in frames:
		if condition.call(): return {"arrived":true,"continuous":continuous}
		var previous: Vector2=vehicle["point"]
		manager.step(1.0/60)
		continuous=continuous and previous.distance_to(vehicle["point"])<SAMPLE_LIMIT
	return {"arrived":condition.call(),"continuous":continuous}

func position_car(manager: Node,vehicle: Dictionary) -> Dictionary:
	var incoming: Dictionary=manager.plan["edges"]["0,0>1,0"]
	manager.release_bay(vehicle)
	vehicle["from"]="0,0"
	vehicle["to"]="1,0"
	manager.set_path(vehicle,incoming["points"],"edge")
	vehicle["distance"]=incoming["length"]*.3
	var start: Dictionary=Plan.sample(vehicle["path"],vehicle["distance"])
	vehicle["point"]=start["point"]
	vehicle["heading"]=start["heading"]
	manager.pose(vehicle)
	manager.choose_bay(vehicle)
	return incoming

func live(mode: String) -> void:
	studio.switch_mode(mode)
	var doc:=Doc.new()
	doc.data=fixture(mode)
	studio.documents[mode]=doc
	studio.changed()
	await settle()
	var manager: Node=studio.traffic_tools.managers[mode]
	manager.set_physics_process(false)
	if "--packages" in OS.get_cmdline_user_args():
		var archive: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(studio.worlds[mode],doc.data,studio.library,output+"/reroute_"+mode+".zip")
		check(archive["ok"],"The allowed road and parking fixture packages with its dependencies: "+mode+" "+str(archive.get("reason","")))
	check(manager.vehicles.size()==1 and manager.bays.has("bay"),"A real car and reserved route fixture spawn: "+mode)
	if manager.vehicles.size()!=1 or not manager.bays.has("bay"): return
	var vehicle: Dictionary=manager.vehicles[0]
	var actor_id: int=vehicle["actor"].get_instance_id()
	var incoming: Dictionary=position_car(manager,vehicle)
	check(vehicle["bay"]=="bay","The live car has a reservation beyond the direct road.")
	var point: Vector2=vehicle["point"]
	var revision: int=manager.route_queue.revision
	var previous_sections: Dictionary=manager.plan["sections"]
	doc.object("bay")["name"]="Renamed parking"
	studio.changed()
	await settle()
	check(manager.route_queue.revision==revision and is_same(manager.plan["sections"],previous_sections) and vehicle["point"]==point and vehicle["bay"]=="bay","A rename preserves the graph object, revision, route and bay claim.")
	edit_road(doc,Vector2i(2,0))
	await settle()
	var request: int=vehicle.get("route_request",0)
	check(manager.route_queue.revision==revision+1 and request>0 and vehicle["point"]==point and vehicle["phase"]=="edge" and vehicle["path"]==incoming["points"],"Removing the road ahead queues a detour and preserves the valid current segment.")
	if request==0: return
	manager.route_queue.step(1,100000)
	edit_road(doc,Vector2i(2,1))
	await settle()
	var second: int=vehicle.get("route_request",0)
	check(second>request and manager.route_queue.take(vehicle["id"],request).is_empty(),"A second edit replaces the active request and invalidates its partial result.")
	studio._command("undo",null)
	await settle()
	check(vehicle.get("route_request",0)>second and vehicle["point"]==point,"Undo publishes a fresh detour for the unchanged actor position.")
	var detoured: Dictionary=drive_until(manager,vehicle,func():return "2,1" in vehicle["sections"])
	check(detoured["arrived"] and detoured["continuous"] and vehicle["actor"].get_instance_id()==actor_id and not "2,0" in vehicle["sections"],"The same actor physically uses the alternate road without a jump: "+mode+" "+str([vehicle["status"],vehicle["sections"]]))
	if not detoured["arrived"]: return
	var path: String=output+"/edited_"+mode+".isocity.json"
	var authored: Dictionary=doc.data.duplicate(true)
	check(studio.write_project(path,false),"Normal save writes the actual edited city: "+mode)
	var repair:=Repair.new(studio.library)
	var reopened: Dictionary=repair.read(path)
	var raw: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	var loaded: Dictionary=reopened.get("content",{}).get("documents",{}).get(mode,{})
	var raw_authored: Dictionary=JSON.parse_string(JSON.stringify(authored))
	check(raw.get("documents",{}).get(mode,{})==raw_authored and not raw_authored.has("route_request"),"The saved document retains the exact authored city and excludes live routing: "+mode)
	check(reopened["ok"] and repair.issues.is_empty() and Plan.build(loaded)["edges"]==Plan.build(authored)["edges"] and Plan.settings(loaded)==Plan.settings(authored) and loaded["objects"][0]["position"]==raw_authored["objects"][0]["position"] and loaded["objects"][0]["traffic_parking"],"Reopening preserves the road graph and original parking transform: "+mode+" "+str(repair.issues))
	await capture(mode,"traffic",vehicle["point"])
	var parked: Dictionary=drive_until(manager,vehicle,func():return vehicle["phase"]=="parked")
	check(parked["arrived"] and parked["continuous"] and manager.bay_owners.get("bay")==vehicle["id"],"The detour keeps the original reachable parking destination.")
	if not parked["arrived"]: return
	point=vehicle["point"]
	doc.checkpoint()
	doc.object("bay")["position"][0]+=160
	studio.changed()
	doc.finish_checkpoint()
	await settle()
	check(vehicle["point"]==point and vehicle["phase"]=="parking_out" and manager.bay_owners.is_empty(),"Moving the parked bay keeps the car in place and releases the obsolete reservation.")
	var left: Dictionary=drive_until(manager,vehicle,func():return vehicle["phase"]=="edge" and vehicle["to"]!="4,0")
	check(left["arrived"] and left["continuous"] and vehicle["actor"].get_instance_id()==actor_id,"The parked car reverses onto the connected road with the same actor.")
	if not left["arrived"]: return
	var occupied_cell: Vector2i=manager.plan["sections"][vehicle["to"]]["cell"]
	point=vehicle["point"]
	var stationary_before: int=manager.route_queue.serial
	edit_road(doc,occupied_cell)
	await settle()
	check(vehicle["phase"]=="blocked" and vehicle["point"]==point and vehicle["status"].contains("safe road") and manager.gates.owners.is_empty() and manager.bay_owners.is_empty(),"A deleted current lane holds the exact pose and clears obsolete claims.")
	for frame in 90: manager.step(1.0/60)
	check(vehicle["point"]==point and manager.route_queue.serial==stationary_before,"A disconnected car cannot jump across a gap or keep retrying on the same revision.")
	studio._command("undo",null)
	await settle()
	check(vehicle["phase"]!="blocked" and vehicle["point"]==point and vehicle["actor"].get_instance_id()==actor_id,"Restoring the lane revives the same actor from the same point.")
	manager.active=false
	var pending: int=manager.route_queue.order.size()
	manager.step(.25)
	check(vehicle["point"]==point and manager.route_queue.order.size()==pending,"A hidden world consumes no route work or motion.")
	manager.active=true
	manager.step(.25)
	check(vehicle["point"]!=point,"The restored vehicle continues under normal physics.")
	manager.reset()
	check(manager.route_queue.requests.is_empty() and manager.route_queue.completed.is_empty() and manager.gates.owners.is_empty() and manager.bay_owners.is_empty(),"Runtime reset clears searches, junctions and bays.")

func transit_fixture(mode: String) -> void:
	studio.switch_mode(mode)
	var doc:=Doc.new()
	doc.data=Templates.make(mode,"blank")
	doc.data["objects"]=[]
	doc.data["roads"]=[]
	for x in range(-4,13): doc.data["roads"].append({"cell":[x,0]})
	for x in range(2,7): doc.data["roads"].append({"cell":[x,-1]})
	for index in 2:
		var asset: String="2d:Bus_Stop_Sign" if mode=="2d" else "3d:HanX_Traffic/Bus_Stop"
		var point: Vector2=Plan.center(Vector2i(index*8,0),mode)+Vector2(0,8)
		var item: Dictionary=doc.add(asset,Plan.world(point,mode),studio.library.directions(asset)[0])
		item["uid"]="stop_"+str(index)
	doc.data["transit"]={"enabled":true,"automatic":false}
	doc.data["transit_lines"]=[{"uid":"connector","stops":["stop_0","stop_1"],"headway":240,"capacity":2}]
	studio.documents[mode]=doc
	studio.changed()
	await settle()
	var manager: Node=studio.transit_tools.managers[mode]
	manager.set_physics_process(false)
	var stops: Dictionary=manager.passengers.plan["stops"]
	check(manager.passengers.plan["lines"].has("connector") and stops.size()==2,"The real stops and line compile: "+mode)
	if not manager.passengers.plan["lines"].has("connector"): return
	var a: Dictionary=stops["stop_0"]
	var b: Dictionary=stops["stop_1"]
	var request: Dictionary=manager.request(a["platform"]+a["right"]*2,b["platform"]+b["right"]*2)
	check(request["ok"],"A passenger can book the physical connection: "+mode)
	if not request["ok"]: return
	var job: Dictionary=request["job"]
	var entry: Dictionary={}
	for frame in 6000:
		manager.step(1.0/60)
		if job["state"]=="onboard":
			entry=manager.buses[job["vehicle"]]
			var piece: Dictionary=entry["segments"][entry["segment"]] if entry["segment"]<entry["segments"].size() else {}
			if piece.get("lane",[])==["1,0","2,0"] and piece["kind"]=="edge" and entry["distance"]>.1: break
			entry={}
	check(not entry.is_empty(),"The passenger boards and the bus reaches the road before the closure: "+mode)
	if entry.is_empty(): return
	var vehicle: Dictionary=entry["vehicle"]
	var bus: Dictionary=manager.passengers.vehicles[vehicle["id"]]
	var actor_id: int=vehicle["actor"].get_instance_id()
	var point: Vector2=vehicle["point"]
	var destination: String=bus["next"]
	var layout_revision: int=manager.route_queue.revision
	var pieces: Array=entry["segments"]
	doc.object("stop_1")["name"]="Renamed platform"
	studio.changed()
	await settle()
	check(manager.route_queue.revision==layout_revision and is_same(entry["segments"],pieces) and bus["manifest"]==[job["id"]],"A platform rename retains the occupied bus's exact route and manifest: "+mode)
	doc.checkpoint()
	doc.data["objects"].erase(doc.object("stop_1"))
	studio.changed()
	doc.finish_checkpoint()
	await settle()
	check(vehicle["point"]==point and bus["manifest"]==[job["id"]] and not entry.has("route_request"),"Removing the destination platform holds the rider with the original bus and books no arrival: "+mode)
	studio._command("undo",null)
	await settle()
	check(vehicle["point"]==point and not entry.has("route_boundary") and bus["next"]==destination,"Undo restores the original next stop and safe trip: "+mode)
	edit_road(doc,Vector2i(4,0))
	await settle()
	var first: int=entry.get("route_request",{}).get("id",0)
	check(first>0 and point==vehicle["point"] and bus["phase"]=="moving" and bus["next"]==destination,"The occupied bus keeps the valid current lane while a route is queued: "+mode)
	if first==0: return
	edit_road(doc,Vector2i(4,-1))
	await settle()
	check(manager.route_queue.take(vehicle["id"],first).is_empty(),"A second road edit discards the old bus request: "+mode)
	var continuous: bool=true
	for frame in 600:
		var last: Vector2=vehicle["point"]
		manager.step(1.0/60)
		continuous=continuous and last.distance_to(vehicle["point"])<.16
		if bus["phase"]=="blocked": break
	point=vehicle["point"]
	await capture(mode,"transit",point)
	check(bus["phase"]=="blocked" and continuous and entry["status"].contains("unreachable") and bus["manifest"]==[job["id"]] and job["state"]=="onboard","The bus finishes its safe lane, stops with the same manifest and reports the disconnect: "+mode+str(entry["status"]))
	var revision: int=manager.route_queue.serial
	for frame in 30: manager.step(1.0/60)
	check(vehicle["point"]==point and manager.route_queue.serial==revision and manager.passengers.completed==0,"The disconnected bus stays at the stop line without retries or arrival credit: "+mode)
	studio._command("undo",null)
	await settle()
	check(vehicle["point"]==point and vehicle["actor"].get_instance_id()==actor_id and bus["manifest"]==[job["id"]],"Undo preserves the bus actor, its pose and its rider: "+mode)
	if mode=="3d":
		doc.data["transit_lines"][0]["headway"]=10
		doc.data["transit"]["speed"]=2
		studio.changed()
		await settle()
		check(manager.passengers.plan["lines"].is_empty() and not manager.passengers.plan["route_stops"].is_empty() and bus["manifest"]==[job["id"]],"A timetable that cannot start a new fleet still allows the occupied bus to reach its existing stop.")
	var alternate: bool=false
	var reached_dock: bool=false
	for frame in 9000:
		var last: Vector2=vehicle["point"]
		manager.step(1.0/60)
		continuous=continuous and last.distance_to(vehicle["point"])<.16
		var piece: Dictionary=entry["segments"][entry["segment"]] if entry["segment"]<entry["segments"].size() else {}
		alternate=alternate or piece.get("lane",[])==["3,-1","4,-1"]
		reached_dock=reached_dock or job["state"]=="alighting" and bus["stop"]==destination and vehicle["point"].distance_to(b["dock"])<.001
		if job["state"] in ["complete","blocked","cancelled"]: break
	check(continuous and alternate and vehicle["actor"].get_instance_id()==actor_id and reached_dock,"The same bus drives the restored detour without jumping: "+mode+str([entry["status"],vehicle["point"]]))
	check(job["state"]=="complete" and manager.passengers.completed==1 and bus["manifest"].is_empty(),"The passenger alights at the original destination and earns exactly one arrival: "+mode+str(job["state"]))

func service_fixture(mode: String) -> void:
	studio.switch_mode(mode)
	var doc:=Doc.new()
	doc.data=Templates.make(mode,"blank")
	doc.data["objects"]=[]
	doc.data["roads"]=[]
	for x in range(-4,10): doc.data["roads"].append({"cell":[x,0]})
	for x in range(1,5): doc.data["roads"].append({"cell":[x,-1]})
	Service.load_catalog()
	var station_asset: String=""
	for id in Service.catalog["stations"]:
		if Service.catalog["stations"][id]=="medical" and id.begins_with(mode+":"): station_asset=id; break
	if station_asset.is_empty():
		for id in Service.catalog["stations"]:
			if Service.catalog["stations"][id]=="medical": station_asset=id; break
	var station: Dictionary=doc.add(station_asset,Plan.world(Vector2(-24,-10),mode),studio.library.directions(station_asset)[0],studio.library.assets[station_asset]["data"].get("default_scale",1.0))
	station["city_service"]={"kind":"medical","radius":160,"units":1,"task_seconds":2}
	var target: Dictionary=doc.add("2d:House_Blue" if mode=="2d" else "3d:HanX_City/Row_Houses_A",Plan.world(Vector2(56,10),mode),"SE" if mode=="2d" else "180")
	doc.data["services"]={"enabled":true,"automatic":false}
	studio.documents[mode]=doc
	studio.changed()
	await settle()
	var world: Node=studio.worlds[mode]
	for desired in [[station,Vector2(-24,-10)],[target,Vector2(56,10)]]:
		var item: Dictionary=desired[0]
		var entrance: Variant=Entrance.position_for(world.instances[item["uid"]],item,mode,studio.library)
		var actual: Vector2=Plan.metric([entrance.x,entrance.y,0] if mode=="2d" else [entrance.x,entrance.y,entrance.z],mode)
		item["position"]=Plan.world(Plan.metric(item["position"],mode)+desired[1]-actual,mode)
	studio.changed()
	await settle()
	var manager: Node=studio.service_tools.managers[mode]
	manager.set_physics_process(false)
	var request: Dictionary=manager.dispatch.request("medical",target["uid"])
	check(request["ok"],"The actual service station can dispatch to the fixture target: "+mode)
	if not request["ok"]: return
	var job: Dictionary=request["job"]
	var crew: Dictionary={}
	for frame in 3500:
		manager.step(1.0/60)
		if not manager.crews.has(job["id"]): continue
		var active: Dictionary=manager.crews[job["id"]]
		var segment: Dictionary=active["segments"][active["segment"]] if active["segment"]<active["segments"].size() else {}
		if segment.get("kind")=="edge" and segment["lane"]==["0,0","1,0"] and active["distance"]>.1:
			crew=active
			break
	check(not crew.is_empty(),"The assigned crew reaches the road before the edited section: "+mode+" "+str(job["reason"]))
	if crew.is_empty(): return
	var vehicle: Dictionary=crew["vehicle"]
	var actor_id: int=vehicle["actor"].get_instance_id()
	var worker_id: int=crew["worker"].get_instance_id()
	var point: Vector2=vehicle["point"]
	var unit: String=job["unit"]
	var target_id: String=job["target"]
	doc.checkpoint()
	doc.data["objects"].erase(target)
	studio.changed()
	doc.finish_checkpoint()
	await settle()
	check(job["state"]=="blocked" and vehicle["point"]==point and not manager.target_owners.has(target_id) and manager.dispatch.history.is_empty(),"Removing the target releases the obsolete claim and preserves the actual crew and job: "+mode)
	studio._command("undo",null)
	await settle()
	check(job["state"]=="outbound" and manager.target_owners.get(target_id)==job["id"] and vehicle["point"]==point,"Undo restores the same assigned target and physical crew: "+mode)
	edit_road(doc,Vector2i(2,0))
	await settle()
	var first: int=crew.get("route_request",{}).get("id",0)
	check(first>0 and vehicle["point"]==point and job["state"]=="outbound","A road closure queues an alternate route and keeps the assigned crew driving its current lane: "+mode)
	if first==0: return
	edit_road(doc,Vector2i(2,-1))
	await settle()
	check(manager.route_queue.take(vehicle["id"],first).is_empty(),"The second edit makes the former service request stale: "+mode)
	var continuous: bool=true
	for frame in 800:
		var last: Vector2=vehicle["point"]
		manager.step(1.0/60)
		continuous=continuous and last.distance_to(vehicle["point"])<.16
		if job["state"]=="blocked": break
	point=vehicle["point"]
	await capture(mode,"services",point)
	check(job["state"]=="blocked" and continuous and job["reason"].contains("unreachable") and job["unit"]==unit and manager.dispatch.history.is_empty(),"The disconnected crew holds at its safe anchor with the same job and no work credit: "+mode+" "+str(job["reason"]))
	var serial: int=manager.route_queue.serial
	for frame in 30: manager.step(1.0/60)
	check(vehicle["point"]==point and manager.route_queue.serial==serial,"The service actor waits without duplicate requests or a jump: "+mode)
	studio._command("undo",null)
	await settle()
	check(vehicle["point"]==point and vehicle["actor"].get_instance_id()==actor_id and is_same(manager.crews[job["id"]]["job"],job),"Undo keeps the same crew and actual position: "+mode)
	var alternate: bool=false
	var returning: bool=false
	for frame in 12000:
		var last: Vector2=vehicle["point"]
		manager.step(1.0/60)
		continuous=continuous and last.distance_to(vehicle["point"])<.16
		var segment: Dictionary=crew["segments"][crew["segment"]] if crew["segment"]<crew["segments"].size() else {}
		alternate=alternate or crew["stage"]=="outbound" and segment.get("lane",[])==["1,-1","2,-1"]
		returning=returning or crew["stage"]=="returning" and segment.get("lane",[])==["2,-1","1,-1"]
		if job["state"] in ["complete","blocked","cancelled"]: break
	check(alternate and continuous and vehicle["actor"].get_instance_id()==actor_id and crew["worker"].get_instance_id()==worker_id,"The same service crew drives the restored detour continuously: "+mode+" "+str([job["reason"],vehicle["point"]]))
	check(job["state"]=="complete" and job["target"]==target_id and job["fulfilled"] and manager.dispatch.history.size()==1 and manager.dispatch.units.is_empty() and manager.target_owners.is_empty(),"One visit to the original target is fulfilled and the unit returns to the original station: "+mode+" "+str(job["reason"]))
	check(returning and vehicle["point"].distance_to(crew["home"])<.4,"The return uses the alternate road and reaches the original garage: "+mode)

func run() -> void:
	if OS.has_environment("ISOCITY_REROUTE_OUTPUT"): output=OS.get_environment("ISOCITY_REROUTE_OUTPUT")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	queue_checks()
	if "--stress" in OS.get_cmdline_user_args(): stress_queue()
	studio=load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled=false
	root.add_child(studio)
	await settle()
	if studio.consumer_shell: studio.consumer_shell.dismiss_welcome()
	for mode in ["2d","3d"]:
		await live(mode)
		await transit_fixture(mode)
		await service_fixture(mode)
	studio.free()
	await settle()
	print("TRAFFIC REROUTE: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
