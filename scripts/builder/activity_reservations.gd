extends RefCounted

# Transient, scope-qualified station ownership. Tokens prevent a late cancellation
# from releasing a station that has since been acquired by another activity.
var entries: Dictionary={}
var sequence: int=0

static func for_world(world: Node) -> RefCounted:
	if not world.has_meta("activity_reservations"):
		world.set_meta("activity_reservations",load("res://scripts/builder/activity_reservations.gd").new())
	return world.get_meta("activity_reservations")

func current(key: String) -> Dictionary:
	if entries.has(key) and not is_instance_valid(entries[key]["owner"].get_ref()): entries.erase(key)
	return entries.get(key,{})

func acquire(key: String,owner: Object) -> int:
	if key.is_empty() or not is_instance_valid(owner) or not current(key).is_empty(): return 0
	sequence+=1; entries[key]={"owner":weakref(owner),"token":sequence}; return sequence

func release(key: String,token: int) -> void:
	if current(key).get("token",0)==token: entries.erase(key)

func release_owner(owner: Object) -> void:
	for key in entries.keys():
		var entry: Dictionary=current(key)
		if entry.is_empty() or entry["owner"].get_ref()==owner: entries.erase(key)
