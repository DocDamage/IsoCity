extends "res://tools/test_local_deliveries.gd"

const Markets=preload("res://scripts/builder/market_plan.gd")

func workflow(mode: String) -> void:
	var data: Dictionary=await fixture(mode)
	var doc: RefCounted=data["doc"]
	var driver: Node=data["driver"]
	var manager: Node=driver.business_clock
	var runtime=manager.market
	doc.object("pickup")["delivery_site"]["stock"]={"produce":8}
	doc.object("pickup")["delivery_contract"]["goods"]="produce"
	doc.object("drop")["market"]={"enabled":true,"offset_z":16.0,"stock_policy":"delivery","goods_style":"hanx",
		"vendors":[{"kind":"fruit","stock":2,"price":5}]}
	studio.changed()
	await settle()
	manager.hour=12
	manager.step(.016,false)
	var vendor: String=Markets.market_id("drop",0)
	check(runtime.vendors.has(vendor) and runtime.count(vendor)==0,"A delivery-supplied stall opens empty: "+mode+" "+str(runtime.notices))
	if not runtime.vendors.has(vendor): return
	await enter_car("van")
	studio.control_settings.execute("delivery_cargo")
	tick(driver,16)
	check(driver.delivery.job.get("loaded")==3 and drive_to(driver,data["finish"]),"The original van carries three actual units to the market's receiving site: "+mode)
	var ticket: String=driver.delivery.job.get("id","")
	studio.control_settings.execute("delivery_cargo")
	tick(driver,16)
	var receipt: Dictionary=driver.delivery.receipts.get(ticket,{})
	check(receipt.get("quantity")==3 and runtime.count(vendor)==2 and driver.delivery.inventory("drop").get("produce")==2,"The market takes two units and the delivery site retains the overflow plus its original stock: "+mode)
	if receipt.is_empty(): return
	manager.receive_market_delivery(receipt)
	check(runtime.count(vendor)==2 and runtime.supply_receipts.get(ticket)==2 and runtime.revenue==0,"Replaying a delivery receipt adds neither stock nor sales revenue: "+mode)
	driver.exit_vehicle(true)
	var world: Node=data["world"]
	var point: Vector2=runtime.vendors[vendor]["point"]
	world.player.teleport_to(world.player.get_parent().to_local(world.to_global(Plan.Drive.world(point,mode,.03))))
	await settle()
	studio.control_settings.execute("business")
	for tick_index in 12: manager.step(.2,false)
	check(runtime.count(vendor)==1 and runtime.revenue==5 and doc.data["economy_account"]["cash"]==900,"A real shopper can buy delivered produce without altering the authored treasury: "+mode+" "+manager.message)
	manager.preview_day+=1
	manager.step(.016,false)
	check(runtime.count(vendor)==1 and runtime.supply_receipts.size()==1,"Tomorrow retains delivered stock without daily replenishment: "+mode)
	studio.set_walking(false)
