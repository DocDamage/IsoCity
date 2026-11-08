extends SceneTree
const Plan=preload("res://scripts/builder/resident_activity_plan.gd")
const Scheduler=preload("res://scripts/builder/resident_activities.gd")
const View=preload("res://scripts/builder/resident_activity_view.gd")
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;print("FAIL: "+message)
func settle() -> void:
	for frame in 8:await process_frame
	await physics_frame
func run() -> void:
	var studio: Control=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio);await settle()
	for mode in ["2d","3d"]:
		studio.switch_mode(mode);var doc: RefCounted=preload("res://scripts/builder/document.gd").new();doc.data=preload("res://scripts/builder/templates.gd").make(mode,"blank");studio.documents[mode]=doc
		var room: Dictionary=preload("res://scripts/builder/interiors.gd").make(mode,"Resident room");room["objects"]=[];var room_doc: RefCounted=preload("res://scripts/builder/document.gd").new();room_doc.data=room
		for x in [-2,2]:room_doc.add("3d:HanX_School/Student_Chair",[(x+2)*16,-32,0] if mode=="2d" else [x,.12,-2],"0")
		var building: Dictionary=doc.add("3d:HanX_School/School_Building",[300,0,0] if mode=="2d" else [30,0,0],"0");building["interior"]=room;studio.changed();await settle();var world: Node=studio.worlds[mode];var visit: Node=world.exploration
		var manager: Node=preload("res://scripts/builder/citizen_runtime.gd").new();manager.dimension=mode;world.add_child(manager);manager.set_physics_process(false);manager.container=Node2D.new() if mode=="2d" else Node3D.new();manager.container.name="OriginalResidentBodies";world.objects.add_child(manager.container)
		var residents: Array=[];var identities: Array=[]
		for index in 2:
			var actor: Node=manager.make_actor("resident_"+str(index));actor.teleport_to(Vector2(100+index*32,40) if mode=="2d" else Vector3(10+index,.05,3));actor.visible=false;residents.append({"id":"resident_"+str(index),"actor":actor});identities.append(actor.get_instance_id())
		var scheduler: RefCounted=Scheduler.new();var plan: Dictionary=Plan.compile(room,studio.library);scheduler.configure({building["uid"]:plan});var entry: Vector3=plan["floors"]["ground"]["exit"]
		for resident in residents:scheduler.request(resident["id"],building["uid"],"ground",entry)
		for tick in 400:
			scheduler.step(.05)
			if scheduler.jobs.values().all(func(job: Dictionary):return job["state"]=="service"):break
		check(scheduler.jobs.values().all(func(job: Dictionary):return job["state"]=="service"),"Two logical residents arrive at distinct real room stations before player visit: "+mode)
		var original: Dictionary=doc.data.duplicate(true);var history: int=doc.undo_history.size();var ids: Array=scheduler.jobs.values().map(func(job: Dictionary):return job["id"]);var view: RefCounted=View.new(visit,scheduler.reservations)
		studio.set_walking(true);world.player.set_physics_process(false);visit.nearby={"item":building,"node":world.instances[building["uid"]]};visit.enter_interior();await settle();check(visit.interior!=null,"Player enters actual owned room during logical service: "+mode)
		view.synchronize(scheduler,residents);await settle()
		check(view.attached.size()==2 and residents.map(func(resident: Dictionary):return resident["actor"].get_instance_id())==identities,"The original bodies appear in the visited room without actor duplication: "+mode)
		check(scheduler.jobs.values().map(func(job: Dictionary):return job["id"])==ids,"Changing rendering context preserves job identities: "+mode)
		for resident in residents:
			var actor: Node=resident["actor"];var job: Dictionary=scheduler.result(resident["id"]);check(actor.get_parent()==visit.room_world().objects and actor.visible,"Resident uses the actual room render context: "+mode)
			if mode=="3d":check(actor.body.global_position.is_equal_approx(visit.room_world().objects.to_global(job["station"]["point"])-Vector3.UP*.85),"Resident body uses the calibrated actual seat anchor")
			else:check(actor.action=="sit" and not actor.interaction_visual_offset.is_zero_approx(),"Resident uses the supplied seated sprite action and source anchor")
		var held: Dictionary=scheduler.result(residents[0]["id"]);check(preload("res://scripts/builder/activity_reservations.gd").for_world(visit.room_world()).acquire(held["station_key"],visit.props)==0,"Player interaction sees the occupied resident station: "+mode)
		check(visit.room_world().instances.size()==2 and visit.room_world().instances.values().all(func(node: Node):return node.is_visible_in_tree()),"Both actual source chairs remain visible around their resident bodies: "+mode)
		if "--capture" in OS.get_cmdline_user_args():
			studio.set_process(false)
			if mode=="3d":world.walking=false;world.target=Vector3(0,.8,-1);world.distance=8;world.update_camera()
			else:world.camera.position=Vector2(24,-20);world.camera.zoom=Vector2(4,4)
			await settle();RenderingServer.force_draw(false);RenderingServer.force_draw(false);root.get_texture().get_image().save_png("res://output/verification/asset_expansion/I14/residents_seated_"+mode+".png")
			for resident in residents:resident["actor"].visible=false
			await settle();RenderingServer.force_draw(false);RenderingServer.force_draw(false);root.get_texture().get_image().save_png("res://output/verification/asset_expansion/I14/station_reference_"+mode+".png")
			for resident in residents:resident["actor"].visible=true
			if mode=="3d":
				var original_yaw: float=world.yaw;world.yaw=225;world.update_camera();await settle();RenderingServer.force_draw(false);RenderingServer.force_draw(false);root.get_texture().get_image().save_png("res://output/verification/asset_expansion/I14/residents_seated_reverse_3d.png");world.yaw=original_yaw;world.update_camera()
			var render_facts: Array=[]
			for uid in visit.room_world().instances:
				var node: Node=visit.room_world().instances[uid];var facts: Dictionary={"uid":uid,"path":str(node.get_path()),"position":str(node.global_position),"visible":node.is_visible_in_tree(),"children":[]}
				for child in node.find_children("*","VisualInstance3D",true,false):facts["children"].append({"path":str(child.get_path()),"position":str(child.global_position),"scale":str(child.global_basis.get_scale()),"visible":child.is_visible_in_tree(),"layers":child.layers,"bounds":str(child.get_aabb())})
				for child in node.find_children("*","Sprite2D",true,false):facts["children"].append({"path":str(child.get_path()),"position":str(child.global_position),"visible":child.is_visible_in_tree(),"texture_size":str(child.texture.get_size()) if child.texture else "missing"})
				render_facts.append(facts)
			FileAccess.open("res://output/verification/asset_expansion/I14/render_facts_"+mode+".json",FileAccess.WRITE).store_string(JSON.stringify(render_facts,"\t"))
			if mode=="3d":world.walking=true
			studio.set_process(true)
		visit.leave_interior();await settle();check(residents.all(func(resident: Dictionary):return is_instance_valid(resident["actor"]) and resident["actor"].get_parent()==manager.container) and view.attached.is_empty(),"Closing room returns original bodies before its tree is freed: "+mode)
		visit.nearby={"item":building,"node":world.instances[building["uid"]]};visit.enter_interior();await settle();view.synchronize(scheduler,residents);scheduler.move_actor=view.move
		for tick in 1200:
			await physics_frame;scheduler.step(1.0/60);view.synchronize(scheduler,residents,1.0/60)
			if scheduler.jobs.values().all(func(job: Dictionary):return job["state"]=="returning" and job["reason"].contains("obstructed")):break
		check(scheduler.jobs.values().all(func(job: Dictionary):return job["state"]=="returning" and job["reason"].contains("obstructed")),"Player physically blocking the exit pauses residents without bypassing collision: "+mode)
		if not scheduler.jobs.values().all(func(job: Dictionary):return job["state"]=="returning" and job["reason"].contains("obstructed")):
			for job in scheduler.jobs.values():print("EXIT WAIT ",mode," ",job["state"]," ",job["position"]," ",job["reason"]," blocked=",job["blocked_seconds"])
		check(scheduler.jobs.values().map(func(job: Dictionary):return job["id"])==ids,"Blocked return retains the same jobs and progress: "+mode)
		world.player.teleport_to(Vector2(-64,32) if mode=="2d" else Vector3(-4,.2,2));await settle()
		for tick in 600:
			await physics_frame;scheduler.step(1.0/60);view.synchronize(scheduler,residents,1.0/60)
			if scheduler.jobs.values().all(func(job: Dictionary):return job["state"]=="complete"):break
		check(scheduler.jobs.values().all(func(job: Dictionary):return job["state"]=="complete"),"Live room bodies stand and physically walk their return routes: "+mode)
		if not scheduler.jobs.values().all(func(job: Dictionary):return job["state"]=="complete"):
			for job in scheduler.jobs.values():print("RESIDENT STOP ",mode," ",job["state"]," ",job["position"]," ",job["reason"]," leg ",job["leg"]," point ",job["point"])
		visit.leave_interior();studio.set_walking(false);await settle();check(residents.map(func(resident: Dictionary):return resident["actor"].get_instance_id())==identities,"Repeated room visits retain the same two resident bodies: "+mode)
		check(doc.data==original and doc.undo_history.size()==history,"Visits, poses, reservations and physical NPC movement preserve authored content/history: "+mode)
		view.close();scheduler.reset();manager.free();await settle()
	studio.free();await settle();print("RESIDENT ACTIVITY VIEW: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
