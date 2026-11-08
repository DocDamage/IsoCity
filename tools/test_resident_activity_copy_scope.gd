extends "res://tools/test_resident_activity_interruptions.gd"
var facts: Array=[]
func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio);await settle()
	if studio.consumer_shell:studio.consumer_shell.dismiss_welcome()
	for mode in ["2d","3d"]:
		for kind in ["stairs","elevator"]:
			var doc: RefCounted=await setup_case(mode,kind);var world: Node=studio.worlds[mode];var visit: Node=world.exploration;var coordinator: RefCounted=citizens.activities;var ready: bool=false
			for frame in 1800:
				await tick()
				ready=coordinator.scheduler.jobs.values().any(func(job: Dictionary):return job.has("stair") and job["stair"]["progress"]>.35 and job["stair"]["progress"]<.65) if kind=="stairs" else visit.interior.floor_stack.lifts["link"].npc_token!=0 and visit.interior.floor_stack.lifts["link"].phase=="moving"
				if ready:break
			var label: String=mode+" "+kind;check(ready,"Copy starts during an actual occupied flight: "+label)
			if not ready:citizens.clear();visit.leave_interior();studio.set_walking(false);continue
			var identities: Array=citizens.residents.map(func(resident: Dictionary):return resident["actor"].get_instance_id());var jobs: Array=coordinator.scheduler.jobs.values().map(func(job: Dictionary):return job["id"]);var original: Dictionary=doc.object("work")["interior"].duplicate(true);var source: Dictionary=doc.data.duplicate(true);var history: int=doc.undo_history.size()
			studio.selected_uid="work";studio.selected_uids.assign(["work"]);studio._command("duplicate",null);await settle()
			var copy_uid: String=studio.selected_uid;var copy: Dictionary=doc.object(copy_uid);var copied: Dictionary=doc.data.duplicate(true)
			check(copy_uid!="work" and not copy.is_empty() and doc.object("work")["interior"]==original,"Actual Duplicate creates an independent owned room and preserves the original: "+label)
			check(coordinator.scheduler.jobs.values().map(func(job: Dictionary):return job["id"])==jobs and coordinator.scheduler.jobs.values().all(func(job: Dictionary):return job["building"]=="work"),"Copying keeps private jobs scoped to their original building: "+label)
			var quote: Dictionary=preload("res://scripts/builder/economy_plan.gd").quote(source,copied,studio.library)
			check(doc.undo_history.size()==history+1 and doc.data["economy_account"]["cash"]==source["economy_account"]["cash"]-quote["net"],"Duplicate adds one history step and its ordinary construction quote: "+label)
			studio.interior_tools.start(copy_uid);await settle();var floor_uid: String=copy["interior"]["floors"][0]["uid"];studio.interior_tools.floor_tools.switch_floor(floor_uid);await settle()
			var room_doc: RefCounted=studio.current();room_doc.checkpoint();room_doc.data["objects"][0]["position"][0]+=(16 if mode=="2d" else 1);studio.changed();await settle();studio.interior_tools.flush()
			check(doc.object("work")["interior"]==original and doc.object(copy_uid)["interior"]!=original,"Editing the copied chair preserves the occupied original furnishing: "+label)
			studio.set_walking(true);await settle();world.player.set_physics_process(false)
			check(visit.preview and visit.interior_uid==copy_uid,"Walk previews the actual copied building: "+label)
			check(coordinator.data()==doc.data,"Activity source stays the exterior city while the editor renders a copied floor: "+label)
			check(coordinator.items.has("work") and coordinator.cache.has("work"),"Preview reconciliation retains the original destination and compiled plan: "+label)
			# Source replacement occurs in shared history; a captured old dictionary is insufficient.
			var replacement: Dictionary=doc.data.duplicate(true);doc.data=replacement;coordinator.poll(true)
			check(is_same(coordinator.data(),replacement) and coordinator.items.has("work"),"The city provider follows document replacement during room preview: "+label)
			check(coordinator.scheduler.jobs.values().map(func(job: Dictionary):return job["id"])==jobs and coordinator.history.is_empty(),"Previewing a different building cannot cancel or duplicate original activity: "+label)
			check(coordinator.view.attached.is_empty() and citizens.residents.map(func(resident: Dictionary):return resident["actor"].get_instance_id())==identities,"The copied preview cannot borrow original city bodies: "+label)
			facts.append({"mode":mode,"kind":kind,"original_jobs":jobs,"jobs_after_preview":coordinator.scheduler.jobs.values().map(func(job: Dictionary):return job["id"]),"outcomes":coordinator.history.duplicate(true)})
			studio.set_walking(false);studio.interior_tools.leave();await settle();var edited: Dictionary=doc.data.duplicate(true)
			check(doc.object("work")["interior"]==original,"Leaving copied preview preserves the original authored room: "+label)
			studio._command("undo",null);await settle();check(doc.data==copied,"Actual Undo restores the copied room before its chair edit: "+label)
			studio._command("undo",null);await settle();check(doc.data==source,"Actual Undo removes the copy and restores its exact account: "+label)
			studio._command("redo",null);await settle();studio._command("redo",null);await settle();check(doc.data==edited,"Actual Redo restores copy plus chair edit without transient activity state: "+label)
			citizens.clear();visit.leave_interior();studio.set_walking(false);await settle()
	FileAccess.open("res://output/verification/asset_expansion/I14/copy_scope_facts.json",FileAccess.WRITE).store_string(JSON.stringify(facts,"\t"));studio.free();await settle();print("RESIDENT ACTIVITY COPY SCOPE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
