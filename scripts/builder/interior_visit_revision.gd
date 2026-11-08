extends RefCounted

# A visit owns a transient physical floor stack. Keep its loaded layout revision
# separate from source dictionaries, which can be mutated in place by history or
# a peer. Door state and cosmetic metadata use their existing runtime adapters.
static func layout(room: Dictionary) -> Dictionary:
	var value: Dictionary={}
	for key in ["mode","exit","spawn","tiles","roads","terrain","terrain_vertices","water_cells","layers","floor_links","floor_entrances"]:
		if key in ["tiles","roads","terrain_vertices","water_cells","floor_links","floor_entrances"]:value[key]=room.get(key,[]).duplicate(true)
		elif room.has(key):value[key]=room[key].duplicate(true) if room[key] is Array or room[key] is Dictionary else room[key]
	value["objects"]=[]
	for item in room.get("objects",[]):
		var geometry: Dictionary=item.duplicate(true)
		for key in ["name","title","notes","tags","open","part_colors","tint","color","citizen_role","business","interior"]:geometry.erase(key)
		value["objects"].append(geometry)
	value["floors"]=[]
	for floor in room.get("floors",[]):value["floors"].append({"uid":floor["uid"],"height":floor["height"],"room":layout(floor["room"])})
	return value
static func stamp(room: Dictionary) -> String:
	# Shared snapshots add empty collections and normalize JSON numbers. Those
	# equivalent forms must not tear down a valid occupied visit on joining.
	return JSON.stringify(JSON.parse_string(JSON.stringify(layout(room)))).sha256_text()

static func content_stamp(room: Dictionary) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(room))).sha256_text()
