extends SceneTree

const Care=preload("res://scripts/builder/vehicle_service_plan.gd")
const Runtime=preload("res://scripts/builder/vehicle_service_runtime.gd")
const Drive=preload("res://scripts/builder/driving_plan.gd")
const Templates=preload("res://scripts/builder/templates.gd")
const Document=preload("res://scripts/builder/document.gd")
const Repair=preload("res://scripts/builder/project_repair.gd")
const Economy=preload("res://scripts/builder/economy_plan.gd")
var studio: Control
var checks: int=0
var failures: int=0
var output: String="res://output/vehicle_care_fixture"

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool,description: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		print("FAIL: "+description)

func settle() -> void:
	for frame in 8: await process_frame
	await physics_frame

func pure() -> void:
	var gas: Dictionary={"asset":"2d:Sedan_Blue","vehicle_care":{"enabled":true}}
	var electric: Dictionary=gas.duplicate(true)
	electric["vehicle_care"]["energy"]="charge"
	var pump: Dictionary={"asset":"3d:HanX_GasStation/Fuel_Pump","vehicle_bay":{"enabled":true,"seconds":.5}}
	check(Care.vehicle({"asset":"2d:Sedan_Blue"}).is_empty() and Care.bay({"asset":pump["asset"]}).is_empty(),"Old assets do not enable vehicle care or service bays by default.")
	var invalid: Dictionary=gas.duplicate(true)
	invalid["vehicle_care"]["initial"]=251
	check(not Care.valid_vehicle(invalid) and not Care.valid_bay({"asset":pump["asset"],"vehicle_bay":{"price":1.5}}),"Capacities, authored initial energy and whole-credit prices are validated.")
	var bay: Dictionary=Care.bay(pump)
	bay.merge({"uid":"pump","center":Vector2.ZERO,"axis":Vector2.DOWN,"supported":true})
	var pose: Dictionary={"point":Vector2.ZERO,"heading":Vector2.DOWN,"extent":Vector2(.65,1.45),"speed":0.0}
	check(Care.reason(Care.vehicle(electric),pose,bay).contains("charger"),"A charge vehicle cannot use the fuel supply.")
	var heavy: Dictionary=Care.vehicle(gas)
	heavy["class"]="heavy"
	check(Care.reason(heavy,pose,bay).contains("vehicle class"),"The posted bay class excludes heavy vehicles even when their pose fits.")
	var wet: Dictionary=bay.duplicate()
	wet["supported"]=false
	check(Care.reason(Care.vehicle(gas),pose,wet).contains("dry, level"),"An unsupported apron cannot accept a service request.")
	var over: Dictionary=pose.duplicate()
	over["extent"]=Vector2(.7,4.0)
	check(Care.reason(Care.vehicle(gas),over,bay).contains("too long"),"An overlong body cannot use the physically smaller bay.")
	var wrong: Dictionary=pose.duplicate()
	wrong["heading"]=Vector2.RIGHT
	check(not Care.geometry(wrong,bay)["in_bay"],"The entire oriented body and alignment must fit inside the bay.")
	var runtime:=Runtime.new()
	runtime.source={"economy":{"enabled":true,"starting_cash":18}}
	runtime.vehicles={"a":{"config":Care.vehicle(gas)},"b":{"config":Care.vehicle(gas)}}
	runtime.bays={"pump":bay}
	var staged: Dictionary=pose.duplicate()
	staged["point"]=Vector2(0,-8)
	var snapshot: Dictionary={"a":pose,"b":staged}
	var positions: Callable=func(uid: String)->Dictionary:return snapshot[uid]
	var one: Dictionary=runtime.request("a","pump",pose)
	runtime.step(.2,positions)
	var two: Dictionary=runtime.request("b","pump",staged)
	check(one["ok"] and two["ok"] and runtime.locked("a") and not runtime.locked("b"),"The FIFO starts only the stopped vehicle physically in the bay.")
	for tick in 3: runtime.step(.2,positions)
	var receipt: Dictionary=runtime.complete("a",one["job"]["id"])
	check(runtime.wallet==0 and receipt["paid"]==18 and runtime.state("a")["energy"]==100,"The completion debits exactly once and fills actual energy.")
	check(runtime.complete("a",one["job"]["id"])==receipt and runtime.wallet==0 and runtime.receipts.size()==1,"Replaying the exact receipt has no second payment or result.")
	snapshot["b"]=pose
	runtime.step(.2,positions)
	check(not runtime.jobs.has("b") and runtime.state("b")["energy"]==40 and runtime.feedback["b"].contains("Insufficient"),"Queued service rechecks funds and applies no partial result.")
	runtime.travelled("b",10)
	check(is_equal_approx(runtime.state("b")["energy"],36.5) and runtime.state("b")["condition"]<70 and runtime.state("b")["cleanliness"]<35,"Actual distance consumes bounded energy and wears condition and cleanliness.")
	runtime.reset()
	check(runtime.jobs.is_empty() and runtime.queues.is_empty() and runtime.receipts.is_empty() and runtime.state("a")["energy"]==40,"Reset clears all preview economy and reservations together.")
	runtime.source={}
	runtime.travelled("a",1000)
	check(runtime.energy_limit("a")==0 and runtime.state("a")["energy"]==0,"Travel saturates at zero energy with no remaining range.")
	var creative: Dictionary=runtime.request("a","pump",pose)
	for tick in 3: runtime.step(.25,positions)
	check(creative["ok"] and runtime.wallet==-1 and runtime.receipts[creative["job"]["id"]]["paid"]==0 and runtime.state("a")["energy"]==100,"Creative preview restores energy with no economy balance or charge.")

