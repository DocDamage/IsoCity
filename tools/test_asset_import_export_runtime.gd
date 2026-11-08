extends SceneTree
const Custom=preload("res://scripts/builder/custom_assets.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var path: String="res://city.tscn"
	for mode in ["2d","3d"]:
		if "--"+mode in OS.get_cmdline_user_args(): path="res://output/custom_import_"+mode+".tscn"; Custom.registry_override="res://output/custom_asset_test_registry.json"
	var scene: Node=load(path).instantiate(); root.add_child(scene)
	for frame in 6: await physics_frame
	var library: RefCounted=scene.exploration.library; var imported: Array=scene.studio_data["objects"].filter(func(item: Dictionary):return item["asset"].contains(":Custom/"))
	check(imported.size()==2,"Export retains both imported placements")
	for item in imported:
		var asset: Dictionary=library.assets[item["asset"]]; check(asset["behavior"]["building"] and asset["data"]["author"]=="IsoCity fixture author","Custom behavior and attribution survive fresh export")
		check(library.icon(item["asset"])!=null,"Generated thumbnail loads without original source files")
		check(preload("res://scripts/builder/repair_assets.gd").available(item["asset"],library,{}),"Prepared scene and all texture dependencies are available")
		var instance: Node=scene.city_instances[item["uid"]]
		if item["asset"].begins_with("2d:"):
			if scene.dimension=="2d": check(instance.origin_offset==Vector2(24,68) and instance.footprint==Vector2i(4,8),"Native sprite preserves authored pivot and footprint")
			else: check(instance.source.origin_offset==Vector2(24,68) and instance.collision.shape.size==Vector3(4,5,8),"Mixed sprite preserves source pivot and authored collision")
		else:
			if scene.dimension=="2d": check(instance.footprint==Vector2i(8,4),"Mixed model preserves its rotated authored footprint")
			else: check(instance.get_node("FootprintCollision").get_child(0).shape.size==Vector3(4,5,8),"Native model retains prepared authored collision")
	check(preload("res://scripts/builder/document.gd").valid(scene.studio_data,scene.dimension,library),"Exported data validates with only packaged catalog dependencies")
	if "--capture" in OS.get_cmdline_user_args():
		RenderingServer.force_draw(false); RenderingServer.force_draw(false); root.get_texture().get_image().save_png("res://output/custom_import_export_"+scene.dimension+".png")
	scene.free(); await process_frame; print("Asset import export: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
