extends SceneTree
const Plan=preload("res://scripts/builder/floor_elevator_plan.gd")
const Floors=preload("res://scripts/builder/floor_plan.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func room() -> Dictionary:
	return {"mode":"3d","title":"Lift","interior_room":true,"night":false,"objects":[],"tiles":[]}
func run() -> void:
	for endpoints in [[0,0],[0,2.4],[6,0],[-24,32],[32,-24]]:
		var trip: Dictionary=Plan.trip(endpoints[0],endpoints[1]); var previous: float=endpoints[0]; var bounded: bool=true; var direction: float=signf(endpoints[1]-endpoints[0])
		for frame in ceili(trip["duration"]*60)+2:
			var point: float=Plan.sample(trip,frame/60.0)
			bounded=bounded and point>=minf(endpoints[0],endpoints[1])-0.000001 and point<=maxf(endpoints[0],endpoints[1])+0.000001 and (point-previous)*direction>=-0.000001 and absf(point-previous)<=1.5/60+0.000001
			previous=point
		check(bounded,"Trips are monotonic, bounded and speed-limited: "+str(endpoints))
		check(Plan.sample(trip,trip["duration"]+1)==endpoints[1] and Plan.sample(trip,-1)==endpoints[0],"Trip endpoints remain exact before/after the journey: "+str(endpoints))
	var data: Dictionary=room(); data["floors"]=[{"uid":"basement","name":"Basement","height":-3,"room":room()},{"uid":"upper","name":"Upper","height":3,"room":room()},{"uid":"top","name":"Top","height":6,"room":room()}]
	var link: Dictionary={"uid":"lift","kind":"elevator","lower":"ground","upper":"top","start":[0,0],"end":[0,0],"width":1.2,"extension":"retain"}; data["floor_links"]=[link]
	check(Plan.stops(data,link).map(func(floor: Dictionary):return floor["uid"])==["ground","upper","top"],"An elevator serves intermediate floors while excluding floors outside its range")
	check(Floors.valid(data),"One range-spanning elevator uses the persistent floor schema")
	var duplicate: Dictionary=link.duplicate(true); duplicate["uid"]="second"; data["floor_links"].append(duplicate)
	check(not Floors.valid(data),"Separate cabins cannot occupy overlapping shafts")
	var library=preload("res://scripts/builder/asset_library.gd").new(); var repair=preload("res://scripts/builder/project_repair.gd").new(library)
	var fixed: Dictionary=repair.world(data,"3d","room",1)
	check(Floors.valid(fixed) and fixed["floor_links"].size()==1 and fixed["floor_links"][0]["extension"]=="retain" and repair.issues.size()==1,"Repair archives the conflicting shaft while preserving the valid elevator and its metadata")
	data["floor_links"][1]["start"]=[4,0]; data["floor_links"][1]["end"]=[4,0]
	check(Floors.valid(data),"Independent adjacent shafts remain supported")
	print("FLOOR ELEVATOR PLAN: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