func stress() -> void:
	var runtime:=Runtime.new()
	var pump: Dictionary=Care.bay({"asset":"3d:HanX_GasStation/Fuel_Pump","vehicle_bay":{"enabled":true,"seconds":10,"queue":4}})
	var config: Dictionary=Care.vehicle({"asset":"2d:Sedan_Blue","vehicle_care":{"enabled":true}})
	var poses: Dictionary={}
	for site in 32:
		var name: String="bay_%d"%site
		var center:=Vector2(site*25,0)
		var bay: Dictionary=pump.duplicate()
		bay.merge({"uid":name,"center":center,"axis":Vector2.DOWN,"supported":true})
		runtime.bays[name]=bay
		for index in 4:
			var uid: String="%s_car_%d"%[name,index]
			var pose: Dictionary={"point":center-Vector2(0,index*4),"heading":Vector2.DOWN,"extent":Vector2(.65,1.45),"speed":0.0}
			runtime.vehicles[uid]={"config":config}
			poses[uid]=pose
			if not runtime.request(uid,name,pose)["ok"]: check(false,"Stress fixture rejected "+uid)
	var overflow: Dictionary=poses["bay_0_car_1"]
	runtime.vehicles["overflow"]={"config":config}
	check(runtime.jobs.size()==128 and not runtime.request("overflow","bay_0",overflow)["ok"],"The request cap bounds 32 concurrent bays and 96 waiting vehicles.")
	var times: Array[int]=[]
	var snapshot: Callable=func(uid: String)->Dictionary:return poses[uid]
	for tick in 500:
		var start: int=Time.get_ticks_usec()
		runtime.step(.001,snapshot)
		times.append(Time.get_ticks_usec()-start)
	times.sort()
	print("VEHICLE CARE STRESS: 128 jobs, 500 ticks, median %d us, p95 %d us"%[times[250],times[474]])
	for tick in 300: runtime.step(.25,snapshot)
	check(runtime.jobs.is_empty() and runtime.queues.is_empty() and runtime.receipts.size()==32,"Completed bays and expired waiting cars release all 128 reservations.")

func select(uid: String,command: String) -> void:
	studio.selected_uid=uid
	studio.selected_uids.assign([uid])
	studio._command(command,null)

