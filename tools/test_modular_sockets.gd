extends SceneTree

const Plan = preload("res://scripts/builder/connector_plan.gd")
const Blueprint = preload("res://scripts/builder/blueprint_plan.gd")
const Economy = preload("res://scripts/builder/economy_plan.gd")
const Doc = preload("res://scripts/builder/document.gd")
const Templates = preload("res://scripts/builder/templates.gd")
const Repair = preload("res://scripts/builder/project_repair.gd")
const Protection = preload("res://scripts/builder/cooperative_plan.gd")
const GLORIA_RISE = "2d:Added_Gloria_Station_1_2_2_Gloria_Station_Walls_4x_wall_neXsw_1fade71f"
const GLORIA_FALL = "2d:Added_Gloria_Station_1_2_2_Gloria_Station_Walls_4x_wall_nwXse_8fd77692"
const PIPE = "2d:Added_rendered_modular_pipeline_pack_modular_pipeline_pack_01_666e79e8"
const SMALL_PIPE = "2d:Added_rendered_modular_pipeline_pack_modular_pipeline_pack_04_1c9e1b6d"
const WALL = "3d:Supplemental_SWAT/Training_Wall_Straight"
const DOOR_WALL = "3d:Supplemental_SWAT/Training_Wall_Door"
const CORNER = "3d:Supplemental_SWAT/Training_Wall_Corner"
const SCAFFOLD = "3d:HanX_Construction/Scaffold_Module"
const LADDER = "3d:HanX_Construction/Scaffold_Module_Ladder"
const FENCE = "3d:HanX_Construction/Fence_Panel"
const SCREEN = "3d:HanX_Construction/Fence_Panel_Screen"

var checks: int = 0
var failures: int = 0
var studio: Control
var output: String = "res://output/modular_socket_fixture"

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: " + message)

func settle() -> void:
	for frame in 8: await process_frame
	await physics_frame

func record(id: String, uid: String, at: Array, heading: String, size: float = 1) -> Dictionary:
	return {"asset": id, "uid": uid, "position": at, "direction": heading, "scale": size}

func raw_pose_tests() -> void:
	var frame := Transform3D(Basis(Vector3.UP, .61).scaled(Vector3.ONE * 1.75), Vector3(3, 2, -5))
	var local := Transform3D(Basis(Vector3.RIGHT, .32), Vector3(2, 0, 0))
	var result: Dictionary = Plan.socket_transform(frame, local, .75)
	check(result["ok"] and (result["transform"] * local.origin).distance_to(frame.origin) < .0001, "3D solver aligns the endpoint with a rotated and uniformly scaled target.")
	check(result["ok"] and result["transform"].basis.get_scale().is_equal_approx(Vector3.ONE * .75), "The source scale remains explicit and the target is never stretched.")
	for basis in [Basis(Vector3.LEFT, Vector3.UP, Vector3.BACK), Basis(Vector3.ZERO, Vector3.UP, Vector3.BACK), Basis(Vector3.RIGHT * 2, Vector3.UP, Vector3.BACK), Basis(Vector3.RIGHT, Vector3(.2, 1, 0), Vector3.BACK)]:
		check(not Plan.socket_transform(Transform3D(basis, Vector3.ZERO), local, 1)["ok"], "Mirrored, singular, uneven and sheared target frames are rejected.")
	check(not Plan.socket_transform(frame, local, -.5)["ok"], "Negative source scale is rejected.")
	var buckets: Dictionary = Plan.index([
		{"object_uid":"z", "socket":"a", "screen":Vector2(-2,0)},
		{"object_uid":"a", "socket":"b", "screen":Vector2(2,0)},
		{"object_uid":"far", "socket":"a", "screen":Vector2(100,100)}
	])
	var near: Array = Plan.nearby(buckets, Vector2.ZERO, 28)
	check(near.size()==2 and near[0]["object_uid"]=="a", "Equal screen distances resolve by stable object and socket IDs.")
	for pair in [[WALL,DOOR_WALL],[WALL,CORNER],[SCAFFOLD,LADDER],[FENCE,SCREEN]]:
		var a: Dictionary = record(pair[0],"first",[12,4,6],"38",1.4)
		a["tilt"]=[12,-4]
		var b: Dictionary = record(pair[1],"second",[0,0,0],"310",1.4)
		var t: Dictionary = Plan.frames(a,"3d")[1]
		var mate: Dictionary = Plan.solve(b,Plan.frames(b,"3d")[0],t,"3d",Templates.make("3d","blank"),{})
		check(mate["ok"] and Plan.aligned_pair(mate["source"],t,"3d"),"Rotated and tilted measured model end faces mate: "+pair[1])

