extends RefCounted

const Traffic=preload("res://scripts/builder/traffic_plan.gd")
const Zone=preload("res://scripts/builder/zone_plan.gd")
const Fit=preload("res://scripts/builder/grid_fit.gd")
const Terrain=preload("res://scripts/builder/terrain_plan.gd")
const Layers=preload("res://scripts/builder/layers.gd")
const Economy=preload("res://scripts/builder/economy_plan.gd")
const Palettes=preload("res://scripts/builder/neighborhood_palettes.gd")
const PATTERNS: Array[String]=["grid","staggered","courtyard"]
const BLOCK_CELLS: int=10
const MAX_BLOCKS: int=4
static var catalog: Dictionary={}

static func themes() -> Dictionary:
	if catalog.is_empty():
		catalog=JSON.parse_string(FileAccess.get_file_as_string("res://resources/catalog/neighborhoods.json"))
	catalog.merge(Palettes.palettes(),true)
	return catalog

static func defaults() -> Dictionary:
	return {"seed":1,"density":65,"blocks":2,"pattern":"grid","theme":"homes","origin":[-10,-10]}

static func integer(value: Variant,low: int,high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)==floorf(float(value)) and value>=low and value<=high

static func valid_settings(raw: Variant) -> bool:
	if not raw is Dictionary: return false
	return integer(raw.get("seed"),1,2147483647) and integer(raw.get("density"),0,100) and integer(raw.get("blocks"),1,MAX_BLOCKS) and raw.get("pattern") in PATTERNS and raw.get("theme") in themes() and raw.get("origin") is Array and raw["origin"].size()==2 and integer(raw["origin"][0],-128,128) and integer(raw["origin"][1],-128,128)

static func bounds(config: Dictionary,mode: String) -> Rect2:
	var low: Vector2=Traffic.center(Vector2i(config["origin"][0],config["origin"][1]),mode)
	return Rect2(low-Vector2.ONE*4,Vector2.ONE*(int(config["blocks"])*BLOCK_CELLS*8+8))

static func road_cells(config: Dictionary) -> Array[Vector2i]:
	var cells: Dictionary={}; var blocks: int=int(config["blocks"]); var length: int=blocks*BLOCK_CELLS; var origin:=Vector2i(config["origin"][0],config["origin"][1])
	# All layouts retain the outer loop and connected vertical streets. Interior
	# cross-streets form square blocks, alternating junctions or long courtyards.
	for boundary in range(blocks+1):
		for along in range(length+1): cells[origin+Vector2i(boundary*BLOCK_CELLS,along)]=true
		for column in blocks:
			var included: bool=boundary in [0,blocks] or config["pattern"]=="grid"
			if config["pattern"]=="staggered": included=included or (column+boundary)%2==0
			if included:
				for along in range(column*BLOCK_CELLS,(column+1)*BLOCK_CELLS+1): cells[origin+Vector2i(along,boundary*BLOCK_CELLS)]=true
	var result: Array[Vector2i]=[]
	for cell in cells: result.append(cell)
	result.sort_custom(func(a: Vector2i,b: Vector2i)->bool:return a.x<b.x or (a.x==b.x and a.y<b.y))
	return result

static func failure(reason: String) -> Dictionary: return {"ok":false,"reason":reason}

static func beside_city(data: Dictionary,blocks: int,library: RefCounted) -> Array:
	var right: float=-INF
	for item in data["objects"]:
		if Layers.layer(item,library)!="Ground": right=maxf(right,Zone.footprint(item,data["mode"],library).end.x)
	for road in data.get("roads",[]): right=maxf(right,float(road["cell"][0])*8+4)
	for lot in data.get("zones",[]): right=maxf(right,Zone.rectangle(lot).end.x)
	return [clampi(ceili((right+16)/8),-128,128),-blocks*5] if is_finite(right) else [-blocks*5,-blocks*5]

static func identity(data: Dictionary,seed: int) -> String:
	var used: Dictionary={}
	for item in data["objects"]: used[item["uid"]]=true
	for road in data.get("roads",[]):
		if road.get("neighborhood_uid") is String: used[road["neighborhood_uid"]+":road"]=true
	for index in range(1,10001):
		var prefix: String="neighborhood_%d_%d"%[seed,index]
		if not used.keys().any(func(uid: String)->bool:return uid.begins_with(prefix+":")): return prefix
	return ""

static func nearest_road(point: Vector2,centers: Array[Vector2]) -> Vector2:
	var selected: Vector2=centers[0]; var distance: float=INF
	for center in centers:
		var next: float=point.distance_squared_to(center)
		if next<distance: selected=center; distance=next
	return selected

