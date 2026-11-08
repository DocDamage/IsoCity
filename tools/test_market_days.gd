extends SceneTree

const Plan=preload("res://scripts/builder/market_plan.gd")
const Doc=preload("res://scripts/builder/document.gd")
const Templates=preload("res://scripts/builder/templates.gd")
const Repair=preload("res://scripts/builder/project_repair.gd")
const Portable=preload("res://scripts/builder/portable_export.gd")
var studio: Control
var checks: int=0
var failures: int=0
var output: String="res://output/market_fixture"

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

func place(doc: RefCounted,uid: String,asset: String,at: Vector2,scale_value: float=.6) -> Dictionary:
	var item: Dictionary=doc.add(asset,Plan.Traffic.world(at,doc.data["mode"]),studio.library.directions(asset)[0],scale_value)
	item["uid"]=uid
	return item

func fixture(mode: String,residents: bool=false) -> Dictionary:
	studio.switch_mode(mode)
	studio.set_walking(false)
	var doc:=Doc.new()
	doc.data=Templates.make(mode,"blank")
	studio.documents[mode]=doc
	var asset: String="2d:Supermarket" if mode=="2d" else "3d:HanX_Shop/Shop_Grocery"
	var host: Dictionary=place(doc,"market",asset,Vector2(0,-16))
	host["name"]="Neighborhood market"
	host["market"]={"enabled":true,"offset_z":16.0,"capacity":3,"queue":2,"vendors":[{"kind":"fruit","stock":3 if residents else 2,"price":5}]}
	if not residents: host["market"]["vendors"].append({"kind":"vegetables","stock":1,"price":7})
	var home: Dictionary=place(doc,"home","2d:House_Blue",Vector2(0,16))
	home["citizen_role"]="home"
	place(doc,"permanent","3d:HanX_Shop/Stall_Umbrella",Vector2(-18,10),.5)
	doc.data["economy"]={"enabled":true,"starting_cash":1200}
	doc.data["economy_account"]=Plan.Economy.fresh_account(doc.data,studio.library)
	studio.economy_tools.pauses[mode]=true
	doc.data["citizens"]={"enabled":residents,"population":4,"day_length":3600,"start_hour":12.2 if residents else 10.0}
	studio.changed()
	await settle()
	var manager: Node=studio.business_tools.managers[mode]
	var citizens: Node=studio.citizen_tools.managers[mode]
	manager.set_physics_process(false)
	citizens.set_physics_process(false)
	manager.reset()
	manager.configure(doc.data,studio.library,studio.worlds[mode].instances,studio.worlds[mode].exploration,citizens)
	manager.hour=12.2 if residents else 10.0
	manager.step(.016,false)
	check(manager.market.sites.has("market") and manager.market.sites["market"]["problem"].is_empty(),"The reviewed host compiles with a clear vendor row: "+mode+" "+str(manager.market.notices))
	return {"doc":doc,"world":studio.worlds[mode],"manager":manager,"citizens":citizens,"asset":asset}

func clock(manager: Node,hour: float,seconds: float=.016) -> void:
	manager.hour=hour
	manager.step(seconds,false)

func put_player(world: Node,point: Vector2,mode: String) -> void:
	var coordinates: Array=Plan.Traffic.world(point,mode,.03)
	var local: Variant=Vector2(coordinates[0],coordinates[1]) if mode=="2d" else Vector3(coordinates[0],coordinates[1],coordinates[2])
	world.player.teleport_to(world.player.get_parent().to_local(world.to_global(local)))

func buy(manager: Node) -> void:
	studio.control_settings.execute("business")
	for tick in 12: manager.step(.2,false)

func capture(name: String) -> void:
	RenderingServer.force_draw(false)
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(output+"/"+name+".png")==OK,"Captured "+name)

func capture_settings(mode: String,tools: RefCounted) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	var line: LineEdit=tools.stalls[0]["price"].get_line_edit()
	for size in [Vector2i(1480,900),Vector2i(960,640)]:
		line.release_focus()
		root.size=size
		studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true} if size.x==960 else {})
		if size.x==960: studio.workspace_layout.library_toggle.button_pressed=false
		await settle()
		line.grab_focus()
		await settle()
		var bounds: Rect2=line.get_global_rect()
		check(line.has_focus() and tools.panel.get_global_rect().encloses(bounds) and Rect2(Vector2.ZERO,Vector2(size)).encloses(bounds) and float(line.text)==5,"The vendor price is readable and keyboard reachable: "+mode+" "+str([size,bounds,tools.panel.get_global_rect(),line.text]))
		capture("settings_%s_%d"%[mode,size.x])
	line.release_focus()
	root.size=Vector2i(1480,900)
	studio.accessibility_settings.restore({})
	await settle()

