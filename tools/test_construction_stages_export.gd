extends SceneTree

const Plan=preload("res://scripts/builder/zone_plan.gd")
const Stages=preload("res://scripts/builder/zone_stage_plan.gd")
const EXPECTED: Dictionary={
	Plan.Stage.FOUNDATION:["Foundation_Rebar","Rebar_Bundle","Gravel_Pile"],
	Plan.Stage.FRAMING:["Building_Frame","Scaffold_Module"],
	Plan.Stage.FINISHING:["Scaffold_Module_Ladder","Pallet_Bricks","Lumber_Stack"],
}
var checks: int=0
var failures: int=0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool,description: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		print("FAIL: "+description)

func phase(manager: Node,lot: Dictionary) -> Array[Node]:
	var marker: Node=manager.visuals[lot["uid"]]
	var scenery: Node=marker.get_node_or_null("ConstructionScenery")
	var props: Array[Node]=scenery.get_children() if scenery else []
	var stage: int=lot["stage"]
	check(props.map(func(prop: Node)->String:return str(prop.get_meta("stage_asset")).get_file())==EXPECTED[stage],
		"The relocated project uses all supplied "+Plan.stage_name(lot)+" props.")
	return props

func run() -> void:
	var city: Node=load("res://city.tscn").instantiate()
	root.add_child(city)
	var manager: Node=city.zoning
	manager.set_process(false)
	city.economy.set_process(false)
	city.player.set_physics_process(false)
	city.walking=false
	city._set_mode()
	for frame in 8: await physics_frame
	var source: Dictionary=city.studio_data.duplicate(true)
	var lots: Array=city.live_data["zones"]
	var lot: Dictionary=lots.front()
	var proposal: Dictionary=lot["proposal"].duplicate(true)
	var cost: int=Plan.Economy.profile(proposal["asset"],manager.library)["construction"]
	check(lots.size()==2 and lot["stage"]==Plan.Stage.FOUNDATION and lots[1]["stage"]==Plan.Stage.VACANT and Stages.required_assets(city.live_data,manager.library).size()==8,
		"The portable project opens at the saved foundation with all future art dependencies.")
	manager.pause_button.pressed.emit()
	var frozen: Dictionary=manager.timers.duplicate(true)
	var props: Array[Node]=phase(manager,lot)
	manager.step(.25)
	check(manager.paused and manager.timers==frozen and props.all(is_instance_valid),
		"The ordinary pause button freezes growth and leaves current art in place.")
	manager.pause_button.pressed.emit()
	var observed: Array[int]=[int(lot["stage"])]
	for tick in 400:
		manager.people=city.development_people()
		manager.step(.25)
		lot=city.live_data["zones"].front()
		var stage: int=lot["stage"]
		if observed.back()==stage: continue
		observed.append(stage)
		check(props.all(func(node: Variant)->bool:return not is_instance_valid(node)),
			"Changing stages frees the preceding temporary scene.")
		if stage==Plan.Stage.DEVELOPED: break
		props=phase(manager,lot)
		check(lot["proposal"]==proposal and city.live_data["economy_account"]["cash"]==25000 and city.live_data["objects"].is_empty(),
			"Intermediate stages keep the exact design without new objects or charges.")
	var finished_has_scenery: bool=manager.visuals[lot["uid"]].has_node("ConstructionScenery")
	check(observed==[1,2,4,3] and not finished_has_scenery,
		"Runtime growth follows all stages and cleans up. Observed %s, scenery present %s."%[str(observed),finished_has_scenery])
	check(city.live_data["objects"].size()==1 and city.city_instances.has(proposal["uid"]) and city.live_data["economy_account"]["cash"]==25000-cost and city.studio_data==source,
		"Completing the real building charges once and preserves the exported source city.")
	city.free()
	await process_frame
	print("PORTABLE CONSTRUCTION STAGES: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
