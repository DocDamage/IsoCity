extends Node

signal door_changed(uid: String, opened: bool)
signal interior_requested(uid: String)
signal interior_opened
signal interior_closing
signal interior_door_changed(host_uid: String, uid: String, opened: bool)
signal interior_floor_door_changed(host_uid: String, floor_uid: String, uid: String, opened: bool)
signal preview_finished(floor_uid: String,position: Variant,notice: String)
signal preview_exit_requested(entry: Dictionary)
const Layers = preload("res://scripts/builder/layers.gd")
const FloorEntrances=preload("res://scripts/builder/floor_entrances.gd")
var dimension: String = "2d"
var library: RefCounted
var instances: Dictionary = {}
var records: Array = []
var player: Node
var enabled: bool = false
var interior: Node
var interior_uid: String = ""
var owned_room: Dictionary={}
var loaded_room_revision: String=""
var loaded_room_content: String=""
var actor_parent: Node
var actor_index: int=0
var saved_camera_zoom:=Vector2.ZERO
var exterior_states: Array = []
var return_position: Variant
var exit_position: Variant
var markers: Node
var nearby: Dictionary = {}
var marker_nodes: Dictionary = {}
var marker_states: Dictionary = {}
var door_states: Dictionary = {}
var visit_entry: Dictionary={}
var exit_markers: Node
var exit_stamp: int=0
var entering: bool=false
var entry_saved_physics: bool=false
var entry_generation: int=0
var entrance_notice: String=""
var preview: bool=false
var host_record: Dictionary={}
var room_traversal: Node
var props: Node
var power: Node
var garden: Node
var cooking: Node
var laundry: Node
var fitness: Node
var arcade: Node
var camping: Node
var pet: Node
var cycling: Node
var harbor: Node
var outpost: Node
var emergency: Node
var village: Node
var driving: Node
var photo: Node
var editor_scope: String=""

func _ready() -> void:
	props=preload("res://scripts/builder/prop_runtime.gd").new(); props.exploration=self; add_child(props)
	driving=preload("res://scripts/builder/driving_runtime.gd").new(); driving.exploration=self; add_child(driving)
	cycling=preload("res://scripts/builder/cycling_runtime.gd").new(); cycling.exploration=self; cycling.primary=driving
	driving.course=cycling; add_child(cycling)
	harbor = preload("res://scripts/builder/harbor_runtime.gd").new()
	harbor.exploration = self
	add_child(harbor)
	outpost = preload("res://scripts/builder/space_outpost_runtime.gd").new()
	outpost.exploration = self
	add_child(outpost)
	emergency = preload("res://scripts/builder/emergency_training_runtime.gd").new()
	emergency.exploration = self
	add_child(emergency)
	photo=preload("res://scripts/builder/photo_runtime.gd").new(); photo.exploration=self; add_child(photo)
	garden=preload("res://scripts/builder/garden_runtime.gd").new(); garden.exploration=self; add_child(garden)
	cooking=preload("res://scripts/builder/cooking_runtime.gd").new(); cooking.exploration=self; add_child(cooking)
	interior_closing.connect(func(): cooking.cancel_all("Left the kitchen."))
	laundry=preload("res://scripts/builder/laundry_runtime.gd").new(); laundry.exploration=self; add_child(laundry)
	interior_closing.connect(laundry.close_counter)
	fitness=preload("res://scripts/builder/fitness_runtime.gd").new(); fitness.exploration=self; add_child(fitness)
	interior_closing.connect(func(): fitness.cancel("Left the sports floor."))
	arcade=preload("res://scripts/builder/arcade_runtime.gd").new(); arcade.exploration=self; add_child(arcade)
	interior_closing.connect(func(): arcade.close("Left the arcade floor."))
	camping=preload("res://scripts/builder/camping_runtime.gd").new(); camping.exploration=self; add_child(camping)
	village = preload("res://scripts/builder/village_runtime.gd").new()
	village.exploration = self
	driving.delivery.village = village
	add_child(village)
	interior_closing.connect(func(): camping.cancel_player("Left the campsite floor."))
	pet=preload("res://scripts/builder/pet_runtime.gd").new(); pet.exploration=self; add_child(pet)
	interior_closing.connect(func(): pet.close())

static func is_building(asset: String, library_value: RefCounted) -> bool:
	return preload("res://scripts/builder/asset_behavior.gd").for_asset(asset, library_value).get("building", false)

static func is_door(asset: String, library_value: RefCounted = null) -> bool:
	return preload("res://scripts/builder/asset_behavior.gd").for_asset(asset, library_value).get("door", false)

static func has_room(item: Dictionary, library_value: RefCounted) -> bool:
	return is_building(item["asset"],library_value) or item.get("interior") is Dictionary

