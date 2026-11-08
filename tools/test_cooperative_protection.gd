extends SceneTree
const Plan=preload("res://scripts/builder/cooperative_plan.gd")
const Doc=preload("res://scripts/builder/document.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var library: RefCounted=preload("res://scripts/builder/asset_library.gd").new(); var base: Dictionary={"2d":preload("res://scripts/builder/templates.gd").make("2d","blank"),"3d":preload("res://scripts/builder/templates.gd").make("3d","blank")}
	var area: Dictionary={"uid":"guard","name":"Private work","owner":"alice","rect":[-8,-8,16,16]}
	check(Plan.valid_areas([area]),"A bounded named ownership area is valid")
	for bad in [null,{},[null],[{}],[area,area]]: check(not Plan.valid_areas(bad),"Malformed or duplicate areas are rejected")
	for bounds in [[0,0,0,1],[0,0,1,-1],[0,0,4097,1],[NAN,0,1,1],[true,0,1,1],[0,0]]:
		var broken: Dictionary=area.duplicate(true); broken["rect"]=bounds; check(not Plan.valid_areas([broken]),"Area coordinates and extents are finite and bounded")
	for mode in ["2d","3d"]:
		base[mode]["protected_areas"]=[area.duplicate(true)]
		var candidate: Dictionary=base.duplicate(true); candidate[mode]["objects"].append({"uid":"car","asset":"2d:Sedan_Blue","position":[0,0,0],"direction":"SE","scale":1.0})
		check(not Plan.allowed(base,candidate,"bob",library).is_empty(),"New footprint inside another builder's area is refused: "+mode)
		check(Plan.allowed(base,candidate,"alice",library).is_empty() and Plan.allowed(base,candidate,"host",library).is_empty(),"Area owner and host retain editing access: "+mode)
		var occupied: Dictionary=candidate.duplicate(true); candidate[mode]["objects"][0]["position"]=[2000,0,0]
		check(not Plan.allowed(occupied,candidate,"bob",library).is_empty(),"Moving a protected object outside does not bypass its original footprint: "+mode)
		candidate=occupied.duplicate(true); candidate[mode]["objects"][0]["name"]="Changed"; check(not Plan.allowed(occupied,candidate,"bob",library).is_empty(),"Non-positional edits to protected objects are refused: "+mode)
		for key in ["roads","tiles","terrain_vertices","water_cells"]:
			candidate=base.duplicate(true)
			candidate[mode][key]=[{"cell":[0,0],"crossing":false}] if key=="roads" else [{"cell":[0,0],"asset":"2d:Asphalt","direction":"SE"}] if key=="tiles" else [{"cell":[0,0],"height":2}] if key=="terrain_vertices" else [{"cell":[0,0],"level":2}]
			check(not Plan.allowed(base,candidate,"bob",library).is_empty(),"Protected ground editing is refused: "+mode+"/"+key)
		candidate=base.duplicate(true); candidate[mode]["roads"]=[{"cell":[100,100],"crossing":false}]; check(Plan.allowed(base,candidate,"bob",library).is_empty(),"Unrelated construction outside the protected area stays editable: "+mode)
		candidate=base.duplicate(true); candidate[mode]["blueprints"]=[{"uid":"plan","kind":"road","start":[0,0],"end":[1,0],"settings":{"width":6,"sidewalks":true,"style":"asphalt"}}]; check(not Plan.allowed(base,candidate,"bob",library).is_empty(),"Planning proposals also respect protected areas: "+mode)
		candidate=base.duplicate(true); candidate[mode]["protected_areas"][0]["owner"]="bob"; check(not Plan.allowed(base,candidate,"bob",library).is_empty(),"Client cannot grant itself ownership: "+mode)
		var edge: Dictionary=base.duplicate(true); edge[mode]["protected_areas"][0]["rect"]=[1.8,0,1,1]
		for key in ["tiles","water_cells"]:
			candidate=edge.duplicate(true); candidate[mode][key]=[{"cell":[0,0],"asset":"2d:Asphalt","direction":"SE"}] if key=="tiles" else [{"cell":[0,0],"level":2}]; check(not Plan.allowed(edge,candidate,"bob",library).is_empty(),"Actual tile/water far edges remain protected: "+mode+"/"+key)
		edge=base.duplicate(true); edge[mode]["protected_areas"][0]["rect"]=[7,-1,2,2]; edge[mode]["roads"]=[{"cell":[1,0],"crossing":false}]; candidate=edge.duplicate(true); candidate[mode]["roads"].append({"cell":[0,0],"crossing":false}); check(not Plan.allowed(edge,candidate,"bob",library).is_empty(),"Connecting a neighbor cannot alter a protected road's junction appearance: "+mode)
		var stacked: Dictionary=base.duplicate(true); stacked[mode]["floors"]=[{"uid":"upper","height":3,"room":preload("res://scripts/builder/templates.gd").make(mode,"room")}]; candidate=stacked.duplicate(true); candidate[mode]["floors"][0]["room"]["objects"].append({"uid":"far","asset":"2d:Sedan_Blue","position":[2000,0,0],"direction":"SE","scale":1.0}); check(Plan.allowed(stacked,candidate,"bob",library).is_empty(),"Upper-floor edits outside protected bounds remain possible: "+mode)
		candidate[mode]["floors"][0]["room"]["objects"].back()["position"]=[0,0,0]; check(not Plan.allowed(stacked,candidate,"bob",library).is_empty(),"Protected bounds include stacked-floor contents: "+mode)
		candidate=base.duplicate(true); candidate[mode]["layers"]={"Buildings":{"visible":false,"locked":false}}; check(not Plan.allowed(base,candidate,"bob",library).is_empty(),"Global hiding cannot bypass protected object editing: "+mode)
		var damaged: Dictionary=base[mode].duplicate(true); damaged["protected_areas"].append(null); var repair=preload("res://scripts/builder/project_repair.gd").new(library); var repaired: Dictionary=repair.world(damaged,mode,"city",0); check(repaired["protected_areas"]==[area] and not repair.issues.is_empty() and Doc.valid(repaired,mode,library),"Project repair retains valid protection and reports damaged records: "+mode)
	print("Cooperative protection: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
