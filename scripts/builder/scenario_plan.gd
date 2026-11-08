extends RefCounted
const PATH: String="res://resources/catalog/scenarios.json"
const Citizen=preload("res://scripts/builder/citizen_plan.gd")
const Economy=preload("res://scripts/builder/economy_plan.gd")
const Layers=preload("res://scripts/builder/layers.gd")
const Construction=preload("res://scripts/builder/construction_plan.gd")
const Emergency = preload("res://scripts/builder/emergency_training_plan.gd")
const MAX_DESTINATIONS: int=8
const APPROACH_TOLERANCE: float=1.6
static var catalog: Dictionary={}
static func definitions() -> Dictionary:
	if catalog.is_empty():
		var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(PATH)); catalog=raw if raw is Dictionary else {}
		catalog.merge(Emergency.definitions())
	return catalog
static func valid(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.get("id")=="construction": return Construction.valid(value)
	if Emergency.recognized(value.get("id")): return Emergency.valid(value)
	if not value.get("id") in ["walkable","apartment"]: return false
	if not value.get("attempt") is String or value["attempt"].is_empty() or value["attempt"].length()>128: return false
	return value.get("host_uid","") is String and value.get("host_uid","").length()<=256 and (value["id"]!="apartment" or not value.get("host_uid","").is_empty())
static func visible(item: Dictionary,data: Dictionary,library: RefCounted) -> bool:
	return library.assets.has(item["asset"]) and not library.assets[item["asset"]].get("unavailable",false) and not item.has("missing_asset") and item.get("visible",true) and Layers.shown(data,Layers.layer(item,library))
static func goal(id: String,title: String,current: int,required: int,detail: String="") -> Dictionary:
	return {"id":id,"title":title,"current":current,"required":required,"complete":current>=required,"detail":detail}
static func result(goals: Array,notices: Array=[]) -> Dictionary:
	return {"goals":goals,"complete":not goals.is_empty() and goals.all(func(item: Dictionary):return item["complete"]),"notices":notices,"checking":false}
static func begin(source: Dictionary,id: String,library: RefCounted,attempt: String,host_uid: String="",position: Array=[0,0,0],pickup_uid: String="", drill: Dictionary={}) -> Dictionary:
	if not id in definitions() or attempt.is_empty() or attempt.length()>128: return {"ok":false,"reason":"Choose a known challenge and a valid attempt ID."}
	if Emergency.recognized(id):
		var training: Dictionary = drill.duplicate(true)
		training.merge({"id": id, "attempt": attempt}, true)
		return Emergency.begin(source, library, training)
	var data: Dictionary=source.duplicate(true)
	if id=="construction":
		var config: Dictionary={"id":id,"attempt":attempt,"host_uid":host_uid,"pickup_uid":pickup_uid}
		if not Construction.valid(config): return Construction.failure("Choose a supply container and a distinct site office.")
		data["scenario"]=config
		var site: Dictionary=Construction.inspect(data,library)
		return {"ok":true,"data":data} if site.get("ok",false) else site
	if id=="apartment":
		var host: Dictionary={}
		for item in data["objects"]:
			if item["uid"]==host_uid: host=item; break
		if not host_uid.is_empty() and host.is_empty(): return {"ok":false,"reason":"The selected building no longer exists."}
		if not host.is_empty() and (not Layers.editable(data,host,library) or not preload("res://scripts/builder/asset_behavior.gd").for_asset(host["asset"],library).get("building",false)): return {"ok":false,"reason":"Select a visible, unlocked building for the apartment challenge."}
		if host.is_empty():
			var asset: String=definitions()[id]["default_asset"][data["mode"]]
			if not library.assets.has(asset) or not Layers.shown(data,"Buildings") or Layers.locked(data,"Buildings"): return {"ok":false,"reason":"Show and unlock Buildings before creating the challenge apartment."}
			host_uid="challenge_"+attempt
			if data["objects"].any(func(item: Dictionary):return item["uid"]==host_uid): return {"ok":false,"reason":"This challenge attempt already has a building."}
			host={"uid":host_uid,"asset":asset,"position":position.duplicate(),"direction":library.directions(asset)[0],"scale":float(library.assets[asset]["data"].get("default_scale",1)),"name":"Challenge apartment"}; data["objects"].append(host)
		var room: Dictionary=preload("res://scripts/builder/interiors.gd").make(data["mode"],host.get("name",library.assets[host["asset"]]["name"]))
		room["objects"]=room["objects"].filter(func(item: Dictionary):return item["asset"] in definitions()["apartment"]["shell_assets"])
		host["interior"]=room
		var economy: Dictionary=data.get("economy",{}).duplicate(true); economy.merge({"enabled":true,"starting_cash":definitions()[id]["budget"],"refund_percent":0,"period_seconds":60},true); data["economy"]=economy
		data["economy_account"]=Economy.fresh_account(data,library); data["economy_account"]["scenario_attempt"]=attempt
		for held in data["economy_account"]["holdings"].values(): held["scenario_free"]=attempt
	data["scenario"]={"id":id,"attempt":attempt,"host_uid":host_uid}
	return {"ok":true,"data":data}

static func construction_progress(manager: Node) -> Dictionary:
	var definition: Dictionary=Construction.recipe()
	if definition.is_empty(): return result([],["The foundation contract definition is missing."])
	var state_ready: bool=is_instance_valid(manager)
	var hauled: int=manager.hauled if state_ready else 0
	var tasks: int=manager.completed_tasks if state_ready else 0
	var reason: String=manager.message if state_ready else ""
	if state_ready and reason.is_empty(): reason=manager.site_plan.get("reason","")
	return result([goal("masonry","Deliver masonry to the site office",hauled,definition["quantity"]),
		goal("barriers","Install the marked safety barriers",mini(2,tasks),2),
		goal("foundation","Set the foundation reinforcement",int(tasks==definition["tasks"].size()),1)],
		[] if reason.is_empty() else [reason])
static func apartment(data: Dictionary,library: RefCounted) -> Dictionary:
	var config: Dictionary=data.get("scenario",{}); var definition: Dictionary=definitions()["apartment"]
	var host: Dictionary={}
	for item in data.get("objects",[]):
		if item["uid"]==config.get("host_uid",""): host=item; break
	var available: bool=not host.is_empty() and visible(host,data,library) and host.get("interior") is Dictionary
	var room: Dictionary=host.get("interior",{})
	var account: Dictionary=data.get("economy_account",{})
	var budget_ok: bool=Economy.settings(data)["enabled"] and Economy.valid_account(account) and account.get("scenario_attempt","")==config.get("attempt","") and account.get("construction_total",Economy.LIMIT)<=definition["budget"]
	var counts: Dictionary={"seating":0,"table":0,"lighting":0,"storage":0}; var untracked: int=0; var misplaced: int=0
	var units: Dictionary=Economy.inventory(data,library)
	for key in units:
		var held: Dictionary=account.get("holdings",{}).get(key,{})
		if held.get("token","")!=units[key]["token"] or (held.get("scenario_free","")!=config.get("attempt","") and held.get("paid",0)<units[key]["construction"]): untracked+=1
	for item in room.get("objects",[]):
		var key: String=JSON.stringify(["object",config.get("host_uid",""),"interior","object",item["uid"]])
		var held: Dictionary=account.get("holdings",{}).get(key,{})
		if item["asset"] in definition["shell_assets"] and held.get("scenario_free","")==config.get("attempt",""): continue
		var paid: bool=held.get("token","")==item["asset"] and held.get("paid",0)>=Economy.profile(item["asset"],library)["construction"]
		var p: Array=item["position"]
		var point: Vector2=preload("res://scripts/builder/grid_fit.gd").grid(Vector2(p[0],p[1])) if data["mode"]=="2d" else Vector2(p[0],p[2])
		var bounds: AABB=preload("res://scripts/builder/grid_fit.gd").footprint_bounds(item,data["mode"],library) if library.assets.has(item["asset"]) else AABB()
		var low: Vector2=point+Vector2(bounds.position.x,bounds.position.z); var high: Vector2=point+Vector2(bounds.end.x,bounds.end.z)
		var limit: float=6.0 if data["mode"]=="2d" else 4.05
		var inside: bool=low.x>=-limit and low.y>=-limit and high.x<=limit and high.y<=limit
		inside=inside and absf(p[2 if data["mode"]=="2d" else 1])<.5
		if not inside: misplaced+=1
		if not available or not inside or not paid or not visible(item,room,library): continue
		for kind in counts:
			if item["asset"] in definition["furniture"][kind]: counts[kind]+=1
	var goals: Array=[goal("apartment","Keep the challenge apartment available",int(available),1)]
	for kind in counts: goals.append(goal(kind,"Add "+kind,counts[kind],1))
	goals.append(goal("budget","Stay within the %d-credit construction allowance" % definition["budget"],int(budget_ok and untracked==0),1,"Construction spent: %d / %d. All added furniture must be purchased in this attempt." % [account.get("construction_total",0),definition["budget"]]))
	goals.append(goal("placement","Keep furniture inside the apartment at floor level",int(misplaced==0),1))
	var floor_cells: Dictionary={}
	if data["mode"]=="2d" and Layers.shown(room,"Ground"):
		for tile in room.get("tiles",[]):
			if library.assets.has(tile["asset"]) and library.assets[tile["asset"]]["category"]=="Floors" and tile["cell"][0]>=-6 and tile["cell"][0]<6 and tile["cell"][1]>=-6 and tile["cell"][1]<6: floor_cells[Vector2i(tile["cell"][0],tile["cell"][1])]=true
	elif data["mode"]=="3d":
		for item in room.get("objects",[]):
			if item["asset"]!="3d:HanX_Shop/Floor_Tile_Store" or not visible(item,room,library) or not is_equal_approx(item["scale"],1.0): continue
			var p: Array=item["position"]
			var cell:=Vector2i(roundi(p[0]),roundi(p[2]))
			if cell.x in [-3,-1,1,3] and cell.y in [-3,-1,1,3] and is_equal_approx(p[0],cell.x) and is_equal_approx(p[2],cell.y) and absf(p[1])<.1: floor_cells[cell]=true
	goals.append(goal("floor","Keep the apartment floor intact",floor_cells.size(),144 if data["mode"]=="2d" else 16))
	var notices: Array=[]
	if not budget_ok: notices.append("Keep economy enabled and the challenge's original treasury. Restarting the budget invalidates this attempt; restart the challenge to try again.")
	if untracked>0: notices.append("%d construction units have no purchase or free starting basis in this challenge attempt." % untracked)
	return result(goals,notices)
static func destinations(data: Dictionary,library: RefCounted,arrivals: Dictionary) -> Dictionary:
	var result: Dictionary={"home":[],"work":[],"shop":[],"park":[]}
	for item in data.get("objects",[]):
		var role: String=Citizen.role(item)
		if not result.has(role) or not visible(item,data,library) or not arrivals.has(item["uid"]): continue
		if role!="park" and not preload("res://scripts/builder/asset_behavior.gd").for_asset(item["asset"],library).get("building",false): continue
		var point: Array=arrivals[item["uid"]]
		if point.size()!=3 or not point.all(func(n: Variant):return (n is int or n is float) and is_finite(float(n))) or absf(point[2 if data["mode"]=="2d" else 1])>=.5: continue
		result[role].append({"uid":item["uid"],"point":Citizen.metric(point,data["mode"]),"name":item.get("name",library.assets[item["asset"]]["name"])})
	for kind in result:
		result[kind].sort_custom(func(a: Dictionary,b: Dictionary):return a["uid"]<b["uid"])
		result[kind]=result[kind].slice(0,MAX_DESTINATIONS)
	return result
static func requests(destinations: Dictionary) -> Array:
	var result: Array=[]; var limit: float=definitions()["walkable"]["distance"]
	for home in destinations["home"]:
		for kind in ["work","shop","park"]:
			var targets: Array=destinations[kind].duplicate()
			targets.sort_custom(func(a: Dictionary,b: Dictionary):
				var a_distance: float=home["point"].distance_squared_to(a["point"]); var b_distance: float=home["point"].distance_squared_to(b["point"])
				return a["uid"]<b["uid"] if is_equal_approx(a_distance,b_distance) else a_distance<b_distance)
			for target in targets:
				if home["point"].distance_to(target["point"])<=limit: result.append({"home":home["uid"],"kind":kind,"target":target["uid"],"from":home["point"],"to":target["point"]})
	return result
static func route_length(path: PackedVector2Array) -> float:
	var total: float=0
	for index in range(1,path.size()): total+=path[index-1].distance_to(path[index])
	return total
static func route_ok(request: Dictionary,route: Dictionary) -> bool:
	return route_issue(request,route).is_empty()
static func route_issue(request: Dictionary,route: Dictionary) -> String:
	if route.get("path",PackedVector2Array()).is_empty(): return route.get("reason","No walking route")
	if route.get("start",Vector2.INF).distance_to(request["from"])>APPROACH_TOLERANCE: return "Home approach is obstructed"
	if route.get("goal",Vector2.INF).distance_to(request["to"])>APPROACH_TOLERANCE: return "Destination approach is obstructed"
	if route_length(route["path"])>definitions()["walkable"]["distance"]: return "Walking detour exceeds 64 units"
	return ""
static func walkable(destinations: Dictionary,connections: Dictionary,checking: bool) -> Dictionary:
	var connected: int=0
	for home in destinations["home"]:
		if ["work","shop","park"].all(func(kind: String):return connections.get(home["uid"],{}).has(kind)): connected+=1
	var goals: Array=[goal("homes","Provide two ground-level homes",destinations["home"].size(),2)]
	for kind in ["work","shop","park"]: goals.append(goal(kind,"Provide a "+kind+" destination",destinations[kind].size(),1))
	goals.append(goal("routes","Connect two homes to work, shops and parks within 64 walking units",connected,2))
	var value: Dictionary=result(goals)
	value["checking"]=checking
	if checking: value["complete"]=false
	return value
