extends Node2D

const Plan=preload("res://scripts/builder/floor_plan.gd")
const Fit=preload("res://scripts/builder/grid_fit.gd")
const HEIGHT_PIXELS: float=8.0
var world: Node2D
var room: Dictionary={}
var actor: CharacterBody2D
var current_floor: String="ground"
var labels: Array=[]
var travel: Dictionary={}
var saved_physics: bool=false
var saved_offset:=Vector2.ZERO
var notice: String=""
var fade: ColorRect
var lifts: Dictionary={}
var heights: Dictionary={}
var stair_lease: Dictionary={}

func configure(base: Node2D,data: Dictionary,player: CharacterBody2D) -> void:
	world=base; room=data; actor=player; z_index=-1
	var layer:=CanvasLayer.new(); layer.layer=200; add_child(layer)
	fade=ColorRect.new(); fade.color=Color(0.035,0.05,0.075,0); fade.mouse_filter=Control.MOUSE_FILTER_IGNORE; layer.add_child(fade)
	for floor in Plan.definitions(data): heights[floor["uid"]]=float(floor["height"])
	for link in data.get("floor_links",[]):
		if link["kind"]!="elevator": continue
		var view=preload("res://scripts/builder/floor_elevator_2d.gd").new(); view.name="Elevator_"+link["uid"]; add_child(view)
		var runtime=preload("res://scripts/builder/floor_elevator_runtime.gd").new(); view.add_child(runtime); lifts[link["uid"]]=runtime; runtime.configure(self,link,view)
	after_apply()

func floor_name(uid: String) -> String:
	for floor in Plan.definitions(room):
		if floor["uid"]==uid: return floor["name"]
	return uid

func endpoint(link: Dictionary,upper: bool) -> Vector2:
	var point: Array=link["end"] if upper else link["start"]
	return Fit.pixels(Vector2(point[0],point[1]))

func after_apply() -> void:
	if not world: return
	var passages: Array=preload("res://scripts/builder/floor_terrain_plan.gd").passages(room,current_floor)
	world.terrain_traversal.exclusions=passages; world.terrain_presentation.exclusions=passages
	world.terrain.floor_holes=passages; world.terrain.configure(world.data_state,world.terrain_tiles)
	world.grid.visible=false; world.selection.visible=false; world.camera.enabled=false
	world.player.visible=false
	for node in labels:
		if is_instance_valid(node): node.free()
	labels.clear()
	for child in world.get_children():
		if child is Label and child.text.begins_with("EXIT"): child.visible=current_floor=="ground"
	for link in room.get("floor_links",[]):
		if link["kind"]!="stairs" or not current_floor in [link["lower"],link["upper"]]: continue
		var upper: bool=current_floor==link["upper"]
		var label:=Label.new(); label.text=("↓ " if upper else "↑ ")+floor_name(link["lower"] if upper else link["upper"])+" · E"
		label.position=endpoint(link,upper)+Vector2(8,-20); label.z_index=100; label.add_theme_color_override("font_shadow_color",Color.BLACK); label.add_theme_constant_override("shadow_offset_x",1); label.add_theme_constant_override("shadow_offset_y",1); add_child(label); labels.append(label)
	queue_redraw()
	for lift in lifts.values(): lift.view.refresh_floor()

func nearby_elevator() -> Node:
	if not travel.is_empty(): return null
	for lift in lifts.values():
		if lift.active(): return lift
	for lift in lifts.values():
		if lift.view.fully_inside(): return lift
	var result: Node; var distance: float=INF
	for lift in lifts.values():
		if lift.view.near() and lift.view.distance()<distance: result=lift; distance=lift.view.distance()
	return result

func nearby() -> Dictionary:
	if not travel.is_empty(): return {}
	var best: float=1.15; var result: Dictionary={}; var metric: Vector2=Fit.grid(actor.position)
	for link in room.get("floor_links",[]):
		if link["kind"]!="stairs" or not current_floor in [link["lower"],link["upper"]]: continue
		var upper: bool=current_floor==link["upper"]; var values: Array=link["end"] if upper else link["start"]
		var distance: float=metric.distance_to(Vector2(values[0],values[1]))
		if distance<best:
			best=distance; result={"link":link,"upper":upper,"target":link["lower"] if upper else link["upper"]}
	return result