func update(data: Dictionary, nodes: Dictionary) -> void:
	records = data["objects"]
	instances = nodes
	if garden: garden.configure(data)
	if cooking: cooking.configure(data)
	if laundry: laundry.configure(data)
	if fitness: fitness.configure(data)
	if arcade: arcade.configure(data)
	if camping: camping.configure(data)
	if village: village.configure(data)
	if pet: pet.configure(data)
	if driving:
		driving.configure_care(data,nodes)
		driving.configure_delivery(data,nodes)
	if cycling: cycling.configure(data,nodes)
	if harbor: harbor.configure(data,nodes)
	if outpost: outpost.configure(data)
	if emergency: emergency.configure(data,nodes)
	if not markers:
		markers = Node2D.new() if dimension == "2d" else Node3D.new()
		markers.name = "Entrances"
		get_parent().add_child(markers)
	markers.visible = enabled
	var keep: Dictionary = {}
	var keep_doors: Dictionary = {}
	for item in records:
		var uid: String = item["uid"]
		if not instances.has(uid): continue
		var node: Node = instances[uid]
		if is_door(item["asset"], library):
			keep_doors[uid] = true
			var state: Array = [item, node.get_instance_id(), node.visible]
			if door_states.get(uid) != state:
				apply_door(node, item)
				door_states[uid] = state.duplicate(true)
			continue
		if not node.visible or not has_room(item, library): continue
		for entry in FloorEntrances.entries(item):
			var key: String=uid+(":"+entry["uid"] if not entry["uid"].is_empty() else "")
			keep[key]=true
			var title: String=FloorEntrances.name_for(item.get("interior",{}),entry["floor"])
			var state: Array=[item["asset"],item["direction"],item.get("entrance_anchor",{}),entry,title,node.transform,node.get_instance_id()]
			if marker_states.get(key)==state: continue
			var position_value: Variant=FloorEntrances.outside(node,item,entry,dimension,library)
			if not marker_nodes.has(key):
				var label: Node=Label.new() if dimension=="2d" else Label3D.new()
				label.modulate=Color("70f4ce")
				if dimension=="2d": label.z_index=100
				else: label.billboard=BaseMaterial3D.BILLBOARD_ENABLED; label.font_size=40
				markers.add_child(label); marker_nodes[key]=label
			marker_nodes[key].text=("⌂" if dimension=="2d" else "⌂  Entrance") if entry["uid"].is_empty() else "⌂ "+title
			marker_nodes[key].position=position_value-Vector2(8,18) if dimension=="2d" else position_value+Vector3.UP*1.5
			marker_states[key]=state.duplicate(true)
	for uid in marker_nodes.keys():
		if not keep.has(uid):
			marker_nodes[uid].free()
			marker_nodes.erase(uid)
			marker_states.erase(uid)
	for uid in door_states.keys():
		if not keep_doors.has(uid): door_states.erase(uid)

func reconcile_source(data: Dictionary) -> void:
	if not is_instance_valid(interior) or preview:return
	var owner_record: Dictionary={}
	for item in data.get("objects",[]):
		if item["uid"]==interior_uid:owner_record=item;break
	var removed: bool=owner_record.is_empty() or not owner_record.get("visible",true) or not Layers.shown(data,Layers.layer(owner_record,library)) or not owner_record.get("interior") is Dictionary
	if not removed and preload("res://scripts/builder/interior_visit_revision.gd").stamp(owner_record["interior"])==loaded_room_revision:
		host_record=owner_record;owned_room=owner_record["interior"]
		if is_instance_valid(interior.floor_stack):interior.floor_stack.room=owned_room
		var content: String=preload("res://scripts/builder/interior_visit_revision.gd").content_stamp(owned_room)
		if content!=loaded_room_content:
			loaded_room_content=content
			for floor in preload("res://scripts/builder/floor_plan.gd").definitions(owned_room):apply_room(floor["uid"])
		return
	# Emit closing while every original resident and source parent still exists.
	# World.apply then rebuilds the current city before any further simulation.
	leave_interior();entrance_notice="The visited room was removed or changed. You returned to the city; re-enter to visit its current layout."

func entrance(node: Node) -> Variant:
	for item in records:
		if instances.get(item["uid"]) == node:
			if item.has("missing_asset"): return node.transform * Vector2(0,24) if dimension == "2d" else node.transform * Vector3(0,.02,1.3)
			return preload("res://scripts/builder/entrance_anchors.gd").position_for(node, item, dimension, library)
	return node.position

