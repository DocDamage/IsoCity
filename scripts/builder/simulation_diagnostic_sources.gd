extends RefCounted

const Common=preload("res://scripts/builder/simulation_diagnostics.gd")
const Traffic=preload("res://scripts/builder/traffic_plan.gd")
const Walking=preload("res://scripts/builder/resident_activity_plan.gd")
const Setup=preload("res://scripts/builder/interaction_setup_plan.gd")
const Zone=preload("res://scripts/builder/zone_plan.gd")
const Layers=preload("res://scripts/builder/layers.gd")
var studio: Control
var world: Node
var mode: String
var scope: String
var revision: String
var document: RefCounted
var objects: Dictionary={}
var rows: Array[Dictionary]=[]
var shapes: int=0
var points: int=0
var limited: bool=false

func _init(editor: Control,scope_key: String,epoch: int) -> void:
	studio=editor
	mode=studio.mode
	world=studio.worlds[mode]
	scope=scope_key
	revision=str(epoch)
	document=studio.current()
	for item in document.data["objects"]: objects[item["uid"]]=item

func collect(kind: String,fixture_report: Dictionary={}) -> Dictionary:
	var interior: bool=studio.interior_tools.editing() or world.exploration.interior!=null or document.data.get("interior_room",false)
	if interior and kind!="fixtures":
		row("exterior","info","","","Exterior simulation","Return to the city to see this overlay.")
	else:
		match kind:
			"traffic": traffic()
			"transit": transit()
			"services": services()
			"water","power": utility(kind)
			"residents": residents()
			"fixtures": fixtures(fixture_report)
			"zoning": zoning()
			"challenges": challenges()
			"deliveries": deliveries()
			"vehicle_care": vehicle_care()
			"businesses": businesses()
			"markets": markets()
	return {"rows":rows,"shapes":shapes,"points":points,"limited":limited}

func row(code: String,severity: String,uid: String,entity: String,title: String,message: String,related: Array=[],fields: Dictionary={}) -> Dictionary:
	if rows.size()>=Common.MAX_ROWS:
		limited=true
		return {}
	var details: Dictionary={"title":title,"entity":entity,"geometry":[]}
	details.merge(fields)
	var result: Dictionary=Common.record(code,severity,scope,uid,related,message,revision,details)
	rows.append(result)
	return result

func ground_point(at: Vector2,walking_units: bool=false) -> Vector3:
	var metric: Vector2=Vector2(at.x+at.y,at.y-at.x) if walking_units and mode=="2d" else at
	var height: float=.10
	if world.terrain_traversal.active(): height+=world.terrain_traversal.sample_at(metric)["height"]
	var values: Array=Traffic.world(metric,mode,height)
	return Vector3(values[0],values[1],values[2])

func object_title(uid: String) -> String:
	var item: Dictionary=objects.get(uid,{})
	return item.get("name",studio.library.assets.get(item.get("asset",""),{}).get("name",uid)).replace("_"," ")

func object_pin(result: Dictionary,uid: String,label: String="") -> void:
	if result.is_empty() or not objects.has(uid): return
	var item: Dictionary=objects[uid]
	if not item.get("visible",true) or not Layers.shown(document.data,Layers.layer(item,studio.library)): return
	pin(result,ground_point(Traffic.metric(item["position"],mode)),label)

func available_shape(result: Dictionary,count: int) -> bool:
	if result.is_empty(): return false
	if shapes>=Common.MAX_SHAPES or points+count>Common.MAX_POINTS:
		limited=true
		return false
	return true

func pin(result: Dictionary,at: Vector3,label: String="",style: String="pin") -> void:
	if not at.is_finite() or not available_shape(result,1): return
	if not result["details"].has("anchor"): result["details"]["anchor"]=at
	result["details"]["geometry"].append({"kind":style,"points":PackedVector3Array([at]),"label":label})
	shapes+=1
	points+=1

