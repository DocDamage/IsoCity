extends RefCounted

# Setup inspection reads the authored floor and the same routes, capacity and
# prop definitions used by Walk. It never opens a room or takes a reservation.
const Props=preload("res://scripts/builder/prop_plan.gd")
const Activities=preload("res://scripts/builder/resident_activity_plan.gd")
const Floors=preload("res://scripts/builder/floor_plan.gd")
const Layers=preload("res://scripts/builder/layers.gd")
const CharacterPose=preload("res://scripts/character_animation.gd")
const Diagnostics=preload("res://scripts/builder/simulation_diagnostics.gd")
const MAX_INSPECTED: int=96

static func revision(room: Dictionary,library: RefCounted,options: Dictionary={}) -> String:
	return JSON.stringify([room,library.project_palette_revision,options.get("building",""),options.get("floor",""),options.get("object",""),options.get("city",false)]).sha256_text()

static func make_record(code: String,severity: String,message: String,details: Dictionary,related: Array=[]) -> Dictionary:
	return Diagnostics.record(code,severity,details["scope"],details["object_uid"],related,message,details["revision"],details,"interaction")

static func prop_details(item: Dictionary,floor: Dictionary,mode: String,options: Dictionary,stamp: String,library: RefCounted) -> Dictionary:
	var building: String=options.get("building","standalone");var floor_uid: String=floor["uid"]
	return {"object_uid":item["uid"],"object_name":item.get("name",library.assets.get(item.get("asset",""),{}).get("name",item.get("asset","Unavailable asset"))),"building_uid":building,"floor_uid":floor_uid,"floor_name":floor.get("name","Ground floor"),"mode":mode,"scope":"city:" if options.get("city",false) else "room:"+building+":"+floor_uid+":","revision":stamp}

static func capacity_record(item: Dictionary,profile: Dictionary,details: Dictionary,pool: RefCounted) -> Dictionary:
	if profile["kind"]=="switch":return make_record("station_capacity","ok","A switch can be toggled without reserving a station.",details)
	var key: String=details["scope"]+item["uid"]
	var busy: bool=pool!=null and not pool.current(key).is_empty()
	return make_record("station_capacity","info" if busy else "ok","One user at a time; this station is in use." if busy else "One user at a time; this station is free.",details)

static func pose_record(profile: Dictionary,details: Dictionary,animation: Dictionary) -> Dictionary:
	if profile["kind"]=="switch":return make_record("animation","ok","Switch operation does not require a character pose.",details)
	if details["mode"]=="3d":return make_record("animation","ok","Uses the native 3D interaction pose.",details)
	if animation.is_empty():return make_record("animation","info","Uses the built-in sprite presentation. A supplied clip is checked when an authored character is active.",details)
	var action: String="sit" if profile["kind"] in ["seat","swing","slide"] else "wave"
	var pose: Dictionary=CharacterPose.resolve_pose(animation["clips"],animation["actions"],action)
	var reason: String=pose["reason"]
	if not pose["available"]:reason="No supported idle clip; keeping the base pose."
	return make_record("animation","ok" if reason.is_empty() else "warning","Source pose: "+str(pose["clip"]) if reason.is_empty() else reason,details)

