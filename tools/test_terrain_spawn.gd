extends SceneTree
const Traffic=preload("res://scripts/builder/traffic_plan.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for frame in 6: await process_frame
	await physics_frame
func start(mode: String) -> Variant: return Vector2.ZERO if mode=="2d" else Vector3(0,.2,0)
func run() -> void:
	var studio: Control=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio); await settle()
	for mode in ["2d","3d"]:
		studio.switch_mode(mode); var doc=preload("res://scripts/builder/document.gd").new(); doc.data=preload("res://scripts/builder/templates.gd").make(mode,"blank"); doc.data["objects"]=[]; doc.data["terrain"]={"enabled":true,"bounds":[-8,-8,16,16]}; doc.data["terrain_vertices"]=[]; doc.data["water_cells"]=[]; doc.data["spawn"]=Traffic.world(Vector2.ZERO,mode,.2)
		for x in range(-8,9):
			for z in range(-8,9): doc.data["terrain_vertices"].append({"cell":[x,z],"height":2})
		studio.documents[mode]=doc; studio.changed(); await settle(); var world: Node=studio.worlds[mode]; var player: Node=world.player; player.teleport_to(start(mode)); var before: Dictionary=doc.data.duplicate(true); studio.set_walking(true); player.set_physics_process(false)
		check(player.is_player_controlled if mode=="2d" else player.active and player.position.y>=2,"Ordinary Walk starts on raised terrain: "+mode)
		for frame in 120:
			await physics_frame
			if mode=="2d": player.move_character(1.0/60,Vector2(8,4).normalized())
			else: player.move_character(1.0/60,Vector3.RIGHT)
		check(player.recovery_count==0 and (mode=="2d" or player.position.y>1.99),"Actual walking stays above raised terrain without recovery teleportation: "+mode)
		studio.set_walking(false); check(doc.data==before,"Starting and walking preserve the authored spawn and land: "+mode)
		if mode=="3d":
			player.teleport_to(Vector3(0,10,0)); studio.set_walking(true); player.set_physics_process(false); check(player.position.y==10,"Explicit above-ground starting heights remain intact"); studio.set_walking(false)
		for wet in [false,true]:
			if wet:
				for x in range(-2,2):
					for z in range(-2,2): doc.data["water_cells"].append({"cell":[x,z],"level":4})
				studio.changed(); await settle(); player.teleport_to(start(mode)); studio.set_walking(true); player.set_physics_process(false)
				check(world.terrain_traversal.safe_position(player.global_position) and world.terrain_traversal.metric(player.global_position).length()>4,"Walk relocates a submerged start to dry land: "+mode); studio.set_walking(false)
			var source: Dictionary=doc.data.duplicate(true); var path: String="res://output/terrain_spawn_"+mode+str(wet)+".tscn"; check(studio.Exporter.save_scene(world,doc.data,studio.library,path)==OK,"Authored terrain spawn exports: "+mode+str(wet))
			var viewport:=SubViewport.new(); viewport.size=Vector2i(1000,700); if mode=="3d": viewport.own_world_3d=true
			root.add_child(viewport); var playable: Node=load(path).instantiate(); viewport.add_child(playable); await settle(); playable.player.set_physics_process(false)
			check(playable.terrain_traversal.safe_position(playable.player.global_position) and (mode=="2d" or playable.player.position.y>=2),"Playable startup resolves a supported dry spawn: "+mode+str(wet))
			check(playable.studio_data==source and doc.data==source,"Spawn resolution never overwrites saved coordinates: "+mode+str(wet)); viewport.free()
			if wet:
				var portable: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(world,doc.data,studio.library,"res://output/terrain_spawn_"+mode+".zip"); check(portable["ok"],"Submerged authored starts package their safe runtime resolution: "+mode)
		doc.data["water_cells"]=[]; var home: Dictionary=doc.add("2d:House_Blue" if mode=="2d" else "3d:HanX_City/Row_Houses_A",Traffic.world(Vector2.ZERO,mode,0 if mode=="2d" else 2),"SE" if mode=="2d" else "0"); studio.changed(); await settle(); player.teleport_to(start(mode)); studio.set_walking(true); player.set_physics_process(false)
		check(player.clear_at(player.global_position) if mode=="2d" else player.clear_at(player.global_transform,true),"Walking start avoids an actual placed building: "+mode); studio.set_walking(false)
		doc.data["layers"]={"Ground":{"visible":false}}; studio.changed(); studio.set_walking(true); player.set_physics_process(false)
		check(not (player.is_player_controlled if mode=="2d" else player.active) and "Show Ground" in player.movement_hint(),"Hidden terrain suspends walking with an actionable explanation: "+mode)
		player.teleport_to(world.exploration.entrance(world.instances[home["uid"]])); world.exploration.interact(); await settle()
		check(world.exploration.interior!=null and (player.is_player_controlled if mode=="2d" else player.active),"A valid owned interior restores walking independently of hidden exterior Ground: "+mode)
		world.exploration.leave_interior(); await settle()
		check(not (player.is_player_controlled if mode=="2d" else player.active),"Returning to hidden exterior terrain suspends control again: "+mode); studio.set_walking(false); doc.data["layers"]={}
		doc.data["layers"]={"Ground":{"visible":false}}; studio.changed(); var hidden_path: String="res://output/terrain_hidden_spawn_"+mode+".tscn"; check(studio.Exporter.save_scene(world,doc.data,studio.library,hidden_path)==OK,"Hidden-ground interior state exports: "+mode)
		var hidden_view:=SubViewport.new(); hidden_view.size=Vector2i(1000,700); if mode=="3d": hidden_view.own_world_3d=true
		root.add_child(hidden_view); var hidden: Node=load(hidden_path).instantiate(); hidden_view.add_child(hidden); await settle(); hidden.player.set_physics_process(false)
		check(not (hidden.player.is_player_controlled if mode=="2d" else hidden.player.active),"Playable exterior suspension survives subsequent frames: "+mode)
		hidden.player.teleport_to(hidden.exploration.entrance(hidden.city_instances[home["uid"]])); hidden.exploration.interact(); await settle(); check(hidden.exploration.interior!=null and (hidden.player.is_player_controlled if mode=="2d" else hidden.player.active),"Playable owned interiors restore valid walking independently: "+mode)
		hidden.exploration.leave_interior(); await settle(); check(not (hidden.player.is_player_controlled if mode=="2d" else hidden.player.active),"Playable return restores exterior suspension: "+mode); hidden_view.free(); doc.data["layers"]={}
		doc.data["terrain"]["enabled"]=false; studio.changed(); player.teleport_to(start(mode)); studio.set_walking(true); player.set_physics_process(false); check(player.position==start(mode),"Disabled terrain preserves legacy walking starts: "+mode); studio.set_walking(false)
		if mode=="3d":
			doc.data["objects"]=[]; doc.data["terrain"]={"enabled":true,"bounds":[-40,-40,80,80]}; doc.data["water_cells"]=[]
			for x in range(-40,40):
				for z in range(-40,40): doc.data["water_cells"].append({"cell":[x,z],"level":4})
			studio.changed(); await settle(); player.teleport_to(start(mode)); studio.set_walking(true); player.set_physics_process(false)
			await settle(); check(not player.active and "No dry supported" in player.movement_hint(),"A completely flooded city keeps movement suspended across frames with a concrete landing explanation")
			studio.set_walking(false)
	studio.free(); print("TERRAIN SPAWN: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
