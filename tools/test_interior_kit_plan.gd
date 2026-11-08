extends SceneTree
const Plan=preload("res://scripts/builder/interior_kit_plan.gd")
const Rooms=preload("res://scripts/builder/interiors.gd")
const Doc=preload("res://scripts/builder/document.gd")
const Kits=preload("res://scripts/builder/interior_kits.gd")
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func run() -> void:
	var library: RefCounted=preload("res://scripts/builder/asset_library.gd").new()
	for mode in ["2d","3d"]:
		var city: Dictionary=preload("res://scripts/builder/templates.gd").make(mode,"blank");var host: Dictionary={"uid":"school","asset":"3d:HanX_School/School_Building","position":[0,0,0],"scale":1.0,"direction":"0"};city["objects"]=[host]
		var baseline: Dictionary=city.duplicate(true)
		for key in ["classroom","shop","cafe","apartment","garage","station","empty"]:
			var proposal: Dictionary=Plan.propose(city,"school","ground",key,"create",[0,0],library)
			check(proposal["ok"] and not host.has("interior") and city==baseline,"Previewing creates no authored room: "+mode+" "+key)
			if not proposal["ok"]:printerr(proposal);continue
			check(Doc.valid(proposal["data"],mode,library) and Plan.current(proposal,city),"Proposed layout is valid and records current dependencies")
			check(proposal["data"]==Plan.propose(city,"school","ground",key,"create",[0,0],library)["data"],"Equivalent previews have identical temporary identities and content")
			var applied: Dictionary=Plan.materialize(proposal);var other: Dictionary=Plan.materialize(proposal)
			check(Doc.valid(applied["data"],mode,library) and applied["ids"].size()==proposal["created"].size(),"Applying allocates every new saved identity")
			check(applied["ids"].values().all(func(uid: String):return uid not in other["ids"].values()),"Separate applications never share kit identities")
			var before_objects: Array=proposal["room"]["objects"].duplicate(true);var after_objects: Array=Plan.owner(applied["data"],"school")["interior"]["objects"].duplicate(true)
			for item in before_objects:item.erase("uid")
			for item in after_objects:item.erase("uid")
			check(before_objects==after_objects,"Applied source geometry, transforms and settings exactly match the proposal")
		host["interior"]=Rooms.make_for(host,mode,library);var room: Dictionary=host["interior"];room["objects"][-1]["name"]="Customized item";room["floor_name"]="My ground";var original: Dictionary=city.duplicate(true)
		var add: Dictionary=Plan.propose(city,"school","ground","shop","add",[1,0],library)
		check(add["ok"] and add["room"]["objects"].size()==room["objects"].size()+Kits.definitions()["kits"]["shop"]["objects"].size() and city==original,"Add retains every customized object and changes no source")
		check(add["room"]["objects"].slice(0,room["objects"].size())==room["objects"],"Add preserves original identities, values and order")
		var replace: Dictionary=Plan.propose(city,"school","ground","shop","replace",[0,0],library)
		check(replace["ok"] and replace["removed"].size()==room["objects"].size() and replace["room"]["exit"]==room["exit"] and replace["room"]["floor_name"]=="My ground","Replace explicitly lists the affected layout while preserving exit and floor settings")
		room["objects"][-1]["locked"]=true
		check(not Plan.propose(city,"school","ground","shop","replace",[0,0],library)["ok"],"Replacement cannot delete a protected object")
		check(Plan.propose(city,"school","ground","shop","add",[0,0],library)["ok"],"Adding does not delete or mutate protected existing objects")
		room["objects"][-1].erase("locked")
		var floor: Dictionary=Plan.propose(city,"school","ground","apartment","floor",[0,0],library,"Home upstairs",3)
		check(floor["ok"] and floor["root"]["floors"].size()==1 and floor["root"]["objects"]==room["objects"],"New floor preserves the existing ground layout")
		var installed: Dictionary=Plan.materialize(floor);check(installed["floor_uid"]!="kit_floor_preview" and installed["root"]["floors"][0]["uid"]==installed["floor_uid"],"A created floor receives a fresh saved identity")
		check(not Plan.propose(city,"school","ground","shop","floor",[0,0],library,"Too close",1)["ok"],"New floor obeys the existing minimum storey gap")
		check(not Plan.propose(city,"school","ground","shop","add",[NAN,0],library)["ok"],"Nonfinite offsets cannot enter proposals")
		check(not Plan.propose(city,"school","missing","shop","add",[0,0],library)["ok"],"Deleted target floor is rejected")
		var changed: Dictionary=city.duplicate(true);changed["title"]="Concurrent edit";check(not Plan.current(add,changed),"Concurrent document changes invalidate the exact preview")
		var maximum: Dictionary=city.duplicate(true)
		for index in 7:
			maximum["objects"][0]["interior"].get_or_add("floors",[]).append({"uid":"floor_"+str(index),"name":"Floor "+str(index),"height":3*(index+1),"room":Plan.shell(mode)})
		check(not Plan.propose(maximum,"school","ground","shop","floor",[0,0],library,"Ninth",24)["ok"],"Existing eight-floor limit is enforced")
		var old: Dictionary=library.assets["3d:HanX_School/Student_Chair"].duplicate(true);library.assets[old["id"]]["path"]="res://output/verification/asset_expansion/U13/missing_chair.tscn"
		var missing: Dictionary=Plan.propose(baseline,"school","ground","classroom","create",[0,0],library)
		check(not missing["ok"] and not missing["missing"].is_empty(),"Missing prepared source is a structured dependency failure, without engine errors")
		library.assets[old["id"]]=old
		check(Plan.propose(baseline,"school","ground","classroom","create",[0,0],library)["ok"],"Restored source clears the failure")
		var economy: Dictionary=baseline.duplicate(true);economy["economy"]={"enabled":true,"starting_cash":0};economy["economy_account"]=preload("res://scripts/builder/economy_plan.gd").fresh_account(economy,library)
		var free: Dictionary=Plan.propose(economy,"school","ground","classroom","create",[0,0],library);check(free["ok"] and free["quote"]["ok"] and free["quote"]["construction"]==0,"Actual reviewed default allowance makes first school layout complimentary")
		var alternate: Dictionary=Plan.propose(economy,"school","ground","shop","create",[0,0],library);check(alternate["ok"] and not alternate["quote"]["ok"],"Alternate first room remains previewable but an unaffordable quote rejects application")
	print("INTERIOR KIT PLAN: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
