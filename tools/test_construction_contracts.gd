extends "res://tools/test_local_deliveries.gd"

const Construction=preload("res://scripts/builder/construction_plan.gd")
const Scenarios=preload("res://scripts/builder/scenario_plan.gd")

func choose(field: OptionButton,id: String) -> bool:
	for index in field.item_count:
		if field.get_item_metadata(index)==id:
			field.select(index)
			field.item_selected.emit(index)
			return true
	return false

func station(doc: RefCounted,uid: String,asset: String,at: Vector2,pad: Vector2,stock: Dictionary) -> void:
	var mode: String=doc.data["mode"]
	var item: Dictionary=doc.add(asset,Plan.Traffic.world(at,mode),"180",.65)
	item["uid"]=uid
	item["delivery_site"]={"enabled":true,"stock":stock,"capacity":12}
	var offset: Vector2=pad-Plan.loading_point(item,mode,studio.library)
	item["delivery_site"].merge({"offset_x":offset.x,"offset_z":offset.y})

func setup_site(mode: String) -> Dictionary:
	studio.switch_mode(mode)
	var doc:=Document.new()
	doc.data=Templates.make(mode,"blank")
	var start:=Vector2(-16,10)
	var finish:=Vector2(24,10)
	doc.data["roads"]=[]
	for index in range(-6,8): doc.data["roads"].append({"cell":[index,0]})
	station(doc,"supply",Construction.recipe()["supply"],start+Vector2(0,7),start,{"masonry":8,"parcels":2})
	station(doc,"site",Construction.recipe()["site"],finish+Vector2(0,7),finish,{})
	add_vehicle(doc,"van",start,8)
	add_vehicle(doc,"small_van",start-Vector2(12,0),2)
	for id in ["van","small_van"]:
		var vehicle: Dictionary=doc.object(id)
		var direction: String=Plan.Drive.direction(vehicle,PI*.5)
		var at: Vector2=start if id=="van" else start-Vector2(12,0)
		vehicle["direction"]=direction
		vehicle["position"]=Plan.Traffic.world(at-Plan.Drive.Roads.center_offset(studio.library,vehicle["asset"],direction,vehicle["scale"],mode)*(2 if mode=="2d" else 1),mode)
	doc.data["economy"]={"enabled":true,"starting_cash":900}
	doc.data["economy_account"]=Plan.Economy.fresh_account(doc.data,studio.library)
	studio.economy_tools.pauses[mode]=true
	studio.documents[mode]=doc
	studio.changed()
	await settle()
	var world: Node=studio.worlds[mode]
	var driver: Node=world.exploration.driving
	driver.set_physics_process(false)
	driver.business_clock.set_physics_process(false)
	driver.business_clock.hour=12
	return {"doc":doc,"world":world,"driver":driver,"start":start,"finish":finish}

func walk_to(world: Node,point: Vector2,height: float=0.0) -> void:
	var local: Variant=Plan.Drive.world(point,world.exploration.dimension,height+.05)
	world.player.teleport_to(world.player.get_parent().to_local(world.to_global(local)))
	if world.exploration.dimension=="2d": world.player.set_meta("terrain_height",height)

func capture_setup(mode: String,challenge: RefCounted) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	for size in [Vector2i(1480,900),Vector2i(960,640)]:
		challenge.construction_site.release_focus()
		root.size=size
		studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true} if size.x==960 else {})
		if size.x==960: studio.workspace_layout.library_toggle.button_pressed=false
		await settle()
		challenge.construction_site.grab_focus()
		await settle()
		var bounds: Rect2=challenge.construction_site.get_global_rect()
		var back: Button=studio.consumer_shell.expert_return
		check(challenge.construction_site.has_focus() and bounds.intersects(challenge.panel.get_global_rect()) and Rect2(Vector2.ZERO,Vector2(size)).encloses(bounds) and (not back.visible or not back.get_global_rect().intersects(bounds)),"The site picker is reachable by keyboard at the selected size: "+mode+" "+str([size,bounds]))
		screen("contract_setup_%s_%d"%[mode,size.x])
	challenge.construction_site.release_focus()
	root.size=Vector2i(1480,900)
	studio.accessibility_settings.restore({})
	await settle()

