extends Node

const Plan=preload("res://scripts/builder/construction_plan.gd")
const Instance=preload("res://scripts/builder/asset_instance.gd")
const MAX_ATTEMPTS: int=128
var driver: Node
var source: Dictionary={}
var site_plan: Dictionary={}
var attempt: String=""
var completed_tasks: int=0
var materials: int=0
var hauled: int=0
var terminal: Dictionary={}
var receipts: Dictionary={}
var reward_total: int=0
var message: String=""
var models: Node

func configure(data: Dictionary) -> Dictionary:
	var next: Dictionary=Plan.inspect(data,driver.exploration.library)
	var next_attempt: String=data.get("scenario",{}).get("attempt","") if Plan.enabled(data) else ""
	if not attempt.is_empty() and (attempt!=next_attempt or site_plan!=next) and site_plan.get("ok",false):
		if receipts.has(attempt):
			clear_models()
			completed_tasks=0
		elif driver.exploration.enabled:
			var pickup: Dictionary=Plan.records(data,site_plan["config"]).get("pickup",{})
			var restored: Dictionary=Plan.Deliveries.settings(pickup,"delivery_site")
			var original: Dictionary=site_plan["stations"]["pickup"]["config"]
			var same_stock: bool=pickup.get("asset")==Plan.recipe()["supply"] and Plan.Deliveries.enabled(pickup,"delivery_site") and restored["stock"]==original["stock"] and restored["capacity"]==original["capacity"]
			cancel("The supply, work area or contract changed.",same_stock)
	if attempt!=next_attempt:
		clear_models()
		completed_tasks=0
		materials=0
		hauled=0
		message=""
	attempt=next_attempt
	site_plan=next
	source=data
	return next if next.get("ok",false) and terminal.size()<MAX_ATTEMPTS else {}

func receive(receipt: Dictionary) -> void:
	if attempt.is_empty() or receipt.get("construction_attempt","")!=attempt or not site_plan.get("ok",false) or terminal.has(attempt) or hauled>0: return
	var delivery=driver.delivery
	var offer: Dictionary=site_plan["offer"]
	var pickup: String=site_plan["config"]["pickup_uid"]
	if delivery.receipts.get(receipt.get("id",""))!=receipt or receipt.get("pickup")!=pickup or receipt.get("destination")!=offer["destination"] or receipt.get("goods")!=offer["goods"] or receipt.get("quantity")!=offer["quantity"]: return
	var inventory: Dictionary=delivery.inventory(offer["destination"])
	if inventory.get(offer["goods"],0)<offer["quantity"]: return
	inventory[offer["goods"]]-=offer["quantity"]
	materials=offer["quantity"]
	hauled=materials
	message="Masonry delivered. Leave the vehicle and follow the work markers."
	delivery.message=message

func haul_cancelled(id: String,reason: String) -> void:
	if id!=attempt or terminal.has(id): return
	terminal[id]=true
	message=reason

func cancel(reason: String="Construction cancelled.",restore: bool=true) -> bool:
	if attempt.is_empty() or terminal.has(attempt) or terminal.size()>=MAX_ATTEMPTS: return false
	terminal[attempt]=true
	var delivery=driver.delivery
	if delivery.job.get("construction_attempt","")==attempt:
		delivery.cancel(reason,restore)
		delivery.release_gate(driver.traffic)
		reason=delivery.message
	elif materials>0:
		var pickup: String=site_plan["config"]["pickup_uid"]
		var goods: String=site_plan["offer"]["goods"]
		if restore and delivery.sites.has(pickup) and delivery.available(pickup)>=materials:
			var stock: Dictionary=delivery.inventory(pickup)
			stock[goods]=int(stock.get(goods,0))+materials
			reason+=" Materials returned to the supply stock."
		else: reason+=" Reserved materials cleared."
	materials=0
	completed_tasks=0
	clear_models()
	message=reason
	delivery.completed_hauls[attempt]=true
	delivery.message=reason
	return true

func next_task() -> Dictionary:
	if materials<=0 or terminal.has(attempt) or not site_plan.get("ok",false): return {}
	return site_plan["tasks"][completed_tasks]

