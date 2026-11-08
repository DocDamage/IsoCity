extends "res://tools/test_resident_stair_routines.gd"
var samples: Dictionary={}
func facts_path() -> String:return "res://output/verification/asset_expansion/I14/stair_terrain_facts.json"
func prepare_document(doc: RefCounted,mode: String) -> void:
	super.prepare_document(doc,mode);var room: Dictionary=doc.data["objects"].filter(func(item: Dictionary):return item.get("citizen_role","")=="work")[0]["interior"]
	for data in [room,room["floors"][0]["room"]]:data["terrain"]={"enabled":true,"bounds":[-8,-8,16,16]}
func tick() -> void:
	await super.tick()
	if citizens.dimension!="2d" or not studio.worlds["2d"].exploration.interior:return
	for resident in citizens.residents:
		var job: Dictionary=citizens.activities.scheduler.jobs.get(resident["id"],{});var state: Dictionary=job.get("stair",{});var token: String=str(job.get("link_token",0))
		if state.is_empty() or samples.has(token) or state["progress"]<.4 or state["progress"]>.6:continue
		samples[token]=true;await process_frame;await process_frame
		var expected: float=-(lerpf(state["source_height"],state["target_height"],state["progress"]))*8
		check(absf(resident["actor"].terrain_visual_offset.y-expected)<.05,"Automatic flat-terrain presentation cannot overwrite a resident's in-flight stair elevation")
func after_completed(doc: RefCounted,mode: String) -> void:
	if mode=="2d":check(samples.size()==4,"All four sprite stair trips are observed with terrain presentation enabled")
	await super.after_completed(doc,mode)
