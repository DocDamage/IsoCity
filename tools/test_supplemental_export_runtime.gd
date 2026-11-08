extends SceneTree
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var scene: Node=load("res://city.tscn").instantiate(); root.add_child(scene)
	for frame in 6: await physics_frame
	var library: RefCounted=scene.exploration.library
	check(preload("res://scripts/builder/document.gd").valid(scene.studio_data,scene.dimension,library),"Relocated data validates with packaged catalog subset")
	check(scene.studio_data["objects"].size()==3,"All selected model, atlas and animated character placements survive")
	for item in scene.studio_data["objects"]:
		check(library.assets.has(item["asset"]) and preload("res://scripts/builder/repair_assets.gd").available(item["asset"],library,{}),"Every prepared scene and animation dependency loads without source workspace")
		var info: Dictionary=library.assets[item["asset"]]["data"]
		check(not info.get("source_pack","").is_empty(),"Source attribution remains available")
		if info.get("kind")=="char":
			var actor: Node=load(library.assets[item["asset"]]["path"]).instantiate(); root.add_child(actor)
			actor.action="walk"; actor._apply_direction(); actor._update_animation(.5); actor._update_frame()
			check(actor.get_node("Sprite2D").texture is AtlasTexture,"Relocated character resolves walking atlas frames")
			actor.free()
	var models: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/catalog/supplemental_registry.json"))
	check(models["models"].size()==1,"Portable registry contains only the selected supplemental model")
	scene.free(); await process_frame; await process_frame
	print("Supplemental relocated runtime: %d checks, %d failures"%[checks,failures]); quit(1 if failures else 0)