func path(result: Dictionary,line: PackedVector2Array,style: String="lane",first: int=0) -> void:
	if line.size()-first<2 or not available_shape(result,2): return
	var length: int=mini(line.size()-first,Common.MAX_POINTS-points)
	if length<line.size()-first: limited=true
	var locations:=PackedVector3Array()
	for index in range(first,first+length):
		if not line[index].is_finite(): return
		locations.append(ground_point(line[index],style=="walk"))
	if not result["details"].has("anchor"): result["details"]["anchor"]=locations[0]
	result["details"]["geometry"].append({"kind":style,"points":locations})
	shapes+=1
	points+=locations.size()

func wait(title: String) -> void:
	row("rebuilding","pending","","",title,"Waiting for the current simulation plan.")

func utility(kind: String) -> void:
	var tools: RefCounted=studio.power_tools if kind=="power" else studio.utility_tools
	var runtime: Node=tools.manager()
	var graph: Dictionary=runtime.graph
	if graph.is_empty(): return
	var title: String=kind.capitalize()
	if not graph["enabled"]: row(kind+"_off","info","","",title+" simulation off","Enable "+kind+" in its network panel to run the connected network.")
	var preview: Dictionary=tools.preview()
	if not preview.is_empty():
		var reason: String=preview["reason"]
		row(kind+"_candidate","pending" if reason.is_empty() else "warning","","","Candidate "+tools.run_name,
			"Connect the two marked ports." if reason.is_empty() else reason)
	for uid in graph["nodes"]:
		var node: Dictionary=graph["nodes"][uid]
		var severity: String="ok" if graph["enabled"] else "info"
		if not node["reason"].is_empty(): severity="warning"
		elif graph["enabled"] and node["role"]=="consumer" and runtime.served(uid)<node["quantity"]:
			severity="error" if runtime.served(uid)==0 else "warning"
		var entry: Dictionary=row(kind+"_"+node["role"],severity,uid,"object",node["label"],runtime.describe(uid))
		object_pin(entry,uid,"P" if kind=="power" else "")
	for key in graph["links"]:
		var link: Dictionary=graph["links"][key]
		var bad: bool=not link["reason"].is_empty()
		var run_title: String=tools.port_label(link["from"],objects)+" ↔ "+tools.port_label(link["to"],objects)
		var entry: Dictionary=row(kind+"_run","warning" if bad else "info",link["uid"],"utility_run",run_title,
			link["reason"] if bad else "Connected "+kind+" ports.",[link["from"]["object_uid"],link["to"]["object_uid"]],{"key":key})
		utility_line(entry,link["positions"],kind,bad)

func utility_line(result: Dictionary,positions: Array,kind: String,interrupted: bool) -> void:
	if positions.size()!=2 or not available_shape(result,2): return
	var start:=Vector3(positions[0][0],positions[0][1],positions[0][2])
	var end:=Vector3(positions[1][0],positions[1][1],positions[1][2])
	if not start.is_finite() or not end.is_finite(): return
	if start.distance_squared_to(end)<.0001:
		pin(result,start,"P" if kind=="power" else "W","station")
		return
	result["details"]["anchor"]=(start+end)*.5
	result["details"]["geometry"].append({"kind":kind+("_interrupted" if interrupted else "_run"),"points":PackedVector3Array([start,end])})
	shapes+=1
	points+=2

func traffic() -> void:
	var tools: RefCounted=studio.traffic_tools
	var manager: Node=tools.managers[mode]
	if tools.dirty or manager.plan.is_empty(): wait("Road traffic"); return
	revision+=":traffic:%d:%d"%[manager.signature,manager.route_queue.revision]
	var plan: Dictionary=manager.plan
	for uid in plan.get("controls",{}).get("issues",{}):
		var result: Dictionary=row("traffic_control","error",uid,"object",object_title(uid),plan["controls"]["issues"][uid])
		object_pin(result,uid)
	for key in plan.get("closed_sections",{}):
		if rows.size()>=Common.MAX_ROWS: limited=true; break
		var cell:=Vector2i(int(key.get_slice(",",0)),int(key.get_slice(",",1)))
		var result: Dictionary=row("closed_road","error",key,"road","Closed road "+key,plan["closed_sections"][key])
		pin(result,ground_point(Traffic.center(cell,mode)))
	for car in manager.vehicles:
		var pending: bool=car.has("route_request")
		var blocked: bool=car["phase"]=="blocked"
		var parked: bool=car["phase"]=="parked"
		var severity: String="pending" if pending else "error" if blocked else "info"
		var code: String="traffic_pending" if pending else "traffic_blocked" if blocked else "traffic_parked" if parked else "traffic_lane"
		var reason: String="Searching for a route for this vehicle." if pending else car["status"]
		var related: Array=[] if car["bay"].is_empty() else [car["bay"]]
		var result: Dictionary=row(code,severity,car["id"],"traffic_actor",car["id"].capitalize(),reason,related)
		pin(result,ground_point(car["point"]))
		if not pending and not blocked and not parked: path(result,car["path"])
	for notice in plan.get("notices",[]):
		if not notice.begins_with("Road ") and not notice.begins_with("Traffic control "):
			row("traffic_notice","info","","","Road traffic",notice,[],{"key":notice})

