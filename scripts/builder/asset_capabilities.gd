extends RefCounted

# Presentation only. Never stamp placed records, build routes, request visits,
# create interiors, or change interaction candidates while describing an asset.
const Defaults=preload("res://scripts/builder/catalog_defaults.gd")
const Behavior=preload("res://scripts/builder/asset_behavior.gd")
const Business=preload("res://scripts/builder/business_plan.gd")
const Citizens=preload("res://scripts/builder/citizen_plan.gd")
const Services=preload("res://scripts/builder/service_plan.gd")
const Driving=preload("res://scripts/builder/driving_plan.gd")
const Props=preload("res://scripts/builder/prop_plan.gd")
const Repair=preload("res://scripts/builder/repair_assets.gd")
const KEYS=["Enter","Drive","Use","Citizens","Business","Services"]
var defaults: Dictionary={}

func build(library: RefCounted) -> void:
	defaults.clear()
	for id in library.assets:
		var item: Dictionary={"asset":id,"uid":"__library_potential__"}
		Defaults.stamp(item)
		defaults[id]=profiles(item,library)

static func profiles(item: Dictionary,library: RefCounted) -> Array[String]:
	var result: Array[String]=[]
	var behavior: Dictionary=Behavior.for_asset(item.get("asset",""),library)
	if behavior.get("building",false) or item.get("interior") is Dictionary:result.append("Enter")
	if not Driving.profile(item).is_empty():result.append("Drive")
	if behavior.get("door",false) or not Props.profile(item).is_empty():result.append("Use")
	if not Citizens.role(item).is_empty():result.append("Citizens")
	if Business.profile(item)["kind"]!="none":result.append("Business")
	if Services.profile(item)["kind"]!="none":result.append("Services")
	return result

func potential(id: String) -> Array:
	return defaults.get(id,[]).duplicate()

static func names(values: Array) -> String:
	return " · ".join(values) if not values.is_empty() else "Decorative"

func compact(id: String) -> String:
	var values: Array=potential(id)
	return names(values.slice(0,2))+(" +%d"%(values.size()-2) if values.size()>2 else "")

func describe(id: String,library: RefCounted=null) -> String:
	var result: String="Default potential: "+names(potential(id))+"\nSupported profiles describe new placements. Access, routes and overrides determine availability."
	if library:
		var missing: String=dependency_reason({"asset":id},library)
		if not missing.is_empty():result+="\nUnavailable: "+missing
	return result

static func dependency_reason(item: Dictionary,library: RefCounted) -> String:
	var id: String=item.get("asset","")
	if item.has("missing_asset"):return "Original asset is missing: "+str(item["missing_asset"])
	if not library.assets.has(id):return "Asset is absent from this library: "+id
	var asset: Dictionary=library.assets[id]
	if asset.get("unavailable",false):return "Prepared scene or required artwork is unavailable. Restore its files."
	# Raw source previews need not ship with a working prepared runtime scene.
	if not Repair.path_available(asset.get("path",""),{}):return "Prepared scene or a runtime dependency is missing: "+str(asset.get("path",""))
	for view in asset.get("data",{}).get("directions",{}).values():
		var path: String=preload("res://scripts/sprite_view.gd").path(view)
		if not FileAccess.file_exists(path):return "Required sprite artwork is missing: "+path
	for animation in asset.get("data",{}).get("animations",{}).values():
		for view in animation.get("directions",{}).values():
			var path: String=preload("res://scripts/sprite_view.gd").path(view)
			if not FileAccess.file_exists(path):return "Required action artwork is missing: "+path
	return ""

func selected(item: Dictionary,library: RefCounted,data: Dictionary,world: Node=null,runtimes: Dictionary={}) -> Dictionary:
	var id: String=item.get("asset","")
	var effective: Array[String]=profiles(item,library)
	var unavailable: String=dependency_reason(item,library)
	var badges: Array[Dictionary]=[]
	for key in effective:
		var status: Dictionary={"label":key,"state":"Supported","reason":reason(key,item,data)}
		if not unavailable.is_empty():status.merge({"state":"Unavailable","reason":unavailable},true)
		elif not item.get("visible",true) or not preload("res://scripts/builder/layers.gd").shown(data,preload("res://scripts/builder/layers.gd").layer(item,library)):
			status["reason"]="Object or layer is hidden."
		elif key=="Citizens" and not Citizens.settings(data)["enabled"]:pass
		elif key=="Services" and not Services.settings(data)["enabled"]:pass
		elif is_instance_valid(world):runtime_status(status,item,world,runtimes)
		badges.append(status)
	var inactive: Array=[]
	for key in potential(id):
		if key not in effective:inactive.append(key)
	return {"badges":badges,"potential":potential(id),"inactive":inactive,"unavailable":unavailable}

