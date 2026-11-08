extends "res://tools/test_traffic_reroute.gd"

const Common=preload("res://scripts/builder/simulation_diagnostics.gd")
const Sources=preload("res://scripts/builder/simulation_diagnostic_sources.gd")
const Zone=preload("res://scripts/builder/zone_plan.gd")
const Portable=preload("res://scripts/builder/portable_export.gd")
var ui: RefCounted

func document(mode: String,data: Dictionary) -> RefCounted:
	ui.choose("off")
	studio.switch_mode(mode)
	var doc:=Doc.new()
	doc.data=data
	studio.documents[mode]=doc
	studio.selected_uid=""
	studio.selected_uids.clear()
	studio.changed()
	await settle()
	return doc

func street(mode: String) -> Dictionary:
	var data: Dictionary=Templates.make(mode,"blank")
	data["roads"]=[]
	for x in range(-10,11): data["roads"].append({"cell":[x,0]})
	return data

func find(code: String,uid: String="") -> Dictionary:
	for row in ui.snapshot.get("rows",[]):
		if row["code"]==code and (uid.is_empty() or row["object_uid"]==uid): return row
	return {}

func shapes(row: Dictionary,kind: String) -> Array:
	return row.get("details",{}).get("geometry",[]).filter(func(shape: Dictionary)->bool:return shape["kind"]==kind)

func expected(points: PackedVector2Array,mode: String) -> PackedVector3Array:
	var result:=PackedVector3Array()
	for point in points:
		var at: Array=Plan.world(point,mode,.1)
		result.append(Vector3(at[0],at[1],at[2]))
	return result

func palette() -> void:
	studio.command_palette.show()
	studio.command_palette.query.text="simulation diagnostics"
	studio.command_palette.refresh()
	studio.command_palette.execute()
	await settle()

func frame_metric(mode: String,point: Vector2) -> void:
	var at: Array=Plan.world(point,mode)
	var world: Node=studio.worlds[mode]
	if mode=="2d": world.camera.position=Vector2(at[0],at[1])
	else: world.target=Vector3(at[0],0,at[2]); world.update_camera()

func press_key(code: Key) -> void:
	var event:=InputEventKey.new()
	event.keycode=code
	event.physical_keycode=code
	event.pressed=true
	Input.parse_input_event(event)
	await process_frame
	event=event.duplicate()
	event.pressed=false
	Input.parse_input_event(event)
	await settle()

func capture_diagnostics(mode: String,point: Vector2,name: String="traffic") -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	var world: Node=studio.worlds[mode]
	for size in [Vector2i(1480,900),Vector2i(960,640)]:
		ui.selector.release_focus()
		root.size=size
		studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true} if size.x==960 else {})
		if size.x==960: studio.workspace_layout.library_toggle.button_pressed=false
		await settle()
		studio._command("simulation_diagnostics",null)
		await settle()
		var at: Array=Plan.world(point,mode)
		if mode=="2d":
			world.camera.position=Vector2(at[0]+(70 if studio.consumer_shell.active else 0),at[1])
			world.camera.zoom=Vector2.ONE*1.7
		else:
			world.target=Vector3(at[0],.4,at[2])
			world.distance=29
			if studio.consumer_shell.active: world.target+=world.camera.global_basis.x*3.0
			world.update_camera()
		await settle()
		ui.tick(.3)
		check(ui.selector.has_focus() and Rect2(Vector2.ZERO,Vector2(size)).encloses(ui.selector.get_global_rect()) and ui.overlay.visible and (size.x!=960 or ui.overlay.contrast),"Keyboard focus and the verified overlay stay visible: "+mode+" "+str(size))
		RenderingServer.force_draw(false)
		RenderingServer.force_draw(false)
		check(root.get_texture().get_image().save_png(output+"/"+name+"_"+mode+"_"+str(size.x)+".png")==OK,"Captured the actual diagnostic overlay: "+mode+" "+name)
		if size.x==960 and name=="coverage":
			await press_key(KEY_TAB)
			check(ui.results.has_focus(),"Tab reaches the findings list in the compact diagnostics panel: "+mode)
			await press_key(KEY_DOWN)
			await press_key(KEY_TAB)
			var bounds: Rect2=ui.detail.get_global_rect()
			var back: Button=studio.consumer_shell.expert_return
			check(ui.detail.has_focus() and ui.detail.text.contains("road coverage") and Rect2(Vector2.ZERO,Vector2(size)).encloses(bounds)
				and (not back.visible or not back.get_global_rect().intersects(bounds)) and not studio.walking,
				"Keyboard focus reveals the complete current finding at enlarged text: "+mode+" "+str(bounds))
			RenderingServer.force_draw(false)
			RenderingServer.force_draw(false)
			check(root.get_texture().get_image().save_png(output+"/coverage_details_"+mode+"_960.png")==OK,"Captured the keyboard-focused service finding: "+mode)
		ui.selector.release_focus()
		ui.detail.release_focus()
	root.size=Vector2i(1480,900)
	studio.accessibility_settings.restore({})
	await settle()

