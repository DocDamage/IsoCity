extends "res://tools/test_power_network.gd"

const Connector=Plan.Connector
const Wall="2d:Added_Gloria_Station_1_2_2_Gloria_Station_Walls_4x_wall_neXsw_1fade71f"
const Scaffold="3d:HanX_Construction/Scaffold_Module"
const Fence="3d:HanX_Construction/Fence_Panel"

func shortcut(code: Key,alt: bool=false) -> void:
	var event:=InputEventKey.new()
	event.keycode=code
	event.physical_keycode=code
	event.alt_pressed=alt
	event.pressed=true
	if not studio.control_settings.input(event): studio._unhandled_key_input(event)

func open_canvas(mode: String,source: Dictionary) -> RefCounted:
	studio.switch_mode(mode)
	var doc: RefCounted=studio.current()
	doc.data=source
	doc.undo_history.clear()
	doc.redo_history.clear()
	studio.economy_tools.pauses[mode]=true
	studio.control_settings.cursor_active=false
	studio.set_tool("select")
	studio.changed()
	return doc

func select_module(item: Dictionary) -> void:
	studio.select_asset(item["asset"])
	studio.direction=item["direction"]
	studio.scale_input.set_value_no_signal(item["scale"])
	studio.placement_angle=0
	studio.placement_tilt=Vector2.ZERO

func show_at(at: Vector2) -> void:
	studio.control_settings.cursor_active=true
	studio.control_settings.cursor_position=at
	await settle()
	studio.update_overlay(true)

func structure(mode: String) -> void:
	var source: Dictionary=Templates.make(mode,"blank")
	var item: Dictionary=object(Wall if mode=="2d" else Scaffold,"module",Vector2.ZERO,mode,.1)
	item["direction"]="SE" if mode=="2d" else "0"
	source["objects"]=[item]
	var doc: RefCounted=open_canvas(mode,source)
	await settle()
	studio._command("connectors",null)
	studio.connector_tools.enabled.button_pressed=true
	studio.connector_tools.markers_visible.button_pressed=true
	select_module(item)
	var target: Dictionary=Connector.frames(item,mode)[1]
	var at: Vector2=studio.connector_tools.project(target["point"])
	await show_at(at)
	var markers: Array=studio.overlay.socket_markers
	check(markers.size()==2 and markers[0]["kind"]=="structure" and markers[0]["at"].is_equal_approx(markers[1]["at"]),
		"Tiny calibrated sockets retain two screen-sized markers at the aligned point "+mode+" "+studio.connector_tools.status.text)
	check(studio.connector_tools.status.text.contains("Face ends together"),"Structure inspector names the allowed mating direction "+mode)
	var before: Dictionary=doc.data.duplicate(true)
	var moved: Array=doc.object("module")["position"].duplicate()
	moved[0]+=1.0
	doc.object("module")["position"]=moved
	studio.changed()
	studio.paint(at)
	check(doc.data["objects"].size()==1 and studio.status.text.contains("Connection changed"),
		"A move between visible preview and click cannot silently change the snapped pose "+mode)
	target=Connector.frames(doc.object("module"),mode)[1]
	at=studio.connector_tools.project(target["point"])
	await show_at(at)
	var reviewed: Dictionary=studio.placement(at)
	doc.checkpoint()
	studio.stroke_cells.clear()
	studio.paint(at)
	doc.finish_checkpoint()
	check(doc.data["objects"].size()==2 and doc.data.get("connections",[]).size()==1 and doc.data["objects"][-1]["position"]==reviewed["position"],
		"Click after reviewing the new marker commits its exact pose and connection "+mode)
	studio._command("undo",null)
	check(doc.data["objects"].size()==1 and doc.data.get("connections",[]).is_empty(),"One Undo clears the exact structural joint "+mode)
	doc.data=before
	studio.changed()
	await settle()
	if mode=="3d": await obstructed_structure(doc,item)
	studio.connector_tools.enabled.button_pressed=false
	studio.control_settings.cursor_active=false
	studio.set_tool("select")

