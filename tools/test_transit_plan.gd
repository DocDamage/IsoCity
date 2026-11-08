extends SceneTree
const Plan=preload("res://scripts/builder/transit_plan.gd")
const Passengers=preload("res://scripts/builder/transit_passengers.gd")
var checks: int=0
var failures: int=0
var library: RefCounted
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func fixture(mode: String,transfer: bool=false) -> Dictionary:
	var data: Dictionary=preload("res://scripts/builder/templates.gd").make(mode,"blank")
	data["transit"]={"enabled":true}
	data["objects"]=[]; data["roads"]=[]
	for x in range(-4,21): data["roads"].append({"cell":[x,0]})
	var asset: String="2d:Bus_Stop_Sign" if mode=="2d" else "3d:HanX_Traffic/Bus_Stop"
	for index in range(3 if transfer else 2):
		var point: Vector2=Plan.Traffic.center(Vector2i(index*8,0),mode)+Vector2(0,8)
		data["objects"].append({"uid":"stop_"+str(index),"asset":asset,"position":Plan.Traffic.world(point,mode),"direction":library.directions(asset)[0],"scale":1.0})
	data["transit_lines"]=[{"uid":"line_a","name":"District connector","stops":["stop_0","stop_1"],"capacity":1,"headway":120}]
	if transfer: data["transit_lines"].append({"uid":"line_b","stops":["stop_1","stop_2"],"headway":120,"offset":30})
	return data
func walk(from: String,to: String,point: Vector2) -> Dictionary:
	return {"kind":"walk","from":from,"to":to,"path":PackedVector2Array([point]),"seconds":0.0}
func itinerary(plan: Dictionary) -> Dictionary:
	return {"ok":true,"legs":[walk("","stop_0",plan["stops"]["stop_0"]["platform"]),{"kind":"ride","line":"line_a","from":"stop_0","to":"stop_1"},walk("stop_1","",plan["stops"]["stop_1"]["platform"]+Vector2(0,3))]}
