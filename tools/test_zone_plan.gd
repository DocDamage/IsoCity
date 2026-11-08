extends SceneTree
const Plan=preload("res://scripts/builder/zone_plan.gd")
const Economy=preload("res://scripts/builder/economy_plan.gd")
var checks: int=0
var failures: int=0
var library: RefCounted
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func add(data: Dictionary,uid: String,asset: String,point: Vector2) -> Dictionary:
	var item: Dictionary={"uid":uid,"asset":asset,"position":Plan.Traffic.world(point,data["mode"]),"direction":library.directions(asset)[0],"scale":1.0}; data["objects"].append(item); return item
func fixture(mode: String,kind: String) -> Dictionary:
	var data: Dictionary=preload("res://scripts/builder/templates.gd").make(mode,"blank")
	data["zoning"]={"enabled":true,"stage_seconds":12,"seed":7}
	data["zones"]=[{"uid":"lot_"+kind,"kind":kind,"rect":[-24,8,48,48],"stage":0,"extension":"keep"}]
	data["roads"]=[]
	for x in range(-8,9): data["roads"].append({"cell":[x,0]})
	var home: String="2d:House_Blue" if mode=="2d" else "3d:HanX_City/Row_Houses_A"
	add(data,"home_1",home,Vector2(-40,-20)); add(data,"home_2",home,Vector2(40,-20))
	return data