func obstructed_structure(doc: RefCounted,item: Dictionary) -> void:
	var full: Dictionary=item.duplicate(true)
	full["scale"]=1.0
	doc.data["objects"]=[full]
	var target: Dictionary=Connector.frames(full,"3d")[1]
	var point: Vector3=target["point"]
	var blocker: Dictionary=object(Fence,"cover",Vector2(point.x,point.z),"3d")
	blocker["position"][1]=point.y-.5
	doc.data["objects"].append(blocker)
	studio.changed()
	select_module(full)
	var world: Node=studio.worlds["3d"]
	world.target=point
	world.distance=8
	world.update_camera()
	await settle()
	var at: Vector2=studio.connector_tools.project(point)
	await show_at(at)
	var choice: Dictionary=studio.placement(at).get("socket",{})
	check(choice.get("blocked",false) and choice.get("reason","").contains("blocks") and studio.overlay.socket_markers.size()==2,
		"A real covering collider leaves both markers visible and explains the blocked mate.")
	var old: Dictionary=doc.data.duplicate(true)
	studio.connector_tools.markers_visible.button_pressed=false
	studio.update_overlay(true)
	check(studio.overlay.socket_markers.is_empty(),"Structure marker toggle clears the canvas without changing the plan.")
	shortcut(KEY_PAGEDOWN,true)
	shortcut(KEY_F7)
	check(doc.data==old,"A hidden overlay and keyboard click cannot bypass a physical obstruction.")
	studio.connector_tools.markers_visible.button_pressed=true

func occupied_pipe() -> void:
	var data: Dictionary=authored("2d")
	var item: Dictionary=object(Pipe,"pipe",Vector2(-6,6),"2d",.7)
	var target: Dictionary=Connector.frames(item,"2d")[1]
	data["objects"].append(item)
	data["utility_edges"].append(edge("pipe_branch","well","outlet_west","pipe",target["socket"]))
	var doc: RefCounted=open_canvas("2d",data)
	await settle()
	studio._command("connectors",null)
	studio.connector_tools.enabled.button_pressed=true
	studio.connector_tools.utility.button_pressed=true
	select_module(item)
	var at: Vector2=studio.connector_tools.project(target["point"])
	await show_at(at)
	var choice: Dictionary=studio.placement(at).get("socket",{})
	check(choice.get("blocked",false) and choice.get("reason","").contains("already"),
		"An existing utility run reserves the calibrated pipe socket in the placement tool.")
	var before: Dictionary=doc.data.duplicate(true)
	shortcut(KEY_F7)
	check(doc.data==before and studio.status.text.contains("already"),
		"An attempted snapped pipe cannot displace the existing utility run.")
	studio.connector_tools.utility.button_pressed=false
	studio.connector_tools.enabled.button_pressed=false
	studio.control_settings.cursor_active=false

