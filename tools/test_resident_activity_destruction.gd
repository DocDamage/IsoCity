extends "res://tools/test_resident_activity_routines.gd"

func run() -> void:
	for mode in ["2d","3d"]:
		studio=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio);await settle();studio.switch_mode(mode)
		var doc: RefCounted=Doc.new();doc.data=Templates.make(mode,"blank");studio.documents[mode]=doc
		var home: Dictionary=doc.add("2d:House_Blue",[-112,48,0] if mode=="2d" else [-7,0,2],"SE",.6);home["citizen_role"]="home"
		var destination: Dictionary=doc.add("3d:HanX_School/School_Building",[112,-32,0] if mode=="2d" else [7,0,-2],"0",.25);destination["citizen_role"]="work";destination["entrance_anchor"]={"point":[0,0,8],"arrival":[0,0,12]};destination["business"]={"kind":"service","open_hour":0,"close_hour":23.9}
		doc.data["citizens"]={"enabled":true,"interior_activities":true,"population":2,"seed":42,"start_hour":9,"day_length":3600};studio.changed();await settle();studio.citizen_tools.tick(1);studio.business_tools.tick(1)
		citizens=studio.citizen_tools.managers[mode];business=studio.business_tools.managers[mode];citizens.set_physics_process(false);business.set_physics_process(false)
		var world: Node=studio.worlds[mode];var visit: Node=world.exploration;var approach: Variant=visit.entrance(world.instances[destination["uid"]])
		# Isolate teardown at the coordinator's verified-arrival boundary. Ordinary
		# city routing and service completion are covered by the routine suites.
		for resident in citizens.residents:resident["actor"].teleport_to(approach);check(citizens.activities.arrive(resident,destination["uid"]),"Verified arrival starts an occupied job for destruction: "+mode)
		studio.set_walking(true);world.player.set_physics_process(false);world.player.teleport_to(approach);studio.control_settings.execute("interact");await settle()
		var coordinator: RefCounted=citizens.activities;var ledger: RefCounted=coordinator.scheduler.reservations;var bodies: Array=citizens.residents.map(func(resident: Dictionary):return weakref(resident["actor"]))
		check(visit.interior!=null and coordinator.view.attached.size()==2 and ledger.entries.size()==2,"Actual room contains two reserved original bodies before destroying their manager: "+mode)
		var source: Dictionary=doc.data.duplicate(true);var count: int=doc.undo_history.size()
		studio.set_process(false);citizens.free()
		check(coordinator.closed and coordinator.view.attached.is_empty() and coordinator.scheduler.jobs.is_empty() and ledger.entries.is_empty(),"Actual manager destruction closes occupied jobs and releases the shared room ledger: "+mode)
		check(bodies.all(func(body: WeakRef):return not is_instance_valid(body.get_ref())) and not coordinator.scheduler.service_request.is_valid() and not coordinator.scheduler.move_actor.is_valid(),"Destruction frees the two original bodies and breaks scheduler callback ownership: "+mode)
		check(visit.interior!=null and doc.data==source and doc.undo_history.size()==count,"Destroying transient residents preserves the player visit, source and history: "+mode)
		visit.leave_interior();studio.free();await settle()
	print("RESIDENT ACTIVITY DESTRUCTION: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
