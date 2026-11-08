extends SceneTree

const ActivityPlan=preload("res://scripts/builder/resident_activity_plan.gd")
const Scheduler=preload("res://scripts/builder/resident_activities.gd")
const Reservations=preload("res://scripts/builder/activity_reservations.gd")
const View=preload("res://scripts/builder/resident_activity_view.gd")
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;print("FAIL: "+message)
func settle() -> void:
	for frame in 4:await physics_frame
	await process_frame
func run() -> void:
	var library: RefCounted=preload("res://scripts/builder/asset_library.gd").new()
	for mode in ["2d","3d"]:
		var room: Dictionary=preload("res://scripts/builder/interiors.gd").make(mode,"Shared elevator");room["objects"]=[]
		var upper: Dictionary=room.duplicate(true);var doc: RefCounted=preload("res://scripts/builder/document.gd").new();doc.data=upper
		for x in [-2,2]:doc.add("3d:HanX_School/Student_Chair",[(x+2)*16,-32,0] if mode=="2d" else [x,.12,-2],"0")
		room["floors"]=[{"uid":"upper","name":"Upstairs","height":3,"room":upper}];room["floor_links"]=[{"uid":"lift","kind":"elevator","lower":"ground","upper":"upper","start":[0,0],"end":[0,0],"width":1.6}]
		var source: Dictionary=room.duplicate(true);var city: Dictionary={"mode":mode,"title":"Capacity city","night":false,"objects":[{"uid":"host","asset":"2d:House_Blue","position":[0,0,0],"direction":"SE","scale":1,"interior":room}],"tiles":[]}
		var world: Node=load("res://scripts/builder/world_"+mode+".gd").new();world.library=library;root.add_child(world);world.apply(city);world.walk(true);world.player.set_physics_process(false);world.player.teleport_to(world.exploration.entrance(world.instances["host"]));world.exploration.interact();await settle()
		var visit: Node=world.exploration;var pool: RefCounted=Reservations.for_world(world);var scheduler: RefCounted=Scheduler.new(pool);var view: RefCounted=View.new(visit,pool);var plan: Dictionary=ActivityPlan.compile(room,library);scheduler.configure({"host":plan});view.synchronize(scheduler,[])
		var lift: Node=visit.interior.floor_stack.lifts["lift"];var link_key: String="room:host:link:lift"
		world.player.teleport_to(Vector2.ZERO if mode=="2d" else Vector3(0,.03,0));await settle()
		check(lift.view.fully_inside() and pool.current(link_key).get("owner",weakref(null)).get_ref()==lift,"Player cabin occupancy uses the exact shared building/link reservation key: "+mode)
		lift.interact();check(lift.menu.visible,"Player can open the ordinary elevator menu while owning capacity: "+mode);lift.cancel_menu();await settle()
		check(not lift.menu.visible and not pool.current(link_key).is_empty(),"Cancelling the menu preserves cabin occupancy until the player steps outside: "+mode)
		for identity in ["resident_a","resident_b"]:check(scheduler.request(identity,"host","ground",plan["floors"]["ground"]["exit"])["ok"],"Upstairs resident request has a complete furnished itinerary: "+mode)
		for frame in 60:scheduler.step(.1)
		check(scheduler.jobs.values().all(func(job: Dictionary):return job["link_token"]==0 and job["floor"]=="ground") and pool.current(link_key).get("owner",weakref(null)).get_ref()==lift,"Both logical residents wait for the physically occupied player cabin: "+mode)
		world.player.teleport_to(Vector2(128,80) if mode=="2d" else Vector3(5,.03,5));await settle()
		check(pool.current(link_key).is_empty(),"Walking out releases player elevator capacity: "+mode)
		for frame in 20:
			scheduler.step(.1)
			if scheduler.jobs.values().any(func(job: Dictionary):return job["link_token"]!=0):break
		check(scheduler.jobs.values().filter(func(job: Dictionary):return job["link_token"]!=0).size()==1,"Exactly one resident owns the elevator after the player exits: "+mode)
		world.player.teleport_to(Vector2.ZERO if mode=="2d" else Vector3(0,.03,0));await settle();lift.interact()
		check(not lift.menu.visible and lift.notice.contains("reserved") and lift.reservation_token==0,"Player input cannot take the elevator away from the reserved resident: "+mode)
		scheduler.reset();await settle();check(lift.reservation_token!=0,"The player can acquire cabin capacity after resident cancellation: "+mode)
		view.close();world.free();await settle();check(pool.entries.is_empty() and room==source,"Actual room destruction releases cabin capacity and preserves authored source: "+mode)
	print("RESIDENT FLOOR CAPACITY: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