func transit() -> void:
	var tools: RefCounted=studio.transit_tools
	var manager: Node=tools.managers[mode]
	var plan: Dictionary=manager.passengers.plan
	if tools.dirty: wait("Public transit"); return
	revision+=":transit:%d:%d"%[manager.signature,manager.route_queue.revision]
	for issue in plan.get("issues",[]):
		var result: Dictionary=row(issue["code"],"error",issue["uid"],issue["entity"],issue["title"],issue["reason"],issue["related"])
		if issue["entity"]=="object": object_pin(result,issue["uid"])
		else:
			for stop in issue["related"]:
				if not objects.has(stop): continue
				object_pin(result,stop)
				break
	var waiting: Dictionary={}
	for job in manager.passengers.jobs:
		if job["state"]!="waiting" or job["index"]>=job["legs"].size(): continue
		var uid: String=job["legs"][job["index"]].get("from","")
		if plan.get("stops",{}).has(uid): waiting[uid]=int(waiting.get(uid,0))+1
	for uid in waiting:
		var stop: Dictionary=plan["stops"][uid]
		var result: Dictionary=row("platform_queue","info",uid,"object",stop["name"],"%d passengers waiting at this platform."%waiting[uid])
		pin(result,ground_point(stop["platform"]),str(waiting[uid]),"queue")
	for id in manager.buses:
		var bus: Dictionary=manager.passengers.vehicles.get(id,{})
		if bus.is_empty(): continue
		var actor: Dictionary=manager.buses[id]
		var pending: bool=actor.has("route_request")
		var blocked: bool=bus["phase"]=="blocked"
		var title: String=actor.get("configured_line",{}).get("name","Bus")
		var uid: String=bus.get("stop","") if bus["phase"]=="dwell" else bus.get("next","")
		var result: Dictionary=row("bus_pending" if pending else "bus_blocked" if blocked else "bus_route",
			"pending" if pending else "error" if blocked else "info",bus["line"],"line",title,
			"Checking the updated route for this bus." if pending else actor["status"],[uid],{"key":id})
		pin(result,ground_point(actor["vehicle"]["point"]))
		var index: int=actor["segment"]
		if not pending and not blocked and bus["phase"]=="moving" and index<actor["segments"].size():
			var piece: Dictionary=actor["segments"][index]
			if manager.safe_piece(actor,piece,actor["distance"]): path(result,piece["points"])
	if plan.is_empty(): row("transit_off","info","","","Public transit","Enable public transit to see routes and queues.")

