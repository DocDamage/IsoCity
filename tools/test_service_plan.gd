extends SceneTree
const Plan=preload("res://scripts/builder/service_plan.gd")
const Dispatch=preload("res://scripts/builder/service_dispatch.gd")
const Traffic=preload("res://scripts/builder/traffic_plan.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func record(uid: String,asset: String,point: Vector2,mode: String) -> Dictionary:
	return {"uid":uid,"asset":asset,"position":Traffic.world(point,mode),"direction":"SE" if asset.begins_with("2d:") else "0","scale":1.0}
func run() -> void:
	var library: RefCounted=preload("res://scripts/builder/asset_library.gd").new()
	var defaults: Dictionary=Plan.settings({})
	check(not defaults["enabled"] and defaults["automatic"],"City services are opt-in with automatic visits available")
	Plan.load_catalog()
	for asset in Plan.catalog["stations"]:
		check(library.assets.has(asset) and Plan.profile({"asset":asset})["kind"]==Plan.catalog["stations"][asset],"Authored service station references a real asset: "+asset)
	for asset in Plan.catalog["targets"]: check(library.assets.has(asset),"Authored service target references a real asset: "+asset)
	for kind in Plan.KINDS.slice(0,4):
		var unit: Dictionary=Plan.unit(kind)
		for key in ["vehicle_2d","vehicle_3d","worker_2d"]: check(library.assets.has(unit[key]),"Every service vehicle/worker reference is installed: "+kind+key)
		check(not unit["activity"].is_empty() and Color.html_is_valid(unit["color"]),"Service crews have a named task and uniform color: "+kind)
		unit["activity"]="mutated"
		check(Plan.unit(kind)["activity"]!="mutated","Unit definitions are isolated from callers: "+kind)
	check(Plan.profile({"asset":"unknown:Fire_Hospital_Police"})["kind"]=="none","Service classification never guesses from names")
	check(Plan.profile({"asset":"2d:Hopital","city_service":{"kind":"none"}})["kind"]=="none","Authored service stations can explicitly opt out")
	for kind in Plan.KINDS:
		check(Plan.valid_profile({"kind":kind,"extension":"keep"}),"Explicit service profiles support all kinds and preserve extensions: "+kind)
	for bad in [[],{"kind":4},{"kind":"unknown"},{"units":2.5},{"units":0},{"units":9},{"radius":0},{"radius":513},{"task_seconds":INF},{"task_seconds":1}]:
		check(not Plan.valid_profile(bad),"Invalid station profile is rejected: "+str(bad))
	for bad in [[],{"enabled":1},{"automatic":"yes"},{"interval":0},{"interval":601},{"seed":1.5},{"seed":NAN}]:
		check(not Plan.valid_settings(bad),"Invalid global service configuration is rejected: "+str(bad))
	check(Plan.valid_settings({"enabled":true,"extension":{"keep":true}}),"Service configuration accepts optional fields and extensions")
	var bounded: Dictionary=Plan.profile({"city_service":{"radius":999,"units":999,"task_seconds":-4}})
	check(bounded["radius"]==512 and bounded["units"]==8 and bounded["task_seconds"]==2,"Damaged station numbers have bounded fallbacks")
	for mode in ["2d","3d"]:
		var data: Dictionary={"mode":mode,"objects":[],"roads":[],"services":{"enabled":true,"automatic":false,"interval":30,"seed":5}}
		for x in 7: data["roads"].append({"cell":[x,0]})
		data["roads"].append({"cell":[10,10]}); data["roads"].append({"cell":[11,10]})
		var center: Vector2=Traffic.center(Vector2i.ZERO,mode)
		for kind in Plan.KINDS.slice(0,4):
			var station: Dictionary=record("station_"+kind,"2d:Fire_Station1_-_Copie",center+Vector2(0,-6),mode)
			station["city_service"]={"kind":kind,"radius":96,"units":1,"task_seconds":3}; data["objects"].append(station)
		var house_asset: String="2d:House_Blue" if mode=="2d" else "3d:HanX_City/Row_Houses_A"
		var house: Dictionary=record("house",house_asset,center+Vector2(48,6),mode)
		data["objects"].append(house); data["objects"].append(record("house_b",house_asset,center+Vector2(40,6),mode))
		data["objects"].append(record("island",house_asset,center+Vector2(80,86),mode)); data["objects"].append(record("far",house_asset,center+Vector2(200,200),mode))
		data["objects"].append(record("bin","2d:Dumpster",center+Vector2(32,6),mode))
		var before: Dictionary=data.duplicate(true)
		var plan: Dictionary=Plan.build(data,library)
		check(plan["stations"].size()==4 and plan["targets"].size()==5,"Four service types discover neighborhood buildings and a waste target: "+mode)
		for kind in Plan.KINDS.slice(0,4):
			var choice: Dictionary=Plan.choose(plan,kind,"house")
			check(choice["ok"] and choice["station"]=="station_"+kind and choice["route"]==PackedStringArray(["1,0","2,0","3,0","4,0","5,0"]) and is_equal_approx(choice["distance"],52),"Dispatch uses the shortest road-plus-driveway route rather than a straight coverage circle: "+mode+kind)
		check(plan["routes"].size()==4,"Shortest-path trees are cached per station: "+mode)
		check(Plan.choose(plan,"sanitation","bin")["ok"] and not Plan.choose(plan,"medical","bin")["ok"],"Waste props accept sanitation visits without becoming medical targets: "+mode)
		check("disconnected" in Plan.choose(plan,"fire","island")["reason"],"Disconnected roads do not claim service coverage: "+mode)
		check("no connected road" in Plan.choose(plan,"fire","far")["reason"],"Distant targets explain absent road access: "+mode)
		check("busy" in Plan.choose(plan,"fire","house",{"station_fire":1})["reason"],"Crew capacity distinguishes covered but busy neighborhoods: "+mode)
		plan["stations"]["station_fire"]["config"]["radius"]=32
		check("Outside" in Plan.choose(plan,"fire","house")["reason"],"Actual travel distance enforces station coverage limits: "+mode)
		plan["stations"].erase("station_fire")
		check("No station" in Plan.choose(plan,"fire","house")["reason"],"Missing service kinds have a specific explanation: "+mode)
		check(data==before,"Coverage, cached routing and dispatch selection do not mutate the project: "+mode)
		var altered: Dictionary=data.duplicate(true); altered["objects"][4]["visible"]=false
		check(not Plan.build(altered,library)["targets"].has("house") and Plan.build(altered,library,{},false)["targets"].has("house"),"Preview visibility is respected while exports may include all layers: "+mode)
		altered=data.duplicate(true); altered["objects"][4]["locked"]=true
		check(Plan.choose(Plan.build(altered,library),"fire","house")["ok"],"Editing protection does not prevent buildings receiving city services: "+mode)
		altered=data.duplicate(true); altered["objects"][4]["position"][2 if mode=="2d" else 1]=3
		check(not Plan.build(altered,library)["targets"].has("house"),"Elevated targets do not claim a reachable ground approach: "+mode)
		var arrivals: Dictionary={"house":Traffic.world(center+Vector2(200,200),mode)}
		check(Plan.build(data,library,arrivals)["targets"]["house"]["access"].is_empty(),"Actual transformed entrance approaches replace record origins for routing: "+mode)
		plan=Plan.build(data,library)
		var dispatch:=Dispatch.new(); dispatch.configure(plan)
		var first: Dictionary=dispatch.request("fire","house")["job"]
		var second: Dictionary=dispatch.request("fire","house_b")["job"]
		var medical: Dictionary=dispatch.request("medical","house")["job"]
		check(dispatch.request("fire","house")["existing"] and dispatch.jobs.size()==3,"Duplicate outstanding requests share the original job: "+mode)
		dispatch.dispatch()
		check(first["state"]=="outbound" and second["state"]=="waiting" and "busy" in second["reason"] and medical["state"]=="outbound","Independent service crews dispatch while excess requests queue: "+mode)
		check(not dispatch.arrive(second) and not dispatch.returned(first) and not dispatch.arrive(first.duplicate(true)),"Lifecycle gates reject unassigned, premature and copied job records: "+mode)
		check(dispatch.arrive(first),"A dispatched crew's arrival callback starts site work: "+mode)
		dispatch.work(2)
		check(not first["fulfilled"] and first["remaining"]==1 and dispatch.history.is_empty(),"Partially completed work does not claim service fulfillment: "+mode)
		dispatch.work(1)
		check(first["state"]=="returning" and first["fulfilled"] and dispatch.history.size()==1,"Finishing site work records a real service result before the return journey: "+mode)
		dispatch.dispatch()
		check(second["state"]=="waiting" and dispatch.units.has(first["unit"]),"Returning crews remain unavailable for another call: "+mode)
		check(dispatch.returned(first),"A return callback releases the crew after completed site work: "+mode)
		dispatch.dispatch()
		check(second["state"]=="outbound" and second["unit"]==first["unit"],"Queued work acquires the same freed crew without exceeding station capacity: "+mode)
		dispatch.arrive(second)
		altered=data.duplicate(true); altered["services"]["enabled"]=false; dispatch.configure(Plan.build(altered,library)); dispatch.work(10)
		check(second["remaining"]==3 and not dispatch.request("police","house")["ok"],"Disabled city services cannot create or advance work: "+mode)
		dispatch.configure(Plan.build(data,library)); dispatch.work(3); dispatch.work(10)
		check(second["state"]=="returning" and dispatch.history.size()==2,"A finished job cannot award duplicate service results: "+mode)
		dispatch.cancel(medical)
		check(medical["state"]=="cancelled" and not medical["fulfilled"] and not dispatch.units.has(medical["unit"]),"Cancellation releases an unfulfilled crew without a false completion: "+mode)
		altered=data.duplicate(true); altered["roads"]=altered["roads"].filter(func(road: Dictionary):return road["cell"]!=[3,0]); dispatch.configure(Plan.build(altered,library))
		check(second["state"]=="blocked" and dispatch.units.has(second["unit"]),"Changed roads block the assigned crew until a safe runtime restart: "+mode)
		altered=data.duplicate(true); altered["objects"]=altered["objects"].filter(func(item: Dictionary):return item["uid"]!="station_fire"); dispatch.configure(Plan.build(altered,library))
		check(second["state"]=="cancelled" and dispatch.units.is_empty(),"Removing a station cancels its unfinished return and releases its reservation: "+mode)
		dispatch.reset()
		check(dispatch.jobs.is_empty() and dispatch.units.is_empty() and dispatch.history.is_empty() and dispatch.plan.is_empty(),"Project changes can reset all transient dispatch state: "+mode)
		plan=Plan.build(data,library); dispatch.configure(plan)
		for index in 130:
			var job: Dictionary=dispatch.request("fire","house")["job"]; dispatch.dispatch(); dispatch.arrive(job); dispatch.work(3); dispatch.returned(job)
		check(dispatch.history.size()==128 and dispatch.units.is_empty(),"Recent service history is bounded across repeated completed trips: "+mode)
		dispatch.reset()
		for index in 257:
			var target: Dictionary=plan["targets"]["house"].duplicate(true); target["uid"]="bounded_"+str(index); plan["targets"][target["uid"]]=target
		dispatch.configure(plan)
		for index in Dispatch.MAX_JOBS: dispatch.request("fire","bounded_"+str(index))
		check(not dispatch.request("fire","bounded_256")["ok"] and dispatch.jobs.size()==Dispatch.MAX_JOBS,"Pending service requests have a hard population bound: "+mode)
		dispatch.cancel(dispatch.jobs[0]); check(dispatch.request("fire","bounded_256")["ok"] and dispatch.jobs.size()==Dispatch.MAX_JOBS,"Completed or cancelled records make room for new requests without unbounded growth: "+mode)
	var doc: RefCounted=preload("res://scripts/builder/document.gd").new()
	doc.data=preload("res://scripts/builder/templates.gd").make("2d","blank")
	doc.data["services"]={"enabled":true,"interval":30,"extension":"keep"}
	var station: Dictionary=doc.add("2d:Hopital",[0,0,0],"SE")
	station["city_service"]={"kind":"medical","units":2,"extension":"keep"}
	check(doc.valid(doc.data,"2d",library),"Document validation accepts service settings and station extensions")
	station["city_service"]["units"]=2.5; doc.data["services"]["interval"]=0
	check(not doc.valid(doc.data,"2d",library),"Malformed service and station settings are rejected")
	var repair=preload("res://scripts/builder/project_repair.gd").new(library)
	var repaired: Dictionary=repair.world(doc.data,"2d","world",0)
	check(doc.valid(repaired,"2d",library) and repaired["services"]["interval"]==5 and repaired["objects"][0]["city_service"]["units"]==2,"Damaged city service settings can be repaired")
	check(repaired["services"]["extension"]=="keep" and repaired["objects"][0]["city_service"]["extension"]=="keep" and doc.data["services"]["interval"]==0,"Repair retains extensions and does not rewrite the original source")
	station["city_service"]=["medical"]; doc.data["services"]="yes"
	repaired=repair.world(doc.data,"2d","world",0)
	check(doc.valid(repaired,"2d",library) and not Plan.settings(repaired)["enabled"] and Plan.profile(repaired["objects"][0])["kind"]=="none","Unreadable service configuration disables safely while preserving the building")
	var transport=preload("res://scripts/builder/traffic_runtime.gd").new()
	var footprint:=Node2D.new(); root.add_child(footprint)
	var body:=StaticBody2D.new(); footprint.add_child(body)
	var polygon:=CollisionPolygon2D.new(); polygon.polygon=PackedVector2Array([Vector2(0,0),Vector2(48,24),Vector2(0,48),Vector2(-48,24)]); body.add_child(polygon)
	transport.collect_2d_obstacles(footprint)
	check(transport.obstacles.size()==1 and transport.obstacles[0].is_equal_approx(Rect2(0,0,6,6)),"Sprite collision polygons convert directly into road coordinates without doubling their bounds")
	footprint.free()
	var network: Dictionary=Traffic.build({"roads":[{"cell":[0,0]},{"cell":[1,0]},{"cell":[-1,0]},{"cell":[0,1]},{"cell":[0,-1]}]})
	transport.gates.request(network,"service_crew","0,0",3); transport.gates.request(network,"service_crew","0,0",4)
	transport.vehicles.assign([{"id":"ordinary_car"}]); transport.clear()
	check(transport.gates.owners.get("0,0")=="service_crew","Resetting ordinary traffic preserves another fleet's intersection reservation")
	transport.free()
	print("SERVICE PLAN: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
