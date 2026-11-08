extends SceneTree
const Plan=preload("res://scripts/builder/transit_plan.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for frame in 6: await process_frame
	await physics_frame
func press(parent: Node,title: String) -> void:
	for node in parent.find_children("*","Button",true,false):
		if node.text==title: node.pressed.emit(); return
	check(false,"Missing transit action: "+title)
func capture(name: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await settle(); await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png("res://output/"+name+".png")
func center(studio: Control,mode: String,point: Vector2) -> void:
	var raw: Array=Plan.Traffic.world(point,mode)
	if mode=="2d": studio.worlds[mode].camera.position=Vector2(raw[0],raw[1])
	else: studio.worlds[mode].target=Vector3(raw[0],0,raw[2]); studio.worlds[mode].update_camera()
func run() -> void:
	root.size=Vector2i(1480,900)
	var studio: Control=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio); await settle()
	var tools: RefCounted=studio.transit_tools
	for mode in ["2d","3d"]:
		studio.switch_mode(mode)
		var doc=preload("res://scripts/builder/document.gd").new(); doc.data=preload("res://scripts/builder/templates.gd").make(mode,"blank"); doc.data["objects"]=[]; doc.data["roads"]=[]
		for x in range(-10,11): doc.data["roads"].append({"cell":[x,0]})
		studio.documents[mode]=doc; studio.changed(); await settle(); tools.tick(.4)
		var manager: Node=tools.managers[mode]; manager.set_physics_process(false); tools.paused.button_pressed=true
		studio._command("transit",null)
		check(studio.workspace_layout.tabs.current_tab==tools.panel.get_index() and studio.workspace_layout.inspector_open,"Command palette opens the transit inspector: "+mode)
		for x in [-32,32]:
			center(studio,mode,Vector2(x,10)); press(tools.panel,"Add stop near view center"); await settle(); tools.tick(.4)
		check(doc.data["objects"].size()==2 and doc.data["objects"].all(func(item: Dictionary):return Plan.is_stop(item)),"UI actions place two real native bus stops: "+mode)
		if doc.data["objects"].size()!=2: continue
		var ids: Array=doc.data["objects"].map(func(item: Dictionary):return item["uid"])
		doc.undo(); studio.changed(); check(doc.data["objects"].size()==1,"Stop placement supports Undo: "+mode); doc.redo(); studio.changed(); await settle(); tools.tick(.4)
		check(doc.data["objects"].size()==2 and doc.data["objects"][1]["uid"]==ids[1],"Redo restores the exact authored stop: "+mode)
		doc.data["layers"]={"Decorations":{"locked":true}}; studio.changed(); press(tools.panel,"Add stop near view center")
		check(doc.data["objects"].size()==2,"Protected stop layers reject placement: "+mode); doc.data.erase("layers"); studio.changed(); await settle(); tools.tick(.4)
		studio.selected_uids.assign([ids[1]]); studio.selected_uid=ids[1]
		press(tools.panel,"Remove selected stop designations"); check(not Plan.is_stop(doc.object(ids[1])),"Native stop props can explicitly opt out: "+mode)
		doc.undo(); studio.changed(); await settle(); tools.tick(.4)
		press(tools.panel,"New route")
		for index in tools.stops.item_count: tools.stops.select(index); press(tools.panel,"Append chosen stop to route")
		check(tools.draft.size()==2,"Chosen stops form an editable ordered route: "+mode)
		tools.ordered.select(1); press(tools.panel,"Move route stop up"); check(tools.draft[0]==ids[1],"Route order moves up: "+mode); press(tools.panel,"Move route stop down"); check(tools.draft==Array(ids),"Route order moves down: "+mode)
		tools.name_input.text="District shuttle"; tools.color_input.color=Color("e8ac42"); tools.headway.value=120; tools.dwell.value=6; tools.offset.value=10; tools.capacity.value=2
		press(tools.panel,"Save route"); check(doc.data.get("transit_lines",[]).size()==1,"Route controls save an authored line: "+mode)
		var line_id: String=doc.data["transit_lines"][0]["uid"]
		check(doc.data["transit_lines"][0]["stops"]==ids and doc.data["transit_lines"][0]["headway"]==120 and doc.data["transit_lines"][0]["capacity"]==2,"Saved order, schedule and seats match the controls: "+mode)
		var before: Dictionary=doc.data.duplicate(true); tools.offset.value=200; press(tools.panel,"Save route"); check(doc.data==before,"Invalid departure offsets are rejected without changing content: "+mode); tools.offset.value=10
		doc.undo(); studio.changed(); check(doc.data.get("transit_lines",[]).is_empty(),"Route creation supports Undo: "+mode); doc.redo(); studio.changed(); await settle(); tools.tick(.4)
		tools.selected=line_id; tools.load_line(); tools.enabled.button_pressed=true; tools.automatic.button_pressed=false; press(tools.panel,"Apply transit settings"); await settle(); tools.tick(.4)
		check(manager.passengers.plan["lines"].size()==1 and manager.passengers.plan["stops"].size()==2,"Normal Studio lifecycle compiles the authored route: "+mode+str(manager.passengers.plan["notices"]))
		check(studio.traffic_tools.managers[mode].transit==manager and studio.service_tools.managers[mode].helper.transit==manager,"Traffic and service vehicles discover the shared transit fleet: "+mode)
		check(tools.timetable.text.contains("Next scheduled departures") and tools.timetable.text.contains("Bus stop"),"Inspector exposes the route's next departures: "+mode)
		tools.stops.select(0); tools.destination.select(1); press(tools.panel,"Send a passenger")
		check(manager.passengers.jobs.size()==1,"Connection controls create a live passenger request: "+mode)
		tools.paused.button_pressed=false; var job: Dictionary=manager.passengers.jobs[0]
		for frame in 15000:
			manager.step(1.0/60)
			if job["state"] in ["complete","blocked","cancelled"]: break
		check(job["state"]=="complete","An authored Studio route carries a passenger to the real destination: "+mode+str(job["reason"]))
		tools.paused.button_pressed=true; var clock: float=manager.elapsed; manager.step(.25); check(clock==manager.elapsed,"Inspector pause freezes actual transit: "+mode)
		var actor: Node=manager.buses.values()[0]["vehicle"]["actor"]
		studio.switch_mode("3d" if mode=="2d" else "2d"); tools.tick(.4); manager.step(.25); check(manager.elapsed==clock and not manager.helper.container.visible,"Other city modes suspend and hide transit: "+mode)
		studio.switch_mode(mode); await settle(); tools.tick(.4); check(manager.buses.values()[0]["vehicle"]["actor"]==actor,"Returning to a city preserves its transit actors: "+mode)
		var home_asset: String="2d:House_Blue" if mode=="2d" else "3d:HanX_City/Row_Houses_A"
		var home: Dictionary=doc.add(home_asset,Plan.Traffic.world(Vector2(-12,-24),mode),studio.library.directions(home_asset)[0]); studio.changed(); await settle(); tools.tick(.4)
		studio.set_walking(true); var walk: Node=studio.worlds[mode].exploration; studio.worlds[mode].player.teleport_to(walk.entrance(studio.worlds[mode].instances[home["uid"]])); walk.interact(); await settle(); tools.tick(.4)
		clock=manager.elapsed; var stamp: int=manager.signature; manager.step(.25)
		check(walk.interior!=null and manager.elapsed==clock and manager.signature==stamp and not manager.helper.container.visible,"Interior visits suspend transit without recompiling disabled exterior collisions: "+mode)
		walk.leave_interior(); studio.set_walking(false); await settle(); tools.tick(.4)
		check(manager.buses.values()[0]["vehicle"]["actor"]==actor,"Returning outside retains the existing buses: "+mode)
		var saved: String="res://output/transit_"+mode+".isocity.json"; check(studio.write_project(saved),"Transit definitions save with the project: "+mode)
		tools.selected=line_id; press(tools.panel,"Delete route"); check(doc.data["transit_lines"].is_empty() and doc.data["objects"].size()==3,"Deleting a line preserves its stop props: "+mode)
		check(studio.load_project(saved),"Saved transit projects reopen: "+mode); await settle(); tools.tick(.4); doc=studio.current()
		check(doc.data["transit_lines"][0]["uid"]==line_id and manager.passengers.completed==0,"Reopening retains authored routes and resets transient journeys: "+mode)
		tools.selected=line_id; tools.load_line(); tools.show(); await capture("transit_inspector_"+mode)
		tools.panel.scroll_vertical=int(tools.lines.position.y); await capture("transit_route_editor_"+mode)
		var path: String="res://output/transit_"+mode+".tscn"
		check(studio.Exporter.save_scene(studio.worlds[mode],doc.data,studio.library,path)==OK,"Authored transit cities export as playable scenes: "+mode)
		var viewport:=SubViewport.new(); viewport.size=Vector2i(1480,900); viewport.own_world_3d=true; root.add_child(viewport)
		var playable: Node=load(path).instantiate(); viewport.add_child(playable); await settle(); playable.walking=false; playable._set_mode(); playable.transit.set_physics_process(false); playable.player.set_physics_process(false)
		check(playable.transit.passengers.plan["lines"].size()==1 and playable.traffic.transit==playable.transit,"Playable scenes compile transit and share the traffic fleet: "+mode)
		var stop_values: Array=playable.transit.passengers.plan["stops"].values(); var request: Dictionary=playable.transit.request(stop_values[0]["platform"]+stop_values[0]["right"]*2,stop_values[1]["platform"]+stop_values[1]["right"]*2)
		check(request["ok"],"Playable transit accepts a real connected passenger journey: "+mode)
		if request["ok"]:
			for frame in 15000:
				playable.transit.step(1.0/60)
				if request["job"]["state"] in ["complete","blocked","cancelled"]: break
			check(request["job"]["state"]=="complete","Actual playable buses complete the passenger's final walk: "+mode+str(request["job"]["reason"]))
		playable.transit.update_hud(); check(playable.transit.panel.visible,"Playable transit exposes status and pause controls: "+mode)
		playable.transit.pause_button.pressed.emit(); clock=playable.transit.elapsed; playable.transit.step(.25); check(playable.transit.paused and playable.transit.elapsed==clock,"Playable pause controls freeze transit clocks: "+mode)
		viewport.free()
		var portable_data: Dictionary=doc.data.duplicate(true); var third: Dictionary=portable_data["objects"][0].duplicate(true); third["uid"]="portable_third"; third["name"]="West district"
		var delta: Vector2=Vector2(-64,8)-Plan.Zones.footprint(third,mode,studio.library).get_center(); third["position"]=Plan.Traffic.world(Plan.Traffic.metric(third["position"],mode)+delta,mode)
		portable_data["objects"].append(third); portable_data["transit_lines"].append({"uid":"west_connector","name":"West connector","stops":[ids[1],third["uid"]],"headway":180,"offset":30})
		var portable: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(studio.worlds[mode],portable_data,studio.library,"res://output/transit_"+mode+".zip")
		check(portable["ok"],"Portable export includes future bus and passenger dependencies: "+mode+str(portable))
		studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true}); await settle(); check(tools.enabled.custom_minimum_size.y>=44 and tools.status.get_theme_font_size("font_size")==18,"Transit controls honor accessible text and target settings: "+mode); studio.accessibility_settings.restore({}); await settle()
	root.size=Vector2i(960,640); tools.show(); await settle()
	check(tools.panel.get_child(0).size.x<=tools.panel.size.x,"Transit controls fit a scrolling inspector at 960×640"); await capture("transit_small_window")
	studio.free(); print("TRANSIT WORKFLOW: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
