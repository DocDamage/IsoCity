extends Node3D

const Plan=preload("res://scripts/builder/floor_plan.gd")
const Surface=preload("res://scripts/builder/floor_surface_3d.gd")
var worlds: Dictionary={}
var heights: Dictionary={}
var stairs: Dictionary={}
var lifts: Dictionary={}
var room: Dictionary={}
var actor: CharacterBody3D
var current_floor: String="ground"
var visibility_stamp: String=""
var stair_reservations: RefCounted=preload("res://scripts/builder/floor_stair_reservations.gd").new(self)

func configure(base: Node3D,data: Dictionary,library: RefCounted,player: CharacterBody3D) -> void:
	room=data; actor=player; worlds["ground"]=base; heights["ground"]=0.0
	for floor in data.get("floors",[]):
		var world: Node3D=load("res://scripts/builder/world_3d.gd").new(); world.library=library; world.name="Floor_"+floor["uid"]; add_child(world)
		world.apply(floor["room"]); world.position.y=float(floor["height"])
		world.grid.visible=false; world.selection.visible=false; world.player.set_physics_process(false); world.player.collision_layer=0; world.player.visible=false; world.camera.current=false
		world.sun.visible=false
		for child in world.get_children():
			if child is WorldEnvironment: child.environment=null
		worlds[floor["uid"]]=world; heights[floor["uid"]]=float(floor["height"])
	var area:=Rect2(-6,-6,12,12)
	for world in worlds.values():
		var terrain=preload("res://scripts/builder/terrain_plan.gd")
		if terrain.settings(world.data_state)["enabled"]:
			var cells: Rect2i=terrain.bounds(world.data_state); area=area.merge(Rect2(Vector2(cells.position)*terrain.CELL_SIZE,Vector2(cells.size)*terrain.CELL_SIZE))
		for road in world.data_state.get("roads",[]): area=area.merge(Rect2(Vector2(road["cell"][0],road["cell"][1])*8-Vector2.ONE*4,Vector2.ONE*8))
		for instance in world.instances.values():
			var bounds: AABB=instance.transform*preload("res://scripts/model_bounds.gd").get_bounds(instance)
			area=area.merge(Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z)).grow(0.6))
	for link in data.get("floor_links",[]):
		for point in [link["start"],link["end"]]: area=area.merge(Rect2(Vector2(point[0],point[1]),Vector2.ZERO).grow(float(link["width"])+1))
	for uid in worlds:
		var world: Node3D=worlds[uid]; var surface=Surface.new(); surface.name="InteriorFloor"; world.add_child(surface); world.floor_surface=surface
		surface.configure(world,area,preload("res://scripts/builder/floor_cutouts_3d.gd").holes(data,uid),preload("res://scripts/builder/floor_terrain_plan.gd").passages(data,uid))
		world.floor_stack=self
	for link in data.get("floor_links",[]):
		if link["kind"]=="stairs": stairs[link["uid"]]=preload("res://scripts/builder/floor_stairs_3d.gd").build(self,link,heights)
		else:
			var view=preload("res://scripts/builder/floor_elevator_3d.gd").new(); view.name="Elevator_"+link["uid"]; add_child(view)
			var runtime=preload("res://scripts/builder/floor_elevator_runtime.gd").new(); view.add_child(runtime); lifts[link["uid"]]=runtime; runtime.configure(self,link,view)
	update_visibility()

func floor_at(height: float) -> String:
	var selected: String="ground"; var highest: float=-INF
	for uid in heights:
		if heights[uid]<=height+0.20 and heights[uid]>highest: selected=uid; highest=heights[uid]
	return selected

func update_visibility(force: bool=false) -> void:
	if not is_instance_valid(actor): return
	var local: Vector3=get_parent().to_local(actor.global_position)
	var follows_terrain: bool=false
	if worlds.has(current_floor):
		var world: Node3D=worlds[current_floor]; var point: Vector3=world.to_local(actor.global_position)
		if world.terrain_traversal.enabled:
			var metric:=Vector2(point.x,point.z)
			follows_terrain=world.terrain_traversal.sample_at(metric)["inside"] and not preload("res://scripts/builder/floor_terrain_plan.gd").contains(world.terrain_traversal.exclusions,metric)
	# A room's hills/depressions retain their owning floor. Physical passage
	# regions use the vertical datum to change storeys during stairs/lift travel.
	if not follows_terrain: current_floor=floor_at(local.y)
	var next: String=current_floor
	if next==visibility_stamp and not force: return
	visibility_stamp=next
	worlds["ground"].sun.light_energy=0.15 if worlds[current_floor].data_state.get("night",false) else 0.8
	for uid in worlds:
		var world: Node3D=worlds[uid]; var shown: bool=heights[uid]<=heights[current_floor]+0.01
		world.grid.visible=false; world.selection.visible=false
		# Keep supporting collisions active even when a higher floor is cut away.
		# Do not hide the ground world's root: it also owns this entire stack.
		world.objects.visible=shown; world.floor_surface.visible=shown
		world.terrain.visible=shown
		if world.road_node: world.road_node.visible=shown and preload("res://scripts/builder/layers.gd").shown(world.data_state,"Ground")
		for child in world.get_children():
			if child is Label3D: child.visible=shown
	for link in room.get("floor_links",[]):
		if stairs.has(link["uid"]): stairs[link["uid"]].visible=heights[link["lower"]]<=heights[current_floor]+0.01
	for lift in lifts.values(): lift.view.refresh_floor()

func nearby_elevator() -> Node:
	for lift in lifts.values():
		if lift.active(): return lift
	for lift in lifts.values():
		if lift.view.fully_inside(): return lift
	var result: Node; var distance: float=INF
	for lift in lifts.values():
		if lift.view.near() and lift.view.distance()<distance: result=lift; distance=lift.view.distance()
	return result

func _process(_delta: float) -> void:
	update_visibility()

func filter_stair_motion(from: Vector3,motion: Vector3) -> Vector3:
	return stair_reservations.filter_motion(from,motion)
func _physics_process(_delta: float) -> void:stair_reservations.synchronize()
func _notification(what: int) -> void:
	if what==NOTIFICATION_PREDELETE:stair_reservations.clear()
