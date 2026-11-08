extends "res://tools/test_local_deliveries.gd"

const Care=preload("res://scripts/builder/vehicle_service_plan.gd")
const Markets=preload("res://scripts/builder/market_plan.gd")
var diagnostics: RefCounted

func record(code: String,uid: String="") -> Dictionary:
	for row in diagnostics.snapshot.get("rows",[]):
		if row["code"]==code and (uid.is_empty() or row["object_uid"]==uid): return row
	return {}

func geometry(row: Dictionary,kind: String) -> Array:
	return row.get("details",{}).get("geometry",[]).filter(func(shape: Dictionary)->bool:return shape["kind"]==kind)

func jobs(mode: String) -> void:
	var data: Dictionary=await fixture(mode)
	var doc: RefCounted=data["doc"]
	var driver: Node=data["driver"]
	var world: Node=data["world"]
	var business: Node=driver.business_clock
	var source: Dictionary=doc.object("drop")
	source["business"]["capacity"]=1
	source["market"]={"enabled":true,"offset_z":16.0,"goods_style":"hanx","vendors":[{"kind":"fruit","stock":8,"price":5}]}
	var pump: Dictionary=doc.add("3d:HanX_GasStation/Fuel_Pump",Plan.Traffic.world(Vector2(40,14),mode),"0",.75)
	pump["uid"]="pump"
	pump["vehicle_bay"]={"enabled":true,"queue":3,"length":8,"width":4,"approach":10}
	doc.object("van")["vehicle_care"]={"enabled":true,"initial":40}
	doc.object("small_van")["vehicle_care"]={"enabled":true,"initial":40}
	studio.changed()
	await settle()
	business.hour=12
	business.step(.016,false)
	var vendor: String=Markets.market_id("drop",0)
	var market=business.market
	if market.vendors.has(vendor):
		var at: Vector2=market.vendors[vendor]["point"]
		market.assign("first",at,business.service)
		market.assign("second",at,business.service)
	diagnostics.choose("markets")
	diagnostics.tick(.3)
	var squares: Array=geometry(record("market_queue","drop"),"queue")
	check(squares.size()==1 and squares[0]["label"]=="1" and market.vendors[vendor]["queue_ids"]==["second"],"The market overlay counts an actual assigned queue slot: "+mode)
	world.player.teleport_to(world.exploration.entrance(world.instances["drop"]))
	business.resident_arrival("drop","first-visitor",world.player)
	business.resident_arrival("drop","second-visitor",world.player)
	diagnostics.choose("businesses")
	diagnostics.tick(.3)
	squares=geometry(record("business_queue","drop"),"queue")
	check(squares.size()==1 and squares[0]["label"]=="1" and business.service.queues["drop"]==["second-visitor"],"The business overlay uses the real capacity queue at the entrance: "+mode)
	var care=driver.care
	var bay: Dictionary=care.bays.get("pump",{})
	if not bay.is_empty():
		var pose: Dictionary={"point":bay["center"],"heading":bay["axis"],"extent":Vector2(.55,1.5),"speed":0.0}
		care.request("van","pump",pose)
		pose["point"]-=bay["axis"]*(bay["length"]*.5+2)
		care.request("small_van","pump",pose)
	diagnostics.choose("vehicle_care")
	diagnostics.tick(.3)
	var row: Dictionary=record("vehicle_bay","pump")
	squares=geometry(row,"queue")
	check(squares.size()==1 and squares[0]["label"]=="1" and row["related_uids"]==["small_van"],"The vehicle care overlay counts waiting vehicles and keeps the active service separate: "+mode+" "+str([care.queues,care.feedback]))
	care.reset()
	await enter_car("van")
	diagnostics.choose("deliveries")
	check(driver.request_delivery(),"The actual cargo control creates a live route request: "+mode)
	diagnostics.tick(.3)
	var pending: Dictionary=record("delivery_route","pickup")
	check(pending.get("severity")=="pending" and geometry(pending,"lane").is_empty(),"The loading overlay shows a pending marker before the cargo route is verified: "+mode)
	tick(driver,16)
	diagnostics.tick(.3)
	var active: Dictionary=record("delivery_route","drop")
	check(driver.delivery.job.get("phase")=="carrying" and not geometry(active,"lane").is_empty() and active["related_uids"]==["pickup","drop"],"Only the real accepted cargo route contributes lane geometry in Walk: "+mode)
	studio.set_walking(false)
	diagnostics.choose("off")
	await settle()

func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled=false
	root.add_child(studio)
	await settle()
	if studio.consumer_shell: studio.consumer_shell.dismiss_welcome()
	diagnostics=studio.simulation_diagnostic_tools
	for mode in ["2d","3d"]: await jobs(mode)
	studio.free()
	await settle()
	print("SIMULATION DIAGNOSTIC JOBS: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
