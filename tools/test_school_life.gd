extends SceneTree

const School=preload("res://scripts/builder/school_plan.gd")
const Templates=preload("res://scripts/builder/templates.gd")
const Doc=preload("res://scripts/builder/document.gd")
const Repair=preload("res://scripts/builder/project_repair.gd")
const Economy=preload("res://scripts/builder/economy_plan.gd")
const Transit=preload("res://scripts/builder/transit_plan.gd")
var studio: Control
var count: int=0
var failures: int=0
var output: String="res://output/school_fixture"

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool,description: String) -> void:
	count+=1
	if not ok:
		failures+=1
		print("FAIL: "+description)

func settle() -> void:
	for frame in 10: await process_frame
	await physics_frame

func plan_checks() -> void:
	var item: Dictionary={"asset":"3d:HanX_School/School_Building"}
	check(School.eligible(item) and not School.enabled(item),"An existing school exterior has no enabled schedule by default.")
	var cfg: Dictionary=School.settings(item)
	check(School.valid(cfg) and School.lesson_minutes(cfg)==375.0,"Default bells provide five defined transitions and two lesson blocks.")
	check(not School.valid({"arrival":NAN}) and not School.valid({"capacity":33}) and not School.valid({"lesson":7.5}),"Invalid numeric inputs and overlapping bells are rejected.")
	check(not School.valid({"bus_line":"bus"}) and not School.valid({"bus_line":"bus","home_stop":"a","school_stop":"a"}),"A ride requires a line and two distinct stops.")
	check(School.phase(cfg,7.49)=="before" and School.phase(cfg,7.5)=="arrival" and School.phase(cfg,8.25)=="morning" and School.phase(cfg,11.0)=="break" and School.phase(cfg,11.5)=="afternoon" and School.phase(cfg,15.0)=="dismissed","Bells use explicit inclusive phase boundaries.")
	cfg["closed"]=true
	check(School.phase(cfg,10)=="closed","A holiday overrides normal classes.")
	var pupils: Array[Dictionary]=[{"id":"a","home":"home"},{"id":"b","home":"home"}]
	var sites: Dictionary={"east":{"config":{"capacity":1},"point":Vector2(2,0)},"west":{"config":{"capacity":1},"point":Vector2(-2,0)}}
	var enrolled: Dictionary=School.enroll(pupils,sites,{"home":{"point":Vector2.ZERO}})
	check(enrolled=={"a":"east","b":"west"},"Enrollment is deterministic and bounded by each site's enrollment capacity.")

func stress_classrooms() -> void:
	var activity=preload("res://scripts/builder/resident_activity_plan.gd")
	var Scheduler=preload("res://scripts/builder/resident_activities.gd")
	var school: Dictionary={"asset":"3d:HanX_School/School_Building"}
	var room: Dictionary=activity.for_building(school,"3d",studio.library)
	var compiled: Dictionary={}
	for site in 16: compiled["school_"+str(site)]=room
	var scheduler: RefCounted=Scheduler.new()
	scheduler.configure(compiled)
	var entry: Vector3=room["floors"]["ground"]["exit"]
	var allowed: Array=School.definitions()["seats"]
	for pupil in 128:
		scheduler.request("pupil_"+str(pupil),"school_"+str(pupil%16),"ground",entry,"",allowed,true)
	var samples: Array[int]=[]
	for tick in 360:
		var started: int=Time.get_ticks_usec()
		scheduler.step(1.0/60)
		if tick>=240: samples.append(Time.get_ticks_usec()-started)
	var seated_count: int=scheduler.jobs.values().filter(func(job: Dictionary)->bool:return job["state"]=="service").size()
	var waiting: int=scheduler.jobs.values().filter(func(job: Dictionary)->bool:return job["state"]=="queued").size()
	samples.sort()
	print("SCHOOL SCHEDULER: %d pupils seated, %d queued across 16 rooms, median %d us, p95 %d us"%[
		seated_count,waiting,samples[samples.size()/2],samples[floori(samples.size()*.95)]])
	check(seated_count==64 and waiting==64 and scheduler.reservations.entries.size()==64 and scheduler.class_routes.size()==64,"The maximum pupil population shares exactly four desks per room across sixteen schools.")
	scheduler.reset()
	check(scheduler.reservations.entries.is_empty() and scheduler.class_routes.is_empty(),"Reset releases all stress-fixture reservations and cached routes.")

