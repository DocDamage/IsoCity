extends SceneTree

const Plan=preload("res://scripts/builder/delivery_plan.gd")
const Document=preload("res://scripts/builder/document.gd")
const Templates=preload("res://scripts/builder/templates.gd")
const Repair=preload("res://scripts/builder/project_repair.gd")
const Portable=preload("res://scripts/builder/portable_export.gd")
var studio: Control
var checks: int=0
var failures: int=0
var output: String="res://output/delivery_fixture"

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

func select(uid: String,command: String) -> void:
	studio.selected_uid=uid
	studio.selected_uids.assign([uid])
	studio._command(command,null)

func shop(doc: RefCounted,uid: String,asset: String,pad: Vector2,stock: Dictionary) -> Dictionary:
	var mode: String=doc.data["mode"]
	var record: Dictionary=doc.add(asset,Plan.Traffic.world(pad+Vector2(12,0),mode),studio.library.directions(asset)[0],.6)
	record["uid"]=uid
	record["name"]="Bakery pickup" if uid=="pickup" else "Neighborhood shop"
	record["business"]={"kind":"shop","open_hour":7,"close_hour":22}
	record["delivery_site"]={"enabled":true,"stock":stock,"capacity":12}
	var offset: Vector2=pad-Plan.loading_point(record,mode,studio.library)
	record["delivery_site"].merge({"offset_x":offset.x,"offset_z":offset.y})
	return record

func add_vehicle(doc: RefCounted,uid: String,point: Vector2,capacity: int) -> void:
	var mode: String=doc.data["mode"]
	var asset: String="2d:Delivery_Van" if mode=="2d" else "3d:HanX_Traffic/Van_Delivery"
	var direction: String=Plan.Drive.direction({"asset":asset},0)
	var start: Vector2=point-Plan.Drive.Roads.center_offset(studio.library,asset,direction,.5,mode)*(2 if mode=="2d" else 1)
	var record: Dictionary=doc.add(asset,Plan.Traffic.world(start,mode),direction,.5)
	record["uid"]=uid
	record["delivery_vehicle"]={"enabled":true,"capacity":capacity}
	record["driving"]={"max_speed":9,"braking":15}

func fixture(mode: String) -> Dictionary:
	studio.switch_mode(mode)
	var doc:=Document.new()
	doc.data=Templates.make(mode,"blank")
	studio.documents[mode]=doc
	doc.data["roads"]=[]
	for index in range(-2,9): doc.data["roads"].append({"cell":[0,index]})
	var origin: Vector2=Plan.Traffic.center(Vector2i.ZERO,mode)
	var start: Vector2=origin+Vector2(-1.5,0)
	var finish: Vector2=start+Vector2(0,40)
	var first: Dictionary=shop(doc,"pickup","2d:Coffee_Shop" if mode=="2d" else "3d:HanX_Shop/Shop_Bakery",start,{"parcels":8})
	shop(doc,"drop","2d:Supermarket" if mode=="2d" else "3d:HanX_Shop/Shop_Grocery",finish,{"produce":1})
	first["delivery_contract"]={"enabled":true,"destination":"drop","goods":"parcels","quantity":3,"reward":45,"deadline":120}
	add_vehicle(doc,"van",start,8)
	add_vehicle(doc,"small_van",start-Vector2(0,7),2)
	doc.data["economy"]={"enabled":true,"starting_cash":900}
	doc.data["economy_account"]=Plan.Economy.fresh_account(doc.data,studio.library)
	studio.economy_tools.pauses[mode]=true
	studio.changed()
	await settle()
	var world: Node=studio.worlds[mode]
	var driver: Node=world.exploration.driving
	driver.set_physics_process(false)
	driver.business_clock.set_physics_process(false)
	driver.business_clock.hour=12
	check(driver.delivery.sites.size()==2 and driver.delivery.vehicles.size()==2 and driver.delivery.offers.size()==1,"Both real sites and vans compile: "+mode)
	return {"doc":doc,"driver":driver,"world":world,"start":start,"finish":finish}

