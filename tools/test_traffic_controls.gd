extends SceneTree

const Plan = preload("res://scripts/builder/traffic_plan.gd")
const Signals = preload("res://scripts/builder/traffic_control_plan.gd")
const Transit = preload("res://scripts/builder/transit_runtime.gd")
const TransitPlan = preload("res://scripts/builder/transit_plan.gd")
const Services = preload("res://scripts/builder/service_runtime.gd")
const Instance = preload("res://scripts/builder/asset_instance.gd")
const Gates = preload("res://scripts/builder/traffic_junctions.gd")
const Doc = preload("res://scripts/builder/document.gd")
const Templates = preload("res://scripts/builder/templates.gd")
const Repair = preload("res://scripts/builder/project_repair.gd")
const Protection = preload("res://scripts/builder/cooperative_plan.gd")
const TIMING = {"green": 4.0, "walk": 3.0, "clear": 2.0}

var checks: int = 0
var failures: int = 0
var studio: Control
var output: String = "res://output/traffic_control_fixture"

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + description)

func settle() -> void:
	for frame in 8:
		await process_frame
	await physics_frame

func road_grid(data: Dictionary) -> void:
	for cell in [Vector2i.ZERO, Vector2i(1,0), Vector2i(0,1), Vector2i(-1,0), Vector2i(0,-1)]:
		data["roads"].append({"cell": [cell.x,cell.y], "crossing": cell==Vector2i.ZERO})

func placed(mode: String, asset: String, uid: String, point: Vector2, direction: String) -> Dictionary:
	return {"asset": asset, "uid": uid, "position": Plan.world(Plan.center(Vector2i.ZERO,mode)+point,mode), "scale": 1, "direction": direction}

func control(kind: String, side: int) -> Dictionary:
	var result: Dictionary = {"kind": kind, "cell": [0,0], "side": side}
	if kind == "signal":
		result["timing"] = TIMING.duplicate()
	return result

func fixture(mode: String) -> Dictionary:
	var data: Dictionary = Templates.make(mode,"blank")
	data["roads"]=[]
	road_grid(data)
	var id: String = "2d:Traffic_Light" if mode=="2d" else "3d:HanX_Traffic/Traffic_Light_Red"
	var x: Dictionary = placed(mode,id,"east",Vector2(4.2,-4.6),"SE" if mode=="2d" else "90")
	var y: Dictionary = placed(mode,id,"south",Vector2(-4.6,4.2),"SW" if mode=="2d" else "0")
	x["traffic_control"] = control("signal",0)
	y["traffic_control"] = control("signal",1)
	data["objects"] = [x,y]
	return data