func frame_on_model(node: Node, frame: Dictionary, mode: String) -> Vector3:
	var offset: Vector3 = Plan.vector(frame["local"]["position"])
	if mode == "3d":
		return node.to_global(offset)
	var at: Vector2 = node.to_global(Vector2(offset.x,offset.y))
	return Vector3(at.x,at.y,frame["point"].z)

func set_module(id: String, heading: String, size: float) -> void:
	studio.select_asset(id)
	studio.direction = heading
	studio.scale_input.set_value_no_signal(size)
	studio.placement_angle = 0
	studio.placement_tilt = Vector2.ZERO

func place(at: Vector2) -> void:
	studio.stroke_cells.clear()
	studio.current().checkpoint()
	studio.paint(at)
	studio.current().finish_checkpoint()

func export_package(name: String) -> void:
	var path: String=output+"/"+name+".zip"
	studio._command("export_portable",null)
	studio.file_dialog.hide()
	studio._file_selected(path)
	check(FileAccess.file_exists(path),"Allowed package exports through the normal command: "+name+" "+studio.status.text)

func capture_socket(mode: String, target: Dictionary) -> void:
	var ui: RefCounted=studio.connector_tools
	var world: Node=studio.worlds[mode]
	if mode=="2d":
		world.camera.position=Vector2(target["point"].x,target["point"].y)
		world.camera.zoom=Vector2.ONE*.72
	else:
		world.target=target["point"]
		world.distance=13
		world.update_camera()
	for size in [Vector2i(1480,900),Vector2i(960,640)]:
		root.size=size
		studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true} if size.x==960 else {})
		if size.x==960:
			studio.workspace_layout.library_toggle.button_pressed=false
		studio.control_settings.cursor_active=true
		await settle()
		studio.control_settings.cursor_position=ui.project(target["point"])
		await settle()
		var markers: Array=studio.overlay.socket_markers
		check(markers.size()==2 and markers[0]["at"].is_equal_approx(markers[1]["at"]) and markers[0]["kind"]=="structure","The live ghost and both annotated endpoints coincide: "+mode+" "+str(size))
		if markers.size()==2 and studio.consumer_shell and studio.consumer_shell.active:
			var area: Rect2=studio.overlay.socket_area
			var target_label: Rect2=studio.overlay.socket_label_rect(markers[0])
			var source_label: Rect2=studio.overlay.socket_label_rect(markers[1])
			check(area.encloses(target_label) and area.encloses(source_label) and not target_label.intersects(source_label),"Both labels fit clear of the Simple drawer and dock: "+mode+" "+str(size))
		var cursor: Vector2=studio.control_settings.cursor_position
		check(Rect2(Vector2.ZERO,studio.canvas.size).grow(-15).has_point(cursor) and Rect2(Vector2.ZERO,Vector2(root.size)).grow(-15).has_point(studio.canvas.global_position+cursor),"The socket preview stays inside the visible canvas: "+mode+" "+str(size))
		RenderingServer.force_draw(false)
		RenderingServer.force_draw(false)
		check(root.get_texture().get_image().save_png(output+"/socket_%s_%d.png"%[mode,size.x])==OK,"Capture the rendered joint and affordance: "+mode+" "+str(size))
		ui.enabled.button_pressed=false
		await settle()
		check(studio.overlay.socket_markers.is_empty(),"Switching off snapping clears its markers: "+mode)
		ui.enabled.button_pressed=true
	studio.photo_tools.start()
	await settle()
	check(studio.worlds[mode].exploration.photo.active and studio.overlay.socket_markers.is_empty(),"Photo mode excludes the socket overlay: "+mode)
	studio.photo_tools.stop()
	studio.set_walking(true)
	await settle()
	check(not studio.overlay.visible,"Walking hides editor socket affordances: "+mode)
	studio.set_walking(false)
	root.size=Vector2i(1480,900)
	studio.accessibility_settings.restore({})
	studio.control_settings.cursor_active=false
	await settle()