func suspend_changed_instance(instance: Node) -> void:
	if not interior:return
	# World.apply has just updated this subtree's authored visibility/door state.
	# Replace its old restoration records, then suspend the new colliders before
	# another physics frame can see them on the visited room's plane.
	for state in exterior_states:
		if not state.has("collisions") or not is_instance_valid(state["node"]) or not state["node"].is_ancestor_of(instance):continue
		var saved: Array=[]
		for entry in state["collisions"]:
			if is_instance_valid(entry["node"]) and entry["node"]!=instance and not instance.is_ancestor_of(entry["node"]):saved.append(entry)
		for body in [instance]+instance.find_children("*","CollisionObject2D",true,false)+instance.find_children("*","CollisionObject3D",true,false):
			if body is CollisionObject2D or body is CollisionObject3D:
				saved.append({"node":body,"layer":body.collision_layer});body.collision_layer=0
		state["collisions"]=saved
		return

func apply_door(node: Node, item: Dictionary) -> void:
	var opened: bool = item.get("open", false)
	if node.has_method("set_door_open"):
		node.set_door_open(opened)
	elif dimension == "2d":
		if node is IsoObject:
			node.playing = false
			node.get_node("Sprite2D").frame = mini(2, node.total_frames - 1) if opened else 0
		elif node.has_method("ground_polygon"):
			var pose: Dictionary = item.duplicate(true)
			pose["direction"] = str(float(item["direction"]) + (90 if opened else 0))
			preload("res://scripts/builder/asset_instance.gd").pose(node, pose)
	else:
		var pose: Dictionary = item.duplicate(true)
		pose["direction"] = str(float(item["direction"]) + (90 if opened else 0))
		preload("res://scripts/builder/asset_instance.gd").pose(node, pose)
	Layers.collision_visibility(node, node.visible and not opened)

func set_enabled(value: bool) -> void:
	var starting: bool=value and not enabled
	if photo and photo.active: photo.stop()
	if not value and driving: driving.reset()
	if not value and cycling: cycling.reset()
	if not value and harbor: harbor.reset()
	if not value and outpost: outpost.stop()
	if not value and village: village.pause()
	if not value and props: props.reset(false)
	if not value and cooking: cooking.cancel_all("Returned to Build.")
	if not value and laundry: laundry.close_counter()
	if not value and fitness and not fitness.menu.is_empty(): fitness.cancel("Returned to Build.")
	if not value and arcade: arcade.close("Returned to Build.")
	enabled = value
	if emergency: emergency.walking_changed(value)
	if not value and camping:
		camping.cancel_player("Returned to Build.")
		camping.view.clear_views()
	if not value and pet: pet.disable_walk()
	if starting and driving and is_instance_valid(driving.construction):
		driving.configure_delivery(driving.construction.source,instances)
	if markers: markers.visible = value
	if not value and interior: leave_interior()

func prompt() -> String:
	var message: String = interaction_prompt()
	if player and player.has_method("movement_hint") and not player.movement_hint().is_empty(): message += " · " + player.movement_hint()
	return message

