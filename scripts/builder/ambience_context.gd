extends RefCounted
const Plan=preload("res://scripts/builder/ambience_plan.gd")
var signature: int=0
var cached: Array[Dictionary]=[]
var rebuilds: int=0
var last_listener:=Vector3.ZERO
var last_right:=Vector3.RIGHT

func collect(root_data: Dictionary,world: Node,walking: bool,library: RefCounted,vehicles: Array=[],hour: float=12,editing: Dictionary={},edit_scope: String="",edit_height: float=0,citizens: Node=null,businesses: Node=null) -> Dictionary:
	var config: Dictionary=Plan.settings(root_data)
	if not config["enabled"] or (not walking and not config["preview_in_build"]):
		config["enabled"]=false; return {"sources":[],"listener":last_listener,"right":last_right,"config":config,"scope":"silent"}
	var active: Node=world; var data: Dictionary=root_data; var scope: String="city:"; var height: float=0
	var exploration: Node=world.exploration
	if exploration and exploration.interior:
		active=exploration.room_world(); data=active.data_state; scope="room:"+exploration.interior_uid+":"+exploration.active_floor()+":"
		if exploration.interior.floor_stack: height=float(exploration.interior.floor_stack.heights[exploration.active_floor()])
	elif not editing.is_empty(): active=world; data=editing; scope="room:"+edit_scope+":"; height=edit_height
	elif data.get("interior_room",false): scope="room:standalone:ground:"
	var mode: String=data["mode"]; var actor: Node=world.player
	if walking:
		var local: Variant=active.to_local(actor.global_position)
		if mode=="2d":
			var travel_height: float=float(actor.get_meta("floor_travel_height",0))
			if exploration and exploration.interior and exploration.interior.floor_stack and not exploration.interior.floor_stack.travel.is_empty():
				var travel: Dictionary=exploration.interior.floor_stack.travel
				if travel["entered"] and travel["phase"] in ["walk","return","fade_out"]:
					var path: Vector2=travel["path_end"]-travel["start"]; var progress: float=clampf((actor.position-travel["start"]).dot(path)/maxf(.01,path.length_squared()),0,1); travel_height=float(travel["rise"])*progress
			last_listener=Plan.point([local.x,local.y,float(actor.get_meta("terrain_height",0))+travel_height],mode,height)+Vector3.UP*1.2
		else: last_listener=local+Vector3.UP*(height+1.2)
	else:
		if mode=="2d":
			var local: Vector2=active.to_local(world.camera.global_position); last_listener=Plan.point([local.x,local.y,0],mode,height)+Vector3.UP*1.2
		else: last_listener=world.target+Vector3.UP*(height+1.2)
	last_right=Vector3(1,0,-1).normalized() if mode=="2d" else Vector3(world.camera.global_basis.x.x,0,world.camera.global_basis.x.z).normalized()
	var activity: Dictionary = live_activity(exploration,scope,citizens,businesses)
	var records: Array=[]
	for item in data["objects"]:
		if Plan.profile(item,activity.get(item["uid"],{})).is_empty(): continue
		var business: Dictionary=preload("res://scripts/builder/business_plan.gd").profile(item)
		records.append([item["uid"],item["asset"],item["position"],item["direction"],item["scale"],item.get("angle",0),item.get("tilt",[]),item.get("entrance_anchor",{}),item.get("audio",{}),item.get("visible",true),item.has("missing_asset"),business["kind"],preload("res://scripts/builder/business_plan.gd").open(business,hour)])
	var terrain_stamp: int=active.terrain.signature if active.terrain else 0
	var next: int=hash([scope,height,data.get("night",false),data.get("layers",{}),records,terrain_stamp,activity])
	if next!=signature:
		var instances: Dictionary=active.city_instances if "city_instances" in active else active.instances
		cached=Plan.emitters(data,library,hour,height,scope,instances,activity)
		if scope!="city:": cached.append(Plan.interior(data,height,scope))
		signature=next; rebuilds+=1
	var sources: Array=cached.duplicate()
	if scope=="city:":
		var seen: Dictionary={}
		for vehicle in vehicles:
			var node: Node=vehicle.get("actor")
			if not is_instance_valid(node) or not node.is_visible_in_tree() or vehicle.get("phase","")=="parked": continue
			if seen.has(node.get_instance_id()): continue
			seen[node.get_instance_id()]=true
			var value: Dictionary=Plan.definitions()["kinds"]["traffic"].duplicate(true); var local: Variant=world.to_local(node.global_position)
			var point: Vector3=local if mode=="3d" else Plan.point([local.x,local.y,float(node.get_meta("terrain_height",0))],mode)
			value.merge({"kind":"traffic","uid":"vehicle:"+str(node.get_instance_id()),"position":point+Vector3.UP*.5})
			value["gain"]*=.2+.8*clampf(float(vehicle.get("speed",0))/6,0,1); sources.append(value)
	return {"sources":sources,"listener":last_listener,"right":last_right,"config":config,"scope":scope}

