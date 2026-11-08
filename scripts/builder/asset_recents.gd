extends RefCounted
const LIMIT: int=24
var histories: Dictionary={}
static func valid_id(value: Variant) -> bool:
	return value is String and value.length()>3 and value.length()<=512 and (value.begins_with("2d:") or value.begins_with("3d:")) and not "\n" in value and not "\r" in value
func restore(value: Variant,tasks: Dictionary) -> void:
	histories={}
	if not value is Dictionary:return
	var version: Variant=value.get("version")
	if not (version is int or version is float) or not is_finite(float(version)) or float(version)!=1 or not value.get("histories") is Dictionary:return
	for key in ["all"]+tasks.keys().slice(0,128):
		var records: Variant=value["histories"].get(key,[])
		if not records is Array:continue
		var ids: Array=[]
		for id in records.slice(0,LIMIT*4):
			if valid_id(id) and not id in ids:ids.append(id)
			if ids.size()==LIMIT:break
		if not ids.is_empty():histories[key]=ids
func state() -> Dictionary:return {"version":1,"histories":histories.duplicate(true)}
func remember(id: String,task: String,tasks: Dictionary) -> bool:
	if not valid_id(id):return false
	var changed: bool=false
	for key in ["all"]+([task] if tasks.has(task) else []):
		var ids: Array=histories.get(key,[]).duplicate()
		if not ids.is_empty() and ids[0]==id:continue
		ids.erase(id);ids.push_front(id);histories[key]=ids.slice(0,LIMIT);changed=true
	return changed
func ids(task: String) -> Array:return histories.get(task if not task.is_empty() else "all",[]).duplicate()
func available(task: String,library: RefCounted) -> Array:
	return ids(task).filter(func(id: String):return library.assets.has(id) and not library.assets[id].get("unavailable",false) and not library.assets[id].get("hidden",false))
