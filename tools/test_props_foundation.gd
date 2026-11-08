extends SceneTree
const Plan=preload("res://scripts/builder/prop_plan.gd")
var checks: int=0
var failures: int=0
var studio: Control
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for frame in 5: await physics_frame
	await process_frame
func schema() -> void:
	check(Plan.valid({}) and Plan.profile({"asset":"2d:Park_Bench"})["kind"]=="seat","Explicit automatic bench profile and empty override validate")
	for id in Plan.definitions()["assets"]: check(studio.library.assets.has(id),"Authored prop asset exists: "+id)
	for kind in Plan.KINDS: check(Plan.valid({"kind":kind}),"Authored interaction kind validates: "+kind)
	for raw in [null,[],"seat",{"kind":"building"},{"enabled":1},{"initial_on":0},{"duration":0},{"duration":61},{"reach":INF},{"reach":NAN},{"reach":7},{"point":[1,2]},{"point":[0,0,INF]},{"target":12},{"label":[]}]: check(not Plan.valid(raw),"Malformed interaction rejected: "+str(raw))
	check(Plan.profile({"asset":"2d:Park_Bench","prop":{"kind":"none"}}).is_empty() and Plan.profile({"asset":"2d:Park_Bench","missing_asset":{}}).is_empty(),"Explicitly disabled or missing props do not interact")
	check(Plan.profile({"asset":"2d:Coffee_Shop"}).is_empty(),"Unclassified buildings do not acquire prop behavior from names")
	check(Plan.profile({"asset":"2d:Park_Bench","prop":{"kind":"switch","label":"Wall switch","target":"lamp"}})["label"]=="Wall switch","Any placed object can have an explicitly authored switch profile")
	var custom: Dictionary={"asset":"2d:Swing_Set","direction":"SE","prop":{"point":[0,2,0]}}
	check(Plan.source(Plan.profile(custom),custom,studio.library,"point").is_equal_approx(Vector3(.5,2,1.5)),"Explicit object anchors take precedence over calibrated source-view defaults")
	check(Plan.power_device({"uid":"lamp","asset":"2d:Floor_Lamp","prop":{"target":"lamp"}}) and not Plan.power_device({"uid":"button","asset":"2d:Floor_Lamp","prop":{"target":"lamp"}}),"Self targets remain devices while linked controllers are not relay targets")
	for mode in ["2d","3d"]:
		var data: Dictionary=preload("res://scripts/builder/templates.gd").make(mode,"blank"); var id: String="2d:Park_Bench" if mode=="2d" else "3d:HanX_Park/Bench_Park"
		data["objects"]=[{"uid":"bench","asset":id,"position":[0,0,0],"direction":studio.library.directions(id)[0],"scale":1.0,"prop":{"kind":"seat","reach":2,"point":[0,.6,0]}}]
		check(preload("res://scripts/builder/document.gd").valid(data,mode,studio.library),"Saved per-object interaction is validated: "+mode)
		data["objects"][0]["prop"]={"kind":"seat","duration":-4,"target":"kept","future_setting":21}
		var fixer=preload("res://scripts/builder/project_repair.gd").new(studio.library); var fixed: Dictionary=fixer.world(data,mode,"city",0)
		check(preload("res://scripts/builder/document.gd").valid(fixed,mode,studio.library) and not fixed["objects"][0]["prop"]["enabled"] and fixed["objects"][0]["prop"]["target"]=="kept" and fixed["objects"][0]["prop"]["future_setting"]==21,"Repair safely disables malformed controls while preserving valid object settings: "+mode)
		check(not fixer.issues.is_empty() and fixer.issues[0].has("original"),"Repair retains original prop controls: "+mode)
func candidate(item: Dictionary,world: Node) -> Dictionary:
	var context: Dictionary=Plan.context(world.exploration); context["item"]=item; context["node"]=world.instances[item["uid"]]; context["profile"]=Plan.profile(item); return context
func approach(item: Dictionary,world: Node) -> void:
	var point: Variant=Plan.anchor(world.instances[item["uid"]],item,studio.library,studio.mode,Plan.profile(item),"approach")
	world.player.teleport_to(point); world.player.set_physics_process(false)
func tick(runtime: Node,seconds: float) -> void:
	for frame in ceili(seconds*60): runtime._physics_process(1.0/60)
