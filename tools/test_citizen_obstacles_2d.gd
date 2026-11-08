extends SceneTree
const Raster = preload("res://scripts/builder/citizen_obstacles_2d.gd")
const Plan = preload("res://scripts/builder/citizen_plan.gd")
var checks: int = 0
var failures: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; print("FAIL: " + message)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	# A front door on the diagonal side is outside the real building but deep
	# inside its bounding rectangle. The old obstacle made this unreachable.
	var diamond := PackedVector2Array([Vector2(0,0), Vector2(23,23), Vector2(0,46), Vector2(-23,23)])
	var start := Vector2(-30,-10); var goal := Vector2(-16.6,35.2)
	check(Plan.route(start, goal, [Rect2(-23,0,46,46)])["path"].is_empty(), "Fixture reproduces the blocked front approach with bounding-box navigation")
	var route: Dictionary = Plan.route(start, goal, Raster.polygon(diamond))
	check(not route["path"].is_empty() and route["goal"].distance_to(goal)<1, "A clear diagonal approach is reachable without changing its authored position")
	for point in route["path"]: check(not Geometry2D.is_point_in_polygon(point,diamond), "The route never passes through the building")
	var wall := PackedVector2Array([Vector2(0,-8),Vector2(0,-1),Vector2(0,1),Vector2(0,8)])
	route = Plan.route(Vector2(-5,0),Vector2(5,0),Raster.segments(wall))
	check(not route["path"].is_empty() and route["goal"]==Vector2(5,0), "Height-band wall segments retain an actual doorway gap")
	for point in route["path"]: check(absf(point.x)>.6 or absf(point.y)<1, "The doorway route stays clear of the wall")
	var closed := PackedVector2Array([Vector2(-4,-4),Vector2(4,-4),Vector2(4,-4),Vector2(4,4),Vector2(4,4),Vector2(-4,4),Vector2(-4,4),Vector2(-4,-4)])
	check(Plan.route(Vector2(-8,0),Vector2.ZERO,Raster.segments(closed))["path"].is_empty(), "Closed walls still prevent an outside actor reaching their interior")
	check(Raster.polygon(PackedVector2Array([Vector2(0,0),Vector2(100,0),Vector2(0,1000000)])).size()<=Raster.MAX_STRIPS, "Large polygon preparation remains bounded")
	check(Raster.segments(PackedVector2Array([Vector2.ZERO,Vector2(1000000,1000000)])).size()==1, "Huge segments retain a conservative bounded obstacle")
	var transformed: PackedVector2Array = Raster.metric(PackedVector2Array([Vector2(16,8)]),Transform2D(0,Vector2(16,8)))
	check(transformed==PackedVector2Array([Vector2(2,2)]), "World transforms are applied before walking-coordinate conversion")
	print("CITIZEN OBSTACLES 2D: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