func step_until(manager: Node,test: Callable,frames: int) -> bool:
	for frame in frames:
		if test.call(): return true
		await physics_frame
		manager.step(1.0/60)
	return test.call()

func seated(manager: Node) -> int:
	return manager.activities.scheduler.jobs.values().filter(func(job: Dictionary)->bool:return job.get("hold_station",false) and job["state"]=="service").size() if manager.activities else 0

func states(manager: Node) -> Array:
	return manager.residents.map(func(resident: Dictionary)->Array:return [resident["target"],resident["status"],str(resident["actor"].position) if is_instance_valid(resident["actor"]) else "missing"])

func capture_settings(mode: String,controls: RefCounted) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	var line: LineEdit=controls.bells["lesson"].get_line_edit()
	for size in [Vector2i(1480,900),Vector2i(960,640)]:
		line.release_focus()
		root.size=size
		studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true} if size.x==960 else {})
		if size.x==960: studio.workspace_layout.library_toggle.button_pressed=false
		await settle()
		line.grab_focus()
		await settle()
		var focus: Rect2=line.get_global_rect()
		check(line.has_focus() and Rect2(Vector2.ZERO,Vector2(size)).encloses(focus) and controls.panel.get_global_rect().encloses(focus),"The first lesson field is reachable and visible by keyboard: "+mode+" "+str([size,line.has_focus(),focus,controls.panel.get_global_rect()]))
		RenderingServer.force_draw(false)
		RenderingServer.force_draw(false)
		check(root.get_texture().get_image().save_png(output+"/settings_%s_%d.png"%[mode,size.x])==OK,"Captured the school settings panel.")
	line.release_focus()
	root.size=Vector2i(1480,900)
	studio.accessibility_settings.restore({})
	await settle()

func capture_room(mode: String,manager: Node,world: Node) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or not world.exploration.interior: return
	var center:=Vector3.ZERO
	var bodies: Array=manager.activities.scheduler.jobs.values().filter(func(job: Dictionary)->bool:return job["state"]=="service")
	if bodies.is_empty(): return
	for job in bodies: center+=job["position"]/bodies.size()
	var camera: Node=world.camera
	var position: Variant=camera.position
	var zoom: Vector2=camera.zoom if mode=="2d" else Vector2.ONE
	var target: Vector3=world.target if mode=="3d" else Vector3.ZERO
	var distance: float=world.distance if mode=="3d" else 0.0
	var walking: bool=world.walking if mode=="3d" else false
	studio.set_process(false)
	for size in [Vector2i(1480,900),Vector2i(960,640)]:
		root.size=size
		studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true} if size.x==960 else {})
		if mode=="2d":
			camera.position=Vector2(center.x,center.y)
			camera.zoom=Vector2.ONE*(3 if size.x==1480 else 2)
		else:
			world.walking=false
			world.target=Vector3(center.x,.7,center.z)
			world.distance=10
			world.update_camera()
		await settle()
		RenderingServer.force_draw(false)
		RenderingServer.force_draw(false)
		check(root.get_texture().get_image().save_png(output+"/class_%s_%d.png"%[mode,size.x])==OK,"Captured the occupied classroom.")
	root.size=Vector2i(1480,900)
	studio.accessibility_settings.restore({})
	if mode=="2d":
		camera.position=position
		camera.zoom=zoom
	else:
		world.target=target
		world.distance=distance
		world.walking=walking
		world.update_camera()
	studio.set_process(true)
	await settle()

