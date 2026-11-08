extends SceneTree
const Delta=preload("res://scripts/builder/document_delta.gd")
const Merge=preload("res://scripts/builder/cooperative_merge.gd")
const Reference=preload("res://output/verification/asset_expansion/I16/cooperative_merge_before.gd")
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func run() -> void:
	var old_order_defects: int=0
	for seed_value in range(1,181):
		var random:=RandomNumberGenerator.new();random.seed=seed_value;var before: Dictionary={"objects":[],"tiles":[],"title":"Original","nested":{"keep":true,"value":0}}
		for index in 12:before["objects"].append({"uid":"old_"+str(index),"value":index,"nested":{"keep":true,"label":"Original"}});before["tiles"].append({"cell":[index,0],"asset":"A"})
		var after: Dictionary=before.duplicate(true);after["objects"][0]["value"]=100;after["objects"][1]["nested"]["label"]="Changed";after["nested"]["value"]=seed_value
		for index in 3:after["objects"].remove_at(random.randi_range(2,after["objects"].size()-1));after["tiles"].remove_at(random.randi_range(0,after["tiles"].size()-1))
		for index in 7:after["objects"].insert(random.randi_range(0,after["objects"].size()),{"uid":"new_"+str(index),"value":index});after["tiles"].insert(random.randi_range(0,after["tiles"].size()),{"cell":[index,1],"asset":"B"})
		if seed_value%2==0:after["objects"].reverse();after["tiles"].reverse()
		var delta: Dictionary=Delta.between(before,after)
		for forward in [true,false]:
			var source: Dictionary=before if forward else after;var current: Dictionary=Merge.apply(source,delta,forward);var old: Dictionary=Reference.apply(source,delta,forward);var target: Dictionary=after if forward else before;check(current["ok"] and current["data"]==target,"Mixed nested edits, insertions, removals and reordering restore the exact authored target: "+str(seed_value)+str(forward))
			if old["ok"] and old["data"]==target:check(current==old,"Correct historical behavior remains byte/value/order equivalent")
			else:old_order_defects+=1;check(not forward and old["ok"] and current["data"]==before,"Previously misordered reverse insertions now restore the actual original record sequence")
		var concurrent: Dictionary=before.duplicate(true);concurrent["objects"].insert(2,{"uid":"another_author","value":-1});concurrent["title"]="Another author";var exact: String=JSON.stringify(concurrent);check(Merge.apply(concurrent,delta)==Reference.apply(concurrent,delta),"Unrelated concurrent insertion/field preservation has identical order and values: "+str(seed_value));check(JSON.stringify(concurrent)==exact,"Merge never mutates the caller's source on success")
		var conflict: Dictionary=before.duplicate(true);conflict["objects"][0]["value"]=-99;check(Merge.apply(conflict,delta)==Reference.apply(conflict,delta) and not Merge.apply(conflict,delta)["ok"],"Conflicting fields retain the exact original rejection path: "+str(seed_value))
	var malformed: Dictionary={"fields":{},"collections":{"objects":{"identity":"uid","changes":[{"key":"missing","before":null,"after":null}]}}};check(not Merge.apply({"objects":[]},malformed)["ok"],"A malformed empty deletion is rejected without indexing a nonexistent record")
	check(old_order_defects==90,"Archived reference reproduces the identified reverse-insertion defect in exactly 90 cases")
	print("NEIGHBORHOOD MERGE EQUIVALENCE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
