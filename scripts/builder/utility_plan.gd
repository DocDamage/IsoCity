extends RefCounted

const Profiles=preload("res://scripts/builder/utility_profiles.gd")
const Connector=Profiles.Connector
const Economy=preload("res://scripts/builder/economy_plan.gd")
const KINDS: Array[String]=["water","power"]
const MAX_NODES: int=128
const MAX_EDGES: int=1024
const MAX_QUANTITY: int=10000
const MAX_SPAN: float=40.0
const SECONDS_PER_TICK: float=2.0
const FIELDS: Array[String]=["utilities","utility_nodes","utility_edges"]

static func enabled(data: Dictionary,kind: String) -> bool:
	var value: Variant=data.get("utilities",{})
	return value is Dictionary and value.get(kind,false)==true

static func authored(data: Dictionary,kind: String) -> bool:
	if data.get("utilities",{}).has(kind): return true
	for key in ["utility_nodes","utility_edges"]:
		for record in data.get(key,[]):
			if record["kind"]==kind: return true
	return false

static func valid_settings(value: Variant) -> bool:
	if not value is Dictionary: return false
	for key in value:
		if key not in KINDS or not value[key] is bool: return false
	return true

static func node_valid(value: Variant) -> bool:
	if not value is Dictionary or not Connector.id_valid(value.get("uid")) or not Connector.id_valid(value.get("object_uid")) or value.get("kind") not in KINDS or not value.get("enabled") is bool: return false
	for key in value:
		if key not in ["uid","object_uid","kind","enabled","quantity","priority"]: return false
	return (not value.has("quantity") or Economy.integer(value["quantity"],0,MAX_QUANTITY)) and (not value.has("priority") or Economy.integer(value["priority"],0,100))

static func edge_valid(value: Variant) -> bool:
	return value is Dictionary and value.size()==5 and value.get("enabled") is bool and value.get("kind") in KINDS and Connector.record_valid(value) and value["from"].size()==2 and value["to"].size()==2

static func objects(data: Dictionary) -> Dictionary:
	var result: Dictionary={}
	for item in data.get("objects",[]):
		if item is Dictionary and item.get("uid") is String: result[item["uid"]]=item
	return result

static func node_key(kind: String,uid: String) -> Array:
	return [kind,uid]

static func port_key(kind: String,reference: Dictionary) -> Array:
	return [kind,reference["object_uid"],reference["socket"]]

static func retained(data: Dictionary,library: RefCounted) -> Dictionary:
	var by_id: Dictionary=objects(data)
	var nodes: Array=[]
	var edges: Array=[]
	var active: Dictionary={}
	var ids: Dictionary={}
	var raw_nodes: Variant=data.get("utility_nodes",[])
	if raw_nodes is Array:
		for value in raw_nodes:
			if nodes.size()>=MAX_NODES: break
			if not node_valid(value) or ids.has(value["uid"]) or not by_id.has(value["object_uid"]): continue
			var key: Array=node_key(value["kind"],value["object_uid"])
			if active.has(key): continue
			var item: Dictionary=by_id[value["object_uid"]]
			var profile: Dictionary=Profiles.profile(item,library,value["kind"])
			if profile.is_empty() and not item.has("missing_asset"): continue
			if not profile.is_empty():
				var role: String=profile["role"]
				if value.has("quantity") and role not in ["source","consumer"] or value.has("priority") and role!="consumer": continue
			active[key]=profile
			nodes.append(value)
			ids[value["uid"]]=true
	ids.clear()
	var occupancy: Dictionary={}
	var raw_edges: Variant=data.get("utility_edges",[])
	if raw_edges is Array:
		for edge in raw_edges:
			if edges.size()>=MAX_EDGES: break
			if not edge_valid(edge) or ids.has(edge["uid"]): continue
			var first: Array=port_key(edge["kind"],edge["from"])
			var second: Array=port_key(edge["kind"],edge["to"])
			if occupancy.has(first) or occupancy.has(second): continue
			if not declared_port(edge["from"],edge["kind"],data["mode"],by_id,active) or not declared_port(edge["to"],edge["kind"],data["mode"],by_id,active): continue
			ids[edge["uid"]]=true
			occupancy[first]=true
			occupancy[second]=true
			edges.append(edge)
	return {"utility_nodes":nodes,"utility_edges":edges}