func enter_car(uid: String) -> void:
	select(uid,"driving")
	studio.driving_tools.preview_selected()
	await settle()

func enter_parked(driver: Node,uid: String,point: Vector2,mode: String) -> bool:
	var world: Node=driver.exploration.get_parent()
	for side in [-1,1]:
		var destination: Variant=world.to_global(Plan.Drive.world(point+Vector2(side*1.6,0),mode,.05))
		world.player.teleport_to(world.player.get_parent().to_local(destination))
		var candidate: Dictionary=driver.nearby(uid)
		if not candidate.is_empty() and driver.interact(candidate): return true
	return false

func drive_to(driver: Node,point: Vector2) -> bool:
	for frame in 1200:
		if driver.active.is_empty(): return false
		var braking: float=driver.speed*driver.speed/30.0+.15
		if driver.active["point"].distance_to(point)<maxf(.8,braking): break
		driver.step(1.0/60,Vector2.DOWN)
		driver.step_deliveries(1.0/60)
	for frame in 70:
		driver.step(1.0/60,Vector2.ZERO,true)
		driver.step_deliveries(1.0/60)
	return not driver.active.is_empty() and driver.active["point"].distance_to(point)<1.4 and absf(driver.speed)<.05

func tick(driver: Node,count: int) -> void:
	for frame in count: driver.step_deliveries(.15)

func screen(name: String) -> void:
	RenderingServer.force_draw(false)
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(output+"/"+name+".png")==OK,"Captured "+name)

func capture_settings(mode: String,panel: RefCounted) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	var line: LineEdit=panel.contract_fields["reward"].get_line_edit()
	for size in [Vector2i(1480,900),Vector2i(960,640)]:
		line.release_focus()
		root.size=size
		studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true} if size.x==960 else {})
		if size.x==960: studio.workspace_layout.library_toggle.button_pressed=false
		await settle()
		line.grab_focus()
		await settle()
		var bounds: Rect2=line.get_global_rect()
		check(line.has_focus() and panel.page.get_global_rect().encloses(bounds) and Rect2(Vector2.ZERO,Vector2(size)).encloses(bounds) and float(line.text)==45,"The reward is readable and reachable by keyboard: "+mode+" "+str([size,bounds,panel.page.get_global_rect(),line.text]))
		screen("settings_%s_%d"%[mode,size.x])
	line.release_focus()
	root.size=Vector2i(1480,900)
	studio.accessibility_settings.restore({})
	await settle()

func capture_cargo(mode: String,driver: Node,world: Node) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	var view: Node=driver.delivery_view
	var center: Vector2=driver.active["point"]
	var old_walking: bool=world.walking if mode=="3d" else false
	studio.set_process(false)
	for size in [Vector2i(1480,900),Vector2i(960,640)]:
		root.size=size
		studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true} if size.x==960 else {})
		if mode=="2d":
			world.camera.zoom=Vector2.ONE*2.7
			world.camera.position=Plan.Drive.world(center+Vector2(3,0),mode)
		else:
			world.walking=false
			world.target=Plan.Drive.world(center+Vector2(3,0),mode,.3)
			world.distance=19
			world.update_camera()
		studio.delivery_tools.tick(.2)
		await settle()
		studio.delivery_tools.tick(.2)
		view.refresh()
		await settle()
		check(view.panel.is_visible_in_tree() and view.caption.text.contains("Loading cargo") and is_instance_valid(view.marker) and is_instance_valid(view.cargo) and view.cargo.visible,"The real cargo and loading marker stay visible in the Walk HUD: "+mode+" "+str(size))
		screen("loading_%s_%d"%[mode,size.x])
	if mode=="3d": world.walking=old_walking
	root.size=Vector2i(1480,900)
	studio.accessibility_settings.restore({})
	studio.set_process(true)
	await settle()

