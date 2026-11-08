extends "res://tools/test_resident_elevator_routines.gd"
func activity_floor() -> String:return "middle"
func facts_path() -> String:return "res://output/verification/asset_expansion/I14/elevator_middle_facts.json"
func prepare_document(doc: RefCounted,mode: String) -> void:
	super.prepare_document(doc,mode)
	var room: Dictionary=doc.data["objects"].filter(func(item: Dictionary):return item.get("citizen_role","")=="work")[0]["interior"]
	room["floors"][0]["uid"]="middle";room["floors"][0]["name"]="Middle classroom"
	var top: Dictionary=room["floors"][0]["room"].duplicate(true);top["objects"]=[];top["title"]="Top floor"
	room["floors"].append({"uid":"upper","name":"Top floor","height":6,"room":top})
