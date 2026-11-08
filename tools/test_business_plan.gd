extends SceneTree
const Plan=preload("res://scripts/builder/business_plan.gd")
const Visits=preload("res://scripts/builder/business_visits.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func record(uid: String,asset: String) -> Dictionary:
	return {"uid":uid,"asset":asset,"position":[0,0,0],"direction":"SE","scale":1.0}
func run() -> void:
	var library: RefCounted=preload("res://scripts/builder/asset_library.gd").new()
	check(Plan.profile({"asset":"2d:Coffee_Shop"})["kind"]=="cafe","An authored café has business behavior")
	for asset in Plan.catalog: check(library.assets.has(asset),"Every authored business default references an installed asset: "+asset)
	check(Plan.profile({"asset":"unknown:Coffee_Shop"})["kind"]=="none","Business types never guess from filenames")
	check(Plan.profile({"asset":"2d:Coffee_Shop","business":{"kind":"none"}})["kind"]=="none","A placed business can explicitly opt out")
	for kind in ["cafe","shop","service"]:
		var config: Dictionary=Plan.profile({"business":{"kind":kind}})
		check(Plan.valid(config),"Each business kind has valid defaults: "+kind)
		var actions: Array=Plan.activities(config)
		check(not actions.is_empty(),"Each business supplies actual activities: "+kind)
		var seen: Dictionary={}
		for activity in actions:
			check(not seen.has(activity["id"]) and not activity["label"].is_empty() and not activity["item"].is_empty() and activity["seconds"]>0,"Activities have unique IDs, visible labels, results and nonzero duration: "+kind+activity["id"])
			seen[activity["id"]]=true
		var changed: Dictionary=Plan.action(config,actions[0]["id"]); changed["item"]="mutated"
		check(Plan.action(config,actions[0]["id"])["item"]!="mutated","Activity callers cannot mutate shared definitions: "+kind)
	check(Plan.activities(Plan.defaults("none")).is_empty() and Plan.action(Plan.defaults("cafe"),"missing").is_empty(),"Disabled and unknown activities cannot be used")
	var bounded: Dictionary=Plan.profile({"business":{"kind":"shop","capacity":999,"duration_scale":0,"open_hour":-3,"close_hour":50}})
	check(bounded["capacity"]==32 and bounded["duration_scale"]==.25 and bounded["open_hour"]==0 and bounded["close_hour"]==24,"Business configuration is bounded")
	for malformed in [[],"cafe",{"kind":false},{"kind":"unknown"},{"capacity":2.5},{"capacity":0},{"capacity":33},{"open_hour":24},{"close_hour":25},{"duration_scale":INF},{"open_hour":NAN},{"duration_scale":"fast"}]:
		check(not Plan.valid(malformed),"Malformed business configuration is rejected: "+str(malformed))
	check(Plan.valid({"kind":"shop","extension":{"keep":true}}) and Plan.valid({}),"Optional settings accept extensions without requiring filled defaults")
	var config: Dictionary=Plan.defaults("cafe")
	for entry in [[6.99,false],[7,true],[21.99,true],[22,false],[24,false],[-1,false],[31,true]]:
		check(Plan.open(config,entry[0])==entry[1],"Opening boundary and daily wrap: "+str(entry[0]))
	config["open_hour"]=22; config["close_hour"]=6
	check(Plan.open(config,23) and Plan.open(config,2) and not Plan.open(config,6) and not Plan.open(config,21),"Overnight opening hours work across midnight")
	config["open_hour"]=0; config["close_hour"]=0
	check(Plan.open(config,0) and Plan.open(config,12) and not Plan.open(config,NAN),"Equal hours mean all day while invalid clocks cannot admit visitors")
	check(not Plan.open(Plan.defaults("none"),12),"Disabled businesses are always unavailable")
	config=Plan.defaults("cafe"); config["duration_scale"]=2
	check(Plan.action(config,"coffee")["seconds"]==6,"Activity speed follows the authored duration scale")
	var a: Dictionary=record("cafe","2d:Coffee_Shop"); var b: Dictionary=record("shop","2d:Supermarket")
	var data: Dictionary={"mode":"2d","objects":[a,b,record("custom","2d:House_Blue")]}
	data["objects"][2]["business"]={"kind":"service","extension":"preserved"}
	var before: Dictionary=data.duplicate(true)
	var businesses: Dictionary=Plan.build(data,library)
	check(businesses.size()==3 and businesses["custom"]["config"]["kind"]=="service","Catalog and explicit businesses participate without changing their source asset")
	check(data==before,"Business discovery does not edit project content or extension fields")
	a["visible"]=false
	check(Plan.build(data,library).size()==2 and Plan.build(data,library,false).size()==3,"Editor visibility is respected while export can include all layers")
	a["visible"]=true; data["layers"]={"Buildings":{"visible":false}}
	check(Plan.build(data,library).is_empty(),"Hidden building layers do not attract visitors in previews")
	data.erase("layers"); b["missing_asset"]={}
	check(not Plan.build(data,library).has("shop"),"Missing-asset placeholders do not provide functioning businesses")
	b.erase("missing_asset")
	var visits:=Visits.new(); businesses["cafe"]["config"]["capacity"]=1; visits.configure(businesses)
	check(not visits.request("missing","player","coffee",12)["ok"] and not visits.request("cafe","","coffee",12)["ok"],"Unavailable businesses and unidentified visitors are rejected")
	check(not visits.request("cafe","player","coffee",23)["ok"] and visits.visits.is_empty(),"Closed businesses do not queue visitors")
	check(not visits.request("cafe","player","missing",12)["ok"] and visits.visits.is_empty(),"Unknown activities cannot create visits")
	check(visits.request("cafe","player","coffee",12)["ok"] and visits.result("player")["state"]=="active","An available service begins for an arrived visitor")
	var snapshot: Dictionary=visits.result("player"); snapshot["remaining"]=0
	check(visits.result("player")["remaining"]==3,"Read results cannot mutate a running activity")
	check(visits.request("cafe","player","coffee",12)["ok"] and visits.queues["cafe"].is_empty(),"Repeated requests do not duplicate active work or queue entries")
	check(not visits.request("shop","player","browse",12)["ok"],"One visitor cannot start simultaneous activities at different businesses")
	visits.request("cafe","resident-a","snack",12); visits.request("cafe","resident-b","coffee",12)
	check(visits.result("resident-a")["state"]=="queued" and visits.queues["cafe"]==["resident-a","resident-b"],"Capacity produces a stable first-in queue")
	visits.step(2,12)
	check(visits.result("player")["remaining"]==1 and not visits.inventory.has("player"),"Partial activity progress does not award its result early")
	visits.step(1,12)
	check(visits.result("player")["state"]=="complete" and visits.inventory["player"]["Coffee"]==1,"Completed service awards a real session item")
	check(visits.result("resident-a")["state"]=="active" and visits.result("resident-a")["remaining"]==4 and visits.result("resident-b")["state"]=="queued","Only the next visitor is admitted and receives no work from time before admission")
	visits.step(1,12)
	check(visits.inventory["player"]["Coffee"]==1 and visits.history.size()==1,"Completed activities cannot award repeatedly on later frames")
	visits.cancel("resident-a")
	check(visits.result("resident-a")["state"]=="cancelled" and not visits.inventory.has("resident-a"),"Cancelling active work frees service without an unearned item")
	visits.step(.1,12)
	check(visits.result("resident-b")["state"]=="active","Cancelling a visit allows the next waiting visitor to proceed")
	visits.request("cafe","late","snack",12); visits.step(.1,23)
	check(visits.result("late")["state"]=="cancelled" and "closed" in visits.result("late")["reason"],"Queued visitors receive an explanation when the business closes")
	visits.step(10,23)
	check(visits.result("resident-b")["state"]=="complete","Service already started can finish after closing")
	visits.depart("resident-b")
	check(visits.result("resident-b").is_empty() and visits.inventory["resident-b"]["Coffee"]==1,"Leaving a completed visit retains the visitor's session item")
	visits.request("cafe","remove","coffee",12); businesses.erase("cafe"); visits.configure(businesses)
	check(visits.result("remove")["state"]=="cancelled" and "removed" in visits.result("remove")["reason"],"Removing a business cancels its unfinished service safely")
	visits.request("shop","changed","browse",12); businesses["shop"]["config"]["kind"]="service"; visits.configure(businesses)
	check(visits.result("changed")["state"]=="cancelled","Removing an activity cancels its old service")
	visits.forget("player")
	check(not visits.inventory.has("player") and visits.result("player").is_empty(),"Removed residents can release both visits and inventory")
	visits.reset()
	check(visits.visits.is_empty() and visits.inventory.is_empty() and visits.queues.is_empty() and visits.history.is_empty(),"Loading a new project can reset all transient business state")
	var service: Dictionary={"one":{"config":Plan.defaults("service")}}
	visits.configure(service)
	for index in Visits.MAX_VISITORS: visits.request("one","visitor-"+str(index),"counter",12)
	check(not visits.request("one","overflow","counter",12)["ok"] and visits.visits.size()==Visits.MAX_VISITORS,"Visitor state has a bounded population")
	visits.reset(); visits.configure(service)
	for index in 1005:
		visits.request("one","repeat","counter",12); visits.step(3,12)
	check(visits.inventory["repeat"]["Service receipt"]==999 and visits.history.size()==128,"Repeated activities keep bounded inventory counts and recent history")
	var count: int=visits.history.size(); visits.step(NAN,12); visits.step(-1,12)
	check(visits.history.size()==count,"Invalid simulation deltas cannot create completions")
	check(Plan.build(data,library,false).size()==3,"Session activity state leaves authored business discovery intact")
	var doc: RefCounted=preload("res://scripts/builder/document.gd").new()
	doc.data=preload("res://scripts/builder/templates.gd").make("2d","blank")
	var business: Dictionary=doc.add("2d:Coffee_Shop",[0,0,0],"SE")
	business["business"]={"kind":"cafe","capacity":2,"extension":"keep"}
	check(doc.valid(doc.data,"2d",library),"Document validation accepts authored business configuration and extensions")
	business["business"]["capacity"]=2.5
	check(not doc.valid(doc.data,"2d",library),"Document validation rejects fractional service capacity")
	var repair=preload("res://scripts/builder/project_repair.gd").new(library)
	var repaired: Dictionary=repair.world(doc.data,"2d","world",0)
	check(doc.valid(repaired,"2d",library) and repaired["objects"][0]["business"]["capacity"]==2 and repaired["objects"][0]["business"]["extension"]=="keep","Repair bounds damaged business settings while retaining extensions")
	check(business["business"]["capacity"]==2.5,"Repair does not overwrite the original source document")
	business["business"]=["cafe"]
	check(not doc.valid(doc.data,"2d",library),"Unreadable business definitions are rejected")
	repaired=repair.world(doc.data,"2d","world",0)
	check(doc.valid(repaired,"2d",library) and repaired["objects"][0]["business"]["kind"]=="none","Unreadable businesses can be disabled while preserving the placed building")
	check(preload("res://scripts/builder/citizen_plan.gd").role({"asset":"2d:House_Blue","business":{"kind":"shop"}})=="shop","Explicit businesses attract shoppers even when their source asset had another role")
	check(preload("res://scripts/builder/citizen_plan.gd").role({"asset":"2d:House_Blue","business":{"kind":"shop"},"citizen_role":"none"}).is_empty(),"An explicit citizen opt-out takes precedence over business attraction")
	check(preload("res://scripts/builder/citizen_plan.gd").role({"asset":"2d:Coffee_Shop","business":{"kind":"none"}}).is_empty(),"Disabling a catalog business stops its default shopper attraction")
	check(preload("res://scripts/builder/citizen_plan.gd").role({"asset":"2d:House_Blue","business":{"kind":"none"}})=="home","Removing business behavior from a house retains its original home role")
	print("BUSINESS PLAN: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
