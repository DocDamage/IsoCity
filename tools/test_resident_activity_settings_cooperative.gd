extends "res://tools/test_resident_activity_cooperative.gd"
func apply_guest() -> void:
	guest.citizen_tools.panel.find_children("*","Button",true,false).filter(func(node: Button):return node.text=="Apply simulation settings")[0].pressed.emit()
func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate();guest=load("res://scenes/builder.tscn").instantiate()
	for editor in [studio,guest]:editor.storage_enabled=false;root.add_child(editor)
	await settle()
	for editor in [studio,guest]:editor.consumer_shell.dismiss_welcome()
	for mode in ["2d","3d"]:
		for kind in ["stairs","elevator"]:
			await setup_case(mode,kind);guest.switch_mode(mode);var a: RefCounted=studio.cooperative_tools;var b: RefCounted=guest.cooperative_tools;var world: Node=studio.worlds[mode];var visit: Node=world.exploration;var old: RefCounted=citizens.activities;var ids: Array=citizens.residents.map(func(resident: Dictionary):return resident["actor"].get_instance_id());var label: String=mode+" "+kind
			a.name_field.text="Activity settings host";a.password.text="activity-settings-pass";a.port.value=0;a.host_game();b.name_field.text="Activity settings guest";b.password.text="activity-settings-pass";b.address.text="127.0.0.1";b.port.value=a.session.server.get_local_port();b.join_game();check(await wait_until(synced),"Actual peers converge before guest settings changes: "+label)
			var ready: bool=false
			for frame in 1200:
				await tick()
				ready=old.scheduler.jobs.values().any(func(job: Dictionary):return job.has("stair") and job["stair"]["progress"]>.35) if kind=="stairs" else visit.interior.floor_stack.lifts["link"].npc_token!=0 and visit.interior.floor_stack.lifts["link"].phase=="moving"
				if ready:break
			check(ready,"Host has an actual native passenger before the guest disables interior activities: "+label)
			var source: Dictionary=a.session.data.duplicate(true);guest.control_settings.execute("resident_activities");await settle();guest.citizen_tools.interior_activities.button_pressed=false;apply_guest()
			check(await wait_until(func():return synced() and not a.session.data[mode]["citizens"]["interior_activities"]),"Guest Apply is accepted through authoritative shared settings: "+label);await settle()
			check(visit.interior!=null and citizens.activities==null and old.closed and old.scheduler.jobs.is_empty() and old.scheduler.reservations.entries.is_empty(),"Disabling cancels live ownership while preserving the host player's room visit: "+label)
			check(citizens.residents.map(func(resident: Dictionary):return resident["actor"].get_instance_id())==ids,"Disabling from another peer preserves both original resident bodies: "+label)
			var disabled: Dictionary=a.session.data.duplicate(true);guest._command("undo",null)
			check(await wait_until(func():return synced() and a.session.data==source),"Guest shared Undo restores the exact enabled setting and account: "+label);await settle()
			check(visit.interior!=null and citizens.activities!=null and citizens.activities!=old and citizens.activities.scheduler.jobs.is_empty(),"Enabling from another peer initializes fresh coordination while the host is already inside: "+label)
			guest._command("redo",null);check(await wait_until(func():return synced() and a.session.data==disabled),"Guest shared Redo restores the explicit disabled option: "+label);await settle();check(citizens.activities==null,"Redo stops the newly initialized coordinator inside the unchanged visited room: "+label)
			guest._command("undo",null);check(await wait_until(func():return synced() and a.session.data==source),"Guest can restore the option for an ordinary fresh routine: "+label);await settle()
			if citizens.activities==null:check(false,"Enabled coordinator is available for the resumed routine: "+label);await disconnect_case();continue
			var business_before: int=business.service.history.size();var approach: Variant=visit.entrance(world.instances["work"])
			for resident in citizens.residents:resident["actor"].teleport_to(approach);citizens.activities.arrive(resident,"work")
			var completed: bool=false
			for frame in 3600:
				await tick()
				if citizens.activities.history.size()==2:completed=true;break
			if not completed or business.service.history.size()!=business_before+2:
				var jobs: Array=[]
				for resident in citizens.residents:jobs.append(citizens.activities.scheduler.result(resident["id"]))
				var lift: Node=visit.interior.floor_stack.lifts.get("link");var lift_state: Dictionary={"phase":lift.phase,"height":lift.height,"last_stop":lift.last_stop,"npc_token":lift.npc_token,"call_owner":lift.call_owner_token} if is_instance_valid(lift) else {}
				FileAccess.open("res://output/verification/asset_expansion/I14/settings_cooperative_stop_"+mode+"_"+kind+".json",FileAccess.WRITE).store_string(JSON.stringify({"jobs":jobs,"history":citizens.activities.history,"business_history":business.service.history,"inventory":business.service.inventory,"lift":lift_state},"\t"))
			check(completed and citizens.activities.history.all(func(value: Dictionary):return value["state"]=="complete") and business.service.history.size()==business_before+2 and business.service.inventory.size()==2,"Fresh ordinary routines after shared re-enabling serve each original resident exactly once: "+label)
			check(citizens.residents.map(func(resident: Dictionary):return resident["actor"].get_instance_id())==ids and a.session.data==source and synced() and citizens.activities.scheduler.reservations.entries.is_empty(),"Resumed private activities preserve shared authored data, treasury, bodies and released ownership: "+label)
			await disconnect_case()
	guest.free();studio.free();await settle();print("RESIDENT ACTIVITY COOPERATIVE SETTINGS: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