func services() -> void:
	var tools: RefCounted=studio.service_tools
	var manager: Node=tools.managers[mode]
	var plan: Dictionary=manager.dispatch.plan
	if tools.dirty or plan.is_empty(): wait("City services"); return
	revision+=":service:%d:%d"%[manager.signature,manager.route_queue.revision]
	if not plan["settings"]["enabled"]:
		row("services_off","info","","","City services","Enable city services to see coverage and dispatch.")
		return
	for job in manager.dispatch.jobs:
		if job["state"] in ["complete","cancelled"]: continue
		var uid: String=job["target"]
		if not objects.has(uid): continue
		var crew: Dictionary=manager.crews.get(job["id"],{})
		var pending: bool=crew.has("route_request")
		var blocked: bool=job["state"]=="blocked"
		var result: Dictionary=row("service_pending" if pending else "service_blocked" if blocked else "service_job",
			"pending" if pending else "error" if blocked else "info",uid,"service_target",job["kind"].capitalize()+" · "+object_title(uid),
			"Checking a new approach for this crew." if pending else job["reason"],[job["station"]],{"key":job["id"],"kind":job["kind"]})
		if crew.is_empty(): object_pin(result,uid); continue
		pin(result,ground_point(crew["vehicle"]["point"]))
		var index: int=crew["segment"]
		if not pending and not blocked and crew["stage"] in ["outbound","returning"] and index<crew["segments"].size():
			var piece: Dictionary=crew["segments"][index]
			if manager.usable_piece(crew,piece,crew["distance"]): path(result,piece["path"])
	var selected: Dictionary=tools.coverage_result
	if selected.get("signature")==manager.signature and selected.get("mode")==mode and objects.has(selected.get("target","")):
		var uid: String=selected["target"]
		var coverage: Dictionary=selected["result"]
		var result: Dictionary=row("service_coverage","ok" if coverage["ok"] else "error",uid,"service_target",
			object_title(uid)+" · "+selected["kind"].capitalize(),"Within road coverage · %.1f units."%coverage["distance"] if coverage["ok"] else coverage["reason"],
			[coverage["station"]] if coverage["ok"] else [],{"kind":selected["kind"]})
		object_pin(result,uid)
		if coverage["ok"]:
			var route: PackedStringArray=coverage["route"]
			for index in range(1,route.size()):
				if not available_shape(result,2): break
				var edge: Dictionary=plan["network"]["edges"].get(Traffic.edge_id(route[index-1],route[index]),{})
				if not edge.is_empty(): path(result,edge["points"],"coverage")
	for uid in plan.get("stations",{}):
		if not plan["stations"][uid]["access"].is_empty(): continue
		var result: Dictionary=row("service_access","error",uid,"object",object_title(uid),"No connected road within 16 units of this station's approach.")
		object_pin(result,uid)
	for uid in plan.get("approach_issues",{}):
		var result: Dictionary=row("service_approach","error",uid,"object",object_title(uid),plan["approach_issues"][uid])
		object_pin(result,uid)

func zoning() -> void:
	var tools: RefCounted=studio.zone_tools
	var manager: Node=tools.managers[mode]
	if tools.dirty: wait("Zoning"); return
	revision+=":zoning:"+str(manager.signature)
	for lot in document.data.get("zones",[]):
		var uid: String=lot["uid"]
		var state: Dictionary=manager.states.get(uid,{})
		var severity: String="ok" if state.get("ok",false) else "pending" if state.is_empty() else "error"
		var reason: String=state.get("reason","This lot is waiting for its turn in the zoning checks.")
		if state.is_empty() and not Zone.settings(document.data)["enabled"]:
			severity="info"
			reason="Enable zoning to develop this lot."
		elif state.is_empty() and manager.paused:
			severity="info"
			reason="Resume the growth preview to check this lot."
		var result: Dictionary=row("lot_readiness",severity,uid,"lot",lot.get("name",Zone.definitions()[lot["kind"]]["label"]),reason)
		if lot.get("visible",true) and Layers.shown(document.data,"Ground") and Layers.shown(document.data,"Buildings"):
			pin(result,ground_point(Zone.rectangle(lot).get_center()))
			if state.get("ok",false): path(result,state.get("approach_path",PackedVector2Array()),"walk_metric")

func residents() -> void:
	var tools: RefCounted=studio.citizen_tools
	var manager: Node=tools.managers[mode]
	if tools.dirty: wait("Residents"); return
	revision+=":residents:"+str(manager.scene_signature)
	for resident in manager.residents:
		var actor: Node=resident.get("actor")
		if not is_instance_valid(actor) or not actor.visible: continue
		var uid: String=resident.get("target","")
		if not objects.has(uid): uid=resident["home"]
		var waiting: bool=not resident["waiting"].is_empty() or resident["blocked"]
		var result: Dictionary=row("resident_wait" if waiting else "resident_route","warning" if waiting else "info",
			uid,"object","Resident · "+object_title(uid),resident["waiting"] if waiting else resident["status"],
			[resident["home"]],{"key":resident["id"]})
		pin(result,ground_point(manager.point(actor),true))
		if not waiting and resident["index"]<resident["path"].size():
			path(result,resident["path"],"walk",maxi(0,resident["index"]-1))
	for notice in manager.plan.get("notices",[]):
		row("resident_notice","warning","","","Residents",notice,[],{"key":notice})