func manifest(plan: Dictionary) -> void:
	var state=Passengers.new(); state.configure(plan)
	check(not state.request({"ok":true,"legs":[1,{},false]})["ok"],"Malformed itinerary endpoints are rejected without an exception")
	check(state.register_vehicle("bus","line_a")["ok"],"Register a bounded scheduled vehicle")
	check(not state.register_vehicle("bus","line_a")["ok"] and not state.register_vehicle("outside","line_a",99)["ok"],"Reject duplicate buses and nonexistent timetable slots")
	check(not state.register_vehicle("duplicate_slot","line_a")["ok"],"Each scheduled fleet slot has at most one actual bus")
	var a: Dictionary=plan["stops"]["stop_0"]; var b: Dictionary=plan["stops"]["stop_1"]
	var first: Dictionary=state.request(itinerary(plan))["job"]; var second: Dictionary=state.request(itinerary(plan))["job"]
	check(not state.walk_arrived(first.duplicate(true),a["platform"],0),"Copied passenger records cannot mutate live requests")
	check(not state.walk_arrived(first,Vector2(INF,0),0) and not state.walk_arrived(first,Vector2(999,999),0),"Walking requires a finite actual arrival")
	check(state.walk_arrived(first,a["platform"],0) and state.walk_arrived(second,a["platform"],1),"Passengers join a platform queue after walking")
	check(not state.dock("bus","stop_0",Vector2.ZERO,0)["ok"],"A bus cannot dock remotely")
	check(state.dock("bus","stop_0",a["dock"],0)["ok"],"Bus physically docks at the first scheduled stop")
	check(not state.reserve(second,"bus",2)["ok"],"FIFO prevents a later passenger taking the first seat")
	check(state.reserve(first,"bus",2)["ok"],"First passenger reserves a seat while walking to the door")
	check(not state.reserve(second,"bus",2)["ok"],"Reserved seats count against vehicle capacity")
	check(not state.depart("bus",120)["ok"],"A bus waits for a reserved passenger to board")
	check(not state.board(first,a["platform"]+Vector2(20,0)),"Boarding cannot teleport from a remote platform")
	check(state.board(first,a["dock"]+a["right"]*1.2) and first["state"]=="onboard","Actual door arrival moves the passenger onto the manifest")
	check(not state.board(first,a["dock"]) and not state.cancel(first),"Duplicate boarding and cancelling an onboard passenger are refused")
	check(not state.depart("bus",0)["ok"] and state.depart("bus",6)["ok"],"Departure obeys the scheduled first departure and dwell")
	check(not state.dock("bus","stop_1",b["dock"],6)["ok"],"A bus cannot skip physical journey time")
	var arrival: float=state.vehicles["bus"]["not_before"]
	check(not state.dock("bus","stop_0",a["dock"],arrival)["ok"],"Arrival must follow the authored stop sequence")
	check(state.dock("bus","stop_1",b["dock"],arrival)["ok"] and first["state"]=="alighting","Destination docking starts actual alighting")
	check(not state.depart("bus",arrival+900)["ok"],"A bus waits until alighting finishes")
	check(not state.alight(first,a["platform"],arrival),"Seats remain occupied until the passenger reaches the correct platform")
	check(state.alight(first,b["platform"],arrival) and state.vehicles["bus"]["manifest"].is_empty(),"Alighting releases exactly one seat")
	check(state.completed==0 and first["state"]=="walking","Reaching the destination stop does not complete the final walk")
	check(state.walk_arrived(first,first["legs"][-1]["path"][-1],arrival+3) and state.completed==1,"Actual final destination arrival completes the journey")
	check(not state.walk_arrived(first,b["platform"],arrival+4) and state.completed==1 and state.history.size()==1,"Repeated arrivals cannot duplicate completion credit")
	var occupied=Passengers.new(); occupied.configure(plan); occupied.register_vehicle("occupied","line_a")
	var rider: Dictionary=occupied.request(itinerary(plan))["job"]
	occupied.walk_arrived(rider,a["platform"],0); occupied.dock("occupied","stop_0",a["dock"],0); occupied.reserve(rider,"occupied",0); occupied.board(rider,a["dock"]+a["right"]*1.2)
	var changed: Dictionary=plan.duplicate(true); changed["lines"].clear(); occupied.configure(changed)
	check(rider["state"]=="blocked" and occupied.vehicles["occupied"]["manifest"]==[rider["id"]] and occupied.completed==0,"Deleting an occupied route preserves its passenger manifest without fabricated arrivals")
	var bounded=Passengers.new(); bounded.configure(plan)
	for index in Passengers.MAX_REQUESTS: bounded.request(itinerary(plan))
	check(bounded.jobs.size()==Passengers.MAX_REQUESTS and not bounded.request(itinerary(plan))["ok"],"Active requests are bounded and never evicted to make room")
	bounded.cancel(bounded.jobs[0]); check(bounded.request(itinerary(plan))["ok"] and bounded.jobs.size()==Passengers.MAX_REQUESTS,"Only settled requests can be replaced at the request limit")
	var altered: Dictionary=plan.duplicate(true); altered["lines"]["line_a"]["name"]="Renamed"
	state.configure(altered); check(state.vehicles["bus"]["phase"]=="dwell","Renaming a line preserves live service")
	altered["lines"]["line_a"]["headway"]=130; state.configure(altered)
	check(state.vehicles["bus"]["phase"]=="blocked" and second["state"]=="cancelled","Schedule edits block buses and cancel requests awaiting changed connections")
	state.configure(Plan.build({},library)); check(state.jobs.is_empty() and state.vehicles.is_empty() and state.completed==0,"Disabling transit resets all transient state")
