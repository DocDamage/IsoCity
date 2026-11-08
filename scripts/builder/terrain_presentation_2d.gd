extends Node
const Plan=preload("res://scripts/builder/terrain_plan.gd")
const Traffic=preload("res://scripts/builder/traffic_plan.gd")
var data: Dictionary={}
var heights: Dictionary={}
var actors: Dictionary={}
var records: Dictionary={}
var objects: Node2D
var world: Node2D
var exploration: Node
var stamps: Dictionary={}
var signature: int=0
var watching: bool=false
var exclusions: Array=[]
var external_actors: Dictionary={}
func _ready() -> void:
	get_tree().node_added.connect(added); set_process(false)
func added(node: Node) -> void:
	if watching and is_instance_valid(objects) and node is Node2D and objects.is_ancestor_of(node) and "terrain_visual_offset" in node: actors[node.get_instance_id()]=weakref(node)
func bind_actor(actor: Node2D) -> void:
	external_actors[actor.get_instance_id()]=weakref(actor)
	if watching: actors[actor.get_instance_id()]=weakref(actor)
	present(actor)
func release_actor(actor: Node2D) -> void:
	# Clear this world's presentation before another room takes ownership. A later
	# refresh must not overwrite the new room's or staircase's presentation.
	if "terrain_visual_offset" in actor: actor.terrain_visual_offset=Vector2.ZERO
	actor.set_meta("terrain_height",0.0)
	for child in actor.get_children():
		if child is Label and child.has_meta("terrain_base_position"): child.position=child.get_meta("terrain_base_position")
	actors.erase(actor.get_instance_id()); stamps.erase(actor.get_instance_id())
	external_actors.erase(actor.get_instance_id())
func configure(source: Dictionary,parent: Node2D,instances: Dictionary,visit: Node=null) -> void:
	data=source; objects=parent; world=parent.get_parent(); exploration=visit; heights=Plan.lookup(source); records.clear()
	watching=Plan.settings(source)["enabled"]
	var input_stamp: int=hash([source.get("terrain",{}),source.get("terrain_vertices",[])])
	if input_stamp!=signature: signature=input_stamp; stamps.clear()
	for item in source.get("objects",[]):
		if is_instance_valid(instances.get(item["uid"])): records[instances[item["uid"]].get_instance_id()]=item
	for node in objects.find_children("*","Node2D",true,false): added(node)
	for id in external_actors.keys():
		var actor: Node2D=external_actors[id].get_ref()
		if not is_instance_valid(actor): external_actors.erase(id)
		else: actors[id]=external_actors[id]
	refresh()
	set_process(watching)
	if not watching: actors.clear(); stamps.clear()
func refresh() -> void:
	if not is_instance_valid(objects): return
	var enabled: bool=Plan.settings(data)["enabled"] and (not is_instance_valid(exploration) or exploration.interior==null)
	for id in actors.keys():
		var actor: Node2D=actors[id].get_ref()
		if not is_instance_valid(actor) or (not external_actors.has(id) and not objects.is_ancestor_of(actor)): actors.erase(id); stamps.erase(id); continue
		# Native floor travel owns this actor's elevation until its controller releases it.
		if actor.has_meta("floor_travel_height"):continue
		var sprite: Sprite2D=actor.get_node_or_null("Sprite2D")
		if not sprite: continue
		var manual: float=float(records[id]["position"][2]) if records.has(id) else 0.0
		var stamp: int=hash([enabled,actor.global_transform,actor.get("direction"),sprite.transform,manual,exclusions])
		if stamps.get(id)==stamp: continue
		stamps[id]=stamp
		present(actor,manual)
func present(actor: Node2D,manual: float=0) -> void:
	var sprite: Sprite2D=actor.get_node_or_null("Sprite2D")
	if not sprite or not "terrain_visual_offset" in actor: return
	var enabled: bool=Plan.settings(data)["enabled"] and (not is_instance_valid(exploration) or exploration.interior==null)
	var pixel: Vector2=world.to_local(actor.global_position)
	if not actor is CharacterBody2D:
		var polygon: PackedVector2Array=preload("res://scripts/builder/asset_instance.gd").footprint(actor)
		if not polygon.is_empty():
			var box:=Rect2(polygon[0],Vector2.ZERO)
			for point in polygon: box=box.expand(point)
			pixel=world.to_local(actor.to_global(box.get_center()))
	pixel.y+=manual*8
	var ground: Vector2=Traffic.metric([pixel.x,pixel.y,0],"2d"); var height: float=Plan.sample(data,ground,heights)["height"] if enabled else 0.0
	if preload("res://scripts/builder/floor_terrain_plan.gd").contains(exclusions,ground): height=0
	var delta: Vector2=world.global_transform.basis_xform(Vector2(0,-height*8)); actor.terrain_visual_offset=sprite.global_transform.affine_inverse().basis_xform(delta); actor.set_meta("terrain_height",height)
	for child in actor.get_children():
		if child is Label:
			if not child.has_meta("terrain_base_position"): child.set_meta("terrain_base_position",child.position)
			child.position=child.get_meta("terrain_base_position")+actor.global_transform.affine_inverse().basis_xform(delta)
func _process(_delta: float) -> void:
	if is_instance_valid(world) and world.is_visible_in_tree(): refresh()
