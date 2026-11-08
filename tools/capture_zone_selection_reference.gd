extends "res://tools/test_zone_plan.gd"
const OUT="res://output/verification/asset_expansion/I15/"
func run() -> void:
	library=preload("res://scripts/builder/asset_library.gd").new();var rows: Array=[]
	for mode in ["2d","3d"]:
		for theme in ["native","village","any"]:
			for seed_value in [1,2,7,17,42]:
				var data: Dictionary=fixture(mode,"residential");data["zoning"]["seed"]=seed_value;data["zones"][0]["theme"]=theme;var state: Dictionary=Plan.evaluate(data,data["zones"][0],library);check(state["ok"],"Reference state is actually eligible")
				if state["ok"]:rows.append({"data":data,"proposal":state["proposal"],"selection":state["selection"]})
	var file:=FileAccess.open(OUT+"fixed_selection_reference.json",FileAccess.WRITE);file.store_string(JSON.stringify({"plan_sha256":FileAccess.get_sha256("res://scripts/builder/zone_plan.gd"),"catalog_revision":Plan.Candidates.definitions()["revision"],"catalog":Plan.Candidates.definitions(),"cases":rows},"\t"));file.close();print("ZONE SELECTION REFERENCE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
