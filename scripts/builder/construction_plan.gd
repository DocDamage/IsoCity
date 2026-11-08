extends RefCounted

const PATH="res://resources/catalog/construction_contracts.json"
const Deliveries=preload("res://scripts/builder/delivery_plan.gd")
const Zone=preload("res://scripts/builder/zone_plan.gd")
const TerrainSite=preload("res://scripts/builder/terrain_site.gd")
const REACH: float=1.6
static var catalog: Dictionary={}

static func recipe() -> Dictionary:
	if catalog.is_empty():
		var source: Variant=JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if source is Dictionary and source.get("version")==1: catalog=source["foundation"]
	return catalog

static func uid_valid(value: Variant) -> bool:
	return value is String and not value.is_empty() and value.length()<=128

static func valid(config: Dictionary) -> bool:
	return config.size()==4 and config.get("id")=="construction" and uid_valid(config.get("attempt")) and uid_valid(config.get("host_uid")) and uid_valid(config.get("pickup_uid")) and config["host_uid"]!=config["pickup_uid"]

static func enabled(data: Dictionary) -> bool:
	var scenario: Variant=data.get("scenario")
	return scenario is Dictionary and valid(scenario)

static func required_assets(data: Dictionary) -> Array[String]:
	var result: Array[String]=[]
	if not enabled(data) or recipe().is_empty(): return result
	result.append(Deliveries.goods()[recipe()["goods"]][data["mode"]])
	for task in recipe()["tasks"]: result.append(task["asset"])
	return result

static func records(data: Dictionary,config: Dictionary) -> Dictionary:
	var result: Dictionary={}
	for item in data["objects"]:
		if item["uid"]==config["pickup_uid"]: result["pickup"]=item
		if item["uid"]==config["host_uid"]: result["site"]=item
		if result.size()==2: break
	return result

static func failure(reason: String) -> Dictionary:
	return {"ok":false,"reason":reason}

