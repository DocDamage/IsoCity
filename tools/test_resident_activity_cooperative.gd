extends "res://tools/test_resident_activity_interruptions.gd"
var guest: Control
func decorate_room(room: Dictionary,mode: String) -> void:
	var doc: RefCounted=Doc.new();doc.data=room
	var door: Dictionary=doc.add("2d:Door_White",[128,64,0] if mode=="2d" else [8,.03,8],studio.library.directions("2d:Door_White")[0]);door["uid"]="shared_door";door["open"]=false
func wait_until(test: Callable) -> bool:
	for frame in 900:
		if test.call():return true
		await process_frame
	return false
func synced() -> bool:
	var a: RefCounted=studio.cooperative_tools;var b: RefCounted=guest.cooperative_tools
	return a.participating and b.participating and not a.dirty and not b.dirty and b.session.pending.is_empty() and a.snapshot()==b.snapshot() and a.session.data==b.session.data
func disconnect_case() -> void:
	guest.cooperative_tools.leave();studio.cooperative_tools.leave();await settle();citizens.clear();studio.worlds[studio.mode].exploration.leave_interior();studio.set_walking(false)
func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate();guest=load("res://scenes/builder.tscn").instantiate()
	for editor in [studio,guest]:editor.storage_enabled=false;root.add_child(editor)
	await settle()
	for editor in [studio,guest]:editor.consumer_shell.dismiss_welcome()
	for mode in ["2d","3d"]:
		for kind in ["stairs","elevator"]:
			await setup_case(mode,kind);guest.switch_mode(mode);var a: RefCounted=studio.cooperative_tools;var b: RefCounted=guest.cooperative_tools;var world: Node=studio.worlds[mode];var visit: Node=world.exploration;var coordinator: RefCounted=citizens.activities;var ids: Array=citizens.residents.map(func(resident: Dictionary):return resident["actor"].get_instance_id());var jobs: Array=coordinator.scheduler.jobs.values().map(func(job: Dictionary):return job["id"])
			a.name_field.text="Resident host";a.password.text="resident-pass";a.port.value=0;a.host_game()
			check(a.session.server!=null,"Host starts with valid authored shared fixtures: "+mode+" "+kind+" "+a.session.notice)
			if a.session.server==null:citizens.clear();visit.leave_interior();studio.set_walking(false);continue
			b.name_field.text="Resident guest";b.password.text="resident-pass";b.address.text="127.0.0.1";b.port.value=a.session.server.get_local_port();b.join_game()
			var label: String=mode+" "+kind;check(await wait_until(synced),"Actual host/guest controls converge with optional resident activities: "+label)
			check(visit.interior!=null and coordinator.scheduler.jobs.values().map(func(job: Dictionary):return job["id"])==jobs,"Joining a session with equivalent normalized source preserves the host's visit and both private jobs: "+label)
			if not visit.interior:await disconnect_case();continue
			var ready: bool=false
			for frame in 1200:
				await tick()
				ready=coordinator.scheduler.jobs.values().any(func(job: Dictionary):return job.has("stair") and job["stair"]["progress"]>.35) if kind=="stairs" else visit.interior.floor_stack.lifts["link"].npc_token!=0 and visit.interior.floor_stack.lifts["link"].phase=="moving"
				if ready:break
			check(ready,"Host has an actual occupied native transport before the guest's structural edit: "+label)
			guest.interior_tools.start("work");await settle();guest.current().checkpoint();guest.current().object("shared_door")["open"]=true;guest.changed()
			check(await wait_until(synced),"Guest door state edit converges while the host remains aboard transport: "+label)
			check(visit.interior!=null and visit.room_world("ground").exploration.door_states.get("shared_door",[{}])[0].get("open",false),"The host's actual visited-room door adapter reflects the accepted source edit: "+label)
			check(coordinator.scheduler.jobs.values().map(func(job: Dictionary):return job["id"])==jobs and coordinator.history.is_empty(),"Live door refresh preserves both private itineraries and their controller: "+label)
			guest._command("undo",null);check(await wait_until(synced),"Guest shared door Undo converges without retiring the visit: "+label)
			check(visit.interior!=null and not visit.room_world("ground").exploration.door_states.get("shared_door",[{}])[0].get("open",false),"The actual visited door returns to its authored closed state: "+label)
			var before: Dictionary=a.session.data.duplicate(true);guest.interior_tools.floor_tools.switch_floor("upper");guest.interior_tools.floor_tools.remove_floor()
			check(await wait_until(func():return synced() and studio.current().object("work")["interior"]["floors"].is_empty()),"The guest's real floor removal is accepted through host authority: "+label)
			for frame in 20:await tick()
			citizens.paused=true;var removed: Dictionary=a.session.data.duplicate(true)
			check(not visit.interior and coordinator.history.size()==2 and coordinator.history.all(func(value: Dictionary):return value["state"]=="cancelled") and coordinator.scheduler.reservations.entries.is_empty(),"Accepted shared removal closes stale physics and releases both host itineraries: "+label)
			check(citizens.residents.map(func(resident: Dictionary):return resident["actor"].get_instance_id())==ids and citizens.residents.all(func(resident: Dictionary):return resident["actor"].get_parent()==citizens.container),"Shared floor removal preserves the host's two original actor bodies: "+label)
			check(not JSON.stringify(a.session.data).contains("link_token") and not JSON.stringify(a.session.data).contains("activity_1"),"Shared documents contain authored data without private actor/job occupancy: "+label)
			guest._command("undo",null);check(await wait_until(func():return synced() and a.session.data==before),"Guest shared Undo restores exact floor/link/furnishing identities and account through authority: "+label)
			check(coordinator.scheduler.jobs.values().all(func(job: Dictionary):return job["id"] not in jobs) and coordinator.scheduler.reservations.entries.is_empty(),"Shared Undo cannot resurrect interrupted transient jobs: "+label)
			guest._command("redo",null);check(await wait_until(func():return synced() and a.session.data==removed),"Guest shared Redo restores the exact accepted removal and account: "+label)
			guest.interior_tools.leave();citizens.paused=false;await disconnect_case()
	guest.free();studio.free();await settle();print("RESIDENT ACTIVITY COOPERATIVE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