func capture_work(data: Dictionary,mode: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	var world: Node=data["world"]
	var driver: Node=data["driver"]
	var task: Dictionary=driver.construction.next_task()
	var view: Node=driver.delivery_view
	var point: Vector2=task["bounds"].get_center().lerp(task["approach"],.35)
	var walking: bool=world.walking if mode=="3d" else false
	studio.set_process(false)
	for size in [Vector2i(1480,900),Vector2i(960,640)]:
		root.size=size
		studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true} if size.x==960 else {})
		if mode=="2d":
			world.camera.zoom=Vector2.ONE*2.7
			world.camera.position=Plan.Drive.world(point+Vector2(1.6,0),mode)
		else:
			world.walking=false
			world.target=Plan.Drive.world(point,mode,.3)
			world.distance=15
			world.update_camera()
		studio.delivery_tools.tick(.2)
		await settle()
		studio.scenario_tools.tick(.3)
		studio.consumer_shell.tick(.3)
		view.refresh()
		view.action.grab_focus()
		await settle()
		var canvas: Rect2=studio.canvas.get_global_rect()
		var scale_factor: Vector2=canvas.size/driver.get_viewport().get_visible_rect().size
		var action_rect: Rect2=view.action.get_global_rect()
		var onscreen:=Rect2(canvas.position+action_rect.position*scale_factor,action_rect.size*scale_factor)
		var back: Button=studio.consumer_shell.expert_return
		check(view.panel.is_visible_in_tree() and view.action.has_focus() and not view.action.disabled and is_instance_valid(view.marker) and view.caption.text.contains(task["title"]) and studio.scenario_tools.badge.text.contains("2/3 goals") and (size.x!=960 or view.action.custom_minimum_size.y==44) and (not back.visible or not back.get_global_rect().intersects(onscreen)),"The marked work point, real progress and reachable Install action stay visible: "+mode+" "+str([size,onscreen]))
		screen("contract_work_%s_%d"%[mode,size.x])
	view.action.release_focus()
	if mode=="3d": world.walking=walking
	root.size=Vector2i(1480,900)
	studio.accessibility_settings.restore({})
	studio.set_process(true)
	await settle()