static func inspect(data: Dictionary,library: RefCounted) -> Dictionary:
	if not enabled(data): return {}
	var config: Dictionary=data["scenario"]
	var definition: Dictionary=recipe()
	if definition.is_empty(): return failure("The foundation contract definition is missing.")
	var items: Dictionary=records(data,config)
	if items.size()!=2: return failure("A construction supply or site placement was removed.")
	for role in ["pickup","site"]:
		var item: Dictionary=items[role]
		var expected: String=definition["supply"] if role=="pickup" else definition["site"]
		if item["asset"]!=expected or not Zone.usable(item,data,library) or not Deliveries.enabled(item,"delivery_site"):
			return failure("Keep a visible shipping container and site office with enabled loading pads.")
		if not Zone.Candidates.source_ready(library.assets[item["asset"]]["path"],false):
			return failure("Restore the prepared shipping container and site office.")
		var rotation: Vector3=preload("res://scripts/builder/rotation.gd").euler(item)
		if not is_zero_approx(rotation.x) or not is_zero_approx(rotation.z):
			return failure("Keep both construction stations upright.")
		if Deliveries.enabled(item,"delivery_contract"):
			return failure("Reserve the two loading stations for this construction challenge. Disable their outgoing local contracts.")
	var goods: String=definition["goods"]
	var quantity: int=definition["quantity"]
	if items["pickup"]["delivery_site"].get("stock",{}).get(goods,0)<quantity:
		return failure("Stock at least %d units of masonry at the supply container."%quantity)
	var context: Dictionary=Zone.site_context(data,library)
	var buildings: Array[Rect2]=[]
	for item in data["objects"]:
		if Zone.usable(item,data,library) and Zone.Layers.layer(item,library)!="Ground" and Deliveries.Drive.profile(item).is_empty():
			buildings.append(Zone.footprint(item,data["mode"],library))
	var stations: Dictionary={}
	var network: Dictionary=Zone.Traffic.build(data)
	for role in ["pickup","site"]:
		var station: Dictionary=Deliveries.site(items[role],data,library,context["heights"],context["waters"])
		if station.is_empty() or not station["safe"] or Deliveries.Service.access(network,station["point"]).is_empty():
			return failure("Both loading pads need dry, level ground and a nearby connected road.")
		var pad: Rect2=Deliveries.protected_area(items[role],data["mode"],library)
		if overlaps(pad,context["roads"]) or overlaps(pad,buildings):
			return failure("Move both loading pads clear of roads and existing objects.")
		if protected_at(data,pad): return failure("Move the loading pads outside protected areas.")
		stations[role]=station
	if stations["pickup"]["point"].distance_to(stations["site"]["point"])<8:
		return failure("Separate the supply and site loading pads by at least 8 metres.")
	for asset in required_assets(data):
		if not library.assets.has(asset) or library.assets[asset].get("unavailable",false) or not Zone.Candidates.source_ready(library.assets[asset]["path"],false):
			return failure("Install the prepared HanX construction assets to run this contract.")
	var site: Dictionary=items["site"]
	var mode: String=data["mode"]
	var center: Vector2=Zone.Traffic.metric(site["position"],mode)
	var yaw: float=Deliveries.Drive.yaw(site)
	var forward: Vector2=Deliveries.Drive.heading(yaw)
	var right:=Vector2(forward.y,-forward.x)
	var rear: Vector2=center-forward*(2.5*float(site["scale"])*(2.0 if mode=="2d" else 1.0)+1.5)
	var reserved: Array=context["objects"].duplicate()
	for item in items.values(): reserved.append(Deliveries.protected_area(item,mode,library))
	var tasks: Array[Dictionary]=[]
	var walking_obstacles: Array[Rect2]=[]
	walking_obstacles.assign(context["objects"]+context["terrain_obstacles"])
	var last_approach: Vector2=stations["site"]["point"]
	for task in definition["tasks"]:
		var offset: Array=task["offset"]
		var at: Vector2=rear+right*float(offset[0])-forward*float(offset[1])
		var placement: Dictionary={"asset":task["asset"],"scale":task["scale"],"position":Zone.Traffic.world(at,mode),"direction":str(rad_to_deg(yaw))}
		var box: Rect2=Zone.footprint(placement,mode,library)
		var approach: Vector2=at
		var side: Vector2=right*(1.0 if float(offset[0])>=0 else -1.0)
		approach+=side*(absf(side.dot(box.size))*.5+1.15)
		var approach_box:=Rect2(approach-Vector2.ONE*.45,Vector2.ONE*.9)
		if overlaps(box.grow(.25),reserved) or overlaps(approach_box,reserved) or overlaps(box,context["roads"]) or overlaps(approach_box,context["roads"]):
			return failure("Clear the marked work area behind the site office and keep it off the road.")
		if protected_at(data,box) or protected_at(data,approach_box):
			return failure("Move the construction work area outside protected areas.")
		var ground: Dictionary=TerrainSite.foundation(data,box,context["heights"],context["waters"])
		var standing: Dictionary=TerrainSite.foundation(data,approach_box,context["heights"],context["waters"])
		if not ground["ok"] or not standing["ok"] or absf(ground["height"]-standing["height"])>.6:
			return failure("The work area needs a dry, level place to stand and install equipment.")
		var route: Dictionary=Zone.Citizen.route(last_approach,approach,walking_obstacles,.4)
		if route["path"].is_empty() or route.get("goal",Vector2.INF).distance_to(approach)>.6:
			return failure("Leave a walkable path from the unloading pad to each work marker.")
		placement["position"]=Zone.Traffic.world(at,mode,ground["height"])
		tasks.append({"id":task["id"],"title":task["title"],"placement":placement,"bounds":box,
			"approach":approach,"height":standing["height"]})
		reserved.append(box)
		walking_obstacles.append(box)
		last_approach=approach
	var storage: Dictionary=stations["site"]["config"]
	var used: int=0
	for units in storage["stock"].values(): used+=int(units)
	if storage["capacity"]-used<quantity: return failure("Leave room for %d masonry units at the site office."%quantity)
	var offer: Dictionary={"enabled":true,"destination":config["host_uid"],"goods":goods,"quantity":quantity,
		"reward":0,"deadline":0,"construction_attempt":config["attempt"]}
	return {"ok":true,"reason":"","config":config.duplicate(true),"offer":offer,"stations":stations,
		"tasks":tasks,"reward":int(definition["reward"])}

static func overlaps(bounds: Rect2,obstacles: Array) -> bool:
	return obstacles.any(func(other: Rect2)->bool:return bounds.intersects(other))

static func protected_at(data: Dictionary,bounds: Rect2) -> bool:
	for record in data.get("protected_areas",[]):
		var value: Array=record["rect"]
		if bounds.intersects(Rect2(value[0],value[1],value[2],value[3])): return true
	return false