static func declared_port(reference: Dictionary,kind: String,mode: String,by_id: Dictionary,active: Dictionary) -> bool:
	var uid: String=reference["object_uid"]
	if not by_id.has(uid): return false
	var item: Dictionary=by_id[uid]
	var key: Array=node_key(kind,uid)
	if active.has(key):
		return item.has("missing_asset") or Profiles.port_definitions(active[key],kind).has(reference["socket"])
	for socket in Connector.sockets(item,mode):
		if socket["kind"]==kind and socket["id"]==reference["socket"]: return true
	return false

static func valid(data: Dictionary,library: RefCounted,depth: int) -> bool:
	var authored: bool=FIELDS.any(func(key: String)->bool:return data.has(key))
	if not authored: return true
	if depth>0 or data.get("interior_room",false) or not valid_settings(data.get("utilities",{})): return false
	var records: Dictionary=retained(data,library)
	return records["utility_nodes"]==data.get("utility_nodes",[]) and records["utility_edges"]==data.get("utility_edges",[])

static func normalize(data: Dictionary,library: RefCounted) -> void:
	if not data.has("utility_nodes") and not data.has("utility_edges"): return
	var records: Dictionary=retained(data,library)
	for key in records:
		if data.has(key): data[key]=records[key]

static func selection(data: Dictionary,items: Array) -> Dictionary:
	var selected: Dictionary={}
	for item in items: selected[item["uid"]]=true
	return {"utility_nodes":data.get("utility_nodes",[]).filter(func(node: Dictionary)->bool:return selected.has(node["object_uid"])).duplicate(true),
		"utility_edges":data.get("utility_edges",[]).filter(func(edge: Dictionary)->bool:
			return selected.has(edge["from"]["object_uid"]) and selected.has(edge["to"]["object_uid"])).duplicate(true)}

static func copy_into(data: Dictionary,records: Dictionary,remap: Dictionary,make_id: Callable) -> void:
	if data.get("interior_room",false): return
	for node in records.get("utility_nodes",[]):
		if not remap.has(node["object_uid"]): continue
		if not data.has("utility_nodes"): data["utility_nodes"]=[]
		if data["utility_nodes"].size()>=MAX_NODES: break
		var copy: Dictionary=node.duplicate(true)
		copy["uid"]=make_id.call()
		copy["object_uid"]=remap[node["object_uid"]]
		data["utility_nodes"].append(copy)
	for edge in records.get("utility_edges",[]):
		if not remap.has(edge["from"]["object_uid"]) or not remap.has(edge["to"]["object_uid"]): continue
		if not data.has("utility_edges"): data["utility_edges"]=[]
		if data["utility_edges"].size()>=MAX_EDGES: break
		var copy: Dictionary=edge.duplicate(true)
		copy["uid"]=make_id.call()
		for side in ["from","to"]: copy[side]["object_uid"]=remap[edge[side]["object_uid"]]
		data["utility_edges"].append(copy)

static func stamp(data: Dictionary,library: RefCounted,kind: String) -> int:
	var references: Dictionary={}
	for node in data.get("utility_nodes",[]):
		if node.get("kind")==kind: references[node["object_uid"]]=true
	for edge in data.get("utility_edges",[])+data.get("connections",[]):
		if edge.get("kind")==kind:
			references[edge["from"]["object_uid"]]=true
			references[edge["to"]["object_uid"]]=true
	var placed: Array=[]
	var laundry_enabled: bool=Profiles.Laundry.enabled(data)
	for item in data.get("objects",[]):
		if references.has(item["uid"]) or not Connector.sockets(item,data["mode"]).is_empty():
			var asset: Dictionary=library.assets.get(item["asset"],{})
			placed.append([item["uid"],item["asset"],item["position"],item["direction"],item["scale"],item.get("angle"),item.get("tilt"),
				item.get("visible",true),item.get("layer"),item.has("missing_asset"),item.get("name"),asset.get("unavailable"),asset.get("name"),
				item.get("interior",{}) if (kind=="power" or laundry_enabled) and references.has(item["uid"]) else null])
	return hash([data["mode"],enabled(data,kind),data.get("utility_nodes",[]),data.get("utility_edges",[]),data.get("connections",[]),
		placed,laundry_enabled,data.get("layers",{}),data.get("terrain",{}),data.get("terrain_vertices",[]),data.get("water_cells",[]),library.families.revision,
		Profiles.production_context(data) if kind=="power" else null])

