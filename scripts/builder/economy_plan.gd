extends RefCounted

# Currency is an integer game credit, independent of any real currency.
# A purchased unit is one placed object/tile/road section, regardless of scale.
const PATH: String="res://resources/catalog/economy.json"
const LIMIT: int=1000000000000
const BOOK_LIMIT: int=250000
const LEDGER_LIMIT: int=64
const SETTINGS: Dictionary={"enabled":false,"starting_cash":50000,"period_seconds":60,"refund_percent":25}
const RANGES: Dictionary={"starting_cash":[0,1000000000],"period_seconds":[10,3600],"refund_percent":[0,100]}
const TOTALS: Array[String]=["period","income_total","upkeep_total","construction_total","refund_total"]
static var catalog: Dictionary={}

static func integer(value: Variant,low: int,high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)==floorf(float(value)) and float(value)>=low and float(value)<=high

static func settings(data: Dictionary) -> Dictionary:
	var raw: Dictionary=data.get("economy",{}) if data.get("economy",{}) is Dictionary else {}
	var result: Dictionary=SETTINGS.duplicate()
	result["enabled"]=raw.get("enabled",false) if raw.get("enabled",false) is bool else false
	for key in RANGES:
		var value: Variant=raw.get(key,SETTINGS[key]); var bounds: Array=RANGES[key]
		if (value is int or value is float) and is_finite(float(value)):
			result[key]=int(clampf(floorf(float(value)),bounds[0],bounds[1]))
	return result

static func valid_settings(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.has("enabled") and not value["enabled"] is bool: return false
	for key in RANGES:
		if value.has(key) and not integer(value[key],RANGES[key][0],RANGES[key][1]): return false
	return true

static func prices() -> Dictionary:
	if catalog.is_empty():
		var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(PATH))
		catalog=raw if raw is Dictionary else {}
	return catalog

static func profile(asset: String,library: RefCounted) -> Dictionary:
	var behavior: Dictionary=preload("res://scripts/builder/asset_behavior.gd").for_asset(asset,library)
	var item: Dictionary={"asset":asset}
	var role: String=preload("res://scripts/builder/citizen_plan.gd").role(item)
	var kind: String="object"
	if behavior.get("ground",false): kind="ground"
	elif preload("res://scripts/builder/service_plan.gd").profile(item)["kind"]!="none": kind="station"
	elif preload("res://scripts/builder/business_plan.gd").profile(item)["kind"]!="none": kind="shop"
	elif role in ["home","work","shop","park"]: kind=role
	elif behavior.get("building",false): kind="building"
	elif behavior.get("vehicle",false): kind="vehicle"
	elif behavior.get("door",false): kind="door"
	var value: Dictionary=prices()["profiles"][kind].duplicate()
	value.merge(prices().get("assets",{}).get(asset,{}),true)
	value["kind"]=kind
	# Repair placeholders carry no earning or ongoing operating capacity.
	if not library.assets.has(asset) or library.assets[asset].get("unavailable",false) or library.assets[asset].get("hidden",false):
		value["income"]=0; value["upkeep"]=0
	return value

static func road_profile(road: Dictionary) -> Dictionary:
	var config: Dictionary=preload("res://scripts/builder/road_settings.gd").profile(road)
	var rates: Dictionary=prices()["roads"]
	var cost: int=rates["narrow"] if config["width"]==2 else rates["standard"]
	cost=int(round(float(cost)*rates["style_percent"][config["style"]]/100))
	if config["sidewalks"]: cost+=int(rates["sidewalks"])
	if road.get("crossing",false): cost+=int(rates["crossing"])
	return {"construction":cost,"upkeep":int(rates["upkeep"]),"income":0,"kind":"road",
		"token":JSON.stringify([config["width"],config["style"],config["sidewalks"],road.get("crossing",false)])}