static func candidate(source: Dictionary,parcel: Rect2,palette: Array,random: RandomNumberGenerator,road: Vector2,uid: String,library: RefCounted,heights: Dictionary,waters: Dictionary) -> Dictionary:
	var offset: int=random.randi_range(0,palette.size()-1); var best: float=-INF; var chosen: Dictionary={}
	for index in palette.size():
		var asset: String=palette[(offset+index)%palette.size()]
		if not library.assets.has(asset) or library.assets[asset].get("unavailable",false): continue
		for direction in library.directions(asset):
			var item: Dictionary={"uid":uid,"asset":asset,"direction":direction,"scale":float(library.assets[asset]["data"].get("default_scale",1)),"position":[0,0,0]}
			preload("res://scripts/builder/catalog_defaults.gd").stamp(item)
			var box: Rect2=Zone.footprint(item,source["mode"],library)
			item["position"]=Traffic.world(parcel.get_center()-box.get_center(),source["mode"])
			box=Zone.footprint(item,source["mode"],library)
			if not parcel.grow(-1).encloses(box): continue
			var site: Dictionary=preload("res://scripts/builder/terrain_site.gd").foundation(source,box,heights,waters)
			if not site["ok"]: continue
			if source["mode"]=="3d": item["position"][1]=site["height"]-Fit.footprint_bounds(item,"3d",library).position.y
			var arrival: Vector2=Zone.approach(item,source["mode"],library); var facing: Vector2=(arrival-Zone.approach(item,source["mode"],library,false)).normalized()
			var score: float=facing.dot((road-parcel.get_center()).normalized())*100-arrival.distance_to(road)-index*.01
			if score>best: best=score; chosen=item
	return chosen

