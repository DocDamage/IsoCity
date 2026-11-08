extends RefCounted

# Read-only room navigation. Uses source anchors and cached source bounds, never
# creates a World, room viewport, actor, reservation or authored room identity.
const Props=preload("res://scripts/builder/prop_plan.gd")
const Floors=preload("res://scripts/builder/floor_plan.gd")
const Grid=preload("res://scripts/builder/grid_fit.gd")
const Rotation=preload("res://scripts/builder/rotation.gd")
const Citizens=preload("res://scripts/builder/citizen_plan.gd")
const Layers=preload("res://scripts/builder/layers.gd")
const Behavior=preload("res://scripts/builder/asset_behavior.gd")
const CLEARANCE: float=.3

static func vector_values(value: Vector3) -> Array:return [float(value.x),float(value.y),float(value.z)]

static func station_semantics(station: Dictionary) -> String:
	var values: Array=[station["floor"],station["kind"],float(station["duration"])]
	for key in ["approach","exit","customer","facing","point"]:values.append(vector_values(station[key]))
	return JSON.stringify(values)

static func for_building(item: Dictionary,mode: String,library: RefCounted) -> Dictionary:
	if item.get("interior") is Dictionary:
		var owned: Dictionary=compile(item["interior"],library);owned["virtual"]=false;return owned
	var room: Dictionary=preload("res://scripts/builder/interior_kit_plan.gd").shell(mode,library)
	if room.is_empty():return {"mode":mode,"floors":{},"stations":[],"links":[],"signature":"","semantic_revision":"","virtual":true,"notices":["The default room shell is unavailable or outdated."]}
	var kits=preload("res://scripts/builder/interior_kits.gd");var kit: String=kits.default_for(item["asset"])
	if not kit.is_empty():
		var checked: Dictionary=kits.plan(kit,mode,library)
		if not checked["ok"]:return {"mode":mode,"floors":{},"stations":[],"links":[],"signature":"","semantic_revision":"","virtual":true,"notices":["The default room's required furnishings are unavailable."]}
		room["objects"]=room["objects"].filter(func(record: Dictionary):return record["asset"] in ["2d:Wall_White","3d:HanX_Shop/Floor_Tile_Store","3d:HanX_Shop/Wall_Store_Segment"])
		for index in checked["objects"].size():room["objects"].append(kits.placed(checked["objects"][index],mode,library,"logical_"+str(index)))
	var policy: Dictionary=preload("res://scripts/builder/asset_palette_policy.gd").check({},room,library)
	if not policy["ok"]:return {"mode":mode,"floors":{},"stations":[],"links":[],"signature":"","semantic_revision":"","virtual":true,"notices":[policy["reason"]]}
	var result: Dictionary=compile(room,library);result["virtual"]=true;return result

static func metric(point: Vector3,mode: String) -> Vector2:
	return Vector2(point.x/16,point.y/8) if mode=="2d" else Vector2(point.x,point.z)

static func native(point: Vector2,mode: String,height: float=0) -> Vector3:
	return Vector3(point.x*16,point.y*8,0) if mode=="2d" else Vector3(point.x,height,point.y)

static func point(item: Dictionary,source: Vector3,mode: String,library: RefCounted,ground: bool=false) -> Vector3:
	var sprite: bool=library.assets[item["asset"]]["mode"]=="2d";var position: Array=item["position"];var scale_value: float=float(item.get("scale",1))
	if mode=="3d":
		var basis: Basis=Grid.sprite_basis(item,library) if sprite else Basis.from_euler(Rotation.euler(item)*PI/180)
		var local: Vector3=source
		if sprite:
			var views: Dictionary=library.assets[item["asset"]]["data"]["directions"];var view: Dictionary=views.get(item["direction"],views.values()[0]);var foot: Array=view.get("footprint",[1,1]);local+=Vector3(-float(foot[0])*.5,.02,-float(foot[1])*.5)
		return Vector3(position[0],position[1],position[2])+basis*(local*scale_value)
	var pixel: Vector2
	if sprite:pixel=Grid.pixels(Vector2(source.x,source.z))+Vector2(0,-source.y*8)
	else:
		var local: Vector3=Basis.from_euler(Vector3(deg_to_rad(-30),deg_to_rad(45),0)).inverse()*(Basis.from_euler(Rotation.euler(item)*PI/180)*source)
		pixel=Vector2(local.x,-local.y)*22.627417
	pixel=(pixel*scale_value).rotated(deg_to_rad(float(item.get("angle",0))))+Vector2(position[0],position[1]-(0 if ground else float(position[2])*8))
	return Vector3(pixel.x,pixel.y,0)