func workflow_contract(mode: String) -> void:
	var fixture_data: Dictionary=await setup_site(mode)
	var doc: RefCounted=fixture_data["doc"]
	var driver: Node=fixture_data["driver"]
	var world: Node=fixture_data["world"]
	var challenge: RefCounted=studio.scenario_tools
	var baseline: Dictionary=doc.data.duplicate(true)
	var proof: Dictionary=Scenarios.begin(baseline,"construction",studio.library,"proof","site",[0,0,0],"supply")
	check(proof.get("ok",false),"The actual supply, roads and work area form a safe contract: "+mode+" "+str(proof.get("reason","")))
	if not proof.get("ok",false): return
	var protected: Dictionary=baseline.duplicate(true)
	protected["protected_areas"]=[{"uid":"reserved","name":"Protected work area","owner":"host","rect":[18,25,12,12]}]
	check(not Scenarios.begin(protected,"construction",studio.library,"protected","site",[0,0,0],"supply")["ok"],"Protected work area blocks the proposed contract before authoring: "+mode)
	var wrong: Dictionary=baseline.duplicate(true)
	wrong["objects"][0]["delivery_site"]["stock"]={"parcels":8}
	check(not Scenarios.begin(wrong,"construction",studio.library,"wrong","site",[0,0,0],"supply")["ok"],"Parcels cannot substitute for masonry: "+mode)
	var roadside: Dictionary=baseline.duplicate(true)
	roadside["objects"][1]["delivery_site"]["offset_z"]-=10
	check(not Scenarios.begin(roadside,"construction",studio.library,"road","site",[0,0,0],"supply")["ok"],"A loading pad on the road is an unsafe starting configuration: "+mode)
	studio._command("challenges",null)
	check(choose(challenge.choice,"construction") and choose(challenge.construction_supply,"supply") and choose(challenge.construction_site,"site"),"The actual Challenges page selects both authored stations: "+mode)
	await capture_setup(mode,challenge)
	challenge.start_challenge()
	await settle()
	check(Construction.enabled(doc.data) and Document.valid(doc.data,mode,studio.library) and doc.data["objects"]==baseline["objects"] and doc.data["economy_account"]==baseline["economy_account"],"Starting the challenge saves its setup without altering placements or the treasury: "+mode)
	if not Construction.enabled(doc.data): return
	var authored: Dictionary=doc.data.duplicate(true)
	studio._command("undo",null)
	await settle()
	check(doc.data==baseline,"Ordinary Undo restores the exact previous city and balance: "+mode)
	studio._command("redo",null)
	await settle()
	check(doc.data==authored,"Ordinary Redo restores the exact contract identity: "+mode)
	var attempt: String=doc.data["scenario"]["attempt"]
	var manager: Node=driver.construction
	check(driver.delivery.offers.get("supply",{}).get("construction_attempt")==attempt and manager.next_task().is_empty(),"The haul is available with no equipment before receiving masonry: "+mode)
	if "--packages" in OS.get_cmdline_user_args():
		var package: Dictionary=Portable.new().save(world,doc.data,studio.library,output+"/construction_contract_"+mode+".zip")
		check(package["ok"],"The licensed portable package captures future materials and work steps: "+mode+" "+str(package))
	await enter_car("van")
	var original_pose: Dictionary=driver.delivery_pose()
	check(not driver.delivery.request("small_van",original_pose,12) and driver.delivery.message.contains("capacity"),"The four-unit contract rejects the undersized van: "+mode)
	check(not original_pose.is_empty() and driver.request_delivery(),"The actual driver accepts the masonry haul on the supply pad: "+mode+" "+driver.delivery.message)
	tick(driver,6)
	check(driver.delivery.job.get("loaded",0)>0 and driver.delivery.job.get("loaded",0)<4,"Loading transfers only the units already handled: "+mode)
	driver.cancel_delivery()
	check(driver.delivery.job.is_empty() and driver.delivery.inventory("supply").get("masonry")==8 and manager.reward_total==0 and manager.terminal.has(attempt),"Cancel restores partial cargo, closes the attempt and pays nothing: "+mode)
	studio.set_walking(false)
	await settle()
	await enter_car("van")
	check(not manager.terminal.has(attempt) and driver.request_delivery(),"A new Walk session starts the saved setup with independent stock and receipts: "+mode)
	tick(driver,32)
	check(driver.delivery.job.get("phase")=="carrying" and driver.delivery.job.get("loaded")==4 and driver.delivery.inventory("supply")["masonry"]==4,"The real van loads all four masonry units: "+mode)
	var moved: bool=drive_to(driver,fixture_data["finish"])
	check(moved,"Driving physics takes the loaded van to the separate site apron: "+mode+" "+str(driver.active.get("point")))
	check(driver.request_delivery(),"The same stopped vehicle can unload at the site office: "+mode+" "+driver.delivery.message)
	tick(driver,32)
	check(manager.hauled==4 and manager.materials==4 and manager.reward_total==0 and driver.delivery.reward_total==0 and driver.delivery.inventory("site")["masonry"]==0,"Only the exact settled haul transfers reserved masonry and earns no early payment: "+mode)
	if manager.materials!=4: return
	var haul: Dictionary=driver.delivery.receipts.values().back()
	manager.receive(haul)
	check(manager.materials==4,"Replaying the haul receipt does not duplicate materials: "+mode)
	check(driver.exit_vehicle(),"The real van provides a clear on-foot dismount at the work site: "+mode)
	var task: Dictionary=manager.next_task()
	walk_to(world,task["bounds"].get_center(),task["height"])
	check(not manager.work() and manager.completed_tasks==0,"Standing in the placement area cannot create equipment: "+mode)
	for phase in 3:
		task=manager.next_task()
		if task.is_empty(): check(false,"An ordered physical work point exists: "+mode); break
		walk_to(world,task["approach"],task["height"])
		await settle()
		check(world.exploration.interaction_prompt().contains(task["title"]),"The normal interaction prompt names the reachable work step: "+mode)
		if phase==2: await capture_work(fixture_data,mode)
		world.exploration.interact()
		check(manager.completed_tasks==phase+1 and is_instance_valid(manager.models) and manager.models.has_node(task["id"]) and manager.reward_total==(150 if phase==2 else 0),"A real interaction places the specified model and only the final step pays: "+mode+" "+manager.message)
	check(Scenarios.construction_progress(manager)["complete"] and manager.receipts.size()==1 and not manager.work() and not manager.cancel() and manager.reward_total==150 and doc.data==authored,"The scenario reports actual completion with one reward and leaves authored content exact: "+mode)
	studio.set_walking(false)
	await settle()
	check(not is_instance_valid(manager.models) and manager.reward_total==0 and manager.receipts.is_empty() and doc.data==authored,"Returning to Build clears equipment, cargo progress and preview settlement together: "+mode)
	var saved: String=output+"/contract_"+mode+".isocity.json"
	check(studio.write_project(saved,false) and studio.load_project(saved),"The ordinary save and load preserve the selected stations and attempt: "+mode)
	await settle()
	check(studio.current().data["scenario"]==authored["scenario"] and driver.construction.completed_tasks==0 and driver.construction.receipts.is_empty(),"Reopen retains authored setup with clean private activity state: "+mode)
	if "--edges" in OS.get_cmdline_user_args(): await interruption(fixture_data,authored,mode)