static func reason(key: String,item: Dictionary,data: Dictionary) -> String:
	match key:
		"Enter":return "Walk to an entrance. A safe landing is checked on entry."
		"Drive":return "Walk to the vehicle. Reach and a supported driving surface are checked before driving."
		"Use":return "Walk within reach with a clear approach; another interaction must finish first."
		"Citizens":return "Destination: "+Citizens.role(item)+(". A safe citizen route is required." if Citizens.settings(data)["enabled"] else ". Citizen simulation is disabled.")
		"Business":return "Hours, capacity and player access determine availability."
		"Services":return "Station: "+Services.profile(item)["kind"]+(". Connected roads, a reachable target and a free unit are required." if Services.settings(data)["enabled"] else ". City services are disabled.")
	return ""

static func runtime_status(status: Dictionary,item: Dictionary,world: Node,runtimes: Dictionary) -> void:
	var uid: String=item.get("uid","")
	var walk: Node=world.exploration
	var node: Node=world.instances.get(uid)
	# Interior editor records can use a different instance map; do not borrow an
	# exterior object's readiness merely because both rooms reuse a UID.
	if not is_instance_valid(node) or not node.is_visible_in_tree():status["reason"]="No visible runtime instance in this world.";return
	match status["label"]:
		"Business":
			var runtime: Node=runtimes.get("Business")
			if not is_instance_valid(runtime):return
			if not runtime.active or not runtime.service.businesses.has(uid):status["reason"]="Business runtime is paused or this object is unavailable.";return
			if runtime.service.businesses[uid]["config"]!=Business.profile(item):status["reason"]="Business override is waiting for the runtime to refresh.";return
			if not runtime.available(uid):status["reason"]="Closed at the current city time.";return
			if not runtime.player_near(uid):status["reason"]="Open. Walk to its entrance or enter its interior.";return
			var visit: Dictionary=runtime.service.visits.get("player",{})
			if visit.get("state","") in ["queued","active"]:
				if visit.get("business")==uid and visit["state"]=="active":ready(status,"Player is being served.")
				else:status["reason"]="A player visit is already in progress."
				return
			var count: int=0
			for entry in runtime.service.visits.values():
				if entry["business"]==uid and entry["state"]=="active":count+=1
			if count>=Business.profile(item)["capacity"]:status["reason"]="Open; all service places are occupied.";return
			if runtime.service.visits.size()>=runtime.service.MAX_VISITORS and not runtime.service.visits.has("player"):status["reason"]="Visitor limit reached.";return
			ready(status,"Open, player is at the entrance, and a service place is free.")
		"Use":
			if not walk.enabled or walk.entering:return
			if not walk.walk_allowed():status["reason"]="Finish the current vehicle, prop or floor interaction first.";return
			if walk.props and not walk.props.active.is_empty():status["reason"]="Finish the current prop interaction first.";return
			var candidate: Dictionary=Props.nearby(walk)
			if candidate.get("node")!=node:return
			if candidate["profile"]["kind"]=="switch" and walk.props.target(candidate).is_empty():status["reason"]="Switch target is missing or unavailable in this room.";return
			ready(status,"Player is within reach with a clear approach.")
		"Drive":
			if walk.driving and not walk.driving.active.is_empty() and walk.driving.active.get("node")==node:ready(status,"Player is driving this vehicle.")
		"Citizens":
			var runtime: Node=runtimes.get("Citizens")
			if not is_instance_valid(runtime):return
			if not runtime.active or runtime.paused:status["reason"]="Citizen preview is paused or inactive.";return
			if not runtime.plan.get("settings",{}).get("enabled",false):return
			if not runtime.plan.get("lookup",{}).has(uid):status["reason"]="No safe destination approach in the current citizen plan.";return
			for resident in runtime.residents:
				if resident.get("target")==uid and is_instance_valid(resident.get("actor")) and not resident.get("blocked",false) and float(resident.get("stalled",0))==0 and not resident.get("path",[]).is_empty():ready(status,"A citizen has a verified route to this destination.");return
			status["reason"]="Destination is registered. No current citizen route to it has been verified."
		"Services":
			var runtime: Node=runtimes.get("Services")
			if not is_instance_valid(runtime):return
			var plan: Dictionary=runtime.dispatch.plan
			if not runtime.active or runtime.paused:status["reason"]="Service preview is paused or inactive.";return
			if not plan.get("settings",{}).get("enabled",false):return
			if not plan.get("stations",{}).has(uid):status["reason"]="No supported ground approach in the current services plan.";return
			var station: Dictionary=plan["stations"][uid]
			if station["config"]!=Services.profile(item):status["reason"]="Station override is waiting for the runtime to refresh.";return
			var kind: String=station["config"]["kind"]
			var unit: Dictionary=Services.unit(kind)
			if runtime.dimension=="2d":
				var missing: String=dependency_reason({"asset":unit["worker_2d"]},runtime.library)
				if not missing.is_empty():status.merge({"state":"Unavailable","reason":"Service crew dependency: "+missing},true);return
			var selected: Array=plan.get("fleets",{}).get(kind,[])
			if not selected.any(func(profile: Dictionary):return dependency_reason(profile,runtime.library).is_empty()):
				status.merge({"state":"Unavailable","reason":"No available vehicle has a positive fleet weight for this service."},true)
				return
			if station["access"].is_empty():status["reason"]="No connected road within 16 units of the approach.";return
			var busy: int=runtime.dispatch.units.values().count(uid)
			if busy>=station["config"]["units"]:status["reason"]="All station crews are busy.";return
			var paths: Dictionary=plan.get("routes",{}).get(uid,{})
			var circuits: Dictionary=plan.get("circuits",{})
			for target in plan.get("targets",{}).values():
				if kind not in target["kinds"] or station["point"].distance_to(target["point"])>station["config"]["radius"]:continue
				for access in target["access"]:
					if not paths.get("costs",{}).has(access["section"]):continue
					var route: PackedStringArray=Services.path_to(paths,access["section"])
					var options: Array=circuits.get(Services.circuit_key(kind,route),[])
					if options.any(func(option: Dictionary):return dependency_reason(option["profile"],runtime.library).is_empty()):
						ready(status,"A free crew and a verified road route to an eligible target are available.")
						return
			status["reason"]="Connected road found. No eligible target route has been verified by dispatch yet."

