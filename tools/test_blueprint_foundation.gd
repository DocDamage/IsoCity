extends SceneTree
const Plan=preload("res://scripts/builder/blueprint_plan.gd")
const Doc=preload("res://scripts/builder/document.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var library: RefCounted=preload("res://scripts/builder/asset_library.gd").new()
	var road: Dictionary={"uid":"r","kind":"road","start":[0,0],"end":[2,0],"settings":{"width":6,"sidewalks":true,"style":"gravel"}}
	for mode in ["2d","3d"]:
		check(Plan.valid([],mode,library) and Plan.valid([road],mode,library),"Optional and populated planning collections are valid: "+mode)
		for malformed in [null,{},"plans",[null],[{}],[road,road]]:
			check(not Plan.valid(malformed,mode,library),"Malformed proposal collection is rejected: "+mode)
		for key in ["start","end"]:
			for malformed in [null,[],[0],[0,1,2],[NAN,0],[INF,0],[true,0],[.5,0],[10001,0]]:
				var candidate: Dictionary=road.duplicate(true); candidate[key]=malformed; check(not Plan.valid([candidate],mode,library),"Malformed road coordinate rejected: "+mode+key)
		for malformed in [{"width":3},{"style":"lava"},{"sidewalks":"yes"}]:
			var candidate: Dictionary=road.duplicate(true); candidate["settings"]=malformed; check(not Plan.valid([candidate],mode,library),"Invalid road profile is rejected: "+mode)
		var doc: RefCounted=Doc.new(); doc.data=preload("res://scripts/builder/templates.gd").make(mode,"blank"); doc.economy_library=library
		doc.data["economy"]={"enabled":true,"starting_cash":100000,"refund_percent":25,"period_seconds":60}
		var before: Dictionary=doc.data.duplicate(true); doc.data["blueprints"]=[road.duplicate(true)]; doc.record_completed_change(before)
		check(doc.data["economy_account"]["construction_total"]==0,"Sketching costs no construction budget: "+mode)
		before=doc.data.duplicate(true); var result: Dictionary=Plan.construct(doc.data,["r"],library); doc.data=result["data"]; check(doc.record_completed_change(before),"Funded construction commits: "+mode)
		check(doc.data["economy_account"]["construction_total"]>0,"Roads are charged only on commit: "+mode)
		check(doc.data["roads"].all(func(value: Dictionary): return value["width"]==6 and value["sidewalks"] and value["style"]=="gravel"),"Constructed road retains its exact profile: "+mode)
		doc.undo(); check(doc.data==before,"Undo restores funds and proposals together: "+mode)
		var malformed_doc: Dictionary=doc.data.duplicate(true); malformed_doc["blueprints"].append(null)
		var repair=preload("res://scripts/builder/project_repair.gd").new(library); var fixed: Dictionary=repair.world(malformed_doc,mode,"city",0)
		check(fixed["blueprints"]==[road] and not repair.issues.is_empty() and Doc.valid(fixed,mode,library),"Repair retains valid plans with an explicit damage report: "+mode)
		var full: Dictionary=doc.data.duplicate(true); full["roads"]=[]
		for i in 4096: full["roads"].append({"cell":[i,200],"crossing":false})
		result=Plan.construct(full,["r"],library); check(not result["ok"] and full["blueprints"].size()==1 and full["roads"].size()==4096,"Road capacity failure is atomic and leaves the source untouched: "+mode)
	print("Blueprint foundation: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