static func anchor(item: Dictionary,profile: Dictionary,key: String,mode: String,library: RefCounted,ground: bool=true) -> Vector3:
	var source: Vector3=Props.source(profile,item,library,key)
	if mode=="2d" and ground:source.y=0
	return point(item,source,mode,library,ground)

static func obstacles_for(item: Dictionary,mode: String,library: RefCounted) -> Array[Rect2]:
	var id: String=item["asset"];var behavior: Dictionary=Behavior.for_asset(id,library)
	if behavior.get("ground",false) or behavior.get("collision","box")=="none" or library.is_ground_tile(id):return []
	var points: Array[Vector3]=[]
	if library.assets[id]["mode"]=="3d":
		var box: AABB=Grid.bounds_for(id,library,false)
		if box.end.y*float(item.get("scale",1))+float(item["position"][1] if mode=="3d" else item["position"][2])<=.35:return []
		if mode=="2d":
			# Include torso-height furniture, including tabletop overhangs. Contact
			# bounds commonly have zero height and cannot classify low obstacles.
			box=Transform3D(Basis.from_euler(Rotation.euler(item)*PI/180),Vector3.ZERO)*box
			var copy: Dictionary=item.duplicate();copy["direction"]="0";copy.erase("tilt")
			for corner in [Vector3(box.position.x,0,box.position.z),Vector3(box.end.x,0,box.position.z),Vector3(box.end.x,0,box.end.z),Vector3(box.position.x,0,box.end.z)]:points.append(point(copy,corner,mode,library,true))
		else:
			for corner in 8:points.append(point(item,box.get_endpoint(corner),mode,library,true))
	else:
		var views: Dictionary=library.assets[id]["data"]["directions"];var view: Dictionary=views.get(item["direction"],views.values()[0]);var foot: Array=view.get("footprint",[1,1])
		for corner in [Vector3.ZERO,Vector3(foot[0],0,0),Vector3(foot[0],0,foot[1]),Vector3(0,0,foot[1])]:points.append(point(item,corner,mode,library,true))
	var result:=Rect2();var found: bool=false;var polygon:=PackedVector2Array()
	for value in points:
		var p: Vector2=metric(value,mode);polygon.append(p);result=result.expand(p) if found else Rect2(p,Vector2.ZERO);found=true
	if mode=="2d":return preload("res://scripts/builder/citizen_obstacles_2d.gd").polygon(polygon)
	return [result] if result.has_area() else []