func traffic_diagnostics(mode: String) -> void:
	var doc: RefCounted=await document(mode,fixture(mode))
	var before: Dictionary=doc.data.duplicate(true)
	var runtime: Node=studio.traffic_tools.managers[mode]
	runtime.set_physics_process(false)
	await palette()
	check(ui.kind=="off" and not ui.overlay.visible and ui.panel.is_visible_in_tree() and ui.selector.has_focus(),"The actual command opens a read-only selector with overlays disabled initially: "+mode)
	ui.choose("traffic")
	ui.tick(.3)
	if runtime.vehicles.is_empty(): check(false,"The actual traffic runtime spawned its vehicle: "+mode); return
	var car: Dictionary=runtime.vehicles[0]
	var row: Dictionary=find("traffic_lane",car["id"])
	var lines: Array=shapes(row,"lane")
	check(lines.size()==1 and lines[0]["points"]==expected(car["path"],mode) and row.keys().size()==8,"Only the current runtime lane provides geometry in the common diagnostic record: "+mode)
	check(ui.overlay.mouse_filter==Control.MOUSE_FILTER_IGNORE and before==doc.data and doc.undo_history.is_empty(),"Displaying diagnostics does not capture pointer input or edit the city: "+mode)
	await capture_diagnostics(mode,car["point"])
	studio.photo_tools.start()
	check(studio.worlds[mode].exploration.photo.active and not ui.overlay.visible,"Photo mode immediately hides diagnostic drawing: "+mode)
	studio.photo_tools.stop()
	await settle()
	ui.tick(.3)
	check(ui.overlay.visible,"Leaving Photo mode refreshes the current live geometry: "+mode)
	check(ui.navigate(find("traffic_lane",car["id"]),true) and studio.workspace_layout.tabs.current_tab==studio.traffic_tools.panel.get_index() and not studio.traffic_tools.list.get_selected_items().is_empty(),"Activating a car finding frames the actual actor and opens its traffic control: "+mode)
	runtime.request_route(car,car["to"],car["from"])
	ui.tick(.3)
	var pending: Dictionary=find("traffic_pending",car["id"])
	check(not pending.is_empty() and runtime.route_queue.requests.has(car["id"]) and shapes(pending,"lane").is_empty(),"An actual pending search gets a marker without drawing a substitute route: "+mode)
	var lane: String=car["to"]
	edit_road(doc,Vector2i(int(lane.get_slice(",",0)),int(lane.get_slice(",",1))))
	check(not ui.overlay.visible and not ui.navigate(pending,true),"Editing the road immediately clears stale geometry and makes the old finding inert: "+mode)
	await settle()
	ui.tick(.3)
	var blocked: Dictionary=find("traffic_blocked",car["id"])
	check(not blocked.is_empty() and shapes(blocked,"lane").is_empty() and not blocked["details"]["message"].is_empty(),"An invalid lane reports the runtime's actual reason and no geometry: "+mode)
	studio._command("undo",null)
	await settle()
	ui.tick(.3)
	check(doc.data==before and not ui.current_row(pending),"Undo restores the authored road and never reuses its stale diagnostic revision: "+mode)
	if "--packages" in OS.get_cmdline_user_args():
		var result: Dictionary=Portable.new().save(studio.worlds[mode],doc.data,studio.library,output+"/diagnostics_"+mode+".zip")
		check(result["ok"],"The live diagnostics do not interfere with ordinary portable export: "+mode)
		var saved: String=output+"/diagnostics_"+mode+".isocity.json"
		var saved_ok: bool=studio.write_project(saved,false)
		var text: String=FileAccess.get_file_as_string(saved) if saved_ok else ""
		check(saved_ok and not text.contains("message_key") and not text.contains("traffic_lane") and studio.load_project(saved),
			"Ordinary saves contain no diagnostic records and reopen through the normal command: "+mode)
		await settle()
		check(JSON.parse_string(JSON.stringify(studio.current().data))==JSON.parse_string(JSON.stringify(before)),
			"Reopening retains the exact authored road source: "+mode)