static func inventory(data: Dictionary,library: RefCounted,path: Array=[],depth: int=0,result: Dictionary={}) -> Dictionary:
	# Never share the default mutable dictionary across independent calls.
	if depth==0: result={}
	if depth>4: return result
	for floor in data.get("floors",[]): inventory(floor["room"],library,path+["floor",floor["uid"],"room"],depth+1,result)
	for item in data.get("objects",[]):
		var key: Array=path+["object",str(item.get("uid",""))]
		var value: Dictionary=profile(str(item.get("asset","")),library)
		value["token"]=str(item.get("asset",""))
		if depth>0 or item.has("missing_asset"): value["income"]=0
		if item.has("missing_asset"): value["upkeep"]=0
		result[JSON.stringify(key)]=value
		if item.get("interior") is Dictionary: inventory(item["interior"],library,key+["interior"],depth+1,result)
	for tile in data.get("tiles",[]):
		var value: Dictionary=profile(str(tile.get("asset","")),library)
		value["token"]=str(tile.get("asset","")); value["income"]=0
		result[JSON.stringify(path+["tile",int(tile["cell"][0]),int(tile["cell"][1])])]=value
	for road in data.get("roads",[]):
		result[JSON.stringify(path+["road",int(road["cell"][0]),int(road["cell"][1])])]=road_profile(road)
	return result

static func starter_holdings(data: Dictionary, uid: String, library: RefCounted) -> Dictionary:
	var result: Dictionary = {}
	if not settings(data)["enabled"]: return result
	var holdings: Dictionary = inventory(data, library)
	for key in holdings:
		var path: Array = JSON.parse_string(key)
		if path.size() > 3 and path.slice(0, 3) == ["object", uid, "interior"]:
			result[key] = holdings[key]["token"]
	return result

static func fresh_account(data: Dictionary,library: RefCounted) -> Dictionary:
	var result: Dictionary={"cash":settings(data)["starting_cash"],"holdings":{},"ledger":[]}
	for key in TOTALS: result[key]=0
	# Existing content is a free starting city, with no refundable purchase basis.
	var units: Dictionary=inventory(data,library)
	for key in units: result["holdings"][key]={"token":units[key]["token"],"paid":0}
	return result

static func valid_account(value: Variant) -> bool:
	if not value is Dictionary or not integer(value.get("cash"),-LIMIT,LIMIT): return false
	for key in TOTALS:
		if not integer(value.get(key),0,LIMIT): return false
	if not value.get("holdings") is Dictionary or value["holdings"].size()>BOOK_LIMIT: return false
	for key in value["holdings"]:
		var held: Variant=value["holdings"][key]
		if not key is String or key.length()>2048 or not held is Dictionary or not held.get("token") is String or not integer(held.get("paid"),0,LIMIT): return false
	if not value.get("ledger") is Array or value["ledger"].size()>LEDGER_LIMIT: return false
	for row in value["ledger"]:
		if not row is Dictionary or not row.get("kind") in ["construction","period"] or not integer(row.get("cash"),-LIMIT,LIMIT): return false
		for key in ["period","income","upkeep","construction","refund"]:
			if not integer(row.get(key),0,LIMIT): return false
	return true

static func repair_account(raw: Variant) -> Dictionary:
	var source: Dictionary=raw if raw is Dictionary else {}
	var value: Dictionary=source.duplicate(true)
	# Never replace a damaged cash balance with the starting grant.
	value["cash"]=int(source["cash"]) if integer(source.get("cash"),-LIMIT,LIMIT) else 0
	for key in TOTALS: value[key]=int(source[key]) if integer(source.get(key),0,LIMIT) else 0
	value["holdings"]={}; value["ledger"]=[]
	if source.get("holdings") is Dictionary:
		for key in source["holdings"]:
			if value["holdings"].size()>=BOOK_LIMIT: break
			var held: Variant=source["holdings"][key]
			if key is String and key.length()<=2048 and held is Dictionary and held.get("token") is String and integer(held.get("paid"),0,LIMIT): value["holdings"][key]=held.duplicate(true)
	if source.get("ledger") is Array:
		for row in source["ledger"]:
			var probe: Dictionary=value.duplicate(); probe["ledger"]=[row]
			if valid_account(probe): value["ledger"].append(row.duplicate(true))
			while value["ledger"].size()>LEDGER_LIMIT: value["ledger"].pop_front()
	return value

static func account(data: Dictionary,library: RefCounted) -> Dictionary:
	return normalized_account(data["economy_account"]) if valid_account(data.get("economy_account")) else fresh_account(data,library)

