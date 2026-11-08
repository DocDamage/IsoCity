extends SceneTree
const Plan=preload("res://scripts/builder/prop_plan.gd")
const Claims=preload("res://scripts/builder/activity_reservations.gd")
const OUT="res://output/verification/asset_expansion/I07/"
var studio: Control
var checks: int=0
var failures: int=0
func _initialize() -> void: call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func settle() -> void:
	for i in 5: await physics_frame
	await process_frame
func capture(name: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	for frame in 8: await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUT+name+".png")==OK,"Rendered capture: "+name)
func schema() -> void:
	var slide: Dictionary={"asset":"3d:HanX_School/Slide","direction":"0"};var slide_profile: Dictionary=Plan.profile(slide)
	check(Plan.source(slide_profile,slide,studio.library,"facing")==Plan.source(slide_profile,slide,studio.library,"end"),"Legacy slide heading still faces its landing")
	for key in ["exit","facing","customer"]:
		check(Plan.valid({key:[1,.4,-2]}),"Optional source point validates: "+key)
		for value in [[],[0,0],[0,0,NAN],[0,0,65],"point"]: check(not Plan.valid({key:value}),"Invalid source point rejected: "+key)
	var pool=Claims.new(); var a:=Node.new(); var b:=Node.new()
	var token: int=pool.acquire("room:A:ground:chair",a)
	check(token>0 and pool.acquire("room:A:ground:chair",b)==0,"Two actors cannot own one station")
	check(pool.acquire("room:B:ground:chair",b)>0 and pool.acquire("room:A:upstairs:chair",b)>0,"Building and floor namespaces isolate reused UIDs")
	pool.release("room:A:ground:chair",token+1); check(not pool.current("room:A:ground:chair").is_empty(),"A stale cancellation cannot release a newer reservation")
	pool.release("room:A:ground:chair",token); var next: int=pool.acquire("room:A:ground:chair",b)
	pool.release("room:A:ground:chair",token); check(pool.current("room:A:ground:chair")["token"]==next,"Tokens remain distinct after reacquisition")
	a.free(); b.free(); check(pool.current("room:A:ground:chair").is_empty(),"Freed owners release abandoned reservations lazily")
	pool.release_owner(null); check(pool.entries.is_empty(),"Cleanup prunes abandoned entries")
	for id in Plan.definitions()["assets"]:
		var authored: Dictionary=Plan.definitions()["assets"][id]
		if not authored.get("anchor_review",{}).has("source_pixels"): continue
		for direction in authored["anchor_review"]["source_pixels"]:
			var point: Vector3=Plan.source(Plan.profile({"asset":id,"direction":direction}),{"asset":id,"direction":direction},studio.library,"point")
			var pixel: Vector2=preload("res://scripts/builder/grid_fit.gd").pixels(Vector2(point.x,point.z))-Vector2(0,point.y*8)
			var view: Dictionary=studio.library.assets[id]["data"]["directions"][direction]; var raw: Array=authored["anchor_review"]["source_pixels"][direction]; var origin: Array=view["origin"]
			check(pixel.distance_to(Vector2(raw[0]-origin[0],raw[1]-origin[1]))<.001,"Reviewed contact projects onto the actual source frame: "+id+" "+direction)
func candidate(world: Node,item: Dictionary) -> Dictionary:
	var result: Dictionary=Plan.context(world.exploration).duplicate(false); result["item"]=item; result["node"]=world.instances[item["uid"]]; result["profile"]=Plan.profile(item); return result
func approach(world: Node,item: Dictionary) -> Dictionary:
	var result: Dictionary=candidate(world,item); var at: Variant=Plan.ground_point(result,world.exploration,"approach")
	world.player.teleport_to(world.player.get_parent().to_local(at)); world.player.set_physics_process(false); return result
