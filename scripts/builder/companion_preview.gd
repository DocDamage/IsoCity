extends RefCounted
const Plan=preload("res://scripts/builder/companion_plan.gd")
const Grid=preload("res://scripts/builder/grid_fit.gd")
const Fit=preload("res://scripts/builder/asset_scale_preview.gd")
const Zone=preload("res://scripts/builder/zone_plan.gd")
const Props=preload("res://scripts/builder/prop_plan.gd")
const Layers=preload("res://scripts/builder/layers.gd")
var viewport: SubViewport
var world: Node
var token: int=0
var focus: Array=[]
var checks: int=0
var occluders: Array=[]
var cutaway: bool=false
func clear() -> void:
	token+=1
	if is_instance_valid(viewport):viewport.free()
	viewport=null;world=null;focus=[];occluders=[];cutaway=false
func see_through(value: bool) -> void:
	cutaway=value
	for node in occluders:
		if not is_instance_valid(node):continue
		if node is Node2D:
			if not node.has_meta("companion_original_modulate"):node.set_meta("companion_original_modulate",node.modulate)
			node.modulate=node.get_meta("companion_original_modulate");node.modulate.a*=.24 if value else 1
		else:
			for mesh in node.find_children("*","MeshInstance3D",true,false):
				if not mesh.has_meta("companion_original_transparency"):mesh.set_meta("companion_original_transparency",mesh.transparency)
				mesh.transparency=maxf(.75,mesh.get_meta("companion_original_transparency")) if value else mesh.get_meta("companion_original_transparency")
func valid(request: int,local: Variant) -> bool:return request==token and is_instance_valid(local) and is_instance_valid(world)
func frame() -> void:
	if not is_instance_valid(world) or not is_instance_valid(viewport):return
	var found: bool=false
	if world is Node2D:
		var area:=Rect2()
		for uid in focus:
			if world.instances.has(uid):
				var node: Node2D=world.instances[uid];var box: Rect2=Fit.projected_geometry(node) if node.has_method("configure_walk_collision") else Fit.screen_bounds(node)
				if node.has_method("configure_walk_collision"):box.position+=node.transform.basis_xform(node.terrain_visual_offset)
				area=area.merge(box) if found else box;found=true
		world.camera.position=area.get_center();var zoom: float=minf(viewport.size.x/maxf(1,area.size.x+20),viewport.size.y/maxf(1,area.size.y+20));world.camera.zoom=Vector2.ONE*zoom
	else:
		var area:=AABB()
		for uid in focus:
			if world.instances.has(uid):
				var box: AABB=Fit.render_bounds(world.instances[uid]);area=area.merge(box) if found else box;found=true
		var center: Vector3=area.get_center();var radius: float=maxf(1,area.size.length()*.5);world.camera.projection=Camera3D.PROJECTION_ORTHOGONAL;world.camera.global_position=center+Vector3(1,.9,1).normalized()*radius*3;world.camera.look_at(center)
		var extent:=Vector2.ZERO
		for corner in 8:
			var point: Vector3=world.camera.to_local(area.get_endpoint(corner));extent=extent.max(Vector2(absf(point.x),absf(point.y)))
		world.camera.size=maxf(extent.y,extent.x*float(viewport.size.y)/maxf(1,viewport.size.x))*2.3;world.camera.near=.01;world.camera.far=radius*10+100
static func issue(code: String,uid: String,message: String) -> Dictionary:return {"code":code,"uid":uid,"message":message}
static func metric(point: Variant,mode: String) -> Vector2:return Grid.grid(point) if mode=="2d" else Vector2(point.x,point.z)
func walk_point(at: Vector2,mode: String) -> Variant:
	if mode=="2d":return Grid.pixels(at)
	return Vector3(at.x,float(world.terrain_traversal.sample_at(at)["height"])+.03 if world.terrain_traversal.enabled else .2,at.y)
static func rectangle(item: Dictionary,mode: String,library: RefCounted,full: bool=false) -> Rect2:
	if not full or not item["asset"].begins_with("3d:"):return Zone.footprint(item,mode,library)
	var box: AABB=Transform3D(Basis.from_euler(preload("res://scripts/builder/rotation.gd").euler(item)*PI/180.0).scaled(Vector3.ONE*float(item["scale"])),Vector3.ZERO)*Grid.bounds_for(item["asset"],library,false)
	var scale: float=2 if mode=="2d" else 1
	return Rect2(preload("res://scripts/builder/traffic_plan.gd").metric(item["position"],mode)+Vector2(box.position.x,box.position.z)*scale,Vector2(box.size.x,box.size.z)*scale)