func transit_diagnostics(mode: String) -> void:
	var doc: RefCounted=await document(mode,street(mode))
	var tools: RefCounted=studio.transit_tools
	var manager: Node=tools.managers[mode]
	manager.set_physics_process(false)
	for x in [-32,32]:
		frame_metric(mode,Vector2(x,10))
		tools.add_stop()
		await settle()
	if doc.data["objects"].size()!=2: check(false,"Native stops were placed: "+mode); return
	var stops: Array=doc.data["objects"].map(func(item: Dictionary):return item["uid"])
	var invalid: Dictionary=doc.data["objects"][0].duplicate(true)
	invalid["uid"]="invalid_stop"
	invalid["name"]="Remote platform"
	invalid["position"]=Plan.world(Vector2(0,60),mode)
	doc.data["objects"].append(invalid)
	doc.data["transit"]={"enabled":true,"automatic":false,"population":1}
	doc.data["transit_lines"]=[
		{"uid":"shuttle","name":"District shuttle","stops":stops,"offset":40,"headway":120,"dwell":6},
		{"uid":"remote","name":"Remote route","stops":[stops[0],invalid["uid"]],"headway":120}]
	studio.changed()
	await settle()
	ui.choose("transit")
	ui.tick(.3)
	var bad_stop: Dictionary=find("invalid_platform",invalid["uid"])
	var bad_line: Dictionary=find("invalid_bus_line","remote")
	check(not bad_stop.is_empty() and bad_stop["details"]["message"].contains("sidewalk") and not bad_line.is_empty() and bad_line["related_uids"].has(invalid["uid"]),"The actual transit compiler retains the reasons and identities of failed platforms and lines: "+mode)
	check(ui.navigate(bad_line,true) and tools.selected=="remote" and studio.workspace_layout.tabs.current_tab==tools.panel.get_index(),"A transit issue opens the exact saved line: "+mode)
	var plan: Dictionary=manager.passengers.plan
	var start: Dictionary=plan["stops"][stops[0]]
	var destination: Dictionary=plan["stops"][stops[1]]
	var request: Dictionary=manager.request(start["platform"]+start["right"]*2,destination["platform"]+destination["right"]*2)
	check(request.get("ok",false),"The actual runtime admits a connected transit journey: "+mode)
	if not request.get("ok",false): return
	var job: Dictionary=request["job"]
	for step in 1200:
		manager.step(1.0/60)
		if job["state"]=="waiting": break
	ui.tick(.3)
	var waiting: Array=shapes(find("platform_queue",stops[0]),"queue")
	check(job["state"]=="waiting" and waiting.size()==1 and waiting[0]["label"]=="1" and waiting[0]["points"]==expected(PackedVector2Array([start["platform"]]),mode),"The live passenger queue is anchored at the verified platform: "+mode)
	for step in 5500:
		manager.step(1.0/60)
		if manager.passengers.vehicles.values().any(func(bus: Dictionary)->bool:return bus["phase"]=="moving"): break
	ui.tick(.3)
	var bus_row: Dictionary=find("bus_route","shuttle")
	var lane: Array=shapes(bus_row,"lane")
	check(not bus_row.is_empty() and not lane.is_empty(),"A moving bus contributes its checked current route segment: "+mode)

