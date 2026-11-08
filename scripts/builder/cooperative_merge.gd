extends RefCounted
const Delta=preload("res://scripts/builder/document_delta.gd")
const MAX_DEPTH=32
static func failure(path: String) -> Dictionary: return {"ok":false,"reason":"A collaborator changed the same field: "+path+". Your edit was not committed."}
static func apply(source: Dictionary,delta: Variant,forward: bool=true,skip_accounts: bool=false) -> Dictionary:
	var result: Dictionary=source.duplicate(true); var error: String=walk(result,delta,forward,skip_accounts,"project",0)
	return {"ok":true,"data":result} if error.is_empty() else failure(error)
static func walk(data: Dictionary,delta: Variant,forward: bool,skip_accounts: bool,path: String,depth: int) -> String:
	if depth>MAX_DEPTH or not delta is Dictionary or not delta.get("fields") is Dictionary or not delta.get("collections") is Dictionary: return path
	var target: String="after" if forward else "before"; var expected: String="before" if forward else "after"
	for key in delta["fields"]:
		if not key is String: return path
		if skip_accounts and key=="economy_account": continue
		var change: Variant=delta["fields"][key]; var here: String=path+"/"+key
		if not change is Dictionary: return here
		if change.has("nested"):
			if not data.get(key) is Dictionary: return here
			var error: String=walk(data[key],change["nested"],forward,skip_accounts,here,depth+1)
			if not error.is_empty(): return error
		else:
			if not change.get("has_"+expected) is bool or not change.get("has_"+target) is bool: return here
			if data.has(key)!=change["has_"+expected] or (data.has(key) and data[key]!=change.get(expected)): return here
			if change["has_"+target]: data[key]=Delta.copied(change.get(target))
			else: data.erase(key)
	for key in delta["collections"]:
		var here: String=path+"/"+str(key); var collection: Variant=delta["collections"][key]
		if not key is String or not data.get(key) is Array or not collection is Dictionary or not collection.get("identity") in ["uid","cell"] or not collection.get("changes") is Array: return here
		var identity: String=collection["identity"]; var records: Dictionary=Delta.indexed(data[key],identity)
		if records.size()!=data[key].size(): return here
		# Keep values and order separately while validating a transaction. Rebuilding
		# the complete dictionary after each paving tile makes district purchases
		# quadratic. Materialize the ordered collection once after all changes.
		var order: Array=records.keys()
		var insertions: Array=[]
		var changed: Dictionary={}
		for change in collection["changes"]:
			if not change is Dictionary or not change.get("key") is String or changed.has(change["key"]): return here
			var id: String=change["key"]; changed[id]=true
			if change.has("delta"):
				if not records.has(id): return here+"/"+id
				var error: String=walk(records[id]["value"],change["delta"],forward,skip_accounts,here+"/"+id,depth+1)
				if not error.is_empty(): return error
			else:
				var old: Variant=change.get(expected); var next: Variant=change.get(target)
				if old!=null and (not old is Dictionary or not old.get("value") is Dictionary): return here
				if next!=null and (not next is Dictionary or not next.get("value") is Dictionary or not next.get("index") is int and not next.get("index") is float): return here
				if (old==null)!=(not records.has(id)) or (old!=null and records[id]["value"]!=old["value"]): return here+"/"+id
				if next!=null:
					if not next["value"].has(identity) or Delta.record_key(next["value"],identity)!=id or not is_finite(float(next["index"])): return here
					if records.has(id): records[id]["value"]=Delta.copied(next["value"])
					else:
						insertions.append({"id":id,"index":int(next["index"]),"sequence":insertions.size()});records[id]={"value":Delta.copied(next["value"])}
				else:
					if not records.has(id):return here
					order.erase(id);records.erase(id)
		# Remove obsolete records before positioning new records. On Undo, a
		# restored record's saved index excludes the forward-only insertions.
		# Inserting while those still exist silently changes restored ordering.
		insertions.sort_custom(func(a: Dictionary,b: Dictionary):return a["sequence"]<b["sequence"] if a["index"]==b["index"] else a["index"]<b["index"])
		for insertion in insertions:order.insert(clampi(insertion["index"],0,order.size()),insertion["id"])
		if collection.has("order_"+target):
			if not collection.get("order_"+expected) is Array or not collection["order_"+target] is Array: return here
			var old_order: Array=collection["order_"+expected]; var new_order: Array=collection["order_"+target]
			var old_ids: Dictionary={};var new_ids: Dictionary={}
			for id in old_order:old_ids[id]=true
			for id in new_order:new_ids[id]=true
			var current_order: Array=order.filter(func(id: String):return old_ids.has(id))
			if current_order!=old_order.filter(func(id: Variant):return records.has(str(id))): return here
			var ordered: Array=[]
			for id in new_order:
				if not records.has(str(id)): return here
				ordered.append(str(id))
			for id in order:
				if not new_ids.has(id):ordered.append(id)
			order=ordered
		var values: Array=[]
		for id in order:values.append(records[id]["value"])
		data[key]=values
	return ""