func capture_checkout(mode: String,world: Node,manager: Node) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	var walking: bool=world.walking if mode=="3d" else false
	var point: Vector2=manager.market.vendors[Plan.market_id("market",0)]["point"]+Vector2(1,-.8)
	studio.set_process(false)
	for size in [Vector2i(1480,900),Vector2i(960,640)]:
		root.size=size
		studio.accessibility_settings.restore({"text_scale":1.5,"large_targets":true,"high_contrast":true} if size.x==960 else {})
		if mode=="2d":
			var at: Array=Plan.Traffic.world(point,mode)
			world.camera.zoom=Vector2.ONE*2.8
			world.camera.position=Vector2(at[0],at[1])
		else:
			world.walking=false
			world.target=Vector3(point.x,.25,point.y)
			world.distance=15
			world.update_camera()
		await settle()
		studio.business_tools.tick(.2)
		manager.update_ui()
		await settle()
		check(manager.panel.is_visible_in_tree() and manager.caption.text.contains("Checking out") and manager.market_view.displays.size()==2,"The checkout status and both real stalls remain visible: "+mode+" "+str(size))
		if size.x==960:
			manager.cancel_button.grab_focus()
			await settle()
			check(manager.cancel_button.has_focus() and manager.scroll.get_global_rect().encloses(manager.cancel_button.get_global_rect()),"Keyboard focus reveals the live Cancel action at compact size: "+mode)
		capture("checkout_%s_%d"%[mode,size.x])
	manager.cancel_button.release_focus()
	if mode=="3d": world.walking=walking
	root.size=Vector2i(1480,900)
	studio.accessibility_settings.restore({})
	studio.set_process(true)
	await settle()

