extends Node2D

const Fit=preload("res://scripts/builder/grid_fit.gd")
var controller: Node
var stack: Node2D
var actor: CharacterBody2D
var width: float=1.2
var center:=Vector2.ZERO
var bodies: Array=[]
var gate: StaticBody2D
var own: Array[RID]=[]
var amounts: Dictionary={}
var label: Label
var captured:=Vector2.ZERO
var fade: ColorRect
var arrival_phase: String=""
var arrival_time: float=0
var arrival_wait: int=0
var arrival_result: int=1
var source_floor: String=""

func polygon(area: Rect2) -> PackedVector2Array:
	return PackedVector2Array([Fit.pixels(area.position),Fit.pixels(Vector2(area.end.x,area.position.y)),Fit.pixels(area.end),Fit.pixels(Vector2(area.position.x,area.end.y))])

func body(area: Rect2) -> StaticBody2D:
	var result:=StaticBody2D.new(); result.collision_layer=1; add_child(result); own.append(result.get_rid()); bodies.append(result)
	var collision:=CollisionPolygon2D.new(); collision.polygon=polygon(area); result.add_child(collision); return result

func configure(runtime: Node) -> void:
	controller=runtime; stack=runtime.stack; actor=runtime.actor; width=float(runtime.link["width"]); center=Vector2(runtime.link["start"][0],runtime.link["start"][1]); position=Fit.pixels(center)
	for side in [-1,1]: body(Rect2(Vector2(side*(width*0.5+0.03)-0.03,-width*0.5-0.06),Vector2(0.06,width+0.12)))
	body(Rect2(-width*0.5-0.06,-width*0.5-0.06,width+0.12,0.06))
	gate=body(Rect2(-width*0.5-0.06,width*0.5+0.08,width+0.12,0.08))
	for floor in runtime.stops: amounts[floor["uid"]]=0.0
	label=Label.new(); label.text="E · Elevator"; label.position=Fit.pixels(Vector2(0,width*0.5+0.7))+Vector2(8,-14); label.z_index=100; label.add_theme_font_size_override("font_size",12); label.add_theme_color_override("font_shadow_color",Color.BLACK); label.add_theme_constant_override("shadow_offset_x",1); label.add_theme_constant_override("shadow_offset_y",1); add_child(label)
	var layer:=CanvasLayer.new(); layer.layer=200; add_child(layer); fade=ColorRect.new(); fade.color=Color(0.035,0.05,0.075,0); fade.mouse_filter=Control.MOUSE_FILTER_IGNORE; layer.add_child(fade)
	refresh_floor()

func refresh_floor() -> void:
	visible=amounts.has(stack.current_floor)
	for item in bodies: item.collision_layer=1 if visible else 0
	if visible: gate.collision_layer=0 if amounts[stack.current_floor]>=1 and absf(controller.height-stack.heights[stack.current_floor])<0.01 else 1
	queue_redraw()

func local_metric() -> Vector2:
	return Fit.grid(to_local(actor.global_position))

func fully_inside() -> bool:
	return passenger_inside(actor,stack.current_floor)

func passenger_inside(body: Node,uid: String) -> bool:
	if not body is CharacterBody2D or not amounts.has(uid) or absf(controller.height-stack.heights[uid])>.1:return false
	var point: Vector2=Fit.grid(to_local(body.global_position));var half: float=maxf(.1,width*.5-.28)
	return absf(point.x)<=half and absf(point.y)<=half and body.clear_at(body.global_position)

func distance() -> float:
	return local_metric().distance_to(Vector2(0,width*0.5+0.6)) if amounts.has(stack.current_floor) else INF

func near() -> bool:
	return fully_inside() or distance()<1.6

func query(area: Rect2,ignore_actor: bool) -> bool:
	var shape:=ConvexPolygonShape2D.new(); shape.points=polygon(area)
	var parameters:=PhysicsShapeQueryParameters2D.new(); parameters.shape=shape; parameters.transform=global_transform; parameters.collision_mask=1
	var excluded: Array[RID]=own.duplicate()
	if ignore_actor and is_instance_valid(controller.occupant()):excluded.append(controller.occupant().get_rid())
	parameters.exclude=excluded
	return get_world_2d().direct_space_state.intersect_shape(parameters,1).is_empty()

func doorway_clear(uid: String) -> bool:
	return true if uid!=stack.current_floor else query(Rect2(-width*0.5,width*0.5+0.04,width,0.16),controller.rider)

func can_move(value: float,carrying: bool) -> bool:
	if absf(value-stack.heights[stack.current_floor])>2.1: return true
	return query(Rect2(-width*0.5,-width*0.5,width,width),carrying)

func capture_actor() -> void:
	captured=controller.occupant().position;source_floor=stack.current_floor

