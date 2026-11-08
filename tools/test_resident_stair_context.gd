extends "res://tools/test_resident_stair_routines.gd"
var reopened: Dictionary={}
func facts_path() -> String:return "res://output/verification/asset_expansion/I14/stair_context_facts.json"
func hidden_frames() -> int:return 0
func before_close(_mode: String) -> void:pass
func after_open(_mode: String) -> void:pass
func descending() -> bool:return false
func tick() -> void:
	await super.tick()
	var mode: String=citizens.dimension;var world: Node=studio.worlds[mode];var visit: Node=world.exploration
	if reopened.has(mode) or not visit.interior:return
	var held: Array=citizens.activities.scheduler.jobs.values().filter(func(job: Dictionary):return job.has("stair") and job["stair"]["progress"]>.4 and job["stair"]["progress"]<.55 and (job["stair"]["source"]=="upper")==descending())
	if held.is_empty():return
	reopened[mode]=true
	var job: Dictionary=held[0];var building: String=visit.interior_uid;var token: int=job["link_token"];var body: Node=citizens.residents.filter(func(resident: Dictionary):return resident["id"]==job["resident"])[0]["actor"];var identity: int=body.get_instance_id();var jobs: Array=citizens.activities.scheduler.jobs.values().map(func(value: Dictionary):return value["id"])
	var progress: float=job["stair"]["progress"]
	var pose: Variant=body.body.transform if mode=="3d" else [body.action,body.direction,body.get_node("Sprite2D").frame]
	await before_close(mode)
	visit.leave_interior();await settle();check(is_instance_valid(body) and body.get_instance_id()==identity,"Closing on the flight preserves the original body before freeing the stair tree: "+mode)
	for frame in hidden_frames():await super.tick()
	var expected: Dictionary=citizens.activities.scheduler.jobs[job["resident"]]["stair"].duplicate(true);var opened: Dictionary={}
	if hidden_frames()>0:check(expected["progress"]>progress,"Unrendered stair walking advances private progress: "+mode)
	var capture_opened: Callable=func():
		opened["point"]=body.position if mode=="2d" else visit.interior.floor_stack.worlds[expected["source"]].objects.to_local(body.global_position)
		opened["pose"]=body.body.transform if mode=="3d" else [body.action,body.direction,body.get_node("Sprite2D").frame]
		opened["token"]=citizens.activities.scheduler.jobs[job["resident"]]["link_token"]
	visit.interior_opened.connect(capture_opened)
	world.player.teleport_to(visit.entrance(world.instances[building]));studio.control_settings.execute("interact");await settle();world.player.teleport_to(Vector2(128,0) if mode=="2d" else Vector3(5,.2,4));visit.interior_opened.disconnect(capture_opened);facts[mode]["previous"].clear()
	check(citizens.activities.scheduler.jobs.values().map(func(value: Dictionary):return value["id"])==jobs and body.get_instance_id()==identity,"Reopening retains both itineraries and original resident identities: "+mode)
	var point: Vector3=expected["point"];var restored: Vector3=Vector3(opened["point"].x,opened["point"].y,0) if mode=="2d" else opened["point"]
	check(restored.distance_to(point)<.005 and opened["token"]==token,"Reopening restores the private supported flight position and exact shared reservation: "+mode)
	if mode=="3d":check(body.clear_at(body.global_transform,true),"Restored native capsule is clear of the actual treads before resuming")
	check(opened["pose"]==pose,"Reopening preserves the original walking action/frame or model pose: "+mode)
	await after_open(mode)
func after_completed(doc: RefCounted,mode: String) -> void:
	check(reopened.get(mode,false),"The fixture actually interrupts a live mid-flight trip: "+mode)
	await super.after_completed(doc,mode)