func edges(mode: String) -> void:
	var data: Dictionary=await fixture(mode)
	var doc: RefCounted=data["doc"]
	var driver: Node=data["driver"]
	var runtime=driver.delivery
	doc.data["economy"]["starting_cash"]=20000
	doc.data["economy_account"]=Plan.Economy.fresh_account(doc.data,studio.library)
	studio.changed()
	await settle()
	await enter_car("van")
	studio.control_settings.execute("delivery_cargo")
	tick(driver,16)
	check(runtime.job.get("loaded")==3,"The live van holds cargo before the destination is removed: "+mode)
	var original_job: String=runtime.job.get("id","")
	check(driver.exit_vehicle() and enter_parked(driver,"small_van",data["start"]-Vector2(0,7),mode),"The player physically exits and enters the second van: "+mode)
	tick(driver,4)
	check(not driver.request_delivery() and runtime.job.get("id")==original_job and runtime.job.get("vehicle")=="van" and runtime.job.get("loaded")==3,"The load stays in the first van after an actual vehicle switch: "+mode)
	if not driver.active.is_empty(): driver.exit_vehicle(true)
	check(enter_parked(driver,"van",data["start"],mode),"The original loaded van can be entered again: "+mode)
	doc.checkpoint()
	doc.data["objects"].erase(doc.object("drop"))
	studio.changed()
	await settle()
	check(runtime.job.is_empty() and not runtime.sites.has("drop") and runtime.inventory("pickup").get("parcels")==8 and runtime.reward_total==0,"Deleting the receiving site cancels the task and returns the load with no reward: "+mode)
	studio._command("undo",null)
	await settle()
	var original: Dictionary=doc.data.duplicate(true)
	doc.object("pickup")["delivery_contract"]["deadline"]=2
	studio.changed()
	await settle()
	await enter_car("van")
	studio.control_settings.execute("delivery_cargo")
	tick(driver,12)
	check(runtime.job.get("phase")=="carrying" and runtime.job.get("loaded")==3,"Cargo loads before the short deadline elapses: "+mode)
	tick(driver,6)
	check(runtime.job.is_empty() and runtime.message.contains("deadline expired") and runtime.inventory("pickup").get("parcels")==8 and runtime.receipts.is_empty(),"The monotonic deadline expires and restores the load without payout: "+mode)
	studio.set_walking(false)
	doc.data=original.duplicate(true)
	studio.changed()
	await settle()
	select("pickup","deliveries")
	studio._command("duplicate",null)
	await settle()
	var single: Dictionary=doc.object(studio.selected_uid)
	check(single.get("uid")!="pickup" and single.get("delivery_contract",{}).get("enabled")==false and single["delivery_contract"]["destination"].is_empty(),"A lone copied pickup keeps the settings and disables its external contract link: "+mode+" "+studio.status.text)
	studio._command("undo",null)
	await settle()
	studio.selected_uid="pickup"
	studio.selected_uids.assign(["pickup","drop"])
	studio._command("duplicate",null)
	await settle()
	var copied: Array=studio.selected_uids.duplicate()
	check(copied.size()==2 and copied[0]!="pickup" and copied[1]!="drop" and doc.object(copied[0]).get("delivery_contract",{}).get("destination")==copied[1],"Copying both sites remaps the destination to the new loading pad: "+mode+" "+studio.status.text)
	studio._command("undo",null)
	await settle()
	check(doc.data==original,"Undo of the paired copy restores the exact source and treasury: "+mode)
	var damaged: Dictionary=doc.data.duplicate(true)
	for item in damaged["objects"]:
		if item["uid"]=="pickup": item["delivery_site"]["stock"]["parcels"]=999
		if item["uid"]=="van": item["asset"]="3d:Unavailable/Delivery"
	var repair:=Repair.new(studio.library)
	var restored: Dictionary=repair.world(damaged,mode,"test/delivery",0)
	var records: Dictionary={}
	for item in restored["objects"]: records[item["uid"]]=item
	check(Document.valid(restored,mode,studio.library) and not records["pickup"].has("delivery_site") and repair.issues.any(func(issue: Dictionary)->bool:return issue["path"].ends_with("delivery_site")),"Repair archives the excessive stock and keeps the site art: "+mode)
	check(not records["van"].has("delivery_vehicle") and records["van"]["missing_asset"]["record"].get("delivery_vehicle",{}).get("capacity")==8,"A missing van archives the original delivery metadata for recovery: "+mode)

