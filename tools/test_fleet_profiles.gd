extends SceneTree

const Fleet=preload("res://scripts/builder/fleet_plan.gd")
const Plan=preload("res://scripts/builder/traffic_plan.gd")
const Doc=preload("res://scripts/builder/document.gd")
const Templates=preload("res://scripts/builder/templates.gd")
const Repair=preload("res://scripts/builder/project_repair.gd")
const Assets=preload("res://scripts/builder/cooperative_plan.gd")
const Restricted="2d:Supplemental_Flipped_Fleet_EU_city_car_9a4bf3c7"
const TYPES={
	"2d":["2d:Sedan_Blue","2d:Hatchback_Mint","2d:Box_Truck","2d:School_Bus"],
	"3d":["3d:HanX_Traffic/Car_Sedan","3d:HanX_Traffic/Car_Hatchback","3d:HanX_Traffic/Truck_Box","3d:HanX_School/School_Bus"]
}
var checks: int=0
var failures: int=0
var studio: Control
var output: String="res://output/fleet_fixture"

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks+=1
	if not value:
		failures+=1
		print("FAIL: "+message)

func settle() -> void:
	for frame in 8: await process_frame
	await physics_frame

func choice(id: String, weight: int=50) -> Dictionary:
	return {"asset":id,"weight":weight}

func fixture(mode: String) -> Dictionary:
	var data: Dictionary=Templates.make(mode,"blank")
	data["roads"]=[]
	for x in range(-3,4):
		data["roads"].append({"cell":[x,0],"crossing":x==2})
	for y in [-2,-1,1,2]:
		data["roads"].append({"cell":[0,y]})
	var parking: String="2d:Parking_Accessible" if mode=="2d" else "3d:HanX_Traffic/Road_Parking"
	var size: float=2 if mode=="2d" else .5
	var direction: String="SE" if mode=="2d" else "0"
	var offset: Vector2=Plan.Roads.center_offset(studio.library,parking,direction,size,mode)*(2 if mode=="2d" else 1)
	for side in [-1,1]:
		var at: Vector2=Plan.center(Vector2i(side,0),mode)+Vector2(0,side*5.5)
		data["objects"].append({"asset":parking,"uid":"bay_"+str(side),"position":Plan.world(at-offset,mode),"scale":size,"direction":direction,"traffic_parking":true})
	return data

func plan_checks(mode: String) -> void:
	var types: Array=TYPES[mode]
	var data: Dictionary=fixture(mode)
	check(Fleet.selections(data,"traffic")==[choice(types[0])] and not Plan.settings(data)["enabled"],"Legacy projects keep their default sedan and traffic stays opt-in: "+mode)
	data["fleet"]={"traffic":[choice(types[0]),choice(types[1]),choice(types[2],0)]}
	var candidates: Array=Fleet.pool(data,"traffic",studio.library)
	check(candidates.size()==2 and candidates[0]["length"]!=candidates[1]["length"],"Eligible cars have distinct reviewed footprints: "+mode)
	var first: Dictionary=Fleet.choose(candidates,8,"traffic_0")
	var second: Dictionary=Fleet.choose(candidates,8,"traffic_1")
	data["fleet"]["traffic"].reverse()
	check(first["asset"]!=second["asset"] and Fleet.choose(Fleet.pool(data,"traffic",studio.library),8,"traffic_0")==first,"Weighted choice is deterministic and independent of saved row order: "+mode)
	var off: Dictionary=data.duplicate(true)
	off["fleet"]["traffic"]=[choice(types[0],0),choice(mode+":Missing_Fleet_Model"),choice("3d:Supplemental_SWAT/Vehicle_Armored_Truck")]
	check(Fleet.pool(off,"traffic",studio.library).is_empty() and Fleet.required(off).size()==3,"Zero weights and unavailable or ineligible assets never spawn and saved references remain repairable.")
	check(not Fleet.valid({"traffic":[choice(types[0]),choice(types[0])]}) and not Fleet.valid({"air":[choice(types[0])]}) and Fleet.valid(JSON.parse_string(JSON.stringify(data["fleet"]))),"Fleet validation handles duplicate identities and integral JSON weights.")
	var narrow: Dictionary=fixture(mode)
	narrow["roads"]=[{"cell":[-1,0],"width":2},{"cell":[0,0],"width":2},{"cell":[0,1],"width":2}]
	var lane: Dictionary=Plan.build(narrow)
	var truck: Dictionary=Fleet.definitions()[types[2]]
	var hatch: Dictionary=Fleet.definitions()[types[1]]
	check(Plan.route(lane,"-1,0","0,1",truck).is_empty() and Plan.route(lane,"-1,0","0,1",hatch).size()==3,"The hatchback can turn where the selected truck cannot: "+mode)
	check(not Fleet.fit_bay({"length":4,"width":4},truck) and Fleet.fit_bay({"length":4,"width":4},hatch),"A standard marked bay refuses the oversized truck.")
	check(Fleet.allowed_for(types[3],mode,"transit") and not Fleet.allowed_for(types[3],mode,"traffic"),"A reviewed bus belongs to transit without entering ordinary traffic.")
	if mode=="2d":
		var local: Dictionary={"mode":mode,"fleet":{"traffic":[choice(Restricted)]}}
		var restricted: Array=Fleet.pool(local,"traffic",studio.library)
		check(restricted.size()==1 and Fleet.direction(restricted[0],Vector2.UP)=="NE" and Fleet.direction(restricted[0],Vector2(1,1))=="S","The reviewed sprite mapping matches its authored cardinal and diagonal headings.")

