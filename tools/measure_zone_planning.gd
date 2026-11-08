extends "res://tools/test_zone_plan.gd"
const OUT="res://output/verification/asset_expansion/I15/"
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT);library=preload("res://scripts/builder/asset_library.gd").new();var results: Array=[]
	for mode in ["2d","3d"]:
		for theme in ["native","village","any"]:
			var data: Dictionary=fixture(mode,"residential");data["zones"][0]["theme"]=theme;var start: int=Time.get_ticks_usec();var state: Dictionary=Plan.evaluate(data,data["zones"][0],library);var cold: int=Time.get_ticks_usec()-start;check(state["ok"],"Measured planning case is actually eligible: "+mode+theme)
			start=Time.get_ticks_usec()
			for repeat in 20:state=Plan.evaluate(data,data["zones"][0],library)
			var elapsed: int=Time.get_ticks_usec()-start
			start=Time.get_ticks_usec()
			for repeat in 20:Plan.Candidates.groups(data["zones"][0],mode,library)
			var groups_usec: int=Time.get_ticks_usec()-start;var chosen: Dictionary=Plan.choice_result(data,data["zones"][0],library,Plan.road_access(data,data["zones"][0]),"measurement")
			results.append({"mode":mode,"theme":theme,"first_call_ms":cold/1000.0,"twenty_cached_calls_ms":elapsed/1000.0,"cached_average_ms":elapsed/20000.0,"eligible_families":state.get("eligible_families",0),"group_average_ms":groups_usec/20000.0,"geometry_checks":chosen.get("geometry_checks",0)})
	var artifact: String=OUT+"planning_performance_"+str(Time.get_unix_time_from_system()).replace(".","_")+".json";var file:=FileAccess.open(artifact,FileAccess.WRITE);file.store_string(JSON.stringify({"scope":"CPU planning only; new process, ordinary OS file cache; no UI/layout/render/frame-rate claim","results":results},"\t"));file.close();var latest:=FileAccess.open(OUT+"planning_performance.json",FileAccess.WRITE);latest.store_string(FileAccess.get_file_as_string(artifact));latest.close();print("ZONE PLANNING MEASUREMENT: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