func live_activity(exploration: Node, scope: String, citizens: Node, businesses: Node) -> Dictionary:
	var sources: Dictionary = {}
	if not is_instance_valid(exploration) or exploration.entering or exploration.photo.active: return sources
	if is_instance_valid(citizens) and citizens.active and not citizens.paused:
		school_activity(sources,scope,citizens,exploration)
	var arcade: Node = exploration.arcade
	if arcade and arcade.session.get("phase") == "playing" and arcade.session["stamp"][0] == scope:
		if arcade.available() and arcade.focus_available and arcade.valid_locks():
			add_activity(sources,arcade.session["uid"],"arcade",1.0)
	if scope != "city:": return sources
	if is_instance_valid(businesses) and businesses.active and businesses.outdoor_market():
		var market: RefCounted = businesses.market
		for uid in market.vendors:
			var vendor: Dictionary = market.vendors[uid]
			var host: String = vendor["host"]
			if market.active.has(host) and (market.count(uid) != 0 or not vendor["checkout"].is_empty()):
				var customers: int = market.people(host)+int(market.player_at_market(host,businesses.service))
				add_activity(sources,host,"market",.56+.11*mini(customers,4))
				if not sources[host].has("market_position"):
					var point: Vector2 = market.active[host]["site"]["area"].get_center()
					sources[host]["market_position"] = Vector3(point.x,float(vendor.get("height",0))+.7,point.y)
	var village: Node = exploration.village
	if village and village.exterior():
		for uid in village.book.batches:
			if village.book.sites[uid]["profile"]["role"] == "smith":
				add_activity(sources,uid,"workshop",1.0)
		for uid in village.book.orders:
			if not village.book.order(uid).is_empty():
				add_activity(sources,uid,"market",.72)
	return sources

func school_activity(sources: Dictionary, scope: String, citizens: Node, exploration: Node) -> void:
	var schools: RefCounted = citizens.schools
	if schools.sites.is_empty(): return
	if scope == "city:":
		var counts: Dictionary = {}
		for resident in citizens.residents:
			var school: String = schools.enrolled.get(resident["id"],"")
			var phase: String = schools.phase(school,citizens.hour)
			if phase not in ["arrival","break"]: continue
			var target: String = school if phase == "arrival" else schools.sites[school]["yard"]
			var actor: Node = resident["actor"]
			if resident["target"] != target or not is_instance_valid(actor) or not actor.is_visible_in_tree(): continue
			if resident["index"] < resident["path"].size() or not resident["waiting"].is_empty(): continue
			counts[target] = mini(5,counts.get(target,0)+1)
		for uid in counts: add_activity(sources,uid,"school",.37+.11*counts[uid])
	elif exploration.interior and citizens.activities:
		var owner: String = exploration.interior_uid
		var phase: String = schools.phase(owner,citizens.hour)
		if not phase in schools.Plan.CLASS_PHASES: return
		var floor: String = exploration.active_floor()
		for job in citizens.activities.scheduler.jobs.values():
			if job["building"] != owner or not job["hold_station"] or job["state"] != "service": continue
			if job.get("leave_requested",false) or job["station"]["floor"] != floor: continue
			if schools.enrolled.get(job["resident"]) == owner:
				add_activity(sources,job["station"]["uid"],"school",.86)

func add_activity(sources: Dictionary, uid: String, kind: String, intensity: float) -> void:
	if not sources.has(uid): sources[uid] = {}
	sources[uid][kind] = maxf(intensity,sources[uid].get(kind,0))

func reset() -> void: signature=0; cached.clear()