func package(name: String) -> String:
	studio._command("export_portable",null)
	studio.file_dialog.hide()
	var path: String=output+"/"+name+".zip"
	studio._file_selected(path)
	return path

func capture_workflow(mode: String, ui: RefCounted) -> void:
	for size in [Vector2i(1480,900),Vector2i(960,640)]:
		ui.apply_button.release_focus()
		root.size=size
		studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true} if size.x==960 else {})
		if size.x==960: studio.workspace_layout.library_toggle.button_pressed=false
		await settle()
		ui.apply_button.grab_focus()
		await settle()
		var focused: Rect2=ui.apply_button.get_global_rect()
		check(ui.apply_button.has_focus() and Rect2(Vector2.ZERO,Vector2(root.size)).encloses(focused) and ui.panel.get_global_rect().encloses(focused),"Keyboard focus reveals the fleet apply action: "+mode+" "+str(size))
		RenderingServer.force_draw(false)
		RenderingServer.force_draw(false)
		check(root.get_texture().get_image().save_png(output+"/fleet_%s_%d.png"%[mode,size.x])==OK,"Captured the fleet editor at the requested window size.")
		if size.x==960:
			var weight: LineEdit=ui.entries[TYPES[mode][1]]["weight"].get_line_edit()
			weight.grab_focus()
			await settle()
			var field: Rect2=weight.get_global_rect()
			check(weight.has_focus() and Rect2(Vector2.ZERO,Vector2(root.size)).encloses(field) and ui.panel.get_global_rect().encloses(field),"Keyboard focus scrolls the selected model weight into the compact view.")
			RenderingServer.force_draw(false)
			RenderingServer.force_draw(false)
			check(root.get_texture().get_image().save_png(output+"/fleet_weight_"+mode+".png")==OK,"Captured the editable compact weight field.")
	root.size=Vector2i(1480,900)
	studio.accessibility_settings.restore({})
	await settle()