static func compile(room: Dictionary,library: RefCounted) -> Dictionary:
	var mode: String=room.get("mode","");var result: Dictionary={"mode":mode,"floors":{},"stations":[],"links":room.get("floor_links",[]).duplicate(true),"signature":JSON.stringify(room).sha256_text(),"semantic_revision":"","virtual":false,"notices":[]}
	if mode not in ["2d","3d"] or not Floors.valid(room):result["notices"].append("The room or floor plan is invalid.");return result
	for definition in Floors.definitions(room):
		var data: Dictionary=definition["room"];var uid: String=definition["uid"];var obstacles: Array[Rect2]=[]
		for link in room.get("floor_links",[]):
			if link["kind"]!="elevator" or not preload("res://scripts/builder/floor_elevator_plan.gd").stops(room,link).any(func(stop: Dictionary):return stop["uid"]==uid):continue
			var half: float=float(link["width"])*.5+.25;var center:=Vector2(link["start"][0],link["start"][1]);var box:=Rect2(center-Vector2.ONE*half,Vector2.ONE*half*2)
			if mode=="3d":obstacles.append(box)
			else:
				var polygon:=PackedVector2Array()
				for corner in [box.position,Vector2(box.end.x,box.position.y),box.end,Vector2(box.position.x,box.end.y)]:polygon.append(metric(Vector3(Grid.pixels(corner).x,Grid.pixels(corner).y,0),mode))
				obstacles.append_array(preload("res://scripts/builder/citizen_obstacles_2d.gd").polygon(polygon))
		var floor: Dictionary={"uid":uid,"height":definition["height"],"shown":Layers.shown(data,"Ground"),"obstacles":obstacles,"terrain":JSON.parse_string(JSON.stringify([data.get("terrain",{}),data.get("terrain_vertices",[]),data.get("water_cells",[])]))}
		floor["surface"]={"terrain":floor["terrain"][0],"terrain_vertices":floor["terrain"][1],"water_cells":floor["terrain"][2]}
		floor["surface_heights"]=preload("res://scripts/builder/terrain_plan.gd").lookup(floor["surface"])
		floor["passages"]=preload("res://scripts/builder/floor_terrain_plan.gd").passages(room,uid)
		var exit: Array=data.get("exit",[0,60,0] if mode=="2d" else [0,.2,2.5]);floor["exit"]=Vector3(exit[0],exit[1],exit[2])
		if mode=="3d" and absf(floor["exit"].y)<=.25 and preload("res://scripts/builder/terrain_plan.gd").settings(floor["surface"])["enabled"]:floor["exit"]=walking_point(floor,floor["exit"],mode)
		result["floors"][uid]=floor
		if not floor["shown"]:continue
		for item in data.get("objects",[]):
			if not library.assets.has(item.get("asset","")) or item.has("missing_asset") or not item.get("visible",true) or not Layers.shown(data,Layers.layer(item,library)):continue
			obstacles.append_array(obstacles_for(item,mode,library))
			var profile: Dictionary=Props.profile(item)
			if profile.get("kind","") not in ["seat","appliance"]:continue
			var station: Dictionary={"uid":item["uid"],"floor":uid,"kind":profile["kind"],"name":item.get("name",library.assets[item["asset"]]["name"]),"duration":profile["duration"],"item":item.duplicate(true),"profile":profile,"reason":""}
			for key in ["approach","exit","customer","facing"]:station[key]=anchor(item,profile,key,mode,library)
			station["point"]=anchor(item,profile,"point",mode,library,false)
			result["stations"].append(station)
		obstacles.append_array(preload("res://scripts/builder/terrain_navigation.gd").obstacles(data,mode=="2d"))
	result["stations"].sort_custom(func(a: Dictionary,b: Dictionary):return (a["floor"]+":"+a["uid"])<(b["floor"]+":"+b["uid"]))
	var floor_semantics: Array=[];var station_values: Array=[];var occupied: Dictionary={}
	for uid in result["floors"]:
		var floor: Dictionary=result["floors"][uid];var boxes: Array=[]
		for box in floor["obstacles"]:boxes.append(JSON.stringify([float(box.position.x),float(box.position.y),float(box.size.x),float(box.size.y)]))
		boxes.sort();floor_semantics.append(JSON.stringify([uid,float(floor["height"]),floor["shown"],boxes,vector_values(floor["exit"]),floor["terrain"]]))
	for station in result["stations"]:
		var floor: Dictionary=result["floors"][station["floor"]]
		station["semantic"]=station_semantics(station);station_values.append(station["semantic"])
		var spot: String=JSON.stringify([station["floor"],vector_values(station["point"]),vector_values(station["approach"])])
		station["checks"]=station_checks(station,floor,mode,occupied.has(spot))
		station["reason"]=""
		for check in station["checks"]:
			if not check["ok"]:station["reason"]=check["message"]
		occupied[spot]=true
	floor_semantics.sort();station_values.sort();result["semantic_revision"]=JSON.stringify([floor_semantics,station_values,JSON.parse_string(JSON.stringify(result["links"]))]).sha256_text()
	return result

