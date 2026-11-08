extends SceneTree
const SHIP = "2d:Reviewed_sailing_ship_turntable"
const FLAG = "2d:Reviewed_rodwan_flag_0"
const TILE = "2d:Reviewed_village_floor_3_v1_0_1"
const LEGACY = "2d:Added_ship_Ship_sprPlayer_strip16_56b1db61"
var checks: int = 0
var failures: int = 0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1;print("FAIL: "+message)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var scene: Node=load("res://city.tscn").instantiate();root.add_child(scene)
	for frame in 8:await physics_frame
	var library: RefCounted=scene.exploration.library
	check(scene.studio_data["objects"].size()==5 and library.assets.keys().filter(func(id: String):return id.begins_with("2d:Reviewed_")).size()==4,"Fresh package retains the five placed assets without unrelated reviewed content; standard room dependencies remain allowed")
	check(not FileAccess.file_exists("res://resources/catalog/reviewed_registry.json"),"Full reviewed catalog is not an implicit export dependency")
	check(preload("res://scripts/builder/document.gd").valid(scene.studio_data,scene.dimension,library),"Original and reviewed IDs validate independently")
	check(library.assets[LEGACY]["data"]["content_kind"]=="atlas" and library.assets[LEGACY]["data"]["directions"]["SE"]["frame_width"]==512,"Legacy classification and artwork dimensions survive export")
	check(library.directions(SHIP).size()==16 and library.assets[SHIP]["data"]["animation_status"]=="directional_sprite","All supplied ship angles are packaged without inventing animation")
	var ship: Node
	var flag: Node
	for item in scene.studio_data["objects"]:
		var instance: Node=scene.exploration.instances[item["uid"]]
		if item["asset"]==SHIP:ship=instance if scene.dimension=="2d" else instance.source
		if item["asset"]==FLAG:flag=instance if scene.dimension=="2d" else instance.source
	ship.direction="View_16"
	check(ship.get_node("Sprite2D").texture.get_width()==64 and ship.origin_offset==Vector2(32,31),"Relocated ship uses its last supplied view and fixed pivot")
	flag.set_process(false);flag._anim_timer=0;flag._anim_frame_idx=0;flag.get_node("Sprite2D").frame=0;flag._process(.11)
	check(flag.total_frames==8 and flag.animation_fps==10 and flag.get_node("Sprite2D").frame==1,"Relocated flag uses its actual source timing")
	var image: Image=flag.get_node("Sprite2D").texture.get_image()
	if image.is_compressed():image.decompress()
	check(image.get_pixel(0,0).a==0,"Approved flag background remains transparent after a fresh import")
	var origin: Array=library.assets[TILE]["data"]["directions"]["SE"]["origin"]
	check(library.is_ground_tile(TILE) and origin[0]==32 and origin[1]==0,"Flat tile retains its source phase and calibrated ground anchor")
	scene.free();await process_frame;await process_frame
	print("REVIEWED PORTABLE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
