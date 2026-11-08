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
	var water: Node=city.get_node_or_null("WaterNetwork")
	check(water!=null and water.panel.visible and water.pause_button.text=="Pause water","The portable main scene creates the water runtime and its HUD.")
	if not water: quit(1); return
	water.set_process(false)
	var source: Dictionary=city.studio_data.duplicate(true)
	check(city.exploration.interior==null and water.served("home")==5 and water.stored()==0,"The unloaded household has service with empty initial storage.")
	for tick in 8: water.step(.25)
	var b: Dictionary=water.report["balance"]
	check(water.tick_count==1 and water.stored()==1 and b=={"opening":0,"production":10,"delivered":9,"closing":1,"spill":0},
		"Portable runtime computes the same conserved delivery and stock.")
	water.pause_button.pressed.emit()
	for tick in 8: water.step(.25)
	check(water.tick_count==1 and water.pause_button.text=="Resume water","The exported HUD pauses water locally.")
	water.pause_button.pressed.emit()
	var interrupted: Dictionary=source.duplicate(true)
	interrupted["utility_edges"]=interrupted["utility_edges"].filter(func(run: Dictionary)->bool:return run["to"]["object_uid"]!="home")
	water.configure(interrupted,city.exploration.library)
	check(water.served("home")==0 and water.describe("home").contains("Outage") and water.caption.text.contains("1 short"),
		"Portable runtime reports an outage after losing the service connection.")
	water.configure(source,city.exploration.library)
	check(water.served("home")==5 and water.caption.text.contains("0 short"),"Portable runtime reports recovery when the same connection returns.")
	check(source==city.studio_data and not source.has("stock"),"Water ticks leave the authored exported city intact.")
	city.free()
	await process_frame
	print("PORTABLE WATER NETWORK: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
