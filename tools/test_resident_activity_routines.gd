extends SceneTree
const Doc=preload("res://scripts/builder/document.gd")
const Templates=preload("res://scripts/builder/templates.gd")
var checks: int=0
var failures: int=0
var studio: Control
var citizens: Node
var business: Node
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;print("FAIL: "+message)
func settle() -> void:
	for frame in 10:await process_frame
	await physics_frame
func tick() -> void:
	await physics_frame;citizens.step(1.0/60);business.step(1.0/60)
func states() -> String:
	return str(citizens.residents.map(func(resident: Dictionary):return [resident["status"],str(resident["actor"].position) if is_instance_valid(resident["actor"]) else "missing"]))
func destination_spec() -> Dictionary:
	return {"name":"school","asset":"3d:HanX_School/School_Building","scale":.25,"role":"work","kind":"service","hour":9,"anchor":{"point":[0,0,8],"arrival":[0,0,12]}}
func while_visited(_doc: RefCounted,_building: Dictionary,_mode: String) -> void:pass
func after_completed(_doc: RefCounted,_mode: String) -> void:pass
func prepare_document(_doc: RefCounted,_mode: String) -> void:pass
func before_visit(_doc: RefCounted,_building: Dictionary,_mode: String) -> void:pass
func expected_attachments(_mode: String) -> int:return 2
func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio);await settle()
	check(not preload("res://scripts/builder/citizen_plan.gd").settings({})["interior_activities"],"Interior activity simulation defaults off")
	var spec: Dictionary=destination_spec()
	for mode in ["2d","3d"]:
		studio.switch_mode(mode);var doc: RefCounted=Doc.new();doc.data=Templates.make(mode,"blank");studio.documents[mode]=doc
		var home: Dictionary=doc.add("2d:House_Blue",[-112,48,0] if mode=="2d" else [-7,0,2],"SE",.6);home["citizen_role"]="home"
		var school: Dictionary=doc.add(spec["asset"],[112,-32,0] if mode=="2d" else [7,0,-2],"0",spec["scale"]);school["citizen_role"]=spec["role"];school["entrance_anchor"]=spec["anchor"];school["business"]={"kind":spec["kind"],"capacity":1,"open_hour":0,"close_hour":23.9,"duration_scale":2}
		prepare_document(doc,mode)
		doc.data["citizens"]={"enabled":true,"interior_activities":true,"population":2,"seed":42,"day_length":3600,"start_hour":spec["hour"]};doc.data["economy"]={"enabled":true,"starting_cash":100000};doc.data["economy_account"]=preload("res://scripts/builder/economy_plan.gd").fresh_account(doc.data,studio.library);studio.economy_tools.pauses[mode]=true
		studio.changed();studio.citizen_tools.dirty=true;studio.business_tools.dirty=true;await settle();studio.citizen_tools.tick(1);studio.business_tools.tick(1)
		citizens=studio.citizen_tools.managers[mode];business=studio.business_tools.managers[mode];citizens.set_physics_process(false);business.set_physics_process(false)
		check(citizens.activities!=null and citizens.residents.size()==2,"Normal citizen configuration initializes the interior coordinator and two original bodies: "+mode)
		if citizens.activities==null:continue
		var ids: Array=citizens.residents.map(func(resident: Dictionary):return resident["actor"].get_instance_id());var source: Dictionary=doc.data.duplicate(true);var undo_count: int=doc.undo_history.size();var arrived: bool=false
		for frame in 2400:
			await tick()
			if citizens.activities.scheduler.jobs.size()==2:arrived=true;break
		check(arrived,"Normal daily routes reach the "+spec["name"]+" and reserve furnished stations: "+mode+" "+states())
		if not arrived:citizens.clear();continue
		check(doc.data==source and doc.undo_history.size()==undo_count,"Offscreen resident entry preserves authored rooms, transforms, budget and history: "+mode)
		var jobs: Array=citizens.activities.scheduler.jobs.values();var job_ids: Array=jobs.map(func(job: Dictionary):return job["id"])
		check(jobs[0]["station_key"]!=jobs[1]["station_key"] and business.service.visits.is_empty(),"Two stations are distinct and service has not started at the exterior entrance: "+mode)
		await before_visit(doc,school,mode)
		studio.set_walking(true);var world: Node=studio.worlds[mode];var visit: Node=world.exploration;world.player.set_physics_process(false);world.player.teleport_to(visit.entrance(world.instances[school["uid"]]));studio.control_settings.execute("interact");await settle()
		check(visit.interior!=null and visit.interior_uid==school["uid"],"Actual normal interact enters the "+spec["name"]+" during resident itineraries: "+mode)
		if not visit.interior:citizens.clear();studio.set_walking(false);continue
		check(citizens.activities.scheduler.jobs.values().map(func(job: Dictionary):return job["id"])==job_ids and citizens.residents.map(func(resident: Dictionary):return resident["actor"].get_instance_id())==ids,"Lazy room creation and normal editor refresh retain both jobs and original actor identities: "+mode)
		check(citizens.activities.view.attached.size()==expected_attachments(mode) and citizens.active,"Ordinary simulation stays active and renders the original resident bodies in the applicable floor context: "+mode)
		check(doc.data["economy_account"]["cash"]==100000,"The normal starter-room creation stays complimentary: "+mode)
		world.player.teleport_to(Vector2(128,0) if mode=="2d" else Vector3(5,.2,4));await settle();await while_visited(doc,school,mode);source=doc.data.duplicate(true);undo_count=doc.undo_history.size();var completed: bool=false;var saw_service: bool=false
		if not citizens.activities:
			check(false,"The interior activity coordinator remains configured during the visit: "+mode);visit.leave_interior();studio.set_walking(false);citizens.clear();continue
		for frame in 3600:
			await tick()
			if business.service.visits.values().any(func(value: Dictionary):return value["state"] in ["active","queued"]):saw_service=true
			if citizens.activities.history.size()==2:completed=true;break
		check(completed and citizens.activities.history.all(func(value: Dictionary):return value["state"]=="complete"),"Ordinary resident routines finish station service and exit through the live room route: "+mode+" "+states())
		if not completed:
			for job in citizens.activities.scheduler.jobs.values():print("ROUTINE STOP ",mode," ",job["state"]," ",job["position"]," ",job["reason"])
			var stopped: Array=[]
			for resident in citizens.residents:
				var actor: Node=resident["actor"];var detail: Dictionary={"job":citizens.activities.scheduler.result(resident["id"]),"parent":str(actor.get_parent().get_path()),"global_position":str(actor.global_position),"velocity":str(actor.velocity),"travel_phase":citizens.activities.view.travel.states.get(resident["id"],{}).get("phase","")}
				if mode=="3d":detail.merge({"deep_clear":actor.clear_at(actor.global_transform,true),"clear":actor.clear_at(actor.global_transform),"on_floor":actor.is_on_floor(),"platform_velocity":str(actor.get_platform_velocity()),"safe_positions":str(actor.safe_positions),"overlap_time":actor.overlap_time,"last_position":str(actor.last_position)})
				var contacts: Array=[]
				for index in actor.get_slide_collision_count():
					var collision: Variant=actor.get_slide_collision(index);var collider: Node=collision.get_collider()
					contacts.append({"collider":str(collider.get_path()),"normal":str(collision.get_normal()),"position":str(collision.get_position()),"travel":str(collision.get_travel()),"remainder":str(collision.get_remainder()),"collider_transform":str(collider.global_transform)})
				detail["contacts"]=contacts;stopped.append(detail)
			FileAccess.open("res://output/verification/asset_expansion/I14/routine_stop_"+mode+".json",FileAccess.WRITE).store_string(JSON.stringify(stopped,"\t"))
		check(saw_service and business.service.history.size()==2 and business.service.inventory.size()==2,"The existing capacity-one business queue serves each resident once: "+mode)
		check(doc.data==source and doc.undo_history.size()==undo_count and doc.data["economy_account"]["cash"]==100000,"Ordinary live resident activity preserves authored content, treasury and history: "+mode)
		check(citizens.residents.map(func(resident: Dictionary):return resident["actor"].get_instance_id())==ids and citizens.activities.scheduler.reservations.entries.is_empty(),"Completed routines retain both original bodies and release station ownership: "+mode)
		visit.leave_interior();studio.set_walking(false);await settle()
		for frame in 900:await tick()
		check(citizens.activities.history.size()==2 and business.service.history.size()==2,"A completed daily activity does not immediately re-enter and duplicate service: "+mode)
		await after_completed(doc,mode)
		citizens.clear();await settle()
	studio.free();await settle();print("RESIDENT ACTIVITY ROUTINES %s: %d checks, %d failures"%[spec["name"],checks,failures]);quit(1 if failures else 0)
