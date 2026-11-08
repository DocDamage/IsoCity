extends SceneTree
var studio: Control
func _initialize() -> void: call_deferred("run")
func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio)
	for frame in 5: await physics_frame
	var extension: String="png" if "--sprite" in OS.get_cmdline_user_args() else "glb"
	studio.asset_import_tools.load_source(ProjectSettings.globalize_path("user://import-fixtures/fixture."+extension)); studio.asset_import_tools.show(); studio.asset_import_tools.go(2)
	for frame in 5: await physics_frame
	if studio.asset_import_tools.source.is_empty(): print("FAIL: Shutdown probe needs an imported fixture"); quit(1); return
	print("Asset import shutdown: 1 checks, 0 failures")
	# Normal application shutdown, while the raw source and live preview exist.
	quit()
