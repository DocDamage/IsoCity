extends SceneTree
const Rooms=preload("res://scripts/builder/interiors.gd")
const Plan=preload("res://scripts/builder/prop_plan.gd")
const Grid=preload("res://scripts/builder/grid_fit.gd")
var studio: Control
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+message)
func settle() -> void:
	for frame in 8:await physics_frame
	await process_frame
func point(mode: String,x: float,z: float) -> Array:
	var pixel: Array=Grid.pixel_values([x,z]);return [pixel[0],pixel[1],0] if mode=="2d" else [x,.12,z]
func use_switch(world: Node,uid: String) -> void:
	var context: Dictionary=Plan.context(world.exploration)
	for item in context["data"]["objects"]:
		if item["uid"]!=uid:continue
		var candidate: Dictionary=context.duplicate(false);candidate["item"]=item;candidate["node"]=context["instances"][uid];candidate["profile"]=Plan.profile(item)
		world.player.teleport_to(world.player.get_parent().to_local(Plan.ground_point(candidate,world.exploration,"approach")));world.player.set_physics_process(false)
		check(world.exploration.props.interact(candidate),"Actual local switch operates its copied target");return
	check(false,"Switch object is present in the active room")
func enter(world: Node,uid: String) -> void:
	world.player.teleport_to(world.exploration.entrance(world.instances[uid]));world.player.set_physics_process(false);world.exploration.interact();await settle()
	check(world.exploration.interior!=null and world.exploration.interior_uid==uid,"Normal interaction enters the requested independent owner")
func fixture(mode: String) -> void:
	studio.switch_mode(mode);var doc=preload("res://scripts/builder/document.gd").new();doc.data=preload("res://scripts/builder/templates.gd").make(mode,"blank");studio.documents[mode]=doc
	var host: Dictionary=doc.add("3d:HanX_School/School_Building",[0,0,0],"0");host.erase("catalog_behavior_revision");host["future_option"]={"kept":17};host["audio"]={"kind":"none"};var original_uid: String=host["uid"]
	var room: Dictionary=Rooms.ensure(host,mode,studio.library)
	room["objects"].append({"uid":"device","asset":"2d:Washing_Machine","position":point(mode,3,0),"direction":"SE","scale":1.0,"prop":{"duration":60}})
	room["objects"].append({"uid":"switch","asset":"2d:Floor_Lamp","position":point(mode,3,-2.8),"direction":"SE","scale":1.0,"prop":{"target":"device"}})
	room["floors"]=[{"uid":"upper","name":"Upper","height":3,"room":Rooms.make_for(host,mode,studio.library,"empty")}]
	room["floor_links"]=[{"uid":"stairs","kind":"stairs","lower":"ground","upper":"upper","start":[-3,3],"end":[2,3],"width":1.4}]
	room["floor_entrances"]=[{"uid":"upstairs_entry","floor":"upper","position":[0,0,0]}]
	studio.changed();await settle();var original: Dictionary=doc.object(original_uid).duplicate(true);studio.selected_uids.assign([original_uid]);studio.selected_uid=original_uid;studio.duplicate_selection();await settle()
	var copy: Dictionary=doc.object(studio.selected_uid);var copied_uid: String=copy["uid"];copy["position"]=[600,0,0] if mode=="2d" else [30,0,0];studio.changed();await settle()
	check(copy["future_option"]==original["future_option"] and copy["audio"]==original["audio"] and not copy.has("catalog_behavior_revision"),"Duplication preserves opaque settings and legacy behavior opt-outs")
	check(copy["interior"]["floor_links"][0]["upper"]==copy["interior"]["floors"][0]["uid"] and copy["interior"]["floors"][0]["uid"]!="upper","Copied passages follow renewed floors")
	var copied_device: Dictionary=copy["interior"]["objects"].filter(func(item: Dictionary):return item["asset"]=="2d:Washing_Machine")[0]
	var copied_switch: Dictionary=copy["interior"]["objects"].filter(func(item: Dictionary):return item["asset"]=="2d:Floor_Lamp")[0]
	check(copied_switch["prop"]["target"]==copied_device["uid"] and copied_device["uid"]!="device","Copied switch points to the renewed local device")
	studio.set_walking(true);await settle();var world: Node=studio.worlds[mode];var runtime: Node=world.exploration.props
	await enter(world,original_uid)
	if world.exploration.interior:
		use_switch(world,"switch");check(runtime.states.get("room:"+original_uid+":ground:device",{}).get("on",false),"Original owner's device powers on");world.exploration.leave_interior();await settle()
	await enter(world,copied_uid)
	if world.exploration.interior:
		var key: String="room:"+copied_uid+":ground:"+copied_device["uid"]
		check(not runtime.states.get(key,{}).get("on",false),"Copied device starts with its independent default state")
		use_switch(world,copied_switch["uid"]);check(runtime.states.get(key,{}).get("on",false),"Copied switch powers the copied device")
		use_switch(world,copied_switch["uid"]);check(not runtime.states.get(key,{}).get("on",false) and runtime.states.get("room:"+original_uid+":ground:device",{}).get("on",false),"Copied power changes cannot operate the original owner's device")
		world.exploration.leave_interior();await settle()
	studio.set_walking(false);check(doc.object(original_uid)==original,"Copying and transient operation preserve original authored room bytes")
func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio);await settle()
	for mode in ["2d","3d"]:await fixture(mode)
	studio.free();await process_frame;print("OWNED ROOM COPY: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
