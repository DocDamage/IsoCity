extends RefCounted

const Plan=preload("res://scripts/builder/floor_plan.gd")
const Anchors=preload("res://scripts/builder/entrance_anchors.gd")

static func entries(item: Dictionary) -> Array:
	var result: Array=[{"uid":"","floor":"ground"}]
	for entry in item.get("interior",{}).get("floor_entrances",[]):
		if item.has("missing_asset"): continue
		if item["asset"].begins_with("2d:") and entry.has("view") and entry["view"]!=item["direction"]: continue
		result.append(entry)
	return result

static func name_for(root: Dictionary,uid: String) -> String:
	for floor in Plan.definitions(root):
		if floor["uid"]==uid: return floor["name"]
	return uid

static func outside(node: Node,item: Dictionary,entry: Dictionary,dimension: String,library: RefCounted) -> Variant:
	if entry.get("uid","").is_empty():
		if item.has("missing_asset"): return node.transform*Vector2(0,24) if dimension=="2d" else node.transform*Vector3(0,.02,1.3)
		return Anchors.position_for(node,item,dimension,library)
	var raw: Array=entry["position"]
	return Anchors.source_position(node,item,dimension,library,Vector3(raw[0],raw[1],raw[2]))

static func landing(root: Dictionary,entry: Dictionary,dimension: String) -> Variant:
	var room: Dictionary=Plan.room(root,entry["floor"])
	var values: Array=entry.get("arrival",room.get("exit",[0,60,0] if dimension=="2d" else [0,.2,2.5]))
	return Vector2(values[0],values[1]) if dimension=="2d" else Vector3(values[0],values[1],values[2])