func keyboard_targets(target: Dictionary) -> void:
	var world: Node=studio.worlds["3d"]
	var ui: RefCounted=studio.connector_tools
	var controls: RefCounted=studio.control_settings
	world.distance=240
	world.update_camera()
	await settle()
	var at: Vector2=ui.project(target["point"])
	controls.cursor_active=true
	controls.cursor_position=at
	await settle()
	var before: Dictionary=studio.current().data.duplicate(true)
	var blocked: Dictionary=studio.placement(at)
	check(blocked.get("socket",{}).get("blocked",false) and ui.choices.size()>=2,"Occupied nearest stays blocked with multiple reachable alternates. %s (%d alternates)"%[blocked.get("socket",{}).get("reason",""),ui.choices.size()])
	if ui.choices.size()<2:
		controls.cursor_active=false
		return
	var focus: Control=root.gui_get_focus_owner()
	if focus: focus.release_focus()
	var free_target: Dictionary={}
	for step in [1,-1]:
		var command: String="connector_next" if step==1 else "connector_previous"
		var event:=InputEventKey.new()
		event.keycode=KEY_J if step==1 else KEY_K
		event.physical_keycode=event.keycode
		event.ctrl_pressed=true
		event.alt_pressed=true
		event.pressed=true
		check(controls.assign(command,0,controls.event_code(event)).is_empty(),"Socket traversal can be rebound: "+command)
		var prior: String=ui.selected
		if not controls.input(event):
			studio._unhandled_key_input(event)
		await process_frame
		var alternate: Dictionary=studio.placement(at).get("socket",{})
		check(alternate.get("ok",false) and ui.selected!=prior and Plan.socket_key(alternate["target"])!=Plan.socket_key(target) and studio.current().data==before,"The actual keyboard binding previews another free endpoint without committing: %s (%s → %s, %s)"%[command,prior,ui.selected,alternate.get("reason","")])
		if alternate.get("ok",false):
			free_target=alternate["target"]
		controls.clear_binding(command,0)
	if not free_target.is_empty():
		ui.selected=""
		# Keep both verified alternatives within the search radius after moving
		# the cursor off the occupied socket in either workspace layout.
		world.distance=520
		world.update_camera()
		await settle()
		var free_at: Vector2=ui.project(free_target["point"])
		controls.cursor_position=free_at
		await settle()
		var automatic: Dictionary=studio.placement(free_at).get("socket",{})
		check(automatic.get("ok",false) and ui.choices.size()>=2,"A free default target and another candidate are reachable. %s (%d alternates)"%[automatic.get("reason",""),ui.choices.size()])
		if automatic.get("ok",false) and ui.choices.size()>=2:
			var expected: String=Plan.socket_key(automatic["target"])
			ui.cycle(1)
			var next: Dictionary=studio.placement(free_at).get("socket",{})
			check(next.get("ok",false) and Plan.socket_key(next["target"])!=expected,"Next starts from the visible default and advances on the first press.")
		world.distance=240
		world.update_camera()
	ui.selected=""
	controls.cursor_active=false