func workflow(mode: String) -> void:
	var data: Dictionary=await fixture(mode)
	var doc: RefCounted=data["doc"]
	var manager: Node=data["manager"]
	var world: Node=data["world"]
	var market=manager.market
	var original: Dictionary=doc.data.duplicate(true)
	var fruit: String=Plan.market_id("market",0)
	var veg: String=Plan.market_id("market",1)
	check(market.active.is_empty() and manager.market_view.displays.is_empty(),"The closed market has no temporary stalls: "+mode)
	select("market","markets")
	var tools: RefCounted=studio.market_tools
	check(tools.panel.is_visible_in_tree() and tools.stalls[0]["stock"].value==2,"The normal inspector exposes the saved stall stock: "+mode)
	await capture_settings(mode,tools)
	tools.stalls[0]["price"].value=9
	tools.apply_settings()
	check(doc.object("market")["market"]["vendors"][0]["price"]==9 and doc.data["economy_account"]==original["economy_account"],"A market price is authored history without a treasury charge: "+mode)
	studio._command("undo",null)
	await settle()
	check(doc.data==original,"Undo restores the exact market settings and treasury: "+mode)
	clock(manager,12)
	check(market.active.has("market") and market.vendors.size()==2 and manager.market_view.displays.size()==2 and doc.data==original,"Opening creates two event-owned stalls and no authored objects: "+mode+" "+str(market.notices))
	if not market.active.has("market"): return
	check(manager.market_view.displays[fruit]["goods"].visible and manager.market_view.displays[veg]["markers"].get_child_count()==3,"Reviewed goods and each physical queue marker are instantiated: "+mode)
	studio.set_walking(true)
	put_player(world,market.vendors[fruit]["point"],mode)
	await settle()
	buy(manager)
	check(market.count(fruit)==1 and market.revenue==5 and manager.service.inventory.get("player",{}).get("Market fruit")==1,"The normal business action settles one real purchase: "+mode+" "+manager.message)
	studio.control_settings.execute("business")
	manager.step(.5,false)
	var incomplete: Dictionary=manager.service.visits.get("player",{})
	check(incomplete.get("state")=="active","Closing fixture begins with an active checkout: "+mode)
	await capture_checkout(mode,world,manager)
	clock(manager,15,2.5)
	check(incomplete.get("state")=="cancelled" and market.revenue==5 and market.active.is_empty() and manager.market_view.displays.is_empty() and world.instances.has("permanent"),"Closing cancels unfinished sales and frees only event-owned art: "+mode)
	clock(manager,12)
	check(market.count(fruit)==1,"Reopening within the same day preserves finite stock: "+mode)
	buy(manager)
	buy(manager)
	check(market.count(fruit)==0 and market.revenue==10 and market.receipts.size()==2 and manager.message.contains("Sold out") and not manager.market_view.displays[fruit]["goods"].visible,"Stock exhaustion prevents more sales and clears the display: "+mode+" "+manager.message)
	var receipt: int=market.receipts.keys()[0]
	check(not market.settle({"sequence":receipt,"business":fruit}) and market.revenue==10,"Replayed purchase receipts cannot add revenue: "+mode)
	doc.data["weather"]={"enabled":true,"condition":"rain","intensity":.8}
	studio.changed()
	await settle()
	clock(manager,12)
	check(market.active.is_empty() and market.notices["market"].contains("rain"),"The configured rain policy closes the event: "+mode)
	doc.data.erase("weather")
	studio.changed()
	await settle()
	clock(manager,23.99)
	manager.step(2.0,true)
	clock(manager,12)
	check(manager.preview_day==1 and market.count(fruit)==2 and market.revenue==10,"A real day wrap seeds tomorrow's stock once without resetting receipts: "+mode+" "+str(manager.preview_day))
	studio.set_walking(false)
	var other: Dictionary=place(doc,"overlap",data["asset"],Vector2(24,-16))
	other["market"]=doc.object("market")["market"].duplicate(true)
	other["market"]["offset_x"]=-24.0
	studio.changed()
	await settle()
	clock(manager,12)
	check(market.active.keys()==["market"] and market.notices["overlap"].contains("Another open market"),"Two overlapping events have one deterministic winner: "+mode)
	place(doc,"obstruction","2d:House_Blue",Vector2(-3,0),1)
	studio.changed()
	await settle()
	clock(manager,12)
	check(market.active.is_empty() and market.sites["market"]["problem"].contains("overlaps"),"A permanent obstruction prevents temporary stalls from spawning: "+mode+" "+str(market.notices))
	doc.data["objects"].erase(doc.object("obstruction"))
	doc.data["objects"].erase(other)
	doc.object("market")["market"]["enabled"]=false
	studio.changed()
	await settle()
	clock(manager,12)
	check(market.active.is_empty() and market.sites.is_empty() and manager.market_view.displays.is_empty(),"Disabling the event removes temporary stalls and leaves the host: "+mode)
	doc.object("market")["market"]["enabled"]=true
	doc.object("market")["market"]["stock_policy"]="creative"
	doc.object("market")["market"]["vendors"][0]["stock"]=0
	studio.changed()
	await settle()
	clock(manager,12)
	studio.set_walking(true)
	put_player(world,market.vendors[fruit]["point"],mode)
	await settle()
	buy(manager)
	check(market.count(fruit)==-1 and market.revenue==15,"Creative stock continues selling at the configured preview price: "+mode)
	studio.set_walking(false)
	doc.data=original.duplicate(true)
	studio.changed()
	await settle()
	check(doc.data["economy_account"]==original["economy_account"],"Sales and temporary setup leave the authored treasury exact: "+mode)
	var path: String=output+"/market_"+mode+".isocity.json"
	check(studio.write_project(path,false),"Normal save persists the market schedule: "+mode)
	var repair:=Repair.new(studio.library)
	var loaded: Dictionary=repair.read(path)
	check(loaded["ok"] and repair.issues.is_empty(),"Normal reopen validates the authored market without repair: "+mode+" "+str(repair.issues))
	if "--packages" in OS.get_cmdline_user_args():
		var exporter:=Portable.new()
		var restricted: Dictionary=exporter.save(world,doc.data,studio.library,output+"/restricted_market_"+mode+".zip")
		check(not restricted["ok"] and restricted["message"].contains("Supermarket kit restricts"),"The license gate protects restricted supermarket art: "+mode)
		var portable_source: Dictionary=doc.data.duplicate(true)
		for item in portable_source["objects"]:
			if item["uid"]=="market": item["market"]["goods_style"]="hanx"
		var package: Dictionary=exporter.save(world,portable_source,studio.library,output+"/market_"+mode+".zip")
		check(package["ok"],"Portable ZIP includes required temporary vendor art: "+mode+" "+str(package))
	var damaged: Dictionary=doc.data.duplicate(true)
	for item in damaged["objects"]:
		if item["uid"]=="market": item["market"]["vendors"][0]["stock"]=-4
	var restored: Dictionary=repair.world(damaged,mode,"test/market",0)
	var repaired: Array=restored["objects"].filter(func(item: Dictionary)->bool:return item["uid"]=="market")
	check(Doc.valid(restored,mode,studio.library) and repaired.size()==1 and not repaired[0].has("market") and repair.issues.any(func(issue: Dictionary)->bool:return issue["path"].ends_with("/market")),"Damaged stock is archived and the permanent market host is retained: "+mode)
	doc.data["economy"]["starting_cash"]=20000
	doc.data["economy_account"]=Plan.Economy.fresh_account(doc.data,studio.library)
	studio.changed()
	await settle()
	var before_copy: Dictionary=doc.data.duplicate(true)
	select("market","markets")
	studio._command("duplicate",null)
	await settle()
	var copied: Dictionary=doc.object(studio.selected_uid)
	check(copied.get("uid")==studio.selected_uid and studio.selected_uid!="market" and copied.get("market",{}).get("enabled")==false and copied.get("market",{}).get("vendors")==doc.object("market")["market"]["vendors"],"A copied host retains vendor settings and starts disabled: "+mode+" "+studio.status.text)
	studio._command("undo",null)
	await settle()
	check(doc.data==before_copy,"Undo restores the exact authored host and ordinary placement budget: "+mode)

