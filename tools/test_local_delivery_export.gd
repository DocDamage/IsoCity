extends SceneTree

const Drive=preload("res://scripts/builder/driving_plan.gd")
var checks: int=0
var failures: int=0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool,description: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		print("FAIL: "+description)

func handle_cargo(city: Node) -> void:
	var key:=InputEventKey.new()
	key.keycode=KEY_H
	key.pressed=true
	city._unhandled_input(key)

func run() -> void:
	var city: Node=load("res://city.tscn").instantiate()
	root.add_child(city)
	var driver: Node=city.exploration.driving
	driver.set_physics_process(false)
	city.economy.set_physics_process(false)
	city.player.set_physics_process(false)
	driver.business_clock.set_physics_process(false)
	driver.business_clock.hour=12
	for frame in 8: await physics_frame
	var source: Dictionary=city.studio_data.duplicate(true)
	var runtime=driver.delivery
	check(runtime.sites.size()==2 and runtime.vehicles.size()==2 and runtime.receipts.is_empty() and runtime.stock.is_empty(),"A fresh package has both reviewed shops and vans with clean preview state.")
	var pickup: Vector2=runtime.sites["pickup"]["point"]
	var drop: Vector2=runtime.sites["drop"]["point"]
	var point: Variant=city.to_global(Drive.world(pickup+Vector2(1.4,0),city.dimension,.05))
	city.player.teleport_to(city.player.get_parent().to_local(point))
	var entered: bool=driver.interact(driver.nearby("van"))
	handle_cargo(city)
	check(entered and not runtime.job.is_empty(),"The actual exported van enters and accepts the nearby contract using the normal shortcut.")
	for frame in 12: driver.step_deliveries(.15)
	var offered: String=runtime.job.get("id","")
	check(runtime.job.get("phase")=="carrying" and runtime.job.get("loaded")==3 and runtime.inventory("pickup").get("parcels")==5,"Three units physically load into the van.")
	for frame in 800:
		if driver.active.is_empty(): break
		var distance: float=driver.active["point"].distance_to(drop)
		if distance<=maxf(.8,driver.speed*driver.speed/30.0+.15): break
		driver.step(1.0/60,Vector2.DOWN)
		driver.step_deliveries(1.0/60)
	for frame in 70: driver.step(1.0/60,Vector2.ZERO,true)
	handle_cargo(city)
	check(runtime.job.get("phase")=="unloading","The van reaches the other store through real driving and starts unloading. "+str(runtime.message))
	for frame in 12: driver.step_deliveries(.15)
	check(runtime.receipts.get(offered,{}).get("quantity")==3 and runtime.reward_total==45 and runtime.inventory("drop").get("parcels")==3,"Only the completed delivery settles the cargo and preview reward.")
	check(city.studio_data==source and runtime.job.is_empty(),"Independent delivery preserves the authored source and treasury.")
	city.free()
	await process_frame
	print("PORTABLE LOCAL DELIVERIES: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