func socket_fixture(mode: String, target_asset: String, source_asset: String, heading: String) -> void:
	studio.switch_mode(mode)
	var doc:=Doc.new()
	doc.data=Templates.make(mode,"blank")
	studio.documents[mode]=doc
	var target: Dictionary=record(target_asset,"anchor",[0,0,0],heading,1.15)
	if mode=="2d": target["angle"]=8
	else: target["tilt"]=[0,0]
	doc.data["objects"].append(target)
	studio.changed()
	await settle()
	var ui: RefCounted=studio.connector_tools
	studio._command("connectors",null)
	check(studio.arrange_tools.panel.is_visible_in_tree(), "The socket command opens Arrange in the current workspace: "+mode)
	ui.enabled.button_pressed=true
	ui.utility.button_pressed=false
	set_module(source_asset,heading,1.15)
	var target_frame: Dictionary=Plan.frames(target,mode)[1]
	var at: Vector2=ui.project(target_frame["point"])
	var proposed: Dictionary=studio.placement(at)
	check(proposed.get("socket",{}).get("ok",false), "Normal placement finds a calibrated open endpoint: "+mode+" "+str(proposed.get("socket",{}).get("reason","")))
	if not proposed.get("socket",{}).get("ok",false): return
	var target_node: Node=studio.worlds[mode].instances["anchor"]
	check(frame_on_model(target_node,target_frame,mode).distance_to(target_frame["point"])<.001, "Target socket projection follows the actual asset node: "+mode)
	if mode=="3d":
		var point: Vector3=target_frame["point"]
		var blocked: Dictionary=record(FENCE,"blocker",[point.x,point.y-.5,point.z],"0")
		doc.data["objects"].append(blocked)
		studio.changed()
		await settle()
		var denied: Dictionary=studio.placement(at)
		check(denied.get("socket",{}).get("blocked",false) and denied["socket"]["reason"].contains("blocks"),"Live colliders refuse an obstructed joint even with an unclaimed socket.")
		doc.data["objects"].erase(blocked)
		studio.changed()
		await settle()
	if "--capture" in OS.get_cmdline_user_args() and target_asset in [GLORIA_RISE,WALL]:
		await capture_socket(mode,target_frame)
		at=ui.project(target_frame["point"])
		proposed=studio.placement(at)
	var snapshot: Dictionary=doc.data.duplicate(true)
	place(at)
	await settle()
	check(doc.data["objects"].size()==2 and doc.data.get("connections",[]).size()==1, "The normal paint path places and records one structural connection: "+mode)
	if doc.data["objects"].size()!=2 or doc.data.get("connections",[]).size()!=1: return
	var copy: Dictionary=doc.data["objects"][1]
	var source_frame: Dictionary=Plan.frame_by_id(Plan.frames(copy,mode),proposed["socket"]["source"]["socket"])
	var instance: Node=studio.worlds[mode].instances[copy["uid"]]
	check(copy["position"]==proposed["position"] and Plan.aligned_pair(source_frame,target_frame,mode) and frame_on_model(instance,source_frame,mode).distance_to(target_frame["point"])<.08,"Committed scene joins at the exact previewed pose: "+mode)
	var joined: Dictionary=doc.data.duplicate(true)
	var previous_count: int=doc.data["objects"].size()
	place(at)
	check(doc.data["objects"].size()==previous_count and studio.status.text.contains("already"),"An occupied endpoint blocks paint even when overlap normally allows placement: "+mode)
	if target_asset==WALL:
		await keyboard_targets(target_frame)
	studio._command("undo",null)
	# A blocked click may create an empty editor gesture in creative mode.
	if doc.data==joined: studio._command("undo",null)
	check(doc.data==snapshot,"Undo removes the joint and the object in one construction change: "+mode)
	studio._command("redo",null)
	check(doc.data==joined,"Redo restores the exact socket link and object IDs: "+mode)
	studio.selected_uid="anchor"
	studio.selected_uids.assign(["anchor",copy["uid"]])
	studio.duplicate_selection()
	check(doc.data["objects"].size()==4 and doc.data["connections"].size()==2, "Duplicate remaps both ends of an internal joint: "+mode)
	if doc.data["connections"].size()==2:
		var link: Dictionary=doc.data["connections"][1]
		check(link["uid"]!=joined["connections"][0]["uid"] and link["from"]["object_uid"] in studio.selected_uids and link["to"]["object_uid"] in studio.selected_uids,"Copied connections never refer back to the original pair: "+mode)
	studio._command("undo",null)
	doc.checkpoint()
	doc.object("anchor")["scale"]=1.45
	studio.changed()
	doc.finish_checkpoint()
	check(doc.data.get("connections",[]).is_empty() and doc.object(copy["uid"])["scale"]==copy["scale"],"Scaling one part detaches the joint without stretching its mate: "+mode)
	studio._command("undo",null)
	check(doc.data==joined, "Undo restores the original calibrated joint: "+mode)
	var path: String=output+"/joint_"+mode
	check(studio.write_project(path+".isocity.json",false), "Linked parts save through the normal project writer: "+mode)
	var repair:=Repair.new(studio.library)
	var opened: Dictionary=repair.read(path+".isocity.json")
	check(opened["ok"] and repair.issues.is_empty() and opened["content"]["documents"][mode]["connections"]==joined["connections"],"Reopening preserves links and their scoped identities: "+mode)
	if "--packages" in OS.get_cmdline_user_args():
		if target_asset==GLORIA_RISE:
			export_package("socket_2d")
		elif target_asset==WALL:
			var path_to_zip: String=output+"/restricted_swat.zip"
			studio._command("export_portable",null)
			studio.file_dialog.hide()
			studio._file_selected(path_to_zip)
			check(not FileAccess.file_exists(path_to_zip) and studio.status.text.contains("restricts redistributing"),"Portable export rejects the restricted SWAT sources.")
		elif target_asset in [SCAFFOLD,FENCE] and studio.library.assets[target_asset].get("data",{}).get("source_export_allowed",true) and studio.library.assets[source_asset].get("data",{}).get("source_export_allowed",true):
			export_package("socket_"+target_asset.get_file().to_lower())
	var protected: Dictionary=joined.duplicate(true)
	var rect: Rect2=Protection.object_rect(target,mode,studio.library)
	protected["protected_areas"]=[{"uid":"plot","name":"Socket plot","owner":"host","rect":[rect.position.x-2,rect.position.y-2,maxf(1,rect.size.x+4),maxf(1,rect.size.y+4)]}]
	var after: Dictionary=protected.duplicate(true)
	after["connections"]=[]
	var before_state: Dictionary={"2d":Templates.make("2d","blank"),"3d":Templates.make("3d","blank")}
	before_state[mode]=protected
	var after_state: Dictionary=before_state.duplicate(false)
	after_state[mode]=after
	check(Protection.allowed(before_state,after_state,"guest",studio.library).contains("Protected area"),"The authority protects both endpoints even when only the link changes: "+mode)
	ui.enabled.button_pressed=false