func plan_tests(mode: String) -> void:
	var data: Dictionary = fixture(mode)
	var plan: Dictionary = Plan.build(data)
	check(plan["controls"]["active"]=={"east":"0,0","south":"0,0"} and plan["edges"].size()==8,"Both facing-validated heads share one four-way junction: "+mode)
	check(Signals.valid(control("signal",0)) and not Signals.valid(control("stop",4)) and not Signals.valid({"kind":"signal","cell":[0,0],"side":1,"timing":{"green":4,"clear":0,"walk":4}}),"Bindings require bounded timing and integral valid cell and side.")
	var gates := Gates.new()
	gates.synchronize(plan,0)
	for expected in [[0.0,"red"],[2.1,"x"],[6.1,"amber_x"],[7.1,"red"],[9.1,"y"],[13.1,"amber_y"],[14.1,"red"],[16.1,"walk"],[19.1,"red"]]:
		check(gates.phase(plan,"0,0",expected[0])==expected[1],"The shared phase sequence includes "+str(expected)+" in "+mode)
	check(not gates.request(plan,"bus","0,0",2.1,false,"0,1")["allowed"],"The perpendicular bus waits through the car green.")
	check(not gates.request(plan,"car","0,0",2.2,true,"1,0")["allowed"],"A pedestrian already in the intersection blocks even a green approach.")
	check(gates.request(plan,"car","0,0",2.3,false,"1,0")["allowed"],"The car enters only once the green approach clears.")
	check(not gates.request(plan,"service","0,0",2.3,false,"-1,0")["allowed"],"Opposing green turns still serialize at the junction.")
	check(gates.phase(plan,"0,0",9.1)=="red" and not gates.request(plan,"bus","0,0",9.1,false,"0,1")["allowed"],"An overrun keeps every head red while the original car still owns the junction.")
	check(gates.request(plan,"car","0,0",9.1,true,"1,0")["allowed"],"The reserved car can clear after its green ends.")
	gates.release("car")
	check(gates.request(plan,"bus","0,0",9.2,false,"0,1")["allowed"],"The bus moves on its own phase after the previous vehicle clears.")
	gates.release("bus")
	check(not gates.request(plan,"service","0,0",16.2,false,"-1,0")["allowed"],"All vehicle types wait during the pedestrian phase.")
	var no_road: Dictionary = data.duplicate(true)
	no_road["roads"]=[]
	check(Plan.build(no_road)["controls"]["issues"]["east"].contains("absent"),"Erasing the road keeps its binding dormant.")
	check(Signals.nearest(data["objects"][0],{},mode,Vector2.ZERO,TIMING)["reason"].contains("No road"),"A placed signal with no nearby road receives a binding diagnosis.")
	check(Plan.build(data)["controls"]["active"].size()==2,"Restoring the same road cells reactivates existing bindings.")
	var turned: Dictionary = data.duplicate(true)
	turned["objects"][0]["direction"]="SW" if mode=="2d" else "0"
	check(Plan.build(turned)["controls"]["issues"]["east"].contains("faces"),"Turning the artwork away disables its stored approach.")
	var conflict: Dictionary = data.duplicate(true)
	conflict["objects"][1]["traffic_control"]["timing"]["green"]=8
	var bad: Dictionary = Plan.build(conflict)["controls"]
	check(bad["active"].is_empty() and bad["issues"].size()==2,"Conflicting signal timings fall back as one unit.")
	gates.release("service")
	var gone: Dictionary = data.duplicate(true)
	gone["objects"]=[]
	var legacy: Dictionary = Plan.build(gone)
	gates.synchronize(legacy,17.0)
	check(not gates.request(legacy,"late","0,0",17.1,false,"1,0")["allowed"] and gates.phase(legacy,"0,0",17.1)=="red","Deleting signal heads mid-phase enforces an all-red clearance.")
	check(gates.phase(legacy,"0,0",19.1).is_empty() and not gates.request(legacy,"late","0,0",19.1,false,"1,0")["allowed"],"The original all-way stop returns after clearance.")
	check(gates.request(legacy,"late","0,0",22.6,false,"1,0")["allowed"],"Legacy traffic moves after the complete stop and pedestrian window.")

