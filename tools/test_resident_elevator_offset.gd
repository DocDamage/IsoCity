extends "res://tools/test_resident_elevator_routines.gd"
func prepare_document(doc: RefCounted,mode: String) -> void:
	super.prepare_document(doc,mode)
	var room: Dictionary=doc.data["objects"].filter(func(item: Dictionary):return item.get("citizen_role","")=="work")[0]["interior"]
	room["floor_links"][0]["start"]=[1,-1];room["floor_links"][0]["end"]=[1,-1]