func capture(mode: String,stage: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	if mode=="2d": studio.worlds[mode].camera.zoom=Vector2(3,3)
	for frame in 5: await process_frame
	RenderingServer.force_draw(false); RenderingServer.force_draw(false); root.get_texture().get_image().save_png("res://output/props_"+mode+"_"+stage+".png")
func fixture(mode: String) -> void:
	studio.switch_mode(mode); var doc=preload("res://scripts/builder/document.gd").new(); doc.data=preload("res://scripts/builder/templates.gd").make(mode,"blank"); studio.documents[mode]=doc
	var assets: Array=["2d:Park_Bench","2d:Swing_Set","2d:Playground_Slide","2d:Floor_Lamp","2d:Washing_Machine","3d:HanX_Park/Bench_Park","3d:HanX_Shop/Vending_Machine","3d:HanX_School/Swing_Set","3d:HanX_School/Slide"] if mode=="2d" else ["3d:HanX_Park/Bench_Park","3d:HanX_School/Swing_Set","3d:HanX_School/Slide","3d:HanX_Park/Lamp_Park","3d:HanX_Shop/Vending_Machine","2d:Park_Bench","2d:Washing_Machine","2d:Swing_Set","2d:Playground_Slide"]
	for index in assets.size():
		var x: float=-24+(index%4)*16; var z: float=-12+floori(index/4.0)*24
		var item: Dictionary=doc.add(assets[index],[x*16,z*8,0] if mode=="2d" else [x,0,z],studio.library.directions(assets[index])[0]); item["uid"]="prop_"+str(index)
	studio.changed(); await settle(); studio.set_walking(true); var world: Node=studio.worlds[mode]; world.player.set_physics_process(false); var exploration: Node=world.exploration; var runtime: Node=exploration.props
	var before: Dictionary=doc.data.duplicate(true); var history: int=doc.undo_history.size()
	for index in [0,5]:
		var item: Dictionary=doc.data["objects"][index]; approach(item,world); var found: Dictionary=Plan.nearby(exploration)
		check(found.get("item",{}).get("uid")==item["uid"] and exploration.prompt().contains("Sit"),"Real transformed bench approach exposes normal exploration prompt: "+mode+"/"+item["asset"])
		exploration.interact(); check(not runtime.active.is_empty() and not world.player.is_physics_processing() and world.player.collision_layer==0,"Seating locks only the transient player controller and collision: "+mode+"/"+item["asset"])
		var point: Variant=Plan.global_point(candidate(item,world),exploration)
		if mode=="2d":
			var sprite: Sprite2D=world.player.get_node("Sprite2D"); var feet: Vector2=sprite.to_global(sprite.offset+world.player.origin_offset)
			check(world.player.action=="sit" and sprite.frame==6 and feet.distance_to(point+Vector2(0,.85*8))<.01,"Actual seated sprite aligns to its authored seat: "+item["asset"])
		else: check((world.player.body.global_position+Vector3.UP*.85).distance_to(point)<.01 and world.player.limbs[2].rotation.x>.8,"Actual 3D body and seated leg pose align to seat: "+item["asset"])
		await capture(mode,"seat_"+str(index))
		exploration.interact(); check(runtime.active.is_empty() and world.player.collision_mask==(1 if mode=="2d" else 3),"Normal interaction releases seat at a clear standing position: "+mode+"/"+item["asset"])
	var swing: Dictionary=doc.data["objects"][1]; approach(swing,world); exploration.interact(); var start: Variant=world.player.interaction_visual_offset if mode=="2d" else world.player.body.global_position
	var original_meshes: Array=runtime.swing.meshes.duplicate(); var original_sprite: Sprite2D=runtime.swing.sprite; var original_texture: Texture2D=runtime.swing.original_texture
	check((not original_meshes.is_empty() and original_meshes.all(func(value: Dictionary)->bool:return value["removed"]>0)) if mode=="3d" else (runtime.swing.masked_texture!=null and original_sprite.texture==runtime.swing.masked_texture),"Active swing replaces only its static seat/ropes while retaining the frame: "+mode)
	tick(runtime,.5); check(not runtime.active.is_empty() and (world.player.interaction_visual_offset if mode=="2d" else world.player.body.global_position)!=start,"Using playground swing animates the actual rider: "+mode)
	await capture(mode,"swing")
	exploration.interact(); check(runtime.active.is_empty(),"Swing can be stopped through normal interaction: "+mode)
	check(original_meshes.all(func(value: Dictionary)->bool:return value["node"].get_ref().mesh==value["original"]) if mode=="3d" else original_sprite.texture==original_texture,"Stopping a swing restores its exact original meshes / sprite texture: "+mode)
	exploration.interact(); tick(runtime,.25); check(not runtime.active.is_empty() and (runtime.swing.ropes.all(func(rope: MeshInstance3D)->bool:return is_instance_valid(rope)) if mode=="3d" else is_instance_valid(runtime.swing.canvas)),"Repeated swing rides allocate valid fresh rig parts: "+mode); exploration.interact()
	var slide: Dictionary=doc.data["objects"][2]; approach(slide,world); exploration.interact(); tick(runtime,Plan.profile(slide)["duration"]*.4); await capture(mode,"slide"); tick(runtime,Plan.profile(slide)["duration"]+1)
	check(runtime.active.is_empty(),"A slide ride completes and returns normal player control: "+mode)
	var lamp: Dictionary=doc.data["objects"][3]; approach(lamp,world); exploration.interact(); var lamp_key: String="city:"+lamp["uid"]
	check(runtime.states[lamp_key]["on"] and runtime.effects.entries[lamp_key]["light"].visible,"Switch operates a real localized light: "+mode)
	await capture(mode,"switch")
	exploration.interact(); check(not runtime.states[lamp_key]["on"] and not runtime.effects.entries[lamp_key]["light"].visible,"Switch turns its actual light off: "+mode)
	lamp["prop"]={"target":lamp["uid"]}; exploration.interact(); check(runtime.effects.entries[lamp_key]["light"].visible,"An explicit self-target still operates the lamp itself: "+mode); exploration.interact(); lamp.erase("prop")
	for index in [4,6]:
		var item: Dictionary=doc.data["objects"][index]; approach(item,world); exploration.interact(); var key: String="city:"+item["uid"]
		check(not runtime.active.is_empty() and runtime.states[key]["on"] and runtime.states[key]["remaining"]>0,"Appliance starts an actual timed use cycle: "+mode+"/"+item["asset"])
		await capture(mode,"appliance_"+str(index))
		tick(runtime,Plan.profile(item)["duration"]+1)
		check(runtime.active.is_empty() and runtime.states[key]["cycles"]==1 and runtime.inventory.get(Plan.profile(item)["result"],0)>0,"Completed appliance use yields its session result: "+mode+"/"+item["asset"])
		exploration.interact(); exploration.interact(); check(runtime.active.is_empty() and runtime.states[key]["cycles"]==1,"Cancelling an appliance does not award a completed result: "+mode+"/"+item["asset"])
	var foreign_swing: Dictionary=doc.data["objects"][7]; approach(foreign_swing,world); exploration.interact(); tick(runtime,.4)
	check(not runtime.active.is_empty() and (runtime.swing.canvas!=null if mode=="2d" else runtime.swing.rig!=null),"Mixed-source swings create a real moving seat rig: "+mode); await capture(mode,"mixed_swing")
	exploration.interact(); check(runtime.active.is_empty() and runtime.swing.candidate.is_empty(),"Mixed-source swing release restores its source artwork: "+mode)
	var foreign_slide: Dictionary=doc.data["objects"][8]; approach(foreign_slide,world); exploration.interact(); tick(runtime,Plan.profile(foreign_slide)["duration"]*.5); await capture(mode,"mixed_slide"); tick(runtime,Plan.profile(foreign_slide)["duration"]+1)
	check(runtime.active.is_empty(),"Mixed-source slide completes at a clear standing position: "+mode)
	check(doc.data==before and doc.undo_history.size()==history,"Prop use, power states and results never alter authored city or project history: "+mode)
	var bench: Dictionary=doc.data["objects"][0]; approach(bench,world); var bench_node: Node=world.instances[bench["uid"]]; bench_node.visible=false
	check(Plan.nearby(exploration).is_empty(),"Hidden props cannot expose interactions: "+mode); bench_node.visible=true
	var destination: Variant=world.player.global_position; var displacement: Variant=Vector2(24,0) if mode=="2d" else Vector3(1,0,0); world.player.global_position+=displacement
	var wall: Node=StaticBody2D.new() if mode=="2d" else StaticBody3D.new(); var shape: Node=CollisionShape2D.new() if mode=="2d" else CollisionShape3D.new(); wall.collision_layer=1
	if mode=="2d": shape.shape=RectangleShape2D.new(); shape.shape.size=Vector2(3,80)
	else: shape.shape=BoxShape3D.new(); shape.shape.size=Vector3(.1,3,3)
	wall.add_child(shape); world.add_child(wall); wall.global_position=destination+displacement*.5+(Vector2.ZERO if mode=="2d" else Vector3.UP*1.5); await physics_frame
	check(Plan.nearby(exploration).is_empty(),"Prop interaction cannot pass through an intervening wall: "+mode)
	wall.free(); await physics_frame; approach(bench,world); exploration.interact(); var saved_position: Variant=runtime.saved["position"]
	var blocker: Node=StaticBody2D.new() if mode=="2d" else StaticBody3D.new(); var blocker_shape: Node=CollisionShape2D.new() if mode=="2d" else CollisionShape3D.new(); blocker.collision_layer=1
	if mode=="2d": blocker_shape.shape=RectangleShape2D.new(); blocker_shape.shape.size=Vector2(200,200)
	else: blocker_shape.shape=BoxShape3D.new(); blocker_shape.shape.size=Vector3(10,4,10)
	blocker.add_child(blocker_shape); world.add_child(blocker); blocker.global_position=saved_position; await physics_frame; exploration.interact()
	check(not runtime.active.is_empty() and exploration.prompt().contains("blocked"),"Blocked standing space keeps the rider safe and explains how to release: "+mode)
	blocker.free(); await physics_frame; exploration.interact(); check(runtime.active.is_empty(),"Clearing a standing space permits normal release again: "+mode)
	lamp["prop"]={"target":doc.data["objects"][4]["uid"]}; approach(lamp,world); exploration.interact(); var controlled: Dictionary=doc.data["objects"][4]; var controlled_key: String="city:"+controlled["uid"]
	check(runtime.states[controlled_key]["on"] and runtime.states[controlled_key]["remaining"]>0 and runtime.active.is_empty(),"A linked switch starts the actual target appliance without locking the player: "+mode)
	exploration.interact(); check(not runtime.states[controlled_key]["on"] and runtime.states[controlled_key]["remaining"]==0,"Linked switch also cancels target power and its timer: "+mode)
	lamp["prop"]["target"]="missing"; exploration.interact(); check(runtime.active.is_empty() and runtime.notice.contains("missing"),"Missing switch targets explain the problem without changing control ownership: "+mode); lamp.erase("prop")
	approach(controlled,world); exploration.interact(); controlled["prop"]={"kind":"none"}; runtime._physics_process(1.0/60)
	check(runtime.active.is_empty() and not runtime.states.has(controlled_key),"Disabling an appliance during use cancels its pose and stale timed state: "+mode); controlled.erase("prop")
	for index in [0,5]:
		var item: Dictionary=doc.data["objects"][index]; var node: Node=world.instances[item["uid"]]; var original: Dictionary=item.duplicate(true)
		item["direction"]=studio.library.directions(item["asset"])[-1]; item["angle"]=31; item["scale"]=1.7; preload("res://scripts/builder/asset_instance.gd").pose(node,item); node.scale=(Vector2.ONE if mode=="2d" else Vector3.ONE)*1.7
		approach(item,world); exploration.interact(); var point: Variant=Plan.global_point(candidate(item,world),exploration)
		var actual: Variant=world.player.get_node("Sprite2D").to_global(world.player.get_node("Sprite2D").offset+world.player.origin_offset)-Vector2(0,.85*8) if mode=="2d" else world.player.body.global_position+Vector3.UP*.85
		check(not runtime.active.is_empty() and actual.distance_to(point)<.01,"Rotated/scaled native or mixed artwork retains exact seat alignment: "+mode+"/"+item["asset"])
		exploration.interact(); item.clear(); item.merge(original,true); preload("res://scripts/builder/asset_instance.gd").pose(node,item); node.scale=Vector2.ONE if mode=="2d" else Vector3.ONE
	check(doc.data==before and doc.undo_history.size()==history,"Interaction overrides and transform probes restore the original fixture exactly: "+mode)
	approach(doc.data["objects"][0],world); exploration.interact(); studio.set_walking(false)
	check(runtime.active.is_empty() and runtime.effects.entries.is_empty() and (world.player.interaction_visual_offset==Vector2.ZERO if mode=="2d" else world.player.body.position==Vector3.ZERO),"Returning to Build clears all use poses and visual effects: "+mode)
	doc.data["objects"][0]["prop"]={"kind":"seat","label":"Reading bench","point":[0,.55,0]}
	var path: String="res://output/props_state_reset_"+mode+".isocity.json"
	check(studio.write_project(path),"Normal project saving accepts authored interaction settings: "+mode)
	var loaded: bool=studio.load_project(path); var point_values: Array=studio.current().data["objects"][0].get("prop",{}).get("point",[])
	check(loaded and point_values.size()==3 and Vector3(point_values[0],point_values[1],point_values[2]).is_equal_approx(Vector3(0,.55,0)),"Normal project loading retains source-space interaction anchors: "+mode+" · "+str(point_values))
	check(runtime.states.is_empty() and runtime.inventory.is_empty(),"Project loading clears transient use states and session results: "+mode)
func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio); await settle(); schema()
	for mode in ["2d","3d"]: await fixture(mode)
	studio.free(); await process_frame; print("PROPS FOUNDATION: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