func schema(data: Dictionary) -> void:
	var Doc=preload("res://scripts/builder/document.gd")
	check(Doc.valid(data,data["mode"],library),"Transit metadata validates with the complete city document")
	var original: Dictionary=data.duplicate(true)
	var repair=preload("res://scripts/builder/project_repair.gd").new(library)
	var preserved: Dictionary=repair.world(data,data["mode"],"world",0)
	check(preserved["transit"]==original["transit"] and preserved["transit_lines"]==original["transit_lines"] and data==original,"Repair preserves valid authored transit content")
	var broken: Dictionary=data.duplicate(true)
	broken["transit"]={"enabled":1,"automatic":"yes","speed":INF,"interval":-1,"population":1.5,"seed":0,"extension":"retain"}
	broken["transit_lines"]=[{"uid":"line_a","name":false,"stops":["stop_0","stop_0",42,"deleted_stop"],"headway":-4,"offset":200,"dwell":INF,"capacity":2.5,"color":"bad color","enabled":"yes","extension":"keep"},{"uid":"line_a","stops":["stop_0","stop_1"]},{"uid":"quarantine","stops":["stop_0"]},null]
	broken["objects"][0]["transit_stop"]="yes"
	var source: Dictionary=broken.duplicate(true)
	var fixed: Dictionary=repair.world(broken,data["mode"],"world",0)
	check(Doc.valid(fixed,data["mode"],library),"Repair produces a valid city from malformed transit settings, lines and stop flags")
	check(broken==source,"Repair does not alter the original damaged document")
	check(fixed["transit"]["extension"]=="retain" and fixed["transit_lines"][0]["extension"]=="keep","Repair retains extension metadata")
	check(fixed["transit_lines"].size()==2 and fixed["transit_lines"][0]["stops"]==["stop_0","deleted_stop"] and fixed["transit_lines"][1]["uid"]!="line_a","Repair retains dangling references, deduplicates references and repairs duplicate identities")
	check(not fixed["transit"]["enabled"] and not fixed["objects"][0]["transit_stop"] and fixed["transit_lines"][0]["offset"]<fixed["transit_lines"][0]["headway"],"Unsafe toggles are disabled and departure offsets fit their headway")
