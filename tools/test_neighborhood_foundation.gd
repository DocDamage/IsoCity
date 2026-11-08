extends SceneTree
const Plan=preload("res://scripts/builder/neighborhood_plan.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for frame in 3: await physics_frame
	await process_frame
func support(world: Node,point: Vector2) -> Dictionary:
	var query:=PhysicsRayQueryParameters3D.create(Vector3(point.x,10,point.y),Vector3(point.x,-10,point.y),2)
	return world.get_world_3d().direct_space_state.intersect_ray(query)
func run() -> void:
	var library=preload("res://scripts/builder/asset_library.gd").new()
	for sculpted in [false,true]:
		var source: Dictionary=preload("res://scripts/builder/templates.gd").make("3d","blank")
		if sculpted: source["terrain"]={"enabled":true,"bounds":[-4,-4,8,8]}; source["terrain_vertices"]=[]; source["water_cells"]=[]
		var config: Dictionary=Plan.defaults(); config["density"]=0; config["origin"]=[20,20]
		var result: Dictionary=Plan.generate(source,config,library); check(result["ok"],"A far-away road district is valid with and without sculpted terrain")
		var world: Node=preload("res://scripts/builder/world_3d.gd").new(); world.library=library; root.add_child(world); world.apply(source)
		var point: Vector2=result["bounds"].end-Vector2.ONE*10
		await settle(); check(support(world,point).is_empty(),"The support probe starts outside the original city foundation")
		var doc=preload("res://scripts/builder/document.gd").new(); doc.data=result["data"]; doc.record_completed_change(source); world.apply(doc.data); await settle()
		var hit: Dictionary=support(world,point)
		check(not hit.is_empty() and absf(hit.get("position",Vector3.INF).y)<.01,"Generated parcels beyond the old foundation receive actual support at the city datum")
		check(preload("res://scripts/builder/city_foundation.gd").bounds(doc.data).encloses(result["bounds"]),"The foundation encloses the complete road district and its sidewalks")
		var mesh: Mesh=world.get_node("Foundation").get_child(0).mesh; world.apply(doc.data)
		check(world.get_node("Foundation").get_child(0).mesh==mesh and world.terrain.last_rebuilt==0,"Unchanged reapplication retains the support mesh and terrain chunks")
		doc.undo(); world.apply(doc.data); await settle(); check(support(world,point).is_empty(),"Neighborhood Undo restores the original bounded support")
		doc.redo(); world.apply(doc.data); await settle(); check(not support(world,point).is_empty(),"Neighborhood Redo restores expanded physical support")
		check(source.get("terrain_vertices",[]).is_empty() and source.get("water_cells",[]).is_empty(),"Foundation growth preserves authored terrain and water records")
		world.free()
	print("NEIGHBORHOOD FOUNDATION: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
