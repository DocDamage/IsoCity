extends SceneTree
var checks: int=0
var failures: int=0
var scene: Node
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func settle() -> void:
	for frame in 16:await process_frame
	await physics_frame
func normalized(value: Dictionary) -> Dictionary:return JSON.parse_string(JSON.stringify(value))
func layout(value: Dictionary) -> Dictionary:
	var result: Dictionary=value.duplicate(true)
	for item in result.get("objects",[]):item.erase("uid")
	return normalized(result)
func capture(name: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args():return
	await RenderingServer.frame_post_draw;check(root.get_texture().get_image().save_png("res://"+name+".png")==OK,"Retained independent runtime artwork: "+name)
func run() -> void:
	root.size=Vector2i(1480,900);var expectation: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://palette_expectation.json"));scene=load("res://city.tscn").instantiate();root.add_child(scene);await settle();var mode: String=scene.dimension;var ex: Node=scene.exploration;var library: RefCounted=ex.library
	check(normalized(scene.studio_data)==expectation["world"] and normalized(scene.project_palette)==expectation["policy"],"Relocated scene retains exact authored values and common policy")
	check(normalized(library.project_palette)==expectation["policy"] and library.project_palette.get("restricted",false),"Fresh runtime applies the explicit restriction before use")
	check(not library.assets.has(expectation["private_id"]) and library.project_palette_ids.has(expectation["private_id"]),"Private recommendation is identifiable without becoming an installed asset")
	check(library.project_palette["collection"]["entries"].any(func(entry: Dictionary):return entry.get("id")=="2d:Uninstalled_Palette_Shelf" and entry.get("name")=="Remembered shelf on another computer"),"Missing peer reference keeps its original identity and name")
	check(not preload("res://scripts/builder/zone_plan.gd").settings(scene.live_data)["enabled"] and not preload("res://scripts/builder/citizen_plan.gd").settings(scene.live_data)["enabled"] and not preload("res://scripts/builder/economy_plan.gd").settings(scene.live_data)["enabled"],"Export keeps ordinary disabled simulation defaults")
	check(library.assets.has(expectation["chair"]) and library.icon(expectation["chair"])!=null,"Actual authored furnishing keeps its usable preview dependency")
	check(not FileAccess.file_exists("res://scripts/builder/collection_tools.gd") and not FileAccess.file_exists("res://scripts/builder/asset_collection_store.gd"),"Independent package excludes personal-list persistence and editor management")
	scene.player.set_physics_process(false);var owned: String=expectation["owned_uid"];var fresh: String=expectation["fresh_uid"];scene.player.teleport_to(ex.entrance(ex.instances[owned]));ex.interact();await settle()
	check(ex.interior!=null and ex.interior_uid==owned,"Actual runtime interaction enters the saved owned room")
	if ex.interior:
		check(ex.interior.instances.has("kept_palette_furnishing") and ex.interior.data_state["objects"].any(func(item: Dictionary):return item["uid"]=="kept_palette_furnishing" and item.get("name")=="Exact palette furnishing"),"Saved exact furnishing renders independently of the editor")
		await capture("saved_palette_room_"+mode);ex.leave_interior();await settle()
	check(ex.interior==null and scene.get_node("Objects").visible,"Saved-room exit restores the exterior normally")
	var record: Dictionary={}
	for item in scene.live_data["objects"]:
		if item["uid"]==fresh:record=item
	check(not record.has("interior"),"Unvisited source building remains lazy before actual runtime entry")
	scene.player.teleport_to(ex.entrance(ex.instances[fresh]));ex.interact();await settle();check(ex.interior!=null and ex.interior_uid==fresh,"Actual runtime interaction creates a fully permitted lazy room")
	if ex.interior:
		check(layout(record["interior"])==layout(expectation["future_layout"]),"Lazy room retains supplied layout and fresh ordinary identities")
		check(preload("res://scripts/builder/document.gd").valid(record["interior"],mode,library),"All permitted lazy room dependencies are installed in the relocated package")
		await capture("lazy_palette_room_"+mode);ex.leave_interior();await settle()
	var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://city-source.json"));check(source["documents"][mode]==expectation["world"] and source["project_palette"]==expectation["policy"],"Runtime visits leave the exported source file unchanged")
	scene.free();await process_frame;await process_frame;print("COLLECTION EXPORT RUNTIME: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
