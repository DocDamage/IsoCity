extends SceneTree
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func finish(manager: Node) -> void:
	for i in 200:
		if manager.queue.is_empty(): break
		manager.step()
func run() -> void:
	var scene: Node=load("res://city.tscn").instantiate(); root.add_child(scene)
	for i in 6: await process_frame
	await physics_frame
	var manager: Node=scene.scenario; manager.set_process(false); finish(manager)
	var plan=load("res://scripts/builder/scenario_plan.gd"); var data: Dictionary=scene.studio_data.duplicate(true)
	check(plan.valid(data["scenario"]) and not data["scenario"].has("complete"),"Portable challenges save attempt metadata rather than trusting a completed flag")
	check(manager.progress["complete"] and manager.panel.visible,"Fresh portable scenes recompute and display actual challenge completion")
	if data["scenario"]["id"]=="walkable":
		check(manager.checked>=6 and manager.connections.size()==2 and not manager.obstacles.is_empty(),"Portable neighborhoods check their actual walking links against authored collision geometry")
		data["objects"][0]["visible"]=false
	else:
		check(data["economy_account"]["construction_total"]==400 and data["economy_account"]["cash"]==200 and data["economy_account"]["scenario_attempt"]==data["scenario"]["attempt"],"Portable apartment attempts retain their real purchases and construction allowance")
		data["economy_account"]["scenario_attempt"]="reset_treasury"
	manager.configure(data,scene.exploration.library,scene.exploration.instances,false); finish(manager)
	check(not manager.progress["complete"],"Portable goal evaluation rejects missing requirements or replaced budget proof")
	manager.configure(scene.studio_data,scene.exploration.library,scene.exploration.instances,false); finish(manager)
	check(manager.progress["complete"],"Restoring the valid authored city restores portable challenge completion")
	check(scene.studio_data["scenario"]!=data["scenario"] or scene.studio_data["objects"]!=data["objects"] or scene.studio_data.get("economy_account",{})!=data.get("economy_account",{}),"Portable checks preserve the original source document")
	scene.queue_free(); await process_frame
	print("SCENARIO EXPORT: %d checks, %d failures" % [checks,failures]); quit(0 if failures==0 else 1)