func blocker(world: Node,mode: String,at: Variant,size_value: float) -> Node:
	var body: Node=StaticBody2D.new() if mode=="2d" else StaticBody3D.new(); var shape: Node=CollisionShape2D.new() if mode=="2d" else CollisionShape3D.new()
	if mode=="2d": shape.shape=RectangleShape2D.new(); shape.shape.size=Vector2.ONE*size_value
	else: shape.shape=BoxShape3D.new(); shape.shape.size=Vector3(size_value,3,size_value)
	body.add_child(shape); world.add_child(body); body.global_position=at; return body
func fixture(mode: String) -> void:
	studio.switch_mode(mode); var doc=preload("res://scripts/builder/document.gd").new(); doc.data=preload("res://scripts/builder/templates.gd").make(mode,"blank"); studio.documents[mode]=doc
	var ids: Array=["3d:HanX_School/Student_Chair","3d:HanX_School/Computer_Desk","2d:Supplemental_Classroom_school_kit_bean_bag_04c585ab","2d:Supplemental_Office_desk_kit_office_chair_bad6887e","2d:Supplemental_Gym_fitness_kit_weight_bench_4a8a0688","2d:Stove_Oven","3d:Supplemental_SWAT/Prop_Comms_Station"]
	for i in ids.size():
		var x: float=(i%3)*12; var z: float=floori(i/3.0)*16
		var item: Dictionary=doc.add(ids[i],[x*16,z*8,0] if mode=="2d" else [x,0,z],studio.library.directions(ids[i])[0]); item["uid"]="anchor_"+str(i)
	studio.changed(); await settle(); studio.set_walking(true); var world: Node=studio.worlds[mode]; var runtime: Node=world.exploration.props
	var before: Dictionary=doc.data.duplicate(true); var history: int=doc.undo_history.size()
	for item in doc.data["objects"]:
		var node: Node=world.instances[item["uid"]]
		for direction in studio.library.directions(item["asset"]):
			item["direction"]=direction; preload("res://scripts/builder/asset_instance.gd").pose(node,item); await settle()
			var target: Dictionary=approach(world,item); var clear: bool=Plan.standing_clear(world.exploration,world.player.global_position)
			check(clear,"Calibrated approach clears actual traversal shape: "+mode+" "+item["asset"]+" "+direction)
			check(runtime.interact(target),"Reviewed interaction starts: "+mode+" "+item["asset"]+" "+direction)
			if runtime.active.is_empty(): continue
			var use: Variant=Plan.global_point(target,world.exploration)
			if target["profile"]["kind"]=="seat":
				var hips: Variant=world.player.body.global_position+Vector3.UP*.85 if mode=="3d" else world.player.get_node("Sprite2D").to_global(world.player.get_node("Sprite2D").offset+world.player.origin_offset)-Vector2(0,.85*8)
				check(hips.distance_to(use)<.01,"Actual seated pose follows reviewed contact: "+mode+" "+item["asset"])
			if direction==studio.library.directions(item["asset"])[0] and "--capture" in OS.get_cmdline_user_args():
				if mode=="2d": world.camera.position=world.player.position; world.camera.zoom=Vector2(5,5)
				else: world.camera.fov=35
				await capture("pose_"+mode+"_"+item["uid"])
				if mode=="3d" and item["uid"]=="anchor_0":
					world.yaw+=180; world.update_camera(); await capture("pose_3d_chair_rear"); world.yaw-=180; world.update_camera()
			check(runtime.reservation_token>0 and not runtime.reservations.current(runtime.reservation_key).is_empty(),"Actual use owns its scoped station")
			var saved_key: String=runtime.reservation_key; var pool: RefCounted=runtime.reservations
			check(runtime.finish() and runtime.active.is_empty() and pool.current(saved_key).is_empty(),"Exit clears the pose and reservation")
			check(Plan.standing_clear(world.exploration,world.player.global_position),"Exit returns to actual clear walking space")
		item["direction"]=studio.library.directions(item["asset"])[0]; preload("res://scripts/builder/asset_instance.gd").pose(node,item)
	for index in [0,3,4]:
		var item: Dictionary=doc.data["objects"][index]; var original_item: Dictionary=item.duplicate(true); var source: Node=world.instances[item["uid"]]
		item["scale"]=1.7; item["tilt"]=[-8,7]
		if item["asset"].begins_with("3d:"):item["direction"]="35"
		else:item["angle"]=35
		preload("res://scripts/builder/asset_instance.gd").pose(source,item); source.scale=(Vector2.ONE if mode=="2d" else Vector3.ONE)*1.7; await settle()
		var transformed: Dictionary=approach(world,item)
		check(runtime.interact(transformed),"Rotated, scaled and tilted approach remains usable: "+mode+" "+item["asset"])
		if not runtime.active.is_empty():
			check(runtime.finish() and Plan.standing_clear(world.exploration,world.player.global_position),"Transformed exit returns to clear walking space: "+mode)
		item.clear();item.merge(original_item,true);preload("res://scripts/builder/asset_instance.gd").pose(source,item);source.scale=Vector2.ONE if mode=="2d" else Vector3.ONE
	await settle()
	var chair: Dictionary=doc.data["objects"][0]; var target: Dictionary=approach(world,chair); var pool: RefCounted=Claims.for_world(world); var rival:=Node.new(); var key: String=runtime.key_for(target); var rival_token: int=pool.acquire(key,rival)
	check(not runtime.interact(target) and runtime.notice.contains("already in use") and world.player.collision_mask==(1 if mode=="2d" else 3),"Occupied station refuses control takeover: "+mode)
	pool.release(key,rival_token); rival.free(); check(runtime.interact(target),"Released station can be acquired again: "+mode)
	var node: Node=world.instances[chair["uid"]]; var original: Variant=node.global_transform
	if mode=="2d": node.position+=Vector2(16,0)
	else: node.position+=Vector3(1,0,0)
	runtime._physics_process(1.0/60)
	check(runtime.active.is_empty() and pool.current(key).is_empty() and world.player.collision_mask==(1 if mode=="2d" else 3),"Moving occupied geometry cancels pose and claim: "+mode)
	node.global_transform=original; await settle(); target=approach(world,chair)
	var wall: Node=blocker(world,mode,world.player.global_position,8 if mode=="2d" else .6); await settle()
	check(not runtime.interact(target) and runtime.notice.contains("blocked") and pool.current(key).is_empty(),"Actual capsule clearance rejects a blocked operator position: "+mode)
	wall.free(); await settle(); target=approach(world,chair); runtime.interact(target)
	wall=blocker(world,mode,world.player.global_position,220 if mode=="2d" else 12); await settle()
	check(not runtime.finish() and runtime.reservation_token>0,"Blocked exit retains the safe pose and reservation: "+mode)
	wall.free(); await settle(); check(runtime.finish(),"Cleared exit resumes walking: "+mode)
	target=approach(world,chair); runtime.interact(target); node.visible=false; runtime._physics_process(1.0/60)
	check(runtime.active.is_empty() and pool.current(key).is_empty(),"Hiding occupied furniture releases its claim: "+mode); node.visible=true
	target=approach(world,chair); runtime.interact(target); doc.data["objects"]=doc.data["objects"].filter(func(item: Dictionary):return item["uid"]!=chair["uid"]); runtime._physics_process(1.0/60)
	check(runtime.active.is_empty() and pool.current(key).is_empty(),"Deletion releases station even before render reconciliation: "+mode)
	doc.data=before.duplicate(true); studio.changed(); await settle(); chair=doc.data["objects"][0]; target=approach(world,chair); runtime.interact(target); runtime.reset()
	check(runtime.active.is_empty() and pool.entries.is_empty(),"Reset releases every runtime-owned claim: "+mode)
	check(doc.data==before and doc.undo_history.size()==history,"All ordinary use remains transient: "+mode)
	if mode=="2d":
		var family: String=""
		for id in studio.library.assets:
			if studio.library.assets[id]["data"].get("kind")=="char" and not studio.library.assets[id]["data"].get("animations",{}).is_empty(): family=id.trim_prefix("2d:"); break
		check(not family.is_empty(),"A supplied character family is present for unsupported-pose validation")
		if not family.is_empty():
			var original_id: String=world.player.item_id; world.player.item_id=family; target=approach(world,chair); runtime.interact(target)
			check(not runtime.active.is_empty() and runtime.prompt().contains("No supported sit"),"Unavailable supplied sitting pose explains its idle fallback")
			runtime.finish(); world.player.item_id=original_id
			target=approach(world,chair);runtime.interact(target);check(not runtime.prompt().contains("No supported sit"),"Returning to a supplied seated sprite drops a stale fallback notice");runtime.finish()
	studio.set_walking(false)
	await authoring(mode)
