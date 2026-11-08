extends SceneTree
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var scene: Node=load("res://city.tscn").instantiate(); root.add_child(scene)
	for i in 6: await process_frame
	await physics_frame
	var runtime: Node=scene.economy; runtime.set_process(false)
	var plan=load("res://scripts/builder/economy_plan.gd")
	check(runtime.panel.visible and plan.valid_account(runtime.data["economy_account"]),"Relocated playable project discovers the treasury and its purchase book")
	var value: Dictionary=runtime.data["economy_account"]; var cash: int=value["cash"]; var period: int=value["period"]
	var rates: Dictionary=plan.forecast(runtime.data,scene.exploration.library)
	check(rates["income"]>0 and rates["upkeep"]>0 and runtime.rates==rates,"Portable catalog metadata preserves actual operating income and costs")
	runtime.elapsed=0
	for i in int(runtime.data["economy"]["period_seconds"])*4: runtime.step(.25)
	check(runtime.data["economy_account"]["period"]==period+1 and runtime.data["economy_account"]["cash"]==cash+rates["net"],"Portable accounting settles a complete period exactly once")
	check(scene.studio_data["economy_account"]["cash"]==cash and runtime.data["economy_account"]["construction_total"]==value["construction_total"],"Portable play preserves its authored source and construction totals")
	runtime.pause_button.pressed.emit(); var frozen: float=runtime.elapsed
	for i in 80: runtime.step(.25)
	check(runtime.paused and runtime.elapsed==frozen and runtime.data["economy_account"]["period"]==period+1,"Portable accounting controls pause the clock and treasury")
	runtime.pause_button.pressed.emit(); runtime.active=false; runtime.step(.25)
	check(not runtime.paused and runtime.elapsed==frozen,"Inactive accounting cannot advance")
	scene.queue_free(); await process_frame
	print("ECONOMY EXPORT: %d checks, %d failures" % [checks,failures]); quit(0 if failures==0 else 1)
