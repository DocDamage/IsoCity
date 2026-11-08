extends SceneTree
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var scene: Node=load("res://city.tscn").instantiate(); root.add_child(scene)
	for frame in 6: await process_frame
	await physics_frame
	scene.zoning.set_process(false); scene.economy.set_process(false); scene.player.set_physics_process(false); scene.citizens.set_physics_process(false); scene.traffic.set_physics_process(false); scene.walking=false; scene._set_mode()
	var before: Dictionary=scene.studio_data.duplicate(true)
	check(scene.live_data["zones"].size()==1 and scene.live_data["zones"][0]["stage"]==1,"Relocated terrain project retains its authored foundation stage")
	check(scene.zoning.visuals.has("terrain_lot"),"Relocated terrain rebuilds the elevated construction presentation")
	for frame in 200:
		scene.zoning.people=scene.development_people(); scene.zoning.step(.25)
		if scene.live_data["zones"][0]["stage"]==3: break
	check(scene.live_data["zones"][0]["stage"]==3 and scene.city_instances.size()==1,"Relocated terrain lots develop into actual editable buildings")
	if scene.live_data["objects"].is_empty(): scene.free(); quit(1); return
	var item: Dictionary=scene.live_data["objects"][0]; var node: Node=scene.city_instances[item["uid"]]
	if scene.dimension=="2d": scene.terrain_presentation.refresh(); check(float(node.get_meta("terrain_height",0))==2,"Relocated grown sprites retain their terrain height")
	else: check(absf(node.position.y+load("res://scripts/builder/grid_fit.gd").footprint_bounds(item,"3d",scene.exploration.library).position.y-2)<.001,"Relocated grown models contact the supported terrain")
	check(scene.studio_data==before,"Live terrain development preserves the portable authored source")
	scene.walking=true; scene._set_mode(); scene.player.teleport_to(scene.exploration.entrance(node)); scene.exploration.interact(); check(scene.exploration.interior!=null and scene.exploration.interior_uid==item["uid"],"A building grown on terrain has an accessible owned interior")
	scene.free(); print("TERRAIN ZONING EXPORT: %d checks, %d failures"%[checks,failures]); quit(1 if failures else 0)