func workflow(mode: String) -> void:
	var data: Dictionary=await fixture(mode)
	var doc: RefCounted=data["doc"]
	var driver: Node=data["driver"]
	var runtime=driver.delivery
	var original: Dictionary=doc.data.duplicate(true)
	select("pickup","deliveries")
	var panel: RefCounted=studio.delivery_tools
	check(panel.page.is_visible_in_tree() and panel.site_box.visible and panel.contract_fields["destination"].get_selected_metadata()=="drop","The normal inspector exposes the saved drop-off: "+mode)
	await capture_settings(mode,panel)
	panel.contract_fields["reward"].value=49
	panel.apply_settings()
	check(doc.object("pickup")["delivery_contract"]["reward"]==49 and doc.data["economy_account"]==original["economy_account"],"Changing an offer is authored history without a treasury charge: "+mode)
	studio._command("undo",null)
	await settle()
	check(doc.data==original,"Undo restores the original offer and treasury: "+mode)
	await enter_car("van")
	check(not driver.active.is_empty() and driver.active["item"]["uid"]=="van","The normal drive command enters the actual delivery van: "+mode)
	if driver.active.is_empty(): return
	var pose: Dictionary=driver.delivery_pose()
	check(not runtime.request("small_van",pose,12) and runtime.message.contains("cargo capacity"),"A stopped under-capacity vehicle receives an actionable reason: "+mode)
	studio.control_settings.execute("delivery_cargo")
	for frame in 20:
		if runtime.job.get("phase")!="routing": break
		driver.step_deliveries(.001)
	tick(driver,4)
	check(runtime.job.get("phase")=="loading" and runtime.job.get("loaded",0)==1 and runtime.inventory("pickup")["parcels"]==7,"One unit physically stages into the van before loading completes: "+mode+" "+str(runtime.job))
	if runtime.job.is_empty(): return
	var held: Vector2=driver.active["point"]
	driver.step(.1,Vector2.DOWN)
	check(driver.active["point"]==held,"Throttle cannot move the van while cargo is being handled: "+mode)
	await settle()
	check(is_instance_valid(driver.delivery_view.cargo) and driver.delivery_view.cargo.visible,"The real supplied cargo has a visible scene instance: "+mode)
	await capture_cargo(mode,driver,data["world"])
	var cargo_position: Variant=driver.delivery_view.cargo.position
	tick(driver,1)
	driver.delivery_view.update_cargo()
	check(driver.delivery_view.cargo.position.distance_to(cargo_position)>.001,"Loading moves the supplied crate between the pad and van: "+mode)
	studio.control_settings.execute("delivery_cancel")
	check(runtime.job.is_empty() and runtime.inventory("pickup")["parcels"]==8 and runtime.reward_total==0,"Cancelling partial loading restores the original pickup stock: "+mode)
	studio.control_settings.execute("delivery_cargo")
	tick(driver,16)
	check(runtime.job.get("phase")=="carrying" and runtime.job.get("loaded")==3 and runtime.inventory("pickup")["parcels"]==5,"The original van holds the three reserved units: "+mode)
	if runtime.job.get("phase")!="carrying": return
	check(not runtime.request("small_van",pose,12) and runtime.message.contains("original delivery vehicle"),"Changing vehicles cannot transfer the contract or cargo: "+mode)
	var original_ticket: String=runtime.job["id"]
	Plan.Traffic.Roads.paint(doc.data,Vector2i(0,2),Vector2i(0,2),true)
	studio.changed()
	await settle()
	tick(driver,10)
	check(runtime.job.get("phase")=="blocked" and runtime.job.get("loaded")==3 and runtime.inventory("pickup")["parcels"]==5,"A removed connecting road blocks delivery and retains the load: "+mode+" "+str(runtime.job))
	Plan.Traffic.Roads.paint(doc.data,Vector2i(0,2),Vector2i(0,2))
	studio.changed()
	await settle()
	tick(driver,10)
	check(runtime.job.get("phase")=="carrying" and runtime.job["id"]==original_ticket and runtime.job["route"].size()>3 and runtime.job["loaded"]==3 and runtime.inventory("pickup")["parcels"]==5,"Restoring the road re-routes the same job and load: "+mode+" "+str(runtime.job))
	check(drive_to(driver,data["finish"]),"The van drives to the separate drop-off through real physics: "+mode+" "+str([driver.active.get("point"),driver.notice]))
	driver.business_clock.hour=23
	studio.control_settings.execute("delivery_cargo")
	check(runtime.job.get("phase")=="carrying" and runtime.message.contains("closed"),"A closed shop retains all cargo in the original van: "+mode)
	driver.business_clock.hour=12
	studio.control_settings.execute("delivery_cargo")
	tick(driver,4)
	check(runtime.job.get("phase")=="unloading" and runtime.job.get("staged")==1 and not runtime.inventory("drop").has("parcels"),"Unloading animates staged cargo before the receiving stock commits: "+mode)
	driver.business_clock.hour=23
	tick(driver,1)
	check(runtime.job.get("phase")=="carrying" and runtime.job.get("loaded")==3 and not runtime.inventory("drop").has("parcels") and runtime.reward_total==0,"Closing mid-unload returns staged units to the van without credit: "+mode)
	driver.business_clock.hour=12
	studio.control_settings.execute("delivery_cargo")
	tick(driver,12)
	var receipt: Dictionary=runtime.complete(original_ticket,"van",driver.delivery_pose(),12)
	check(runtime.job.is_empty() and receipt.get("quantity")==3 and runtime.inventory("drop").get("parcels")==3 and runtime.reward_total==45,"Physical drop-off settles inventory and preview reward exactly once: "+mode+" "+str(runtime.message))
	check(runtime.complete(original_ticket,"small_van",pose,12).is_empty() and runtime.receipts.size()==1 and runtime.reward_total==45,"Receipt replay from a different vehicle cannot award a second reward: "+mode)
	check(doc.data["economy_account"]==original["economy_account"],"Delivery rewards leave the authoritative treasury intact: "+mode)
	studio.set_walking(false)
	check(runtime.receipts.is_empty() and runtime.reward_total==0 and runtime.inventory("pickup")["parcels"]==8,"Leaving Walk resets stock, jobs, rewards and receipts together: "+mode)
	doc.data["roads"]=original["roads"].duplicate(true)
	studio.changed()
	var path: String=output+"/delivery_"+mode+".isocity.json"
	check(studio.write_project(path,false),"Normal save persists the authored delivery offer: "+mode)
	var repair:=Repair.new(studio.library)
	var loaded: Dictionary=repair.read(path)
	check(loaded["ok"] and repair.issues.is_empty(),"Normal reopen validates delivery settings without repair: "+mode+" "+str(repair.issues))
	if "--packages" in OS.get_cmdline_user_args():
		var bundle: Dictionary=Portable.new().save(data["world"],doc.data,studio.library,output+"/delivery_"+mode+".zip")
		check(bundle["ok"],"Portable export contains the future cargo dependencies: "+mode+" "+str(bundle))

func run() -> void:
	if OS.has_environment("ISOCITY_DELIVERY_OUTPUT"): output=OS.get_environment("ISOCITY_DELIVERY_OUTPUT")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
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
		if "--edges" in OS.get_cmdline_user_args(): await edges(mode)
	studio.free()
	await settle()
	print("LOCAL DELIVERIES: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