func interaction_prompt() -> String:
	if photo and photo.active: return "Photo mode · P · Return · WASD move camera · Space / X height · Right-drag look · Wheel zoom"
	if harbor and harbor.active(): return harbor.prompt()
	if driving and not driving.active.is_empty(): return driving.prompt()
	if props and not props.active.is_empty(): return props.prompt()
	if fitness and not fitness.session.is_empty(): return fitness.prompt()
	if arcade and arcade.active(): return arcade.prompt()
	if camping and camping.resting(): return camping.prompt()
	if pet and pet.has_menu(): return pet.prompt()
	if village and village.has_menu(): return village.prompt(village.selected)
	if cooking and cooking.player_job().get("phase","") in cooking.Plan.ACTIVE: return cooking.prompt()
	var original: String=entrance_prompt()
	if not enabled or not props or entering or nearby.has("exit") or nearby.has("stairs") or nearby.has("elevator"): return original
	if driving and is_instance_valid(driving.construction):
		var task: Dictionary=driving.construction.nearby_task()
		if not task.is_empty():
			nearby={"construction":true}
			return "E · "+task["title"]
	var drill: Dictionary = emergency.nearby_task() if emergency else {}
	if not drill.is_empty():
		nearby = {"emergency": true}
		return "E · " + drill["title"]
	var candidate: Dictionary=preload("res://scripts/builder/prop_plan.gd").nearby(self)
	var planting: Dictionary=garden.nearby() if garden else {}
	if not planting.is_empty() and (candidate.is_empty() or planting["distance"]<candidate["distance"]):
		candidate={"garden":planting["uid"],"distance":planting["distance"]}
	var kitchen: Dictionary=cooking.nearby() if cooking else {}
	if not kitchen.is_empty() and (candidate.is_empty() or kitchen["distance"]<candidate["distance"]):
		candidate={"cooking":kitchen,"distance":kitchen["distance"]}
	var laundry_station: Dictionary=laundry.nearby() if laundry else {}
	if not laundry_station.is_empty() and (candidate.is_empty() or laundry_station["distance"]<candidate["distance"]):
		candidate={"laundry":laundry_station,"distance":laundry_station["distance"]}
	var sports: Dictionary=fitness.nearby() if fitness else {}
	if not sports.is_empty() and (candidate.is_empty() or sports["distance"]<candidate["distance"]):
		candidate={"fitness":sports,"distance":sports["distance"]}
	var cabinet: Dictionary=arcade.nearby() if arcade else {}
	if not cabinet.is_empty() and (candidate.is_empty() or cabinet["distance"]<candidate["distance"]):
		candidate={"arcade":cabinet,"distance":cabinet["distance"]}
	var campsite: Dictionary=camping.nearby() if camping else {}
	if not campsite.is_empty() and (candidate.is_empty() or campsite["distance"]<candidate["distance"]):
		candidate={"camping":campsite,"distance":campsite["distance"]}
	var companion: Dictionary=pet.nearby() if pet else {}
	if not companion.is_empty() and (candidate.is_empty() or companion["distance"]<candidate["distance"]):
		candidate={"pet":companion,"distance":companion["distance"]}
	var facility: Dictionary=village.nearby() if village else {}
	if not facility.is_empty() and (candidate.is_empty() or facility["distance"] < candidate["distance"]):
		candidate = {"village":facility["uid"],"distance":facility["distance"]}
	var berth: Dictionary = harbor.nearby() if harbor else {}
	if not berth.is_empty() and (candidate.is_empty() or berth["distance"] < candidate["distance"]):
		candidate = {"harbor": true, "distance": berth["distance"]}
	var vehicle: Dictionary=driving.nearby() if driving else {}
	if not vehicle.is_empty() and (candidate.is_empty() or vehicle["distance"]<candidate["distance"]):
		var entrance_distance: float=INF
		if nearby.has("item"):
			var entrance: Node=instances.get(nearby["item"]["uid"])
			if entrance:
				var point: Variant=entrance.global_position if nearby["door"] else entrance.get_parent().to_global(FloorEntrances.outside(entrance,nearby["item"],nearby["entry"],dimension,library))
				entrance_distance=player.global_position.distance_to(point)
		if vehicle["distance"]<entrance_distance: nearby={"vehicle":vehicle}; return driving.prompt(vehicle)
	if candidate.is_empty():
		var camp_hint: String=camping.prompt() if camping else ""
		if not camp_hint.is_empty() and (nearby.is_empty() or original.is_empty()): return camp_hint
		var pet_hint: String=pet.prompt() if pet else ""
		if not pet_hint.is_empty() and (nearby.is_empty() or original.is_empty()): return pet_hint
		var drill_hint: String = emergency.prompt() if emergency else ""
		if not drill_hint.is_empty() and original.is_empty(): return drill_hint
		var harbor_hint: String = harbor.prompt() if harbor else ""
		if not harbor_hint.is_empty() and original.is_empty(): return harbor_hint
		var supply_hint: String = outpost.prompt() if outpost else ""
		if not supply_hint.is_empty() and nearby.is_empty(): return supply_hint
		return cooking.prompt() if original.is_empty() and cooking else original
	if nearby.has("item"):
		var node: Node=(room_world().instances if nearby.get("room",false) else instances).get(nearby["item"]["uid"])
		var point: Variant=node.global_position
		if not nearby["door"]:
			point=node.get_parent().to_global(FloorEntrances.outside(node,nearby["item"],nearby["entry"],dimension,library))
		if player.global_position.distance_to(point)<=candidate["distance"]: return original
	if candidate.has("harbor"):
		nearby = {"harbor": true}
		return "E · Board the moored trireme"
	if candidate.has("garden"):
		nearby={"garden":candidate["garden"]}
		return garden.prompt(candidate["garden"])
	if candidate.has("cooking"):
		nearby={"cooking":candidate["cooking"]["item"]["uid"]}
		return cooking.prompt(candidate["cooking"])
	if candidate.has("laundry"):
		nearby={"laundry":candidate["laundry"]["item"]["uid"]}
		return laundry.prompt(candidate["laundry"])
	if candidate.has("fitness"):
		nearby={"fitness":candidate["fitness"]["item"]["uid"]}
		return fitness.prompt(candidate["fitness"])
	if candidate.has("arcade"):
		nearby={"arcade":candidate["arcade"]["item"]["uid"]}
		return arcade.prompt(candidate["arcade"])
	if candidate.has("camping"):
		nearby={"camping":candidate["camping"]["site"]}
		return camping.prompt(candidate["camping"])
	if candidate.has("pet"):
		nearby={"pet":candidate["pet"]}
		return pet.interaction(candidate["pet"]["role"])
	if candidate.has("village"):
		nearby = {"village":candidate["village"]}
		return village.prompt(candidate["village"])
	nearby={"prop":candidate}; return props.prompt(candidate)

