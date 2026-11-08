extends SceneTree
const Plan=preload("res://scripts/builder/scenario_plan.gd")
const Economy=preload("res://scripts/builder/economy_plan.gd")
var checks: int=0
var failures: int=0
var library: RefCounted
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func add(data: Dictionary,uid: String,asset: String,position: Array=[0,0,0]) -> Dictionary:
	var item: Dictionary={"uid":uid,"asset":asset,"position":position.duplicate(),"direction":library.directions(asset)[0],"scale":1.0}; data["objects"].append(item); return item
func find_goal(progress: Dictionary,id: String) -> Dictionary:
	for goal in progress["goals"]:
		if goal["id"]==id: return goal
	return {}
func furnish(data: Dictionary) -> void:
	var host: Dictionary=data["objects"][0]; var room: Dictionary=host["interior"]; var before: Dictionary=data.duplicate(true)
	var positions: Array=[[-3,-3],[-1,-3],[1,-3],[2,1]]; var index: int=0
	for kind in Plan.definitions()["apartment"]["furniture"]:
		var choices: Array=Plan.definitions()["apartment"]["furniture"][kind].filter(func(asset: String):return library.assets[asset]["mode"]==data["mode"])
		var p: Array=positions[index]; index+=1
		var point: Vector2=preload("res://scripts/builder/grid_fit.gd").pixels(Vector2(p[0],p[1]))
		add(room,"furniture_"+kind,choices[0],[point.x,point.y,0] if data["mode"]=="2d" else [p[0],0,p[1]])
	var quote: Dictionary=Economy.quote(before,data,library); check(quote["ok"],"The four native goal assets fit the construction allowance: "+data["mode"])
	data["economy_account"]=quote["account"]
