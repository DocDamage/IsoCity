extends RefCounted
const Props=preload("res://scripts/builder/prop_plan.gd")
const Grid=preload("res://scripts/builder/grid_fit.gd")
const Zone=preload("res://scripts/builder/zone_plan.gd")
const Layers=preload("res://scripts/builder/layers.gd")
const Fit=preload("res://scripts/builder/asset_scale_preview.gd")
var viewport: SubViewport
var world: Node
var token: int=0
var checks: int=0
var queue_limit: int=12000

func clear() -> void:
	token+=1
	if is_instance_valid(viewport):viewport.free()
	viewport=null;world=null

func valid(request: int,local: Variant) -> bool:return request==token and is_instance_valid(local) and is_instance_valid(world)

static func metric(point: Variant,mode: String) -> Vector2:return Grid.grid(point) if mode=="2d" else Vector2(point.x,point.z)
static func point_at(at: Vector2,mode: String) -> Variant:return Grid.pixels(at) if mode=="2d" else Vector3(at.x,.2,at.y)
static func rectangle(item: Dictionary,mode: String,library: RefCounted) -> Rect2:
	var result: Rect2=Zone.footprint(item,mode,library)
	return Rect2(result.position,result.size.max(Vector2.ONE*.001))
static func polygons(rect: Rect2) -> PackedVector2Array:return PackedVector2Array([rect.position,rect.position+Vector2(rect.size.x,0),rect.end,rect.position+Vector2(0,rect.size.y)])
static func issue(code: String,uid: String,message: String) -> Dictionary:return {"code":code,"uid":uid,"message":message}

func frame() -> void:
	if not is_instance_valid(world) or not is_instance_valid(viewport):return
	if world is Node2D:
		var area: Rect2=Fit.screen_bounds(world.objects)
		for tile in world.data_state["tiles"]:
			var cell:=Vector2(tile["cell"][0],tile["cell"][1])
			for corner in [cell,cell+Vector2.RIGHT,cell+Vector2.ONE,cell+Vector2.DOWN]:area=area.expand(Grid.pixels(corner))
		world.camera.position=area.get_center();var zoom: float=minf(viewport.size.x/maxf(1,area.size.x+24),viewport.size.y/maxf(1,area.size.y+24));world.camera.zoom=Vector2.ONE*zoom
	else:
		var box: AABB=Fit.render_bounds(world.objects);var center: Vector3=box.get_center();var radius: float=maxf(1,box.size.length()*.5)
		world.camera.projection=Camera3D.PROJECTION_ORTHOGONAL;world.camera.global_position=center+Vector3(1,.9,1).normalized()*radius*3;world.camera.look_at(center)
		var extent:=Vector2.ZERO
		for corner in 8:
			var local: Vector3=world.camera.to_local(box.get_endpoint(corner));extent=extent.max(Vector2(absf(local.x),absf(local.y)))
		world.camera.size=maxf(extent.y,extent.x*float(viewport.size.y)/maxf(1,viewport.size.x))*2.2;world.camera.near=.01;world.camera.far=radius*8+10

