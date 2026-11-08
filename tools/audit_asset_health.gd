extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var library: RefCounted=preload("res://scripts/builder/asset_library.gd").new()
	var audit: RefCounted=preload("res://scripts/builder/asset_health.gd").new();audit.begin(library)
	while audit.active:
		audit.step(32,15000)
		await process_frame
	var report: Dictionary=audit.report();var output: String="res://output/verification/asset_expansion/U17/catalog_audit.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	if not preload("res://scripts/builder/project_store.gd").write_json(output,report):printerr("FAIL: health report output unavailable");quit(1);return
	var defects: Array=report["issues"].filter(func(issue: Dictionary):return issue["severity"]=="defect")
	print("LIBRARY HEALTH AUDIT: %d assets, %d grouped defects, %d review groups; %s; work %.1f ms"%[report["assets_scanned"],defects.size(),report["issues"].size()-defects.size(),report["status"],report["scan_work_ms"]]);quit()