func shoppers(mode: String) -> void:
	var data: Dictionary=await fixture(mode,true)
	var manager: Node=data["manager"]
	var citizens: Node=data["citizens"]
	var market=manager.market
	var fruit: String=Plan.market_id("market",0)
	check(citizens.residents.size()==4 and market.vendors.has(fruit),"The live market starts with four real resident bodies: "+mode)
	if not market.vendors.has(fruit): return
	var actors: Array=citizens.residents.map(func(resident: Dictionary)->int:return resident["actor"].get_instance_id() if is_instance_valid(resident["actor"]) else 0)
	var queued: bool=false
	var at_checkout: bool=false
	var bounded: bool=true
	for tick in 3000:
		citizens.step(1.0/60)
		manager.step(1.0/60,true)
		bounded=bounded and market.people("market")<=3 and market.vendors[fruit]["queue_ids"].size()<=2
		for resident in citizens.residents:
			var actor: Node=resident["actor"]
			var target: String=resident["target"]
			if not is_instance_valid(actor) or not actor.visible or not market.targets.has(target): continue
			if manager.actor_metric(actor).distance_to(market.targets[target]["metric"])>.8: continue
			queued=queued or "/queue/" in target
			at_checkout=at_checkout or (target.ends_with("/checkout") and manager.service.result(resident["id"]).get("state")=="active")
		if market.revenue>=10 and queued and at_checkout: break
		await physics_frame
	check(queued and at_checkout and bounded and market.revenue==10 and market.receipts.size()==2,"Residents physically queue and use the shared checkout without exceeding capacity: "+mode+" "+str([queued,at_checkout,market.revenue,market.assignments,citizens.summary()]))
	var world: Node=data["world"]
	studio.set_walking(true)
	var door: Variant=world.exploration.entrance(world.instances["home"])
	world.player.teleport_to(world.player.get_parent().to_local(world.to_global(door)))
	studio.control_settings.execute("interact")
	await settle()
	var previous: Dictionary=market.assignments.duplicate(true)
	var earned: int=market.revenue
	clock(manager,15,2.5)
	check(world.exploration.interior!=null and market.active.has("market") and market.assignments==previous and market.revenue==earned and not manager.market_view.root.is_visible_in_tree(),"An interior visit suspends exterior stalls, queue work and settlement: "+mode)
	if world.exploration.interior:
		var doc: RefCounted=data["doc"]
		var room: Dictionary=doc.object("home")["interior"].duplicate(true)
		room["objects"].append(doc.object("market").duplicate(true))
		var repair:=Repair.new(studio.library)
		var cleaned: Dictionary=repair.world(room,mode,"test/market-room",1)
		check(not Doc.valid(room,mode,studio.library) and Doc.valid(cleaned,mode,studio.library) and not cleaned["objects"].back().has("market"),"Room repair strips the unsupported event and keeps the placed host: "+mode)
	if world.exploration.interior: world.exploration.leave_interior()
	clock(manager,15,2.5)
	for tick in 150:
		citizens.step(1.0/60)
		await physics_frame
	check(market.assignments.is_empty() and market.targets.is_empty() and citizens.residents.map(func(resident: Dictionary)->int:return resident["actor"].get_instance_id() if is_instance_valid(resident["actor"]) else 0)==actors and citizens.residents.all(func(resident: Dictionary)->bool:return not resident["target"].begins_with("market/")),"Closing clears crowded lanes and the original residents return to ordinary routing: "+mode)
	studio.set_walking(false)

func run() -> void:
	if OS.has_environment("ISOCITY_MARKET_OUTPUT"): output=OS.get_environment("ISOCITY_MARKET_OUTPUT")
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
		await shoppers(mode)
	studio.free()
	await settle()
	print("MARKET DAYS: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
