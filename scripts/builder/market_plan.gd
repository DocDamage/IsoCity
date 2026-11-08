extends RefCounted

const PATH="res://resources/catalog/market_days.json"
const Traffic=preload("res://scripts/builder/traffic_plan.gd")
const Terrain=preload("res://scripts/builder/terrain_plan.gd")
const Economy=preload("res://scripts/builder/economy_plan.gd")
const Business=preload("res://scripts/builder/business_plan.gd")
const Weather=preload("res://scripts/builder/weather_plan.gd")
const MAX_MARKETS: int=16
const MAX_VISITORS: int=12
const QUEUE_SPACING: float=1.45
const ARRIVAL_RADIUS: float=.9
const PREFIX: String="market/"
const DEFAULTS: Dictionary={"enabled":false,"open_hour":11.0,"close_hour":15.0,"repeat_days":1,"close_in_rain":true,
	"capacity":6,"queue":2,"stock_policy":"daily","goods_style":"supermarket","offset_x":0.0,"offset_z":14.0,"facing":0,"spacing":6.0,
	"vendors":[{"kind":"fruit","stock":8,"price":5}]}
static var catalog: Dictionary={}

static func definitions() -> Dictionary:
	if catalog.is_empty():
		var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if raw is Dictionary and raw.get("version")==1: catalog=raw
	return catalog

static func eligible(item: Dictionary) -> bool:
	return not item.has("missing_asset") and item.get("asset","") in definitions().get("hosts",[])

static func settings(item: Dictionary) -> Dictionary:
	var result: Dictionary=DEFAULTS.duplicate(true)
	var raw: Variant=item.get("market",{})
	if raw is Dictionary:
		for key in DEFAULTS:
			if raw.has(key): result[key]=raw[key]
	return result.duplicate(true)

