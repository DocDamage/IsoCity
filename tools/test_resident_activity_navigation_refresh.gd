extends "res://tools/test_resident_activity_interruptions.gd"
func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio);await settle()
	for mode in ["2d","3d"]:
		for kind in ["stairs","elevator"]:
			var doc: RefCounted=await setup_case(mode,kind);var world: Node=studio.worlds[mode];var visit: Node=world.exploration;var coordinator: RefCounted=citizens.activities;var ids: Array=citizens.residents.map(func(resident: Dictionary):return resident["actor"].get_instance_id());var ready: bool=false
			for frame in 1200:
				await tick()
				ready=coordinator.scheduler.jobs.values().any(func(job: Dictionary):return job.has("stair") and job["stair"]["progress"]>.35) if kind=="stairs" else visit.interior.floor_stack.lifts["link"].npc_token!=0 and visit.interior.floor_stack.lifts["link"].phase=="moving"
				if ready:break
			var label: String=mode+" "+kind;check(ready,"Fixture reaches a native trip before unrelated exterior construction: "+label)
			if not ready:citizens.clear();visit.leave_interior();studio.set_walking(false);continue
			var signature: int=citizens.scene_signature;var old_obstacles: int=citizens.obstacles.size();var jobs: Array=coordinator.scheduler.jobs.values().map(func(job: Dictionary):return job["id"]);var tokens: Array=coordinator.scheduler.jobs.values().map(func(job: Dictionary):return job["link_token"]);var state_ids: Array=coordinator.view.travel.states.keys();var source: Dictionary=doc.data.duplicate(true);doc.checkpoint();var extra: Dictionary=doc.add("2d:House_Blue",[480,240,0] if mode=="2d" else [30,0,30],"SE",2);extra["uid"]="new_obstacle";extra["citizen_role"]="none";studio.changed();await settle();studio.citizen_tools.tick(1)
			check(visit.interior!=null and citizens.scene_signature!=signature and citizens.obstacles.size()>old_obstacles,"Unrelated exterior construction refreshes current navigation while the player remains inside: "+label)
			check(coordinator.scheduler.jobs.values().map(func(job: Dictionary):return job["id"])==jobs and coordinator.scheduler.jobs.values().map(func(job: Dictionary):return job["link_token"])==tokens and coordinator.view.travel.states.keys()==state_ids,"Navigation refresh preserves live transport state, both jobs and shared ownership: "+label)
			if kind=="elevator":check(visit.interior.floor_stack.lifts["link"].npc_token in tokens and visit.interior.floor_stack.lifts["link"].npc_token!=0,"Exterior refresh leaves the original resident aboard its actual moving car: "+label)
			var instance: Node=world.instances["new_obstacle"];var colliders: Array=([instance]+instance.find_children("*","CollisionObject2D",true,false)+instance.find_children("*","CollisionObject3D",true,false)).filter(func(node: Node):return node is CollisionObject2D or node is CollisionObject3D)
			check(not colliders.is_empty() and colliders.all(func(node: Node):return node.collision_layer==0),"Navigation uses authored collisions without activating hidden exterior colliders: "+label)
			var inside_obstacles: Array=citizens.obstacles.duplicate();var edited_cash: int=doc.data["economy_account"]["cash"];for frame in 90:await tick()
			check(citizens.residents.map(func(resident: Dictionary):return resident["actor"].get_instance_id())==ids and coordinator.history.all(func(value: Dictionary):return value["state"]!="cancelled"),"Unrelated edits neither duplicate original bodies nor cancel valid room activities: "+label)
			visit.leave_interior();await settle();studio.citizen_tools.tick(1);check(citizens.obstacles==inside_obstacles,"The visited and visible city use the same refreshed navigation obstacles: "+label)
			check(doc.data["economy_account"]["cash"]==edited_cash,"Transient transport/navigation refresh changes no treasury: "+label)
			citizens.clear();studio.set_walking(false);await settle()
	studio.free();await settle();print("RESIDENT ACTIVITY NAVIGATION REFRESH: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
