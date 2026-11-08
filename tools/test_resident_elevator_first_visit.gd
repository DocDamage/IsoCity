extends "res://tools/test_resident_elevator_routines.gd"
var expected: Dictionary={}
func target_phase() -> String:return "moving"
func capture_name(mode: String) -> String:return "elevator_first_visit_"+mode+".png"
func facts_path() -> String:return "res://output/verification/asset_expansion/I14/elevator_first_visit_facts.json"
func before_visit(doc: RefCounted,_building: Dictionary,mode: String) -> void:
	var source: Dictionary=doc.data.duplicate(true);var count: int=doc.undo_history.size();var child_count: int=studio.worlds[mode].get_child_count();var travelling: Dictionary={}
	for frame in 600:
		await tick()
		for job in citizens.activities.scheduler.jobs.values():
			if job["link_token"]!=0 and job.get("transport",{}).get("phase","")==target_phase() and (target_phase()!="moving" or job["transport"]["height"]>1.1):travelling=job;break
		if not travelling.is_empty():break
	check(not travelling.is_empty() and not studio.worlds[mode].exploration.interior and studio.worlds[mode].get_child_count()==child_count,"A wholly unrendered trip has private "+target_phase()+" state without creating room worlds: "+mode)
	if travelling.is_empty():return
	var phase: String=travelling["transport"]["call_phase"] if target_phase()=="calling" else "idle" if target_phase()=="boarding" else target_phase()
	expected[mode]={"height":travelling["transport"]["height"],"token":travelling["link_token"],"job":travelling["id"],"phase":phase}
	check(doc.data==source and doc.undo_history.size()==count,"Unrendered elevator simulation creates no room, content or history: "+mode)
	var visit: Node=studio.worlds[mode].exploration;visit.interior_opened.connect(func():
		var lift: Node=visit.interior.floor_stack.lifts["lift"];expected[mode]["opened_height"]=lift.height;expected[mode]["opened_token"]=lift.npc_token if lift.npc_token!=0 else lift.call_owner_token;expected[mode]["opened_phase"]=lift.phase,CONNECT_ONE_SHOT)
func while_visited(_doc: RefCounted,_building: Dictionary,mode: String) -> void:
	if not expected.has(mode):return
	check(expected[mode].get("opened_token",0)==expected[mode]["token"] and absf(expected[mode].get("opened_height",-100)-expected[mode]["height"])<.08 and expected[mode].get("opened_phase","")==expected[mode]["phase"],"First entry materializes the car's logical position, phase and reservation without restarting: "+mode)
