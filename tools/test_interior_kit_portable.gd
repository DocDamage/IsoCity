extends SceneTree
const Fit=preload("res://scripts/builder/grid_fit.gd")
const Floors=preload("res://scripts/builder/floor_plan.gd")
const Props=preload("res://scripts/builder/prop_plan.gd")
var checks: int=0
var failures: int=0
var scene: Node
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func same(a: Variant,b: Variant) -> bool:
	if (a is float or a is int) and (b is float or b is int):return absf(float(a)-float(b))<=1e-8*maxf(1,absf(float(a)))
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for key in a:
			if not b.has(key) or not same(a[key],b[key]):return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for index in a.size():
			if not same(a[index],b[index]):return false
		return true
	return a==b
func settle() -> void:
	for frame in 12:await physics_frame
	await process_frame
func capture(name: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args():return
	if scene.dimension=="2d":scene.camera.position=Vector2(0,-35);scene.camera.zoom=Vector2(2,2)
	else:
		scene.camera.projection=Camera3D.PROJECTION_ORTHOGONAL;scene.camera.size=15
		var height: float=0 if scene.exploration.interior==null else float(scene.exploration.interior.floor_stack.heights[scene.exploration.active_floor()])
		scene.camera.global_position=Vector3(9,height+10,12);scene.camera.look_at(Vector3(0,height,0))
	scene.set_process(false);await settle();await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://rendered_"+name+".png")==OK,"Independent applied layout renders: "+name)
	scene.set_process(true)
func check_room(room: Dictionary,instances: Dictionary,library: RefCounted) -> void:
	for item in room["objects"]:
		check(not item["uid"].begins_with("preview_") and instances.has(item["uid"]),"Real saved furnishing identity instantiates: "+item["asset"])
		if item["asset"].begins_with("3d:HanX_") or item["asset"] in preload("res://scripts/builder/interior_kits.gd").definitions()["kits"]["apartment"]["objects"].map(func(record: Dictionary):return record["asset"]):
			check(library.icon(item["asset"])!=null and preload("res://scripts/builder/model_preview.gd").meaningful(library.icon(item["asset"])),"Included furnishing preview has artwork: "+item["asset"])
func ride(lift: Node,destination: String) -> void:
	scene.exploration.interact();check(lift.menu.visible,"Actual interaction opens independent elevator choices")
	var chosen: bool=false
	for button in lift.choices.get_children():
		if button is Button and button.get_meta("floor_uid","")==destination:button.pressed.emit();chosen=true;break
	check(chosen,"Actual independent destination button is available")
	for frame in 4000:
		await physics_frame
		if lift.phase in ["idle","blocked"]:break
	await process_frame
	check(lift.phase=="idle" and lift.last_stop==destination and scene.exploration.active_floor()==destination and scene.player.is_physics_processing(),"Independent elevator safely delivers the player to "+destination+" ("+lift.phase+" · "+lift.notice+")")
	check(scene.player.recovery_count==0,"Independent applied-floor trip never invokes stuck-player recovery")
func run() -> void:
	scene=load("res://city.tscn").instantiate();scene.photo_storage_enabled=false;root.add_child(scene);await settle();scene.player.set_physics_process(false)
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://expected.json"));var library: RefCounted=scene.exploration.library
	check(same(scene.studio_data,expected),"Relocation preserves every saved layout/settings/account source value")
	for key in ["traffic","citizens","services","economy","weather","businesses","scenario","zoning","transit"]:
		check(same(scene.studio_data.get(key,{}),expected.get(key,{})),"Relocation retains the intentional enabled/disabled setting: "+key)
	var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://city-source.json"))
	check(same(source["documents"][scene.dimension],expected),"Portable source reopens with the exact owning room/account/floor records")
	if expected.get("template")=="room":
		check_room(expected,scene.city_instances,library);await capture("standalone")
	else:
		var host: Dictionary=expected["objects"][0];var exploration: Node=scene.exploration;var player: Node=scene.player
		var parent: Node=player.get_parent();var entrance: Variant=exploration.entrance(exploration.instances[host["uid"]]);player.teleport_to(entrance)
		var event:=InputEventKey.new();event.keycode=KEY_E;event.pressed=true;scene._unhandled_input(event);await settle();player.set_physics_process(false)
		check(exploration.interior!=null and exploration.active_floor()=="ground","Actual independent input enters the applied shop ground floor")
		if exploration.interior:
			check_room(Floors.room(host["interior"],"ground"),Props.context(exploration)["instances"],library);await capture("ground")
			var lift: Node=exploration.interior.floor_stack.lifts["kit_delivery_lift"];var upper: String=host["interior"]["floors"][0]["uid"]
			# Stage at the cabin center, then use the actual collision occupancy,
			# interaction menu, runtime movement and arrival-clearance checks.
			var center:=Vector2(lift.link["start"][0],lift.link["start"][1])
			player.teleport_to(Fit.pixels(center) if scene.dimension=="2d" else Vector3(center.x,.03,center.y));await settle()
			check(lift.view.fully_inside(),"Saved connection has a clear independent cabin")
			player.set_physics_process(true);await ride(lift,upper);player.set_physics_process(false)
			check_room(Floors.room(host["interior"],upper),Props.context(exploration)["instances"],library);await capture("upper")
			check(Floors.room(host["interior"],upper)["starter_kit"]["id"]=="apartment","Independent upper floor retains its explicitly applied apartment")
			player.set_physics_process(true);await ride(lift,"ground");player.teleport_to(exploration.exit_position);exploration.interact()
			check(exploration.interior==null and player.get_parent()==parent and player.position.distance_to(entrance)<.01,"Ordinary exit restores independent exterior position and actor ownership")
	check(same(scene.studio_data,expected),"Independent visits and elevator round trip preserve authored data and accounting")
	scene.free();await process_frame;await process_frame;print("INTERIOR KIT PORTABLE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
