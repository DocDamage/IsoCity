extends "res://tools/test_neighborhood_palettes.gd"
const Merge=preload("res://scripts/builder/cooperative_merge.gd")
const Delta=preload("res://scripts/builder/document_delta.gd")
func run() -> void:
	library=preload("res://scripts/builder/asset_library.gd").new();var source: Dictionary=preload("res://scripts/builder/templates.gd").make("2d","blank");var config: Dictionary=Plan.defaults();config.merge({"theme":"village","blocks":1,"density":100,"seed":17},true);var proposed: Dictionary=Plan.generate(source,config,library);check(proposed["ok"] and proposed["data"]["tiles"].size()>2000,"Batch fixture uses an actual complete district with over 2,000 paving records")
	if not proposed["ok"]:quit(1);return
	var built: Dictionary=proposed["data"];var initial: Dictionary=Delta.between(source,built);var applied: Dictionary=Merge.apply(source,initial);check(applied["ok"] and applied["data"]==built,"A whole district merges with exact authored record order, artwork and notes");check(Merge.apply(built,initial,false).get("data")==source,"Shared district Undo restores the exact original document")
	var changed: Dictionary=built.duplicate(true);changed["objects"][0]["name"]="Customized district building"
	for index in 5:changed["tiles"].remove_at(1)
	for index in 7:changed["tiles"].insert(2+index,{"cell":[1000+index,1000],"asset":"2d:Grass","direction":"SE"})
	var delta: Dictionary=Delta.between(built,changed);var update: Dictionary=Merge.apply(built,delta);check(update["ok"] and update["data"]==changed,"Mixed paving replacement and ordinary building customization retain exact target order");check(Merge.apply(changed,delta,false).get("data")==built,"Undo of simultaneous insertions/removals restores every original paving slot")
	var concurrent: Dictionary=built.duplicate(true);concurrent["title"]="Another collaborator's title";var other: Dictionary=concurrent["objects"][0].duplicate(true);other["uid"]="another_author";concurrent["objects"].append(other);var before: String=JSON.stringify(concurrent);var shared: Dictionary=Merge.apply(concurrent,delta);check(shared["ok"] and shared["data"]["title"]==concurrent["title"] and shared["data"]["objects"].back()==other,"An unrelated collaborator's title and object survive the complete batch")
	check(JSON.stringify(concurrent)==before,"Successful merge preserves its caller's original source")
	concurrent["objects"][0]["name"]="Conflicting name";before=JSON.stringify(concurrent);var rejected: Dictionary=Merge.apply(concurrent,delta);check(not rejected["ok"] and rejected["reason"].contains("name") and JSON.stringify(concurrent)==before,"Conflicting customization rejects the whole transaction without mutating the source")
	var malformed: Dictionary={"fields":{},"collections":{"objects":{"identity":"uid","changes":[{"key":"missing","before":null,"after":null}]}}};check(not Merge.apply({"objects":[]},malformed)["ok"],"An invalid empty deletion returns a structured rejection without engine errors")
	print("COOPERATIVE DISTRICT BATCH: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