static func polygon(rect: Rect2) -> PackedVector2Array:return PackedVector2Array([rect.position,rect.position+Vector2(rect.size.x,0),rect.end,rect.position+Vector2(0,rect.size.y)])
func ground_supported(item: Dictionary,excluded: Array[RID]) -> bool:
	var point: Vector3=Vector3(item["position"][0],item["position"][1],item["position"][2])+Plan.centered_3d(item,world.library)
	var query:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*.4,point-Vector3.UP*.45,3,excluded)
	var hit: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and absf(hit["position"].y-point.y)<=.35 and hit["normal"].dot(Vector3.UP)>=cos(world.player.floor_max_angle)
func build(proposal: Dictionary,library: RefCounted,parent: Node,render: bool=true) -> bool:
	clear();var request: int=token;checks=0
	if not proposal.get("ok",false):return false
	proposal["geometry_checked"]=false;proposal["issues"]=[];focus=proposal["focus"].duplicate()
	var local:=SubViewport.new();viewport=local;local.name="PrivateCompanionPreview";local.size=Vector2i(640,360);local.world_2d=World2D.new();local.own_world_3d=true;local.transparent_bg=true;local.render_target_update_mode=SubViewport.UPDATE_ALWAYS if render else SubViewport.UPDATE_DISABLED;parent.add_child(local)
	var mode: String=proposal["room"]["mode"];var display: Dictionary=proposal["room"].duplicate(true)
	for field in ["citizens","traffic","businesses","services","economy","scenario","zoning","transit","weather","ambience"]:
		if display.get(field) is Dictionary:display[field]["enabled"]=false
	world=load("res://scripts/builder/world_"+mode+".gd").new();world.library=library;local.add_child(world);world.apply(display);world.grid.visible=false;world.selection.visible=false;world.player.visible=false;world.player.collision_layer=0;world.player.collision_mask=1 if mode=="2d" else 3
	var indoors: bool=not proposal["scope"].get("owner","").is_empty() or display.get("interior_room",false) or display.get("template")=="room"
	if mode=="3d" and indoors:world.get_node("Foundation").visible=false
	# CollisionObject disable modes remove physics shapes. Stop callbacks and
	# input individually while leaving actual placement colliders active.
	for node in [world]+world.find_children("*","",true,false):node.set_process(false);node.set_physics_process(false);node.set_process_input(false);node.set_process_unhandled_input(false);node.set_process_unhandled_key_input(false)
	for frame_index in 4:
		await parent.get_tree().physics_frame
		if not valid(request,local):return false
	for frame_index in 3:
		await parent.get_tree().process_frame
		if not valid(request,local):return false
	frame()
	var issues: Array=[];var recipe: Dictionary=Plan.definitions()["relationships"][proposal["recipe"]];var data: Dictionary=proposal["room"];var floors: Array[Rect2]=[];var created: Array=proposal["created"]
	for tile in data["tiles"]:floors.append(Rect2(Vector2(tile["cell"][0],tile["cell"][1])*2,Vector2.ONE*2))
	for item in data["objects"]:
		if Layers.layer(item,library)=="Ground":floors.append(rectangle(item,mode,library))
	var root_room: Dictionary=proposal["data"] if proposal["scope"].get("owner","").is_empty() else Plan.object(proposal["data"],proposal["scope"]["owner"])["interior"]
	var passages: Array=preload("res://scripts/builder/floor_terrain_plan.gd").passages(root_room,proposal["scope"].get("floor","ground")) if indoors else []
	var excluded: Array[RID]=[world.player.get_rid()]
	if mode=="3d":
		for uid in focus:
			if not world.instances.has(uid):continue
			for node in [world.instances[uid]]+world.instances[uid].find_children("*","CollisionObject3D",true,false):
				if node is CollisionObject3D:excluded.append(node.get_rid())
	for item in data["objects"]:
		if not item["uid"] in created or Layers.layer(item,library)=="Ground":continue
		var rect: Rect2=rectangle(item,mode,library,recipe["related_overlap"]);var small: Rect2=rect.grow(-minf(.02,minf(rect.size.x,rect.size.y)*.1));checks+=1
		for other in data["objects"]:
			if other["uid"]==item["uid"] or Layers.layer(other,library)=="Ground" or (recipe["related_overlap"] and other["uid"] in focus):continue
			if small.intersects(rectangle(other,mode,library).grow(-.005)):
				issues.append(issue("occupied",item["uid"],"The proposed set overlaps "+other.get("name",library.assets[other["asset"]]["name"])+". Move the group or clear this space."));break
		for region in passages:
			if not Geometry2D.intersect_polygons(polygon(small),region).is_empty():issues.append(issue("floor_connection",item["uid"],"The set overlaps a reserved stair, landing or elevator opening."));break
		if indoors:
			for point in polygon(small):
				if not floors.any(func(floor_rect: Rect2):return floor_rect.grow(.025).has_point(point)):issues.append(issue("outside_floor",item["uid"],"The set extends beyond this floor. Move it or choose a smaller source scale."));break
		if mode=="3d" and not ground_supported(item,excluded):issues.append(issue("unsupported",item["uid"],"The proposed piece has no usable supporting surface at its reviewed height."))
	var goals: Dictionary={};var exit_points: Array=[]
	if indoors:
		if not proposal["scope"].get("owner","").is_empty():
			var host: Dictionary=Plan.object(proposal["data"],proposal["scope"]["owner"])
			for entry in preload("res://scripts/builder/floor_entrances.gd").entries(host):
				if entry["floor"]==proposal["scope"].get("floor","ground"):exit_points.append(preload("res://scripts/builder/floor_entrances.gd").landing(host["interior"],entry,mode))
		if exit_points.is_empty():
			var raw: Array=data.get("exit",[0,60,0] if mode=="2d" else [0,.2,2.5]);exit_points.append(Vector2(raw[0],raw[1]) if mode=="2d" else Vector3(raw[0],raw[1],raw[2]))
		for point in exit_points:
			if not Props.standing_clear(world.exploration,point):issues.append(issue("blocked_exit","","The set blocks an existing exit or arrival point."))
	var source: Dictionary=proposal["source"]
	for point in recipe["clearance"]:
		var raw: Array=source["position"];var delta: Variant=Plan.relative_point(source,point,mode,library);var at: Variant
		if mode=="2d":at=Vector2(raw[0],raw[1])+Plan.centered_offset(source,mode,library)+delta
		else:at=Vector3(raw[0],raw[1],raw[2])+Plan.centered_3d(source,library)+delta+Vector3.UP*.2
		checks+=1
		if not Props.standing_clear(world.exploration,at):issues.append(issue("blocked_clearance",source["uid"],"The reviewed standing space around this set is blocked."))
		else:goals[Vector2i((metric(at,mode)*4).round())]=source["uid"]
	for uid in focus:
		var item: Dictionary=Plan.object(data,uid);var profile: Dictionary=Props.profile(item)
		if profile.is_empty():continue
		for key in ["approach","exit"]:
			var at: Variant=Props.ground_point({"node":world.instances[uid],"item":item,"profile":profile},world.exploration,key);checks+=1
			if not Props.standing_clear(world.exploration,at):issues.append(issue("blocked_approach",uid,"The set blocks "+key+" for "+library.assets[item["asset"]]["name"]+". Adjust its scale, position or station anchors."))
			else:goals[Vector2i((metric(at,mode)*4).round())]=uid
	if indoors and not goals.is_empty() and not issues.any(func(value: Dictionary):return value["code"]=="blocked_exit"):
		var queue: Array[Vector2i]=[Vector2i((metric(exit_points[0],mode)*4).round())];var cursor: int=0;var visited: Dictionary={}
		while cursor<queue.size() and visited.size()<12000 and not goals.is_empty():
			var cell: Vector2i=queue[cursor];cursor+=1
			if visited.has(cell):continue
			visited[cell]=true;var at: Vector2=Vector2(cell)*.25;var floor_point: Vector2=at*2 if mode=="2d" else at
			if not floors.any(func(area: Rect2):return area.has_point(floor_point)) or not Props.standing_clear(world.exploration,walk_point(at,mode)):continue
			goals.erase(cell);checks+=1
			for step in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
				if not visited.has(cell+step):queue.append(cell+step)
			if cursor%128==0:
				await parent.get_tree().process_frame
				if not valid(request,local):return false
		for uid in goals.values():issues.append(issue("unconnected_approach",uid,"No connected quarter-grid walking route from the room arrival reaches this set's standing points."))
	if not valid(request,local):return false
	proposal["issues"]=issues
	if recipe["related_overlap"]:
		for uid in focus:
			if uid!=proposal["source"]["uid"] and world.instances.has(uid):occluders.append(world.instances[uid])
	see_through(cutaway)
	if render and DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		if not valid(request,local):return false
	proposal["geometry_checked"]=true;return true
