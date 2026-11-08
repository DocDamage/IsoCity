extends "res://tools/test_zone_plan.gd"
func run() -> void:
	library=preload("res://scripts/builder/asset_library.gd").new()
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://output/verification/asset_expansion/I15/fixed_selection_reference.json"))
	var current_catalog: Dictionary=Plan.Candidates.definitions();Plan.Candidates.cached=reference["catalog"]
	check(reference["cases"].size()==30,"All pre-optimization cases retained")
	check(reference["catalog_revision"]==Plan.Candidates.definitions()["revision"],"Compared with the same catalog revision")
	for row in reference["cases"]:
		var state: Dictionary=Plan.evaluate(row["data"],row["data"]["zones"][0],library)
		check(state["ok"],"Reference remains eligible")
		check(JSON.stringify(state.get("proposal",{}))==JSON.stringify(row["proposal"]),"Exact selected appearance and pose match exhaustive algorithm")
		check(JSON.parse_string(JSON.stringify(state.get("selection",{})))==row["selection"],"Exact family, revision and reviewed price retained")
	Plan.Candidates.cached=current_catalog;print("ZONE SELECTION REFERENCE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
