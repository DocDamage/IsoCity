extends SceneTree
const Caps=preload("res://scripts/builder/asset_capabilities.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;print("FAIL: "+message)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var library: RefCounted=preload("res://scripts/builder/asset_library.gd").new()
	var found: Dictionary={}
	for id in library.assets:
		for key in library.capabilities.potential(id):found[key]=true
	for key in Caps.KEYS:check(found.has(key),"Independent library retains verified potential: "+key)
	var item: Dictionary={"asset":"3d:HanX_Shop/Shop_Cafe","uid":"portable",Caps.Defaults.FIELD:1}
	var data: Dictionary=preload("res://scripts/builder/templates.gd").make("2d","blank")
	check(Caps.dependency_reason(item,library).is_empty(),"Prepared scene and required artwork open independently")
	check(library.capabilities.potential(item["asset"]).has("Business"),"Reviewed new-placement potential survives subset export")
	item["business"]={"kind":"none"}
	var report: Dictionary=library.capabilities.selected(item,library,data)
	check(report["potential"].has("Business") and report["inactive"].has("Business") and report["badges"].all(func(entry: Dictionary):return entry["label"]!="Business"),"Saved overrides remain separate from catalog potential")
	item={"asset":"2d:Hatchback_Yellow","uid":"custom","prop":{"kind":"appliance"}}
	check(Caps.profiles(item,library).has("Use"),"Custom supported interaction still works without full authoring catalog")
	check(not Caps.Citizens.settings(data)["enabled"] and not Caps.Services.settings(data)["enabled"],"Portable inspection never enables simulations")
	print("ASSET CAPABILITIES PORTABLE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