func overlapping_floors(mode: String) -> void:
	var source: Dictionary=Templates.make(mode,"blank")
	var home: Dictionary=object("2d:House_Blue" if mode=="2d" else "3d:HanX_City/Row_Houses_A","house",Vector2.ZERO,mode)
	var ground: Dictionary=Templates.make(mode,"blank")
	var upper: Dictionary=ground.duplicate(true)
	ground["interior_room"]=true
	upper["interior_room"]=true
	var item: Dictionary=object(Wall if mode=="2d" else Scaffold,"ground_socket",Vector2.ZERO,mode,.65)
	item["direction"]="SE" if mode=="2d" else "0"
	var upstairs: Dictionary=item.duplicate(true)
	upstairs["uid"]="upper_socket"
	ground["objects"]=[item]
	upper["objects"]=[upstairs]
	ground["floors"]=[{"uid":"upper","name":"Upper","height":3,"room":upper}]
	home["interior"]=ground
	source["objects"]=[home]
	open_canvas(mode,source)
	await settle()
	studio.interior_tools.start("house")
	await settle()
	check(studio.interior_tools.editing(),"Normal interior editor opens the building with overlapping sockets "+mode)
	if not studio.interior_tools.editing(): return
	studio._command("connectors",null)
	studio.connector_tools.enabled.button_pressed=true
	var frame: Dictionary=Connector.frames(item,mode)[1]
	select_module(item)
	var at: Vector2=studio.connector_tools.project(frame["point"])
	await show_at(at)
	check(studio.placement(at).get("socket",{}).get("target",{}).get("object_uid")=="ground_socket",
		"The ground-floor preview resolves only the ground socket "+mode)
	studio.interior_tools.floor_tools.switch_floor("upper")
	select_module(item)
	await settle()
	at=studio.connector_tools.project(frame["point"])
	await show_at(at)
	var choice: Dictionary=studio.placement(at).get("socket",{})
	check(choice.get("target",{}).get("object_uid")=="upper_socket","The same projected location resolves only the active upper floor "+mode)
	studio.stroke_cells.clear()
	studio.current().checkpoint()
	studio.paint(at)
	studio.current().finish_checkpoint()
	var data: Dictionary=studio.current().canonical.data
	check(data.get("connections",[]).is_empty() and data["floors"][0]["room"].get("connections",[]).size()==1
		and data["floors"][0]["room"]["connections"][0]["to"]["object_uid"]=="upper_socket",
		"A committed upstairs joint cannot affect the overlapping ground floor "+mode)
	studio.connector_tools.enabled.button_pressed=false
	studio.control_settings.cursor_active=false
	studio.interior_tools.leave()

func network_source(mode: String,kind: String) -> Dictionary:
	var data: Dictionary=authored(mode) if kind=="water" else authored_power(mode)
	data["utility_edges"].pop_front()
	for i in 24:
		var uid: String="extra_%02d"%i
		var house: String="2d:House_Blue" if mode=="2d" else "3d:HanX_City/Row_Houses_A"
		data["objects"].append(object(house,uid,Vector2(-1+(i%6)*2,-2-floori(i/6.0)*2),mode,.28))
		var facility: Dictionary=node(uid)
		facility["kind"]=kind
		data["utility_nodes"].append(facility)
	return data

