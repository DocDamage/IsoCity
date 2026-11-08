extends "res://tools/test_school_life.gd"

const Traffic=preload("res://scripts/builder/traffic_plan.gd")
var guest: Control

func synced() -> bool:
	var a: RefCounted=studio.cooperative_tools
	var b: RefCounted=guest.cooperative_tools
	return a.participating and b.participating and not a.dirty and not b.dirty and b.session.pending.is_empty() and a.session.data==b.session.data and a.snapshot()==b.snapshot()

func wait_for(test: Callable) -> bool:
	for frame in 900:
		if test.call(): return true
		await process_frame
	return false

func apply_school(uid: String) -> void:
	guest.selected_uid=uid
	guest.selected_uids.assign([uid])
	guest._command("schools",null)
	guest.school_tools.enabled.button_pressed=true
	guest.school_tools.yard.select(1)
	guest.school_tools.save()

func share(mode: String) -> void:
	for editor in [studio,guest]:
		editor.switch_mode(mode)
		editor.economy_tools.pauses[mode]=true
	var doc:=Doc.new()
	doc.data=Templates.make(mode,"blank")
	var house: Dictionary=doc.add("2d:House_Blue",[-112,48,0] if mode=="2d" else [-7,0,2],"SE",.6)
	house["citizen_role"]="home"
	var school: Dictionary=doc.add("3d:HanX_School/School_Building",[112,-32,0] if mode=="2d" else [7,0,-2],"0",.25)
	school["entrance_anchor"]={"point":[0,0,8],"arrival":[0,0,12]}
	var yard: Dictionary=doc.add("2d:Playground_Slide" if mode=="2d" else "3d:HanX_School/Tile_Hopscotch",
		[-48,30,0] if mode=="2d" else [3,0,-5],"SE" if mode=="2d" else "0",.6 if mode=="2d" else 1.0)
	var point: Vector2=Traffic.metric(yard["position"],mode)
	doc.data["protected_areas"]=[{"uid":"yard","name":"Protected playground","owner":"host","rect":[point.x-1,point.y-1,2,2]}]
	doc.data["citizens"]={"enabled":true,"population":2,"day_length":3600,"start_hour":9.0}
	doc.data["economy"]={"enabled":true,"starting_cash":100000}
	doc.data["economy_account"]=Economy.fresh_account(doc.data,studio.library)
	studio.documents[mode]=doc
	studio.changed()
	await settle()
	var a: RefCounted=studio.cooperative_tools
	var b: RefCounted=guest.cooperative_tools
	a.name_field.text="School host"
	a.password.text="school-fixture"
	a.port.value=0
	a.host_game()
	check(a.session.server!=null,"The local school host starts: "+mode)
	if a.session.server==null: return
	b.name_field.text="School guest"
	b.password.text="school-fixture"
	b.address.text="127.0.0.1"
	b.port.value=a.session.server.get_local_port()
	b.join_game()
	check(await wait_for(synced),"Both peers converge on the same school city: "+mode)
	await settle()
	var original: Dictionary=a.session.data.duplicate(true)
	apply_school(school["uid"])
	check(await wait_for(func()->bool:return synced() and b.session.notice.contains("Protected area")) and a.session.data==original,"A guest cannot assign a protected playground from an unprotected school: "+mode+" "+b.session.notice)
	a.selected="yard"
	a.remove_area()
	check(await wait_for(func()->bool:return synced() and studio.current().data.get("protected_areas",[]).is_empty()),"The host can open the playground for editing: "+mode)
	var before: Dictionary=a.session.data.duplicate(true)
	apply_school(school["uid"])
	check(await wait_for(func()->bool:return synced() and studio.current().object(school["uid"]).has("school")),"School settings converge after the guest uses the real inspector: "+mode+" "+b.session.notice)
	var accepted: Dictionary=a.session.data.duplicate(true)
	check(accepted[mode]["economy_account"]==before[mode]["economy_account"],"Changing the schedule creates no construction charge or receipt: "+mode)
	var manager: Node=studio.citizen_tools.managers[mode]
	manager.set_physics_process(false)
	var in_class: bool=await step_until(manager,func()->bool:return seated(manager)>=1,3600)
	check(in_class and synced() and a.session.data==accepted,"Physical attendance and desk reservations stay private to each peer: "+mode+" "+str(states(manager)))
	guest._command("undo",null)
	check(await wait_for(func()->bool:return synced() and a.session.data==before),"Shared Undo restores exact school settings, objects and treasury: "+mode)
	await settle()
	check(manager.activities==null and manager.schools.attendance.is_empty(),"Shared Undo releases the live school and its local occupancy: "+mode)
	guest._command("redo",null)
	check(await wait_for(func()->bool:return synced() and a.session.data==accepted),"Shared Redo restores only the authored opt-in and timetable: "+mode)
	b.leave()
	a.leave()
	await settle()

func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate()
	guest=load("res://scenes/builder.tscn").instantiate()
	for editor in [studio,guest]:
		editor.storage_enabled=false
		root.add_child(editor)
	await settle()
	for editor in [studio,guest]:
		if editor.consumer_shell: editor.consumer_shell.dismiss_welcome()
	for mode in ["2d","3d"]: await share(mode)
	guest.free()
	studio.free()
	await settle()
	print("SCHOOL COOPERATIVE: %d checks, %d failures"%[count,failures])
	quit(1 if failures else 0)