func authoring(mode: String) -> void:
	var doc: RefCounted=studio.current(); var uid: String=doc.data["objects"][0]["uid"]; studio.selected_uids.assign([uid]); studio.selected_uid=uid
	var ui: RefCounted=studio.prop_tools; ui.stamp=0; ui.refresh(); studio._command("props",null)
	root.size=Vector2i(1480,900); await capture("props_simple_"+mode+"_1480")
	studio.consumer_shell.set_active(false,false); studio._command("props",null); await capture("props_precision_"+mode+"_1480"); studio.consumer_shell.set_active(true,false)
	var history: int=doc.undo_history.size(); var overrides: Dictionary={"exit":[.8,0,1.2],"facing":[0,.44,2],"customer":[0,0,-1.4]}
	for key in overrides:
		ui.point_checks[key].button_pressed=true
		for axis in 3: ui.point_fields[key][axis].value=overrides[key][axis]
	ui.apply_settings()
	check(doc.undo_history.size()==history+1 and doc.object(uid)["prop"].has_all(["exit","facing","customer"]),"New anchors author through one ordinary history entry: "+mode)
	studio._command("undo",null); check(not doc.object(uid).has("prop"),"Undo restores legacy automatic anchors: "+mode)
	studio._command("redo",null); check(doc.object(uid)["prop"].has("customer"),"Redo restores optional customer and exit points: "+mode)
	check(studio.write_project(OUT+"anchors_"+mode+".isocity.json"),"Save retains optional source anchors: "+mode)
	var repair=preload("res://scripts/builder/project_repair.gd").new(studio.library); var reopened: Dictionary=repair.read(OUT+"anchors_"+mode+".isocity.json")
	check(reopened["ok"] and repair.issues.is_empty(),"Reopen requires no migration or repair: "+mode)
	var exported: Dictionary=preload("res://scripts/builder/portable_export.gd").new().save(studio.worlds[mode],doc.data,studio.library,OUT+"anchors_"+mode+".zip")
	check(not exported["ok"] and exported.get("message","").contains("restrict"),"Restricted prepared sprites retain their existing export restriction: "+mode)
	var permitted: Dictionary=doc.data.duplicate(true); permitted["objects"]=permitted["objects"].filter(func(item: Dictionary):return studio.library.assets[item["asset"]].get("data",{}).get("source_export_allowed",true))
	exported=preload("res://scripts/builder/portable_export.gd").new().save(studio.worlds[mode],permitted,studio.library,OUT+"anchors_"+mode+".zip")
	check(exported["ok"],"Permitted package includes anchors and reservation dependency: "+mode+" "+exported.get("message",""))
	check(preload("res://scripts/builder/project_store.gd").write_json(OUT+"expected_"+mode+".json",permitted),"Independent expected document saved: "+mode)
	var original: Vector2i=root.size; root.size=Vector2i(960,640); studio.accessibility_settings.restore({"text_scale":1.5,"high_contrast":true,"large_targets":true}); studio._command("props",null); ui.advanced.button_pressed=true; await settle()
	ui.page.ensure_control_visible(ui.point_checks["customer"]); ui.point_checks["customer"].grab_focus(); await settle()
	check(Rect2(Vector2.ZERO,Vector2(root.size)).has_point(ui.point_checks["customer"].get_global_rect().get_center()),"Enlarged keyboard controls reach customer setup anchor: "+mode)
	var edit: LineEdit=ui.point_fields["exit"][0].get_line_edit();var background: StyleBox=edit.get_theme_stylebox("read_only")
	check(background is StyleBoxFlat and background.bg_color.get_luminance()<.1 and edit.get_theme_color("font_uneditable_color").get_luminance()>.5,"Read-only coordinates stay legible in high contrast: "+mode)
	await capture("props_accessible_customer_"+mode+"_960")
	ui.page.ensure_control_visible(ui.apply_button); ui.apply_button.grab_focus(); await settle()
	check(Rect2(Vector2.ZERO,Vector2(root.size)).has_point(ui.apply_button.get_global_rect().get_center()),"Enlarged keyboard controls reach Apply: "+mode)
	await capture("props_accessible_actions_"+mode+"_960")
	root.size=original; studio.accessibility_settings.restore({}); await settle()
	await occupied_floor(mode)