static func generate(source: Dictionary,config: Dictionary,library: RefCounted) -> Dictionary:
	if not valid_settings(config): return failure("Choose a seed, density from 0–100%, 1–4 blocks per side, a road layout, a theme and a road-grid origin within ±128.")
	if not load("res://scripts/builder/document.gd").valid(source,str(source.get("mode","")),library): return failure("Repair this city before generating a neighborhood.")
	if source.get("interior_room",false): return failure("Generate neighborhoods from the exterior city.")
	for layer in ["Ground","Buildings"]:
		if not Layers.shown(source,layer) or Layers.locked(source,layer): return failure("Show and unlock "+layer+" before generating a neighborhood.")
	var mode: String=source["mode"]; var region: Rect2=bounds(config,mode);var curated: bool=Palettes.palettes().has(config["theme"]);var inventory: Dictionary={};var appearance: Dictionary=Palettes.appearance_choice(Palettes.palettes()[config["theme"]],config["seed"]) if curated else {}
	if curated and config["density"]>0:
		inventory=Palettes.inventory(config["theme"],mode,library,appearance)
		if not inventory["ok"]:return inventory
	var theme: Dictionary=themes()[config["theme"]]
	if curated and mode=="2d" and not Palettes.usable("2d:"+theme["ground"],library):return failure("Restore or permit this theme's ground asset before generating the district.")
	# Generation is additive. Even hidden or individually locked objects reserve
	# their footprint; no authored object, owned interior or road is overwritten.
	for item in source["objects"]:
		if Layers.layer(item,library)!="Ground" and region.intersects(Zone.footprint(item,mode,library).grow(.5)): return failure("This area contains existing objects. Move the neighborhood origin to a clear area.")
	for lot in source.get("zones",[]):
		if region.intersects(Zone.rectangle(lot)): return failure("This area contains designated lots. Move the origin or edit those lots first.")
	for road in source.get("roads",[]):
		var center: Vector2=Traffic.center(Vector2i(road["cell"][0],road["cell"][1]),mode)
		if region.intersects(Rect2(center-Vector2.ONE*4,Vector2.ONE*8)): return failure("This area contains existing roads. Move the origin to a clear area.")
	var cells: Array[Vector2i]=road_cells(config)
	if cells.size()+source.get("roads",[]).size()>Traffic.MAX_SECTIONS: return failure("The generated roads would exceed the city's 4,096-section limit.")
	var heights: Dictionary=Terrain.lookup(source); var waters: Dictionary=Terrain.lookup(source,true); var centers: Array[Vector2]=[]
	for cell in cells:
		var center: Vector2=Traffic.center(cell,mode); centers.append(center)
		var reason: String=preload("res://scripts/builder/terrain_road_policy.gd").reason(source,center,heights,waters)
		if not reason.is_empty(): return failure("Cannot generate roads here: "+reason)
	var prefix: String=identity(source,int(config["seed"]))
	if prefix.is_empty(): return failure("No unused neighborhood identity is available.")
	var parcels: Array=[]; var blocks: int=int(config["blocks"])
	var origin: Vector2=Traffic.center(Vector2i(config["origin"][0],config["origin"][1]),mode)
	for x in blocks:
		for z in blocks:
			for corner in 4:
				var low: Vector2=origin+Vector2(x,z)*80+Vector2(8+(corner%2)*40,8+(corner/2)*40)
				parcels.append({"rect":Rect2(low,Vector2.ONE*24),"block":[x,z],"corner":corner})
	var random:=RandomNumberGenerator.new(); random.seed=int(config["seed"])
	# Fisher–Yates uses a local RNG; global city simulation randomness is untouched.
	for index in range(parcels.size()-1,0,-1):
		var swap: int=random.randi_range(0,index); var saved: Dictionary=parcels[index]; parcels[index]=parcels[swap]; parcels[swap]=saved
	var count: int=ceili(parcels.size()*float(config["density"])/100); var generated: Array=[]; var footprints: Array[Rect2]=[]; var approaches: Array=[]
	var working: Dictionary=source.duplicate(true);working["zoning"]={"seed":int(config["seed"])};working["roads"]=source.get("roads",[]).duplicate(true)
	for cell in cells:working["roads"].append({"cell":[cell.x,cell.y],"width":6,"style":theme["road_style"],"sidewalks":true,"crossing":false,"neighborhood_uid":prefix})
	var context: Dictionary=Zone.site_context(working,library) if curated else {}
	for index in count:
		var parcel: Dictionary=parcels[index]; var rectangle: Rect2=parcel["rect"]; var road: Vector2=nearest_road(rectangle.get_center(),centers)
		var item: Dictionary
		if curated:
			var lot: Dictionary={"uid":prefix+":"+str(index),"kind":"residential","rect":[rectangle.position.x,rectangle.position.y,rectangle.size.x,rectangle.size.y]};var chosen: Dictionary=Zone.choice_result(working,lot,library,{"point":road},lot["uid"],[],context,inventory)
			if not chosen["ok"]:return failure("No safe "+theme["label"]+" building fits this parcel: "+chosen["reason"])
			item=chosen["proposal"];item.erase("zone_uid");item["neighborhood_palette_selection"]={"version":1,"theme":config["theme"],"revision":theme["revision"],"family":chosen["selection"]["family"],"member":item["asset"],"role":"building"};context["objects"].append(Zone.footprint(item,mode,library));context["identities"][item["uid"]]=true
		else:item=candidate(source,rectangle,theme[mode],random,road,prefix+":"+str(index),library,heights,waters)
		if item.is_empty(): return failure("No available "+theme["label"]+" building fits a safe parcel. Check installed assets and flatten/drain this site.")
		item["name"]="%s · block %d / %d · %d"%[theme["label"],parcel["block"][0]+1,parcel["block"][1]+1,parcel["corner"]+1]
		item["group"]=prefix+":block_%d_%d"%[parcel["block"][0],parcel["block"][1]]
		item["neighborhood"]={"uid":prefix,"seed":int(config["seed"]),"theme":config["theme"],"block":parcel["block"],"parcel":parcel["corner"]}
		generated.append(item); footprints.append(Zone.footprint(item,mode,library)); approaches.append([road,Zone.approach(item,mode,library)])
	var route_obstacles: Array[Rect2]=footprints.duplicate()
	if curated:route_obstacles.append_array(preload("res://scripts/builder/terrain_navigation.gd").obstacles(source))
	for approach in approaches:
		var route: Dictionary=preload("res://scripts/builder/citizen_plan.gd").route(approach[0],approach[1],route_obstacles,.35)
		if route["path"].is_empty() or route.get("goal",Vector2.INF).distance_to(approach[1])>1.6: return failure("A generated entrance has no clear road approach. Try another seed or architectural theme.")
	var building_count: int=generated.size();var scenery: Dictionary={"parks":0,"props":0,"skipped":0}
	if curated and count>0:scenery=decorate(source,config,theme,prefix,origin,blocks,library,generated,footprints,approaches,heights,waters,appearance)
	var data: Dictionary=source.duplicate(true)
	data["objects"].append_array(generated)
	var ground_tiles: int=0
	if mode=="2d":
		var existing: Dictionary={}
		for tile in data["tiles"]: existing[Vector2i(tile["cell"][0],tile["cell"][1])]=true
		var first:=Vector2i((region.position*.5).floor()); var last:=Vector2i((region.end*.5).ceil())
		for x in range(first.x,last.x):
			for z in range(first.y,last.y):
				if not existing.has(Vector2i(x,z)):
					data["tiles"].append({"cell":[x,z],"asset":"2d:"+theme["ground"],"direction":"SE"}); ground_tiles+=1
	if not data.has("roads"): data["roads"]=[]
	for cell in cells: data["roads"].append({"cell":[cell.x,cell.y],"width":6,"style":theme["road_style"],"sidewalks":true,"crossing":false,"neighborhood_uid":prefix})
	data["neighborhood_generator"]=config.duplicate(true)
	var allowed: Dictionary=preload("res://scripts/builder/asset_palette_policy.gd").check(source,data,library)
	if not allowed["ok"]:return failure(allowed["reason"])
	var quote: Dictionary=Economy.quote(source,data,library)
	if quote["ok"] and quote.get("enabled",false): data["economy_account"]=quote["account"]
	return {"ok":true,"data":data,"config":config.duplicate(true),"uid":prefix,"bounds":region,"buildings":building_count,"parks":scenery["parks"],"props":scenery["props"],"skipped_scenery":scenery["skipped"],"note":theme.get("note",""),"appearance":appearance,"roads":cells.size(),"ground_tiles":ground_tiles,"blocks":blocks*blocks,"quote":quote,"affordable":quote["ok"]}

