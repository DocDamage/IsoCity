extends "res://tools/test_resident_activity_plan.gd"
const Setup=preload("res://scripts/builder/interaction_setup_plan.gd")
const Reservations=preload("res://scripts/builder/activity_reservations.gd")
func records(report: Dictionary,uid: String,code: String="",severity: String="") -> Array:
	return report["records"].filter(func(row: Dictionary):return row["object_uid"]==uid and (code.is_empty() or row["code"]==code) and (severity.is_empty() or row["severity"]==severity))
func add(doc: RefCounted,id: String,at: Array) -> Dictionary:
	var item: Dictionary=doc.add("3d:HanX_School/Student_Chair",at,"0");item["uid"]=id;return item
func run() -> void:
	var studio: Control=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio);await settle()
	for mode in ["2d","3d"]:
		studio.switch_mode(mode);var room: Dictionary=preload("res://scripts/builder/interiors.gd").make(mode,"Unvisited setup room");room["objects"]=[];var ground:=Docs.new();ground.data=room
		var upper:=Docs.new();upper.data=room.duplicate(true)
		var seat: Dictionary=add(ground,"seat",[0,-32,0] if mode=="2d" else [-2,.12,-2]);var blocked_a: Dictionary=add(upper,"a",seat["position"].duplicate());var blocked_b: Dictionary=add(upper,"b",seat["position"].duplicate())
		for prop in [blocked_a,blocked_b]:prop["prop"]={"kind":"seat","approach":[0,.9,0],"exit":[0,.9,0]}
		room["floors"]=[{"uid":"upper","name":"Workshop","height":3,"room":upper.data}];room["floor_links"]=[]
		var switch: Dictionary=add(ground,"switch",[96,0,0] if mode=="2d" else [5,.12,0]);switch["prop"]={"kind":"switch","target":"device"}
		var device: Dictionary=add(upper,"device",[96,0,0] if mode=="2d" else [5,.12,0]);device["prop"]={"kind":"appliance"};device["locked"]=true
		var missing: Dictionary=add(ground,"missing",[160,32,0] if mode=="2d" else [10,.12,0]);missing["missing_asset"]={"name":"Unavailable fixture"}
		var source: Dictionary=room.duplicate(true);var world: Node=studio.worlds[mode];var children: int=world.get_child_count();var pool:=Reservations.new();var owner:=RefCounted.new();var key: String="room:house:ground:seat";var token: int=pool.acquire(key,owner)
		var animation: Dictionary={"clips":{"idle":{"directions":{"SE":{}}}},"actions":{}}
		var options: Dictionary={"building":"house"};var report: Dictionary=Setup.report(room,studio.library,options,pool,animation)
		check(not report["records"].is_empty() and report["objects"]==6,"Inspect six unvisited fixtures without loading a room: "+mode)
		check(room==source and world.get_child_count()==children and not world.exploration.interior,"Inspection never authors content or creates a room/world: "+mode)
		check(records(report,"b","station_overlap","error").size()==1 and records(report,"b","station_clearance","error").size()==1 and records(report,"b","return_route","error").size()==1,"The same fixture exposes overlap, physical clearance and return failures: "+mode)
		check(records(report,"b","approach_route","error").size()==1 and records(report,"b","station_support","error").size()==(1 if mode=="3d" else 0),"Unlinked access and unsupported native height are reported independently: "+mode)
		check(records(report,"missing","missing_asset","error").size()==1 and records(report,"device","protected","info").size()==1,"Missing and locked fixtures remain actionable without changing visibility: "+mode)
		var target: Array=records(report,"switch","required_target","error")
		check(target.size()==1 and target[0]["related_uids"]==["device"],"The runtime target rule rejects a powered device on another floor: "+mode)
		check(records(report,"seat","animation","warning" if mode=="2d" else "ok").size()==1,"Availability uses authored sprite fallback or the native 3D pose: "+mode)
		check(records(report,"seat","station_capacity","info").size()==1 and pool.current(key)["token"]==token,"Inspection reads the live scoped reservation without taking it: "+mode)
		pool.release(key,token);var free: Dictionary=Setup.report(room,studio.library,options,pool,animation)
		check(records(free,"seat","station_capacity","ok").size()==1 and free["revision"]==report["revision"],"Transient capacity changes do not alter the authored revision: "+mode)
		upper.data["objects"].erase(device);ground.data["objects"].append(device);device["visible"]=false
		check(records(Setup.report(room,studio.library,options),"switch","required_target","error").size()==1,"A hidden same-floor target stays unavailable: "+mode)
		device["visible"]=true;upper.data["objects"].erase(blocked_a);blocked_b.erase("prop");room["floor_links"]=[{"uid":"stairs","kind":"stairs","lower":"ground","upper":"upper","start":[0,0],"end":[0,6],"width":1.2}]
		var fixed: Dictionary=Setup.report(room,studio.library,options)
		check(fixed["revision"]!=report["revision"] and records(fixed,"switch","required_target","ok").size()==1 and records(fixed,"b","return_route","ok").size()==1,"Actual source corrections refresh the revision and retry successfully: "+mode)
		check(fixed["records"].all(func(row: Dictionary):return row["revision"]==fixed["revision"] and not row["message_key"].is_empty() and row["scope"].begins_with("room:house:")),"Each diagnostic has a stable code, scope, object and fresh revision: "+mode)
		var selected: Dictionary=Setup.report(room,studio.library,{"building":"house","floor":"upper","object":"b"})
		check(selected["objects"]==1 and selected["records"].all(func(row: Dictionary):return row["object_uid"]=="b" and row["scope"]=="room:house:upper:"),"Targeted checks keep the precise floor and object identity: "+mode)
	studio.free();await settle();print("INTERACTION SETUP PLAN: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
