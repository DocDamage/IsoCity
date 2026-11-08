extends SceneTree
const Plan=preload("res://scripts/builder/asset_recents.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var tasks: Dictionary={"classroom":{},"garage":{}};var history=Plan.new()
	for raw in [null,true,[],{}, {"version":false,"histories":{}},{"version":1.5,"histories":{}},{"version":NAN,"histories":{}},{"version":INF,"histories":{}},{"version":1,"histories":[]},{"version":1,"histories":{"classroom":false}}]:
		history.restore(raw,tasks);check(history.histories.is_empty(),"Malformed recent preferences fall back to an empty local history")
	history.restore({"version":1,"histories":{"unknown":["2d:A"],"classroom":[false,2,[],"","res://private", "2d:Bad\nID","2d:"+"x".repeat(513),"3d:Valid","3d:Valid","2d:Custom/Private"]}},tasks)
	check(history.ids("classroom")==["3d:Valid","2d:Custom/Private"] and not history.histories.has("unknown"),"Only bounded concrete IDs and known task names are restored")
	for index in 100:history.remember("2d:Asset_"+str(index),"classroom",tasks)
	check(history.ids("classroom").size()==24 and history.ids("").size()==24 and history.ids("classroom")[0]=="2d:Asset_99" and history.ids("classroom")[-1]=="2d:Asset_76","Each activity and the global fallback is capped at 24, newest first")
	check(not history.remember("2d:Asset_99","classroom",tasks),"Repeating the current first ID avoids redundant preference writes")
	history.remember("2d:Asset_80","classroom",tasks);check(history.ids("classroom")[0]=="2d:Asset_80" and history.ids("classroom").count("2d:Asset_80")==1,"Reusing an older asset moves one identity to the front")
	history.remember("3d:Garage","garage",tasks);check(history.ids("garage")==["3d:Garage"] and not "3d:Garage" in history.ids("classroom"),"Different activities retain independent histories")
	var state: Dictionary=history.state();state["histories"]["garage"].clear();check(history.ids("garage")==["3d:Garage"],"Serialized preference copies do not expose mutable internal lists")
	var library: RefCounted=preload("res://scripts/builder/asset_library.gd").new();var id: String="3d:HanX_School/Student_Chair"
	history.restore({"version":1,"histories":{"classroom":["2d:Removed/Private",id]}},tasks)
	check(history.available("classroom",library)==[id] and history.ids("classroom").size()==2,"Removed/private asset identities remain local but never create broken cards")
	library.assets[id]["unavailable"]=true;check(history.available("classroom",library).is_empty(),"Unavailable prepared sources are excluded from available recents")
	library.assets[id]["unavailable"]=false;check(history.available("classroom",library)==[id],"Restoring the current catalog makes retained recent IDs usable again")
	var reopened=Plan.new();reopened.restore(JSON.parse_string(JSON.stringify(history.state())),tasks);check(reopened.state()==history.state(),"Local IDs round-trip without project paths, descriptors or runtime state")
	print("ASSET RECENTS: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
