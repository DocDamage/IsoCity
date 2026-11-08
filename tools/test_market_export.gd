extends SceneTree

const Plan=preload("res://scripts/builder/market_plan.gd")
var checks: int=0
var failures: int=0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool,description: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		print("FAIL: "+description)

func run() -> void:
	var city: Node=load("res://city.tscn").instantiate()
	root.add_child(city)
	var manager: Node=city.businesses
	manager.set_physics_process(false)
	city.economy.set_physics_process(false)
	city.player.set_physics_process(false)
	for frame in 8: await physics_frame
	var source: Dictionary=city.studio_data.duplicate(true)
	var market=manager.market
	var fruit: String=Plan.market_id("market",0)
	check(market.sites.has("market") and market.active.is_empty() and market.receipts.is_empty(),"The independent project starts with its authored event closed and private state clean.")
	manager.hour=12
	manager.step(.016,false)
	check(market.active.has("market") and market.vendors.size()==2 and manager.market_view.displays[fruit]["product"]=="3d:HanX_Shop/Crate_Apples","Opening uses the independently imported HanX stalls and licensed goods.")
	if not market.vendors.has(fruit): quit(1); return
	var point: Vector2=market.vendors[fruit]["point"]
	var coordinates: Array=Plan.Traffic.world(point,city.dimension,.03)
	var local: Variant=Vector2(coordinates[0],coordinates[1]) if city.dimension=="2d" else Vector3(coordinates[0],coordinates[1],coordinates[2])
	city.player.teleport_to(city.player.get_parent().to_local(city.to_global(local)))
	var event:=InputEventKey.new()
	event.keycode=KEY_G
	event.pressed=true
	city._unhandled_input(event)
	for tick in 12: manager.step(.2,false)
	check(market.count(fruit)==1 and market.revenue==5 and manager.service.inventory.get("player",{}).get("Market fruit")==1,"The ordinary exported shortcut buys an item from the actual stall.")
	manager.hour=15
	manager.step(.016,false)
	check(market.active.is_empty() and manager.market_view.displays.is_empty() and city.city_instances.has("permanent"),"Closing clears temporary stalls and leaves the original art.")
	check(city.studio_data==source and market.receipts.size()==1,"The export keeps the city and treasury exact while retaining its private receipt.")
	city.free()
	await process_frame
	print("PORTABLE MARKET DAYS: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