static func number(value: Variant,low: float,high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value>=low and value<=high

static func valid(item: Dictionary) -> bool:
	var raw: Variant=item.get("market")
	if not eligible(item) or not raw is Dictionary or raw.keys().any(func(key: Variant)->bool:return not DEFAULTS.has(key)): return false
	var config: Dictionary=settings(item)
	if not config["enabled"] is bool or not config["close_in_rain"] is bool or config["stock_policy"] not in ["daily","creative","delivery"]: return false
	if config["goods_style"] not in ["supermarket","hanx"]: return false
	if not number(config["open_hour"],0,23.999) or not number(config["close_hour"],0,24): return false
	if not number(config["offset_x"],-48,48) or not number(config["offset_z"],-48,48) or not number(config["spacing"],4,12): return false
	if not Economy.integer(config["facing"],0,270) or int(config["facing"])%90!=0: return false
	if not Economy.integer(config["capacity"],1,MAX_VISITORS) or not Economy.integer(config["queue"],0,4) or not Economy.integer(config["repeat_days"],1,7): return false
	var vendors: Variant=config["vendors"]
	if not vendors is Array or vendors.is_empty() or vendors.size()>3: return false
	for entry in vendors:
		if not entry is Dictionary or entry.size()!=3 or not definitions()["vendors"].has(entry.get("kind")):
			return false
		if not Economy.integer(entry.get("stock"),0,99) or not Economy.integer(entry.get("price"),0,999): return false
		if config["stock_policy"]=="delivery" and entry["kind"] not in ["fruit","vegetables"]: return false
	return true

static func enabled(item: Dictionary) -> bool:
	return item.has("market") and valid(item) and item["market"].get("enabled",false)

static func market_id(host: String,index: int) -> String:
	return PREFIX+str(host.length())+"/"+host+"/"+str(index)

static func layout(item: Dictionary,mode: String,library: RefCounted) -> Dictionary:
	if not enabled(item): return {}
	var config: Dictionary=settings(item)
	var origin: Vector2=Traffic.metric(item["position"],mode)+Vector2(config["offset_x"],config["offset_z"])
	var radians: float=deg_to_rad(config["facing"])
	var front:=Vector2(roundf(sin(radians)),roundf(cos(radians)))
	var side:=Vector2(front.y,-front.x)
	var vendors: Dictionary={}
	var area:=Rect2()
	var pieces: Array[Rect2]=[]
	var first: bool=true
	var problem: String=""
	for index in config["vendors"].size():
		var preset: Dictionary=config["vendors"][index]
		var art: Dictionary=definitions()["vendors"][preset["kind"]]
		var goods: String=art["hanx_goods"] if config["goods_style"]=="hanx" else art["goods"]
		if not asset_available(art["stall"],library) or not asset_available(goods,library):
			problem="A required stall or product is unavailable."
			continue
		var center: Vector2=origin+side*(index-(config["vendors"].size()-1)*.5)*config["spacing"]
		var uid: String=market_id(item["uid"],index)
		var record: Dictionary={"uid":uid,"asset":art["stall"],"direction":str(int(config["facing"])),"position":Traffic.world(center,mode),"scale":.45 if mode=="2d" else .85}
		var zone=load("res://scripts/builder/zone_plan.gd")
		var stall: Rect2=zone.footprint(record,mode,library)
		if not stall.has_area(): stall=Rect2(center-Vector2.ONE,Vector2.ONE*2)
		var far: Vector2=stall.get_center()+stall.size*.5*front
		var checkout: Vector2=center+front*maxf(2.0,(far-center).dot(front)+(1.3 if mode=="2d" else .85))
		var queue: Array[Vector2]=[]
		for slot in int(config["queue"]): queue.append(checkout+front*(slot+1)*QUEUE_SPACING)
		var exit: Vector2=checkout+side*(2.1 if index%2==0 else -2.1)+front*.65
		var end: Vector2=checkout+front*(1+int(config["queue"]))*QUEUE_SPACING
		var walkway: Rect2=Rect2(checkout,Vector2.ZERO).expand(end).expand(exit).grow(.55)
		var footprint: Rect2=stall.grow(.2).merge(walkway)
		if pieces.any(func(previous: Rect2)->bool:return previous.intersects(footprint)):
			problem="Vendor aisles overlap. Increase the stall spacing."
		pieces.append(footprint)
		area=footprint if first else area.merge(footprint)
		first=false
		vendors[uid]={"id":uid,"host":item["uid"],"name":art["name"],"item":art["item"],"goods":goods,
			"record":record,"center":center,"stall":stall,"point":checkout,"queue":queue,"exit":exit,
			"stock":int(preset["stock"]),"price":int(preset["price"]),"creative":config["stock_policy"]=="creative"}
	return {"uid":item["uid"],"name":str(item.get("name","Market")),"config":config,"area":area,
		"pieces":pieces,"vendors":vendors,"problem":problem}

static func protected_area(item: Dictionary,mode: String,library: RefCounted) -> Rect2:
	return layout(item,mode,library).get("area",Rect2())

static func asset_available(id: String,library: RefCounted) -> bool:
	return library.assets.has(id) and not library.assets[id].get("unavailable",false) and ResourceLoader.exists(library.assets[id]["path"])

static func compile(data: Dictionary,library: RefCounted) -> Dictionary:
	var mode: String=data["mode"]
	var zone=load("res://scripts/builder/zone_plan.gd")
	var markets: Dictionary={}
	for item in data.get("objects",[]):
		if markets.size()>=MAX_MARKETS: break
		if not enabled(item) or not zone.usable(item,data,library): continue
		markets[item["uid"]]=layout(item,mode,library)
	if markets.is_empty(): return markets
	var obstacles: Array[Rect2]=[]
	var behavior=preload("res://scripts/builder/asset_behavior.gd")
	for item in data.get("objects",[]):
		if not zone.usable(item,data,library): continue
		var profile: Dictionary=behavior.for_asset(item["asset"],library)
		if profile.get("ground",false) or profile.get("collision","box")=="none": continue
		var height: float=item["position"][2 if mode=="2d" else 1]
		if height>1.8: continue
		var bounds: Rect2=zone.footprint(item,mode,library)
		if bounds.has_area(): obstacles.append(bounds)
	for road in data.get("roads",[]):
		var center: Vector2=Traffic.center(Vector2i(road["cell"][0],road["cell"][1]),mode)
		obstacles.append(Rect2(center-Vector2.ONE*4,Vector2.ONE*8))
	var sculpted: bool=Terrain.settings(data)["enabled"]
	var heights: Dictionary=Terrain.lookup(data) if sculpted else {}
	var waters: Dictionary=Terrain.lookup(data,true) if sculpted else {}
	for site in markets.values():
		if not site["problem"].is_empty(): continue
		for box in site["pieces"]:
			if obstacles.any(func(other: Rect2)->bool:return other.intersects(box)):
				site["problem"]="A stall or aisle overlaps a permanent object or road."
				break
		if not sculpted: continue
		for vendor in site["vendors"].values():
			var level: float=Terrain.sample(data,vendor["center"],heights)["height"]
			vendor["record"]["position"]=Traffic.world(vendor["center"],mode,level)
			vendor["height"]=level
			for point in [vendor["center"],vendor["point"],vendor["exit"]]+vendor["queue"]:
				var sample: Dictionary=Terrain.sample(data,point,heights)
				var water: Variant=Terrain.water_level(data,point,heights,waters)
				if sample["normal"].y<.94 or absf(sample["height"]-level)>.5 or water!=null and water-sample["height"]>.25:
					site["problem"]="The market needs a dry, level stall and aisle."
	return markets

static func active_cycle(site: Dictionary,hour: float,day: int,raining: bool) -> Variant:
	var config: Dictionary=site["config"]
	if not site["problem"].is_empty() or raining and config["close_in_rain"]: return null
	var window: Dictionary={"kind":"market","open_hour":config["open_hour"],"close_hour":config["close_hour"]}
	if not Business.open(window,hour): return null
	var cycle: int=day-1 if config["open_hour"]>config["close_hour"] and hour<config["close_hour"] else day
	return cycle if posmod(cycle,int(config["repeat_days"]))==0 else null

static func required_assets(data: Dictionary) -> Array:
	var result: Array=[]
	for item in data.get("objects",[]):
		if not enabled(item): continue
		var config: Dictionary=settings(item)
		for vendor in config["vendors"]:
			var art: Dictionary=definitions()["vendors"][vendor["kind"]]
			for asset in [art["stall"],art["hanx_goods"] if config["goods_style"]=="hanx" else art["goods"]]:
				if asset not in result: result.append(asset)
	return result