func service_diagnostics(mode: String) -> void:
	var doc: RefCounted=await document(mode,street(mode))
	var office: String="2d:Office_Tower" if mode=="2d" else "3d:HanX_City/Office_Tower"
	var home: String="2d:House_Blue" if mode=="2d" else "3d:HanX_City/Row_Houses_A"
	var station: Dictionary=doc.add(office,Plan.world(Vector2(-40,-20),mode),"SE" if mode=="2d" else "0")
	station["uid"]="station"
	station["city_service"]={"kind":"fire","radius":256,"units":1,"task_seconds":2}
	var target: Dictionary=doc.add(home,Plan.world(Vector2(16,10),mode),"SE" if mode=="2d" else "180")
	target["uid"]="target"
	doc.data["services"]={"enabled":true,"automatic":false}
	studio.changed()
	await settle()
	var world: Node=studio.worlds[mode]
	for item in doc.data["objects"]:
		var entry: Variant=world.exploration.entrance(world.instances[item["uid"]])
		var actual: Vector2=Plan.metric([entry.x,entry.y,0] if mode=="2d" else [entry.x,entry.y,entry.z],mode)
		var desired:=Vector2(-40,-10) if item["uid"]=="station" else Vector2(16,10)
		item["position"]=Plan.world(Plan.metric(item["position"],mode)+desired-actual,mode)
	studio.changed()
	await settle()
	var tools: RefCounted=studio.service_tools
	var manager: Node=tools.managers[mode]
	manager.set_physics_process(false)
	tools.tick(.4)
	for index in tools.targets.item_count:
		if tools.targets.get_item_metadata(index)=="target": tools.targets.select(index)
	tools.request_kind.select(0)
	tools.tick(.4)
	ui.choose("services")
	ui.tick(.3)
	var row: Dictionary=find("service_coverage","target")
	var coverage: Array=shapes(row,"coverage")
	var verified: bool=not coverage.is_empty()
	if verified:
		var route: PackedStringArray=tools.coverage_result["result"]["route"]
		var edge: Dictionary=manager.dispatch.plan["network"]["edges"][Plan.edge_id(route[0],route[1])]
		verified=coverage[0]["points"]==expected(edge["points"],mode)
	check(verified and row["related_uids"]==["station"],"Service coverage uses the exact dispatch network and winning station: "+mode)
	await capture_diagnostics(mode,Vector2(-10,0),"coverage")
	check(ui.navigate(row,true) and studio.selected_uid=="target" and studio.workspace_layout.tabs.current_tab==tools.panel.get_index(),"A service finding frames the target and opens its real controls: "+mode)
	var request: Dictionary=manager.dispatch.request("fire","target")
	if request["ok"]:
		for step in 30: manager.step(1.0/60)
	ui.tick(.3)
	check(not shapes(find("service_job","target"),"lane").is_empty(),"A dispatched physical crew contributes its safe current piece: "+mode)

func zone_diagnostics(mode: String) -> void:
	var data: Dictionary=street(mode)
	data["zoning"]={"enabled":true,"stage_seconds":120,"seed":7}
	data["zones"]=[
		{"uid":"connected","kind":"residential","rect":[-24,8,48,48],"stage":0},
		{"uid":"isolated","kind":"residential","rect":[-24,72,48,48],"stage":0}]
	var doc: RefCounted=await document(mode,data)
	var manager: Node=studio.zone_tools.managers[mode]
	manager.set_process(false)
	manager.paused=false
	for step in 8: manager.step(.25)
	ui.choose("zoning")
	ui.tick(.3)
	var ready: Dictionary=find("lot_readiness","connected")
	var blocked: Dictionary=find("lot_readiness","isolated")
	var paths: Array=shapes(ready,"walk_metric")
	check(paths.size()==1 and paths[0]["points"]==expected(manager.states["connected"]["approach_path"],mode),"The zone overlay uses the approach accepted by the real lot planner: "+mode)
	check(not blocked.is_empty() and blocked["severity"]=="error" and blocked["details"]["message"].contains("connected roads") and shapes(blocked,"walk_metric").is_empty(),"Disconnected lots describe the failure without a substitute line: "+mode)
	check(ui.navigate(blocked,true) and studio.zone_tools.selected=="isolated","A lot finding opens the exact selected lot: "+mode)
	doc.checkpoint()
	doc.data["zones"].pop_back()
	studio.changed()
	await settle()
	ui.tick(.3)
	check(not ui.navigate(blocked,true) and find("lot_readiness","isolated").is_empty(),"A deleted lot never remains an actionable finding: "+mode)