func pipe_and_assembly() -> void:
	studio.switch_mode("2d")
	var doc:=Doc.new()
	doc.data=Templates.make("2d","blank")
	studio.documents["2d"]=doc
	var target: Dictionary=record(PIPE,"pipe",[0,0,0],"SE")
	doc.data["objects"]=[target]
	if "--packages" in OS.get_cmdline_user_args():
		studio.economy_tools.pauses["2d"]=true
		doc.economy_library=studio.library
		doc.content_library=studio.library
		doc.data["economy"]={"enabled":true,"starting_cash":1000000,"period_seconds":60}
		doc.data["economy_account"]=Economy.fresh_account(doc.data,studio.library)
	studio.changed()
	await settle()
	var ui: RefCounted=studio.connector_tools
	ui.enabled.button_pressed=true
	ui.utility.button_pressed=false
	set_module(PIPE,"SE",1)
	var target_frame: Dictionary=Plan.frames(target,"2d")[1]
	var at: Vector2=ui.project(target_frame["point"])
	var info: Dictionary=studio.placement(at)
	check(info.get("socket",{}).get("ok",false),"The measured pipe flanges align in their prepared view.")
	if not info.get("socket",{}).get("ok",false): return
	place(at)
	check(doc.data["objects"].size()==2 and doc.data.get("connections",[]).is_empty(),"Visual pipe snapping leaves service connections opt-in.")
	studio._command("undo",null)
	set_module(SMALL_PIPE,"SE",1)
	info=studio.placement(at)
	check(info.get("socket",{}).get("blocked",false) and info["socket"]["reason"].contains("sizes"),"A visually nearby pipe with a different diameter is blocked.")
	set_module(PIPE,"E",1)
	info=studio.placement(at)
	check(not info.get("socket",{}).get("ok",false) and ui.status.text.contains("no calibrated"),"Changing the prepared source view invalidates the socket mapping.")
	set_module(PIPE,"SE",1)
	ui.utility.button_pressed=true
	info=studio.placement(at)
	place(at)
	check(doc.data.get("connections",[]).size()==1 and doc.data["connections"][0]["kind"]=="water","Explicit pipe opt-in records the compatible water connection.")
	if doc.data.get("connections",[]).size()!=1: return
	var built: Dictionary=doc.data["objects"][1]
	var link: Dictionary=doc.data["connections"][0]
	doc.checkpoint()
	doc.object(built["uid"])["direction"]="E"
	studio.changed()
	doc.finish_checkpoint()
	check(doc.data["connections"].is_empty(),"Changing a placed source view detaches the stored edge.")
	studio._command("undo",null)
	check(doc.data["connections"]==[link],"Undo restores the calibrated source view and semantic edge.")
	studio.selected_uid="pipe"
	studio.selected_uids.assign(["pipe",built["uid"]])
	studio._command("blueprints",null)
	studio.blueprint_tools.capture_assembly()
	var proposal: Dictionary=studio.blueprint_tools.entry()
	check(proposal.get("connections",[]).size()==1,"The normal assembly capture includes the internal pipe connection.")
	if proposal.is_empty(): return
	var moved: Dictionary=Blueprint.moved_assembly(proposal,[1400,1000,0],"2d")
	doc.data["blueprints"]=[moved]
	var result: Dictionary=Blueprint.construct(doc.data,[moved["uid"]],studio.library)
	check(result["ok"] and result["data"]["connections"].size()==2,"Assembly construction resolves and saves its copied internal pipe edge. "+result.get("reason",""))
	if result["ok"]:
		var copied: Dictionary=result["data"]["connections"][1]
		check(copied["uid"]!=link["uid"] and copied["from"]["object_uid"]!=link["from"]["object_uid"] and copied["to"]["object_uid"]!=link["to"]["object_uid"],"Assembly commit remaps both internal endpoints and the edge identity.")
		var pending: Dictionary=doc.data.duplicate(true)
		var blueprint: RefCounted=studio.blueprint_tools
		blueprint.review([moved["uid"]])
		check(not blueprint.reviewed.is_empty(),"The ordinary review accepts the internal pipe link.")
		if "--packages" in OS.get_cmdline_user_args():
			export_package("pipe_internal_pending")
		blueprint.construct(false)
		check(doc.data.get("connections",[]).size()==2 and doc.data.get("blueprints",[]).is_empty(),"One reviewed commit builds the internal pipe joint.")
		if "--packages" in OS.get_cmdline_user_args():
			check(doc.data["economy_account"]==result["quote"]["account"],"Commit charges the quoted account exactly once.")
			export_package("pipe_internal_built")
		var committed: Dictionary=doc.data.duplicate(true)
		studio._command("undo",null)
		check(doc.data==pending,"Undo restores the deferred assembly, both original endpoints and the account.")
		studio._command("redo",null)
		check(doc.data==committed,"Redo restores the same copied identities and account.")
		studio._command("undo",null)
	var outside: Dictionary=doc.data.duplicate(true)
	outside["objects"]=[target]
	outside["connections"]=[]
	var external: Dictionary=link.duplicate(true)
	external["to"]["external"]=true
	outside["blueprints"]=[{"kind":"assembly","version":1,"uid":"attach","name":"Required pipe tie-in","objects":[built],"roads":[],"connections":[external]}]
	var before: Dictionary=outside.duplicate(true)
	result=Blueprint.construct(outside,["attach"],studio.library)
	check(result["ok"] and result["data"]["connections"].size()==1 and result["data"]["connections"][0]["to"]["object_uid"]=="pipe" and outside==before,"Explicit external socket resolves to the original city endpoint without mutating review source. "+result.get("reason",""))
	var locked: Dictionary=outside.duplicate(true)
	locked["objects"][0]["locked"]=true
	check(not Blueprint.construct(locked,["attach"],studio.library)["ok"],"A locked required socket blocks the entire assembly.")
	var missing: Dictionary=outside.duplicate(true)
	missing["objects"]=[]
	check(not Blueprint.construct(missing,["attach"],studio.library)["ok"],"A missing external object blocks the entire assembly.")
	outside["blueprints"][0]["connections"][0]["to"].erase("external")
	check(not Blueprint.construct(outside,["attach"],studio.library)["ok"],"An undeclared external socket cannot bind by identity coincidence.")
	await external_workflow(doc,built)
	ui.utility.button_pressed=false
	ui.enabled.button_pressed=false

