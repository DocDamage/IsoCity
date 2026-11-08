extends SceneTree
const Plan=preload("res://scripts/builder/citizen_plan.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func safe_path(path: PackedVector2Array,boxes: Array[Rect2],padding: float=.3) -> bool:
	for i in maxi(0,path.size()-1):
		for j in 11:
			var at: Vector2=path[i].lerp(path[i+1],j/10.0)
			for box in boxes:
				if box.grow(padding).has_point(at): return false
	return true
func record(uid: String,id: String,position: Array) -> Dictionary:
	return {"uid":uid,"asset":id,"position":position,"direction":"SE","scale":1.0}
func run() -> void:
	var library: RefCounted=preload("res://scripts/builder/asset_library.gd").new()
	var defaults: Dictionary=Plan.settings({})
	check(not defaults["enabled"] and defaults["population"]==12,"Citizens default to an opt-in simulation")
	var malformed: Dictionary=Plan.settings({"citizens":{"enabled":"yes","population":INF,"seed":false,"day_length":0,"start_hour":"noon"}})
	check(not malformed["enabled"] and malformed["population"]==12 and malformed["seed"]==1 and malformed["day_length"]==30 and malformed["start_hour"]==7,"Malformed configuration falls back to bounded values")
	check(Plan.settings({"citizens":{"population":999,"seed":-5}})["population"]==128,"Population is bounded")
	for use in ["home","work","shop","park"]:
		check(Plan.role({"asset":"2d:Coffee_Shop","citizen_role":use})==use,"Placed objects can explicitly author the "+use+" role")
	check(Plan.role({"asset":"2d:Coffee_Shop","citizen_role":"none"}).is_empty(),"An explicit opt-out overrides a catalog role")
	check(Plan.role({"asset":"unknown:Home_Work_Shop_Park"}).is_empty(),"Role classification does not guess from asset names")
	check(Plan.role({"asset":"2d:Coffee_Shop"})=="shop","Authored defaults supply known business roles")
	for id in Plan.catalog_roles:
		check(library.assets.has(id),"Every authored role references an installed asset: "+id)
	for mode in ["2d","3d"]:
		var items: Array=[record("home-b","2d:House_Blue",[80,40,0]),record("work","2d:Office_Tower",[160,0,0]),record("shop","2d:Coffee_Shop",[0,100,0]),record("park","2d:Park_Bench",[-100,0,0]),record("home-a","2d:Apartment_Building",[0,0,0])]
		var data: Dictionary={"mode":mode,"objects":items,"citizens":{"enabled":true,"population":8,"seed":42}}
		var before: Dictionary=data.duplicate(true)
		var plan: Dictionary=Plan.build(data,library)
		check(plan["residents"].size()==8 and plan["destinations"]["home"].size()==2,"Population distributes across authored homes: "+mode)
		check(plan["residents"].all(func(r: Dictionary):return r["work"]=="work" and r["shop"]=="shop" and r["park"]=="park"),"Residents have real work/shop/park assignments: "+mode)
		check(plan["residents"][0]["home"]=="home-a" and plan["residents"][1]["home"]=="home-b","Home assignment uses stable IDs: "+mode)
		var ids: Dictionary={}
		for r in plan["residents"]: ids[r["id"]]=true
		check(ids.size()==8,"Resident identities are unique: "+mode)
		check(Plan.build(data,library)["residents"]==plan["residents"],"Seeded planning is deterministic: "+mode)
		items.reverse()
		check(Plan.build(data,library)["residents"]==plan["residents"],"Reordering editor objects does not reshuffle residents: "+mode)
		items.reverse()
		check(data==before,"Planning leaves document data unchanged: "+mode)
		var arrivals: Dictionary={"home-a":Vector2(3,4)}
		check(Plan.build(data,library,arrivals)["lookup"]["home-a"]["point"]==Vector2(3,4),"Authored entrance approaches can replace object centers: "+mode)
		var p: Vector2=Plan.metric([32,16,2] if mode=="2d" else [2,2,2],mode)
		check(p==Vector2(2,2),"Route metric handles the dimension's ground coordinates: "+mode)
		check(Plan.world(p,mode,2)==[32.0,16.0,2.0] if mode=="2d" else Plan.world(p,mode,2)==[2.0,2.0,2.0],"Ground coordinates round trip without losing elevation: "+mode)
		items[2]["visible"]=false
		var hidden: Dictionary=Plan.build(data,library)
		check(hidden["destinations"]["shop"].is_empty() and hidden["residents"].all(func(r: Dictionary):return r["shop"]==r["home"]),"Hidden destinations fall back to home with a notice: "+mode)
	var no_home: Dictionary=Plan.build({"objects":[record("shop","2d:Coffee_Shop",[0,0,0])],"citizens":{"enabled":true}},library)
	check(no_home["residents"].is_empty() and not no_home["notices"].is_empty(),"Cities without homes do not invent residents or destinations")
	for entry in [[0,"home"],[7.9,"home"],[8,"work"],[11.9,"work"],[12,"shop"],[13,"work"],[17,"park"],[19,"shop"],[21,"home"],[24,"home"],[32,"work"],[-1,"home"]]:
		check(Plan.activity(entry[0])==entry[1],"Daily routine boundary: "+str(entry[0]))
	check(Plan.activity(8,.15)=="home" and Plan.activity(8.2,.15)=="work","Staggered schedules avoid a simultaneous commute")
	check(Plan.destination({"home":"h","work":"w","shop":"s","park":"p","offset":0},17.5)=="p","The active routine resolves an assigned destination")
	var empty: Array[Rect2]=[]
	var direct: Dictionary=Plan.route(Vector2.ZERO,Vector2(6,0),empty)
	check(not direct["path"].is_empty() and direct["start"]==Vector2.ZERO and direct["goal"]==Vector2(6,0),"Unobstructed routes connect the requested endpoints")
	var boxes: Array[Rect2]=[Rect2(2,-2,2,4)]
	var detour: Dictionary=Plan.route(Vector2.ZERO,Vector2(7,0),boxes)
	check(not detour["path"].is_empty() and safe_path(detour["path"],boxes),"Routes walk around buildings with clearance instead of cutting through them")
	check(detour["path"].size()>direct["path"].size(),"Obstacle detours are longer than a direct path")
	var enclosure: Array[Rect2]=[Rect2(-2,-2,4,.5),Rect2(-2,1.5,4,.5),Rect2(-2,-2,.5,4),Rect2(1.5,-2,.5,4)]
	var blocked: Dictionary=Plan.route(Vector2.ZERO,Vector2(8,0),enclosure)
	check(blocked["path"].is_empty() and not blocked["reason"].is_empty(),"Enclosed residents report an unavailable route instead of crossing walls")
	var nudged: Dictionary=Plan.route(Vector2(3,0),Vector2(7,0),boxes)
	check(not nudged["path"].is_empty() and nudged["start"]!=Vector2(3,0) and safe_path(nudged["path"],boxes),"Spawn/approach planning exposes a nearby safe point when a supplied endpoint is blocked")
	check(Plan.route(Vector2.ZERO,Vector2(10000,10000),empty)["path"].is_empty(),"Oversized route grids fail with a bounded result")
	check(Plan.route(Vector2(INF,0),Vector2.ZERO,empty)["path"].is_empty(),"Invalid endpoints cannot enter pathfinding")
	check(Plan.route(Vector2.ZERO,Vector2(2000000,0),empty)["path"].is_empty(),"Out-of-range route coordinates are rejected")
	check(Plan.route(Vector2.ZERO,Vector2.ZERO,empty)["path"].size()==1,"Already-arrived residents have a valid stationary path")
	print("CITIZEN PLAN: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
