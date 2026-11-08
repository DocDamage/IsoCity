extends SceneTree
const Plan=preload("res://scripts/builder/neighborhood_plan.gd")
const Document=preload("res://scripts/builder/document.gd")
var library: RefCounted
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func blank(mode: String) -> Dictionary: return preload("res://scripts/builder/templates.gd").make(mode,"blank")
func connected(roads: Array) -> bool:
	var cells: Dictionary={}
	for road in roads: cells[Vector2i(road["cell"][0],road["cell"][1])]=true
	var queue: Array=[cells.keys()[0]]; var visited: Dictionary={queue[0]:true}; var cursor: int=0
	while cursor<queue.size():
		var cell: Vector2i=queue[cursor]; cursor+=1
		for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			if cells.has(cell+direction) and not visited.has(cell+direction): visited[cell+direction]=true; queue.append(cell+direction)
	return visited.size()==cells.size()
func signature(data: Dictionary) -> Array:
	var result: Array=[]
	for item in data["objects"]: result.append([item["asset"],item["direction"],item["position"]])
	return result
func cases(mode: String) -> void:
	# These are the four historical palettes. Expanded palettes have separate
	# family, scenery, compatibility and physical-fixture checks.
	for theme in JSON.parse_string(FileAccess.get_file_as_string("res://resources/catalog/neighborhoods.json")):
		for pattern in Plan.PATTERNS:
			var source: Dictionary=blank(mode); var before: Dictionary=source.duplicate(true); var config: Dictionary=Plan.defaults(); config["theme"]=theme; config["pattern"]=pattern; config["seed"]=19311
			var generated: Dictionary=Plan.generate(source,config,library)
			check(generated["ok"],"Every theme and layout generates installed native buildings: "+mode+"/"+theme+"/"+pattern+" "+generated.get("reason",""))
			if not generated["ok"]: continue
			var data: Dictionary=generated["data"]
			check(source==before and Document.valid(data,mode,library),"Generation is immutable and returns valid city records")
			check(Plan.generate(source,config,library)["data"]==data,"The same seed and parameters reproduce exact records")
			check(generated["buildings"]==11 and generated["blocks"]==4 and generated["affordable"],"Density controls the number of occupied parcels")
			check(connected(data["roads"]),"Every authored road section belongs to the connected layout")
			check(generated["ground_tiles"]>0 if mode=="2d" else generated["ground_tiles"]==0,"Native pixel neighborhoods receive editable themed ground; model cities retain their existing foundation")
			check(data["neighborhood_generator"]==config and data["objects"].all(func(item: Dictionary)->bool:return item["asset"] in Plan.themes()[theme][mode] and item["group"].begins_with(generated["uid"]) and item["neighborhood"]["seed"]==19311),"Theme, editable block grouping and reproducible parameters are retained")
			var boxes: Array[Rect2]=[]
			for item in data["objects"]:
				var box: Rect2=Plan.Zone.footprint(item,mode,library)
				check(generated["bounds"].encloses(box) and not boxes.any(func(other: Rect2)->bool:return other.intersects(box.grow(.5))),"Buildings occupy separate bounded parcels")
				boxes.append(box)
				var intersects: bool=false
				for road in data["roads"]:
					var center: Vector2=Plan.Traffic.center(Vector2i(road["cell"][0],road["cell"][1]),mode)
					if Rect2(center-Vector2.ONE*4,Vector2.ONE*8).intersects(box): intersects=true
				check(not intersects,"Actual footprints leave roads and sidewalks clear")
			print("NEIGHBORHOOD CASE: ",mode,"/",theme,"/",pattern," ",generated["buildings"]," buildings, ",generated["roads"]," roads")
	var config: Dictionary=Plan.defaults(); var source: Dictionary=blank(mode); config["seed"]=71; config["density"]=25
	var low: Dictionary=Plan.generate(source,config,library); config["density"]=100; var high: Dictionary=Plan.generate(source,config,library)
	check(low["ok"] and high["ok"] and low["buildings"]==4 and high["buildings"]==16 and signature(high["data"]).slice(0,4)==signature(low["data"]),"Increasing density retains the same seeded parcels and adds more buildings: "+mode)
	config["density"]=65; var first: Dictionary=Plan.generate(source,config,library); config["seed"]=72; var other: Dictionary=Plan.generate(source,config,library)
	check(first["ok"] and other["ok"] and signature(first["data"])!=signature(other["data"]),"Changing the seed changes actual placements and appearance: "+mode)
	config["density"]=0; var empty: Dictionary=Plan.generate(source,config,library)
	check(empty["ok"] and empty["buildings"]==0 and connected(empty["data"]["roads"]),"Zero density produces editable connected streets and vacant blocks: "+mode)
	config["origin"]=[30,30]; var second: Dictionary=Plan.generate(empty["data"],config,library)
	check(second["ok"] and second["uid"]!=empty["uid"] and second["data"]["roads"].size()==empty["roads"]+second["roads"],"Road-only neighborhoods reserve independent identities and can be appended: "+mode)
	config=Plan.defaults(); config["blocks"]=4; var maximum: Dictionary=Plan.generate(source,config,library)
	check(maximum["ok"] and maximum["blocks"]==16 and maximum["buildings"]==42,"The maximum district size generates all requested blocks: "+mode)
	var masks: Array=[]
	for pattern in Plan.PATTERNS:
		config["pattern"]=pattern; masks.append(Plan.road_cells(config))
	check(masks[0]!=masks[1] and masks[1]!=masks[2] and masks[0]!=masks[2],"Road layouts change actual topology: "+mode)
	config["blocks"]=2; masks=[]
	for pattern in Plan.PATTERNS:
		config["pattern"]=pattern; masks.append(Plan.road_cells(config))
	check(masks[0]!=masks[1] and masks[1]!=masks[2] and masks[0]!=masks[2],"Every road choice changes the default district's topology: "+mode)
	for theme in Plan.themes():
		for edge_seed in [1,2147483647]:
			config=Plan.defaults(); config["blocks"]=4; config["density"]=100; config["seed"]=edge_seed; config["theme"]=theme
			var full: Dictionary=Plan.generate(source,config,library)
			if Plan.Palettes.palettes().has(theme) and not mode in Plan.Palettes.palettes()[theme]["modes"]:
				check(not full["ok"] and full["reason"].contains("3D"),"An unsupported maximum district preserves its explicit source limitation: "+mode+"/"+theme);continue
			check(full["ok"] and full["buildings"]==64 and Document.valid(full["data"],mode,library),"Every theme fills the maximum district at both seed limits: "+mode+"/"+theme+"/"+str(edge_seed))
