extends SceneTree
const Plan=preload("res://scripts/builder/resident_activity_plan.gd")
const Props=preload("res://scripts/builder/prop_plan.gd")
const Docs=preload("res://scripts/builder/document.gd")
const Templates=preload("res://scripts/builder/templates.gd")
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;print("FAIL: "+message)
func settle() -> void:
	for frame in 6:await process_frame
	await physics_frame
func run() -> void:
	var studio: Control=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio);await settle()
	for mode in ["2d","3d"]:
		studio.switch_mode(mode);var doc: RefCounted=Docs.new();doc.data=Templates.make(mode,"blank");studio.documents[mode]=doc
		for id in ["3d:HanX_School/Student_Chair","2d:Park_Bench"]:
			for direction in (["0","45","90","270"] if id.begins_with("3d:") else ["SE","SW","NW","NE"]):
				doc.data["objects"]=[];var item: Dictionary=doc.add(id,[42,-16,1.25] if mode=="2d" else [2,.12,1],direction,1.2);item["angle"]=23 if id.begins_with("2d:") else 0;studio.changed();await settle()
				var node: Node=studio.worlds[mode].instances[item["uid"]];var profile: Dictionary=Props.profile(item);check(not profile.is_empty(),"Actual source has reviewed interaction anchors: "+id)
				for key in ["approach","exit","customer","facing","point"]:
					var ground: bool=key!="point";var source: Vector3=Props.source(profile,item,studio.library,key)
					if ground and mode=="2d":source.y=0
					var actual: Variant=preload("res://scripts/builder/entrance_anchors.gd").source_position(node,item,mode,studio.library,source)
					var expected: Vector3=Vector3(actual.x,actual.y+(item["position"][2]*8 if ground else 0),0) if mode=="2d" else actual
					check(Plan.anchor(item,profile,key,mode,studio.library,ground).is_equal_approx(expected),"Logical anchor equals actual instantiated source: %s/%s/%s/%s"%[mode,id,direction,key])
		var room: Dictionary=preload("res://scripts/builder/interiors.gd").make(mode,"Activity test");room["objects"]=[];var source_doc: RefCounted=Docs.new();source_doc.data=room
		for x in [-2,2]:source_doc.add("3d:HanX_School/Student_Chair",[(x+2)*16,-32,0] if mode=="2d" else [x,.12,-2],"0")
		var upper: Dictionary=room.duplicate(true);upper["title"]="Upper activity";room["floors"]=[{"uid":"upper","name":"Upstairs","height":3,"room":upper}];room["floor_links"]=[{"uid":"stairs","kind":"stairs","lower":"ground","upper":"upper","start":[0,0],"end":[0,6],"width":1.2}]
		check(Plan.endpoint(room["floor_links"][0],true,mode,false)==(Vector3(-96,48,0) if mode=="2d" else Vector3(0,.03,6)),"Raw flight endpoints retain native projection independently of safe landing offsets: "+mode)
		var before: Dictionary=room.duplicate(true);var child_count: int=studio.worlds[mode].get_child_count();var plan: Dictionary=Plan.compile(room,studio.library)
		check(plan["floors"].size()==2 and plan["stations"].size()==4,"Compile includes each owned floor and each distinct reviewed station: "+mode)
		check(room["objects"].all(func(item: Dictionary):return not Plan.clear(Plan.metric(Plan.point(item,Vector3.ZERO,mode,studio.library,true),mode),plan["floors"]["ground"]["obstacles"])),"Tall source chairs with zero-height contact bounds remain navigation obstacles: "+mode)
		check(room==before and studio.worlds[mode].get_child_count()==child_count,"Compiling occupancy creates no room, actor or authored content: "+mode)
		var raw: Array=room["exit"];var start:=Vector3(raw[0],raw[1],raw[2])
		for station in plan["stations"]:
			var route: Dictionary=Plan.itinerary(plan,"ground",start,station["floor"],station["approach"])
			check(station["reason"].is_empty() and route["ok"],"Exact station approach has a clear room/floor itinerary: "+mode+"/"+station["floor"]+" "+str(route.get("reason",""))+" "+station["reason"])
			if route["ok"]:
				check(route["legs"].back()["to"]==station["approach"],"Route retains exact station approach instead of a nearby free cell: "+mode)
				check(station["floor"]=="ground" or route["legs"].any(func(leg: Dictionary):return leg["kind"]=="stairs"),"Upstairs route includes its authored floor link: "+mode)
		plan["links"]=[];var upper_station: Dictionary=plan["stations"].filter(func(s: Dictionary):return s["floor"]=="upper")[0];check(not Plan.itinerary(plan,"ground",start,"upper",upper_station["approach"])["ok"],"Unlinked floor is unavailable rather than teleported: "+mode)
		var blocked: Dictionary={"shown":true,"obstacles":[Rect2(-1,-1,2,2)]};check(not Plan.walk(blocked,Plan.native(Vector2(-3,0),mode),Plan.native(Vector2.ZERO,mode),mode)["ok"],"Blocked exact endpoint is refused despite nearest-free-cell fallback: "+mode)
		room["layers"]={"Ground":{"visible":false}};check(not Plan.compile(room,studio.library)["floors"]["ground"]["shown"],"Hidden floor surface is unavailable: "+mode)
	studio.free();await settle();print("RESIDENT ACTIVITY PLAN: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