static func compile(data: Dictionary,library: RefCounted,kind: String) -> Dictionary:
	var by_id: Dictionary=objects(data)
	var records: Dictionary=retained(data,library)
	var mode: String=data["mode"]
	var terrain=Profiles.Terrain
	var heights: Dictionary=terrain.lookup(data)
	var waters: Dictionary=terrain.lookup(data,true)
	var graph: Dictionary={"enabled":enabled(data,kind),"kind":kind,"nodes":{},"ports":{},"links":{},"occupied":{},"components":[]}
	var context: Dictionary=Profiles.production_context(data) if kind=="power" else {}
	var laundry_enabled: bool=Profiles.Laundry.enabled(data)
	var adjacency: Dictionary={}
	for item in by_id.values():
		var ports: Dictionary=Profiles.pipe_ports(item,mode,data,heights,kind)
		if ports.is_empty(): continue
		var uid: String=item["uid"]
		var reason: String=Profiles.availability(item,library,data)
		graph["ports"][uid]=ports
		adjacency[uid]=[]
		if not reason.is_empty():
			for port in ports.values(): port["reason"]=reason
	for node in records["utility_nodes"]:
		if node["kind"]!=kind: continue
		var uid: String=node["object_uid"]
		var item: Dictionary=by_id[uid]
		var profile: Dictionary=Profiles.profile(item,library,kind)
		var reason: String=Profiles.availability(item,library,data)
		var ports: Dictionary={}
		if reason.is_empty() and not profile.is_empty():
			ports=Profiles.terminal_ports(item,profile,library,data,heights,kind)
			reason=Profiles.access_reason(item,profile,ports,data,library,heights,waters)
		if not node["enabled"]: reason="This utility facility is disabled."
		if profile.is_empty() and reason.is_empty(): reason="The utility profile is unavailable."
		for port in ports.values(): port["reason"]=reason
		graph["ports"][uid]=ports
		adjacency[uid]=[]
		var quantity: int=int(node.get("quantity",profile.get("quantity",0)))
		var effect: String=profile.get("effect","")
		var building: bool=effect=="building" or kind=="water" and laundry_enabled and profile.get("role","")=="consumer"
		var fixtures: int=Profiles.interior_load(item["interior"],library,kind,laundry_enabled) if building and item.has("interior") else 0
		var limit: int=int(profile.get("capacity",0))
		graph["nodes"][uid]={"uid":node["uid"],"object_uid":uid,"asset":item["asset"],"role":profile.get("role","unknown"),
			"quantity":quantity+fixtures,"priority":int(node.get("priority",profile.get("priority",0))),"fixtures":fixtures,"effect":effect,
			"production":floori(quantity*float(context.get(profile.get("production",""),1.0))),
			"charge":int(profile.get("charge",limit)),"discharge":int(profile.get("discharge",limit)),
			"capacity":int(profile.get("capacity",0)),"reason":reason,"label":str(item.get("name",library.assets.get(item["asset"],{}).get("name",uid))).replace("_"," ")}
	for link in Connector.retained(data,data.get("connections",[])):
		if link["kind"]!=kind: continue
		var entry: Dictionary=link.duplicate()
		entry["enabled"]=true
		add_link(graph,adjacency,entry,true)
	for edge in records["utility_edges"]:
		if edge["kind"]==kind: add_link(graph,adjacency,edge,false)
	graph["components"]=components(adjacency,graph["nodes"])
	return graph

static func endpoint(graph: Dictionary,reference: Dictionary) -> Dictionary:
	return graph["ports"].get(reference["object_uid"],{}).get(reference["socket"],{})

static func join_reason(graph: Dictionary,first: Dictionary,second: Dictionary,physical: bool=false) -> String:
	if first["object_uid"]==second["object_uid"]: return "Choose ports on two different objects."
	var a: Dictionary=endpoint(graph,first)
	var b: Dictionary=endpoint(graph,second)
	if a.is_empty() or b.is_empty(): return "A utility port is missing or unavailable."
	for port in [a,b]:
		if not port.get("reason","").is_empty(): return port["reason"]
	if a["polarity"]==b["polarity"] and a["polarity"]!="tap": return "Pair an output with an input or a relay port." if graph["kind"]=="power" else "Pair an outlet with an inlet or a pipe end."
	if not physical:
		var distance: float=Vector3(a["point"].x,a["height"],a["point"].y).distance_to(Vector3(b["point"].x,b["height"],b["point"].y))
		if distance>MAX_SPAN: return "Ports are more than %.0f units apart. Add an intermediate connection."%MAX_SPAN
		if distance<.05: return "Choose distinct port positions."
	for reference in [first,second]:
		if graph["occupied"].has(port_key(graph["kind"],reference)): return "This port already has a connection."
	return ""

