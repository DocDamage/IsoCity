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
	var manager: Node=scene.citizens
	check(manager!=null and manager.residents.size()==2,"Fresh portable project starts its configured residents")
	manager.set_physics_process(false)
	for activity in [[9,"work"],[12.5,"shop"],[17.5,"park"],[21.5,"home"]]:
		manager.hour=activity[0]
		var arrived: bool=false
		for i in 2000:
			manager.step(1.0/60)
			if manager.residents.all(func(r: Dictionary):return not r["target"].is_empty() and manager.plan["lookup"][r["target"]]["role"]==activity[1] and r["index"]>=r["path"].size() and r["status"].begins_with("At ")): arrived=true; break
		check(arrived,"Portable citizens physically complete their "+activity[1]+" routine")
	check(manager.residents.all(func(r: Dictionary):return r["visits"].size()>=4),"Portable residents retain the completed daily visits")
	scene.queue_free(); await process_frame
	print("CITIZEN EXPORT: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
