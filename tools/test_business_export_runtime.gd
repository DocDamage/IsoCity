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
	var manager: Node=scene.businesses; var citizens: Node=scene.citizens
	manager.set_physics_process(false); citizens.set_physics_process(false); scene.player.set_physics_process(false)
	var uid: String=manager.service.businesses.keys()[0]
	check(manager.service.businesses.size()==1 and citizens.residents.size()==3,"Fresh portable project discovers the authored business and residents")
	scene.player.teleport_to(scene.exploration.entrance(scene.exploration.instances[uid]))
	await physics_frame
	await process_frame
	await process_frame
	var panel: PanelContainer=manager.panel
	check(panel.is_visible_in_tree(),"The business panel appears at the entrance")
	for prompt: Label in scene.walk_prompt.get_parent().get_children():
		var text_rect := Rect2(prompt.global_position,prompt.get_combined_minimum_size())
		check(not panel.get_global_rect().intersects(text_rect),"The business panel clears the portable prompt: "+prompt.text)
	var key:=InputEventKey.new(); key.pressed=true; key.keycode=KEY_G; scene._unhandled_input(key)
	check(manager.service.result("player").get("state","")=="active","The portable walking shortcut starts a verified business activity")
	manager.step(6,false)
	check(manager.service.inventory.get("player",{}).get("Coffee",0)==1,"Portable activities grant real session items")
	scene.exploration.interact()
	key.shift_pressed=true; scene._unhandled_input(key)
	check(scene.exploration.interior!=null and manager.service.result("player")["action"]=="snack","Portable owned interiors retain the second activity shortcut")
	manager.step(8,false)
	check(manager.service.inventory["player"].get("Snack",0)==1,"Portable interior activities complete and retain their results")
	scene.exploration.leave_interior()
	scene.player.teleport_to(Vector2(10000,10000) if scene.dimension=="2d" else Vector3(1000,0,1000))
	# Flush the restored exterior colliders and relocated player before running
	# synchronous movement; otherwise physics may still see the old player body.
	await physics_frame
	await process_frame
	var completed: bool=false
	for frame in 6000:
		# Hold midday for this travel/service probe. Routine tests separately
		# cover the 13:00 transition back to work, which can interrupt this queue.
		citizens.hour=12.5
		await physics_frame
		citizens.step(1.0/60); manager.step(1.0/60,false)
		if citizens.residents.all(func(r: Dictionary):return manager.service.inventory.get(r["id"],{}).get("Coffee",0)==1): completed=true; break
	if not completed:
		for resident in citizens.residents: print("Resident diagnostic: ",resident["id"]," ",resident["status"]," ",resident["actor"].position," path index ",resident["index"],"/",resident["path"].size())
		print("Business diagnostic: ",manager.service.inventory," ",manager.service.visits)
	check(completed,"Portable residents physically reach the business, queue and complete their activities")
	scene.queue_free(); await process_frame
	print("BUSINESS EXPORT: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