func fixture_diagnostics(mode: String) -> void:
	var doc: RefCounted=await document(mode,Templates.make(mode,"blank"))
	var host: Dictionary=doc.add("3d:HanX_School/School_Building",[112,-32,0] if mode=="2d" else [7,0,-2],"0",.25)
	host["uid"]="school"
	var room: Dictionary=preload("res://scripts/builder/interiors.gd").make(mode,"Classroom")
	room["objects"]=[]
	var upstairs:=Doc.new()
	upstairs.data=room.duplicate(true)
	var chair: Dictionary=upstairs.add("3d:HanX_School/Student_Chair",[0,-32,0] if mode=="2d" else [-2,.12,-2],"0")
	chair["uid"]="chair"
	room["floors"]=[{"uid":"upper","name":"Upper classroom","height":3,"room":upstairs.data}]
	room["floor_links"]=[]
	host["interior"]=room
	studio.changed()
	await settle()
	studio.selected_uid="school"
	studio.selected_uids.assign(["school"])
	var before: Dictionary=doc.data.duplicate(true)
	ui.choose("fixtures")
	ui.tick(.3)
	var issue: Dictionary=find("return_route","chair")
	check(not issue.is_empty() and issue["scope"]==Common.scope(mode,"school","upper") and issue["details"]["geometry"].is_empty() and not ui.overlay.visible,"Offscreen floor findings keep scope and never project into the exterior: "+mode)
	check(ui.navigate(issue,false) and not studio.interior_tools.editing(),"Selecting an offscreen finding frames the host without creating a room: "+mode)
	check(ui.navigate(issue,true) and studio.interior_tools.editing() and studio.current().floor_uid=="upper" and studio.selected_uid=="chair","Activating the finding opens the saved floor and relevant fixture controls: "+mode)
	ui.tick(.3)
	var stale: bool=not ui.current_row(issue)
	studio.interior_tools.leave()
	await settle()
	check(stale and doc.data==before and doc.undo_history.is_empty(),"Floor navigation invalidates the exterior revision and preserves the exact authored room: "+mode)
	doc.object("school")["interior"]["floor_links"]=[{"uid":"stairs","kind":"stairs","lower":"ground","upper":"upper","start":[0,0],"end":[0,6],"width":1.2}]
	studio.changed()
	await settle()
	studio.selected_uid="school"
	studio.selected_uids.assign(["school"])
	ui.tick(.3)
	var repaired: Dictionary=find("return_route","chair")
	check(repaired.get("severity")=="ok" and shapes(repaired,"walk").is_empty() and ui.navigate(repaired,true),"A real repaired route can be opened without drawing the upper floor outside: "+mode)
	await settle()
	ui.tick(.3)
	var upstairs_route: Dictionary=find("return_route","chair")
	check(upstairs_route.get("scope")==Common.scope(mode,"school","upper") and not shapes(upstairs_route,"walk").is_empty(),"The active floor draws only its verified walking legs: "+mode)
	studio.interior_tools.leave()
	await settle()