func entrance_prompt() -> String:
	nearby = {}
	if not enabled or not player: return ""
	if entering: return "Checking entrance landing…"
	if interior:
		if interior.floor_stack and interior.floor_stack.has_method("nearby_elevator"):
			var lift: Node=interior.floor_stack.nearby_elevator()
			if lift: nearby={"elevator":lift}; return lift.prompt()
		if dimension=="2d" and interior.floor_stack:
			var stack: Node2D=interior.floor_stack
			if not stack.travel.is_empty(): return stack.prompt()
			var connection: Dictionary=stack.nearby()
			if not connection.is_empty(): nearby={"stairs":connection}; return stack.prompt()
		refresh_exits()
		var best_exit: float=45.0 if dimension=="2d" else 2.5
		for entry in exits():
			var point: Variant=exit_point(entry)
			var distance: float=player.position.distance_to(point)
			if distance<best_exit: best_exit=distance; nearby={"exit":true,"exit_record":entry}
		if nearby.has("exit"): return "E · Return outside · "+FloorEntrances.name_for(owned_room,active_floor())
		var distance_limit: float = 50 if dimension == "2d" else 3.5
		var active: Node=room_world()
		for item in active.data_state["objects"]:
			if not is_door(item["asset"],library) or not active.instances.has(item["uid"]): continue
			var node: Node = active.instances[item["uid"]]
			if not node.visible: continue
			var distance: float = player.global_position.distance_to(node.global_position)
			if distance < distance_limit:
				distance_limit = distance
				nearby = {"item":item,"door":true,"room":true}
		if not nearby.is_empty(): return "E · " + ("Close door" if nearby["item"].get("open",false) else "Open door")
		return active.data_state.get("title", "Interior") + " · "+(interior.floor_stack.notice if dimension=="2d" and interior.floor_stack and not interior.floor_stack.notice.is_empty() else ("return to a marked EXIT to leave" if not exits().is_empty() else "return to the ground-floor exit to leave"))
	var best: float = 50.0 if dimension == "2d" else 3.5
	for item in records:
		if not instances.has(item["uid"]) or not instances[item["uid"]].visible: continue
		var node: Node = instances[item["uid"]]
		var door: bool = is_door(item["asset"], library)
		if not door and not has_room(item, library): continue
		for entry in ([{}] if door else FloorEntrances.entries(item)):
			var destination: Variant=node.position if door else FloorEntrances.outside(node,item,entry,dimension,library)
			var distance: float=player.position.distance_to(destination)
			if distance<best:
				best=distance; nearby={"item":item,"door":door,"entry":entry}
	if nearby.is_empty(): return entrance_notice if not entrance_notice.is_empty() else "Walk with WASD · E near a door or marked entrance · Tab to build"
	if nearby["door"]: return "E · "+("Close door" if nearby["item"].get("open",false) else "Open door")
	var entrance_prompt: String="E · Enter furnished interior" if nearby["entry"]["uid"].is_empty() else "E · Enter "+FloorEntrances.name_for(nearby["item"].get("interior",{}),nearby["entry"]["floor"])
	return entrance_prompt+(" · "+entrance_notice if not entrance_notice.is_empty() else "")

func interact() -> void:
	if photo and photo.active: return
	if harbor and harbor.active(): harbor.dock_and_exit(); return
	if driving and not driving.active.is_empty(): driving.interact(); return
	if props and not props.active.is_empty(): props.interact(); return
	if fitness and not fitness.session.is_empty(): fitness.interact(); return
	if arcade and arcade.active(): arcade.primary(); return
	if pet and pet.has_menu(): return
	if village and village.has_menu(): return
	if camping and camping.resting(): camping.interact(); return
	if cooking and cooking.player_job().get("phase","") in cooking.Plan.ACTIVE: cooking.cancel_player(); return
	prompt()
	if nearby.has("construction"): driving.construction.work()
	elif nearby.has("emergency"): emergency.interact()
	elif nearby.has("harbor"): harbor.board()
	elif nearby.has("vehicle"): driving.interact(nearby["vehicle"])
	elif nearby.has("prop"): props.interact(nearby["prop"])
	elif nearby.has("garden"): garden.interact(nearby["garden"])
	elif nearby.has("cooking"): cooking.interact(nearby["cooking"])
	elif nearby.has("laundry"): laundry.interact(nearby["laundry"])
	elif nearby.has("fitness"): fitness.interact(nearby["fitness"])
	elif nearby.has("arcade"): arcade.open_at(nearby["arcade"])
	elif nearby.has("camping"): camping.interact()
	elif nearby.has("village"): village.open(nearby["village"])
	elif nearby.has("pet"): pet.open(nearby["pet"])
	elif nearby.has("exit"):
		if preview: preview_exit_requested.emit(nearby["exit_record"]); return
		var entry: Dictionary=nearby["exit_record"]; var destination: Variant=return_position
		if entry["uid"]!=visit_entry.get("uid",""):
			for item in records:
				if item["uid"]==interior_uid: destination=FloorEntrances.outside(instances[interior_uid],item,entry,dimension,library); break
		leave_interior(destination)
	elif nearby.has("elevator"): nearby["elevator"].interact()
	elif nearby.has("stairs"): interior.floor_stack.begin(nearby["stairs"])
	elif nearby.has("item"):
		var item: Dictionary = nearby["item"]
		if nearby["door"]:
			if nearby.get("room",false):
				if active_floor()=="ground": interior_door_changed.emit(interior_uid,item["uid"],not item.get("open",false))
				else: interior_floor_door_changed.emit(interior_uid,active_floor(),item["uid"],not item.get("open",false))
			else: door_changed.emit(item["uid"], not item.get("open", false))
		else: enter_interior()

