extends SceneTree
const Kits=preload("res://scripts/builder/interior_kits.gd")
const Rooms=preload("res://scripts/builder/interiors.gd")
const Doc=preload("res://scripts/builder/document.gd")
const Coop=preload("res://scripts/builder/cooperative_plan.gd")
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func run() -> void:
	var library: RefCounted=preload("res://scripts/builder/asset_library.gd").new()
	var definitions: Dictionary=Kits.definitions()
	for id in definitions["buildings"]:check(library.assets.has(id),"Reviewed building exists: "+id)
	check(Kits.default_for("3d:HanX_School/Student_Desk").is_empty(),"Unmapped furnishings do not become building interiors")
	for mode in ["2d","3d"]:
		for key in definitions["kits"]:
			var sequence: int=Kits.sequence;var plan: Dictionary=Kits.plan(key,mode,library)
			check(plan["ok"] and Kits.sequence==sequence,"Kit preflight is complete and creates no objects: "+mode+" "+key)
			for id in plan["dependencies"]:check(library.assets[id].get("data",{}).get("source_export_allowed",true),"Reviewed kit content allows portable sources: "+id)
			var owner: Dictionary={"uid":"school","asset":"3d:HanX_School/School_Building","scale":.1}
			var room: Dictionary=Rooms.make_for(owner,mode,library,key)
			check(Doc.valid(room,mode,library),"Generated room validates: "+mode+" "+key)
			check(room["starter_kit"]["id"]==key,"Room records its chosen kit and revision")
			var larger: Dictionary=owner.duplicate(true);larger["scale"]=20
			var other: Dictionary=Rooms.make_for(larger,mode,library,key)
			check(room["objects"].map(func(item: Dictionary):return item["position"])==other["objects"].map(func(item: Dictionary):return item["position"]),"Exterior scale does not stretch room-local furnishings")
			var ids: Array=room["objects"].map(func(item: Dictionary):return item["uid"])
			check(other["objects"].all(func(item: Dictionary):return not item["uid"] in ids),"Separate creations have fresh object identities")
		var host: Dictionary={"uid":"school","asset":"3d:HanX_School/School_Building","position":[0,0,0],"direction":"0","scale":1.0}
		var room: Dictionary=Rooms.ensure(host,mode,library);room["exit"]=[1,2,0];var preserved: Dictionary=host.duplicate(true)
		var original: String=definitions["buildings"][host["asset"]];definitions["buildings"][host["asset"]]="garage";Rooms.ensure(host,mode,library)
		check(host==preserved,"Existing customized room is not regenerated after a mapping change");definitions["buildings"][host["asset"]]=original
		var data: Dictionary=preload("res://scripts/builder/templates.gd").make(mode,"blank");host.erase("interior");data["objects"]=[host]
		var required: Dictionary=Coop.required_assets(data,library)
		check(required.has("3d:HanX_School/Student_Chair") and required.has("3d:HanX_School/Chalkboard"),"Lazy unvisited school dependencies are explicit")
		host["interior"]=Rooms.make_for(host,mode,library,"empty");required=Coop.required_assets(data,library)
		check(not required.has("3d:HanX_School/Student_Chair"),"Existing empty/custom room does not acquire unused future furnishings")
		var actual: Dictionary=library.assets["3d:HanX_School/Student_Chair"];library.assets.erase("3d:HanX_School/Student_Chair")
		var missing: Dictionary=Rooms.make_for(host,mode,library)
		check(missing["starter_kit"]["id"]=="empty" and not missing["starter_kit"]["missing"].is_empty() and Doc.valid(missing,mode,library),"Missing pack creates a valid clear shell with an explicit reason")
		library.assets["3d:HanX_School/Student_Chair"]=actual
		check(Kits.plan("classroom",mode,library)["ok"],"Restored source is not held in a stale missing-dependency cache")
		var bad: Dictionary=definitions["kits"]["classroom"].duplicate(true);bad["objects"][0]["position"]=[NAN,0,0]
		check(not Kits.valid_definition(bad,mode,library),"Nonfinite kit metadata is rejected")
		var clone_source: Dictionary=Rooms.make_for(host,mode,library,"classroom")
		clone_source["objects"].append({"uid":"switch","asset":"2d:Floor_Lamp","position":[0,0,0],"direction":"SE","scale":1.0,"prop":{"target":clone_source["objects"][0]["uid"]}})
		clone_source["floors"]=[{"uid":"upper","name":"Upper","height":3,"room":Rooms.make(mode,"Upper")}]
		clone_source["floor_links"]=[{"uid":"stairs","kind":"stairs","lower":"ground","upper":"upper","start":[-3,3],"end":[2,3],"width":1.4}]
		clone_source["floor_entrances"]=[{"uid":"entry","floor":"upper","position":[0,0,0]}]
		var before_clone: Dictionary=clone_source.duplicate(true);var cloned: Dictionary=preload("res://scripts/builder/owned_room_copy.gd").room(clone_source)
		check(Doc.valid(cloned,mode,library) and clone_source==before_clone,"Deep room duplication preserves source content and validates")
		var source_ids: Array=clone_source["objects"].map(func(item: Dictionary):return item["uid"])
		check(cloned["objects"].all(func(item: Dictionary):return not item["uid"] in source_ids),"Deep room duplication renews every object UID")
		check(cloned["objects"][-1]["prop"]["target"]==cloned["objects"][0]["uid"],"Copied local switch targets follow copied objects")
		check(cloned["floors"][0]["uid"]!="upper" and cloned["floor_links"][0]["upper"]==cloned["floors"][0]["uid"] and cloned["floor_entrances"][0]["floor"]==cloned["floors"][0]["uid"],"Copied links and entrances follow renewed floor identities")
	print("INTERIOR KITS: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