func place_car(doc: RefCounted,mode: String,id: String,bay: Dictionary,metres: float,energy: String) -> Dictionary:
	var asset: String="2d:Sedan_Blue" if mode=="2d" else "3d:HanX_Traffic/Car_Sedan"
	if id=="wash_car": asset="2d:Delivery_Van" if mode=="2d" else "3d:HanX_Traffic/Van_Delivery"
	var angle: float=atan2(bay["axis"].x,bay["axis"].y)
	var direction: String=Drive.direction({"asset":asset},angle)
	var start: Vector2=bay["center"]-bay["axis"]*metres
	start-=Drive.Roads.center_offset(studio.library,asset,direction,.5,mode)*(2 if mode=="2d" else 1)
	var car: Dictionary=doc.add(asset,Drive.Traffic.world(start,mode),direction,.5)
	car["uid"]=id
	car["driving"]={"max_speed":6,"braking":14}
	car["vehicle_care"]={"enabled":true,"energy":energy}
	return car

func fixture(mode: String) -> Dictionary:
	studio.switch_mode(mode)
	var doc:=Document.new()
	doc.data=Templates.make(mode,"blank")
	studio.documents[mode]=doc
	var stations: Array=[["fuel","3d:HanX_GasStation/Fuel_Pump",Vector2(0,0)],["charge","2d:EV_Charger" if mode=="2d" else "3d:HanX_GasStation/EV_Charger",Vector2(26,0)],["wash","3d:HanX_GasStation/Car_Wash",Vector2(52,0)],["repair","3d:HanX_GasStation/Repair_Garage",Vector2(78,0)]]
	for spec in stations:
		var directions: Array=studio.library.directions(spec[1])
		var record: Dictionary=doc.add(spec[1],Drive.Traffic.world(spec[2],mode),directions[0] if spec[1].begins_with("2d:") else "0")
		record["uid"]=spec[0]
		record["vehicle_bay"]={"enabled":true,"seconds":2.0}
	var house: Dictionary=doc.add("2d:House_Blue",Drive.Traffic.world(Vector2(-15,10),mode),"SE",.6)
	house["uid"]="house"
	studio.changed()
	await settle()
	var driver: Node=studio.worlds[mode].exploration.driving
	check(driver.care.bays.size()==4,"The four actual supplied fixtures produce independent bays: "+mode+" "+str(driver.care.bays.keys()))
	if driver.care.bays.size()!=4: return {}
	for spec in stations:
		place_car(doc,mode,spec[0]+"_car",driver.care.bays[spec[0]],7.0,"charge" if spec[0]=="charge" else "fuel")
	place_car(doc,mode,"second",driver.care.bays["fuel"],13.0,"fuel")
	doc.data["economy"]={"enabled":true,"starting_cash":1000}
	doc.data["economy_account"]=Economy.fresh_account(doc.data,studio.library)
	studio.economy_tools.pauses[mode]=true
	studio.changed()
	await settle()
	return {"doc":doc,"driver":driver}

func drive_to(driver: Node,point: Vector2,forward: bool=true) -> bool:
	for frame in 1200:
		if driver.active.is_empty(): return false
		if driver.active["point"].distance_to(point)<.65: break
		driver.step(1.0/60,Vector2(0,1 if forward else -1))
		driver.step_services(1.0/60)
	for frame in 60:
		driver.step(1.0/60,Vector2.ZERO,true)
		driver.step_services(1.0/60)
	return not driver.active.is_empty() and driver.active["point"].distance_to(point)<1.2 and absf(driver.speed)<.05

func enter_car(uid: String) -> void:
	select(uid,"driving")
	studio.driving_tools.preview_selected()
	await settle()

func finish_service(driver: Node,uid: String) -> void:
	for frame in 180:
		if not driver.care.jobs.has(uid): break
		driver.step_services(1.0/60)

func capture_screen(path: String) -> void:
	RenderingServer.force_draw(false)
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(output+"/"+path+".png")==OK,"Captured "+path)