func occupied_floor(mode: String) -> void:
	var city: RefCounted=studio.current(); var host: Dictionary=city.add("3d:HanX_Shop/Shop_Cafe",[720,480,0] if mode=="2d" else [45,0,30],"0"); var host_uid: String=host["uid"]
	studio.changed();await settle();studio.interior_tools.start(host_uid)
	check(studio.interior_tools.editing(),"Actual owned-room editor opens for cancellation fixture: "+mode)
	if not studio.interior_tools.editing():return
	var floors: RefCounted=studio.interior_tools.floor_tools; floors.new_name.text="Anchor floor";floors.new_height.value=3;floors.add_floor()
	var doc: RefCounted=studio.current();var upper: String=doc.floor_uid
	doc.checkpoint();doc.data["objects"]=[{"uid":"floor_chair","asset":"3d:HanX_School/Student_Chair","direction":"0","position":[0,0,0],"scale":1.0,"prop":{"exit":[.8,0,1.2],"facing":[0,.44,2],"customer":[0,0,-1.4]}}]
	doc.canonical.data["floor_links"]=[{"uid":"anchor_stairs","kind":"stairs","lower":"ground","upper":upper,"start":[-3,3],"end":[2,3],"width":1.4}];doc.finish_checkpoint();studio.changed();await settle()
	studio.selected_uids.assign(["floor_chair"]);studio.selected_uid="floor_chair";studio.prop_tools.preview_selected();await settle()
	var world: Node=studio.worlds[mode];var runtime: Node=world.exploration.props
	world.player.set_physics_process(false);world.exploration.interact()
	check(not runtime.active.is_empty() and runtime.active["scope"].contains(upper),"Actual connected upstairs chair acquires its floor scope: "+mode)
	var pool: RefCounted=runtime.reservations;var key: String=runtime.reservation_key
	floors.remove_floor();await settle()
	check(runtime.active.is_empty() and (not pool or pool.current(key).is_empty()) and not studio.walking,"Removing an occupied floor returns to Build and releases its claim: "+mode)
	studio._command("undo",null);await settle()
	var restored: Dictionary=preload("res://scripts/builder/floor_plan.gd").room(studio.current().canonical.data,upper)
	check(not restored.is_empty() and restored["objects"][0]["prop"].has_all(["exit","facing","customer"]) and runtime.active.is_empty(),"Undo restores floor anchors without resurrecting a transient rider: "+mode)
	studio.set_walking(false);studio.interior_tools.leave();await settle()
func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio); await settle(); schema()
	for mode in ["2d","3d"]: await fixture(mode)
	studio.free(); await process_frame; print("INTERACTION ANCHORS: %d checks, %d failures"%[checks,failures]); quit(1 if failures else 0)