# The runtime and setup inspector consume these same results. Keep every failure;
# the compatibility reason remains the last failed check in the existing order.
static func station_checks(station: Dictionary,floor: Dictionary,mode: String,duplicate: bool=false) -> Array:
	return [
		{"code":"station_overlap","ok":not duplicate,"message":"Another station occupies this same approach.","pass":"The station has a distinct approach."},
		{"code":"station_support","ok":supported(floor,station["approach"],mode) and supported(floor,station["exit"],mode),"message":"The station approach or exit has no supported walking surface.","pass":"Approach and exit have walking support."},
		{"code":"station_clearance","ok":clear(metric(station["approach"],mode),floor["obstacles"]) and clear(metric(station["exit"],mode),floor["obstacles"]),"message":"The station approach or exit is blocked.","pass":"Approach and exit have standing clearance."}
	]

static func station_routes(plan: Dictionary,station: Dictionary,entry_floor: String,entry: Vector3) -> Dictionary:
	var outbound: Dictionary=itinerary(plan,entry_floor,entry,station["floor"],station["approach"])
	var standing: Dictionary=itinerary(plan,station["floor"],station["approach"],station["floor"],station["exit"])
	var returning: Dictionary=itinerary(plan,station["floor"],station["exit"],entry_floor,entry)
	return {"ok":outbound["ok"] and standing["ok"] and returning["ok"],"outbound":outbound,"standing":standing,"returning":returning}

static func support_height(floor: Dictionary,point: Vector2) -> float:
	var terrain=preload("res://scripts/builder/terrain_plan.gd");var surface: Dictionary=floor.get("surface",{})
	if not terrain.settings(surface)["enabled"] or preload("res://scripts/builder/floor_terrain_plan.gd").contains(floor.get("passages",[]),point):return 0.0
	return terrain.sample(surface,point,floor.get("surface_heights",{}))["height"]

static func supported(floor: Dictionary,point: Vector3,mode: String) -> bool:
	return mode=="2d" or absf(point.y-support_height(floor,metric(point,mode)))<=.4

static func walking_point(floor: Dictionary,point: Vector3,mode: String) -> Vector3:
	return Vector3(point.x,support_height(floor,metric(point,mode))+.03,point.z) if mode=="3d" else point

static func clear(at: Vector2,obstacles: Array) -> bool:
	for box in obstacles:
		if box.grow(CLEARANCE).has_point(at):return false
	return true

static func segment_clear(from: Vector2,to: Vector2,obstacles: Array) -> bool:
	for raw in obstacles:
		var box: Rect2=raw.grow(CLEARANCE)
		if box.has_point(from) or box.has_point(to):return false
		var corners: Array=[box.position,Vector2(box.end.x,box.position.y),box.end,Vector2(box.position.x,box.end.y)]
		for index in 4:
			if Geometry2D.segment_intersects_segment(from,to,corners[index],corners[(index+1)%4])!=null:return false
	return true

static func walk(floor: Dictionary,from: Vector3,to: Vector3,mode: String) -> Dictionary:
	if not floor.get("shown",false):return {"ok":false,"reason":"Show Ground on this floor before residents can walk."}
	if not supported(floor,from,mode) or not supported(floor,to,mode):return {"ok":false,"reason":"The walking approach has no supported surface."}
	var start: Vector2=metric(from,mode);var goal: Vector2=metric(to,mode);var obstacles: Array=floor["obstacles"]
	if not clear(start,obstacles) or not clear(goal,obstacles):return {"ok":false,"reason":"The station or floor-link approach is blocked."}
	if start.distance_to(goal)<.001:return {"ok":true,"path":PackedVector2Array([start,goal]),"reason":""}
	var route: Dictionary=Citizens.route(start,goal,obstacles,CLEARANCE)
	if route["path"].is_empty():return {"ok":false,"reason":route["reason"]}
	var path:=PackedVector2Array([start]);path.append_array(route["path"]);path.append(goal)
	for index in range(1,path.size()):
		if not segment_clear(path[index-1],path[index],obstacles):return {"ok":false,"reason":"No clear walking route reaches the exact approach."}
	return {"ok":true,"path":path,"reason":""}