func run() -> void:
	library=preload("res://scripts/builder/asset_library.gd").new()
	check(not Plan.settings({})["enabled"],"Transit is opt-in")
	check(Plan.valid_settings({"extension":"keep"}),"Optional settings preserve extensions")
	for value in [null,[],true,"yes"]: check(not Plan.valid_settings(value),"Reject malformed settings "+str(value))
	for field in ["speed","interval","population","seed"]:
		for value in [null,true,"12",INF,NAN,-1,2147483648]: check(not Plan.valid_settings({field:value}),"Reject invalid setting "+field+str(value))
	check(not Plan.valid_settings({"population":1.5}) and not Plan.valid_settings({"enabled":1}),"Counts are integral and toggles boolean")
	for asset in Plan.definitions()["stops"]+Plan.definitions()["vehicles"].values(): check(library.assets.has(asset) and ResourceLoader.exists(library.assets[asset]["path"]),"Transit catalog references an installed prefab: "+asset)
	for mode in ["2d","3d"]:
		var data: Dictionary=fixture(mode); var original: Dictionary=data.duplicate(true); var plan: Dictionary=Plan.build(data,library)
		check(plan["stops"].size()==2 and plan["lines"].size()==1,"Compile native roadside stops and a cyclic route "+mode+str(plan["notices"]))
		if plan["lines"].is_empty(): continue
		check(data==original,"Compilation leaves authored content unchanged "+mode)
		schema(data)
		var line: Dictionary=plan["lines"]["line_a"]
		check(line["fleet"]==int(ceil(line["raw_cycle"]/line["headway"])) and is_equal_approx(line["cycle"],line["fleet"]*line["headway"]),"Fleet and recovery time support the scheduled headway "+mode)
		var departure: Dictionary=Plan.next_departure(line,0,6)
		check(is_equal_approx(departure["time"],6) and is_equal_approx(Plan.next_departure(line,0,6.1)["time"],126),"Timetable handles exact and missed departures "+mode)
		for leg in line["legs"]:
			var previous: Vector2=plan["stops"][leg["from"]]["dock"]
			for segment in leg["segments"]:
				check(previous.distance_to(segment["points"][0])<.001,"Bus trajectory segments connect without jumps "+mode)
				previous=segment["points"][-1]
			check(previous.distance_to(plan["stops"][leg["to"]]["dock"])<.001,"Trajectory ends at the actual destination dock "+mode)
		var trip: Dictionary=Plan.journey(plan,plan["stops"]["stop_0"]["platform"],plan["stops"]["stop_1"]["platform"],0)
		check(trip["ok"] and trip["transfers"]==0 and trip["legs"].size()==3,"Plan walking access, one ride, and walking egress "+mode)
		check(not Plan.journey(plan,Vector2(INF,0),Vector2.ZERO,0)["ok"] and not Plan.journey(plan,Vector2.ZERO,Vector2.ZERO,NAN)["ok"],"Invalid positions and clocks cannot enter journey planning "+mode)
		check(not Plan.journey(plan,Vector2(999,999),plan["stops"]["stop_1"]["platform"],0)["ok"],"District journeys require actual walking access "+mode)
		var blocked: Array[Rect2]=[Rect2(plan["stops"]["stop_0"]["platform"]-Vector2(10,10),Vector2(20,20))]
		check(not Plan.journey(plan,plan["stops"]["stop_0"]["platform"],plan["stops"]["stop_1"]["platform"],0,blocked)["ok"],"Platforms trapped inside collision geometry do not create safe walking connections "+mode)
		manifest(plan)
		var transfer: Dictionary=Plan.build(fixture(mode,true),library)
		var connected: Dictionary=Plan.journey(transfer,transfer["stops"]["stop_0"]["platform"],transfer["stops"]["stop_2"]["platform"],0)
		check(connected["ok"] and connected["transfers"]==1,"District journey transfers between two lines at a shared stop "+mode+str(connected))
		if connected["ok"]:
			check(connected["legs"][2]["departure"]>=connected["legs"][1]["arrival"] and connected["arrival"]>=connected["legs"][2]["arrival"],"Transfers wait for the next timed connection "+mode)
		var disconnected: Dictionary=data.duplicate(true); disconnected["roads"]=disconnected["roads"].filter(func(road: Dictionary):return road["cell"][0]!=4)
		check(Plan.build(disconnected,library)["lines"].is_empty(),"Disconnected districts do not compile a bus route "+mode)
		var narrow: Dictionary=data.duplicate(true)
		for road in narrow["roads"]: road["width"]=2
		check(Plan.build(narrow,library)["lines"].is_empty(),"Bus routes reject roads too narrow for the vehicle footprint "+mode)
		var hidden: Dictionary=data.duplicate(true); hidden["objects"][0]["visible"]=false
		check(Plan.build(hidden,library)["lines"].is_empty(),"Unavailable platforms suspend their routes "+mode)
		var dangling: Dictionary=data.duplicate(true); dangling["transit_lines"][0]["stops"][1]="missing"
		check(Plan.valid_lines(dangling["transit_lines"]) and Plan.build(dangling,library)["lines"].is_empty(),"Dangling stop references remain editable and produce no service "+mode)
		for field in ["capacity","headway","dwell","offset","enabled","color"]:
			var malformed: Array=data["transit_lines"].duplicate(true); malformed[0][field]=null
			check(not Plan.valid_lines(malformed),"Reject malformed line setting "+field+mode)
		var duplicate: Array=data["transit_lines"].duplicate(true); duplicate[0]["stops"]=["stop_0","stop_0"]
		check(not Plan.valid_lines(duplicate),"Reject duplicate stops in a line "+mode)
		var excessive: Array=[]
		for index in Plan.MAX_LINES+1: excessive.append({"uid":"line_"+str(index),"stops":["a","b"]})
		check(not Plan.valid_lines(excessive),"Reject line collections beyond the documented limit "+mode)
	print("TRANSIT PLAN: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
