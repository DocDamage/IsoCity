extends SceneTree
const Plan=preload("res://scripts/builder/companion_plan.gd")
const Economy=preload("res://scripts/builder/economy_plan.gd")
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func run() -> void:
	var library: RefCounted=preload("res://scripts/builder/asset_library.gd").new();var definitions: Dictionary=Plan.definitions()["relationships"]
	check(definitions.size()==4,"Four concrete reviewed source-set relationships are present")
	for mode in ["2d","3d"]:
		for key in definitions:
			var recipe: Dictionary=definitions[key];var data: Dictionary=preload("res://scripts/builder/templates.gd").make(mode,"blank")
			var source: Dictionary={"asset":recipe["source"],"position":[0,0,0],"scale":float(library.assets[recipe["source"]]["data"].get("default_scale",1)),"direction":str(library.directions(recipe["source"])[0])}
			var before: Dictionary=data.duplicate(true);var proposal: Dictionary=Plan.propose(data,{},key,"",source,library)
			check(proposal["ok"] and proposal["created"].size()==2 and data==before,"Proposing a complete pair is pure and keeps the city untouched: "+mode+" "+key)
			if not proposal["ok"]:printerr(proposal);continue
			check(Plan.propose(data,{},key,"",source,library)==proposal,"Equivalent source/settings produce deterministic private geometry and identities")
			var first: Dictionary=Plan.materialize(proposal);var second: Dictionary=Plan.materialize(proposal)
			check(first["ids"]!=second["ids"] and first["room"]["objects"].all(func(item: Dictionary):return item["uid"].begins_with("companion_")),"Only applying allocates new independent saved identities")
			var expected: Array=proposal["room"]["objects"].duplicate(true);var actual: Array=first["room"]["objects"].duplicate(true)
			for item in expected:item.erase("uid")
			for item in actual:item.erase("uid");item.erase("group")
			check(expected==actual,"Materializing preserves every proposed geometry/anchor value")
			var owned: Dictionary=first["data"].duplicate(true);var selected: Dictionary=owned["objects"][0];var companion: Dictionary=owned["objects"][1]
			selected["name"]="My customized source";selected["custom_extension"]={"keep":true};var saved: Dictionary=selected.duplicate(true)
			var duplicate: Dictionary=Plan.propose(owned,{},key,selected["uid"],{},library)
			check(duplicate["ok"] and not duplicate["changed"] and duplicate["duplicates"][0]["uid"]==companion["uid"] and owned["objects"][0]==saved,"Already present companions are identified without duplicating or modifying customized sources")
			owned["objects"].pop_back();var added: Dictionary=Plan.propose(owned,{},key,selected["uid"],{},library)
			check(added["ok"] and added["created"].size()==1 and added["room"]["objects"][0]==saved,"An existing source adds only its missing companion, preserving every source field")
			selected["scale"]*=1.5;selected["position"]=[3,4,0] if mode=="2d" else [3,0,4]
			if selected["asset"].begins_with("3d:"):selected["direction"]="90"
			else:selected["angle"]=45
			var modified: Dictionary=Plan.propose(owned,{},key,selected["uid"],{},library)
			check(modified["ok"] and is_equal_approx(float(modified["room"]["objects"][-1]["scale"]),float(companion["scale"])*1.5) and modified["room"]["objects"][0]==selected,"Current position, heading and proportional size drive the new companion without rewriting the source")
			var stale: Dictionary=owned.duplicate(true);stale["title"]="Concurrent change";check(not Plan.current(modified,stale,library),"Concurrent source changes invalidate exact review")
			selected["locked"]=true;check(not Plan.propose(owned,{},key,selected["uid"],{},library)["ok"],"Locked sources cannot be modified indirectly through companion placement");selected.erase("locked")
			owned["economy"]={"enabled":true,"starting_cash":0};owned["economy_account"]=Economy.fresh_account(owned,library)
			var rejected: Dictionary=Plan.propose(owned,{},key,selected["uid"],{},library);check(rejected["ok"] and not rejected["quote"]["ok"],"Unaffordable complete companion transactions remain previewable without partial purchases")
			var descriptor: Dictionary=library.assets[recipe["companions"][0]["asset"]].duplicate(true);library.assets[descriptor["id"]]["path"]="res://output/verification/asset_expansion/U10/missing.tscn"
			var missing: Dictionary=Plan.propose(before,{},key,"",source,library);check(not missing["ok"] and not missing["missing"].is_empty(),"Missing prepared dependencies produce a structured reason before loading a preview")
			library.assets[descriptor["id"]]=descriptor
		var blank: Dictionary=preload("res://scripts/builder/templates.gd").make(mode,"blank");var pump: Dictionary={"asset":"3d:HanX_GasStation/Fuel_Pump","position":[0,0,0],"scale":1.0,"direction":"0"};var covered: Dictionary=Plan.materialize(Plan.propose(blank,{},"covered_pump","",pump,library))
		var shifted: Dictionary=covered["data"];shifted["objects"][0]["position"]=[32,16,0] if mode=="2d" else [2,0,0]
		var existing_cover: Dictionary=Plan.propose(shifted,{},"covered_pump",shifted["objects"][0]["uid"],{},library)
		check(existing_cover["ok"] and not existing_cover["changed"] and existing_cover["duplicates"].size()==1,"A canopy already covering an off-center pump is reused without a second roof: "+mode)
	for malformed in [null,{}, {"source":false},{"source":"3d:x","label":"x","source_set":"x","note":"x","related_overlap":false,"companions":[],"clearance":[]}]:check(not Plan.valid_recipe(malformed),"Malformed relationship metadata is rejected")
	print("COMPANION PLAN: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