func capture_settings(mode: String,tools: RefCounted) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	var line: LineEdit=tools.bay_fields["price"].get_line_edit()
	for size in [Vector2i(1480,900),Vector2i(960,640)]:
		line.release_focus()
		root.size=size
		studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true} if size.x==960 else {})
		if size.x==960: studio.workspace_layout.library_toggle.button_pressed=false
		await settle()
		line.grab_focus()
		await settle()
		var bounds: Rect2=line.get_global_rect()
		check(line.has_focus() and Rect2(Vector2.ZERO,Vector2(size)).encloses(bounds) and tools.page.get_global_rect().encloses(bounds) and float(line.text)==18,"The posted price remains readable and keyboard reachable: "+mode+" "+str([size,bounds,tools.page.get_global_rect(),line.text]))
		capture_screen("settings_%s_%d"%[mode,size.x])
	line.release_focus()
	root.size=Vector2i(1480,900)
	studio.accessibility_settings.restore({})
	await settle()

func capture_wash(mode: String,world: Node,driver: Node) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	var bay: Dictionary=driver.care.bays["wash"]
	for size in [Vector2i(1480,900),Vector2i(960,640)]:
		root.size=size
		studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true} if size.x==960 else {})
		if mode=="2d": world.camera.zoom=Vector2.ONE*3.6
		else:
			world.yaw=35
			world.pitch=44
			world.update_camera()
		await settle()
		var view: Node=driver.care_view
		view.refresh()
		await settle()
		check(view.panel.is_visible_in_tree() and view.text.text.contains("Service in progress") and view.effects.has("wash_car") and is_instance_valid(view.marker) and view.marked[0]==bay["uid"],"The Wash HUD, real effects and marked bay remain visible: "+mode+" "+str(size))
		if studio.consumer_shell and studio.consumer_shell.active:
			var height: float=driver.get_viewport().get_visible_rect().size.y
			var panel_bottom: float=studio.canvas.get_global_rect().position.y+view.panel.get_rect().end.y*studio.canvas.size.y/height
			check(panel_bottom<=studio.consumer_shell.hint_panel.get_global_rect().position.y,"The care actions stay clear of Simple's Walk hint and dock: "+mode+" "+str(size))
		elif studio.consumer_shell and studio.consumer_shell.expert_return.visible:
			var width: float=driver.get_viewport().get_visible_rect().size.x
			var panel_right: float=studio.canvas.get_global_rect().position.x+view.panel.get_rect().end.x*studio.canvas.size.x/width
			check(panel_right<=studio.consumer_shell.expert_return.get_global_rect().position.x,"The care actions stay clear of Precision's workspace switch: "+mode+" "+str(size))
		capture_screen("wash_%s_%d"%[mode,size.x])
	root.size=Vector2i(1480,900)
	studio.accessibility_settings.restore({})
	await settle()

func reenter_parked(driver: Node,uid: String,mode: String) -> bool:
	var pose: Dictionary=driver.care_snapshot(uid)
	var heading: Vector2=pose["heading"]
	var side:=Vector2(heading.y,-heading.x)
	var world: Node=driver.exploration.get_parent()
	for sign_value in [-1,1]:
		var point: Vector2=pose["point"]+side*sign_value*(pose["extent"].x+1.0)
		var destination: Variant=world.to_global(Drive.world(point,mode,.05))
		world.player.teleport_to(world.player.get_parent().to_local(destination))
		var candidate: Dictionary=driver.nearby(uid)
		if not candidate.is_empty() and driver.interact(candidate): return true
	return false

