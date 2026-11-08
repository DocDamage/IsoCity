extends "res://tools/test_resident_activity_interruptions.gd"
var facts: Dictionary={}
const CitizenPlan=preload("res://scripts/builder/citizen_plan.gd")
func same_json(a: Dictionary,b: Dictionary) -> bool:return JSON.parse_string(JSON.stringify(a))==JSON.parse_string(JSON.stringify(b))
func apply_button() -> Button:
	return studio.citizen_tools.panel.find_children("*","Button",true,false).filter(func(node: Button):return node.text=="Apply simulation settings")[0]
func refresh_managers() -> void:
	await settle();studio.citizen_tools.tick(1);studio.business_tools.tick(1);citizens=studio.citizen_tools.managers[studio.mode];business=studio.business_tools.managers[studio.mode];citizens.set_physics_process(false);business.set_physics_process(false)
func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio);await settle()
	if studio.consumer_shell:studio.consumer_shell.dismiss_welcome()
	check(not CitizenPlan.settings({})["interior_activities"] and not studio.citizen_tools.interior_activities.button_pressed,"Fresh cities expose the interior activity control with the disabled default")
	check(studio.citizen_tools.interior_activities.accessibility_name=="Resident interior activities" and studio.citizen_tools.panel.follow_focus,"The new control has an explicit accessible name in a focus-following scroll panel")
	check(preload("res://scripts/builder/command_palette.gd").ACTIONS.any(func(entry: Array):return entry[1]=="resident_activities") and preload("res://scripts/builder/control_settings.gd").SPECS.any(func(entry: Array):return entry[0]=="resident_activities"),"Interior settings have a searchable, rebindable command")
	for mode in ["2d","3d"]:
		var doc: RefCounted=await setup_case(mode,"elevator");doc.data["citizens"]["extension"]={"retained":42};studio.changed();await refresh_managers()
		var tools: RefCounted=studio.citizen_tools;var old: RefCounted=citizens.activities;var ids: Array=citizens.residents.map(func(resident: Dictionary):return resident["actor"].get_instance_id());var source: Dictionary=doc.data.duplicate(true);var count: int=doc.undo_history.size();facts[mode]={"source":source,"history_before":count}
		check(studio.control_settings.assign("resident_activities",0,preload("res://scripts/builder/control_settings.gd").CTRL|preload("res://scripts/builder/control_settings.gd").ALT|KEY_I).is_empty(),"The new settings command accepts an explicit nonconflicting user binding: "+mode)
		studio.get_viewport().gui_release_focus()
		var event:=InputEventKey.new();event.keycode=KEY_I;event.physical_keycode=KEY_I;event.ctrl_pressed=true;event.alt_pressed=true;event.pressed=true;Input.parse_input_event(event);event=event.duplicate();event.pressed=false;Input.parse_input_event(event);await settle();tools.tick(1)
		check(tools.panel.is_visible_in_tree() and tools.interior_activities.has_focus() and tools.interior_activities.button_pressed,"The actual command opens and focuses the saved interior setting in the current shell: "+mode)
		check(doc.data==source and doc.undo_history.size()==count and not studio.walking,"Opening settings returns to Build without changing authored data or history: "+mode)
		tools.residents.select(0);tools.residents.item_selected.emit(0)
		check(tools.activity_status.text.contains("indoors") and tools.resident_detail.text.contains("Resident 1") and not tools.residents.get_item_text(0).begins_with("resident_"),"Diagnostics expose activity counts and a readable selected resident rather than internal identifiers: "+mode)
		var children: int=studio.worlds[mode].get_child_count();tools.follow()
		check(studio.worlds[mode].get_child_count()==children and not studio.worlds[mode].exploration.interior and studio.status.text.contains("entrance"),"Locating an unrendered resident frames its building without authoring or opening a room: "+mode)
		tools.interior_activities.button_pressed=false
		check(doc.data==source and citizens.activities==old,"Changing a draft control alone does not stop or author simulation: "+mode)
		apply_button().pressed.emit();await refresh_managers()
		var disabled: Dictionary=source.duplicate(true);disabled["citizens"]["interior_activities"]=false;facts[mode]["after_apply"]=doc.data.duplicate(true);facts[mode]["history_after"]=doc.undo_history.size()
		check(doc.data==disabled and doc.undo_history.size()==count+1,"Actual Apply writes only the explicit option and preserves extension data in one history step: "+mode)
		check(citizens.activities==null and old.closed and old.scheduler.jobs.is_empty() and old.scheduler.reservations.entries.is_empty() and citizens.residents.map(func(resident: Dictionary):return resident["actor"].get_instance_id())==ids,"Disabling through the UI releases occupied jobs and retains both original residents: "+mode)
		apply_button().pressed.emit();await refresh_managers();check(doc.data==disabled and doc.undo_history.size()==count+1,"Repeated unchanged Apply creates no content or history: "+mode)
		studio._command("undo",null);await refresh_managers()
		check(doc.data==source and tools.interior_activities.button_pressed and citizens.activities!=null and citizens.activities!=old and citizens.activities.scheduler.jobs.is_empty(),"Actual Undo restores the option and starts fresh transient coordination: "+mode)
		studio._command("redo",null);await refresh_managers();check(doc.data==disabled and citizens.activities==null and not tools.interior_activities.button_pressed,"Actual Redo stops the option again without reviving interrupted jobs: "+mode)
		studio._command("undo",null);await refresh_managers()
		var world: Node=studio.worlds[mode];var approach: Variant=world.exploration.entrance(world.instances["work"])
		for resident in citizens.residents:resident["actor"].teleport_to(approach);citizens.activities.arrive(resident,"work")
		var service: bool=false
		for frame in 1800:
			await tick()
			if citizens.activities.scheduler.jobs.values().any(func(job: Dictionary):return job["state"]=="service"):service=true;break
		check(service,"Save fixture reaches an actual ordinary active service before reopening: "+mode)
		for frame in 1800:
			if not business.service.inventory.is_empty() and citizens.activities.scheduler.jobs.values().any(func(job: Dictionary):return job["state"]=="service"):break
			await tick()
		check(not business.service.inventory.is_empty() and not business.service.history.is_empty(),"Save fixture includes a real completed grant alongside ongoing activity: "+mode)
		var coordinator: RefCounted=citizens.activities;var saved_source: Dictionary=doc.data.duplicate(true);var saved_ids: Array=citizens.residents.map(func(resident: Dictionary):return resident["id"]);var path: String="res://output/verification/asset_expansion/I14/controls_project_"+mode+".json"
		check(studio.write_project(path,false),"Actual project writer saves the enabled option and authored interiors: "+mode)
		var serialized: String=FileAccess.get_file_as_string(path)
		check(not serialized.contains("link_token") and not serialized.contains("station_token") and not serialized.contains("activity_1"),"Project files contain no private itinerary identity, occupancy or reservation state: "+mode)
		check(studio.load_project(path),"Actual project loader reopens the saved city: "+mode);await refresh_managers();doc=studio.current()
		facts[mode]["saved"]=saved_source;facts[mode]["loaded"]=doc.data.duplicate(true);facts[mode]["loaded_hour"]=citizens.hour
		check(same_json(doc.data,saved_source) and tools.interior_activities.button_pressed and citizens.activities!=null and citizens.hour==CitizenPlan.settings(doc.data)["start_hour"],"Reopening retains exact authored data and the explicit option at the saved start hour: "+mode)
		check(coordinator.closed and coordinator.scheduler.reservations.entries.is_empty() and citizens.activities.history.is_empty() and citizens.activities.scheduler.jobs.is_empty() and business.service.visits.is_empty() and business.service.inventory.is_empty() and business.service.history.is_empty() and citizens.residents.map(func(resident: Dictionary):return resident["id"])==saved_ids,"Loading resets private jobs, visits and inventory while retaining deterministic resident identities: "+mode)
		var legacy: RefCounted=Doc.new();legacy.data=Templates.make(mode,"blank");legacy.data["citizens"]={"enabled":false};studio.documents[mode]=legacy;studio.changed();await refresh_managers();var before: Dictionary=legacy.data.duplicate(true);var history: int=legacy.undo_history.size();apply_button().pressed.emit();await refresh_managers()
		check(not tools.interior_activities.button_pressed and legacy.data==before and not legacy.data["citizens"].has("interior_activities") and legacy.undo_history.size()==history,"Legacy cities without the field remain disabled and are not rewritten by an unchanged Apply: "+mode)
		tools.interior_activities.button_pressed=true;apply_button().pressed.emit();await refresh_managers();tools.tick(1)
		check(CitizenPlan.settings(legacy.data)["interior_activities"] and not CitizenPlan.settings(legacy.data)["enabled"] and citizens.activities==null and tools.activity_status.text.contains("Enable citizens"),"Explicit opt-in saves the option without silently enabling the citizen simulation: "+mode)
		tools.enabled.button_pressed=true;apply_button().pressed.emit();await refresh_managers()
		check(CitizenPlan.settings(legacy.data)["enabled"] and citizens.activities!=null and legacy.data["objects"].is_empty(),"Actual UI enable starts optional coordination without authoring a room or furnishing: "+mode)
	FileAccess.open("res://output/verification/asset_expansion/I14/controls_facts.json",FileAccess.WRITE).store_string(JSON.stringify(facts,"\t"))
	studio.free();await settle();print("RESIDENT ACTIVITY CONTROLS: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