static func add_link(graph: Dictionary,adjacency: Dictionary,edge: Dictionary,physical: bool) -> void:
	var first: Dictionary=edge["from"]
	var second: Dictionary=edge["to"]
	var a: Dictionary=endpoint(graph,first)
	var b: Dictionary=endpoint(graph,second)
	var reason: String=join_reason(graph,first,second,physical)
	if reason.is_empty() and not edge["enabled"]: reason="This connection is disabled."
	var key: Array=[physical,edge["uid"]]
	graph["links"][key]={"uid":edge["uid"],"from":first,"to":second,"physical":physical,"reason":reason,
		"positions":[a["position"],b["position"]] if not a.is_empty() and not b.is_empty() else []}
	if reason.is_empty():
		adjacency[first["object_uid"]].append(second["object_uid"])
		adjacency[second["object_uid"]].append(first["object_uid"])
	# Saved connections reserve their ports even while disabled or interrupted.
	for reference in [first,second]:
		var id: Array=port_key(graph["kind"],reference)
		if not graph["occupied"].has(id): graph["occupied"][id]=key

static func components(adjacency: Dictionary,nodes: Dictionary) -> Array:
	var result: Array=[]
	var seen: Dictionary={}
	var ids: Array=adjacency.keys()
	ids.sort()
	for start in ids:
		if seen.has(start): continue
		var queue: Array=[start]
		var facilities: Array=[]
		seen[start]=true
		var index: int=0
		while index<queue.size():
			var uid: String=queue[index]
			index+=1
			if nodes.has(uid): facilities.append(uid)
			for neighbor in adjacency[uid]:
				if seen.has(neighbor): continue
				seen[neighbor]=true
				queue.append(neighbor)
		if not facilities.is_empty():
			facilities.sort()
			result.append(facilities)
	return result

static func allocate(graph: Dictionary,stock: Dictionary) -> Dictionary:
	var next: Dictionary={}
	var allocations: Dictionary={}
	var balance: Dictionary={"opening":0,"production":0,"delivered":0,"closing":0,"spill":0}
	for component in graph["components"]:
		var storage: Array=[]
		var demand: Array=[]
		var production: int=0
		var opening: int=0
		for uid in component:
			var node: Dictionary=graph["nodes"][uid]
			var operating: bool=graph["enabled"] and node["reason"].is_empty()
			match node["role"]:
				"source":
					if operating: production+=node["production"]
				"storage":
					var amount: int=clampi(int(stock.get(node["uid"],0)),0,node["capacity"])
					next[node["uid"]]=amount
					opening+=amount
					if operating: storage.append(node)
				"consumer":
					allocations[uid]=0
					if operating: demand.append(node)
		demand.sort_custom(func(a: Dictionary,b: Dictionary)->bool:
			return a["priority"]>b["priority"] if a["priority"]!=b["priority"] else a["uid"]<b["uid"])
		var stored: int=0
		for tank in storage: stored+=mini(next[tank["uid"]],tank["discharge"])
		var available: int=production+stored
		for consumer in demand:
			var served: int=mini(available,consumer["quantity"])
			allocations[consumer["object_uid"]]=served
			available-=served
		var delivered: int=production+stored-available
		var drain: int=maxi(0,delivered-production)
		var excess: int=maxi(0,production-delivered)
		for tank in storage:
			var id: String=tank["uid"]
			var used: int=mini(drain,mini(next[id],tank["discharge"]))
			next[id]-=used
			drain-=used
			var filled: int=mini(excess,mini(tank["capacity"]-next[id],tank["charge"]))
			next[id]+=filled
			excess-=filled
		balance["opening"]+=opening
		balance["production"]+=production
		balance["delivered"]+=delivered
		balance["spill"]+=excess
		balance["closing"]+=opening+production-delivered-excess
	return {"stock":next,"allocations":allocations,"balance":balance}
