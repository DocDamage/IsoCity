extends RefCounted
const Plan=preload("res://scripts/builder/asset_collections.gd")
const Store=preload("res://scripts/builder/project_store.gd")
const HISTORY_LIMIT=50
var path: String="user://studio_asset_collections.json"
var storage_enabled: bool=false
var state: Dictionary=Plan.empty()
var undo_history: Array[Dictionary]=[]
var redo_history: Array[Dictionary]=[]
var notice: String=""
var observed_path: String=""
var observed_hash: String=""
var unreadable_path: String=""
var recovery_path: String=""
var revision: int=0
func restore(favorites: Array,library: RefCounted) -> Dictionary:
	var loaded: Dictionary=Plan.empty()
	observed_path=path;observed_hash=FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "";unreadable_path=""
	if FileAccess.file_exists(path):
		var file:=FileAccess.open(path,FileAccess.READ)
		if not file or file.get_length()>Plan.MAX_BYTES:unreadable_path=path;notice="Personal collections could not be read. The saved file and current session were preserved.";return Plan.failure(notice)
		var raw: Variant=Plan.parse(file.get_as_text())
		if not Plan.state_valid(raw):unreadable_path=path;notice="Personal collections contain invalid data. The saved file and current session were preserved.";return Plan.failure(notice)
		loaded=raw
	var migrated: Dictionary=Plan.migrate_favorites(loaded,favorites,library)
	if not migrated["ok"]:
		notice=migrated["reason"]
		if not FileAccess.file_exists(path):return migrated
		# A full collection list can prevent the one-time favorites copy. That
		# must not hide valid saved lists or replace them with an empty session.
		var retained: Dictionary=loaded.duplicate(true);retained["version"]=1;var retained_changed: bool=retained!=state;state=retained
		if retained_changed:revision+=1
		undo_history.clear();redo_history.clear();return {"ok":true,"changed":retained_changed,"persisted":true,"migration_ok":false,"skipped":[],"reason":notice}
	var normalized: Dictionary=migrated["data"].duplicate(true);normalized["version"]=1;var changed: bool=normalized!=state
	state=normalized
	if changed:revision+=1
	undo_history.clear();redo_history.clear();notice=""
	if not migrated["skipped"].is_empty():notice="Unreadable legacy favorite records were kept in the original favorites file; valid references were copied."
	var saved: bool=true
	if migrated["changed"]:saved=persist()
	return {"ok":true,"changed":changed,"persisted":saved,"migration_ok":true,"skipped":migrated["skipped"],"reason":notice}
func persist() -> bool:
	if not Plan.state_valid(state):notice="The current collections are invalid. The previous saved file was preserved.";return false
	if not storage_enabled:return true
	var current_hash: String=FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""
	if observed_path==path and observed_hash!=current_hash:notice="Collections are available for this session. Another editor changed the saved preferences; export this session or reload before merging the changes.";return false
	var recovered: bool=false
	if unreadable_path==path:
		var source:=FileAccess.open(path,FileAccess.READ)
		if not source or source.get_length()>Plan.MAX_BYTES or observed_hash.is_empty():notice="Collections are available for this session. The unreadable preference file was preserved; export this session to another file.";return false
		source.close()
		if recovery_path.is_empty() or not FileAccess.file_exists(recovery_path) or FileAccess.get_sha256(recovery_path)!=observed_hash:
			recovery_path=path+".unreadable_"+Crypto.new().generate_random_bytes(8).hex_encode()+".bak"
			if DirAccess.copy_absolute(ProjectSettings.globalize_path(path),ProjectSettings.globalize_path(recovery_path))!=OK or FileAccess.get_sha256(recovery_path)!=observed_hash:notice="Collections are available for this session. The unreadable preference file could not be preserved, so it was not replaced.";return false
		if FileAccess.get_sha256(path)!=observed_hash:notice="Collections are available for this session. Saved preferences changed while preserving their recovery copy; reload before merging.";return false
		recovered=true
	if not Store.write_json(path,state):notice="Collections are available for this session. Preferences could not be saved; the previous saved file was preserved.";return false
	observed_path=path;observed_hash=FileAccess.get_sha256(path);unreadable_path=""
	if recovered:notice="Collections saved. A recovery copy of the original unreadable file was kept."
	return true
func commit(value: Dictionary,history: bool=true) -> Dictionary:
	if not Plan.state_valid(value):return Plan.failure("The collection change is invalid or exceeds the supported size. Current collections were preserved.")
	var normalized: Dictionary=value.duplicate(true);normalized["version"]=1
	if normalized==state:return {"ok":true,"changed":false,"persisted":true,"reason":"No collection changes."}
	if history:
		undo_history.append(state.duplicate(true))
		if undo_history.size()>HISTORY_LIMIT:undo_history.pop_front()
		redo_history.clear()
	state=normalized;revision+=1;notice="";var saved: bool=persist();return {"ok":true,"changed":true,"persisted":saved,"reason":notice}
func history(redo: bool=false) -> Dictionary:
	var source: Array[Dictionary]=redo_history if redo else undo_history
	if source.is_empty():return Plan.failure("No personal collection changes to "+("redo." if redo else "undo."))
	var target: Array[Dictionary]=undo_history if redo else redo_history;target.append(state.duplicate(true));state=source.pop_back();revision+=1;notice="";var saved: bool=persist();return {"ok":true,"changed":true,"persisted":saved,"reason":notice}
func select(uid: String) -> Dictionary:
	var value: Dictionary=state.duplicate(true);value["selected"]=uid;return commit(value,false)
func remove(uid: String) -> Dictionary:
	if Plan.collection(state,uid).is_empty():return Plan.failure("Choose an existing personal collection.")
	var value: Dictionary=state.duplicate(true);value["collections"]=value["collections"].filter(func(item: Dictionary):return item["uid"]!=uid)
	if value["selected"]==uid:value["selected"]=""
	return commit(value)
func put(value: Dictionary) -> Dictionary:
	if not Plan.collection_valid(value):return Plan.failure("Choose a valid collection change.")
	var renamed: Dictionary=Plan.rename(value,value["name"],state["collections"])
	if not renamed["ok"]:return renamed
	var result: Dictionary=state.duplicate(true);var found: bool=false
	for index in result["collections"].size():
		if result["collections"][index]["uid"]==value["uid"]:result["collections"][index]=value.duplicate(true);found=true;break
	if not found:result["collections"].append(value.duplicate(true))
	return commit(result)
func apply_import(plan: Dictionary) -> Dictionary:
	var checked: Dictionary=Plan.materialize_import(plan,state)
	return commit(checked["data"]) if checked["ok"] else checked
func export_file(destination: String,uids: Array) -> Dictionary:
	if uids.is_empty():return Plan.failure("Choose at least one personal collection to export.")
	var values: Array=[];var seen: Dictionary={}
	for uid in uids:
		var value: Dictionary=Plan.collection(state,uid)
		if value.is_empty():return Plan.failure("A selected collection no longer exists. Review the export again.")
		if not seen.has(uid):values.append(value.duplicate(true));seen[uid]=true
	var data: Dictionary=Plan.package(values)
	if not Plan.package_valid(data):return Plan.failure("The selected collections exceed the supported file size.")
	return {"ok":true,"count":values.size()} if Store.write_json(destination,data) else Plan.failure("The collection file could not be saved. The previous file was preserved.")
