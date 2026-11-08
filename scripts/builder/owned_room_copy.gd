extends RefCounted
static var sequence: int=0
static func identity() -> String:
	sequence+=1;return "copy_"+Crypto.new().generate_random_bytes(16).hex_encode()

static func room(source: Dictionary, allocate: Callable = Callable()) -> Dictionary:
	if not allocate.is_valid(): allocate = identity
	var result: Dictionary=source.duplicate(true);var floors: Dictionary={"ground":"ground"}
	for floor in result.get("floors",[]):
		var original: String=floor["uid"];floor["uid"]=allocate.call();floors[original]=floor["uid"];floor["room"]=room(floor["room"],allocate)
	var objects: Dictionary={};var groups: Dictionary={}
	for item in result.get("objects",[]):
		var old: String=item["uid"];item["uid"]=allocate.call();objects[old]=item["uid"]
		if item.has("group"):
			if not groups.has(item["group"]):groups[item["group"]]=allocate.call()
			item["group"]=groups[item["group"]]
		if item.get("interior") is Dictionary:item["interior"]=room(item["interior"],allocate)
	for item in result.get("objects",[]):
		remap_target(item,objects)
		preload("res://scripts/builder/camping_plan.gd").copy_references(item,objects)
		preload("res://scripts/builder/cycling_plan.gd").copy_reference(item,objects)
		preload("res://scripts/builder/village_plan.gd").copy_link(item,objects)
	var joints: Dictionary = {}
	if result.has("connections"):
		result["connections"] = preload("res://scripts/builder/connector_plan.gd").copied_links(result["connections"], objects, allocate, joints)
	if result.has("modular_rooms"):
		result["modular_rooms"] = preload("res://scripts/builder/modular_building_plan.gd").copied(result["modular_rooms"],objects,groups,joints)

	for link in result.get("floor_links",[]):
		link["uid"]=allocate.call();link["lower"]=floors[link["lower"]];link["upper"]=floors[link["upper"]]
	for entrance in result.get("floor_entrances",[]):entrance["uid"]=allocate.call();entrance["floor"]=floors[entrance["floor"]]
	return result

static func remap_target(item: Dictionary,identities: Dictionary) -> void:
	if item.get("prop") is Dictionary and identities.has(item["prop"].get("target","")):item["prop"]["target"]=identities[item["prop"]["target"]]

static func item(source: Dictionary,new_uid: String,position: Array, allocate: Callable = Callable()) -> Dictionary:
	var result: Dictionary=source.duplicate(true);result["uid"]=new_uid;result["position"]=position.duplicate()
	# A copied building is an ordinary placement, not a second owner of a lot.
	result.erase("zone_uid")
	if result.get("interior") is Dictionary:result["interior"]=room(result["interior"],allocate)
	remap_target(result,{source["uid"]:new_uid});return result