static func endpoint(link: Dictionary,upper: bool,mode: String,landing: bool=true) -> Vector3:
	var raw: Array=link["end"] if upper else link["start"];var at:=Vector2(raw[0],raw[1])
	# Itineraries wait on the safe landing. The controller adapter walks into
	# and out of the cabin only after the car and doors are ready.
	if landing and link["kind"]=="elevator":at+=Vector2(0,float(link["width"])*.5+.95)
	elif landing and mode=="3d":
		# Approach along the open ends; a side approach to the last tread hits
		# the authored handrail rather than reaching the flight entrance.
		var direction:=Vector2(link["end"][0]-link["start"][0],link["end"][1]-link["start"][1]).normalized()
		at+=direction*(.95 if upper else -.65)
	if mode=="2d":var pixel: Vector2=Grid.pixels(at);return Vector3(pixel.x,pixel.y,0)
	return Vector3(at.x,.03,at.y)

static func itinerary(plan: Dictionary,from_floor: String,from: Vector3,to_floor: String,to: Vector3) -> Dictionary:
	if not plan["floors"].has(from_floor) or not plan["floors"].has(to_floor):return {"ok":false,"reason":"The destination floor is unavailable."}
	var mode: String=plan["mode"];var queue: Array=[{"floor":from_floor,"point":from,"legs":[]}];var seen: Dictionary={}
	while not queue.is_empty():
		var state: Dictionary=queue.pop_front();var floor: Dictionary=plan["floors"][state["floor"]]
		if state["floor"]==to_floor:
			var route: Dictionary=walk(floor,state["point"],to,mode)
			if route["ok"]:
				var legs: Array=state["legs"].duplicate();legs.append({"kind":"walk","floor":to_floor,"from":state["point"],"to":to,"path":route["path"]});return {"ok":true,"legs":legs,"reason":""}
		for link in plan["links"]:
			var upper: bool=state["floor"]==link["upper"];var destinations: Array=[]
			if link["kind"]=="elevator":
				var low: float=plan["floors"][link["lower"]]["height"];var high: float=plan["floors"][link["upper"]]["height"]
				if floor["height"]<low or floor["height"]>high:continue
				for uid in plan["floors"]:
					if uid!=state["floor"] and plan["floors"][uid]["height"]>=low and plan["floors"][uid]["height"]<=high:destinations.append(uid)
			else:
				if not upper and state["floor"]!=link["lower"]:continue
				destinations.append(link["lower"] if upper else link["upper"])
			var at: Vector3=endpoint(link,upper,mode);var route: Dictionary=walk(floor,state["point"],at,mode)
			if not route["ok"]:continue
			for next in destinations:
				var identity: String=link["uid"]+":"+next
				if seen.has(identity):continue
				seen[identity]=true;var legs: Array=state["legs"].duplicate();legs.append({"kind":"walk","floor":state["floor"],"from":state["point"],"to":at,"path":route["path"]})
				var end: Vector3=endpoint(link,not upper,mode);legs.append({"kind":link["kind"],"link":link["uid"],"floor":state["floor"],"next_floor":next,"from":at,"to":end,"rise":absf(float(plan["floors"][next]["height"])-float(floor["height"])),"width":link["width"],"flight_from":endpoint(link,upper,mode,false),"flight_to":endpoint(link,not upper,mode,false)});queue.append({"floor":next,"point":end,"legs":legs})
	return {"ok":false,"reason":"No reachable floor link and walking route connects this station."}