func prompt() -> String:
	if not travel.is_empty(): return "Returning to stair entrance · "+travel["error"] if travel["phase"] in ["return","return_approach"] else "Taking stairs to "+floor_name(travel["target"])+"…"
	var found: Dictionary=nearby()
	if not found.is_empty(): return "E · Stairs to "+floor_name(found["target"])+( " · "+notice if not notice.is_empty() else "")
	return notice

func begin(found: Dictionary) -> void:
	if not travel.is_empty() or found.is_empty(): return
	var shared=preload("res://scripts/builder/floor_link_reservations.gd");var pool: RefCounted=shared.ledger(self);var key: String=shared.key(self,found["link"]["uid"]);var token: int=pool.acquire(key,actor)
	if token==0:notice="Stairs occupied. Wait for the resident to reach the landing.";return
	stair_lease={"pool":pool,"key":key,"token":token}
	saved_physics=actor.is_physics_processing(); saved_offset=actor.terrain_visual_offset; actor.set_physics_process(false)
	var heights: Dictionary={"ground":0.0}
	for floor in room.get("floors",[]): heights[floor["uid"]]=float(floor["height"])
	var destination: Vector2=endpoint(found["link"],not found["upper"])
	var start: Vector2=endpoint(found["link"],found["upper"]); var entered: bool=actor.position.distance_to(start)<=2
	var length: float=start.distance_to(destination)+actor.position.distance_to(start)
	travel={"source":current_floor,"target":found["target"],"origin":actor.position,"start":start,"end":destination,"path_end":destination,"width":found["link"]["width"],"length":length,"rise":heights[found["target"]]-heights[current_floor],"phase":"walk" if entered else "approach","entered":entered,"elapsed":0.0,"stalled":0.0,"timeout":maxf(8,length/maxf(1,actor.move_speed*0.55)*2+3)}
	notice=""

func switch_floor(uid: String) -> bool:
	var data: Dictionary=Plan.room(room,uid)
	if data.is_empty(): return false
	current_floor=uid; world.apply(data)
	return true

func finish(message: String="") -> void:
	if not stair_lease.is_empty():stair_lease["pool"].release(stair_lease["key"],stair_lease["token"]);stair_lease.clear()
	actor.velocity=Vector2.ZERO; actor.terrain_visual_offset=saved_offset; actor.set_physics_process(saved_physics)
	if is_instance_valid(world) and is_instance_valid(world.objects) and actor.get_parent()==world.objects: world.terrain_presentation.present(actor)
	else: actor.terrain_visual_offset=Vector2.ZERO
	if is_instance_valid(fade): fade.color.a=0
	travel={}; notice=message

func rollback(message: String) -> void:
	if current_floor!=travel["source"]:
		switch_floor(travel["source"]); travel["phase"]="rollback"; travel["wait"]=2; travel["error"]=message
	else:
		travel["phase"]="return" if travel["entered"] else "return_approach"; travel["end"]=travel["start"] if travel["entered"] else travel["origin"]; travel["error"]=message; travel["stalled"]=0.0

func _physics_process(delta: float) -> void:
	if travel.is_empty() or not is_instance_valid(actor): return
	if travel["phase"] in ["fade_out","fade_in"]:
		travel["fade_time"]+=delta
		var amount: float=clampf(travel["fade_time"]/0.16,0,1)
		fade.color.a=amount if travel["phase"]=="fade_out" else 1.0-amount
		if amount>=1:
			if travel["phase"]=="fade_in": finish(travel.get("error",""))
			else: travel["phase"]="landing"; travel["wait"]=2; switch_floor(travel["target"])
		return
	if travel["phase"] in ["landing","rollback"]:
		travel["wait"]-=1
		if travel["wait"]>0: return
		if travel["phase"]=="rollback": actor.teleport_to(travel["origin"]); travel["phase"]="fade_in"; travel["fade_time"]=0.0; return
		if not actor.clear_at(travel["end"]): rollback("Stair landing blocked. Move objects away from the landing."); return
		actor.teleport_to(travel["end"]); travel["phase"]="fade_in"; travel["fade_time"]=0.0; return
	travel["elapsed"]+=delta
	var before: Vector2=actor.position; var remaining: Vector2=(travel["start"] if travel["phase"]=="approach" else travel["end"])-before
	if remaining.length()<=maxf(2,actor.move_speed*0.55*delta):
		actor.velocity=Vector2.ZERO
		if travel["phase"]=="approach": actor.position=travel["start"]; travel["phase"]="walk"; travel["entered"]=true
		elif travel["phase"]=="return": actor.position=travel["start"]; travel["entered"]=false; travel["phase"]="return_approach"; travel["end"]=travel["origin"]
		elif travel["phase"]=="return_approach": actor.teleport_to(travel["origin"]); finish(travel["error"])
		else: travel["phase"]="fade_out"; travel["fade_time"]=0.0
		return
	actor.move_character(delta,remaining.normalized()*0.55)
	if travel["phase"]=="walk":
		var a: Vector2=Fit.grid(travel["start"]); var b: Vector2=Fit.grid(travel["path_end"]); var position: Vector2=Fit.grid(actor.position)
		var closest: Vector2=a+(b-a)*clampf((position-a).dot(b-a)/maxf(0.0001,(b-a).length_squared()),0,1)
		if position.distance_to(closest)>maxf(0.1,float(travel["width"])*0.5-0.2): rollback("Stair path blocked. Clear the flight before trying again."); return
	travel["stalled"]=travel["stalled"]+delta if actor.position.distance_to(before)<0.03 else 0.0
	if travel["stalled"]>0.4 or travel["elapsed"]>travel["timeout"]:
		if travel["phase"] in ["return","return_approach"]: actor.teleport_to(travel["origin"]); finish(travel["error"])
		else: rollback("Stair path blocked. Clear the flight before trying again.")