func network(mode: String,kind: String) -> void:
	var doc: RefCounted=open_canvas(mode,network_source(mode,kind))
	await settle()
	studio._command(kind,null)
	var ui: RefCounted=studio.utility_tools if kind=="water" else studio.power_tools
	var input: String="inlet" if kind=="water" else "input"
	var a: Dictionary=reference("well","outlet") if kind=="water" else reference("generator","output")
	var occupied: Dictionary=reference("tank","east") if kind=="water" else reference("relay","east")
	check(choose(ui.first,a) and choose(ui.second,occupied),"Both endpoint controls list the real roles "+mode+" "+kind)
	studio.update_overlay(false)
	var overlay: Control=studio.overlay
	var draft: Dictionary=ui.preview()
	check(ui.join_button.disabled and draft.get("reason","").contains("already") and overlay.socket_markers.size()==2
		and overlay.socket_markers[-1]["blocked"] and ui.status.text.contains("Mating") and overlay.caption.contains("already"),
		"Occupied port shows both markers, the permitted direction and its blocked reason "+mode+" "+kind)
	var before: Dictionary=doc.data.duplicate(true)
	shortcut(KEY_PAGEDOWN,true)
	var selected: Variant=ui.choice(ui.second)
	check(selected!=occupied and not ui.join_button.disabled and ui.status.text.contains("of ") and doc.data==before,
		"Default keyboard shortcut skips occupied targets across many real ports "+mode+" "+kind)
	shortcut(KEY_PAGEUP,true)
	var previous: Variant=ui.choice(ui.second)
	check(previous!=selected and not ui.join_button.disabled,"Previous target wraps within the stable eligible list "+mode+" "+kind)
	shortcut(KEY_PAGEDOWN,true)
	check(ui.choice(ui.second)==selected,"Opposite keyboard commands return to the same candidate "+mode+" "+kind)
	choose(ui.first,reference("extra_00",input))
	choose(ui.second,reference("extra_01",input))
	check(ui.join_button.disabled and ui.status.text.contains("Pair an"),"An incompatible input pair retains a readable reason "+mode+" "+kind)
	choose(ui.first,a)
	choose(ui.second,reference("extra_03",input))
	var latest: Dictionary=ui.preview()
	check(not latest.is_empty() and latest["reason"].is_empty(),"Free draft exposes exact world endpoints "+mode+" "+kind)
	doc.object("extra_03")["position"][0]+=2.0
	studio.changed()
	ui.join_button.pressed.emit()
	check(doc.data["utility_edges"]==before["utility_edges"] and studio.status.text.contains("Connection changed"),
		"Changed coordinates require a fresh visible review even with identical endpoint IDs "+mode+" "+kind)
	latest=ui.preview()
	ui.join_button.pressed.emit()
	var cable: Dictionary=doc.data["utility_edges"][-1]
	var resolved: Dictionary=ui.manager().graph["links"].get([false,cable["uid"]],{})
	check(cable["from"]==a and cable["to"]==reference("extra_03",input) and resolved.get("positions")==latest.get("positions"),
		"The same reviewed source, target and positions reach the accepted utility graph "+mode+" "+kind)
	studio._command("undo",null)
	ui.tick(0)
	check(doc.data["utility_edges"]==before["utility_edges"],"Undo leaves only the original runs "+mode+" "+kind)
	ui.markers_visible.button_pressed=false
	studio.update_overlay(false)
	check(overlay.socket_markers.is_empty() and overlay.socket_line.is_empty() and not ui.preview().is_empty(),
		"Hide connection markers keeps textual review without canvas clutter "+mode+" "+kind)
	ui.markers_visible.button_pressed=true
	var target: Variant=ui.choice(ui.second)
	studio.photo_tools.start()
	await settle()
	shortcut(KEY_PAGEDOWN,true)
	check(ui.choice(ui.second)==target and overlay.socket_markers.is_empty() and not overlay.visible,
		"Photo mode suppresses both utility markers and shortcut traversal "+mode+" "+kind)
	studio.photo_tools.stop()
	studio._command(kind,null)
	await settle()
	var world: Node=studio.worlds[mode]
	if mode=="2d": world.camera.position.x+=1600
	else:
		world.target+=Vector3(600,0,0)
		world.update_camera()
	await settle()
	studio.update_overlay(false)
	var offscreen: Array=overlay.socket_markers.filter(func(marker: Dictionary)->bool:
		return marker["at"].is_finite() and not overlay.socket_bounds().has_point(marker["at"]))
	check(not offscreen.is_empty() and overlay.socket_label(offscreen[0]).begins_with("Off-screen")
		and overlay.socket_bounds().encloses(overlay.socket_label_rect(offscreen[0])),
		"An endpoint outside the canvas gets a bounded off-screen label "+mode+" "+kind)
	world.reset_camera("blank")
	await settle()
	await capture_ports(mode,kind,ui)
	for item in doc.data["objects"]:
		if not item["uid"].begins_with("extra_"): item["locked"]=true
	studio.changed()
	ui.tick(0)
	choose(ui.first,reference("extra_00",input))
	choose(ui.second,reference("extra_01",input))
	shortcut(KEY_PAGEDOWN,true)
	check(ui.join_button.disabled and ui.status.text.contains("No compatible target"),"An empty eligible list gives a clear reason "+mode+" "+kind)