static func decorate(source: Dictionary,config: Dictionary,theme: Dictionary,prefix: String,origin: Vector2,blocks: int,library: RefCounted,generated: Array,footprints: Array[Rect2],approaches: Array,heights: Dictionary,waters: Dictionary,appearance: Dictionary) -> Dictionary:
	var result: Dictionary={"parks":0,"props":0,"skipped":0};var mode: String=source["mode"]
	for x in blocks:
		for z in blocks:
			for role in ["park","prop"]:
				var salt: String="%d/%d/%s"%[x,z,role]
				if role=="prop" and Zone.Candidates.draw(config["seed"],salt,theme["revision"],"scenery-density",100)>=theme["prop_density"]:continue
				var ids: Array=theme["parks" if role=="park" else "props"].filter(func(id: String):return Palettes.usable(id,library) and Palettes.matches_appearance(id,appearance,library));ids.sort()
				if ids.is_empty():
					if not theme["parks" if role=="park" else "props"].is_empty():result["skipped"]+=1
					continue
				var id: String=ids[Zone.Candidates.draw(config["seed"],salt,theme["revision"],"scenery",ids.size())];var directions: Array=library.directions(id);directions.sort();var item: Dictionary={"uid":prefix+":scenery:"+salt,"asset":id,"direction":directions[0],"scale":float(library.assets[id]["data"].get("default_scale",1)),"position":[0,0,0]};preload("res://scripts/builder/catalog_defaults.gd").stamp(item)
				var at: Vector2=origin+Vector2(x,z)*80+Vector2(40,40)+(Vector2(0,-7) if role=="prop" else Vector2.ZERO);var box: Rect2=Zone.footprint(item,mode,library);item["position"]=Traffic.world(at-box.get_center(),mode);box=Zone.footprint(item,mode,library)
				var site: Dictionary=preload("res://scripts/builder/terrain_site.gd").foundation(source,box,heights,waters);var safe: bool=site["ok"] and box.size.x<=12 and box.size.y<=12 and not footprints.any(func(other: Rect2):return other.grow(1).intersects(box))
				if not Layers.shown(source,Layers.layer(item,library)) or Layers.locked(source,Layers.layer(item,library)):safe=false
				if safe:
					var obstacles: Array[Rect2]=footprints.duplicate();obstacles.append(box);obstacles.append_array(preload("res://scripts/builder/terrain_navigation.gd").obstacles(source))
					for approach in approaches:
						var route: Dictionary=Zone.Citizen.route(approach[0],approach[1],obstacles,.35)
						if route["path"].is_empty() or route.get("goal",Vector2.INF).distance_to(approach[1])>1.6:safe=false;break
				if not safe:result["skipped"]+=1;continue
				if mode=="3d":item["position"][1]=site["height"]-Zone.construction_bounds(item,mode,library).position.y
				item["group"]=prefix+":block_%d_%d"%[x,z];item["name"]=theme["label"]+" · "+("shared courtyard" if role=="park" else "street scenery");item["neighborhood_palette_selection"]={"version":1,"theme":config["theme"],"revision":theme["revision"],"family":library.assets[id]["data"].get("family_id","asset/"+id),"member":id,"role":role};generated.append(item);footprints.append(box);result["parks" if role=="park" else "props"]+=1
	return result
