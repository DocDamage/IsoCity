extends SceneTree
const Candidates=preload("res://scripts/builder/zone_candidates.gd")
const Plan=preload("res://scripts/builder/zone_plan.gd")
const Collections=preload("res://scripts/builder/asset_collections.gd")
const OUT="res://output/verification/asset_expansion/I15/"
var checks: int=0
var failures: int=0
var library: RefCounted
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func member_ids(result: Dictionary) -> Array:
	var ids: Array=[]
	for group in result["groups"]:ids.append_array(group["members"])
	return ids
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT);library=preload("res://scripts/builder/asset_library.gd").new();var catalog: Dictionary=Candidates.definitions();check(Candidates.valid(catalog),"Compiled reviewed catalog validates before selection")
	check(catalog["families"].size()==51 and catalog["families"].reduce(func(total: int,entry: Dictionary):return total+entry["members"].size(),0)==255,"Reviewed pool contains distinct designs and frozen concrete appearances")
	for value in [null,true,[],{},catalog.merged({"version":true},true),catalog.merged({"families":[{}]},true)]:check(not Candidates.valid(value),"Unreadable catalog cannot be accepted as candidate rules")
	var malformed: Dictionary=catalog.duplicate(true);malformed["families"][1]["id"]=malformed["families"][0]["id"];check(not Candidates.valid(malformed),"Duplicate design identities are rejected")
	malformed=catalog.duplicate(true);malformed["families"][1]["members"][0]=malformed["families"][0]["members"][0];check(not Candidates.valid(malformed),"A concrete appearance cannot silently count as another independent design")
	malformed=catalog.duplicate(true);malformed["families"][0]["weight"]=0;check(not Candidates.valid(malformed),"Invalid weights cannot enter seeded selection")
	for option in [{"theme":"unknown"},{"theme":[]},{"density":"crowded"},{"max_price":-1},{"max_price":true},{"max_price":NAN}]:check(not Candidates.valid_options(option),"Unreadable lot filter is rejected")
	check(Candidates.valid_options({}) and Candidates.options({})=={"theme":"native","density":"any","max_price":0},"Old lots receive matching-world themes, any density and no price cap")
	for mode in ["2d","3d"]:
		for kind in ["residential","commercial","civic"]:
			var lot: Dictionary={"kind":kind};var found: Dictionary=Candidates.groups(lot,mode,library);check(found["ok"],"Native reviewed design groups are available: "+kind+mode)
			check(found["groups"].all(func(group: Dictionary):return Candidates.theme(lot,mode) in group["definition"]["themes"]),"Default groups preserve the current world's architectural theme: "+kind+mode)
			var priced: Dictionary=Candidates.groups({"kind":kind,"max_price":1},mode,library);check(not priced["ok"] and priced["reason"].contains("price"),"A too-small price limit has a specific reason: "+kind+mode)
	check(not Candidates.groups({"kind":"civic","theme":"korean_street"},"3d",library)["ok"] and Candidates.groups({"kind":"civic","theme":"industrial"},"2d",library)["reason"].contains("No reviewed"),"Incomplete themes report their actual absence instead of using unrelated buildings")
	check(Candidates.groups({"kind":"residential","theme":"korean_street"},"3d",library)["reason"].contains("world"),"Unsuited Korean flat cards have a world-compatibility reason before any seeded draw")
	check(Candidates.groups({"kind":"residential","theme":"village","density":"high"},"3d",library)["reason"].contains("density"),"Density excludes incompatible designs before seeded choice")
	var base: Dictionary=Candidates.groups({"kind":"residential","theme":"pixel_city"},"2d",library);var id: String="2d:House_Blue";var descriptor: Dictionary=library.assets[id].duplicate(true);library.assets[id]["path"]=OUT+"uninstalled_candidate.tscn"
	check(not id in member_ids(Candidates.groups({"kind":"residential","theme":"pixel_city"},"2d",library)),"Missing prepared sources are excluded while other matching designs remain usable");library.assets[id]=descriptor
	var policy: Dictionary=Collections.project_empty();policy["restricted"]=true;policy["collection"]["entries"]=[Collections.asset_entry(id,library)["entry"]];library.set_project_palette(policy)
	check(member_ids(Candidates.groups({"kind":"residential","theme":"pixel_city"},"2d",library))==[id],"Explicit project restriction filters exact concrete members before family choice")
	check(not Candidates.groups({"kind":"residential","theme":"village"},"2d",library)["ok"] and Candidates.groups({"kind":"residential","theme":"village"},"2d",library)["reason"].contains("restriction"),"An excluded entire family has a specific policy reason")
	check(member_ids(Candidates.groups({"kind":"residential","theme":"pixel_city"},"2d",library,{})).size()==member_ids(base).size(),"Explicit unrestricted export policy is independent of a different live browsing/project context")
	check(not Candidates.groups({"kind":"residential"},"2d",library,{"restricted":true})["ok"],"Malformed export policy never silently permits future dependencies");library.set_project_palette({})
	var simple: Array=[{"definition":{"id":"one","weight":1},"members":["single"]},{"definition":{"id":"eighteen","weight":1},"members":[]}]
	for i in 18:simple[1]["members"].append("appearance_%02d"%i)
	var counts: Dictionary={"one":0,"eighteen":0};var appearances: Dictionary={}
	for seed_value in range(1,4001):
		var choice: Dictionary=Candidates.choose(simple,seed_value,"stable_lot","fixed_revision");counts[choice["family"]]+=1;appearances[choice["member"]]=true
	check(counts["one"]>1750 and counts["one"]<2250 and counts["eighteen"]>1750 and counts["eighteen"]<2250,"Eighteen appearances do not multiply their family's selection probability: "+str(counts))
	check(appearances.size()==19,"Concrete appearance selection reaches every member after the design is chosen")
	var reversed: Array=simple.duplicate(true);reversed.reverse();reversed[0]["members"].reverse()
	check(Candidates.choose(simple,42,"stable_lot","fixed_revision")==Candidates.choose(reversed,42,"stable_lot","fixed_revision"),"Input enumeration order does not change a fixed-revision seeded choice")
	var fewer: Array=simple.duplicate(true);fewer[1]["members"]=["one_remaining_appearance"];var stable: bool=true
	for seed_value in range(1,401):stable=stable and Candidates.choose(simple,seed_value,"stable_lot","fixed_revision")["family"]==Candidates.choose(fewer,seed_value,"stable_lot","fixed_revision")["family"]
	check(stable,"Family choice stays independent of concrete member count")
	var weighted: Array=simple.duplicate(true);weighted[1]["definition"]["weight"]=3;var selected: int=0
	for seed_value in range(1,4001):
		if Candidates.choose(weighted,seed_value,"stable_lot","fixed_revision")["family"]=="eighteen":selected+=1
	check(selected>2750 and selected<3250,"Explicit reviewed family weights govern probability: "+str(selected))
	check(Candidates.choose([],1,"empty","fixed_revision").is_empty(),"No eligible family produces an empty choice safely")
	var output:=FileAccess.open(OUT+"family_weight_distribution.json",FileAccess.WRITE);output.store_string(JSON.stringify({"equal_weights":counts,"appearance_ids_reached":appearances.size(),"three_to_one_selected":selected,"seeds":4000},"\t"));output.close()
	print("ZONE CANDIDATES: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
