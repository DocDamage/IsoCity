extends SceneTree
const Reservations=preload("res://scripts/builder/activity_reservations.gd")
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
		var room: Dictionary=preload("res://scripts/builder/interiors.gd").make(mode,"Shared stairs");room["objects"]=[];var upper: Dictionary=room.duplicate(true);var doc: RefCounted=preload("res://scripts/builder/document.gd").new();doc.data=upper
		for x in [-3,3]:doc.add("3d:HanX_School/Student_Chair",[(x+2)*16,-64,0] if mode=="2d" else [x,.12,-6],"0")
		room["floors"]=[{"uid":"upper","name":"Upstairs","height":3,"room":upper}];var link: Dictionary={"uid":"stairs","kind":"stairs","lower":"ground","upper":"upper","start":[0,2],"end":[0,-4],"width":1.6};room["floor_links"]=[link]
		var source: Dictionary=room.duplicate(true);var city: Dictionary={"mode":mode,"title":"Capacity city","night":false,"objects":[{"uid":"host","asset":"2d:House_Blue","position":[0,0,0],"direction":"SE","scale":1,"interior":room}],"tiles":[]}
		var world: Node=load("res://scripts/builder/world_"+mode+".gd").new();world.library=library;root.add_child(world);world.apply(city);world.walk(true);world.player.set_physics_process(false);world.player.teleport_to(world.exploration.entrance(world.instances["host"]));world.exploration.interact();await settle()
		var visit: Node=world.exploration;var pool: RefCounted=Reservations.for_world(world);var scheduler: RefCounted=preload("res://scripts/builder/resident_activities.gd").new(pool);var view: RefCounted=preload("res://scripts/builder/resident_activity_view.gd").new(visit,pool);var plan: Dictionary=preload("res://scripts/builder/resident_activity_plan.gd").compile(room,library);scheduler.configure({"host":plan});view.synchronize(scheduler,[])
		var stack: Node=visit.interior.floor_stack;var key: String="room:host:link:stairs"
		if mode=="2d":
			world.player.teleport_to(stack.endpoint(link,false));stack.begin({"link":link,"upper":false,"target":"upper"});stack.set_physics_process(false)
		else:world.player.teleport_to(Vector3(0,.24,1.95))
		await settle();check(pool.current(key).get("owner",weakref(null)).get_ref()==world.player,"Player stair occupancy uses the exact shared resident link key: "+mode)
		var holder:=Node.new();root.add_child(holder);world.reparent(holder);world.reparent(root);holder.free();await settle();check(not pool.current(key).is_empty(),"Temporary canvas reparenting retains player stair capacity: "+mode)
		for identity in ["a","b"]:check(scheduler.request(identity,"host","ground",plan["floors"]["ground"]["exit"])["ok"],"Resident has a valid upstairs itinerary: "+mode)
		for frame in 60:scheduler.step(.1)
		check(scheduler.jobs.values().all(func(job: Dictionary):return job["link_token"]==0 and job["floor"]=="ground"),"Both residents wait for the player's stair flight: "+mode)
		if mode=="2d":stack.finish()
		world.player.teleport_to(Vector2(128,80) if mode=="2d" else Vector3(5,.03,5));await settle();check(pool.current(key).is_empty(),"Leaving the stair flight releases player capacity: "+mode)
		for frame in 20:
			scheduler.step(.1)
			if scheduler.jobs.values().any(func(job: Dictionary):return job["link_token"]!=0):break
		check(scheduler.jobs.values().filter(func(job: Dictionary):return job["link_token"]!=0).size()==1,"Only one resident can own the newly available stair flight: "+mode)
		if mode=="2d":
			world.player.teleport_to(stack.endpoint(link,false));stack.begin({"link":link,"upper":false,"target":"upper"});check(stack.travel.is_empty() and stack.notice.contains("occupied"),"Player stair input respects the resident's reservation")
		else:
			var from:=Vector3(0,.03,2.6);var motion:=Vector3(0,0,-.4);check(world.player.terrain_motion_filter.call(from,motion)==Vector3.ZERO and world.player.get_meta("terrain_blocked","").contains("occupied"),"Native player walking cannot enter an occupied stair flight")
			check(stack.filter_stair_motion(Vector3(0,.24,1.8),Vector3(0,0,.1))!=Vector3.ZERO,"A player restored inside an occupied flight can retreat toward the nearest landing")
		scheduler.reset();await settle()
		if mode=="2d":stack.begin({"link":link,"upper":false,"target":"upper"});check(not stack.travel.is_empty(),"Player admission resumes after resident cancellation")
		else:check(stack.filter_stair_motion(Vector3(0,.03,2.6),Vector3(0,0,-.4))!=Vector3.ZERO,"Player admission resumes after resident cancellation")
		view.close();world.free();await settle();check(pool.entries.is_empty() and room==source,"Room destruction releases all stair capacity and preserves source: "+mode)
	print("RESIDENT STAIR CAPACITY: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