static func ready(status: Dictionary,message: String) -> void:
	status["state"]="Ready now";status["reason"]=message

func selection_text(item: Dictionary,library: RefCounted,data: Dictionary,world: Node=null,runtimes: Dictionary={}) -> String:
	var report: Dictionary=selected(item,library,data,world,runtimes)
	var lines: PackedStringArray=["Default potential: "+names(report["potential"])]
	if report["badges"].is_empty():lines.append("Current: Decorative · no enabled capability profile.")
	for badge in report["badges"]:lines.append(badge["label"]+" · "+badge["state"]+" — "+badge["reason"])
	if not report["inactive"].is_empty():lines.append("Inactive on this object: "+names(report["inactive"])+" (disabled or overridden; older objects retain their saved defaults).")
	if not report["unavailable"].is_empty():lines.append(report["unavailable"])
	return "\n".join(lines)

func studio_text(studio: Control) -> String:
	var items: Array=studio.selection_items()
	if items.size()>1:return "Capabilities · Mixed selection\nSelect one object to inspect its overrides and current availability."
	if items.is_empty():return describe(studio.selected_tile().get("asset",studio.asset_id),studio.library)
	var runtimes: Dictionary={}
	if studio.business_tools:runtimes["Business"]=studio.business_tools.managers.get(studio.mode)
	if studio.citizen_tools:runtimes["Citizens"]=studio.citizen_tools.managers.get(studio.mode)
	if studio.service_tools:runtimes["Services"]=studio.service_tools.managers.get(studio.mode)
	return selection_text(items[0],studio.library,studio.current().data,studio.worlds[studio.mode],runtimes)

func studio_summary(studio: Control) -> String:
	var items: Array=studio.selection_items()
	if items.size()>1:return "Capabilities · Mixed"
	if items.is_empty():return "Potential: "+compact(studio.selected_tile().get("asset",studio.asset_id))
	var labels: PackedStringArray=[]
	var selected: String=""
	for state in ["Ready now","Unavailable","Supported"]:
		for key in KEYS:
			var text: String=key+" · "+state
			if studio.capability_note.text.contains(text):
				labels.append(text)
				if selected.is_empty():selected=text
	return selected+(" +%d"%(labels.size()-1) if labels.size()>1 else "") if not labels.is_empty() else "Current: Decorative"