func fixtures(report: Dictionary) -> void:
	if report.is_empty():
		row("choose_fixture","info","","","Interaction routes","Select a fixture or a building with a saved interior.")
		return
	revision+=":fixtures:"+report["revision"]
	for original in report["records"]:
		var details: Dictionary=original["details"]
		var building: String=details["building_uid"]
		var floor_uid: String=details["floor_uid"]
		var row_scope: String=Common.scope(mode) if original["scope"]=="city:" else Common.scope(mode,building,floor_uid)
		var uid: String=original["object_uid"]
		if original["severity"]=="ok" and original["code"] not in ["approach_route","return_route"]: continue
		var kind: String=studio.prop_tools.setup.check_name(original["code"])
		var setup_record: Dictionary=original.duplicate()
		setup_record["details"]=details.duplicate()
		setup_record["details"].erase("walk_legs")
		var result: Dictionary=row(original["code"],original["severity"],uid,"fixture",kind+" · "+details["object_name"],
			details["floor_name"]+" · "+details["message"],original["related_uids"],{"setup":setup_record})
		if result.is_empty(): break
		result["scope"]=row_scope
		result["message_key"]=original["message_key"]
		if row_scope!=scope:
			result["details"]["message"]+=" Open its saved floor to inspect the location."
			continue
		if not objects.has(uid): continue
		object_pin(result,uid)
		for leg in details.get("walk_legs",[]):
			if leg["floor"]==floor_uid: path(result,leg["path"],"walk")
	if report["limited"]: limited=true

func challenges() -> void:
	var tools: RefCounted=studio.scenario_tools
	var manager: Node=tools.managers[mode]
	if tools.dirty: wait("Challenges"); return
	revision+=":challenge:"+str(manager.signature)
	if manager.active_scenario=="construction":
		var work: Node=world.exploration.driving.construction
		if not is_instance_valid(work) or work.site_plan.is_empty(): return
		var config: Dictionary=document.data["scenario"]
		var uid: String=config["host_uid"]
		var task: Dictionary=work.next_task()
		var completed: bool=work.receipts.has(work.attempt)
		var message: String=work.message if not work.message.is_empty() else work.site_plan.get("reason","")
		if message.is_empty(): message="Deliver the required masonry to start work."
		var result: Dictionary=row("construction_work","ok" if completed else "info" if work.site_plan.get("ok",false) else "error",
			uid,"object","Foundation contract" if task.is_empty() else task["title"],message,[config["pickup_uid"]])
		if not task.is_empty(): pin(result,ground_point(task["approach"]),"","station")
		else: object_pin(result,uid)
		return
	if not manager.queue.is_empty():
		row("challenge_pending","pending","","","Neighborhood routes","Checking remaining walking routes.")
	for key in manager.failures:
		var uid: String=key.substr(0,key.rfind(":"))
		var result: Dictionary=row("challenge_walk","error",uid,"object",object_title(uid),manager.failures[key],[],{"key":key})
		object_pin(result,uid)
	for uid in manager.connections:
		for destination in manager.connections[uid]:
			var link: Dictionary=manager.connections[uid][destination]
			var result: Dictionary=row("challenge_route","ok",uid,"object",object_title(uid)+" · "+destination,
				"Verified walking route · %.1f units."%link["length"],[link["target"]],{"key":destination})
			path(result,link["path"],"walk")

