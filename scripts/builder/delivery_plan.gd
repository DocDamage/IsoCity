extends RefCounted

const PATH="res://resources/catalog/deliveries.json"
const Drive=preload("res://scripts/builder/driving_plan.gd")
const Traffic=preload("res://scripts/builder/traffic_plan.gd")
const Service=preload("res://scripts/builder/service_plan.gd")
const Business=preload("res://scripts/builder/business_plan.gd")
const Economy=preload("res://scripts/builder/economy_plan.gd")
const Anchors=preload("res://scripts/builder/entrance_anchors.gd")
const Terrain=preload("res://scripts/builder/terrain_plan.gd")
const MAX_SITES: int=64
const MAX_STOCK: int=256
const MAX_REWARD: int=100000
const PAD_RADIUS: float=2.25
const UNIT_SECONDS: float=.45
const FIELDS: Array[String]=["delivery_site","delivery_contract","delivery_vehicle"]
const SITE: Dictionary={"enabled":false,"offset_x":0.0,"offset_z":0.0,"capacity":32,"stock":{}}
const CONTRACT: Dictionary={"enabled":false,"destination":"","goods":"parcels","quantity":2,"reward":40,"deadline":120}
static var catalog: Dictionary={}

static func definitions() -> Dictionary:
	if catalog.is_empty():
		var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if raw is Dictionary and raw.get("version")==1: catalog=raw
	return catalog

static func goods() -> Dictionary:
	return definitions().get("goods",{})

static func eligible(item: Dictionary,field: String) -> bool:
	if item.has("missing_asset"): return false
	var asset: String=str(item.get("asset",""))
	if field=="delivery_vehicle": return definitions().get("vehicles",{}).has(asset)
	return asset in definitions().get("sites",[])

static func settings(item: Dictionary,field: String) -> Dictionary:
	var defaults: Dictionary=SITE if field=="delivery_site" else CONTRACT if field=="delivery_contract" else {"enabled":false,"capacity":definitions().get("vehicles",{}).get(item.get("asset",""),8)}
	var result: Dictionary=defaults.duplicate(true)
	var raw: Variant=item.get(field,{})
	if raw is Dictionary:
		for key in defaults:
			if raw.has(key): result[key]=raw[key]
	return result.duplicate(true)

static func valid(item: Dictionary,field: String) -> bool:
	var raw: Variant=item.get(field)
	if not eligible(item,field) or not raw is Dictionary: return false
	var config: Dictionary=settings(item,field)
	if not config["enabled"] is bool or raw.keys().any(func(key: Variant)->bool:return not config.has(key)): return false
	match field:
		"delivery_vehicle":
			return Economy.integer(config["capacity"],1,definitions()["vehicles"][item["asset"]])
		"delivery_site":
			if not Economy.integer(config["capacity"],1,MAX_STOCK) or not config["stock"] is Dictionary: return false
			for key in ["offset_x","offset_z"]:
				var value: Variant=config[key]
				if not (value is int or value is float) or not is_finite(float(value)) or absf(value)>32: return false
			var total: int=0
			for key in config["stock"]:
				if not goods().has(key) or not Economy.integer(config["stock"][key],0,MAX_STOCK): return false
				total+=int(config["stock"][key])
			return total<=config["capacity"]
		"delivery_contract":
			var destination: Variant=config["destination"]
			return destination is String and destination.length()<=128 and destination!=item.get("uid") and (not config["enabled"] or not destination.is_empty()) and goods().has(config["goods"]) and Economy.integer(config["quantity"],1,16) and Economy.integer(config["reward"],0,MAX_REWARD) and Economy.integer(config["deadline"],0,1800)
	return false

static func enabled(item: Dictionary,field: String) -> bool:
	return item.has(field) and valid(item,field) and item[field].get("enabled",false)

static func loading_point(item: Dictionary,mode: String,library: RefCounted) -> Variant:
	if not enabled(item,"delivery_site") or not library.assets.has(item["asset"]): return null
	var anchor: Dictionary=Anchors.profile(item,library)
	var config: Dictionary=settings(item,"delivery_site")
	var pad_offset:=Vector2(config["offset_x"],config["offset_z"])
	if item["asset"] in ["3d:HanX_Construction/Shipping_Container","3d:HanX_Construction/Site_Office"]:
		var front: Vector2=Drive.heading(Drive.yaw(item))
		var bounds: AABB=preload("res://scripts/builder/grid_fit.gd").bounds_for(item["asset"],library,false)
		var extent: float=bounds.end.z*float(item["scale"])*(2.0 if mode=="2d" else 1.0)
		return Traffic.metric(item["position"],mode)+front*(extent+4.0)+pad_offset
	if anchor.is_empty(): return null
	var sprite: bool=library.assets[item["asset"]]["mode"]=="2d"
	var a: Array=anchor["point"]
	var b: Array=anchor["arrival"]
	var door:=Vector3(a[0],0,a[1]) if sprite else Vector3(a[0],0,a[2])
	var arrival:=Vector3(b[0],0,b[1]) if sprite else Vector3(b[0],0,b[2])
	var offset: Vector3=(arrival-door).normalized()*5.0/maxf(.1,item["scale"])
	var geometry=load("res://scripts/builder/resident_activity_plan.gd")
	var local: Vector3=geometry.point(item,arrival+offset,mode,library,true)
	var point: Vector2=Traffic.metric([local.x,local.y,0] if mode=="2d" else [local.x,local.y,local.z],mode)
	return point+pad_offset

static func protected_area(item: Dictionary,mode: String,library: RefCounted) -> Rect2:
	var point: Variant=loading_point(item,mode,library)
	return Rect2() if point==null else Rect2(point-Vector2.ONE*PAD_RADIUS,Vector2.ONE*PAD_RADIUS*2)

static func site(item: Dictionary,data: Dictionary,library: RefCounted,heights: Dictionary,waters: Dictionary) -> Dictionary:
	var mode: String=data["mode"]
	var point: Variant=loading_point(item,mode,library)
	if point==null: return {}
	var height: float=0
	var safe: bool=absf(item["position"][2 if mode=="2d" else 1])<=.5
	if Terrain.settings(data)["enabled"]:
		var surface: Dictionary=Terrain.sample(data,point,heights)
		height=surface["height"]
		safe=surface["normal"].y>=.94
		for offset in [Vector2.ZERO,Vector2.UP,Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT]:
			var sample: Dictionary=Terrain.sample(data,point+offset*PAD_RADIUS,heights)
			var water: Variant=Terrain.water_level(data,point+offset*PAD_RADIUS,heights,waters)
			if absf(sample["height"]-height)>.5 or (water!=null and water-sample["height"]>.26): safe=false
	return {"uid":item["uid"],"point":point,"height":height,"safe":safe,"business":Business.profile(item),
		"name":str(item.get("name",library.assets[item["asset"]]["name"])).replace("_"," "),"config":settings(item,"delivery_site")}

static func is_open(place: Dictionary,hour: float) -> bool:
	return place["business"]["kind"]=="none" or Business.open(place["business"],hour)

static func required_assets(data: Dictionary) -> Array:
	var result: Array=[]
	for item in data.get("objects",[]):
		if not enabled(item,"delivery_contract"): continue
		var config: Dictionary=settings(item,"delivery_contract")
		var asset: String=goods()[config["goods"]][data["mode"]]
		if asset not in result: result.append(asset)
	return result
