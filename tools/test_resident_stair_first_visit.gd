extends "res://tools/test_resident_stair_routines.gd"
var expected: Dictionary={}
func facts_path() -> String:return "res://output/verification/asset_expansion/I14/stair_first_visit_facts.json"
func before_visit(doc: RefCounted,_building: Dictionary,mode: String) -> void:
	var world: Node=studio.worlds[mode];var source: Dictionary=doc.data.duplicate(true);var count: int=doc.undo_history.size();var children: int=world.get_child_count();var travelling: Dictionary={}
	for frame in 600:
		await tick()
		for job in citizens.activities.scheduler.jobs.values():
			if job.has("stair") and job["stair"]["progress"]>.4:travelling=job;break
		if not travelling.is_empty():break
	check(not travelling.is_empty() and not world.exploration.interior and world.get_child_count()==children,"A wholly logical stair trip advances without creating any room worlds: "+mode)
	if travelling.is_empty():return
	check(doc.data==source and doc.undo_history.size()==count,"Unrendered stair progress preserves exact authored source and history: "+mode)
	expected[mode]={"point":travelling["stair"]["point"],"token":travelling["link_token"],"resident":travelling["resident"]}
	world.exploration.interior_opened.connect(func():
		var body: Node=citizens.residents.filter(func(resident: Dictionary):return resident["id"]==travelling["resident"])[0]["actor"]
		expected[mode]["opened_point"]=Vector3(body.position.x,body.position.y,0) if mode=="2d" else world.exploration.interior.floor_stack.worlds[travelling["stair"]["source"]].objects.to_local(body.global_position)
		expected[mode]["opened_token"]=citizens.activities.scheduler.jobs[travelling["resident"]]["link_token"],CONNECT_ONE_SHOT)
func while_visited(_doc: RefCounted,_building: Dictionary,mode: String) -> void:
	if not expected.has(mode):return
	check(expected[mode].get("opened_token",0)==expected[mode]["token"] and expected[mode].get("opened_point",Vector3.INF).distance_to(expected[mode]["point"])<.005,"First entry restores the same logical tread position and exact reservation: "+mode)
