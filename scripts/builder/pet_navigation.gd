extends RefCounted

const Plan = preload("res://scripts/builder/pet_plan.gd")
const Obstacles = preload("res://scripts/builder/walk_obstacles.gd")
const TerrainRoutes = preload("res://scripts/builder/terrain_navigation.gd")
const FloorTerrain = preload("res://scripts/builder/floor_terrain_plan.gd")

var scope_world: Node
var mode: String
var source: Dictionary
var heights: Dictionary
var water: Dictionary
var sculpted: bool
var obstacles: Array[Rect2] = []
var passages: Array = []

func configure(context: Dictionary, dimension: String) -> void:
	scope_world = context["world"]
	mode = dimension
	source = context["data"]
	sculpted = Plan.Terrain.settings(source)["enabled"]
	heights = Plan.Terrain.lookup(source) if sculpted else {}
	water = Plan.Terrain.lookup(source,true) if sculpted else {}
	obstacles = TerrainRoutes.obstacles(source,mode == "2d")
	passages = context.get("passages",[])
	for polygon in passages:
		var rect := Rect2(Plan.metric(polygon[0],mode),Vector2.ZERO)
		for point in polygon: rect = rect.expand(Plan.metric(point,mode))
		obstacles.append(rect)
	var relative: Variant = scope_world.global_transform.affine_inverse()
	for node in context["instances"].values():
		if is_instance_valid(node) and node.is_visible_in_tree():
			Obstacles.append(node,obstacles,func(body: Node)->int: return body.collision_layer & 1,height,relative,.15)

func height(point: Vector2) -> float:
	return Plan.Terrain.sample(source,Plan.terrain_point(point,mode),heights)["height"] if sculpted else 0.0

func metric(position: Variant) -> Vector2:
	var point: Variant = scope_world.to_local(position)
	return point/Vector2(16,8) if mode == "2d" else Vector2(point.x,point.z)

func position(point: Vector2) -> Variant:
	if mode == "2d": return scope_world.to_global(point*Vector2(16,8))
	return scope_world.to_global(Vector3(point.x,height(point)+.055,point.y))

func safe(point: Vector2) -> bool:
	if not point.is_finite() or not Plan.Utility.Layers.shown(source,"Ground"): return false
	var ground: Vector2 = Plan.terrain_point(point,mode)
	if FloorTerrain.contains(passages,ground): return false
	if not sculpted: return true
	var surface: Dictionary = Plan.Terrain.sample(source,ground,heights)
	var depth: Variant = Plan.Terrain.water_level(source,ground,heights,water)
	return (surface["inside"] and surface["normal"].y >= Plan.Terrain.WALKABLE_NORMAL
		and (depth == null or depth-surface["height"] <= Plan.Terrain.WADING_DEPTH))

func available(point: Vector2) -> bool:
	return safe(point) and not obstacles.any(func(rect: Rect2)->bool: return rect.grow(.55).has_point(point))

func path(from: Vector2, to: Vector2) -> PackedVector2Array:
	if not safe(from) or not safe(to): return PackedVector2Array()
	var result: Dictionary = Plan.Routes.route(from,to,obstacles,.22)
	if result["path"].is_empty() or from.distance_to(result["start"]) > .68 or to.distance_to(result["goal"]) > .6:
		return PackedVector2Array()
	var points: PackedVector2Array = result["path"]
	if points[-1].distance_to(to) > .02: points.append(to)
	return points
