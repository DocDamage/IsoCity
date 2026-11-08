extends "res://tools/test_resident_activity_routines.gd"
const Floors=preload("res://scripts/builder/floor_plan.gd")
var evidence: Array=[]
func decorate_room(_room: Dictionary,_mode: String) -> void:pass
func setup_case(mode: String,kind: String) -> RefCounted:
	studio.switch_mode(mode);var doc: RefCounted=Doc.new();doc.data=Templates.make(mode,"blank");studio.documents[mode]=doc
	var home: Dictionary=doc.add("2d:House_Blue",[-112,48,0] if mode=="2d" else [-7,0,2],"SE",.6);home["uid"]="home";home["citizen_role"]="home"
	var work: Dictionary=doc.add("3d:HanX_School/School_Building",[112,-32,0] if mode=="2d" else [7,0,-2],"0",.25);work["uid"]="work";work["citizen_role"]="work";work["entrance_anchor"]={"point":[0,0,8],"arrival":[0,0,12]};work["business"]={"kind":"service","capacity":1,"open_hour":0,"close_hour":23.9,"duration_scale":2}
	var room: Dictionary=preload("res://scripts/builder/interiors.gd").make(mode,"Interruption entrance");room["objects"]=[];var upper: Dictionary=room.duplicate(true);var furnishings: RefCounted=Doc.new();furnishings.data=upper
	for x in [-3,3]:furnishings.add("3d:HanX_School/Student_Chair",[(x+2)*16,-64,0] if mode=="2d" else [x,.12,-6],"0")
	room["floors"]=[{"uid":"upper","name":"Classroom","height":3,"room":upper}];room["floor_links"]=[{"uid":"link","kind":kind,"lower":"ground","upper":"upper","start":[0,2] if kind=="stairs" else [0,0],"end":[0,-4] if kind=="stairs" else [0,0],"width":1.6}];decorate_room(room,mode);work["interior"]=room
	doc.data["citizens"]={"enabled":true,"interior_activities":true,"population":2,"seed":42,"day_length":3600,"start_hour":9};doc.data["economy"]={"enabled":true,"starting_cash":100000};doc.data["economy_account"]=preload("res://scripts/builder/economy_plan.gd").fresh_account(doc.data,studio.library);studio.economy_tools.pauses[mode]=true
	studio.changed();await settle();studio.citizen_tools.tick(1);studio.business_tools.tick(1);citizens=studio.citizen_tools.managers[mode];business=studio.business_tools.managers[mode];citizens.set_physics_process(false);business.set_physics_process(false)
	var world: Node=studio.worlds[mode];var approach: Variant=world.exploration.entrance(world.instances["work"])
	for resident in citizens.residents:resident["actor"].teleport_to(approach);citizens.activities.arrive(resident,"work")
	studio.set_walking(true);world.player.set_physics_process(false);world.player.teleport_to(approach);studio.control_settings.execute("interact");await settle();world.player.teleport_to(Vector2(128,0) if mode=="2d" else Vector3(5,.2,4))
	return doc
func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio);await settle()
	for mode in ["2d","3d"]:
		for kind in ["stairs","elevator"]:
			for change in ["floor","room","building","station"]:
				var doc: RefCounted=await setup_case(mode,kind);var world: Node=studio.worlds[mode];var visit: Node=world.exploration;var coordinator: RefCounted=citizens.activities;var ids: Array=citizens.residents.map(func(resident: Dictionary):return resident["actor"].get_instance_id());var ready: bool=false
				for frame in 1800:
					await tick()
					if change in ["station","room"]:ready=coordinator.scheduler.jobs.values().any(func(job: Dictionary):return job["state"]=="service")
					else:ready=coordinator.scheduler.jobs.values().any(func(job: Dictionary):return job.has("stair") and job["stair"]["progress"]>.35 and job["stair"]["progress"]<.65) if kind=="stairs" else visit.interior.floor_stack.lifts["link"].npc_token!=0 and visit.interior.floor_stack.lifts["link"].phase=="moving"
					if ready:break
				var label: String=mode+" "+kind+" "+change;check(ready and visit.interior!=null,"Fixture reaches the actual occupied state before structural edit: "+label)
				if not ready:citizens.clear();visit.leave_interior();studio.set_walking(false);continue
				var old_jobs: Array=coordinator.scheduler.jobs.values().map(func(job: Dictionary):return job["id"]);var source: Dictionary=doc.data.duplicate(true);var count: int=doc.undo_history.size();doc.checkpoint()
				match change:
					"floor":doc.object("work")["interior"]=Floors.remove_floor(doc.object("work")["interior"],"upper")["data"]
					"room":doc.object("work").erase("interior")
					"building":doc.data["objects"].assign(doc.data["objects"].filter(func(item: Dictionary):return item["uid"]!="work"))
					"station":doc.object("work")["interior"]["floors"][0]["room"]["objects"].clear()
				studio.changed();await settle();studio.citizen_tools.tick(1);studio.business_tools.tick(1)
				for frame in 20:await tick()
				var edited: Dictionary=doc.data.duplicate(true);var outcomes: Array=coordinator.history.duplicate(true)
				check(visit.interior==null,"Structural edit retires the outdated visited room before further walking: "+label)
				check(citizens.residents.map(func(resident: Dictionary):return resident["actor"].get_instance_id())==ids and citizens.residents.all(func(resident: Dictionary):return resident["actor"].get_parent()==citizens.container),"Both original residents detach safely into the current city: "+label)
				check(outcomes.size()==2 and outcomes.all(func(result: Dictionary):return result["state"]=="cancelled") and coordinator.view.attached.is_empty() and coordinator.scheduler.reservations.entries.is_empty(),"Affected jobs cancel explicitly and release station/transport ownership: "+label+" "+str(outcomes))
				check(doc.undo_history.size()==count+1 and doc.data["economy_account"]["cash"]==100000,"Only the explicit structural edit adds history; transient cleanup changes no treasury: "+label)
				studio._command("undo",null);await settle();studio.citizen_tools.tick(1);studio.business_tools.tick(1)
				check(doc.data==source,"Actual Undo restores exact authored room/floor/station identities and account: "+label)
				check(coordinator.scheduler.jobs.values().all(func(job: Dictionary):return job["id"] not in old_jobs),"Undo never resurrects interrupted transient jobs or reservations: "+label)
				studio._command("redo",null);await settle();check(doc.data==edited,"Actual Redo restores the exact structural edit without another charge: "+label)
				evidence.append({"mode":mode,"kind":kind,"change":change,"outcomes":outcomes});citizens.clear();visit.leave_interior();studio.set_walking(false);await settle()
	FileAccess.open("res://output/verification/asset_expansion/I14/interruption_facts.json",FileAccess.WRITE).store_string(JSON.stringify(evidence,"\t"));studio.free();await settle();print("RESIDENT ACTIVITY INTERRUPTIONS: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