func lifecycle(mode: String) -> void:
	var fixture_data: Dictionary=await fixture(mode)
	if fixture_data.is_empty(): return
	var driver: Node=fixture_data["driver"]
	var doc: RefCounted=fixture_data["doc"]
	var world: Node=studio.worlds[mode]
	var exploration: Node=world.exploration
	driver.set_physics_process(false)
	await enter_car("fuel_car")
	var bay: Dictionary=driver.care.bays["fuel"]
	var queued: bool=driver.request_vehicle_service()
	check(queued and drive_to(driver,bay["center"]) and driver.care.locked("fuel_car"),"A driven car starts service before the driver steps out: "+mode)
	if not driver.care.locked("fuel_car"): return
	var wallet: int=driver.care.wallet
	var job: Dictionary=driver.care.jobs["fuel_car"].duplicate()
	check(driver.exit_vehicle() and driver.care.locked("fuel_car"),"Exiting leaves the parked car and its reservation in the bay: "+mode)
	var door: Variant=exploration.entrance(world.instances["house"])
	world.player.teleport_to(world.to_global(door))
	studio.control_settings.execute("interact")
	await settle()
	check(exploration.interior!=null,"A normal Walk interaction visits the house while the car is parked: "+mode+" "+exploration.prompt())
	if exploration.interior:
		var room: Dictionary=doc.object("house")["interior"].duplicate(true)
		room["objects"].append(doc.object("fuel_car").duplicate(true))
		var repair:=Repair.new(studio.library)
		var cleaned: Dictionary=repair.world(room,mode,"test/room",1)
		check(not Document.valid(room,mode,studio.library) and Document.valid(cleaned,mode,studio.library) and not cleaned["objects"].back().has("vehicle_care"),"Owned room repair removes unsupported vehicle-care metadata and keeps the placement: "+mode)
	for tick in 20: driver.step_services(.25)
	check(driver.care.jobs.get("fuel_car",{})==job and driver.care.wallet==wallet,"Visiting an interior pauses both the reservation timer and payment: "+mode+" "+str([job,driver.care.jobs,driver.care.feedback,wallet,driver.care.wallet,studio.walking]))
	if exploration.interior: exploration.leave_interior()
	check(reenter_parked(driver,"second",mode),"The driver enters the staged second car in Walk: "+mode)
	check(driver.request_vehicle_service() and driver.care.queues.get("fuel",[])==["fuel_car","second"],"The second real car joins the occupied bay in order: "+mode+" "+str(driver.care.feedback))
	check(driver.exit_vehicle() and reenter_parked(driver,"fuel_car",mode) and driver.care.locked("fuel_car"),"Re-entering at the actual parked pose preserves the first job: "+mode)
	finish_service(driver,"fuel_car")
	check(driver.care.wallet==wallet-int(bay["price"]) and driver.care.receipts.size()==1 and driver.care.jobs.get("second",{}).get("state")=="queued","Only the parked first car completes while the second waits: "+mode)
	var clear_point: Vector2=bay["center"]+bay["axis"]*8
	check(drive_to(driver,clear_point) and driver.exit_vehicle(),"The serviced car clears the marked bay through ordinary driving: "+mode)
	await settle()
	check(reenter_parked(driver,"second",mode),"The second driver position remains at its staging pose: "+mode)
	await settle()
	var arrived: bool=drive_to(driver,bay["center"])
	check(arrived and driver.care.locked("second"),"The second car begins its own service after driving in: "+mode+" "+str([driver.active.get("point"),bay["center"],driver.notice,driver.care.feedback,driver.care.jobs]))
	var paid: int=driver.care.wallet
	var energy: float=driver.care.state("second")["energy"]
	studio.control_settings.execute("vehicle_service_cancel")
	check(not driver.care.jobs.has("second") and driver.care.wallet==paid and driver.care.state("second")["energy"]==energy,"The real cancel action releases the bay without payment or partial refill: "+mode)
	check(driver.request_vehicle_service() and driver.care.locked("second"),"A stopped car may request a new job after cancelling: "+mode+" "+str([driver.care.feedback,driver.care.jobs]))
	doc.checkpoint()
	doc.data["objects"].erase(doc.object("fuel"))
	studio.changed()
	await settle()
	check(not driver.care.bays.has("fuel") and driver.care.jobs.is_empty() and driver.care.wallet==paid and driver.care.receipts.size()==1,"Removing a live bay releases the reservation without double payment: "+mode+" "+str([driver.care.bays.keys(),driver.care.jobs,driver.care.feedback,driver.care.wallet,paid,driver.care.receipts]))
	studio.switch_mode("3d" if mode=="2d" else "2d")
	check(driver.care.jobs.is_empty() and driver.care.receipts.is_empty() and driver.care.wallet==-1,"Changing world clears every private queue, receipt and wallet: "+mode)

