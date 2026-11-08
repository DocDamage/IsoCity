extends RefCounted
const PATH="res://resources/catalog/task_collections.json"
var tasks: Dictionary={}
var available: Dictionary={}
var revision: int=0

static func text(value: Variant,limit: int) -> bool:return value is String and not value.is_empty() and value.length()<=limit

func build(assets: Dictionary) -> void:
	tasks.clear();available.clear();revision+=1
	var value: Variant=JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
	if not value is Dictionary or value.get("version")!=1 or not value.get("tasks") is Dictionary:return
	for key in value["tasks"].keys().slice(0,64):
		var task: Variant=value["tasks"][key]
		if not text(key,64) or not task is Dictionary or not text(task.get("name"),100) or not text(task.get("note"),600) or not task.get("sets") is Array:continue
		var reviewed: Dictionary={"name":task["name"],"note":task["note"],"sets":{}}
		for source in task["sets"].slice(0,16):
			if not source is Dictionary or not text(source.get("id"),64) or not text(source.get("name"),100) or not source.get("items") is Array:continue
			var members: Dictionary={}
			for record in source["items"].slice(0,256):
				if not record is Dictionary or not text(record.get("asset"),300) or record.get("part") not in ["essential","extra"] or record.get("site") not in ["indoor","outdoor","either"]:continue
				var id: String=record["asset"];members[id]=record.duplicate(true)
				if not available.has(id):available[id]=assets.has(id) and not assets[id].get("unavailable",false) and FileAccess.file_exists(assets[id]["path"])
			if not members.is_empty():reviewed["sets"][source["id"]]={"name":source["name"],"items":members}
		if not reviewed["sets"].is_empty():tasks[key]=reviewed

func default_set(key: String) -> String:return str(tasks[key]["sets"].keys()[0]) if tasks.has(key) else ""

func members(key: String,style: String="",part: String="",inside: bool=false) -> Dictionary:
	var result: Dictionary={"ids":{},"missing":[],"outdoor":[],"total":0}
	if not tasks.has(key):return result
	for set_key in tasks[key]["sets"]:
		if not style.is_empty() and style!=set_key:continue
		for id in tasks[key]["sets"][set_key]["items"]:
			var record: Dictionary=tasks[key]["sets"][set_key]["items"][id]
			if not part.is_empty() and record["part"]!=part:continue
			result["total"]+=1
			if inside and record["site"]=="outdoor":
				if id not in result["outdoor"]:result["outdoor"].append(id)
			elif not available.get(id,false):
				if id not in result["missing"]:result["missing"].append(id)
			else:result["ids"][id]=record
	return result
