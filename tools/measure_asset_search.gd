extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var started: int=Time.get_ticks_usec()
	var library: RefCounted=preload("res://scripts/builder/asset_library.gd").new()
	if library.search_index==null or library.search_index.index.size()!=library.assets.size():printerr("FAIL: search index did not build");quit(1);return
	var report: Dictionary={"engine":Engine.get_version_info()["string"],"catalog":library.assets.size(),"library_ms":(Time.get_ticks_usec()-started)/1000.0,"headless":DisplayServer.get_name()=="headless","samples":[]}
	report.merge({"cpu":OS.get_processor_name(),"memory_after_library_bytes":OS.get_static_memory_usage(),"viewport":[root.size.x,root.size.y],"nodes":get_node_count(),"active_simulations":[],"capture_or_profiler":false,"renderer":RenderingServer.get_current_rendering_method()},true)
	for query in ["school chair","chair school","school chairs","shcool chair","café","03_cubesat_3u.glb","3d:HanX_School/School_Chair","classroom seating","repair workshop","unlikelymismatch"]:
		var times: Array=[];var count: int=0
		for repeat in 7:
			started=Time.get_ticks_usec();var found: Array=library.find("all","All assets",query,[],false);count=found.size();times.append((Time.get_ticks_usec()-started)/1000.0)
		var cold: float=times.pop_front();times.sort()
		report["samples"].append({"query":query,"matches":count,"cold_ms":cold,"warm_median_ms":(times[2]+times[3])/2,"warm_p95_ms":times[-1]})
	var output: String="res://output/verification/asset_expansion/U16/search_measurement.json"
	report.merge({"memory_after_queries_bytes":OS.get_static_memory_usage(),"indexed_words":library.search_index.postings.size(),"cached_queries":library.search_index.queries.size(),"cached_edit_distances":library.search_index.scores.size()},true)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if not file:printerr("FAIL: measurement output unavailable");quit(1);return
	file.store_string(JSON.stringify(report,"\t",true)+"\n");file.close();print("SEARCH MEASUREMENT: ",JSON.stringify(report));quit()
