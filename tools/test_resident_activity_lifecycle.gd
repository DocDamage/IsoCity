extends "res://tools/test_resident_activity_routines.gd"

func prepare_document(doc: RefCounted,mode: String) -> void:
	var item: Dictionary=doc.add("2d:House_Blue",[256,128,0] if mode=="2d" else [16,0,16],"SE",.6);item["citizen_role"]="none";item["name"]="Exterior interruption fixture"

func while_visited(doc: RefCounted,building: Dictionary,mode: String) -> void:
	var world: Node=studio.worlds[mode];var visit: Node=world.exploration;var coordinator: RefCounted=citizens.activities
	var jobs: Array=coordinator.scheduler.jobs.values().map(func(job: Dictionary):return job["id"])
	var bodies: Array=citizens.residents.map(func(resident: Dictionary):return resident["actor"].get_instance_id())
	var source: Dictionary=doc.data.duplicate(true);var count: int=doc.undo_history.size()
	visit.leave_interior();await settle()
	check(coordinator.view.attached.is_empty() and citizens.residents.all(func(resident: Dictionary):return is_instance_valid(resident["actor"]) and resident["actor"].get_parent()==citizens.container),"Closing an occupied room restores both original bodies before the room is freed: "+mode)
	for frame in 30:await tick()
	world.player.teleport_to(visit.entrance(world.instances[building["uid"]]));studio.control_settings.execute("interact");await settle()
	world.player.teleport_to(Vector2(128,0) if mode=="2d" else Vector3(5,.2,4));await settle()
	check(coordinator.view.attached.size()==2 and citizens.residents.map(func(resident: Dictionary):return resident["actor"].get_instance_id())==bodies and coordinator.scheduler.jobs.values().map(func(job: Dictionary):return job["id"])==jobs,"Reopening during ordinary activity retains both jobs, original actor bodies and station ownership: "+mode)
	check(doc.data==source and doc.undo_history.size()==count,"Closing/reopening an already owned occupied room does not author content or history: "+mode)
	var home: Dictionary=doc.data["objects"].filter(func(item: Dictionary):return item.get("citizen_role","")=="none")[0];var original: Dictionary=home.duplicate(true)
	doc.checkpoint();home["position"][0]+=4 if mode=="2d" else 1;studio.changed();await settle()
	var node: Node=world.instances[home["uid"]];var colliders: Array=([node]+node.find_children("*","CollisionObject2D",true,false)+node.find_children("*","CollisionObject3D",true,false)).filter(func(body: Node):return body is CollisionObject2D or body is CollisionObject3D)
	check(not colliders.is_empty() and colliders.all(func(body: Node):return body.collision_layer==0),"An exterior edit during a visit keeps changed city colliders suspended away from the room plane: "+mode)
	doc.checkpoint();home["visible"]=false;studio.changed();await settle();visit.leave_interior();await settle()
	check(not node.visible and colliders.all(func(body: Node):return body.collision_layer==0),"Leaving the room preserves an exterior object's newly authored hidden visibility and inactive collisions: "+mode)
	doc.checkpoint();home["position"]=original["position"].duplicate();home.erase("visible");studio.changed();await settle();studio.citizen_tools.tick(1)
	world.player.teleport_to(visit.entrance(world.instances[building["uid"]]));studio.control_settings.execute("interact");await settle();world.player.teleport_to(Vector2(128,0) if mode=="2d" else Vector3(5,.2,4));await settle()
	check(coordinator.view.attached.size()==2 and coordinator.scheduler.jobs.values().map(func(job: Dictionary):return job["id"])==jobs,"Exterior edits and another room visit preserve the two occupied itineraries: "+mode)

func after_completed(doc: RefCounted,mode: String) -> void:
	var gone: Dictionary=citizens.residents[1];var removed_id: String=gone["id"];var removed_body: WeakRef=weakref(gone["actor"])
	check(business.service.inventory.has(removed_id) and not business.service.visits.has(removed_id),"A completed resident keeps earned inventory after its transient visit is removed: "+mode)
	doc.checkpoint();doc.data["citizens"]["population"]=1;studio.changed();await settle();studio.citizen_tools.tick(1);studio.business_tools.tick(1);await tick()
	check(citizens.residents.size()==1 and not is_instance_valid(removed_body.get_ref()) and not citizens.activities.scheduler.jobs.has(removed_id),"Population reduction removes only the departing actor and its transient itinerary: "+mode)
	check(not business.service.inventory.has(removed_id) and not business.service.visits.has(removed_id),"Population reduction forgets the removed resident's completed inventory as well as active visits: "+mode)
	var actor: Node=citizens.residents[0]["actor"];var retained_inventory: Dictionary=business.service.inventory.duplicate(true)
	doc.checkpoint();doc.data["citizens"]["interior_activities"]=false;studio.changed();await settle();studio.citizen_tools.tick(1)
	check(citizens.activities==null and citizens.residents[0]["actor"]==actor and business.service.inventory==retained_inventory,"Disabling optional interior activity preserves the exterior resident and its earned inventory: "+mode)
