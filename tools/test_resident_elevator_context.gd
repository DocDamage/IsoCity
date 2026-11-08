extends "res://tools/test_resident_elevator_routines.gd"
var reopened: Dictionary={}
var motion_trace: Dictionary={}
func facts_path() -> String:return "res://output/verification/asset_expansion/I14/elevator_context_facts.json"
func capture_name(mode: String) -> String:return "elevator_context_before_"+mode+".png"
func interrupt(lift: Node) -> bool:return lift.npc_token!=0 and lift.phase=="moving" and lift.height>=1.1 and lift.height<=1.7
func hidden_frames() -> int:return 0
func tick() -> void:
	await super.tick()
	var mode: String=citizens.dimension;var world: Node=studio.worlds[mode];var visit: Node=world.exploration
	if mode=="3d" and visit.interior and "--trace-motion" in OS.get_cmdline_user_args():
		for resident in citizens.residents:
			var job: Dictionary=citizens.activities.scheduler.result(resident["id"])
			if job.get("state","")!="returning" or job.get("floor","")!="upper" or job.get("link_token",0)!=0:continue
			var actor: Node=resident["actor"];var pose: Transform3D=PhysicsServer3D.body_get_state(actor.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
			if not motion_trace.has(resident["id"]):motion_trace[resident["id"]]=[]
			var trace: Array=motion_trace[resident["id"]];var previous: Dictionary=trace.back() if not trace.is_empty() else {};var contacts: Array=[]
			for index in actor.get_slide_collision_count():
				var hit: Variant=actor.get_slide_collision(index);contacts.append({"path":str(hit.get_collider().get_path()),"normal":str(hit.get_normal())})
			trace.append({"position":actor.global_position,"server":pose.origin,"velocity":actor.velocity,"recovery":actor.recovery_count,"steps":actor.step_count,"point":job["point"],"deep_clear":actor.clear_at(actor.global_transform,true),"on_floor":actor.is_on_floor(),"contacts":contacts})
			if trace.size()>140:trace.pop_front()
			if not previous.is_empty() and (Vector2(previous["position"].x-actor.global_position.x,previous["position"].z-actor.global_position.z).length()>.1 or previous["recovery"]!=actor.recovery_count):FileAccess.open("res://output/verification/asset_expansion/I14/elevator_context_motion.json",FileAccess.WRITE).store_string(JSON.stringify(motion_trace,"\t"))
	if reopened.has(mode) or not visit.interior:return
	var lift: Node=visit.interior.floor_stack.lifts["lift"]
	if not interrupt(lift):return
	reopened[mode]=true
	var building: String=visit.interior_uid;var height: float=lift.height;var token: int=lift.npc_token if lift.npc_token!=0 else lift.call_owner_token
	var held: Array=citizens.activities.scheduler.jobs.values().filter(func(job: Dictionary):return job["link_token"]==token)
	if held.is_empty():check(false,"The interrupted controller has a live caller-owned itinerary: "+mode);return
	var body: Node=citizens.residents.filter(func(resident: Dictionary):return resident["id"]==held[0]["resident"])[0]["actor"];var identity: int=body.get_instance_id()
	var pose: Variant=body.body.transform if mode=="3d" else [body.action,body.direction,body.get_node("Sprite2D").frame]
	var jobs: Array=citizens.activities.scheduler.jobs.values().map(func(job: Dictionary):return job["id"])
	facts[mode]["previous"].clear()
	visit.leave_interior();await settle();check(is_instance_valid(body) and body.get_instance_id()==identity,"Closing mid-ride detaches the original passenger before freeing its controller: "+mode)
	for frame in hidden_frames():await super.tick()
	var remaining: Array=citizens.activities.scheduler.jobs.values().filter(func(job: Dictionary):return job["link_token"]==token)
	var expected: Dictionary=remaining[0]["transport"].duplicate(true) if not remaining.is_empty() else {}
	if hidden_frames()>0:check(not visit.interior and expected.get("height",0)>height+.5,"The private car motion advances while its room is unrendered: "+mode)
	var opened: Dictionary={};var capture_opened: Callable=func():
		var restored: Node=visit.interior.floor_stack.lifts["lift"];opened["height"]=restored.height;opened["token"]=restored.npc_token if restored.npc_token!=0 else restored.call_owner_token;opened["phase"]=restored.phase
		opened["pose"]=body.body.transform if mode=="3d" else [body.action,body.direction,body.get_node("Sprite2D").frame]
	visit.interior_opened.connect(capture_opened)
	world.player.teleport_to(visit.entrance(world.instances[building]));studio.control_settings.execute("interact");await settle();world.player.teleport_to(Vector2(128,0) if mode=="2d" else Vector3(5,.2,4));await super.tick()
	visit.interior_opened.disconnect(capture_opened)
	check(citizens.activities.scheduler.jobs.values().map(func(job: Dictionary):return job["id"])==jobs and is_instance_valid(body) and body.get_instance_id()==identity,"Reopening mid-ride preserves both job identities and the original passenger body: "+mode)
	check(opened.get("pose")==pose,"Reopening preserves the actual passenger's in-flight source action/frame or model pose: "+mode)
	var phase: String=expected.get("call_phase","") if expected.get("phase","")=="calling" else "idle" if expected.get("phase","") in ["boarding","alighting"] else expected.get("phase","")
	check(opened.get("token",0)==token and absf(opened.get("height",-100)-expected.get("height",-200))<.08 and opened.get("phase","")==phase,"Reopening resumes the car's private height, ownership and door/motion phase before subsequent physics steps: "+mode+" expected="+str(expected)+" restored="+str(opened))
	if "--capture" in OS.get_cmdline_user_args():await capture_lift(mode,visit.interior.floor_stack.lifts["lift"],"elevator_context_reopened_"+mode+".png")