func safety(mode: String) -> void:
	var config: Dictionary=Plan.defaults(); var source: Dictionary=blank(mode)
	for layer in ["Ground","Buildings"]:
		for field in ["visible","locked"]:
			var protected: Dictionary=source.duplicate(true); Plan.Layers.set_state(protected,layer,field,field=="locked")
			check(not Plan.generate(protected,config,library)["ok"],"Generation respects protected city layers: "+mode+"/"+layer+"/"+field)
	var occupied: Dictionary=source.duplicate(true); occupied["objects"]=[{"uid":"owned","asset":"2d:House_Blue","direction":library.directions("2d:House_Blue")[0],"position":[0,0,0],"scale":1.0,"visible":false,"locked":true,"interior":preload("res://scripts/builder/interiors.gd").make(mode,"Keep me")}]
	var before: Dictionary=occupied.duplicate(true)
	check(not Plan.generate(occupied,config,library)["ok"] and occupied==before,"Hidden locked buildings and their rooms reserve their area without mutation: "+mode)
	var roads: Dictionary=source.duplicate(true); roads["roads"]=[{"cell":[0,0]}]
	check(not Plan.generate(roads,config,library)["ok"],"Existing roads are preserved: "+mode)
	var lots: Dictionary=source.duplicate(true); lots["zones"]=[{"uid":"lot","kind":"residential","rect":[0,0,8,8]}]
	check(not Plan.generate(lots,config,library)["ok"],"Designated lots are preserved: "+mode)
	var interior: Dictionary=source.duplicate(true); interior["interior_room"]=true
	check(not Plan.generate(interior,config,library)["ok"],"Generation is restricted to exterior cities: "+mode)
	var wet: Dictionary=source.duplicate(true); wet["terrain"]={"enabled":true,"bounds":[-40,-40,80,80]}; wet["terrain_vertices"]=[]; wet["water_cells"]=[{"cell":[-40,-40],"level":1.0}]
	check(not Plan.generate(wet,config,library)["ok"],"Flooded road sites reject generation without flattening or draining authored terrain: "+mode)
	var economy: Dictionary=source.duplicate(true); economy["economy"]={"enabled":true,"starting_cash":1}; var cash_before: Dictionary=economy.duplicate(true); var poor: Dictionary=Plan.generate(economy,config,library)
	check(poor["ok"] and not poor["affordable"] and not poor["quote"]["ok"] and poor["quote"]["construction"]>1 and economy==cash_before,"Unaffordable generation returns a preview and exact quote without charging cash: "+mode)
	economy["economy"]["starting_cash"]=100000000; var funded: Dictionary=Plan.generate(economy,config,library)
	check(funded["ok"] and funded["affordable"] and funded["data"]["economy_account"]["cash"]==100000000-funded["quote"]["net"],"A funded generated neighborhood accounts for every purchased building and road: "+mode)
	var doc=Document.new(); doc.data=economy.duplicate(true); doc.economy_library=library; doc.data=funded["data"]
	check(doc.record_completed_change(economy) and doc.undo_history.size()==1 and doc.undo() and doc.data==economy and doc.redo() and doc.data==funded["data"],"Generated city records support exact one-step Undo and Redo with treasury restoration: "+mode)
	var normalized: Dictionary=Document.normalize(JSON.parse_string(JSON.stringify(funded["data"])))
	check(Document.valid(normalized,mode,library) and Plan.valid_settings(normalized["neighborhood_generator"]) and normalized["objects"].size()==funded["buildings"],"JSON persistence retains editable generation results and repeatable parameters: "+mode)
	var broken: Dictionary=normalized.duplicate(true); broken["neighborhood_generator"]={"seed":false}
	check(not Document.valid(broken,mode,library),"Malformed saved generation settings are rejected: "+mode)
	var repair=preload("res://scripts/builder/project_repair.gd").new(library); var repaired: Dictionary=repair.world(broken,mode,"city",0)
	check(Document.valid(repaired,mode,library) and not repaired.has("neighborhood_generator") and repaired["objects"]==normalized["objects"] and repaired["roads"]==normalized["roads"] and repair.issues.size()==1,"Repair removes only invalid generator settings and retains all generated city content: "+mode)
	var ground: Dictionary=source.duplicate(true); ground["tiles"]=[{"cell":[0,0],"asset":"2d:Grass","direction":"SE","extension":{"retain":true}}]
	var covered: Dictionary=Plan.generate(ground,config,library)
	check(covered["ok"] and covered["data"]["tiles"][0]==ground["tiles"][0] and covered["data"]["tiles"].filter(func(tile: Dictionary)->bool:return tile["cell"]==[0,0]).size()==1,"Generated paving preserves existing editable ground records and metadata: "+mode)
	var crowded: Dictionary=source.duplicate(true); crowded["roads"]=[]
	for index in 4090: crowded["roads"].append({"cell":[-5000+index,-5000]})
	var limited: Dictionary=Plan.generate(crowded,config,library)
	check(not limited["ok"] and limited["reason"].contains("4,096") and crowded["roads"].size()==4090,"Generation enforces the complete city's road limit before mutation: "+mode)
	var unavailable=preload("res://scripts/builder/asset_library.gd").new()
	for asset in Plan.themes()[config["theme"]][mode]: unavailable.assets[asset]["unavailable"]=true
	check(not Plan.generate(source,config,unavailable)["ok"],"Unavailable theme assets produce an actionable failure instead of invalid buildings: "+mode)
func run() -> void:
	library=preload("res://scripts/builder/asset_library.gd").new()
	check(Plan.valid_settings(Plan.defaults()),"Default neighborhood parameters are valid")
	for pair in [["seed",0],["seed",true],["seed",INF],["density",-1],["density",101],["density",1.5],["blocks",0],["blocks",5],["pattern","unknown"],["theme","unknown"],["origin",[0]],["origin",[129,0]],["origin",[true,0]]]:
		var invalid: Dictionary=Plan.defaults(); invalid[pair[0]]=pair[1]; check(not Plan.valid_settings(invalid),"Invalid generation parameters are rejected: "+str(pair))
	for mode in ["2d","3d"]: cases(mode); safety(mode)
	seed(9981); var expected: int=randi(); seed(9981); Plan.generate(blank("3d"),Plan.defaults(),library); check(randi()==expected,"Neighborhood generation does not advance global simulation randomness")
	print("NEIGHBORHOOD PLAN: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