func interruption(data: Dictionary,authored: Dictionary,mode: String) -> void:
	var doc: RefCounted=studio.current()
	var driver: Node=data["driver"]
	var manager: Node=driver.construction
	var world: Node=data["world"]
	for interruption_kind in ["removed_site","removed_supply","protected"]:
		var after_haul: bool=interruption_kind!="removed_site"
		await enter_car("van")
		var accepted: bool=driver.request_delivery()
		tick(driver,32)
		var moved: bool=drive_to(driver,data["finish"])
		check(accepted and moved and driver.request_delivery(),"A fresh van reaches the receiving pad for the interruption fixture: "+mode)
		tick(driver,32 if after_haul else 6)
		if interruption_kind=="protected":
			var task: Dictionary=manager.next_task()
			if task.is_empty(): check(false,"Delivered stock reached the first work step: "+mode); return
			driver.exit_vehicle()
			walk_to(world,task["approach"],task["height"])
			await settle()
			world.exploration.interact()
			check(manager.completed_tasks==1 and manager.models.get_child_count()==1,"The interrupted attempt had already installed one barrier: "+mode)
			var bounds: Rect2=manager.next_task()["bounds"].grow(.2)
			doc.data["protected_areas"]=[{"uid":"work","name":"Protected working area","owner":"host","rect":[bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y]}]
		elif interruption_kind=="removed_site":
			check(driver.delivery.job.get("staged",0)>0 and driver.delivery.job["staged"]<4,"The removed site had only partly unloaded the load: "+mode)
			doc.data["objects"]=doc.data["objects"].filter(func(item: Dictionary):return item["uid"]!="site")
		else:
			check(manager.materials==4 and manager.reward_total==0,"The supply was removed after delivery and before placement: "+mode)
			doc.data["objects"]=doc.data["objects"].filter(func(item: Dictionary):return item["uid"]!="supply")
		studio.changed()
		await settle()
		var account: Dictionary=doc.data["economy_account"]
		var expected: Dictionary=authored["economy_account"]
		var balance_keys: Array=["cash","construction_total","refund_total"]
		var exact: bool=account==expected if interruption_kind=="protected" else balance_keys.all(func(key: String)->bool:return account.get(key)==expected.get(key))
		var stock: Dictionary=driver.delivery.inventory("supply")
		var settled: bool=stock.is_empty() and manager.message.contains("cleared") if interruption_kind=="removed_supply" else stock.get("masonry")==8
		check(driver.delivery.job.is_empty() and settled and manager.materials==0 and not is_instance_valid(manager.models) and manager.reward_total==0 and manager.receipts.is_empty() and exact,"The interrupted job clears all equipment and settles stock with no preview or authored payout: "+str([mode,interruption_kind,driver.delivery.job,stock,manager.materials,manager.message,exact]))
		studio.set_walking(false)
		doc.data=authored.duplicate(true)
		studio.changed()
		await settle()

func run() -> void:
	output=OS.get_environment("ISOCITY_CONTRACT_OUTPUT")
	if output.is_empty(): output="res://output/construction_contract_fixture"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size=Vector2i(1480,900)
	studio=load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled=false
	root.add_child(studio)
	await settle()
	if studio.consumer_shell:
		studio.consumer_shell.dismiss_welcome()
		studio.consumer_shell.set_active("--simple" in OS.get_cmdline_user_args(),false)
	for mode in ["2d","3d"]: await workflow_contract(mode)
	studio.free()
	await process_frame
	print("CONSTRUCTION CONTRACTS: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