func external_workflow(doc: RefCounted, built: Dictionary) -> void:
	var blueprint: RefCounted=studio.blueprint_tools
	doc.data["blueprints"]=[]
	studio.selected_uid=built["uid"]
	studio.selected_uids.assign([built["uid"]])
	blueprint.capture_assembly()
	check(blueprint.entry().get("connections",[]).is_empty(),"Ordinary copy omits a link leaving the selected objects.")
	blueprint.discard(false)
	blueprint.require_sockets.button_pressed=true
	blueprint.capture_assembly()
	blueprint.require_sockets.button_pressed=false
	var proposal: Dictionary=blueprint.entry()
	check(proposal.get("connections",[]).size()==1 and proposal["connections"][0]["to"].get("external",false),"Explicit capture marks the required existing socket.")
	if proposal.get("connections",[]).is_empty(): return
	var uid: String=proposal["uid"]
	var occupied: Dictionary=doc.data.duplicate(true)
	blueprint.review([uid])
	check(blueprint.reviewed.is_empty() and blueprint.review_label.text.contains("free"),"Review refuses a still occupied external socket.")
	blueprint.construct(false)
	check(doc.data==occupied,"Failed external construction preserves the city, proposal and account.")
	studio._command("remove",null)
	await settle()
	check(doc.object(built["uid"]).is_empty() and doc.data.get("connections",[]).is_empty(),"Removing the original part frees its socket for the proposed replacement.")
	blueprint.review([uid])
	check(not blueprint.reviewed.is_empty() and blueprint.review_label.text.contains("one existing socket"),"Review names the external dependency after the socket becomes free. "+blueprint.review_label.text)
	if blueprint.reviewed.is_empty(): return
	var pending: Dictionary=doc.data.duplicate(true)
	if "--packages" in OS.get_cmdline_user_args(): export_package("pipe_external_pending")
	blueprint.construct(false)
	check(doc.data.get("connections",[]).size()==1 and doc.data["connections"][0]["to"]["object_uid"]=="pipe" and doc.data["blueprints"].is_empty(),"Ordinary commit attaches the remapped part to the original city socket.")
	if "--packages" in OS.get_cmdline_user_args(): export_package("pipe_external_built")
	var committed: Dictionary=doc.data.duplicate(true)
	studio._command("undo",null)
	check(doc.data==pending,"Undo releases the original city socket and restores the deferred external reference.")
	studio._command("redo",null)
	check(doc.data==committed,"Redo restores the exact external connection and account.")

func run() -> void:
	if OS.has_environment("ISOCITY_SOCKET_FIXTURE_OUTPUT"):
		output=OS.get_environment("ISOCITY_SOCKET_FIXTURE_OUTPUT")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	studio=load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled=false
	root.add_child(studio)
	await settle()
	if studio.consumer_shell: studio.consumer_shell.dismiss_welcome()
	raw_pose_tests()
	await socket_fixture("2d",GLORIA_RISE,GLORIA_RISE,"SE")
	await socket_fixture("2d",GLORIA_FALL,GLORIA_FALL,"SE")
	await socket_fixture("3d",WALL,DOOR_WALL,"32")
	await socket_fixture("3d",SCAFFOLD,LADDER,"24")
	await socket_fixture("3d",FENCE,SCREEN,"50")
	await pipe_and_assembly()
	studio.free()
	await settle()
	print("MODULAR SOCKETS: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
