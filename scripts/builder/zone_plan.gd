extends RefCounted
const PATH: String="res://resources/catalog/zoning.json"
const MAX_LOTS: int=128
enum Stage { VACANT, FOUNDATION, FRAMING, DEVELOPED, FINISHING }
# Keep the saved value for existing developed lots. The sequence defines pacing.
const STAGE_SEQUENCE: Array[int]=[Stage.VACANT,Stage.FOUNDATION,Stage.FRAMING,Stage.FINISHING,Stage.DEVELOPED]
const STAGE_NAMES: Dictionary={Stage.VACANT:"Vacant",Stage.FOUNDATION:"Foundation",Stage.FRAMING:"Framing",Stage.FINISHING:"Finishing",Stage.DEVELOPED:"Developed"}
const Traffic=preload("res://scripts/builder/traffic_plan.gd")
const Fit=preload("res://scripts/builder/grid_fit.gd")
const Entrances=preload("res://scripts/builder/entrance_anchors.gd")
const Layers=preload("res://scripts/builder/layers.gd")
const Economy=preload("res://scripts/builder/economy_plan.gd")
const Candidates=preload("res://scripts/builder/zone_candidates.gd")
const Citizen=preload("res://scripts/builder/citizen_plan.gd")
static var catalog: Dictionary={}
static func definitions() -> Dictionary:
	if catalog.is_empty():
		var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(PATH)); catalog=raw if raw is Dictionary else {}
	return catalog
static func settings(data: Dictionary) -> Dictionary:
	var raw: Dictionary=data.get("zoning",{}) if data.get("zoning",{}) is Dictionary else {}
	return {"enabled":raw.get("enabled",false) if raw.get("enabled",false) is bool else false,
		"stage_seconds":Traffic.number(raw.get("stage_seconds",12),12,2,300),"seed":int(Traffic.number(raw.get("seed",1),1,1,2147483647))}