func run() -> void:
	library=preload("res://scripts/builder/asset_library.gd").new()
	check(not Plan.settings({})["enabled"],"Zoning is opt-in")
	check(Plan.valid_settings({"extension":"keep"}) and Plan.valid_settings({"enabled":true,"seed":1,"stage_seconds":2}),"Optional bounded settings accept extensions")
	for value in [null,true,[],"enabled"]: check(not Plan.valid_settings(value),"Reject unreadable settings: "+str(value))
	for field in ["seed","stage_seconds"]:
		for value in [null,"12",true,INF,NAN,-1,2147483648]: check(not Plan.valid_settings({field:value}),"Reject invalid growth setting: "+field+str(value))
	check(not Plan.valid_settings({"seed":1.5}) and not Plan.valid_settings({"enabled":1}),"Seed is integral and enabled is boolean")
	check(Plan.settings({"zoning":{"stage_seconds":999,"seed":0}})["stage_seconds"]==300 and Plan.settings({"zoning":{"seed":0}})["seed"]==1,"Recovery clamps known settings")
	for kind in Plan.definitions():
		for mode in ["2d","3d"]:
			for asset in Plan.definitions()[kind][mode]: check(library.assets.has(asset) and ResourceLoader.exists(library.assets[asset]["path"]),"Development catalog uses installed prefabs: "+asset)
	for mode in ["2d","3d"]:
		for kind in Plan.definitions():
			var data: Dictionary=fixture(mode,kind); var lot: Dictionary=data["zones"][0]
			check(Plan.valid_lots(data["zones"],mode,library),"Typed development lots validate: "+kind+mode)
			var source: Dictionary=data.duplicate(true); var state: Dictionary=Plan.evaluate(data,lot,library)
			check(state["ok"] and state["rate"]>=1,"A clear accessible lot can start development: "+kind+mode+state["reason"])
			if not state["ok"]: continue
			var proposal: Dictionary=state["proposal"]
			check(Plan.rectangle(lot).grow(-.5).encloses(Plan.footprint(proposal,mode,library)),"Actual building footprint fits the lot margin: "+kind+mode)
			check(Plan.evaluate(data,lot,library)["proposal"]==proposal and data==source,"Seeded planning is deterministic and does not edit authored content: "+kind+mode)
			var node: Node=preload("res://scripts/builder/asset_instance.gd").make(library,proposal["asset"],mode); root.add_child(node)
			preload("res://scripts/builder/asset_instance.gd").pose(node,proposal)
			if mode=="2d": node.position=Vector2(proposal["position"][0],proposal["position"][1]); node.scale=Vector2.ONE*proposal["scale"]
			else: node.position=Vector3(proposal["position"][0],proposal["position"][1],proposal["position"][2]); node.scale=Vector3.ONE*proposal["scale"]
			var arrival: Variant=preload("res://scripts/builder/entrance_anchors.gd").position_for(node,proposal,mode,library)
			var actual: Vector2=Plan.Traffic.metric([arrival.x,arrival.y,0] if mode=="2d" else [arrival.x,arrival.y,arrival.z],mode)
			check(actual.distance_to(Plan.approach(proposal,mode,library))<.001,"Planned entrances match real instantiated source transforms: "+kind+mode)
			check(mode=="2d" or absf(arrival.y)<.5,"Generated model entrances remain at ground level: "+kind+mode)
			node.free()
			var blocked: Dictionary=data.duplicate(true); var item: Dictionary=proposal.duplicate(true); item["uid"]="obstruction"; blocked["objects"].append(item)
			check(not Plan.evaluate(blocked,blocked["zones"][0],library)["ok"],"Growth does not overwrite objects in the planned footprint: "+kind+mode)
			check(not Plan.evaluate(data,lot,library,[Plan.footprint(proposal,mode,library).get_center()])["ok"],"Growth waits for actual people to clear the building footprint: "+kind+mode)
			blocked=data.duplicate(true); blocked["roads"].clear()
			check(not Plan.evaluate(blocked,blocked["zones"][0],library)["ok"],"Removing road access suspends development: "+kind+mode)
			blocked=data.duplicate(true); blocked["roads"]=[{"cell":[0,0]}]
			check(not Plan.evaluate(blocked,blocked["zones"][0],library)["ok"],"A single isolated road section is insufficient: "+kind+mode)
			blocked=data.duplicate(true); blocked["layers"]={"Buildings":{"locked":true}}
			check(not Plan.evaluate(blocked,blocked["zones"][0],library)["ok"],"Protected Buildings cannot be developed automatically: "+kind+mode)
			blocked=data.duplicate(true); blocked["zones"][0]["visible"]=false
			check(not Plan.evaluate(blocked,blocked["zones"][0],library)["ok"],"Hidden lots remain undeveloped: "+kind+mode)
			data["economy"]={"enabled":true,"starting_cash":10000}; data["economy_account"]=Economy.fresh_account(data,library)
			var first: Dictionary=Plan.advance(data,lot["uid"],library,"paid_building")
			check(first["ok"] and first.has("data") and first["data"]["zones"][0]["stage"]==1 and first["data"]["objects"].size()==2 and first["data"]["economy_account"]["cash"]==10000,"Foundation stage persists a proposal without prematurely spawning or charging a building: "+kind+mode)
			var second: Dictionary=Plan.advance(first["data"],lot["uid"],library)
			check(second["ok"] and second["data"]["zones"][0]["stage"]==2 and second["data"]["objects"].size()==2,"Framing is a separate development transition: "+kind+mode)
			var finishing: Dictionary=Plan.advance(second["data"],lot["uid"],library)
			check(finishing["ok"] and finishing["data"]["zones"][0]["stage"]==Plan.Stage.FINISHING and finishing["data"]["objects"].size()==2 and finishing["data"]["economy_account"]["cash"]==10000,"Finishing keeps the exact proposal without a construction charge: "+kind+mode)
			var complete: Dictionary=Plan.advance(finishing["data"],lot["uid"],library)
			check(complete["ok"] and complete["data"]["zones"][0]["stage"]==3 and complete["data"]["objects"].size()==3,"Maturity adds a real editable city building: "+kind+mode)
			var cost: int=Economy.profile(proposal["asset"],library)["construction"]
			check(complete["data"]["economy_account"]["cash"]==10000-cost and complete["data"]["economy_account"]["construction_total"]==cost,"Construction is charged exactly once when the building completes: "+kind+mode)
			check(Plan.evaluate(complete["data"],complete["data"]["zones"][0],library).get("complete",false) and not Plan.advance(complete["data"],lot["uid"],library).has("data"),"Completed lots do not duplicate or replace their editable building: "+kind+mode)
			var demolished: Dictionary=complete["data"].duplicate(true); demolished["objects"].pop_back()
			var regrow: Dictionary=Plan.advance(demolished,lot["uid"],library)
			check(regrow["ok"] and regrow["data"]["zones"][0]["stage"]==0 and not regrow["data"]["zones"][0].has("proposal"),"A demolished zoned building begins a new vacant cycle without immediate replacement: "+kind+mode)
			var poor: Dictionary=second["data"].duplicate(true); poor["economy_account"]["cash"]=0
			check(not Plan.advance(poor,lot["uid"],library)["ok"] and poor["zones"][0]["stage"]==2 and poor["objects"].size()==2,"Construction waits in its current stage when funds are unavailable: "+kind+mode)
			var doc=preload("res://scripts/builder/document.gd").new(); doc.data=finishing["data"].duplicate(true); doc.economy_library=library; doc.checkpoint(); doc.data=complete["data"].duplicate(true); doc.reconcile_economy(library); doc.finish_checkpoint()
			check(doc.data["economy_account"]["cash"]==10000-cost and doc.undo() and doc.data["objects"].size()==2 and doc.data["economy_account"]["cash"]==10000,"Normal document accounting avoids double charging and Undo restores the stage and funds: "+kind+mode)
			check(doc.redo() and doc.data["objects"].size()==3 and doc.data["economy_account"]["cash"]==10000-cost,"Redo restores the exact completed building and purchase once: "+kind+mode)
			var lots: Array=first["data"]["zones"].duplicate(true); var other: Dictionary=lots[0].duplicate(true); other["uid"]="other_lot"; other["rect"]=[100,8,48,48]; other["proposal"]["zone_uid"]=other["uid"]; lots.append(other)
			check(not Plan.valid_lots(lots,mode,library),"Two lots cannot reserve the same future building identity: "+kind+mode)
			check(doc.valid(JSON.parse_string(JSON.stringify(doc.data)),mode,library),"Zoning stages, proposals and purchases survive project JSON validation: "+kind+mode)
		var residential: Dictionary=fixture(mode,"residential"); var empty: Dictionary=residential.duplicate(true); empty["objects"].clear()
		check(Plan.evaluate(empty,empty["zones"][0],library)["ok"],"Residential development can seed a new neighborhood: "+mode)
		var park: String="2d:Park_Bench" if mode=="2d" else "3d:HanX_Park/Bench_Park"; add(residential,"park",park,Vector2(40,30))
		check(Plan.surroundings(residential,residential["zones"][0],library)["rate"]>Plan.surroundings(empty,empty["zones"][0],library)["rate"],"Nearby amenities accelerate residential growth: "+mode)
		for kind in ["commercial","civic"]:
			var data: Dictionary=fixture(mode,kind); data["objects"].clear()
			check(not Plan.evaluate(data,data["zones"][0],library)["ok"],"Nonresidential development waits for neighborhood demand: "+kind+mode)
			add(data,"only_home","2d:House_Blue" if mode=="2d" else "3d:HanX_City/Row_Houses_A",Vector2(40,-20))
			check(Plan.surroundings(data,data["zones"][0],library)["suitable"]==(kind=="commercial"),"Civic lots require more nearby households than commercial lots: "+mode)
	var data: Dictionary=fixture("2d","residential"); var lot: Dictionary=data["zones"][0]
	for value in [null,true,{},[{}],[{"uid":"x","kind":"residential","rect":[0,0,0,0]}]]: check(not Plan.valid_lots(value,"2d",library),"Unreadable lot collections are rejected")
	var duplicate: Array=[lot.duplicate(true),lot.duplicate(true)]; duplicate[1]["rect"]=[100,100,32,32]
	check(not Plan.valid_lots(duplicate,"2d",library),"Lot IDs are unique")
	duplicate[1]["uid"]="different"; duplicate[1]["rect"]=[0,8,32,32]
	check(not Plan.valid_lots(duplicate,"2d",library),"Overlapping lot designations are rejected")
	var repair=preload("res://scripts/builder/project_repair.gd").new(library)
	data["zoning"]["stage_seconds"]=0; data["zoning"]["extension"]="keep"; data["zones"][0]["stage"]=2; data["zones"][0]["proposal"]={"asset":"missing"}; data["zones"].append({"kind":"unknown","rect":[0,0,5,5]})
	var fixed: Dictionary=repair.world(data,"2d","world",0)
	check(fixed["zones"].size()==1 and fixed["zones"][0]["stage"]==0 and fixed["zoning"]["stage_seconds"]==2,"Repair retains usable lot geometry and resets unreadable growth plans")
	check(fixed["zones"][0]["extension"]=="keep" and fixed["zoning"]["extension"]=="keep" and data["zones"][0]["stage"]==2 and not repair.issues.is_empty(),"Repair preserves extensions, original input and archived damaged records")
	check(preload("res://scripts/builder/document.gd").valid(fixed,"2d",library),"Repaired zoning data validates without dropping other city content")
	print("ZONE PLAN: %d checks, %d failures" % [checks,failures]); quit(0 if failures==0 else 1)