func signs() -> void:
	var data: Dictionary = fixture("3d")
	var stop: Dictionary = placed("3d","3d:HanX_Traffic/Sign_Stop","stop",Vector2(4.1,-4.1),"90")
	stop["traffic_control"]=control("stop",0)
	var give: Dictionary=placed("3d","3d:HanX_Traffic/Sign_Yield","yield",Vector2(-4.1,4.1),"0")
	give["traffic_control"]=control("yield",1)
	data["objects"]=[stop,give]
	var plan: Dictionary=Plan.build(data)
	check(plan["controls"]["sections"]["0,0"]["approaches"]=={"1,0":"stop","0,1":"yield"},"Stop and yield attach to individual approaches.")
	var gates:=Gates.new()
	check(gates.request(plan,"through","0,0",3,false,"-1,0")["allowed"],"An unsigned approach can enter a free junction without an artificial stop.")
	check(not gates.request(plan,"stop","0,0",3,false,"1,0")["allowed"] and not gates.request(plan,"yield","0,0",3,false,"0,1")["allowed"],"Stop and yield both obey the existing owner.")
	gates.release("through")
	check(gates.request(plan,"yield","0,0",3.1,false,"0,1")["allowed"],"Yield can proceed while a separate mandatory stop is still running.")
	gates.release("yield")
	check(gates.request(plan,"stop","0,0",4.1,false,"1,0")["allowed"],"The signed stop waits for its full stop interval.")
	check(not gates.request(plan,"aged","0,0",4.2,false,"0,1")["allowed"],"The next yield enters the waiting queue.")
	gates.release("stop")
	check(not gates.request(plan,"fresh","0,0",13,false,"-1,0")["allowed"] and gates.request(plan,"aged","0,0",13,false,"0,1")["allowed"],"An aged yield cannot starve behind an unlimited stream of through traffic.")
	var contradiction: Dictionary=give.duplicate(true)
	contradiction["direction"]="90"
	contradiction["traffic_control"]=control("yield",0)
	data["objects"]=[stop,contradiction]
	check(Plan.build(data)["controls"]["active"].is_empty(),"Stop and yield on one approach are diagnosed as contradictory.")
	for mode in ["2d","3d"]:
		data=fixture(mode)
		var id: String="2d:One_Way_Sign" if mode=="2d" else "3d:HanX_Traffic/Sign_One_Way"
		var sign: Dictionary=placed(mode,id,"one_way",Vector2(4,-4),"SE" if mode=="2d" else "0")
		var side: int=Signals.facing(sign,mode)
		var step: Vector2i=Plan.Roads.STEPS[side]
		sign["traffic_control"]=control("one_way",side)
		data["objects"]=[sign]
		data["roads"]=[{"cell":[-step.x,-step.y]},{"cell":[0,0]},{"cell":[step.x,step.y]}]
		plan=Plan.build(data)
		var from: String=Plan.Roads.key(-step)
		var to: String=Plan.Roads.key(step)
		check(Plan.route(plan,from,to).size()==3 and Plan.route(plan,to,from).is_empty(),"Routing follows the reviewed one-way arrow and refuses reverse travel: "+mode)
		check(plan["sections"]["0,0"]["neighbors"].size()==2 and Plan.exits(plan,"0,0")==[to],"Direction constrains travel without changing road geometry: "+mode)