func outdoors() -> bool:
	return driver.care_visible() and not driver.exploration.entering

func nearby_task() -> Dictionary:
	if not outdoors() or not driver.active.is_empty() or not driver.exploration.props.active.is_empty(): return {}
	var task: Dictionary=next_task()
	if task.is_empty(): return {}
	var walk: Node=driver.exploration
	var pos: Variant=walk.get_parent().to_local(walk.player.global_position)
	var mode: String=walk.dimension
	var point: Vector2=Plan.Zone.Traffic.metric([pos.x,pos.y,0] if mode=="2d" else [pos.x,pos.y,pos.z],mode)
	var height: float=walk.player.get_meta("terrain_height",0.0) if mode=="2d" else pos.y
	return task if point.distance_to(task["approach"])<=Plan.REACH and absf(height-task["height"])<=.75 and not task["bounds"].grow(.45).has_point(point) else {}

func work() -> bool:
	var task: Dictionary=nearby_task()
	if task.is_empty(): return false
	var current: Dictionary=Plan.inspect(source,driver.exploration.library)
	if current!=site_plan:
		cancel("The construction area changed or became unavailable.")
		return false
	var area: Rect2=task["bounds"].grow(.45)
	var traffic: Node=driver.traffic
	if is_instance_valid(traffic):
		var points: Array[Vector2]=traffic.pedestrian_points(driver.exploration.get_parent())
		points.append_array(Plan.Zone.vehicle_points(traffic.vehicles))
		if is_instance_valid(traffic.transit): points.append_array(Plan.Zone.vehicle_points(traffic.transit.vehicle_states()))
		if is_instance_valid(traffic.services):
			points.append_array(Plan.Zone.vehicle_points(traffic.services.crews.values().map(func(crew: Dictionary):return crew["vehicle"])))
		if points.any(func(point: Vector2)->bool:return area.has_point(point)):
			message="Wait for people and vehicles to clear the work area."
			return false
	for vehicle in driver.parked.values():
		var extent: Vector2=Plan.Deliveries.Drive.dimensions(vehicle["item"],driver.exploration.library,driver.exploration.dimension)
		if area.grow(extent.length()).has_point(vehicle["point"]):
			message="Move the parked vehicle out of the work area."
			return false
	if not place(task):
		message="The required equipment could not be placed."
		return false
	completed_tasks+=1
	if completed_tasks<site_plan["tasks"].size():
		message="Walk to the next marker."
		return true
	materials=0
	terminal[attempt]=true
	var reward: int=site_plan["reward"]
	receipts[attempt]={"id":attempt,"reward":reward,"site":site_plan["config"]["host_uid"],"masonry":hauled}
	reward_total+=reward
	message="Foundation complete · %d preview credits earned."%reward
	return true

func place(task: Dictionary) -> bool:
	var walk: Node=driver.exploration
	var placement: Dictionary=task["placement"]
	if not Plan.Zone.Candidates.source_ready(walk.library.assets[placement["asset"]]["path"],true): return false
	var model: Node=Instance.make(walk.library,placement["asset"],walk.dimension)
	var position: Array=placement["position"]
	var scale_value: float=placement["scale"]
	Instance.pose(model,placement,source.get("night",false))
	if model is Node2D:
		model.position=Vector2(position[0],position[1])
		model.scale=Vector2.ONE*scale_value
	else:
		model.position=Vector3(position[0],position[1],position[2])
		model.scale=Vector3.ONE*scale_value
	if not is_instance_valid(models):
		models=Node2D.new() if walk.dimension=="2d" else Node3D.new()
		models.name="ContractEquipment"
		if models is Node2D: models.y_sort_enabled=true
		walk.get_parent().add_child(models)
	model.name=task["id"]
	models.add_child(model)
	if model is Node2D: model.terrain_visual_offset=Vector2(0,-position[2]*8/scale_value)
	return true

func clear_models() -> void:
	if is_instance_valid(models): models.free()
	models=null

func reset() -> void:
	clear_models()
	completed_tasks=0
	materials=0
	hauled=0
	terminal.clear()
	receipts.clear()
	reward_total=0
	message=""
