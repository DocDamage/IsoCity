extends SceneTree

const Connector=preload("res://scripts/builder/connector_plan.gd")
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
	var source: Dictionary=city.studio_data.duplicate(true)
	check(source["connections"].size()==1 and Connector.retained(source,source["connections"])==source["connections"],
		"Portable city preserves the calibrated structure joint and exact endpoint identities.")
	var water: Node=city.get_node_or_null("WaterNetwork")
	var power: Node=city.get_node_or_null("PowerNetwork")
	check(is_instance_valid(water) and is_instance_valid(power) and water.served("home")==5 and power.served("home")==6,
		"Both utilities resolve the same building's independent ports in the portable scene.")
	if water and power:
		check(water.graph["links"].size()==2 and power.graph["links"].size()==6,"Water and power keep their own authored edges.")
		for tick in 8:
			water.step(.25)
			power.step(.25)
		check(water.stored()==5 and power.stored()==8 and city.studio_data==source,"Runtime service leaves the exact source connections intact.")
	check(city.find_children("*","Control",true,false).all(func(control: Control)->bool:
		return not "socket_markers" in control),"The portable main scene excludes the editor preview markers.")
	city.free()
	await process_frame
	print("PORTABLE CONNECTIONS: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