func shared_runtime_checks(mode: String, manager: Node) -> void:
	var people: Array[Vector2]=[]
	manager.route_queue.configure(manager.plan,manager.obstacles)
	var service:=Services.new()
	service.add_child(service.helper)
	service.traffic=manager
	service.dimension=mode
	service.dispatch.plan={"network":manager.plan}
	var crew: Dictionary={"vehicle":{"id":"crew"},"job":{"reason":""}}
	var bus:=Transit.new()
	bus.add_child(bus.helper)
	bus.traffic=manager
	bus.dimension=mode
	bus.helper.dimension=mode
	bus.helper.library=studio.library
	bus.passengers.plan={"network":manager.plan,"settings":{"speed":4}}
	bus.passengers.vehicles["bus"]={"phase":"driving"}
	var route:=PackedStringArray(["0,1","0,0","0,-1"])
	var segments: Array=TransitPlan.segments(manager.plan,route,{"dock":Plan.center(Vector2i(0,1),mode)},{"dock":Plan.center(Vector2i(0,-1),mode)})
	var turn: Dictionary=segments[2]
	var id: String=TransitPlan.definitions()["vehicles"][mode]
	var actor: Node=Instance.make(studio.library,id,mode)
	var label: Node=Label.new() if mode=="2d" else Label3D.new()
	var world: Node=studio.worlds[mode]
	world.objects.add_child(actor)
	world.objects.add_child(label)
	var vehicle: Dictionary={"id":"bus","asset":id,"actor":actor,"point":turn["points"][0],"heading":Vector2.UP,"speed":0.0}
	var entry: Dictionary={"vehicle":vehicle,"segments":segments,"label":label,"segment":2,"distance":0.0,"gate_open":false,"status":""}
	var epoch: float=manager.gates.phase_start["0,0"]
	manager.junction_time=epoch+2.2
	bus.drive(entry,.1,people)
	check(turn["approach"]=="0,1" and not entry["gate_open"] and entry["status"].contains("signal"),"The actual bus driver reads the red phase for its itinerary's incoming lane.")
	var road: Dictionary=manager.plan["edges"]["1,0>0,0"]
	var car: Dictionary={"id":"car","phase":"edge","from":"1,0","to":"0,0","bay":"","stops":0,"point":road["points"][-1],"heading":road["axis"],"status":""}
	check(manager.finish_segment(car,people) and manager.gates.owners.get("0,0")=="car" and car["phase"]=="turn","The ordinary traffic driver acquires the same junction on its green.")
	manager.junction_time=epoch+9.2
	bus.drive(entry,.1,people)
	check(not entry["gate_open"] and not service.gate_request(crew,"0,0",people,"0,1"),"The bus and service driver both wait for the car that entered on the previous phase.")
	manager.gates.release("car")
	bus.drive(entry,.1,people)
	check(entry["gate_open"] and entry["distance"]>0 and manager.gates.owners.get("0,0")=="bus","The bus begins its actual turn after the prior owner clears.")
	bus.release_gate(entry)
	check(service.gate_request(crew,"0,0",people,"0,1") and manager.gates.owners.get("0,0")=="crew","The service vehicle acquires the same shared reservation after the bus.")
	service.release_gate(crew)
	bus.free()
	service.free()
	actor.free()
	label.free()

func capture_signals(mode: String, manager: Node, ui: RefCounted) -> void:
	var world: Node=studio.worlds[mode]
	var epoch: float=manager.gates.phase_start["0,0"]
	if mode=="2d":
		world.camera.position=Vector2(0,8)
		world.camera.zoom=Vector2.ONE*1.4
	else:
		world.target=Vector3.ZERO
		world.distance=31
		world.yaw=45
		world.update_camera()
	for dimensions in [Vector2i(1480,900),Vector2i(960,640)]:
		ui.binding_action.release_focus()
		root.size=dimensions
		studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true} if dimensions.x==960 else {})
		if dimensions.x==960:
			studio.workspace_layout.library_toggle.button_pressed=false
		await settle()
		var compact_simple: bool=dimensions.x==960 and studio.consumer_shell and studio.consumer_shell.active
		if mode=="2d":
			world.camera.position=Vector2(140 if compact_simple else 0,8)
		else:
			world.target=world.camera.global_basis.x*9 if compact_simple else Vector3.ZERO
			world.update_camera()
		manager.junction_time=epoch+2.2
		manager.step(.01)
		ui.refresh_control()
		ui.binding_action.grab_focus()
		await settle()
		var rect: Rect2=ui.binding_action.get_global_rect()
		check(ui.binding_action.has_focus() and ui.panel.get_global_rect().encloses(rect) and Rect2(Vector2.ZERO,Vector2(root.size)).encloses(rect),"Keyboard focus reveals the full road binding action: "+mode+" "+str(dimensions)+" · "+str(root.gui_get_focus_owner())+" · "+str(rect))
		check(manager.signal_views.heads["east"]["color"]=="green" and manager.signal_views.heads["south"]["color"]=="red","The native views display the mutually exclusive authored heads.")
		RenderingServer.force_draw(false)
		RenderingServer.force_draw(false)
		check(root.get_texture().get_image().save_png(output+"/signal_%s_%d.png"%[mode,dimensions.x])==OK,"Captured the native sign artwork and accessible controls.")
	root.size=Vector2i(1480,900)
	studio.accessibility_settings.restore({})
	await settle()

