extends SceneTree
const Plan=preload("res://scripts/builder/asset_import_plan.gd")
const Custom=preload("res://scripts/builder/custom_assets.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	check(Plan.valid(Plan.defaults()),"Default import settings are valid")
	for malformed in [null,[],true,1,"source"]: check(not Plan.valid(malformed),"Reject malformed settings")
	for key in ["anchor","footprint","contact"]:
		for malformed in [null,[],"zero",[NAN,NAN,NAN],[INF,0],[true,false],[100001,0]]:
			var value: Dictionary=Plan.defaults(); value[key]=malformed; check(not Plan.valid(value),"Reject malformed geometry: "+key)
	for key in ["height","model_scale"]:
		for malformed in [null,"1",true,0,-1,NAN,INF,100001]:
			var value: Dictionary=Plan.defaults(); value[key]=malformed; check(not Plan.valid(value),"Reject malformed scale/height: "+key)
	for key in ["name","author","license","source_url"]:
		var value: Dictionary=Plan.defaults(); value[key]=[]; check(not Plan.valid(value),"Metadata must be text: "+key)
	var blank: Dictionary=Plan.defaults(); blank["name"]="   "; check(not Plan.valid(blank),"Asset name cannot be blank")
	for foot in [[0,1],[1,.5],[65,1],[-1,1]]:
		var value: Dictionary=Plan.defaults(); value["footprint"]=foot; check(not Plan.valid(value),"Footprint is a bounded integer ground area")
	var path: String=ProjectSettings.globalize_path("user://invalid-import.png"); var file:=FileAccess.open(path,FileAccess.WRITE); file.store_string("broken image"); file.close()
	check(not Plan.inspect(path)["ok"],"Damaged source returns a readable failure without loader errors")
	check(not Plan.inspect(path+".missing")["ok"],"Missing source is rejected")
	check(not Custom.descriptor_valid("2d:Custom/escape",{"id":"2d:Custom/escape","mode":"2d","name":"x","category":"Decorations","path":"res://assets/custom_assets/../escape.tscn","data":{},"behavior":{}}),"Custom catalog paths cannot escape their asset folder")
	Custom.registry_override="res://output/damaged_custom_registry.json"; file=FileAccess.open(Custom.registry_path(),FileAccess.WRITE); file.store_string("{broken"); file.close(); check(not Custom.read_registry()["ok"],"A damaged catalog is reported rather than replaced")
	Custom.registry_override=""; print("Asset import foundation: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