func live_fixture(mode: String) -> void:
	studio.switch_mode(mode)
	var types: Array=TYPES[mode]
	var doc:=Doc.new()
	doc.data=fixture(mode)
	studio.documents[mode]=doc
	studio.changed()
	await settle()
	studio._command("vehicle_fleets",null)
	var ui: RefCounted=studio.traffic_tools.fleets
	check(ui.panel.is_visible_in_tree() and ui.entries.has(types[1]),"The real fleet command opens available profiles in the selected world.")
	if not ui.entries.has(types[1]): return
	ui.entries[types[1]]["enabled"].button_pressed=true
	ui.entries[types[2]]["enabled"].button_pressed=true
	ui.entries[types[2]]["weight"].value=0
	ui.apply_button.pressed.emit()
	await settle()
	var selection: Array=doc.data.get("fleet",{}).get("traffic",[])
	check(selection.size()==3 and Assets.required_assets(doc.data,studio.library).has(types[2]) and not Plan.settings(doc.data)["enabled"],"Fleet Apply stores exact weights and unspawned dependencies while traffic remains off.")
	if selection.size()!=3: return
	var saved: Dictionary=doc.data.duplicate(true)
	studio._command("undo",null)
	await settle()
	check(not doc.data.has("fleet"),"Undo restores the implicit default fleet.")
	studio._command("redo",null)
	await settle()
	check(doc.data==saved,"Redo restores the exact custom fleet.")
	if "--capture" in OS.get_cmdline_user_args(): await capture_workflow(mode,ui)
	doc.data["traffic"]={"enabled":true,"population":2,"seed":8,"speed":4,"parking_seconds":2}
	studio.changed()
	await settle()
	var sim: Node=studio.traffic_tools.managers[mode]
	sim.set_physics_process(false)
	var spawned: Array=sim.vehicles.map(func(vehicle: Dictionary):return vehicle["asset"])
	check(spawned.size()==2 and types[0] in spawned and types[1] in spawned,"The real fleet spawns a sedan and hatchback for the same city: "+mode+" "+str(spawned))
	if spawned.size()!=2: return
	var history: int=doc.undo_history.size()
	var initial: Dictionary=doc.data.duplicate(true)
	var visited: Dictionary={}
	var left: Dictionary={}
	var intersection: Dictionary={}
	var overlap: bool=false
	var live_captured: bool=false
	for frame in 18000:
		sim.step(1.0/60)
		var a: Dictionary=sim.vehicles[0]
		var b: Dictionary=sim.vehicles[1]
		overlap=overlap or Fleet.overlaps(a,a["point"],a["heading"],b)
		for vehicle in sim.vehicles:
			if "0,0" in vehicle["sections"]: intersection[vehicle["asset"]]=true
			if not vehicle["visits"].is_empty():
				visited[vehicle["asset"]]=true
				if vehicle["phase"]=="edge" and vehicle["bay"].is_empty(): left[vehicle["asset"]]=true
		if not live_captured and "--capture" in OS.get_cmdline_user_args() and sim.vehicles.any(func(v: Dictionary):return v["phase"]=="parked"):
			live_captured=true
			await capture_live(mode,sim.vehicles)
		if left.size()==2 and intersection.size()==2: break
	check(not overlap and visited.size()==2 and left.size()==2 and intersection.size()==2,"Both actual footprints negotiate the intersection, park and rejoin without overlap: "+mode+" "+str([visited,left,intersection,sim.vehicles.map(func(v: Dictionary):return [v["asset"],v["status"],v["point"]])]))
	check(doc.data==initial and doc.undo_history.size()==history,"Vehicle motion and bay use remain transient.")
	var previous: Array=sim.vehicles.map(func(v: Dictionary):return [v["asset"],v["actor"].get_instance_id(),v["point"]])
	doc.checkpoint()
	doc.data["fleet"]["traffic"]=[choice(types[2])]
	studio.changed()
	doc.finish_checkpoint()
	await settle()
	check(sim.vehicles.map(func(v: Dictionary):return [v["asset"],v["actor"].get_instance_id(),v["point"]])==previous,"Changing the configured fleet preserves both in-flight actors and their poses.")
	studio._command("undo",null)
	await settle()
	var file: String=output+"/fleet_"+mode+".isocity.json"
	check(studio.write_project(file,false),"The ordinary save path accepts configured fleet choices.")
	var repair:=Repair.new(studio.library)
	var reopened: Dictionary=repair.read(file)
	check(reopened["ok"] and repair.issues.is_empty() and reopened["content"]["documents"][mode]["fleet"]==JSON.parse_string(JSON.stringify(doc.data["fleet"])),"Load preserves exact asset identities and weights.")
	var broken: Dictionary=doc.data.duplicate(true)
	broken["fleet"]["traffic"].append(choice(types[0],-1))
	var recover:=Repair.new(studio.library)
	var fixed: Dictionary=recover.world(broken,mode,"fixture",0)
	check(Doc.valid(fixed,mode,studio.library) and fixed["fleet"]==doc.data["fleet"] and not recover.issues.is_empty(),"Repair preserves valid rows and archives malformed fleet choices.")
	if "--packages" in OS.get_cmdline_user_args():
		doc.data["traffic"]["population"]=1
		doc.data["fleet"]["transit"]=[choice(types[3])]
		studio.changed()
		await settle()
		check(sim.vehicles.size()==1,"The export fixture has only one currently spawned fleet member.")
		var zip_path: String=package("fleet_"+mode)
		check(FileAccess.file_exists(zip_path),"Allowed portable package includes the unspawned choices: "+studio.status.text)
		if mode=="2d":
			doc.data["fleet"]["traffic"].append(choice(Restricted,0))
			studio.changed()
			var denied: String=package("restricted")
			check(not FileAccess.file_exists(denied) and studio.status.text.contains("restricts redistributing"),"A selected local-use asset stops source export even with zero weight.")