func workflow(mode: String) -> void:
	var case: Dictionary=await fixture(mode)
	if case.is_empty(): return
	var doc: RefCounted=case["doc"]
	var driver: Node=case["driver"]
	driver.set_physics_process(false)
	select("fuel","vehicle_care")
	var tools: RefCounted=studio.vehicle_service_tools
	check(tools.page.is_visible_in_tree() and tools.bay_box.visible,"The normal command opens the service bay inspector: "+mode)
	await capture_settings(mode,tools)
	var initial: Dictionary=doc.data.duplicate(true)
	tools.bay_fields["price"].value=19
	tools.apply_settings()
	check(doc.object("fuel")["vehicle_bay"]["price"]==19 and doc.data["economy_account"]==initial["economy_account"],"A bay override saves as ordinary history without an economy charge: "+mode)
	studio._command("undo",null)
	await settle()
	check(doc.data==initial,"Undo restores the authored bay and exact treasury: "+mode)
	select("fuel_car","vehicle_care")
	check(tools.vehicle_box.visible and tools.vehicle_fields["enabled"].button_pressed,"The vehicle inspector displays the explicit care opt-in: "+mode)
	var original: Dictionary=doc.data.duplicate(true)
	var world: Node=studio.worlds[mode]
	for kind in ["fuel","charge","wash","repair"]:
		var uid: String=kind+"_car"
		await enter_car(uid)
		check(not driver.active.is_empty() and driver.active["item"]["uid"]==uid,"Normal Drive selected enters the actual "+kind+" vehicle: "+mode+" "+world.exploration.prompt())
		if driver.active.is_empty(): break
		var bay: Dictionary=driver.care.bays[kind]
		var before: Dictionary=driver.care.state(uid).duplicate()
		var money: int=driver.care.wallet
		studio.control_settings.execute("vehicle_service")
		check(driver.care.jobs.get(uid,{}).get("state","")=="queued","The normal care action queues the vehicle from the real approach: "+mode+" "+kind+" "+str(driver.care.feedback.get(uid,"")))
		var parked: bool=drive_to(driver,bay["center"])
		check(parked and driver.care.locked(uid),"Driving inside the marked bay begins real service: "+mode+" "+kind+" "+str([driver.active.get("point"),bay["center"],driver.notice,driver.care.feedback.get(uid,"")]))
		if not driver.care.locked(uid):
			driver.exit_vehicle(true)
			continue
		var effect_position: Vector2=driver.active["point"]
		driver.step(.1,Vector2(0,1))
		check(driver.active["point"]==effect_position,"Throttle cannot move a vehicle with active service equipment: "+mode+" "+kind)
		await settle()
		if kind in ["wash","repair"]:
			check(driver.care_view.effects.has(uid) and driver.care_view.effects[uid]["root"].get_child_count()==10,"Service presents a live effect on the actual vehicle: "+mode+" "+kind)
		if kind=="wash": await capture_wash(mode,world,driver)
		finish_service(driver,uid)
		var state: Dictionary=driver.care.state(uid)
		var changed: bool=state["energy"]==100 if kind in ["fuel","charge"] else state["cleanliness"]==100 if kind=="wash" else state["condition"]==100
		check(changed and state!=before and driver.care.wallet==money-int(bay["price"]),"Service changes the actual vehicle state and charges exactly the posted price: "+mode+" "+kind)
		if kind=="wash": check(driver.care.vehicles[uid]["config"]["class"]=="van","The actual delivery van uses the shared driving and care machinery: "+mode)
		check(driver.exit_vehicle(),"The driver can leave after the service completes: "+mode+" "+kind)
	studio.set_walking(false)
	check(driver.care.receipts.is_empty() and driver.care.jobs.is_empty() and driver.care.wallet==-1 and doc.data==original,"Build resets all private service state while retaining the exact city and treasury: "+mode)
	var saved: String=output+"/care_"+mode+".isocity.json"
	check(studio.write_project(saved,false),"Normal project save accepts the configured vehicles and bays: "+mode)
	var repair:=Repair.new(studio.library)
	var loaded: Dictionary=repair.read(saved)
	check(loaded["ok"] and repair.issues.is_empty(),"A saved vehicle-care city reopens without repair: "+mode+" "+str(repair.issues))
	var damaged: Dictionary=doc.data.duplicate(true)
	for item in damaged["objects"]:
		if item["uid"]=="fuel": item["vehicle_bay"]["price"]=-1
		if item["uid"]=="charge": item["asset"]="3d:Unknown/Removed_Charger"
	var restored: Dictionary=repair.world(damaged,mode,"test/"+mode,0)
	var repaired: Dictionary={}
	for item in restored["objects"]: repaired[item["uid"]]=item
	check(Document.valid(restored,mode,studio.library) and not repaired["fuel"].has("vehicle_bay") and repair.issues.any(func(issue: Dictionary)->bool:return issue["path"].ends_with("/vehicle_bay") and issue.get("original",{}).get("price")==-1),"Repair archives a damaged bay override without removing its placed station: "+mode)
	var missing: Dictionary=repaired["charge"].get("missing_asset",{})
	check(not repaired["charge"].has("vehicle_bay") and missing.get("record",{}).get("vehicle_bay")=={"enabled":true,"seconds":2.0},"Missing charger art preserves the original bay settings for recovery: "+mode+" "+str(missing.keys()))
	if "--packages" in OS.get_cmdline_user_args():
		var exporter=preload("res://scripts/builder/portable_export.gd").new()
		var bundle: Dictionary=exporter.save(world,doc.data,studio.library,output+"/care_"+mode+".zip")
		check(bundle["ok"],"Portable package retains the reviewed station and vehicle assets: "+mode+" "+str(bundle))
	select("fuel_car","vehicle_care")
	studio._command("duplicate",null)
	await settle()
	var copy: Dictionary=doc.object(studio.selected_uid)
	var copy_id: String=copy.get("uid","")
	check(not copy_id.is_empty() and copy_id!="fuel_car" and copy.get("vehicle_care")==doc.object("fuel_car")["vehicle_care"] and driver.care.states.is_empty(),"A normal duplicate preserves the authored settings with a fresh vehicle identity: "+mode+" "+studio.status.text)
	var duplicated: Dictionary=doc.data.duplicate(true)
	studio._command("undo",null)
	await settle()
	check(doc.data==original,"Undo of duplication restores exact source and treasury: "+mode)
	studio._command("redo",null)
	await settle()
	check(doc.data==duplicated,"Redo recreates only the authored duplicate and its ordinary placement charge: "+mode)

func run() -> void:
	if OS.has_environment("ISOCITY_CARE_OUTPUT"): output=OS.get_environment("ISOCITY_CARE_OUTPUT")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	pure()
	if "--stress" in OS.get_cmdline_user_args(): stress()
	studio=load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled=false
	root.add_child(studio)
	await settle()
	if studio.consumer_shell: studio.consumer_shell.dismiss_welcome()
	if "--capture" in OS.get_cmdline_user_args():
		root.size=Vector2i(1480,900)
		if studio.consumer_shell: studio.consumer_shell.set_active("--simple" in OS.get_cmdline_user_args(),false)
	for mode in ["2d","3d"]:
		await workflow(mode)
		await lifecycle(mode)
	studio.free()
	await settle()
	print("VEHICLE CARE: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
