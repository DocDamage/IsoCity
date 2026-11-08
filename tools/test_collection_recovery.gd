extends SceneTree
const OUT="res://output/verification/asset_expansion/U15/"
const Plan=preload("res://scripts/builder/asset_collections.gd")
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func normalized(value: Dictionary) -> Dictionary:return JSON.parse_string(JSON.stringify(value))
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT);var library: RefCounted=preload("res://scripts/builder/asset_library.gd").new();var project: Dictionary={"version":1,"grid_version":2,"active_mode":"2d","documents":{}}
	for mode in ["2d","3d"]:project["documents"][mode]=preload("res://scripts/builder/templates.gd").make(mode,"blank")
	var value: Dictionary=Plan.project_empty();value["restricted"]=true;value["collection"]["entries"]=[{"kind":"asset","id":"2d:Missing_Recovery_Palette_Table","name":"Original table from another computer"}];project["project_palette"]=value;var store=preload("res://scripts/builder/project_store.gd");var path: String=OUT+"missing_palette_recovery.isocity.json";check(store.write_json(path,project),"Missing-reference recovery source writes")
	var source_hash: String=FileAccess.get_sha256(path);var repaired: Dictionary=preload("res://scripts/builder/project_repair.gd").new(library).read(path)
	check(repaired["ok"] and not repaired["changed"] and repaired["content"]["project_palette"]==normalized(value),"A valid missing reference is preserved without repair or disabling its explicit restriction")
	check(repaired["content"]["documents"]==normalized(project["documents"]) and FileAccess.get_sha256(path)==source_hash,"Missing palette references never remove authored worlds or rewrite the source")
	for invalid in [{"restricted":true},"unreadable",[],{"version":true,"collection":value["collection"],"restricted":true}]:
		var broken: Dictionary=project.duplicate(true);broken["project_palette"]=invalid;var broken_path: String=OUT+"invalid_palette_recovery_"+str(checks)+".isocity.json";check(store.write_json(broken_path,broken),"Invalid optional metadata fixture writes");source_hash=FileAccess.get_sha256(broken_path);repaired=preload("res://scripts/builder/project_repair.gd").new(library).read(broken_path)
		check(repaired["ok"] and repaired["changed"] and not repaired["content"].has("project_palette") and repaired["content"]["documents"]==normalized(project["documents"]),"Unreadable optional palette metadata is isolated from otherwise valid world recovery")
		check(repaired["report"]["issues"].any(func(issue: Dictionary):return issue["path"]=="project_palette" and issue.get("original")==invalid) and FileAccess.get_sha256(broken_path)==source_hash,"Recovery archives the exact unreadable optional value and leaves source bytes unchanged")
	print("COLLECTION RECOVERY: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
