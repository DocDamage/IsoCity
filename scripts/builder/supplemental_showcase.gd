extends RefCounted

# An editable sampler, with one representative from each supplied art pack.
static func make(mode: String, library: RefCounted) -> Dictionary:
	var doc = preload("res://scripts/builder/document.gd").new()
	doc.data = preload("res://scripts/builder/templates.gd").make(mode, "blank")
	doc.data["title"] = "Supplemental asset showcase"
	var packs: Dictionary = {}
	for id in library.assets:
		var asset: Dictionary = library.assets[id]
		var pack: String = asset["data"].get("source_pack", "")
		if pack.is_empty() or not (id.begins_with("2d:Supplemental_") or id.begins_with("3d:Supplemental_")) or (mode == "2d" and id.begins_with("3d:")): continue
		if not packs.has(pack) or asset["data"].get("kind") == "char": packs[pack] = id
	var names: Array = packs.keys(); names.sort()
	for index in names.size():
		var id: String = packs[names[index]]
		var asset: Dictionary = library.assets[id]
		var point := Vector2((index % 6 - 2.5) * 16, (index / 6 - 2) * 16)
		var position: Array = preload("res://scripts/builder/traffic_plan.gd").world(point, mode)
		doc.add(id, position, str(library.directions(id)[0]), asset["data"].get("default_scale", 1))
		doc.data["objects"][-1]["name"] = names[index] + " · " + asset.get("name", id)
	doc.data["spawn"] = [0, 60, 0] if mode == "2d" else [0, .2, 10]
	return doc.data

static func swat(mode: String, library: RefCounted) -> Dictionary:
	var doc=preload("res://scripts/builder/document.gd").new()
	doc.data=preload("res://scripts/builder/templates.gd").make(mode,"blank"); doc.data["title"]="SWAT compound"
	var placements: Array=[
		["Building_SWAT_HQ",-16,-15,0],["Building_Police_Station",16,-15,0],
		["Vehicle_SWAT_Van",-5,11.5,90],["Vehicle_Patrol_SUV",7,8.5,270],
		["Prop_Folding_Chair",-10,18,0],["Prop_Folding_Table",-8,18,0],
		["Prop_Searchlight",-15,17,0],["Prop_Generator",-18,18,0],
		["Training_Wall_Door",15,18,0],["Training_Wall_Straight",19,18,0],
		["SWAT_Pose_Radio",11,20,0],["SWAT_K9_Dog_Stand",12.5,20,0],
		["Prop_Gear_Crate",-5,18,0],["Prop_Briefing_Board",-8,21,0]]
	for value in placements:
		var id: String="3d:Supplemental_SWAT/"+value[0]
		if library.assets.has(id): doc.add(id,preload("res://scripts/builder/traffic_plan.gd").world(Vector2(value[1],value[2]),mode),str(value[3]),1)
	for x in range(-24,25,8):
		doc.add("3d:HanX_Traffic/Road_Straight",preload("res://scripts/builder/traffic_plan.gd").world(Vector2(x,10),mode,.02),"90",1)
	doc.data["spawn"]=preload("res://scripts/builder/traffic_plan.gd").world(Vector2(0,17),mode,.2 if mode=="3d" else 0)
	return doc.data
