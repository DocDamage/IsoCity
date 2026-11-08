extends SceneTree

const Reservations=preload("res://scripts/builder/activity_reservations.gd")
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;print("FAIL: "+message)
func settle() -> void:
	for frame in 4:await physics_frame
	await process_frame
func run() -> void:
	var library: RefCounted=preload("res://scripts/builder/asset_library.gd").new()
	for mode in ["2d","3d"]:
		var room: Dictionary=preload("res://scripts/builder/interiors.gd").make(mode,"Passenger room");room["objects"]=[];var upper: Dictionary=room.duplicate(true)
		room["floors"]=[{"uid":"upper","name":"Upstairs","height":3,"room":upper}];room["floor_links"]=[{"uid":"lift","kind":"elevator","lower":"ground","upper":"upper","start":[0,0],"end":[0,0],"width":1.6}]
		var original: Dictionary=room.duplicate(true);var city: Dictionary={"mode":mode,"title":"Passenger city","night":false,"objects":[{"uid":"host","asset":"2d:House_Blue","position":[0,0,0],"direction":"SE","scale":1,"interior":room}],"tiles":[]}
		var world: Node=load("res://scripts/builder/world_"+mode+".gd").new();world.library=library;root.add_child(world);world.apply(city);world.walk(true);world.player.set_physics_process(false);world.player.teleport_to(world.exploration.entrance(world.instances["host"]));world.exploration.interact();await settle()
		var visit: Node=world.exploration;var stack: Node=visit.interior.floor_stack;var lift: Node=stack.lifts["lift"];world.player.teleport_to(Vector2(128,80) if mode=="2d" else Vector3(5,.03,5));await settle()
		var body: Node=load("res://scenes/items/Characters/Office_Worker.tscn").instantiate() if mode=="2d" else preload("res://scripts/builder/player_3d.gd").new()
		if mode=="2d":body.is_player_controlled=false
		else:body.active=false
		body.collision_layer=0;body.collision_mask=1 if mode=="2d" else 3;visit.interior.objects.add_child(body);body.set_physics_process(false);body.teleport_to(Vector2.ZERO if mode=="2d" else Vector3(0,.03,0));await settle()
		var identity: int=body.get_instance_id();var player_position: Variant=world.player.position;var player_physics: bool=world.player.is_physics_processing();var player_floor: String=stack.current_floor;var pool: RefCounted=Reservations.for_world(visit.interior);var owner:=RefCounted.new();var key: String="room:host:link:lift";var token: int=pool.acquire(key,owner)
		check(token!=0 and not lift.begin_passenger(body,"ground","upper",token+1),"An unowned token cannot start a resident elevator ride: "+mode)
		check(lift.begin_passenger(body,"ground","upper",token) and lift.rider and lift.npc==body and not lift.active(),"The existing elevator accepts the reserved original NPC body without taking player control: "+mode)
		if mode=="2d":upper["layers"]={"Ground":{"visible":false}}
		var max_step: float=0;var previous: float=body.global_position.y;var visual_height: float=0;var reparented: bool=false
		for frame in 1200:
			await physics_frame
			if mode=="3d":max_step=maxf(max_step,absf(body.global_position.y-previous));previous=body.global_position.y
			else:visual_height=maxf(visual_height,float(body.get_meta("floor_travel_height",0)))
			if not reparented and lift.phase=="moving" and lift.height>1.0:
				reparented=true;var holder:=Node.new();root.add_child(holder);world.reparent(holder);world.reparent(root);holder.free()
				check(lift.npc_token==token and lift.npc==body and lift.frozen and lift.rider and not body.is_physics_processing(),"Temporary scene-tree reparenting preserves the moving car's original passenger and frozen-body state: "+mode)
			if lift.passenger_result(token)["state"] in ["complete","blocked"]:break
		if mode=="2d":
			check(lift.passenger_result(token)["state"]=="blocked" and stack.current_floor==player_floor,"An unavailable unvisited landing blocks the actual NPC trip without switching the player's floor")
			upper.erase("layers");lift.retry_passenger(token)
			for frame in 600:
				await physics_frame
				if lift.passenger_result(token)["state"] in ["complete","blocked"]:break
		await process_frame
		check(lift.passenger_result(token)["state"]=="complete" and lift.phase=="idle" and lift.last_stop=="upper" and not lift.rider,"Doors complete their existing close, acceleration, arrival and opening phases for the resident: "+mode+" "+str(lift.passenger_result(token)))
		check(body.get_instance_id()==identity and (body.global_position.y>2.99 and max_step<.1 if mode=="3d" else visual_height>2.9 and body.terrain_visual_offset.y< -23),"Original resident body is carried continuously by physical/visual cabin motion: "+mode)
		check(stack.current_floor==player_floor and world.player.position==player_position and world.player.is_physics_processing()==player_physics and not lift.menu.visible,"An NPC ride does not switch, move, freeze or open a modal for the player: "+mode)
		check(pool.current(key).get("token",0)==token,"Arrival leaves the scheduler's capacity ownership intact until alighting: "+mode)
		lift.end_passenger(token);check(lift.npc_token==0 and not body.is_physics_processing() and not body.has_meta("floor_travel_height"),"Ending a resident ride restores its original physics and removes travel presentation: "+mode)
		if mode=="3d":body.reparent(stack.worlds["upper"].objects,true)
		var return_started: bool=lift.begin_passenger(body,"upper","ground",token)
		check(return_started,"The same original body can board the return trip at the upper stop: "+mode)
		for frame in 30:await physics_frame
		lift.end_passenger(token);pool.release(key,token);body.visible=false
		check(lift.npc_token==0 and not lift.rider and pool.entries.is_empty(),"Cancelling an in-flight resident releases its controller state and caller-owned capacity: "+mode)
		world.free();await settle();check(room==original and not is_instance_valid(body),"Destruction frees the original passenger without authoring source motion: "+mode)
	print("RESIDENT ELEVATOR PASSENGER: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
