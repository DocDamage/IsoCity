extends SceneTree
const Plan=preload("res://scripts/builder/terrain_plan.gd")
const Doc=preload("res://scripts/builder/document.gd")
const Delta=preload("res://scripts/builder/document_delta.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func fixture(mode: String="3d") -> Dictionary:
	return {"title":"Terrain probe","mode":mode,"objects":[],"tiles":[],"night":false,"terrain":{"enabled":true,"bounds":[-4,-4,8,8],"extension":"retain"},"terrain_vertices":[],"water_cells":[]}
func run() -> void:
	var library=preload("res://scripts/builder/asset_library.gd").new()
	check(not Plan.settings({})["enabled"],"Terrain remains opt-in for existing cities")
	check(Plan.valid_settings({"extension":1}) and Plan.valid_settings({"bounds":[-256,-256,128,128]}),"Optional settings and bounded terrain extents validate")
	for value in [null,true,"yes",[]]: check(not Plan.valid_settings(value),"Reject malformed terrain settings: "+str(value))
	for value in [[0,0,0,4],[0,0,129,4],[256,0,4,4],[0,0,8.5,8],[0,0,INF,8],[0,0,true,8],[0,0,8],[0,0,1e100,8]]: check(not Plan.valid_settings({"bounds":value}),"Reject malformed/out-of-range extents: "+str(value))
	for value in [null,true,"red","fffffg",1234]: check(not Plan.valid_settings({"water_color":value}),"Reject invalid terrain colors: "+str(value))
	check(Plan.valid_settings({"land_color":"#aabbcc","water_color":"112233aa"}) and not Plan.valid_settings({"enabled":1}),"Colors are explicit hex values and enabling is boolean")
	for mode in ["2d","3d"]:
		var data: Dictionary=fixture(mode); var original: Dictionary=data.duplicate(true)
		check(Doc.valid(data,mode,library),"Native city schema accepts terrain: "+mode)
		for value in [null,true,{},"bad"]: check(not Plan.valid_records(value,data),"Reject unreadable height samples: "+mode+str(value))
		for value in [INF,NAN,true,"2",25,-25]: check(not Plan.valid_records([{"cell":[0,0],"height":value}],data),"Reject invalid vertex elevation: "+mode+str(value))
		check(not Plan.valid_records([{"cell":[0.5,0],"height":1}],data) and not Plan.valid_records([{"cell":[5,0],"height":1}],data),"Vertex coordinates are integral and inside the authored boundary: "+mode)
		check(Plan.valid_records([{"cell":[4,4],"height":1}],data) and not Plan.valid_records([{"cell":[4,4],"level":1}],data,true),"Boundary vertices are included while water cells stop at the inner edge: "+mode)
		check(not Plan.valid_records([{"cell":[0,0],"height":1},{"cell":[0,0],"height":2}],data),"Duplicate terrain sample identities are rejected: "+mode)
		var raised: Dictionary=Plan.brush(data,"raise",Vector2.ZERO,6,2)
		check(raised["ok"] and raised["changed"]>1 and data==original,"Sculpting is deterministic and leaves its source unchanged: "+mode)
		var heights: Dictionary=Plan.lookup(raised["data"])
		check(heights["0:0"]["height"]==2 and heights["1:0"]["height"]>0 and heights["1:0"]["height"]<2 and not heights.has("3:0"),"Hills use smooth radial falloff and retain a flat brush boundary: "+mode)
		check(Plan.brush(data,"raise",Vector2.ZERO,6,2)["data"]==raised["data"],"Repeated source dabs produce identical records: "+mode)
		var lowered: Dictionary=Plan.brush(raised["data"],"lower",Vector2.ZERO,6,2)
		check(lowered["data"]["terrain_vertices"].is_empty(),"Matching lower operations return the hill to a sparse flat baseline: "+mode)
		var soil: Dictionary=Plan.brush(data,"lower",Vector2.ZERO,4,3)["data"]
		check(Plan.sample(soil,Vector2.ZERO)["height"]==-3,"Depressions extend below the original foundation: "+mode)
		var flat: Dictionary=Plan.brush(soil,"flatten",Vector2.ZERO,4,1,5)["data"]
		check(Plan.sample(flat,Vector2.ZERO)["height"]==5,"Flattening targets an authored elevation: "+mode)
		var spike: Dictionary=fixture(mode); spike["terrain_vertices"]=[{"cell":[0,0],"height":10,"extension":"keep"}]
		var smooth: Dictionary=Plan.brush(spike,"smooth",Vector2.ZERO,1,1)["data"]
		check(Plan.sample(smooth,Vector2.ZERO)["height"]==2 and smooth["terrain_vertices"][0]["extension"]=="keep","Smoothing averages a snapshot of neighboring heights and retains extensions: "+mode)
		var reset: Dictionary=Plan.brush(spike,"reset",Vector2.ZERO,1,1)["data"]
		check(reset["terrain_vertices"][0]["height"]==0 and reset["terrain_vertices"][0]["extension"]=="keep","Returning to flat ground preserves unknown sample metadata: "+mode)
		var capped: Dictionary=data
		for index in 5: capped=Plan.brush(capped,"raise",Vector2.ZERO,1,8)["data"]
		check(Plan.sample(capped,Vector2.ZERO)["height"]==Plan.MAX_HEIGHT and Plan.valid_records(capped["terrain_vertices"],capped),"Repeated sculpting clamps to supported height limits: "+mode)
		var pond: Dictionary=Plan.brush(data,"basin",Vector2.ZERO,5,3,0)["data"]
		check(not pond["water_cells"].is_empty() and Plan.water_level(pond,Vector2(.2,.2))==0 and Plan.sample(pond,Vector2.ZERO)["height"]==-3,"A basin creates lower land and a level pond surface: "+mode)
		var tiny: Dictionary=Plan.brush(data,"basin",Vector2.ZERO,1,2)["data"]
		check(Plan.water_level(tiny,Vector2(.1,.1))==0,"The smallest basin brush still paints water around a lowered vertex: "+mode)
		var drained: Dictionary=Plan.brush(pond,"drain",Vector2.ZERO,8,1)["data"]
		check(drained["water_cells"].is_empty() and Plan.sample(drained,Vector2.ZERO)["height"]==-3,"Draining removes water while preserving its sculpted depression: "+mode)
		var water_delta: Dictionary=Delta.between(pond,drained)
		check(water_delta["collections"].has("water_cells") and not water_delta["fields"].has("water_cells") and not water_delta["collections"].has("terrain_vertices"),"Draining records individual water-cell changes without copying soil: "+mode)
		var restored: Dictionary=drained.duplicate(true); Delta.apply(restored,water_delta,false); check(restored==pond,"Undo restores exact water cells and their original order: "+mode)
		var cleared: Dictionary=Plan.brush(pond,"reset",Vector2.ZERO,8,1)["data"]
		check(cleared["water_cells"].is_empty() and cleared["terrain_vertices"].is_empty(),"Reset restores dry flat ground within the brush: "+mode)
		var plane: Dictionary=fixture(mode); plane["terrain_vertices"]=[{"cell":[1,0],"height":2},{"cell":[0,1],"height":4},{"cell":[1,1],"height":6}]; plane["water_cells"]=[{"cell":[0,0],"level":3}]
		for point in [Vector2(.5,.5),Vector2(1.5,1.5),Vector2(1,1)]:
			var sample: Dictionary=Plan.sample(plane,point)
			check(is_equal_approx(sample["height"],point.x+2*point.y) and sample["normal"].distance_to(Vector3(-1,1,-2).normalized())<.00001,"Height and normals agree with both surface triangles: "+mode+str(point))
			var target:=Vector3(point.x,sample["height"],point.y); var origin: Vector3=target+Vector3(20,80,12); var hit: Dictionary=Plan.raycast(plane,origin,(target-origin)*10)
			check(hit["ok"] and hit["point"].distance_to(target)<.001 and hit["normal"].distance_to(sample["normal"])<.001,"Bounded grid rays traverse multiple cells and match the sampled surface: "+mode+str(point))
		var wet_ray: Dictionary=Plan.raycast(plane,Vector3(.1,20,.1),Vector3.DOWN,100,true)
		check(wet_ray["ok"] and wet_ray["kind"]=="water" and is_equal_approx(wet_ray["point"].y,3),"Water-aware rays hit the visible surface above the basin: "+mode)
		var land_ray: Dictionary=Plan.raycast(plane,Vector3(.1,20,.1),Vector3.DOWN)
		check(land_ray["ok"] and land_ray["kind"]=="land" and is_equal_approx(land_ray["point"].y,.3),"Land rays pass through water and reach the real bed: "+mode)
		var dry_ray: Dictionary=Plan.raycast(plane,Vector3(1.9,20,1.9),Vector3.DOWN,100,true)
		check(dry_ray["ok"] and dry_ray["kind"]=="land" and is_equal_approx(dry_ray["point"].y,5.7),"Water rays leave terrain above the shoreline dry: "+mode)
		check(not Plan.raycast(plane,Vector3(.1,20,.1),Vector3.DOWN,1)["ok"] and not Plan.raycast(plane,Vector3(1,-30,1),Vector3.UP)["ok"],"Terrain rays honor distance and front-face limits: "+mode)
		for direction in [Vector3.ZERO,Vector3(INF,0,0)]: check(not Plan.raycast(plane,Vector3.ZERO,direction)["ok"],"Invalid terrain ray directions are rejected: "+mode)
		var seam: Dictionary=Plan.raycast(spike,Vector3(20,40,20),Vector3(-20,-30,-20))
		check(seam["ok"] and seam["point"].distance_to(Vector3(0,10,0))<.001,"Analytical rays reach exact shared terrain vertices: "+mode)
		var polygons: Array[PackedVector3Array]=Plan.water_polygons(plane,Vector2i.ZERO)
		check(not polygons.is_empty() and Plan.water_level(plane,Vector2(.1,.1))==3 and Plan.water_level(plane,Vector2(1.9,1.9))==null,"Water clips to low land and leaves uphill terrain dry: "+mode)
		for polygon in polygons:
			check(polygon.size()>=3 and (polygon[1]-polygon[0]).cross(polygon[2]-polygon[0]).y>0,"Clipped water has upward winding and nonzero surface area: "+mode)
			for point in polygon: check(point.y==3 and Plan.sample(plane,Vector2(point.x,point.z))["height"]<=3.00001,"Every shoreline vertex lies above or on land at the water level: "+mode)
		check(Plan.clip_water(PackedVector3Array([Vector3.ZERO,Vector3(0,1,2),Vector3(2,1,0)]),0).is_empty(),"A water level that only touches a vertex creates no degenerate face: "+mode)
		check(Plan.sample(data,Vector2(8,8))["inside"] and not Plan.sample(data,Vector2(8.01,8))["inside"] and not Plan.sample(data,Vector2(INF,0))["inside"],"Boundary and nonfinite surface samples are safe: "+mode)
		var protected: Dictionary=data.duplicate(true); protected["layers"]={"Ground":{"locked":true}}
		var regions: Array[Rect2]=[Rect2(-1,-1,2,2)]
		var guarded: Dictionary=Plan.brush(data,"raise",Vector2.ZERO,8,1,0,regions)["data"]
		check(Plan.sample(guarded,Vector2.ZERO)["height"]==Plan.sample(data,Vector2.ZERO)["height"] and guarded!=data,"Protected footprints retain their surface while surrounding land changes: "+mode)
		guarded=Plan.brush(data,"basin",Vector2.ZERO,8,3,1,regions)["data"]
		check(Plan.water_level(guarded,Vector2.ZERO)==null and not guarded.get("water_cells",[]).is_empty(),"Protected footprints block water without blocking the whole brush: "+mode)
		check(not Plan.brush(protected,"raise",Vector2.ZERO,2,1)["ok"],"Protected Ground blocks sculpting: "+mode)
		protected["layers"]["Ground"]={"visible":false}; check(not Plan.brush(protected,"water",Vector2.ZERO,2,1)["ok"],"Hidden Ground blocks water painting: "+mode)
		for operation in ["unknown",""]: check(not Plan.brush(data,operation,Vector2.ZERO,2,1)["ok"],"Unknown brush operations are rejected: "+mode)
		for center in [Vector2(INF,0),Vector2(1e20,1e20)]: check(not Plan.brush(data,"raise",center,2,1)["ok"],"Invalid or distant brush coordinates fail without an enormous scan: "+mode)
		for radius in [0,25,INF,NAN]: check(not Plan.brush(data,"raise",Vector2.ZERO,radius,1)["ok"],"Invalid brush radii are rejected: "+mode)
		var delta: Dictionary=Delta.between(raised["data"],Plan.brush(raised["data"],"raise",Vector2.ZERO,1,1)["data"])
		check(delta["collections"]["terrain_vertices"]["changes"].size()==1 and not delta["fields"].has("terrain_vertices"),"History stores only the changed vertex: "+mode)
		var replay: Dictionary=raised["data"].duplicate(true); Delta.apply(replay,delta,true); check(Plan.sample(replay,Vector2.ZERO)["height"]==3,"Sparse terrain delta replays the new elevation: "+mode); Delta.apply(replay,delta,false); check(replay==raised["data"],"Undo restores exact source terrain records and order: "+mode)
		var repair=preload("res://scripts/builder/project_repair.gd").new(library)
		check(repair.world(plane,mode,"world",0)["terrain_vertices"]==plane["terrain_vertices"],"Valid saved terrain is preserved by repair: "+mode)
		var broken: Dictionary=fixture(mode); broken["terrain"]={"enabled":1,"bounds":[-4,-4,8.5,8],"land_color":"bad","extension":"retain"}; broken["terrain_vertices"]=[{"cell":[0.2,0.1],"height":100,"extension":"keep"},{"cell":[0,0],"height":2},{"cell":[9999,0],"height":1},null]; broken["water_cells"]=[{"cell":[1,1],"level":-100},{"cell":[1,2],"level":INF}]
		var source: Dictionary=broken.duplicate(true); var fixed: Dictionary=repair.world(broken,mode,"world",0)
		check(Doc.valid(fixed,mode,library) and broken==source,"Repair recovers a valid city without altering its damaged source: "+mode)
		check(fixed["terrain"]["extension"]=="retain" and fixed["terrain_vertices"][0]["height"]==24 and fixed["terrain_vertices"][0]["extension"]=="keep" and fixed["water_cells"][0]["level"]==-24,"Recovery clamps elevations, repairs coordinates and retains extensions: "+mode)
		check(fixed["terrain_vertices"].size()==1 and fixed["water_cells"].size()==1 and repair.issues.size()>=6,"Duplicate, out-of-bounds and unreadable samples are archived with repair evidence: "+mode)
	print("TERRAIN PLAN: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