static func valid_settings(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.has("enabled") and not value["enabled"] is bool: return false
	if value.has("stage_seconds") and (not (value["stage_seconds"] is int or value["stage_seconds"] is float) or not is_finite(float(value["stage_seconds"])) or value["stage_seconds"]<2 or value["stage_seconds"]>300): return false
	return not value.has("seed") or Economy.integer(value["seed"],1,2147483647)
static func rectangle(lot: Dictionary) -> Rect2:
	var raw: Array=lot["rect"]; return Rect2(raw[0],raw[1],raw[2],raw[3])
static func valid_stage(stage: Variant) -> bool:
	return Economy.integer(stage,Stage.VACANT,Stage.FINISHING)
static func stage_name(lot: Dictionary) -> String:
	return STAGE_NAMES.get(int(lot.get("stage",Stage.VACANT)),"Vacant")
static func stage_rank(lot: Dictionary) -> int:
	return STAGE_SEQUENCE.find(int(lot.get("stage",Stage.VACANT)))
static func stage_dressed(lot: Dictionary) -> bool:
	return int(lot.get("stage",Stage.VACANT)) in [Stage.FOUNDATION,Stage.FRAMING,Stage.FINISHING]
static func valid_lots(value: Variant,mode: String,library: RefCounted) -> bool:
	if not value is Array or value.size()>MAX_LOTS: return false
	var seen: Dictionary={}; var buildings: Dictionary={}; var rectangles: Array[Rect2]=[]
	for lot in value:
		if not lot is Dictionary or not lot.get("uid") is String or lot["uid"].is_empty() or lot["uid"].length()>128 or seen.has(lot["uid"]): return false
		seen[lot["uid"]]=true
		if not lot.get("kind") in definitions() or not lot.get("name","") is String or not Candidates.valid_options(lot): return false
		if lot.has("selection") and not Candidates.selection_valid(lot["selection"]):return false
		if not lot.get("visible",true) is bool or not lot.get("locked",false) is bool: return false
		if not lot.get("rect") is Array or lot["rect"].size()!=4: return false
		for n in lot["rect"]:
			if not (n is int or n is float) or not is_finite(float(n)) or absf(n)>100000: return false
		if lot["rect"][2]<4 or lot["rect"][2]>64 or lot["rect"][3]<4 or lot["rect"][3]>64: return false
		var bounds: Rect2=rectangle(lot)
		if rectangles.any(func(other: Rect2):return other.intersects(bounds)): return false
		rectangles.append(bounds)
		if not valid_stage(lot.get("stage",Stage.VACANT)): return false
		if lot.get("stage",Stage.VACANT)!=Stage.VACANT:
			var proposal: Variant=lot.get("proposal")
			if not proposal is Dictionary or proposal.get("zone_uid")!=lot["uid"] or not library.assets.has(proposal.get("asset")) or not preload("res://scripts/builder/asset_behavior.gd").for_asset(proposal["asset"],library).get("building",false): return false
			if not proposal.get("uid") is String or proposal["uid"].is_empty() or proposal["uid"].length()>256: return false
			if buildings.has(proposal["uid"]): return false
			buildings[proposal["uid"]]=true
			var sample: Dictionary={"title":"Zoning proposal","mode":mode,"objects":[proposal],"tiles":[],"night":false}
			if not load("res://scripts/builder/document.gd").valid(sample,mode,library): return false
	return true
static func construction_bounds(item: Dictionary,mode: String,library: RefCounted) -> AABB:
	# Upright sprite footprints depend on their authored ground rectangle, not
	# picture height. Do not instantiate every palette's sprite/texture merely
	# to obtain X/Z extents. Tilted sprites retain the complete geometry path.
	var tilt: Array=item.get("tilt",[0,0])
	if mode=="3d" and library.assets[item["asset"]]["mode"]=="2d" and not library.is_ground_tile(item["asset"]) and is_zero_approx(float(tilt[0])) and is_zero_approx(float(tilt[1])):
		var views: Dictionary=library.assets[item["asset"]]["data"]["directions"];var view: Dictionary=views.get(item["direction"],views.get("SE",views.values()[0]));var foot: Array=view.get("footprint",[1,1]);var size: float=float(item["scale"])
		return Transform3D(Fit.sprite_basis(item,library).scaled(Vector3.ONE*size),Vector3.ZERO)*AABB(Vector3(-foot[0]*.5,0,-foot[1]*.5),Vector3(foot[0],0,foot[1]))
	return Fit.footprint_bounds(item,mode,library)
static func footprint(item: Dictionary,mode: String,library: RefCounted) -> Rect2:
	var raw: AABB=construction_bounds(item,mode,library)
	var scale: float=2.0 if mode=="2d" else 1.0
	return Rect2(Traffic.metric(item["position"],mode)+Vector2(raw.position.x,raw.position.z)*scale,Vector2(raw.size.x,raw.size.z)*scale)
static func approach(item: Dictionary,mode: String,library: RefCounted,arrival: bool=true) -> Vector2:
	var profile: Dictionary=Entrances.profile(item,library)
	var raw: Array=profile.get("arrival" if arrival else "point",[])
	var origin: Vector2=Traffic.metric(item["position"],mode)
	if raw.is_empty(): return origin
	if mode=="2d":
		var offset: Vector2
		if library.assets[item["asset"]]["mode"]=="2d":offset=Fit.pixels(Vector2(raw[0],raw[1])).rotated(deg_to_rad(float(item.get("angle",0))))*float(item["scale"])
		else:
			var source: Vector3=Basis.from_euler(preload("res://scripts/builder/rotation.gd").euler(item)*PI/180.0)*Vector3(raw[0],raw[1],raw[2])
			var view: Vector3=Basis.from_euler(Vector3(deg_to_rad(-30),deg_to_rad(45),0)).inverse()*source
			offset=Vector2(view.x,-view.y)*preload("res://scripts/builder/model_in_2d.gd").PIXELS_PER_UNIT*float(item["scale"])
		return origin+Traffic.metric([offset.x,offset.y,0],"2d")
	if library.assets[item["asset"]]["mode"]=="2d":
		var views: Dictionary=library.assets[item["asset"]]["data"]["directions"]; var view: Dictionary=views.get(item["direction"],views.get("SE",views.values()[0])); var foot: Array=view.get("footprint",[1,1])
		var point:=Vector3(raw[0]-foot[0]*.5,0,raw[1]-foot[1]*.5).rotated(Vector3.UP,deg_to_rad(float(item.get("angle",0))))*float(item["scale"])
		return origin+Vector2(point.x,point.z)
	var transformed: Vector3=Vector3(raw[0],raw[1],raw[2]).rotated(Vector3.UP,deg_to_rad(float(item["direction"])))*float(item["scale"])
	return origin+Vector2(transformed.x,transformed.z)
static func usable(item: Dictionary,data: Dictionary,library: RefCounted) -> bool:
	return library.assets.has(item["asset"]) and not library.assets[item["asset"]].get("unavailable",false) and not item.has("missing_asset") and item.get("visible",true) and Layers.shown(data,Layers.layer(item,library))
static func surroundings(data: Dictionary,lot: Dictionary,library: RefCounted) -> Dictionary:
	var center: Vector2=rectangle(lot).get_center(); var homes: int=0; var amenities: int=0
	for item in data.get("objects",[]):
		if not usable(item,data,library): continue
		var distance: float=center.distance_to(Traffic.metric(item["position"],data["mode"]))
		var kind: String=Economy.profile(item["asset"],library)["kind"]
		if Citizen.role(item)=="home" and distance<=96: homes+=1
		if distance<=64 and (kind in ["park","station"] or item["asset"] in definitions()["civic"][data["mode"]]): amenities+=1
	var required: int=definitions()[lot["kind"]]["homes_required"]
	var rate: float=1.0
	if lot["kind"]=="residential": rate+=minf(.75,amenities*.25)
	else: rate+=minf(.75,maxi(0,homes-required)*.15)
	return {"homes":homes,"amenities":amenities,"required":required,"rate":rate,"suitable":homes>=required}
static func road_access(data: Dictionary,lot: Dictionary) -> Dictionary:
	var network: Dictionary=Traffic.build(data); var bounds: Rect2=rectangle(lot)
	var best: Dictionary={}; var distance: float=INF
	for section in network["sections"].values():
		if section["neighbors"].is_empty(): continue
		var center: Vector2=Traffic.center(section["cell"],data["mode"])
		var nearest: Vector2=center.clamp(bounds.position,bounds.end)
		if center.distance_to(nearest)>12: continue
		var score: float=center.distance_squared_to(bounds.get_center())
		var key: String=preload("res://scripts/builder/roads.gd").key(section["cell"])
		if score<distance or is_equal_approx(score,distance) and key<best.get("section","~"):
			distance=score; best={"point":center,"section":key}
	return best
static func site_context(data: Dictionary,library: RefCounted) -> Dictionary:
	var obstacles: Array[Rect2]=[];var identities: Dictionary={};var roads: Array[Rect2]=[]
	for existing in data.get("objects",[]):
		identities[existing["uid"]]=true
		if usable(existing,data,library) and Layers.layer(existing,library)!="Ground":obstacles.append(footprint(existing,data["mode"],library))
	for section in data.get("roads",[]):
		var center: Vector2=Traffic.center(Vector2i(section["cell"][0],section["cell"][1]),data["mode"]);var half: float=preload("res://scripts/builder/road_settings.gd").outer_half(section)
		roads.append(Rect2(center-Vector2(4,half),Vector2(8,half*2)));roads.append(Rect2(center-Vector2(half,4),Vector2(half*2,8)))
	return {"objects":obstacles,"identities":identities,"roads":roads,"terrain_obstacles":preload("res://scripts/builder/terrain_navigation.gd").obstacles(data),"heights":preload("res://scripts/builder/terrain_plan.gd").lookup(data),"waters":preload("res://scripts/builder/terrain_plan.gd").lookup(data,true)}
static func site_failure(code: String,reason: String) -> Dictionary:return {"ok":false,"code":code,"reason":reason}
static func site_check(data: Dictionary,lot: Dictionary,library: RefCounted,source: Dictionary,road: Dictionary,people: Array[Vector2],context: Dictionary) -> Dictionary:
	var item: Dictionary=source.duplicate(true);var box: Rect2=footprint(item,data["mode"],library)
	if not rectangle(lot).grow(-.5).encloses(box):return site_failure("footprint","The planned building does not fit the lot margin. Enlarge it or choose a smaller design.")
	var site: Dictionary=preload("res://scripts/builder/terrain_site.gd").foundation(data,box,context["heights"],context["waters"])
	if not site["ok"]:return site_failure("terrain",site["reason"])
	if data["mode"]=="3d":item["position"][1]=site["height"]-construction_bounds(item,"3d",library).position.y
	if context["identities"].has(item["uid"]):return site_failure("identity","The proposed building identity already exists; restart the lot.")
	for occupied in context["objects"]:
		if occupied.grow(.5).intersects(box):return site_failure("obstruction","Existing objects obstruct the planned building.")
	for road_box in context["roads"]:
		if road_box.intersects(box):return site_failure("road","The planned building overlaps a road.")
	if people.any(func(point: Vector2):return box.grow(.7).has_point(point)):return site_failure("people","Waiting for people or vehicles to clear the building footprint.")
	var arrival: Vector2=approach(item,data["mode"],library);var doorway: Vector2=approach(item,data["mode"],library,false)
	if arrival.distance_to(doorway)<.05:return site_failure("entrance","The source has no distinct doorway and safe arrival point.")
	if data["mode"]=="3d" and library.assets[item["asset"]]["mode"]=="3d":
		var raw: Array=Entrances.profile(item,library)["arrival"];var relative: Vector3=Basis.from_euler(preload("res://scripts/builder/rotation.gd").euler(item)*PI/180.0)*Vector3(raw[0],raw[1],raw[2])*float(item["scale"])
		if absf(item["position"][1]+relative.y-site["height"])>.6:return site_failure("entrance","The supplied entrance landing is too far above or below the foundation.")
	var obstacles: Array[Rect2]=[box];obstacles.append_array(context["objects"]);obstacles.append_array(context["terrain_obstacles"])
	var route: Dictionary=Citizen.route(road["point"],arrival,obstacles,.35)
	if route["path"].is_empty() or route.get("goal",Vector2.INF).distance_to(arrival)>1.6:return site_failure("entrance","The entrance has no clear approach from its road.")
	return {"ok":true,"proposal":item,"box":box,"arrival":arrival,"path":route["path"]}
static func member_pose(data: Dictionary,lot: Dictionary,library: RefCounted,road: Dictionary,identity: String,id: String,definition: Dictionary,people: Array[Vector2],context: Dictionary,geometry_cache: Dictionary,rejected: Dictionary) -> Dictionary:
	var bounds: Rect2=rectangle(lot);var directions: Array=library.directions(id);directions.sort();var ranked: Array=[]
	for direction in directions:
		var anchor: Dictionary=Entrances.profile({"asset":id,"direction":direction},library)
		if not Entrances.valid_point(anchor,2 if library.assets[id]["mode"]=="2d" else 3):continue
		var kind: String=definition.get("zone",lot["kind"])
		var item: Dictionary={"uid":identity,"asset":id,"position":[0,0,0],"direction":direction,"scale":float(library.assets[id]["data"].get("default_scale",1)),"zone_uid":lot["uid"],"name":definitions()[kind]["label"]+" development"};preload("res://scripts/builder/catalog_defaults.gd").stamp(item)
		if kind=="residential":item["citizen_role"]="home"
		var box: Rect2=footprint(item,data["mode"],library);var cap: Array=definition["footprint_limit"]
		if minf(box.size.x,box.size.y)>minf(cap[0],cap[1]) or maxf(box.size.x,box.size.y)>maxf(cap[0],cap[1]):rejected["footprint"]="The source exceeds this design's reviewed footprint limit.";continue
		item["position"]=Traffic.world(bounds.get_center()-box.get_center(),data["mode"])
		if data["mode"]=="3d":item["position"][1]=-construction_bounds(item,"3d",library).position.y
		box=footprint(item,data["mode"],library);var arrival: Vector2=approach(item,data["mode"],library);var entry: Vector2=approach(item,data["mode"],library,false)
		var key: String=JSON.stringify([box.position.x,box.position.y,box.size.x,box.size.y,arrival.x,arrival.y,entry.x,entry.y,item["position"][1],anchor["arrival"],library.assets[id]["mode"]])
		var facing: Vector2=(arrival-entry).normalized();var toward: Vector2=(road["point"]-bounds.get_center()).normalized();var quality: float=facing.dot(toward)*100-arrival.distance_to(road["point"])
		ranked.append({"item":item,"key":key,"quality":quality})
	# Foundation height changes Y only; orientation quality uses ground-plane
	# coordinates. Test the best orientations first and stop at the first valid
	# one, preserving the original sorted-direction tie break.
	ranked.sort_custom(func(a: Dictionary,b: Dictionary):return a["item"]["direction"]<b["item"]["direction"] if a["quality"]==b["quality"] else a["quality"]>b["quality"])
	for pose in ranked:
		var item: Dictionary=pose["item"];var key: String=pose["key"]
		if not geometry_cache.has(key):geometry_cache[key]=site_check(data,lot,library,item,road,people,context)
		var checked: Dictionary=geometry_cache[key]
		if not checked["ok"]:rejected[checked["code"]]=checked["reason"];continue
		item["position"]=checked["proposal"]["position"].duplicate()
		return {"proposal":item,"path":checked["path"]}
	return {}
static func choice_result(data: Dictionary,lot: Dictionary,library: RefCounted,road: Dictionary,identity: String,people: Array[Vector2]=[],prepared_context: Dictionary={},prepared_inventory: Dictionary={}) -> Dictionary:
	# Neighborhood generation supplies a reviewed mixed-use family inventory;
	# both callers share the same eligibility, pose and two-stage seeded draw.
	var inventory: Dictionary=Candidates.groups(lot,data["mode"],library) if prepared_inventory.is_empty() else prepared_inventory
	if not inventory["ok"]:return inventory
	var context: Dictionary=site_context(data,library) if prepared_context.is_empty() else prepared_context
	var groups: Array=[];var poses: Dictionary={};var rejected: Dictionary={};var geometry_cache: Dictionary={}
	# Establish each family's eligibility before its weighted draw. A family
	# needs one usable appearance to qualify; its appearance count adds no weight.
	for group in inventory["groups"]:
		for id in group["members"]:
			var best: Dictionary=member_pose(data,lot,library,road,identity,id,group["definition"],people,context,geometry_cache,rejected);poses[id]=best
			if not best.is_empty():groups.append(group);break
	if groups.is_empty():
		for code in ["identity","people","obstruction","road","terrain","entrance","footprint"]:
			if rejected.has(code):return {"ok":false,"code":code,"reason":rejected[code],"rejections":rejected,"counts":inventory["counts"]}
		return site_failure("entrance","The installed members have no usable entrance orientation.")
	var chosen: Dictionary=Candidates.choose(groups,settings(data)["seed"],lot["uid"],inventory["revision"]);var fitting: Array=[]
	# Only the selected family needs its full eligible appearance list. Use the
	# same independent appearance salt and sorted IDs as the exhaustive draw.
	for group in groups:
		if group["definition"]["id"]!=chosen["family"]:continue
		for id in group["members"]:
			if not poses.has(id):poses[id]=member_pose(data,lot,library,road,identity,id,group["definition"],people,context,geometry_cache,rejected)
			if not poses[id].is_empty():fitting.append(id)
	fitting.sort();chosen["member"]=fitting[Candidates.draw(settings(data)["seed"],lot["uid"],inventory["revision"],"appearance/"+chosen["family"],fitting.size())]
	var pose: Dictionary=poses[chosen["member"]];var source_mode: String=library.assets[chosen["member"]]["mode"]
	var selection: Dictionary={"version":1,"family":chosen["family"],"revision":inventory["revision"],"theme":inventory["theme"],"density":chosen["definition"]["density"],"price":Economy.profile(chosen["member"],library)["construction"],"representation":"native" if source_mode==data["mode"] else ("model_in_2d" if data["mode"]=="2d" else "flat_sprite_in_3d")}
	return {"ok":true,"proposal":pose["proposal"],"approach_path":pose["path"],"selection":selection,"eligible_families":groups.size(),"counts":inventory["counts"],"geometry_checks":geometry_cache.size()}
static func future_assets(lot: Dictionary,mode: String,library: RefCounted,policy: Variant=null) -> Array:
	var groups: Dictionary=Candidates.groups(lot,mode,library,policy);var result: Array=[]
	for group in groups["groups"]:
		for id in group["members"]:
			for direction in library.directions(id):
				var item: Dictionary={"uid":"future","asset":id,"position":[0,0,0],"direction":direction,"scale":float(library.assets[id]["data"].get("default_scale",1))};var size: Vector2=footprint(item,mode,library).size;var cap: Array=group["definition"]["footprint_limit"]
				if size.x<=lot["rect"][2]-1 and size.y<=lot["rect"][3]-1 and minf(size.x,size.y)<=minf(cap[0],cap[1]) and maxf(size.x,size.y)<=maxf(cap[0],cap[1]):result.append(id);break
	result.sort();return result
static func candidate(data: Dictionary,lot: Dictionary,library: RefCounted,road: Dictionary,identity: String) -> Dictionary:
	return choice_result(data,lot,library,road,identity).get("proposal",{})
static func failure(reason: String) -> Dictionary: return {"ok":false,"reason":reason,"rate":0.0}
static func vehicle_points(vehicles: Array) -> Array[Vector2]:
	var result: Array[Vector2]=[]
	for car in vehicles:
		if not is_instance_valid(car.get("actor")) or not car["actor"].visible: continue
		var point: Vector2=car["point"]; var heading: Vector2=car.get("heading",Vector2.RIGHT); var side:=Vector2(-heading.y,heading.x)
		result.append(point)
		for sign_value in [-1,1]: result.append(point+heading*car.get("half_length",1.3)*sign_value); result.append(point+side*car.get("half_width",.6)*sign_value)
		if car.has("half_length"):
			for along in [-1,1]:
				for across in [-1,1]: result.append(point+heading*car["half_length"]*along+side*car.get("half_width",.6)*across)
	return result
static func evaluate(data: Dictionary,lot: Dictionary,library: RefCounted,people: Array[Vector2]=[]) -> Dictionary:
	if not settings(data)["enabled"]: return failure("Enable zoning to develop lots.")
	if not lot.get("visible",true) or lot.get("locked",false): return failure("This lot is hidden or locked.")
	if not Layers.shown(data,"Ground") or not Layers.shown(data,"Buildings") or Layers.locked(data,"Buildings"): return failure("Show Ground and show/unlock Buildings to develop lots.")
	if lot.get("stage",Stage.VACANT)==Stage.DEVELOPED:
		for item in data["objects"]:
			if item["uid"]==lot["proposal"]["uid"]: return {"ok":true,"reason":"Developed building remains editable.","rate":0.0,"complete":true}
		return {"ok":true,"reason":"Demolished building; lot will start a new development cycle.","rate":1.0,"regrow":true}
	var context: Dictionary=surroundings(data,lot,library)
	if not context["suitable"]: return failure("Needs %d nearby homes; currently %d within 96 units." % [context["required"],context["homes"]])
	var road: Dictionary=road_access(data,lot)
	if road.is_empty(): return failure("Needs connected roads within 12 units of the lot edge.")
	var item: Dictionary=lot.get("proposal",{});var choice: Dictionary={};var selection: Dictionary=lot.get("selection",{});var approach_path:=PackedVector2Array()
	if lot.get("stage",0)==0:
		choice=choice_result(data,lot,library,road,"growth_"+lot["uid"],people)
		if not choice["ok"]:return failure(choice["reason"])
		item=choice["proposal"];selection=choice["selection"];approach_path=choice["approach_path"]
	else:
		if not preload("res://scripts/builder/asset_collections.gd").available(item.get("asset",""),library) or not Candidates.source_ready(library.assets[item["asset"]]["path"],false):return failure("The saved building source is unavailable. Restore its pack; the construction plan is retained.")
		if not preload("res://scripts/builder/asset_palette_policy.gd").allowed(item["asset"],library):return failure(preload("res://scripts/builder/asset_palette_policy.gd").excluded(item["asset"],library))
		var checked: Dictionary=site_check(data,lot,library,item,road,people,site_context(data,library))
		if not checked["ok"]:return failure(checked["reason"])
		item=checked["proposal"];approach_path=checked["path"]
	var limit: int=Candidates.options(lot)["max_price"]
	if limit>0 and Economy.profile(item["asset"],library)["construction"]>limit:return failure("The saved plan exceeds the lot's construction-price limit. Raise it or explicitly restart the plan.")
	# Eligibility does not need to copy the city and rebuild both purchase
	# inventories. The actual completion still commits a full economy quote.
	var cost: int=Economy.profile(item["asset"],library)["construction"]
	if Economy.settings(data)["enabled"]:
		var account: Dictionary=data.get("economy_account",{})
		var cash: int=int(account.get("cash",Economy.settings(data)["starting_cash"]))
		if cash<cost: return failure("Insufficient construction budget: need %d credits; %d available." % [cost,maxi(0,cash)])
		if account.get("construction_total",0)+cost>Economy.LIMIT: return failure("Treasury limit reached.")
	return {"ok":true,"reason":"Ready · %d nearby homes · %d amenities · %.2f× growth" % [context["homes"],context["amenities"],context["rate"]],"rate":context["rate"],"proposal":item,"road":road,"approach_path":approach_path,"context":context,"cost":cost,"selection":selection,"eligible_families":choice.get("eligible_families",0)}
static func advance(source: Dictionary,uid: String,library: RefCounted,identity: String="",people: Array[Vector2]=[]) -> Dictionary:
	if identity.length()>256: return failure("The new building identity is too long.")
	var lot: Dictionary={}
	for entry in source.get("zones",[]):
		if entry["uid"]==uid: lot=entry; break
	if lot.is_empty(): return failure("This lot no longer exists.")
	if not valid_stage(lot.get("stage",Stage.VACANT)): return failure("The construction stage is invalid.")
	var state: Dictionary=evaluate(source,lot,library,people)
	if not state["ok"] or state.get("complete",false): return state
	if not state.get("regrow",false) and not Candidates.source_ready(library.assets[state["proposal"]["asset"]]["path"],true):return failure("Restore or reimport the selected building's prepared dependencies before construction. The saved plan and funds were preserved.")
	var data: Dictionary=source.duplicate(true); var next: Dictionary=data["zones"][source["zones"].find(lot)]
	if state.get("regrow",false): next["stage"]=0; next.erase("proposal");next.erase("selection"); return {"ok":true,"data":data,"reason":"Vacant lot ready for a new cycle."}
	if next.get("stage",0)==0:
		next["proposal"]=state["proposal"].duplicate(true)
		if not state.get("selection",{}).is_empty():next["selection"]=state["selection"].duplicate(true)
		next["proposal"]["uid"]=identity if not identity.is_empty() else "growth_"+str(Time.get_ticks_usec())+"_"+str(randi())
		if data["objects"].any(func(item: Dictionary):return item["uid"]==next["proposal"]["uid"]): return failure("The new building identity is already in use.")
		for other in data["zones"]:
			if other["uid"]!=uid and other.get("proposal",{}).get("uid","")==next["proposal"]["uid"]: return failure("Another lot already reserves this building identity.")
	else: next["proposal"]=state["proposal"].duplicate(true)
	next["stage"]=STAGE_SEQUENCE[stage_rank(next)+1]
	if next["stage"]==Stage.DEVELOPED:
		data["objects"].append(next["proposal"].duplicate(true))
		var quote: Dictionary=Economy.quote(source,data,library)
		if not quote["ok"]: return quote
		if quote.get("enabled",false): data["economy_account"]=quote["account"]
	return {"ok":true,"data":data,"reason":stage_name(next)}
