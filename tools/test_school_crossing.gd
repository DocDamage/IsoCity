extends "res://tools/test_traffic_controls.gd"

const School=preload("res://scripts/builder/school_plan.gd")
const Entrance=preload("res://scripts/builder/entrance_anchors.gd")

func crossing_school(mode: String) -> void:
	studio.switch_mode(mode)
	var doc:=Doc.new()
	doc.data=fixture(mode)
	studio.documents[mode]=doc
	var center: Vector2=Plan.center(Vector2i.ZERO,mode)
	var home: Dictionary=doc.add("2d:House_Blue",Plan.world(center+Vector2(0,-11),mode),"SE",.35)
	home["uid"]="home"
	home["citizen_role"]="home"
	var site: Dictionary=doc.add("3d:HanX_School/School_Building",Plan.world(center+Vector2(0,11),mode),"180",.20)
	site["uid"]="school"
	site["entrance_anchor"]={"point":[0,0,8],"arrival":[0,0,24]}
	site["school"]={"enabled":true,"capacity":1}
	doc.data["citizens"]={"enabled":true,"population":1,"start_hour":9,"day_length":3600}
	studio.changed()
	await settle()
	var world: Node=studio.worlds[mode]
	for pair in [[home,Vector2(0,-7)],[site,Vector2(0,7)]]:
		var item: Dictionary=pair[0]
		var raw: Variant=Entrance.position_for(world.instances[item["uid"]],item,mode,studio.library)
		var current: Vector2=Plan.metric([raw.x,raw.y,0] if mode=="2d" else [raw.x,raw.y,raw.z],mode)
		item["position"]=Plan.world(Plan.metric(item["position"],mode)+center+pair[1]-current,mode)
	studio.changed()
	await settle()
	var traffic: Node=studio.traffic_tools.managers[mode]
	var manager: Node=studio.citizen_tools.managers[mode]
	traffic.set_physics_process(false)
	manager.set_physics_process(false)
	check(traffic.plan.get("controls",{}).get("active",{}).size()==2 and manager.schools.enrolled.size()==1,"The real school crossing controls compile with moving cars disabled: "+mode)
	if not traffic.gates.phase_start.has("0,0") or manager.residents.is_empty(): return
	var pupil: Dictionary=manager.residents[0]
	var epoch: float=traffic.gates.phase_start["0,0"]
	traffic.junction_time=epoch+2.2
	var waited: bool=false
	for frame in 1800:
		await physics_frame
		manager.step(1.0/60)
		if pupil["waiting"]=="Waiting for the pedestrian signal":
			waited=true
			break
	check(waited,"The pupil reaches and waits at the actual crossing on red: "+mode+" "+str(pupil["status"]))
	if not waited: return
	var stop: Vector2=manager.point(pupil["actor"])
	var hours: float=manager.hour
	manager.active=false
	manager.step(.25)
	check(manager.point(pupil["actor"])==stop and manager.hour==hours,"A hidden school world does no walking or attendance work: "+mode)
	manager.active=true
	for frame in 60:
		await physics_frame
		manager.step(1.0/60)
	check(manager.point(pupil["actor"]).distance_to(stop)<.01 and manager.schools.attendance.is_empty(),"A blocked school crossing leaves the pupil at the stop without lesson credit: "+mode)
	traffic.junction_time=epoch+16.2
	var reached: bool=false
	for frame in 3000:
		await physics_frame
		manager.step(1.0/60)
		var job: Dictionary=manager.activities.scheduler.jobs.get(pupil["id"],{})
		if job.get("state","")=="service":
			reached=true
			break
	check(reached,"A pedestrian phase lets the same pupil walk to a real desk: "+mode+" "+str(pupil["status"]))

func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled=false
	root.add_child(studio)
	await settle()
	if studio.consumer_shell: studio.consumer_shell.dismiss_welcome()
	for mode in ["2d","3d"]: await crossing_school(mode)
	studio.free()
	await settle()
	print("SCHOOL CROSSING: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
