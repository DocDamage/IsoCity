extends RefCounted

static func copied(value: Variant) -> Variant:
	return value.duplicate(true) if value is Dictionary or value is Array else value

static func record_key(item: Dictionary, field: String) -> String:
	var value: Variant=item[field]
	if field=="cell" and value is Array and value.size()==2 and (value[0] is int or value[0] is float) and (value[1] is int or value[1] is float) and is_finite(float(value[0])) and is_finite(float(value[1])): return "%d,%d" % [int(value[0]),int(value[1])]
	return str(value)

static func indexed(values: Array, field: String) -> Dictionary:
	var result: Dictionary = {}
	for i in values.size():
		if not values[i] is Dictionary or not values[i].has(field): return {}
		var key: String = record_key(values[i], field)
		if result.has(key): return {}
		result[key] = {"value": values[i], "index": i}
	return result

static func between(before: Dictionary, after: Dictionary) -> Dictionary:
	var result: Dictionary = {"fields": {}, "collections": {}}
	var keys: Dictionary = before.duplicate()
	keys.merge(after)
	for key in keys:
		if before.has(key) == after.has(key) and typeof(before.get(key)) == typeof(after.get(key)) and before.get(key) == after.get(key): continue
		var identity: String = "uid" if key in ["zones","transit_lines","protected_areas","blueprints","objects","floors","floor_links","floor_entrances","connections","utility_nodes","utility_edges","modular_rooms"] else "cell"
		if (identity=="uid" or key in ["tiles","roads","terrain_vertices","water_cells"]) and before.get(key) is Array and after.get(key) is Array:
			var old: Dictionary = indexed(before[key], identity)
			var next: Dictionary = indexed(after[key], identity)
			if old.size() == before[key].size() and next.size() == after[key].size():
				var changes: Array = []
				var ids: Dictionary = old.duplicate()
				ids.merge(next)
				for id in ids:
					if old.get(id, {}).get("value") == next.get(id, {}).get("value"): continue
					if old.has(id) and next.has(id):
						changes.append({"key":id,"index_before":old[id]["index"],"index_after":next[id]["index"],"delta":between(old[id]["value"],next[id]["value"])})
					else: changes.append({"key": id, "before": copied(old.get(id)), "after": copied(next.get(id))})
				var collection: Dictionary = {"identity": identity, "changes": changes}
				var surviving_before: Array = old.keys().filter(func(id: String) -> bool: return next.has(id))
				var surviving_after: Array = next.keys().filter(func(id: String) -> bool: return old.has(id))
				if surviving_before != surviving_after:
					collection["order_before"] = old.keys()
					collection["order_after"] = next.keys()
				result["collections"][key] = collection
				continue
		if before.get(key) is Dictionary and after.get(key) is Dictionary:
			result["fields"][key]={"nested":between(before[key],after[key])}
		else: result["fields"][key] = {"has_before": before.has(key), "has_after": after.has(key), "before": copied(before.get(key)), "after": copied(after.get(key))}
	return result

static func apply(data: Dictionary, delta: Dictionary, forward: bool) -> void:
	var side: String = "after" if forward else "before"
	for key in delta["fields"]:
		var change: Dictionary = delta["fields"][key]
		if change.has("nested"): apply(data[key],change["nested"],forward)
		elif change["has_" + side]: data[key] = copied(change[side])
		else: data.erase(key)
	for key in delta["collections"]:
		var collection: Dictionary = delta["collections"][key]
		var affected: Dictionary = {}
		var inserts: Array = []
		var records: Dictionary=indexed(data[key],collection["identity"])
		for change in collection["changes"]:
			affected[change["key"]] = true
			if change.has("delta"):
				var record: Dictionary=records[change["key"]]["value"]
				apply(record,change["delta"],forward)
				inserts.append({"index":change["index_"+side],"value":record})
			elif change[side] != null: inserts.append({"index":change[side]["index"],"value":copied(change[side]["value"])})
		var values: Array = []
		for item in data[key]:
			if not affected.has(record_key(item, collection["identity"])): values.append(item)
		inserts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["index"] < b["index"])
		for entry in inserts: values.insert(mini(entry["index"], values.size()), entry["value"])
		if collection.has("order_" + side):
			records = indexed(values, collection["identity"])
			values = []
			for id in collection["order_" + side]: values.append(records[id]["value"])
		data[key] = values