func build(proposal: Dictionary,library: RefCounted,parent: Node,render: bool=true) -> bool:
	clear();var request: int=token;checks=0
	if not proposal.get("ok",false):return false
	proposal["geometry_checked"]=false;proposal["issues"]=[]
	var local:=SubViewport.new();viewport=local;local.name="PrivateInteriorKitPreview";local.size=Vector2i(640,360);local.world_2d=World2D.new();local.own_world_3d=true;local.transparent_bg=true;local.render_target_update_mode=SubViewport.UPDATE_ALWAYS if render else SubViewport.UPDATE_DISABLED;parent.add_child(local)
	var mode: String=proposal["room"]["mode"]
	world=load("res://scripts/builder/world_"+mode+".gd").new();world.library=library;local.add_child(world)
	var display: Dictionary=proposal["room"].duplicate(true)
	# Private previews show authored geometry with no transient agents or audio.
	for field in ["citizens","traffic","businesses","services","economy","scenario","zoning","transit","weather","ambience"]:
		if display.get(field) is Dictionary:display[field]["enabled"]=false
	world.apply(display);world.grid.visible=false;world.selection.visible=false;world.player.visible=false;world.player.collision_layer=0;world.player.collision_mask=1 if mode=="2d" else 3
	if mode=="3d":world.get_node("Foundation").visible=false
	# Disable callbacks, not PROCESS_MODE: CollisionObject's default disable mode
	# would otherwise remove its shapes and make clearance checks falsely pass.
	for child in [world]+world.find_children("*","",true,false):
		child.set_process(false);child.set_physics_process(false);child.set_process_input(false);child.set_process_unhandled_input(false);child.set_process_unhandled_key_input(false)
	for iteration in 4:
		await parent.get_tree().physics_frame
		if not valid(request,local):return false
	for iteration in 3:
		await parent.get_tree().process_frame
		if not valid(request,local):return false
	frame()
	var issues: Array=[];var room: Dictionary=proposal["room"];var created: Array=proposal["created"];var floors: Array[Rect2]=[];var existing: Array=[];var fresh: Array=[]
	for tile in room["tiles"]:floors.append(Rect2(Vector2(tile["cell"][0],tile["cell"][1])*2,Vector2.ONE*2))
	for item in room["objects"]:
		if Layers.layer(item,library)=="Ground":floors.append(rectangle(item,mode,library));continue
		if item["uid"] in created:
			if not item["uid"].begins_with("preview_shell_"):fresh.append(item)
		else:existing.append(item)
	var passages: Array=preload("res://scripts/builder/floor_terrain_plan.gd").passages(proposal["root"],proposal["floor_uid"])
	for item in fresh:
		var rect: Rect2=rectangle(item,mode,library);var footprint: PackedVector2Array=polygons(rect.grow(-minf(.04,minf(rect.size.x,rect.size.y)*.1)))
		for previous in existing:
			var prior: Rect2=rectangle(previous,mode,library);prior=prior.grow(-minf(.01,minf(prior.size.x,prior.size.y)*.1))
			if rect.intersects(prior):
				issues.append(issue("occupied_footprint",item["uid"],"New furnishing overlaps an existing object footprint: "+previous.get("name",library.assets[previous["asset"]]["name"])+". Adjust the offset or choose Replace."));break
		for region in passages:
			if not Geometry2D.intersect_polygons(footprint,region).is_empty():issues.append(issue("floor_connection",item["uid"],"New furnishing overlaps a reserved stair flight, landing or elevator opening. Adjust the offset."));break
		var supported: bool=true
		for corner in footprint:
			var covered: bool=false
			for floor_rect in floors:
				if floor_rect.grow(.025).has_point(corner):covered=true;break
			if not covered:supported=false;break
		if not supported:issues.append(issue("outside_floor",item["uid"],"Furnishing extends beyond the authored floor artwork. Use a smaller layout, change the offset or replace the room."))
	var raw: Array=room.get("exit",[0,60,0] if mode=="2d" else [0,.2,2.5]);var exit: Variant=Vector2(raw[0],raw[1]) if mode=="2d" else Vector3(raw[0],raw[1],raw[2])
	if not Layers.shown(room,"Ground"):issues.append(issue("hidden_ground","","Show Ground on the affected floor before applying a layout."))
	elif not Props.standing_clear(world.exploration,exit):issues.append(issue("blocked_exit","","The proposed room blocks its exit or arrival point."))
	var goals: Dictionary={}
	for item in room["objects"]:
		if not item.get("visible",true) or not Layers.shown(room,Layers.layer(item,library)):continue
		var profile: Dictionary=Props.profile(item)
		if profile.is_empty():continue
		var candidate: Dictionary={"item":item,"node":world.instances[item["uid"]],"profile":profile};var approach: Variant=Props.ground_point(candidate,world.exploration,"approach")
		checks+=1
		if not Props.standing_clear(world.exploration,approach):issues.append(issue("blocked_approach",item["uid"],"Station approach is blocked: "+item.get("name",library.assets[item["asset"]]["name"])))
		else:goals[Vector2i((metric(approach,mode)*4).round())]=item["uid"]
	if not goals.is_empty() and not issues.any(func(entry: Dictionary):return entry["code"] in ["blocked_exit","hidden_ground"]):
		var start:=Vector2i((metric(exit,mode)*4).round());var pending: Array[Vector2i]=[start];var visited: Dictionary={};var cursor: int=0
		while cursor<pending.size() and visited.size()<queue_limit and not goals.is_empty():
			var cell: Vector2i=pending[cursor];cursor+=1
			if visited.has(cell):continue
			visited[cell]=true
			var at: Vector2=Vector2(cell)*.25;var floor_point: Vector2=at*2 if mode=="2d" else at;var on_floor: bool=false
			for floor_rect in floors:
				if floor_rect.has_point(floor_point):on_floor=true;break
			if not on_floor or not Props.standing_clear(world.exploration,point_at(at,mode)):continue
			goals.erase(cell);checks+=1
			for offset in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
				if not visited.has(cell+offset):pending.append(cell+offset)
			if cursor%128==0:
				await parent.get_tree().process_frame
				if not valid(request,local):return false
		for uid in goals.values():issues.append(issue("unconnected_approach",uid,"No connected quarter-grid walking approach was found from the room exit. Move furnishings or adjust the layout."))
		if visited.size()>=queue_limit:issues.append(issue("review_limit","","The bounded walking review could not finish in this room."))
	if not valid(request,local):return false
	proposal["issues"]=issues
	if render and DisplayServer.get_name()!="headless":
		await parent.get_tree().process_frame
		if not valid(request,local):return false
		await RenderingServer.frame_post_draw
	if not valid(request,local):return false
	proposal["geometry_checked"]=true
	return true