func run() -> void:
	library=preload("res://scripts/builder/asset_library.gd").new()
	for id in Plan.definitions(): check(not Plan.definitions()[id]["description"].is_empty(),"Every challenge explains its concrete rules: "+id)
	for list in Plan.definitions()["apartment"]["furniture"].values():
		for asset in list: check(library.assets.has(asset) and ResourceLoader.exists(library.assets[asset]["path"]),"Goal furniture references an installed prefab: "+asset)
	for asset in Plan.definitions()["apartment"]["shell_assets"]+Plan.definitions()["apartment"]["default_asset"].values(): check(library.assets.has(asset),"Challenge shell/starter references exist: "+asset)
	for value in [null,[],{},true,"walkable",{"id":"unknown","attempt":"a"},{"id":"walkable","attempt":true},{"id":"walkable","attempt":""},{"id":"walkable","attempt":"a".repeat(129)},{"id":"apartment","attempt":"a","host_uid":""},{"id":"walkable","attempt":"a","host_uid":4}]: check(not Plan.valid(value),"Reject malformed challenge metadata: "+str(value))
	check(Plan.valid({"id":"walkable","attempt":"a","extension":"preserve"}),"Known challenge metadata supports extension fields")
	for mode in ["2d","3d"]:
		var blank: Dictionary=preload("res://scripts/builder/templates.gd").make(mode,"blank")
		var started: Dictionary=Plan.begin(blank,"apartment",library,"attempt_"+mode)
		check(started["ok"] and blank["objects"].is_empty(),"Challenge setup is a proposal that preserves the source city: "+mode)
		var data: Dictionary=started["data"]; var doc=preload("res://scripts/builder/document.gd").new(); doc.data=data
		check(Plan.valid(data["scenario"]) and doc.valid(data,mode,library) and data["economy_account"]["cash"]==600,"Apartment setup creates a valid owned room and dedicated budget: "+mode)
		var host_uid: String=data["scenario"]["host_uid"]
		var progress: Dictionary=Plan.apartment(data,library)
		check(not progress["complete"] and find_goal(progress,"floor")["complete"] and find_goal(progress,"budget")["complete"] and not find_goal(progress,"seating")["complete"],"The empty shell has a floor and budget but cannot complete its furnishing goals: "+mode)
		furnish(data); progress=Plan.apartment(data,library)
		check(progress["complete"] and progress["goals"].size()==8,"Four purchased, correctly placed furniture types complete the actual apartment challenge: "+mode)
		var altered: Dictionary=data.duplicate(true); altered["objects"][0]["interior"]["objects"].pop_back()
		check(not Plan.apartment(altered,library)["complete"],"Removing a required furnishing invalidates prior completion: "+mode)
		altered=data.duplicate(true); altered["objects"][0]["interior"]["objects"].back()["visible"]=false
		check(not Plan.apartment(altered,library)["complete"],"Hidden furniture cannot fulfill a furnishing goal: "+mode)
		altered=data.duplicate(true); altered["objects"][0]["interior"]["objects"].back()["position"]=[999,999,0]
		check(not find_goal(Plan.apartment(altered,library),"placement")["complete"],"Furniture outside the apartment cannot complete the challenge: "+mode)
		altered=data.duplicate(true); altered["objects"][0]["interior"]["objects"].back()["scale"]=8.0
		check(not Plan.apartment(altered,library)["complete"],"Actual transformed furniture bounds must fit the apartment: "+mode)
		altered=data.duplicate(true)
		if mode=="2d": altered["objects"][0]["interior"]["tiles"].pop_back()
		else: altered["objects"][0]["interior"]["objects"].remove_at(0)
		check(not find_goal(Plan.apartment(altered,library),"floor")["complete"],"Removing the starter floor invalidates completion: "+mode)
		altered=data.duplicate(true); altered["economy"]["enabled"]=false
		check(not Plan.apartment(altered,library)["complete"],"Creative mode cannot complete a budget challenge: "+mode)
		altered=data.duplicate(true); altered["economy_account"]=Economy.fresh_account(altered,library)
		check(not Plan.apartment(altered,library)["complete"],"Resetting treasury cannot replenish the challenge allowance: "+mode)
		altered=data.duplicate(true); altered["economy_account"]["construction_total"]=601
		check(not Plan.apartment(altered,library)["complete"],"Income or refunds cannot hide gross construction overspending: "+mode)
		altered=data.duplicate(true); add(altered,"unpaid",host_asset(mode),[30,0,30])
		check(not Plan.apartment(altered,library)["complete"],"Unpaid exterior construction cannot bypass the challenge's city-wide allowance: "+mode)
		altered=data.duplicate(true); add(altered["objects"][0]["interior"],"unpaid_wall",Plan.definitions()["apartment"]["shell_assets"][0])
		check(not Plan.apartment(altered,library)["complete"],"New shell pieces are not mistaken for the free starting room: "+mode)
		altered=data.duplicate(true); altered["objects"][0]["visible"]=false
		check(not Plan.apartment(altered,library)["complete"],"The actual apartment host must remain available: "+mode)
		var restart: Dictionary=Plan.begin(data,"apartment",library,"restart_"+mode,host_uid)
		check(restart["ok"] and not Plan.apartment(restart["data"],library)["complete"] and restart["data"]["economy_account"]["cash"]==600 and Plan.apartment(data,library)["complete"],"An explicit challenge restart creates a new unfurnished attempt without mutating the old city: "+mode)
		altered=data.duplicate(true); altered["objects"][0]["locked"]=true
		check(not Plan.begin(altered,"apartment",library,"protected",host_uid)["ok"],"Protected apartment contents cannot be replaced by challenge setup: "+mode)
		check(not Plan.begin(data,"apartment",library,"missing","missing")["ok"],"A removed selected host is reported rather than replaced silently: "+mode)
		check(doc.valid(JSON.parse_string(JSON.stringify(data)),mode,library),"Challenge and budget proof survive project JSON validation: "+mode)
		var city: Dictionary=preload("res://scripts/builder/templates.gd").make(mode,"blank"); city["scenario"]={"id":"walkable","attempt":"city"}
		var arrivals: Dictionary={}; var roles: Array=["home","home","work","shop","park"]
		for index in roles.size():
			var asset: String=role_asset(roles[index],mode)
			add(city,"destination_"+str(index),asset); arrivals["destination_"+str(index)]=[index*2,0,0] if mode=="3d" else [index*32,0,0]
		var destinations: Dictionary=Plan.destinations(city,library,arrivals); var requests: Array=Plan.requests(destinations); var connections: Dictionary={}
		check(destinations["home"].size()==2 and requests.size()==6 and not Plan.walkable(destinations,connections,false)["complete"],"Destination counts alone do not prove walkability: "+mode)
		for request in requests:
			var route: Dictionary=Plan.Citizen.route(request["from"],request["to"],[])
			check(Plan.route_ok(request,route),"Clear nearby destination has a usable bounded walking route: "+mode)
			if not connections.has(request["home"]): connections[request["home"]]={}
			connections[request["home"]][request["kind"]]=true
		check(Plan.walkable(destinations,connections,false)["complete"] and not Plan.walkable(destinations,connections,true)["complete"],"All six verified links complete the neighborhood only after checking finishes: "+mode)
		connections[destinations["home"][0]["uid"]].erase("park")
		check(not Plan.walkable(destinations,connections,false)["complete"],"A missing park connection invalidates neighborhood completion: "+mode)
		var route: Dictionary={"path":PackedVector2Array([Vector2.ZERO,Vector2(64,0)]),"start":Vector2.ZERO,"goal":Vector2(64,0)}
		check(Plan.route_ok({"from":Vector2.ZERO,"to":Vector2(64,0)},route),"Exact walking-distance boundary is accepted: "+mode)
		route["path"]=PackedVector2Array([Vector2.ZERO,Vector2(32,32),Vector2(64,0)])
		check(not Plan.route_ok({"from":Vector2.ZERO,"to":Vector2(64,0)},route),"Long detours cannot pass by endpoint distance alone: "+mode)
		route={"path":PackedVector2Array([Vector2(2,0),Vector2(4,0)]),"start":Vector2(2,0),"goal":Vector2(4,0)}
		check(not Plan.route_ok({"from":Vector2.ZERO,"to":Vector2(4,0)},route),"Pathfinder recovery far from an entrance cannot count as a valid approach: "+mode)
		city["objects"][0]["visible"]=false
		check(Plan.destinations(city,library,arrivals)["home"].size()==1,"Hidden homes do not count: "+mode)
		city["objects"][0]["visible"]=true; arrivals["destination_0"][2 if mode=="2d" else 1]=2
		check(Plan.destinations(city,library,arrivals)["home"].size()==1,"Elevated approaches do not claim ground-level walkability: "+mode)
	var raw: Dictionary=preload("res://scripts/builder/templates.gd").make("2d","blank"); raw["scenario"]={"id":"walkable","attempt":"x","extension":"preserve"}
	var repair=preload("res://scripts/builder/project_repair.gd").new(library)
	check(repair.world(raw,"2d","world",0)["scenario"]["extension"]=="preserve","Repair preserves valid challenge extension fields")
	raw["scenario"]={"id":"unknown","attempt":"x"}; var fixed: Dictionary=repair.world(raw,"2d","world",0)
	check(not fixed.has("scenario") and raw.has("scenario") and repair.issues.back()["original"]["id"]=="unknown","Unverifiable challenge data is archived without removing city content or rewriting its source")
	print("SCENARIO PLAN: %d checks, %d failures" % [checks,failures]); quit(0 if failures==0 else 1)
func host_asset(mode: String) -> String: return Plan.definitions()["apartment"]["default_asset"][mode]
func role_asset(role: String,mode: String) -> String:
	for id in library.assets:
		if library.assets[id]["mode"]==mode and Plan.Citizen.role({"asset":id})==role: return id
	return ""