func enter_preview(host: Dictionary,room: Dictionary,floor_uid: String,point: Variant) -> void:
	if interior: return
	preview=true; nearby={"item":host,"entry":{"uid":"","floor":floor_uid}}
	enter_interior(room,point)

func enter_interior(preview_room: Dictionary={},preview_position: Variant=null) -> void:
	if interior or not nearby.has("item"): return
	if preview_room.is_empty():
		var checked: Dictionary=preload("res://scripts/builder/interiors.gd").creation_check(nearby["item"],dimension,library)
		if not checked["ok"]:entrance_notice=checked["reason"];return
	if photo and photo.active: photo.stop()
	if driving and not driving.active.is_empty(): return
	if props: props.reset(false)
	var item: Dictionary = nearby["item"]
	visit_entry=nearby.get("entry",{"uid":"","floor":"ground"}).duplicate(true); entrance_notice=""
	if preview_room.is_empty(): interior_requested.emit(item["uid"])
	var room: Dictionary=preload("res://scripts/builder/interiors.gd").ensure(item,dimension,library) if preview_room.is_empty() else preview_room
	if room.is_empty():return
	host_record=item
	owned_room=room;loaded_room_revision=preload("res://scripts/builder/interior_visit_revision.gd").stamp(room);loaded_room_content=preload("res://scripts/builder/interior_visit_revision.gd").content_stamp(room)
	var source_filter: Callable=player.terrain_motion_filter; var source_safe: Callable=player.terrain_position_safe
	interior_uid = item["uid"]
	return_position = player.position
	if dimension=="2d":
		actor_parent=player.get_parent(); actor_index=player.get_index()
		if "terrain_presentation" in get_parent() and get_parent().terrain_presentation:
			get_parent().terrain_presentation.release_actor(player)
		else: player.terrain_visual_offset=Vector2.ZERO; player.set_meta("terrain_height",0.0)
		player.reparent(get_parent(),true)
	# Interiors occupy their own editing plane. Suspend the exterior's rendering
	# and physics while inside, including objects placed far beyond the template.
	exterior_states.clear()
	for child in get_parent().get_children():
		if child == player or child == markers or child == self: continue
		if child is WorldEnvironment:
			exterior_states.append({"node":child,"environment":child.environment})
			child.environment = null
		elif child is CanvasModulate:
			exterior_states.append({"node":child,"color":child.color})
			child.color = Color(.48,.55,.78) if room.get("night",false) else Color.WHITE
		elif child is Node2D or child is Node3D:
			if child is Camera2D or child is Camera3D: continue
			var collisions: Array = []
			for body in [child] + child.find_children("*","CollisionObject2D",true,false) + child.find_children("*","CollisionObject3D",true,false):
				if body is CollisionObject2D or body is CollisionObject3D:
					collisions.append({"node":body,"layer":body.collision_layer})
					body.collision_layer = 0
			exterior_states.append({"node":child,"visible":child.visible,"collisions":collisions})
			child.visible = false
	if markers: markers.visible = false
	interior = preload("res://scripts/builder/interiors.gd").render(get_parent(),room,library)
	if dimension=="2d":
		interior.player.name="InteriorPreviewPlayer"
		player.reparent(interior.objects,true)
	if dimension=="2d" and interior.floor_stack: interior.floor_stack.switch_floor(visit_entry["floor"])
	exit_position=exit_point(visit_entry)
	var camera: Node = get_parent().camera if "camera" in get_parent() else get_parent().get_node_or_null("Camera2D" if dimension == "2d" else "Camera3D")
	if camera:
		if dimension == "2d": saved_camera_zoom=camera.zoom; camera.zoom=Vector2(2,2); camera.enabled = true
		else: camera.current = true
	var start: Variant=exit_position
	if preview_position!=null:
		start=preview_position if dimension=="2d" else get_parent().to_local(room_world(visit_entry["floor"]).to_global(preview_position))
	player.teleport_to(start)
	if dimension=="3d" and interior.floor_stack:
		interior.floor_stack.current_floor=visit_entry["floor"]; interior.floor_stack.update_visibility(true)
	room_traversal=preload("res://scripts/builder/room_traversal.gd").new(); add_child(room_traversal); room_traversal.configure(self,source_filter,source_safe)
	var terrain_start: bool=room_traversal.align_entry()
	refresh_exits()
	if preview or not visit_entry["uid"].is_empty() or room_traversal.enabled() or not terrain_start:
		entry_generation+=1; var generation: int=entry_generation
		entering=true; entry_saved_physics=player.is_physics_processing(); player.set_physics_process(false)
		for frame in 2: await get_tree().physics_frame
		if not interior or generation!=entry_generation: return
		var clear: bool=terrain_start and (player.clear_at(player.global_position) if dimension=="2d" else player.clear_at(player.global_transform,true))
		if dimension=="3d" and clear:
			var query:=PhysicsRayQueryParameters3D.create(player.global_position+Vector3.UP*.1,player.global_position-Vector3.UP*.5,player.collision_mask); query.exclude=[player.get_rid()]
			var support: Dictionary=player.get_world_3d().direct_space_state.intersect_ray(query)
			clear=not support.is_empty() and support["normal"].dot(Vector3.UP)>=cos(player.floor_max_angle)
		player.set_physics_process(entry_saved_physics); entering=false
		if not clear:
			entrance_notice="Walking start blocked or unsupported. Clear the landing before walking." if preview else "Entrance landing blocked or unsupported. Clear the landing before entering."
			leave_interior()
	if interior:interior_opened.emit()