func workflow(mode: String) -> void:
	studio.switch_mode(mode)
	var doc:=Doc.new()
	doc.data=Templates.make(mode,"blank")
	studio.documents[mode]=doc
	var house: Dictionary=doc.add("2d:House_Blue",[-112,48,0] if mode=="2d" else [-7,0,2],"SE",.6)
	house["citizen_role"]="home"
	var building: Dictionary=doc.add("3d:HanX_School/School_Building",[112,-32,0] if mode=="2d" else [7,0,-2],"0",.25)
	building["entrance_anchor"]={"point":[0,0,8],"arrival":[0,0,12]}
	var playground: Dictionary=doc.add("2d:Playground_Slide" if mode=="2d" else "3d:HanX_School/Tile_Hopscotch",
		[-48,30,0] if mode=="2d" else [3,0,-5],"SE" if mode=="2d" else "0",.6 if mode=="2d" else 1.0)
	doc.data["citizens"]={"enabled":true,"population":5,"seed":42,"day_length":1600,"start_hour":8.2}
	doc.data["economy"]={"enabled":true,"starting_cash":100000}
	doc.data["economy_account"]=Economy.fresh_account(doc.data,studio.library)
	studio.economy_tools.pauses[mode]=true
	studio.changed()
	await settle()
	var manager: Node=studio.citizen_tools.managers[mode]
	manager.set_physics_process(false)
	studio.selected_uid=building["uid"]
	studio.selected_uids.assign([building["uid"]])
	studio._command("schools",null)
	var controls: RefCounted=studio.school_tools
	var before: Dictionary=doc.data.duplicate(true)
	controls.enabled.button_pressed=true
	controls.capacity.value=5
	controls.yard.select(1)
	controls.save()
	await settle()
	check(doc.object(building["uid"]).get("school",{}).get("playground","")==playground["uid"] and Doc.valid(doc.data,mode,studio.library),"The actual school inspector saves a valid opt-in and linked playground: "+mode)
	var accepted: Dictionary=doc.data.duplicate(true)
	studio._command("undo",null)
	await settle()
	check(doc.data==before and manager.schools.sites.is_empty(),"One Undo removes the school simulation and restores the exact ledger: "+mode)
	studio._command("redo",null)
	await settle()
	check(doc.data==accepted and manager.schools.enrolled.size()==5,"Redo restores the schedule and enrolls five existing residents: "+mode)
	if manager.activities==null or manager.schools.enrolled.size()!=5: return
	building=doc.object(building["uid"])
	var ids: Array=manager.residents.map(func(resident: Dictionary)->int:return resident["actor"].get_instance_id() if is_instance_valid(resident["actor"]) else 0)
	var seated_enough: bool=await step_until(manager,func()->bool:return seated(manager)>=2 and manager.activities.scheduler.jobs.size()==5,3600)
	check(seated_enough,"Pupils physically reach the school and use furnished desks: "+mode+" "+str(states(manager)))
	if not seated_enough: return
	var assigned: Array=manager.activities.scheduler.jobs.values()
	check(assigned.any(func(job: Dictionary)->bool:return job["state"]=="queued") and assigned.filter(func(job: Dictionary)->bool:return job["station_token"]>0).size()<=4,"The fifth pupil waits for a free shared desk: "+mode)
	var attendance: Dictionary=manager.schools.attendance.duplicate()
	await step_until(manager,func()->bool:return manager.schools.attendance!=attendance,45)
	check(not manager.schools.attendance.is_empty(),"Physical time spent at a study station earns attendance: "+mode)
	if "--capture" in OS.get_cmdline_user_args():
		studio.selected_uid=building["uid"]
		studio.selected_uids.assign([building["uid"]])
		studio._command("schools",null)
		await settle()
		check(controls.enabled.button_pressed and controls.bells["lesson"].get_line_edit().text=="8.25","The selected school displays the exact stored first bell: "+mode)
		await capture_settings(mode,controls)
	var world: Node=studio.worlds[mode]
	var visit: Node=world.exploration
	studio.set_walking(true)
	world.player.set_physics_process(false)
	world.player.teleport_to(visit.entrance(world.instances[building["uid"]]))
	studio.control_settings.execute("interact")
	await settle()
	check(visit.interior!=null and visit.interior_uid==building["uid"] and manager.activities.view.attached.size()>=2,"Visiting during class renders the same pupils in the actual furnished room: "+mode)
	check(manager.residents.map(func(resident: Dictionary)->int:return resident["actor"].get_instance_id())==ids,"Classroom entry retains all original actor identities: "+mode)
	await capture_room(mode,manager,world)
	if visit.interior: visit.leave_interior()
	studio.set_walking(false)
	await settle()
	check(manager.activities.view.attached.is_empty() and seated(manager)>=2,"Leaving the classroom keeps its class and reservations active: "+mode)
	var current: Dictionary=doc.data.duplicate(true)
	var path: String=output+"/school_"+mode+".isocity.json"
	check(studio.write_project(path,false),"The normal save path writes authored school settings: "+mode)
	var repair:=Repair.new(studio.library)
	var reopened: Dictionary=repair.read(path)
	var reopened_school: Array=reopened.get("content",{}).get("documents",{}).get(mode,{}).get("objects",[]).filter(func(item: Dictionary)->bool:return item["uid"]==building["uid"])
	check(reopened["ok"] and reopened_school.size()==1 and JSON.stringify(reopened_school[0]["school"])==JSON.stringify(JSON.parse_string(JSON.stringify(building["school"]))) and not reopened_school[0].has("attendance"),"Reopening preserves school metadata and excludes attendance and live jobs: "+mode+" "+str(repair.issues))
	var observed: Dictionary=manager.schools.attendance.duplicate()
	manager.hour=11.0
	manager.step(1.0/60)
	check(manager.schools.attendance==observed,"Jumping to break grants no time skipped in class: "+mode)
	var outside: bool=false
	for frame in 4800:
		if frame%480==0 and "--trace" in OS.get_cmdline_user_args():
			var one: Dictionary=manager.residents[0]
			var start: Vector2=manager.point(one["actor"])
			var goal: Vector2=manager.plan["lookup"][playground["uid"]]["point"]+one["spacing"]
			print("SCHOOL BREAK ",mode," ",manager.hour," ",start," ",goal," ",manager.route(start,goal)," ",states(manager))
		if manager.activities.scheduler.jobs.is_empty() and manager.residents.any(func(pupil: Dictionary)->bool:return pupil["target"]==playground["uid"] and pupil["status"]=="At the school playground."):
			outside=true
			break
		await physics_frame
		manager.step(1.0/60)
	check(outside and manager.activities.scheduler.reservations.entries.is_empty(),"Break releases classroom claims and changes a real walking destination to the playground: "+mode+" "+str(states(manager)))
	manager.hour=11.5
	var resumed: bool=await step_until(manager,func()->bool:return seated(manager)>=2,3600)
	check(resumed,"The afternoon bell brings the pupils back to study: "+mode+" "+str(states(manager)))
	manager.hour=15.0
	var dismissed: bool=await step_until(manager,func()->bool:
		return manager.activities.scheduler.jobs.is_empty() and manager.residents.all(func(pupil: Dictionary)->bool:return pupil["target"]==house["uid"])
	,4800)
	check(dismissed and manager.activities.scheduler.reservations.entries.is_empty(),"Dismissal sends pupils home and leaves no station claims: "+mode)
	check(doc.data==current and doc.data["economy_account"]["cash"]==100000,"The school day leaves the authored city and treasury untouched: "+mode)
	studio.selected_uid=building["uid"]
	studio.selected_uids.assign([building["uid"]])
	studio._command("schools",null)
	controls.closed.button_pressed=true
	controls.save()
	await settle()
	manager.hour=9
	var holiday: bool=await step_until(manager,func()->bool:return manager.residents.all(func(pupil: Dictionary)->bool:return pupil["target"]==house["uid"]),600)
	check(holiday and manager.schools.attendance.is_empty() and manager.activities.scheduler.jobs.is_empty(),"The holiday keeps pupils at home and starts no classroom claims: "+mode)
	studio._command("undo",null)
	await settle()
	manager.hour=9
	var reopened_class: bool=await step_until(manager,func()->bool:return seated(manager)>=2,3600)
	check(reopened_class,"Undo the holiday and pupils can resume the normal class: "+mode)
	if not reopened_class: return
	doc.checkpoint()
	var room: Dictionary=doc.object(building["uid"])["interior"]
	room["objects"]=room["objects"].filter(func(piece: Dictionary)->bool:return not piece["asset"] in School.definitions()["seats"])
	studio.changed()
	doc.finish_checkpoint()
	await settle()
	var unavailable: bool=await step_until(manager,func()->bool:return manager.activities.scheduler.reservations.entries.is_empty() and manager.residents.any(func(pupil: Dictionary)->bool:return pupil["status"].contains("no usable student desks")),3600)
	check(unavailable and manager.activities.scheduler.jobs.is_empty(),"Removing the actual desks cancels the old itinerary and releases every claim: "+mode)
	studio._command("undo",null)
	await settle()
	check(doc.data==current,"Undo restores the same furnished classroom and authored schedule: "+mode)
	studio.selected_uid=building["uid"]
	studio.selected_uids.assign([building["uid"],playground["uid"]])
	studio.duplicate_selection()
	doc.finish_checkpoint()
	await settle()
	var clone: Dictionary=doc.object(studio.selected_uids[0])
	var copied_yard: Dictionary=doc.object(studio.selected_uids[1])
	var config: Dictionary=School.settings(clone)
	check(clone["uid"]!=building["uid"] and not config["enabled"] and config["lesson"]==8.25 and config["playground"]==copied_yard["uid"],"Duplicating the campus preserves bells and remaps its copied playground while the new school starts disabled: "+mode)
	var original_desks: Array=doc.object(building["uid"])["interior"]["objects"].map(func(piece: Dictionary)->String:return piece["uid"])
	check(clone["interior"]["objects"].all(func(piece: Dictionary)->bool:return not piece["uid"] in original_desks) and Doc.valid(doc.data,mode,studio.library),"The duplicate owns an independent valid furnished classroom: "+mode)
	studio._command("undo",null)
	await settle()
	check(doc.data==current,"Undo restores the exact authored city and treasury after duplicating the campus: "+mode)
	var id: String=building["asset"]
	var original_asset: Dictionary=studio.library.assets[id]
	studio.library.assets.erase(id)
	var recover:=Repair.new(studio.library)
	var repaired: Dictionary=recover.world(current,mode,"school_source",0)
	studio.library.assets[id]=original_asset
	var placeholder: Dictionary=repaired["objects"].filter(func(item: Dictionary)->bool:return item["uid"]==building["uid"])[0]
	check(placeholder.has("missing_asset") and not placeholder.has("school") and placeholder["missing_asset"]["record"]["school"]==doc.object(building["uid"])["school"] and Doc.valid(repaired,mode,studio.library),"Repair archives a missing school's exact timetable and preserves a valid placeholder: "+mode)

func run() -> void:
	if OS.has_environment("ISOCITY_SCHOOL_OUTPUT"): output=OS.get_environment("ISOCITY_SCHOOL_OUTPUT")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	plan_checks()
	studio=load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled=false
	root.add_child(studio)
	await settle()
	if studio.consumer_shell: studio.consumer_shell.dismiss_welcome()
	if "--stress" in OS.get_cmdline_user_args(): stress_classrooms()
	for mode in ["2d","3d"]: await workflow(mode)
	studio.free()
	await settle()
	print("SCHOOL LIFE: %d checks, %d failures"%[count,failures])
	quit(1 if failures else 0)