func capture_ports(mode: String,kind: String,ui: RefCounted) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	for simple in [false,true]:
		studio.consumer_shell.set_active(simple,false)
		for size in [Vector2i(1480,900),Vector2i(960,640)]:
			root.size=size
			studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true} if size.x==960 else {})
			if size.x==960: studio.workspace_layout.library_toggle.button_pressed=false
			studio._command(kind,null)
			await settle()
			ui.second.grab_focus()
			await settle()
			studio.update_overlay(false)
			var overlay: Control=studio.overlay
			var markers: Array=overlay.socket_markers
			var clear: bool=false
			if markers.size()==2:
				var a: Rect2=overlay.socket_label_rect(markers[0])
				var b: Rect2=overlay.socket_label_rect(markers[1])
				clear=a.has_area() and b.has_area() and not a.intersects(b) and overlay.socket_bounds().encloses(a) and overlay.socket_bounds().encloses(b)
			check(clear and ui.second.has_focus() and (size.x!=960 or overlay.socket_tint(markers[-1])==Color.WHITE),
				"Both labels and keyboard focus remain usable with the compact inspector "+str([mode,kind,simple,size]))
			RenderingServer.force_draw(false)
			RenderingServer.force_draw(false)
			var path: String=output+"/%s_%s_%s_%d.png"%[kind,"simple" if simple else "precision",mode,size.x]
			check(root.get_texture().get_image().save_png(path)==OK,"Captured "+path)
			ui.second.release_focus()
	root.size=Vector2i(1480,900)
	studio.accessibility_settings.restore({})
	await settle()

func export_connected_city(mode: String) -> void:
	var data: Dictionary=authored_power(mode)
	data["utilities"]["water"]=true
	data["objects"].append_array([object(Well,"well",Vector2(-12,8),mode,.48),
		object(Tower if mode=="2d" else Roof,"tank",Vector2(12,8),mode,.5)])
	data["utility_nodes"].append_array([node("well"),node("tank"),node("home")])
	data["utility_nodes"][-1]["uid"]="water_home"
	data["utility_edges"].append_array([edge("water_feed","well","outlet","tank","west"),edge("water_house","tank","north","home","inlet")])
	var a: Dictionary=object(Wall if mode=="2d" else Scaffold,"structure_a",Vector2(28,-12),mode,.65)
	a["direction"]="SE" if mode=="2d" else "0"
	var b: Dictionary=a.duplicate(true)
	b["uid"]="structure_b"
	var first: Dictionary=Connector.frames(a,mode)[1]
	var second: Dictionary=Connector.frames(b,mode)[0]
	var solution: Dictionary=Connector.solve(b,second,first,mode,data,{})
	check(solution.get("ok",false),"Mixed portable fixture has a calibrated structure joint "+mode)
	if not solution.get("ok",false): return
	data["objects"].append_array([a,solution["pose"]])
	data["connections"]=[{"uid":"verified_joint","kind":"structure",
		"from":reference("structure_b",second["socket"]),"to":reference("structure_a",first["socket"])}]
	check(Doc.valid(data,mode,studio.library),"The mixed structure, water and power source validates "+mode)
	var result: Dictionary=Export.new().save(studio.worlds[mode],data,studio.library,output+"/connections_"+mode+".zip")
	check(result.get("ok",false),"Mixed connected city exports through the existing policy "+mode+" "+result.get("message",""))

func run() -> void:
	output=OS.get_environment("ISOCITY_CONNECTION_OUTPUT")
	if output.is_empty(): output="res://output/verification/asset_expansion/U11"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	studio=load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled=false
	root.add_child(studio)
	await settle()
	if studio.consumer_shell: studio.consumer_shell.dismiss_welcome()
	await occupied_pipe()
	for mode in ["2d","3d"]:
		await structure(mode)
		await overlapping_floors(mode)
		for kind in ["water","power"]: await network(mode,kind)
		if "--portable" in OS.get_cmdline_user_args(): export_connected_city(mode)
	studio.free()
	await settle()
	print("CONNECTION AFFORDANCES: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
