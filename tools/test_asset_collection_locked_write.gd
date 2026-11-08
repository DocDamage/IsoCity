extends SceneTree
const Plan=preload("res://scripts/builder/asset_collections.gd")
const Local=preload("res://scripts/builder/asset_collection_store.gd")
const Store=preload("res://scripts/builder/project_store.gd")
const OUT="res://output/verification/asset_expansion/U15/locked_writes/"
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func _initialize() -> void:
	var local:=Local.new();local.path=OUT+"preferences.json";local.storage_enabled=true;local.state=Store.read_json(local.path,{})
	check(Plan.state_valid(local.state),"Locked fixture retains readable valid personal state")
	var before: Dictionary=local.state.duplicate(true);var old_hash: String=FileAccess.get_sha256(local.path);var uid: String=before["collections"][0]["uid"];var renamed: Dictionary=Plan.rename(before["collections"][0],"Changed while locked");var changed: Dictionary=local.put(renamed["data"])
	check(changed["ok"] and not changed["persisted"] and local.state!=before and local.notice.contains("session"),"A denied replacement keeps the changed collection usable in the current session")
	check(FileAccess.get_sha256(local.path)==old_hash and Store.read_json(local.path,{})==before,"The actual locked destination remains byte-identical to its good prior state")
	var export_path: String=OUT+"export.json";old_hash=FileAccess.get_sha256(export_path);check(not local.export_file(export_path,[uid])["ok"] and FileAccess.get_sha256(export_path)==old_hash,"A denied export replacement preserves the actual previous collection file")
	var temporary: Array=[]
	for file in DirAccess.get_files_at(OUT):
		if file.ends_with(".tmp"):temporary.append(file)
	check(temporary.is_empty(),"Failed atomic replacements leave no incomplete temporary files")
	print("ASSET COLLECTION LOCKED WRITE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
