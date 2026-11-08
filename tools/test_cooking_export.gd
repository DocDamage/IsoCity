extends SceneTree

const Plan = preload("res://scripts/builder/cooking_plan.gd")
const Props = preload("res://scripts/builder/prop_plan.gd")
const Traffic = preload("res://scripts/builder/traffic_plan.gd")
const Utility = preload("res://scripts/builder/utility_profiles.gd")
const DISH = "dish/tomato_pan_bread"
var scene: Node
var checks: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: "+message)

func frames(count: int) -> void:
	for frame in count: await physics_frame

func arrive(role: String) -> bool:
	var exploration: Node = scene.exploration
	for candidate in exploration.cooking.station_list(Props.context(exploration)).values():
		if candidate["role"] != role: continue
		var node: Node = candidate["node"]
		var point: Vector2 = Utility.side_point(candidate["bounds"],"south",.65)
		var at: Array = Traffic.world(point,scene.dimension)
		var global_point: Variant = node.get_parent().to_global(Vector2(at[0],at[1])) if scene.dimension=="2d" \
			else node.get_parent().to_global(Vector3(at[0],node.position.y,at[2]))
		scene.player.teleport_to(scene.player.get_parent().to_local(global_point))
		await physics_frame
		exploration.interaction_prompt()
		return exploration.nearby.get("cooking","") == candidate["item"]["uid"]
	return false

func run() -> void:
	scene = load("res://city.tscn").instantiate()
	root.add_child(scene)
	await frames(8)
	var exploration: Node = scene.exploration
	var cook: Node = exploration.cooking
	var host: String = scene.studio_data["objects"][0]["uid"]
	var art: String = Plan.recipes()[Plan.DEFAULT_RECIPE]["serving_art"]
	check(Plan.enabled(scene.studio_data) and cook.kitchens.is_empty()
		and exploration.library.assets.has(art) and exploration.library.icon(art)!=null,
		"The isolated scene has authored settings and the future serving art with fresh preview stock.")
	scene.walking = true
	scene._set_mode()
	scene.player.set_physics_process(false)
	scene.player.teleport_to(exploration.entrance(scene.city_instances[host]))
	await frames(4)
	exploration.interact()
	await frames(7)
	check(exploration.interior_uid == host,"The standalone player enters the real café.")
	if exploration.interior_uid != host: quit(1); return
	scene.player.set_physics_process(false)
	check(await arrive("prep"),"The isolated prep approach is reachable.")
	exploration.interact()
	await frames(130)
	check(cook.player_job().get("phase")=="prepared" and cook.stock_for(Props.scope(exploration)).get("flour")==2,
		"Real physics time completes prep and reserves ingredients.")
	check(await arrive("cook"),"The isolated stove approach is reachable.")
	exploration.interact()
	await frames(310)
	check(cook.player_job().get("phase")=="cooked","The standalone timer finishes heating before plating.")
	check(await arrive("serve"),"The isolated serving counter is reachable.")
	exploration.interact()
	await frames(72)
	var request: Dictionary = scene.businesses.request_player(host,DISH)
	await frames(110)
	var visit: Dictionary = scene.businesses.service.result("player")
	check(request["ok"] and visit.get("state")=="complete" and visit.get("result_id")==Plan.DEFAULT_RECIPE
		and scene.businesses.service.inventory["player"].get("Tomato pan bread")==1
		and cook.stock_for(Props.scope(exploration)).get(DISH)==0,
		"The isolated café completes and consumes one actual dish.")
	scene.free()
	await process_frame
	print("PORTABLE COOKING: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