func capture_live(mode: String, vehicles: Array) -> void:
	var world: Node=studio.worlds[mode]
	if studio.consumer_shell and studio.consumer_shell.active:
		studio.consumer_shell.close_overlays()
	else:
		studio.workspace_layout.inspector_toggle.button_pressed=false
		studio.workspace_layout.library_toggle.button_pressed=false
	var middle: Vector2=(vehicles[0]["point"]+vehicles[1]["point"])*.5
	var position: Array=Plan.world(middle,mode)
	if mode=="2d":
		world.camera.position=Vector2(position[0],position[1])
		world.camera.zoom=Vector2.ONE*1.8
	else:
		world.target=Vector3(position[0],0,position[2])
		world.distance=34
		world.yaw=45
		world.update_camera()
	await settle()
	RenderingServer.force_draw(false)
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(output+"/fleet_live_"+mode+".png")==OK,"Captured both running fleet styles by a real occupied bay.")

func transit_fixture(mode: String) -> void:
	studio.switch_mode(mode)
	var doc:=Doc.new()
	doc.data=Templates.make(mode,"blank")
	doc.data["roads"]=[]
	for x in range(-4,13): doc.data["roads"].append({"cell":[x,0]})
	for index in 2:
		var asset: String="2d:Bus_Stop_Sign" if mode=="2d" else "3d:HanX_Traffic/Bus_Stop"
		var item: Dictionary=doc.add(asset,Plan.world(Plan.center(Vector2i(index*8,0),mode)+Vector2(0,8),mode),studio.library.directions(asset)[0])
		item["uid"]="fleet_stop_"+str(index)
	doc.data["transit"]={"enabled":true,"automatic":false}
	doc.data["transit_lines"]=[{"uid":"fleet_line","stops":["fleet_stop_0","fleet_stop_1"],"headway":180,"capacity":2}]
	doc.data["fleet"]={"transit":[choice(TYPES[mode][3])]}
	studio.documents[mode]=doc
	studio.changed()
	await settle()
	var bus: Node=studio.transit_tools.managers[mode]
	bus.set_physics_process(false)
	check(bus.passengers.plan["lines"].size()==1 and bus.bus_pool.size()==1,"The selected school bus is valid for a live route in "+mode)
	if bus.passengers.plan["lines"].is_empty() or bus.bus_pool.is_empty(): return
	var a: Dictionary=bus.passengers.plan["stops"]["fleet_stop_0"]
	var b: Dictionary=bus.passengers.plan["stops"]["fleet_stop_1"]
	var result: Dictionary=bus.request(a["platform"]+a["right"]*2,b["platform"]+b["right"]*2)
	check(result["ok"],"A passenger can request a trip on the selected vehicle: "+mode+" "+str(result.get("reason","")))
	if not result["ok"]: return
	var job: Dictionary=result["job"]
	var actor_id: int=0
	var onboard: bool=false
	for frame in 14000:
		bus.step(1.0/60)
		if not onboard and job["state"]=="onboard":
			onboard=true
			var vehicle: Dictionary=bus.buses[job["vehicle"]]["vehicle"]
			actor_id=vehicle["actor"].get_instance_id()
			check(vehicle["asset"]==TYPES[mode][3] and vehicle["half_length"]==Fleet.definitions()[vehicle["asset"]]["length"]*.5,"A real passenger boards the selected bus with its own body size: "+mode)
			var current_id: String=job["vehicle"]
			doc.data.erase("fleet")
			studio.changed()
			await settle()
			var same: Dictionary=bus.buses[current_id]["vehicle"]
			check(job["state"]=="onboard" and same["actor"].get_instance_id()==actor_id and same["asset"]==TYPES[mode][3] and bus.bus_pool[0]["asset"]!=same["asset"],"Changing the transit roster retains the occupied bus, its manifest and its original profile.")
		if job["state"] in ["complete","blocked","cancelled"]: break
	check(onboard and job["state"]=="complete" and bus.passengers.completed==1,"The same live passenger finishes the trip after the roster edit: "+mode+" "+job["state"])

func run() -> void:
	if OS.has_environment("ISOCITY_FLEET_OUTPUT"): output=OS.get_environment("ISOCITY_FLEET_OUTPUT")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	studio=load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled=false
	root.add_child(studio)
	await settle()
	if studio.consumer_shell: studio.consumer_shell.dismiss_welcome()
	for mode in ["2d","3d"]:
		plan_checks(mode)
		await live_fixture(mode)
		await transit_fixture(mode)
	studio.free()
	await settle()
	print("FLEET PROFILES: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
