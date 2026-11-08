extends RefCounted

const Reservations=preload("res://scripts/builder/activity_reservations.gd")

static func ledger(stack: Node) -> RefCounted:
	return Reservations.for_world(stack.get_parent())

static func key(stack: Node,uid: String) -> String:
	var room: Node=stack.get_parent();var outer: Node=room.get_parent();var building: String="preview_"+str(room.get_instance_id())
	if is_instance_valid(outer) and "exploration" in outer and is_instance_valid(outer.exploration) and outer.exploration.interior==room:building=outer.exploration.interior_uid
	return "room:"+building+":link:"+uid