static func report(room: Dictionary,library: RefCounted,options: Dictionary={},pool: RefCounted=null,animation: Dictionary={}) -> Dictionary:
	var stamp: String=revision(room,library,options);var mode: String=room.get("mode","");var records: Array[Dictionary]=[]
	var result: Dictionary={"revision":stamp,"records":records,"objects":0,"limited":false}
	if mode not in ["2d","3d"] or not Floors.valid(room):return result
	var compiled: Dictionary=Activities.compile(room,library);var stations: Dictionary={}
	for station in compiled["stations"]:stations[[station["floor"],station["uid"]]]=station
	for floor in Floors.definitions(room):
		var floor_uid: String=floor["uid"]
		if not options.get("floor","").is_empty() and floor_uid!=options["floor"]:continue
		var data: Dictionary=floor["room"]
		for item in data.get("objects",[]):
			if not options.get("object","").is_empty() and item["uid"]!=options["object"]:continue
			var profile: Dictionary=Props.profile(item)
			var missing: bool=item.has("missing_asset") or not library.assets.has(item["asset"])
			if profile.is_empty() and not missing and not item.has("prop") and options.get("object","").is_empty():continue
			if result["objects"]>=MAX_INSPECTED:result["limited"]=true;return result
			result["objects"]+=1
			var details: Dictionary=prop_details(item,floor,mode,options,stamp,library)
			if missing:
				records.append(make_record("missing_asset","error","The source asset is missing. Restore its pack or replace the fixture.",details));continue
			var shown: bool=item.get("visible",true) and Layers.shown(data,Layers.layer(item,library)) and compiled["floors"][floor_uid]["shown"]
			if not shown:records.append(make_record("hidden","error","Show the object and its floor/layer before testing the interaction.",details))
			if not Layers.editable(data,item,library):records.append(make_record("protected","info","The fixture is hidden or locked. Unlock or show it before editing.",details))
			if profile.is_empty():
				records.append(make_record("action","warning","No action is available. Choose an interaction type in Props.",details));continue
			records.append(make_record("action","ok","Available action: "+str(profile["label"]),details))
			var target: String=profile.get("target","")
			if profile["kind"]=="switch" and not target.is_empty():
				var target_ok: bool=not Props.target_record(item,data,library).is_empty()
				records.append(make_record("required_target","ok" if target_ok else "error","The linked device is available on this floor." if target_ok else "Choose an available powered device on this floor.",details,[target]))
			records.append(pose_record(profile,details,animation))
			if not shown:continue
			records.append(capacity_record(item,profile,details,pool))
			var station: Dictionary=stations.get([floor_uid,item["uid"]],{})
			if station.is_empty():
				station={"floor":floor_uid,"approach":Activities.anchor(item,profile,"approach",mode,library),"exit":Activities.anchor(item,profile,"exit",mode,library)}
				station["checks"]=Activities.station_checks(station,compiled["floors"][floor_uid],mode)
			for check in station["checks"]:
				var repair: String={"station_overlap":" Move one fixture to separate its approach.","station_support":" Adjust the anchors or repair the walking surface.","station_clearance":" Clear standing space or adjust the source anchors."}[check["code"]]
				records.append(make_record(check["code"],"ok" if check["ok"] else "error",check["pass"] if check["ok"] else check["message"]+repair,details))
			var entry_floor: String=floor_uid if options.get("city",false) else "ground"
			var entry: Vector3=station["approach"] if options.get("city",false) else compiled["floors"][entry_floor]["exit"]
			var routes: Dictionary=Activities.station_routes(compiled,station,entry_floor,entry)
			if not options.get("city",false):
				var approach_ok: bool=routes["outbound"]["ok"]
				var approach_details: Dictionary=with_walk_legs(details,[routes["outbound"]],options)
				records.append(make_record("approach_route","ok" if approach_ok else "error","The room entrance has a planned route to the approach." if approach_ok else "Approach route: "+str(routes["outbound"]["reason"])+" Clear the path or add a reachable floor link.",approach_details))
			var return_ok: bool=routes["standing"]["ok"] and routes["returning"]["ok"]
			var return_reason: String=routes["standing"]["reason"] if not routes["standing"]["ok"] else routes["returning"]["reason"]
			var return_details: Dictionary=with_walk_legs(details,[routes["standing"],routes["returning"]] if return_ok else [],options)
			records.append(make_record("return_route","ok" if return_ok else "error","The planner found a usable return route." if return_ok else "Return route: "+return_reason+" Clear the path or add a reachable floor link.",return_details))
	return result

static func with_walk_legs(details: Dictionary,routes: Array,options: Dictionary) -> Dictionary:
	if not options.get("visual",false): return details
	var result: Dictionary=details.duplicate()
	var legs: Array=[]
	for route in routes:
		for leg in route.get("legs",[]):
			if leg["kind"]=="walk": legs.append({"floor":leg["floor"],"path":leg["path"]})
	result["walk_legs"]=legs
	return result