func carry_actor() -> void:
	var body: Node=controller.occupant();body.position=captured;body.velocity=Vector2.ZERO

func present_actor() -> void:
	var body: Node=controller.occupant();stack.world.terrain_presentation.present(body)
	var travel_height: float=controller.height-float(stack.heights[stack.current_floor])
	body.set_meta("floor_travel_height",travel_height)
	body.terrain_visual_offset+=Vector2(0,-travel_height*8)
	fade.size=get_viewport_rect().size

func release_actor() -> void:
	var body: Node=controller.occupant()
	if not is_instance_valid(body):return
	body.remove_meta("floor_travel_height")
	if body.get_parent()==stack.world.objects:stack.world.terrain_presentation.present(body)
	else:body.terrain_visual_offset=Vector2.ZERO
	if is_instance_valid(fade):fade.color.a=0

func set_height(_height: float) -> void:
	queue_redraw()

func close_all() -> void:
	for uid in amounts: amounts[uid]=0.0
	refresh_floor()

func door_progress(uid: String,amount: float) -> void:
	amounts[uid]=amount; queue_redraw()

func open_at(uid: String,amount: float) -> void:
	amounts[uid]=amount; refresh_floor()

func prepare_arrival(_uid: String,carrying: bool) -> void:
	arrival_phase="out" if carrying else "check"; arrival_time=0; arrival_wait=2; arrival_result=1

func arrival_step(delta: float,uid: String,carrying: bool) -> int:
	if controller.npc_token!=0:
		# Only the player's room is instantiated in 2D. The resident adapter
		# validates an unvisited landing against its current logical room plan;
		# never switch or fade the player's floor for another passenger.
		if uid!=stack.current_floor:return 1 if controller.passenger_landing_allowed(uid) else -1
		var body: Node=controller.occupant();var landing: Vector2=stack.world.to_global(Fit.pixels(center+Vector2(0,width*.5+.95)))
		return 1 if preload("res://scripts/builder/floor_terrain_plan.gd").landing_allowed(stack.world.terrain_traversal,landing) and query(Rect2(-width*.5,-width*.5,width,width),true) and body.clear_at(landing) else -1
	if arrival_phase=="out":
		arrival_time+=delta; fade.color.a=clampf(arrival_time/0.14,0,1)
		if arrival_time>=0.14: stack.switch_floor(uid); arrival_phase="check"; arrival_wait=2
		return 0
	if arrival_phase in ["check","reject"]:
		arrival_wait-=1
		if arrival_wait>0: return 0
		if arrival_phase=="check" and uid==stack.current_floor:
			var landing: Vector2=stack.world.to_global(Fit.pixels(center+Vector2(0,width*0.5+0.95)))
			if not preload("res://scripts/builder/floor_terrain_plan.gd").landing_allowed(stack.world.terrain_traversal,landing) or not query(Rect2(-width*0.5,-width*0.5,width,width),true) or not actor.clear_at(landing):
				arrival_result=-1
				if carrying and stack.current_floor!=source_floor: stack.switch_floor(source_floor); arrival_phase="reject"; arrival_wait=2; return 0
		if not carrying: return arrival_result
		arrival_phase="in"; arrival_time=0
	if arrival_phase=="in":
		arrival_time+=delta; fade.color.a=1.0-clampf(arrival_time/0.14,0,1)
		if arrival_time>=0.14: return arrival_result
	return 0

func _draw() -> void:
	if not controller or not amounts.has(stack.current_floor): return
	var half: float=width*0.5; var offset:=Vector2(0,-(controller.height-float(stack.heights[stack.current_floor]))*8)
	draw_colored_polygon(polygon(Rect2(-half-0.12,-half-0.12,width+0.24,width+0.24)),Color("263643"))
	var cab: PackedVector2Array=polygon(Rect2(-half,-half,width,width))
	for index in cab.size(): cab[index]+=offset
	draw_colored_polygon(cab,Color("a8b7c2")); draw_polyline(PackedVector2Array([cab[0],cab[1],cab[2],cab[3],cab[0]]),Color("556e82"),2)
	for side in [-1,1]:
		var base: Vector2=Fit.pixels(Vector2(side*half,-half))+offset; draw_line(base,base-Vector2(0,16),Color("546f83"),3)
	var amount: float=amounts[stack.current_floor]
	for side in [-1,1]:
		var x: float=side*(width*0.25+amount*(width*0.55+0.12)); var bottom: Vector2=Fit.pixels(Vector2(x,half+0.1)); var side_vector:=Fit.pixels(Vector2(width*0.25,0))
		draw_colored_polygon(PackedVector2Array([bottom-side_vector,bottom+side_vector,bottom+side_vector-Vector2(0,16),bottom-side_vector-Vector2(0,16)]),Color("6e8a9e"))
