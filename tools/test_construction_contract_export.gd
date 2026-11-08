extends SceneTree

const Plan=preload("res://scripts/builder/construction_plan.gd")
var checks: int=0
var failures: int=0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool,description: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		print("FAIL: "+description)

func press(city: Node,code: Key) -> void:
	var key:=InputEventKey.new()
	key.keycode=code
	key.pressed=true
	city._unhandled_input(key)

func walk_to(city: Node,point: Vector2,height: float=.05) -> void:
	var local: Variant=Plan.Deliveries.Drive.world(point,city.dimension,height)
	city.player.teleport_to(city.player.get_parent().to_local(city.to_global(local)))

func run() -> void:
	var city: Node=load("res://city.tscn").instantiate()
	root.add_child(city)
	var driver: Node=city.exploration.driving
	driver.set_physics_process(false)
	city.economy.set_process(false)
	city.player.set_physics_process(false)
	for frame in 8: await physics_frame
	var source: Dictionary=city.studio_data.duplicate(true)
	var contract: Node=driver.construction
	check(is_instance_valid(contract) and contract.site_plan.get("ok",false) and contract.materials==0 and contract.receipts.is_empty(),
		"Fresh import has an available contract with its prepared assets and clean private state.")
	if not is_instance_valid(contract) or not contract.site_plan.get("ok",false): quit(1); return
	var delivery=driver.delivery
	var pickup: Vector2=delivery.sites["supply"]["point"]
	var drop: Vector2=delivery.sites["site"]["point"]
	walk_to(city,pickup+Vector2(0,1.55))
	press(city,KEY_E)
	press(city,KEY_H)
	check(not driver.active.is_empty() and not delivery.job.is_empty(),"The actual exported van accepts the offer through the ordinary shortcuts.")
	for frame in 32: driver.step_deliveries(.15)
	check(delivery.job.get("phase")=="carrying" and delivery.job.get("loaded")==4,"The four masonry units physically load into the van.")
	for frame in 1200:
		if driver.active.is_empty(): break
		if driver.active["point"].distance_to(drop)<maxf(.8,driver.speed*driver.speed/30+.15): break
		driver.step(1.0/60,Vector2.DOWN)
	for frame in 70: driver.step(1.0/60,Vector2.ZERO,true)
	press(city,KEY_H)
	for frame in 32: driver.step_deliveries(.15)
	check(contract.materials==4 and contract.reward_total==0 and delivery.reward_total==0,"Driving to the site and unloading unlocks the physical tasks and pays nothing.")
	press(city,KEY_E)
	for phase in 3:
		var task: Dictionary=contract.next_task()
		if task.is_empty(): check(false,"The expected work point is missing."); break
		walk_to(city,task["approach"],task["height"]+.05)
		await physics_frame
		press(city,KEY_E)
		check(is_instance_valid(contract.models) and contract.models.has_node(task["id"]) and contract.reward_total==(150 if phase==2 else 0),
			"The ordinary interaction installs each supplied model and only the foundation pays.")
	city.scenario.step()
	check(city.scenario.progress["complete"] and contract.receipts.size()==1 and city.studio_data==source and city.live_data==source,
		"The actual scenario and one receipt complete while preserving authored city and treasury.")
	press(city,KEY_TAB)
	check(not is_instance_valid(contract.models) and contract.receipts.is_empty() and contract.reward_total==0 and city.studio_data==source,
		"Leaving Walk clears all private activity state together.")
	city.free()
	await process_frame
	print("PORTABLE CONSTRUCTION CONTRACT: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