func deliveries() -> void:
	var driver: Node=world.exploration.driving
	var delivery=driver.delivery
	revision+=":delivery:"+str(delivery.routes.revision)
	var job: Dictionary=delivery.job
	if job.is_empty():
		for pickup in delivery.offers:
			var offer: Dictionary=delivery.offers[pickup]
			var place: Dictionary=delivery.sites[pickup]
			var done: bool=delivery.settled(pickup,offer)
			var result: Dictionary=row("delivery_offer","ok" if done else "info",pickup,"object",place["name"],
				"Cargo has settled for this session." if done else "Stop at the pickup pad to check a route and load.",[offer["destination"]])
			pin(result,ground_point(place["point"]),"","station")
		return
	var pending: bool=job["phase"]=="routing"
	var blocked: bool=job["phase"]=="blocked"
	var pickup: bool=job["phase"]=="loading" or (pending or blocked) and job.get("resume")=="loading"
	var uid: String=job["pickup"] if pickup else job["destination"]
	var place: Dictionary=delivery.sites[uid]
	var result: Dictionary=row("delivery_route","pending" if pending else "error" if blocked else "info",uid,"object",
		place["name"],delivery.message,[job["pickup"],job["destination"]],{"key":job["id"]})
	pin(result,ground_point(place["point"]),"","station")
	if pending or blocked: return
	var route: PackedStringArray=job["route"]
	var network: Dictionary=delivery.routes.network
	for index in range(1,route.size()):
		if not available_shape(result,2): break
		var edge: Dictionary=network["edges"].get(Traffic.edge_id(route[index-1],route[index]),{})
		if not edge.is_empty(): path(result,edge["points"])

func markets() -> void:
	var tools: RefCounted=studio.business_tools
	var manager: Node=tools.managers[mode]
	if tools.dirty: wait("Market days"); return
	revision+=":markets:"+str(manager.signature)
	var market=manager.market
	for uid in market.sites:
		var site: Dictionary=market.sites[uid]
		var problem: String=site.get("problem","")
		var reason: String=problem if not problem.is_empty() else market.notices.get(uid,"")
		if reason.is_empty(): continue
		var result: Dictionary=row("market_status","info" if problem.is_empty() else "error",uid,"object",site["name"],reason)
		object_pin(result,uid)
	for id in market.vendors:
		var vendor: Dictionary=market.vendors[id]
		var count: int=vendor["queue_ids"].size()
		var result: Dictionary=row("market_queue","info",vendor["host"],"object",object_title(vendor["host"]),
			"%d shoppers waiting at this vendor."%count,[],{"key":id})
		pin(result,ground_point(vendor["queue"][0] if count>0 and not vendor["queue"].is_empty() else vendor["point"]),
			str(count),"queue")

func vehicle_care() -> void:
	var runtime=world.exploration.driving.care
	for uid in runtime.bays:
		var bay: Dictionary=runtime.bays[uid]
		var waiting: Array=[]
		for vehicle in runtime.queues.get(uid,[]):
			if runtime.jobs.get(vehicle,{}).get("state")=="queued": waiting.append(vehicle)
		var supported: bool=bay["supported"]
		var message: String="%d vehicles waiting at this bay."%waiting.size() if supported else "The service bay requires a dry, level approach."
		var result: Dictionary=row("vehicle_bay","info" if supported else "error",uid,"object",bay["name"],message,waiting)
		pin(result,ground_point(bay["center"]),str(waiting.size()) if supported else "","queue" if supported else "pin")

func businesses() -> void:
	var tools: RefCounted=studio.business_tools
	var manager: Node=tools.managers[mode]
	if tools.dirty: wait("Businesses"); return
	revision+=":businesses:"+str(manager.signature)
	for uid in manager.service.queues:
		if not manager.standard_businesses.has(uid) or not world.instances.has(uid): continue
		var building: Node=world.instances[uid]
		if not is_instance_valid(building) or not building.visible: continue
		var queue: Array=manager.service.queues[uid]
		if queue.is_empty(): continue
		var at: Variant=world.exploration.entrance(building)
		var point: Vector2=Traffic.metric([at.x,at.y,0] if mode=="2d" else [at.x,at.y,at.z],mode)
		var result: Dictionary=row("business_queue","info",uid,"object",object_title(uid),"%d visits waiting for service."%queue.size())
		pin(result,ground_point(point),str(queue.size()),"queue")
