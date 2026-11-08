extends SceneTree

var checks: int=0
var failures: int=0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		print("FAIL: "+message)

func run() -> void:
	var city: Node=load("res://city.tscn").instantiate()
	root.add_child(city)
	var power: Node=city.get_node_or_null("PowerNetwork")
	check(power!=null and power.panel.visible and city.exploration.power==power,"Portable main scene creates the power runtime, HUD and device supply provider.")
	if not power: quit(1); return
	power.set_process(false)
	var source: Dictionary=city.studio_data.duplicate(true)
	check(power.served("home")==6 and power.graph["nodes"]["home"]["fixtures"]==3 and city.exploration.interior==null,
		"Unloaded fixtures on two floors are included in the portable allocation.")
	for tick in 8: power.step(.25)
	check(power.stored()==8 and power.report["balance"]=={"opening":0,"production":32,"delivered":19,"closing":8,"spill":5},
		"Independent battery runtime respects its charge rate and balance.")
	check(city.businesses.service.request("shop","visitor","coffee",12)["ok"],"Powered portable business starts its ordinary activity.")
	var outage: Dictionary=source.duplicate(true)
	outage["utility_edges"].pop_front()
	power.reset_preview()
	power.configure(outage,city.exploration.library)
	city.businesses.service.step(.25,12)
	check(city.businesses.service.result("visitor").get("state")=="cancelled" and power.caption.text.contains("4 short"),
		"Loss of cable interrupts business service and the HUD reports the four affected loads.")
	check(not city.exploration.driving.charger_power_reason("charger").is_empty(),"The exported charger uses the same supply decision.")
	power.configure(source,city.exploration.library)
	check(city.exploration.driving.charger_power_reason("charger").is_empty() and city.businesses.service.request("shop","second","coffee",12)["ok"],
		"Restoring the cable restores both charge and business service.")
	check(source==city.studio_data and not source.has("stock"),"Private power ticks leave city source unchanged.")
	city.free()
	await process_frame
	print("PORTABLE POWER NETWORK: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