func leave_interior(destination: Variant=null) -> void:
	if not interior: return
	if props: props.reset(false)
	interior_closing.emit()
	var checkpoint: Dictionary=preview_checkpoint() if preview else {}
	preview=false
	entry_generation+=1
	if entering: player.set_physics_process(entry_saved_physics); entering=false
	if room_traversal: room_traversal.release(); room_traversal.free(); room_traversal=null
	if dimension=="2d" and is_instance_valid(actor_parent):
		player.reparent(actor_parent,true)
		actor_parent.move_child(player,mini(actor_index,actor_parent.get_child_count()-1))
		actor_parent=null
	if player.has_method("teleport_to"): player.teleport_to(return_position if destination==null else destination)
	else: player.position = return_position if destination==null else destination
	interior.free()
	interior = null
	interior_uid = ""
	owned_room={}
	host_record={}
	visit_entry={}; exit_markers=null; exit_stamp=0
	for state in exterior_states:
		var node: Node = state["node"]
		if not is_instance_valid(node): continue
		if state.has("environment"): node.environment = state["environment"]
		elif state.has("color"): node.color = state["color"]
		else:
			node.visible = state["visible"]
			for saved in state.get("collisions",[]):
				if is_instance_valid(saved["node"]): saved["node"].collision_layer = saved["layer"]
	exterior_states.clear()
	if markers: markers.visible = enabled
	if dimension=="2d" and saved_camera_zoom!=Vector2.ZERO:
		var camera: Node=get_parent().camera if "camera" in get_parent() else get_parent().get_node_or_null("Camera2D")
		if camera: camera.zoom=saved_camera_zoom
		saved_camera_zoom=Vector2.ZERO
	if dimension=="2d" and "terrain_presentation" in get_parent() and get_parent().terrain_presentation:
		get_parent().terrain_presentation.bind_actor(player)
	if not checkpoint.is_empty(): preview_finished.emit(checkpoint["floor"],checkpoint["position"],entrance_notice)

func active_floor() -> String:
	if not interior or not interior.floor_stack: return "ground"
	if dimension=="3d": interior.floor_stack.update_visibility()
	return interior.floor_stack.current_floor

func room_world(uid: String="") -> Node:
	if not interior: return null
	if dimension=="3d" and interior.floor_stack: return interior.floor_stack.worlds.get(active_floor() if uid.is_empty() else uid,interior)
	return interior

func apply_room(uid: String) -> void:
	if not interior or (dimension=="2d" and uid!=active_floor()): return
	room_world(uid).apply(preload("res://scripts/builder/floor_plan.gd").room(owned_room,uid))