static func normalized_account(source: Dictionary) -> Dictionary:
	var value: Dictionary=source.duplicate(true)
	for key in ["cash"]+TOTALS: value[key]=int(value[key])
	for held in value["holdings"].values(): held["paid"]=int(held["paid"])
	for row in value["ledger"]:
		for key in ["cash","period","income","upkeep","construction","refund"]: row[key]=int(row[key])
	return value

static func append_ledger(value: Dictionary,kind: String,income: int=0,upkeep: int=0,construction: int=0,refund: int=0) -> void:
	value["ledger"].append({"kind":kind,"period":value["period"],"cash":value["cash"],"income":income,"upkeep":upkeep,"construction":construction,"refund":refund})
	while value["ledger"].size()>LEDGER_LIMIT: value["ledger"].pop_front()

static func failure(reason: String) -> Dictionary:
	return {"ok":false,"reason":reason}

static func quote(before: Dictionary,after: Dictionary,library: RefCounted,complimentary: Dictionary={}) -> Dictionary:
	if not settings(before)["enabled"]: return {"ok":true,"enabled":false,"construction":0,"refund":0,"net":0}
	var value: Dictionary=account(before,library)
	var old: Dictionary=inventory(before,library); var next: Dictionary=inventory(after,library)
	if next.size()>BOOK_LIMIT: return failure("The economy purchase book is full.")
	var construction: int=0; var refund: int=0; var holdings: Dictionary={}
	for key in old:
		if next.has(key) and old[key]["token"]==next[key]["token"]: continue
		var held: Dictionary=value["holdings"].get(key,{})
		if held.get("token")==old[key]["token"]: refund+=int(floor(float(held["paid"])*settings(before)["refund_percent"]/100))
	for key in next:
		var token: String=next[key]["token"]
		if old.has(key) and old[key]["token"]==token:
			var held: Dictionary=value["holdings"].get(key,{})
			holdings[key]=held.duplicate(true) if held.get("token")==token else {"token":token,"paid":0}
		else:
			var cost: int=0 if complimentary.get(key)==token else int(next[key]["construction"]); construction+=cost
			holdings[key]={"token":token,"paid":cost}
	var cash: int=value["cash"]+refund-construction
	if construction>0 and cash<0:
		return {"ok":false,"reason":"Insufficient construction budget: need %d credits; %d available including refunds." % [construction,maxi(0,value["cash"]+refund)],"construction":construction,"refund":refund,"net":construction-refund}
	if absi(cash)>LIMIT or value["construction_total"]+construction>LIMIT or value["refund_total"]+refund>LIMIT: return failure("Treasury limit reached.")
	value["cash"]=cash; value["holdings"]=holdings
	value["construction_total"]+=construction; value["refund_total"]+=refund
	if construction>0 or refund>0: append_ledger(value,"construction",0,0,construction,refund)
	return {"ok":true,"enabled":true,"construction":construction,"refund":refund,"net":construction-refund,"account":value}

static func forecast(data: Dictionary,library: RefCounted) -> Dictionary:
	var income: int=0; var upkeep: int=0; var construction: int=0; var counts: Dictionary={}
	for unit in inventory(data,library).values():
		income+=int(unit["income"]); upkeep+=int(unit["upkeep"]); construction+=int(unit["construction"])
		counts[unit["kind"]]=int(counts.get(unit["kind"],0))+1
	return {"income":income,"upkeep":upkeep,"net":income-upkeep,"replacement_value":construction,"counts":counts}

static func settle(data: Dictionary,library: RefCounted) -> Dictionary:
	if not settings(data)["enabled"]: return failure("Economy mode is off; creative building is unlimited.")
	var value: Dictionary=account(data,library); var rates: Dictionary=forecast(data,library)
	var cash: int=value["cash"]+rates["net"]
	if absi(cash)>LIMIT or value["period"]>=LIMIT or value["income_total"]+rates["income"]>LIMIT or value["upkeep_total"]+rates["upkeep"]>LIMIT: return failure("Treasury limit reached.")
	value["cash"]=cash; value["period"]+=1; value["income_total"]+=rates["income"]; value["upkeep_total"]+=rates["upkeep"]
	append_ledger(value,"period",rates["income"],rates["upkeep"])
	return {"ok":true,"account":value,"income":rates["income"],"upkeep":rates["upkeep"],"net":rates["net"]}
