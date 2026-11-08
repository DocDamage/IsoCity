extends SceneTree

const Plan = preload("res://scripts/builder/connector_plan.gd")
const Blueprint = preload("res://scripts/builder/blueprint_plan.gd")
const Doc = preload("res://scripts/builder/document.gd")
var checks: int=0
var failures: int=0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks+=1
	if not value:
		failures+=1
		print("FAIL: "+message)

func normalized(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value))

func run() -> void:
	var scene: Node=load("res://city.tscn").instantiate()
	root.add_child(scene)
	for frame in 8: await physics_frame
	var source: Dictionary=scene.studio_data
	var mode: String=source["mode"]
	var library: RefCounted=scene.exploration.library
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://expected_sockets.json"))
	check(Doc.valid(source,mode,library),"Independently imported source validates in its original dimension.")
	check(scene.city_instances.size()==source["objects"].size(),"The native scene contains exactly the built objects.")
	var result: Dictionary=source
	var plans: Array=source.get("blueprints",[])
	if not plans.is_empty():
		var pending: Dictionary=source.duplicate(true)
		var proposal: Dictionary=Blueprint.construct(source,[plans[0]["uid"]],library)
		check(proposal["ok"] and pending==source,"The relocated proposal resolves required links without mutating the city.")
		if proposal["ok"]:
			result=proposal["data"]
			result["economy_account"]=proposal["quote"]["account"]
	var links: Array=result.get("connections",[])
	check(not links.is_empty() and Plan.retained(result,links)==links,"The complete endpoint graph validates using the exported catalog.")
	check(normalized(result)==expected,"The relocated result preserves the exact city, link IDs and account.")
	var used: Dictionary={}
	for item in result["objects"]:
		used[item["asset"]]=true
	for asset_id in used:
		check(library.assets.has(asset_id),"A referenced module is in the relocated library: "+asset_id)
		if not library.assets.has(asset_id): continue
		var asset: Dictionary=library.assets[asset_id]
		var preview: String=asset["data"].get("preview_path","res://resources/previews_3d/"+asset_id.trim_prefix("3d:")+".png")
		check(ResourceLoader.exists(asset["path"]) and ResourceLoader.exists(preview),"The module scene and preview resolve independently: "+asset_id)
	scene.free()
	await process_frame
	print("PORTABLE MODULAR SOCKETS: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