func people_diagnostics(mode: String) -> void:
	var doc: RefCounted=await document(mode,Templates.make(mode,"blank"))
	var assets: Array=["2d:Apartment_Brick","2d:Office_Tower","2d:Coffee_Shop","2d:Park_Bench"] if mode=="2d" else ["3d:HanX_City/Apartment_4F_A","3d:HanX_City/Office_Tower","3d:HanX_City/Cafe_Small","3d:HanX_Park/Bench_Park"]
	var positions: Array=[[-160,-96,0],[160,-96,0],[160,96,0],[-160,96,0]] if mode=="2d" else [[-14,0,-12],[14,0,-12],[14,0,12],[-14,0,12]]
	for index in 4:
		var item: Dictionary=doc.add(assets[index],positions[index],("SW" if index==0 else "SE") if mode=="2d" else ("90" if index==0 else "0"))
		item["uid"]=["home","work","shop","park"][index]
	doc.data["citizens"]={"enabled":true,"population":3,"seed":5,"day_length":3600,"start_hour":9}
	doc.data["scenario"]={"id":"walkable","attempt":"paths"}
	var scenario: Node=studio.scenario_tools.managers[mode]
	scenario.set_process(false)
	studio.changed()
	await settle()
	var citizens: Node=studio.citizen_tools.managers[mode]
	citizens.set_physics_process(false)
	var active: Dictionary={}
	for index in 120:
		citizens.step(1.0/60)
		for resident in citizens.residents:
			if resident["actor"] and resident["actor"].visible and resident["index"]+1<resident["path"].size() and resident["waiting"].is_empty():
				active=resident
				break
		if not active.is_empty(): break
	ui.choose("residents")
	ui.tick(.3)
	var found: bool=false
	for row in ui.snapshot["rows"]:
		if row["details"].get("key")==active.get("id",""):
			var paths: Array=shapes(row,"walk")
			if not paths.is_empty():
				var start: Vector2=active["path"][maxi(0,active["index"]-1)]
				var metric: Vector2=Vector2(start.x+start.y,start.y-start.x) if mode=="2d" else start
				found=paths[0]["points"][0]==expected(PackedVector2Array([metric]),mode)[0]
			break
	check(found,"A real visible resident contributes its current walking route in the correct world units: "+mode)
	ui.choose("challenges")
	ui.tick(.3)
	check(not find("challenge_pending").is_empty() and find("challenge_route").is_empty(),"Pending neighborhood requests supply no guessed walking geometry: "+mode)
	while not scenario.queue.is_empty(): scenario.step()
	ui.tick(.3)
	var checked: Dictionary=find("challenge_route","home")
	var paths: Array=shapes(checked,"walk")
	check(not paths.is_empty() and checked["related_uids"].size()==1 and checked["details"]["message"].contains("Verified walking route"),"The challenge contributes a route only after its real walking check: "+mode)

func budget_checks() -> void:
	var source:=Sources.new(studio,Common.scope(studio.mode),0)
	var line:=PackedVector2Array()
	for index in 20000: line.append(Vector2(index,index%2))
	var row: Dictionary=source.row("stress","info","long","object","Long verified result","Test the drawing budget.")
	var started: int=Time.get_ticks_usec()
	source.path(row,line)
	var elapsed: int=Time.get_ticks_usec()-started
	check(source.points==Common.MAX_POINTS and source.shapes==1 and source.limited and row["details"]["geometry"][0]["points"]==expected(line.slice(0,Common.MAX_POINTS),studio.mode),"Long geometry keeps a contiguous prefix at the point budget without shortcuts.")
	for index in 1000:
		var extra: Dictionary=source.row("stress","info",str(index),"object","Finding","Test the finding budget.")
		source.pin(extra,Vector3.ZERO)
	check(source.rows.size()==Common.MAX_ROWS and source.points==Common.MAX_POINTS and source.shapes==1,"Oversized collections stay within row and geometry budgets.")
	print("DIAGNOSTIC GEOMETRY BUDGET: %d candidate points · %d retained · %d us"%[line.size(),source.points,elapsed])

func run() -> void:
	output=OS.get_environment("ISOCITY_DIAGNOSTIC_OUTPUT")
	if output.is_empty(): output="res://output/simulation_diagnostics_fixture"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size=Vector2i(1480,900)
	studio=load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled=false
	root.add_child(studio)
	await settle()
	if studio.consumer_shell:
		studio.consumer_shell.dismiss_welcome()
		studio.consumer_shell.set_active("--simple" in OS.get_cmdline_user_args(),false)
	ui=studio.simulation_diagnostic_tools
	for mode in ["2d","3d"]:
		await traffic_diagnostics(mode)
		await transit_diagnostics(mode)
		await service_diagnostics(mode)
		await zone_diagnostics(mode)
		await fixture_diagnostics(mode)
		await people_diagnostics(mode)
		ui.choose("off")
	budget_checks()
	studio.free()
	await settle()
	print("SIMULATION DIAGNOSTICS: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