func runtime_modal() -> bool:
	if arcade and arcade.active(): return true
	if pet and pet.has_menu(): return true
	if village and village.has_menu(): return true
	if entering: return true
	if not interior or not interior.floor_stack or not interior.floor_stack.has_method("nearby_elevator"): return false
	var lift: Node=interior.floor_stack.nearby_elevator()
	return lift!=null and lift.menu.visible

func walk_allowed() -> bool:
	if photo and photo.active: return false
	if harbor and harbor.active(): return false
	if driving and not driving.active.is_empty(): return false
	if props and not props.active.is_empty(): return false
	if fitness and not fitness.session.is_empty(): return false
	if arcade and arcade.active(): return false
	if pet and pet.has_menu(): return false
	if village and village.has_menu(): return false
	if camping and camping.resting(): return false
	return room_traversal.walk_allowed() if room_traversal else true

func exits() -> Array:
	var result: Array=[]
	for entry in FloorEntrances.entries(host_record):
		if entry["floor"]==active_floor(): result.append(entry)
	# The used entrance wins ties when older entries share the room's exit.
	result.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return a["uid"]==visit_entry.get("uid","") and b["uid"]!=visit_entry.get("uid",""))
	return result

func exit_point(entry: Dictionary) -> Variant:
	var local: Variant=FloorEntrances.landing(owned_room,entry,dimension)
	if dimension=="2d": return local
	var world: Node=room_world(entry["floor"])
	if world.terrain_traversal.enabled:
		var height: float=world.terrain_traversal.sample_at(Vector2(local.x,local.z))["height"]+.025
		local.y=height if absf(local.y)<=.25 else maxf(local.y,height)
	return get_parent().to_local(world.to_global(local))

func refresh_exits() -> void:
	var available: Array=exits(); var next: int=hash([active_floor(),available,room_world().terrain.signature])
	if next==exit_stamp and is_instance_valid(exit_markers): return
	exit_stamp=next
	if is_instance_valid(exit_markers): exit_markers.free()
	exit_markers=Node2D.new() if dimension=="2d" else Node3D.new(); exit_markers.name="FloorExits"; interior.add_child(exit_markers)
	for entry in available:
		var sign: Node=Label.new() if dimension=="2d" else Label3D.new(); sign.text="EXIT · E"
		var point: Variant=exit_point(entry)
		if dimension=="2d":
			var helper: Node=room_world().terrain_traversal; var elevation: float=helper.sample_at(helper.metric(room_world().to_global(point)))["height"] if helper.enabled else 0
			sign.position=point+Vector2(0,15-elevation*8); sign.z_index=100
		else:
			sign.position=point+Vector3.UP*2.2; sign.billboard=BaseMaterial3D.BILLBOARD_ENABLED
			sign.font_size=48; sign.pixel_size=.012; sign.no_depth_test=true
		exit_markers.add_child(sign)
	if not available.is_empty(): exit_position=exit_point(available[0])

func preview_checkpoint() -> Dictionary:
	var floor_uid: String=active_floor()
	var point: Variant=player.position if dimension=="2d" else room_world(floor_uid).to_local(player.global_position)
	var stack: Node=interior.floor_stack
	if stack:
		if dimension=="2d" and not stack.travel.is_empty(): return {"floor":stack.travel["source"],"position":stack.travel["origin"]}
		for lift in stack.lifts.values():
			# A new preview resets the car to its first stop. Preserve a supported
			# landing even when Build is entered from an idle upstairs cabin.
			if not lift.active() and not (lift.phase=="idle" and stack.current_floor==lift.last_stop and lift.view.fully_inside()): continue
			var landing:=Vector2(lift.link["start"][0],lift.link["start"][1]+float(lift.link["width"])*.5+.95)
			return {"floor":lift.last_stop,"position":preload("res://scripts/builder/grid_fit.gd").pixels(landing) if dimension=="2d" else Vector3(landing.x,.05,landing.y)}
		if dimension=="3d":
			var metric:=Vector2(point.x,point.z)
			for link in owned_room.get("floor_links",[]):
				if link["kind"]!="stairs": continue
				var a:=Vector2(link["start"][0],link["start"][1]); var b:=Vector2(link["end"][0],link["end"][1]); var direction: Vector2=(b-a).normalized()
				var progress: float=(metric-a).dot(b-a)/maxf(.001,(b-a).length_squared())
				if progress<0 or progress>1 or metric.distance_to(a.lerp(b,progress))>float(link["width"])*.5+.3: continue
				var height: float=lerpf(stack.heights[link["lower"]],stack.heights[link["upper"]],progress)
				if absf(player.position.y-height)>.5: continue
				var upper: bool=floor_uid==link["upper"]; var landing: Vector2=b+direction*.8 if upper else a-direction*.8
				return {"floor":link["upper"] if upper else link["lower"],"position":Vector3(landing.x,.05,landing.y)}
	return {"floor":floor_uid,"position":point}
