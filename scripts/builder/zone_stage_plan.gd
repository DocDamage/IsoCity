extends RefCounted

const PATH: String="res://resources/catalog/construction_stages.json"
const Plan=preload("res://scripts/builder/zone_plan.gd")
const Terrain=preload("res://scripts/builder/terrain_plan.gd")
const Instance=preload("res://scripts/builder/asset_instance.gd")
const MIN_SCALE: float=.12
static var catalog: Dictionary={}

static func recipes() -> Dictionary:
	if catalog.is_empty():
		var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if raw is Dictionary and raw.get("version")==1: catalog=raw
	return catalog.get("stages",{})

static func available(library: RefCounted,force: bool=false) -> Dictionary:
	var result: Dictionary={}
	for entries in recipes().values():
		for entry in entries:
			var id: String=entry["asset"]
			if result.has(id) or not library.assets.has(id): continue
			var asset: Dictionary=library.assets[id]
			if asset.get("unavailable",false) or not Plan.Candidates.source_ready(asset["path"],force): continue
			var bounds: AABB=Plan.Fit.bounds_for(id,library,false)
			if bounds.size.x>.01 and bounds.size.z>.01: result[id]=bounds
	return result

static func required_assets(data: Dictionary,library: RefCounted) -> Array:
	if data.get("zones",[]).is_empty(): return []
	return available(library,true).keys()

static func pad_color(stage: int) -> Color:
	if stage==Plan.Stage.FINISHING: return Color("ab896c")
	if stage==Plan.Stage.FRAMING: return Color("7f8991")
	return Color("8998a0")

static func layout(data: Dictionary,lot: Dictionary,library: RefCounted,art: Dictionary,heights: Dictionary) -> Dictionary:
	var result: Dictionary={"props":[],"pad":Rect2(),"fallback":false,"missing":false}
	if not Plan.stage_dressed(lot) or not lot.has("proposal"): return result
	var mode: String=data["mode"]
	var proposal: Dictionary=lot["proposal"]
	if not library.assets.has(proposal["asset"]): return result
	var plot: Rect2=Plan.rectangle(lot)
	var pad: Rect2=Plan.footprint(proposal,mode,library).intersection(plot.grow(-.5))
	if not pad.has_area(): return result
	result["pad"]=pad
	var build: Rect2=pad.grow(-.08)
	if not build.has_area():
		result["fallback"]=true
		return result
	# Orient the row toward the proposed entrance. The entire assembly stays
	# inside the footprint that the existing access planner already avoids.
	var heading: Vector2=Plan.approach(proposal,mode,library)-Plan.approach(proposal,mode,library,false)
	var front:=Vector2(signf(heading.x),0) if absf(heading.x)>absf(heading.y) else Vector2(0,signf(heading.y))
	if front.is_zero_approx(): front=Vector2.DOWN
	var side:=Vector2(front.y,-front.x)
	var yaw: int=posmod(roundi(rad_to_deg(atan2(front.x,front.y))),360)
	var metres: float=2.0 if mode=="2d" else 1.0
	var width: float=absf(side.dot(build.size))
	var depth: float=absf(front.dot(build.size))
	var rear: Vector2=build.get_center()-(side*width+front*depth)*.5
	var entries: Array=recipes().get(str(int(lot["stage"])),[])
	for index in entries.size():
		var entry: Dictionary=entries[index]
		var id: String=entry["asset"]
		if not art.has(id):
			result["missing"]=true
			if index==0: result["fallback"]=true
			continue
		var cell: Array=entry["cell"]
		var start: Vector2=rear+side*(cell[0]*width)+front*(cell[1]*depth)
		var cell_box:=Rect2(start,side*(cell[2]*width)+front*(cell[3]*depth)).abs()
		var model_yaw: int=posmod(yaw+int(entry.get("yaw_offset",0)),360)
		var rotation:=Transform3D(Basis(Vector3.UP,deg_to_rad(model_yaw)),Vector3.ZERO)
		var bounds: AABB=rotation*art[id]
		var actual:=Vector2(bounds.size.x,bounds.size.z)*metres
		var scale_value: float=minf(float(entry["scale_limit"]),minf(cell_box.size.x/actual.x,cell_box.size.y/actual.y))
		if scale_value<MIN_SCALE:
			if index==0: result["fallback"]=true
			continue
		var center: Vector2=cell_box.get_center()
		var origin: Vector2=center-Vector2(bounds.get_center().x,bounds.get_center().z)*scale_value*metres
		var ground: float=Terrain.sample(data,center,heights)["height"] if Terrain.settings(data)["enabled"] else 0.0
		var lift: float=.12 if mode=="3d" else .06
		var position: Array=Plan.Traffic.world(origin,mode,ground+lift-bounds.position.y*scale_value)
		var occupied:=Rect2(center-actual*scale_value*.5,actual*scale_value)
		result["props"].append({"asset":id,"direction":str(model_yaw),"scale":scale_value,"position":position,"bounds":occupied})
	if result["props"].is_empty(): result["fallback"]=true
	return result

static func present(parent: Node,props: Array,mode: String,library: RefCounted,night: bool) -> void:
	if props.is_empty(): return
	var scenery: Node=Node2D.new() if mode=="2d" else Node3D.new()
	scenery.name="ConstructionScenery"
	if scenery is Node2D:
		scenery.z_index=2
		scenery.y_sort_enabled=true
	parent.add_child(scenery)
	for entry in props:
		var model: Node=Instance.make(library,entry["asset"],mode,false)
		var at: Array=entry["position"]
		var size: float=entry["scale"]
		model.set_meta("stage_asset",entry["asset"])
		model.set_meta("stage_bounds",entry["bounds"])
		if model is Node2D:
			model.position=Vector2(at[0],at[1])
			model.scale=Vector2.ONE*size
		else:
			model.position=Vector3(at[0],at[1],at[2])
			model.scale=Vector3.ONE*size
		Instance.pose(model,entry,night)
		scenery.add_child(model)
		if model is Node2D: model.terrain_visual_offset=Vector2(0,-at[2]*8/size)