func _process(_delta: float) -> void:
	if is_instance_valid(fade): fade.size=get_viewport_rect().size
	if travel.is_empty() or not is_instance_valid(actor): return
	var path: Vector2=travel["path_end"]-travel["start"]
	var progress: float=clampf((actor.position-travel["start"]).dot(path)/maxf(0.01,path.length_squared()),0,1)
	actor.terrain_visual_offset=saved_offset+Vector2(0,-float(travel["rise"])*HEIGHT_PIXELS*progress) if travel["entered"] and travel["phase"] in ["walk","return","fade_out"] else saved_offset

func _notification(what: int) -> void:
	if what==NOTIFICATION_PREDELETE and not travel.is_empty() and is_instance_valid(actor): finish()

func _draw() -> void:
	if room.is_empty(): return
	var heights: Dictionary={"ground":0.0}
	for floor in room.get("floors",[]): heights[floor["uid"]]=float(floor["height"])
	for link in room.get("floor_links",[]):
		if link["kind"]!="stairs" or not current_floor in [link["lower"],link["upper"]]: continue
		var start:=Vector2(link["start"][0],link["start"][1]); var end:=Vector2(link["end"][0],link["end"][1]); var side: Vector2=(end-start).orthogonal().normalized()*float(link["width"])*0.5
		var rise: float=heights[link["upper"]]-heights[link["lower"]]; var count: int=ceili(rise/0.24)
		var base_offset:=Vector2(0,rise*HEIGHT_PIXELS if current_floor==link["upper"] else 0)
		var top_offset: Vector2=base_offset-Vector2(0,rise*HEIGHT_PIXELS)
		for sign in [-1,1]:
			var a: Vector2=Fit.pixels(start+side*sign)+base_offset; var b: Vector2=Fit.pixels(end+side*sign)
			draw_colored_polygon(PackedVector2Array([a,b+base_offset,b+top_offset]),Color("6b5138"))
		for step in count:
			var a: Vector2=start.lerp(end,float(step)/count); var b: Vector2=start.lerp(end,float(step+1)/count)
			var elevation: float=(float(step+1)/count*rise)-(rise if current_floor==link["upper"] else 0)
			var offset:=Vector2(0,-elevation*HEIGHT_PIXELS)
			var lower_offset: Vector2=offset+Vector2(0,rise/count*HEIGHT_PIXELS)
			draw_colored_polygon(PackedVector2Array([Fit.pixels(a-side)+lower_offset,Fit.pixels(a+side)+lower_offset,Fit.pixels(a+side)+offset,Fit.pixels(a-side)+offset]),Color("9b7249"))
			var polygon:=PackedVector2Array([Fit.pixels(a-side)+offset,Fit.pixels(a+side)+offset,Fit.pixels(b+side)+offset,Fit.pixels(b-side)+offset])
			draw_colored_polygon(polygon,Color("c6ae87") if step%2==0 else Color("a98c68")); draw_line(polygon[0],polygon[1],Color("4c4640"),1)
		for sign in [-1,1]: draw_line(Fit.pixels(start+side*sign)+base_offset-Vector2(0,10),Fit.pixels(end+side*sign)+top_offset-Vector2(0,10),Color("5c4c3c"),2)