func workflow(mode: String) -> void:
	studio.switch_mode(mode)
	var doc:=Doc.new()
	doc.data=fixture(mode)
	var original: Dictionary=doc.data.duplicate(true)
	for item in doc.data["objects"]:
		item.erase("traffic_control")
	studio.documents[mode]=doc
	studio.changed()
	await settle()
	var ui: RefCounted=studio.traffic_tools
	studio.selected_uid="east"
	studio.selected_uids.assign(["east"])
	studio._command("traffic",null)
	await settle()
	for key in TIMING:
		ui.timing_fields[key].set_value_no_signal(TIMING[key])
	ui.binding_action.pressed.emit()
	await settle()
	check(doc.object("east").get("traffic_control",{})==original["objects"][0]["traffic_control"],"The actual editor binds the east signal using its placed facing: "+mode+" "+studio.status.text)
	if not doc.object("east").has("traffic_control"):
		return
	var manager: Node=ui.managers[mode]
	check(not manager.plan["settings"]["enabled"] and manager.signal_views.heads.has("east"),"Bound heads animate even with ordinary traffic switched off: "+mode)
	var epoch: float=manager.gates.phase_start["0,0"]
	manager.junction_time=epoch+2.2
	manager.step(.01)
	var head: Dictionary=manager.signal_views.heads["east"]
	check(head["color"]=="green","The runtime shows the active green state on supplied artwork: "+mode)
	if mode=="2d":
		check(head["node"].get_node("Sprite2D").frame==1 and not head["node"].playing,"The native frame is tied to the shared phase rather than the automatic strip animation.")
	else:
		check(is_instance_valid(head.get("variant")) and not head["model"].visible,"The reviewed matching model switches visibly to the active color.")
	var center: Vector2=Plan.center(Vector2i.ZERO,mode)
	var before_crossing: Vector2=center+Vector2(3.8,0)
	var after_crossing: Vector2=center+Vector2(3.5,0)
	check(not manager.pedestrian_can_enter(before_crossing,after_crossing),"New pedestrian entry waits during the vehicle phase.")
	check(manager.pedestrian_can_enter(after_crossing,before_crossing),"An already-entered pedestrian can clear the crossing.")
	check(not Plan.crossing_occupied(manager.plan,"0,0",[before_crossing]) and Plan.crossing_occupied(manager.plan,"0,0",[after_crossing]),"A sidewalk pedestrian does not obstruct the vehicles it is waiting for.")
	manager.junction_time=epoch+16.2
	manager.step(.01)
	check(manager.pedestrian_can_enter(before_crossing,after_crossing) and head["color"]=="red","The shared walk phase stops the signals and admits pedestrians.")
	studio.selected_uid="south"
	studio.selected_uids.assign(["south"])
	await settle()
	ui.refresh_control()
	for key in TIMING:
		ui.timing_fields[key].set_value_no_signal(TIMING[key])
	ui.binding_action.pressed.emit()
	await settle()
	check(doc.object("south").has("traffic_control"),"The normal control binds the perpendicular head to the same phase plan.")
	if doc.object("south").has("traffic_control"):
		shared_runtime_checks(mode,manager)
	studio.selected_uid="east"
	studio.selected_uids.assign(["east"])
	await settle()
	ui.refresh_control()
	if "--capture" in OS.get_cmdline_user_args() and doc.object("south").has("traffic_control"):
		await capture_signals(mode,manager,ui)
	var authored: Dictionary=doc.data.duplicate(true)
	var protected: Dictionary=authored.duplicate(true)
	protected["protected_areas"]=[{"uid":"lane","name":"Protected approach","owner":"host","rect":[8,-1,1,2]}]
	var before: Dictionary=protected.duplicate(true)
	before["objects"][0].erase("traffic_control")
	var worlds: Dictionary={"2d":Templates.make("2d","blank"),"3d":Templates.make("3d","blank")}
	worlds[mode]=before
	var changed: Dictionary=worlds.duplicate(false)
	changed[mode]=protected
	check(Protection.allowed(worlds,changed,"guest",studio.library).contains("Protected area"),"A sign outside a protected strip cannot configure its protected approach: "+mode)
	var file: String=output+"/signals_"+mode+".isocity.json"
	check(studio.write_project(file,false),"The ordinary save path accepts authored bindings: "+mode)
	var broken: Dictionary=authored.duplicate(true)
	broken["objects"][0]["traffic_control"]["side"]=1.5
	var damage:=Repair.new(studio.library)
	var recovered: Dictionary=damage.world(broken,mode,"fixture",0)
	check(Doc.valid(recovered,mode,studio.library) and not damage.issues.is_empty() and not recovered["objects"][0].has("traffic_control") and recovered["objects"][0]["asset"]==authored["objects"][0]["asset"],"Repair archives invalid approach data and keeps the placed signal: "+mode)
	var repair:=Repair.new(studio.library)
	var result: Dictionary=repair.read(file)
	check(result["ok"] and repair.issues.is_empty() and result["content"]["documents"][mode]["objects"][0]["traffic_control"]==JSON.parse_string(JSON.stringify(authored["objects"][0]["traffic_control"])),"Save and read preserve the bound cell, facing and timings: "+mode+" "+str(repair.issues))
	if "--packages" in OS.get_cmdline_user_args():
		studio._command("export_portable",null)
		studio.file_dialog.hide()
		var package: String=output+"/signals_"+mode+".zip"
		studio._file_selected(package)
		check(FileAccess.file_exists(package),"Normal portable export includes the authored signals: "+mode+" "+studio.status.text)
	ui.unbind_action.pressed.emit()
	await settle()
	check(not doc.object("east").has("traffic_control") and not manager.signal_views.heads.has("east"),"Unbind retains the object and removes its authored rule and runtime view.")
	studio._command("undo",null)
	await settle()
	check(doc.data==authored,"Undo restores the authored binding without storing a signal phase.")
	studio._command("redo",null)
	await settle()
	check(not doc.object("east").has("traffic_control"),"Redo removes the binding again.")
	check(studio.load_project(file),"Normal open restores the authored project: "+mode)
	await settle()
	doc=studio.current()
	check(manager.plan["controls"]["active"].size()==2 and manager.signal_views.heads["east"]["color"]=="red","Reopen starts a new all-red epoch from the saved timings: "+mode)
	doc.checkpoint()
	Plan.Roads.paint(doc.data,Vector2i.ZERO,Vector2i.ZERO,true)
	studio.changed()
	doc.finish_checkpoint()
	await settle()
	check(manager.plan["controls"]["active"].is_empty() and doc.object("east").has("traffic_control"),"Removing the bound road keeps the editable binding dormant: "+mode)
	studio._command("undo",null)
	await settle()
	check(manager.plan["controls"]["active"].size()==2,"Undoing a road edit reactivates the original binding: "+mode)
	studio.selected_uid="east"
	studio.selected_uids.assign(["east"])
	studio.duplicate_selection()
	check(doc.data["objects"].size()==3 and not doc.object(studio.selected_uid).has("traffic_control"),"Copying sign artwork leaves the existing road binding with its original object: "+mode)
	studio._command("undo",null)
	await settle()

func run() -> void:
	if OS.has_environment("ISOCITY_TRAFFIC_CONTROL_OUTPUT"):
		output=OS.get_environment("ISOCITY_TRAFFIC_CONTROL_OUTPUT")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	for mode in ["2d","3d"]:
		plan_tests(mode)
	signs()
	studio=load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled=false
	root.add_child(studio)
	await settle()
	if studio.consumer_shell:
		studio.consumer_shell.dismiss_welcome()
	for mode in ["2d","3d"]:
		await workflow(mode)
	studio.free()
	await settle()
	print("TRAFFIC CONTROLS: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
