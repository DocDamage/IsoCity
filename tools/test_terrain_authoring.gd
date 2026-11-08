extends SceneTree
const Plan=preload("res://scripts/builder/terrain_plan.gd")
const Traffic=preload("res://scripts/builder/traffic_plan.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func same_serialized(a: Variant,b: Variant) -> bool:
	# JSON has one numeric type; the loader returns doubles for integral cells.
	if (a is int or a is float) and (b is int or b is float): return absf(float(a)-float(b))<1e-9
	if a is Array and b is Array:
		if a.size()!=b.size(): return false
		for index in a.size():
			if not same_serialized(a[index],b[index]): return false
		return true
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size(): return false
		for key in a:
			if not b.has(key) or not same_serialized(a[key],b[key]): return false
		return true
	return a==b
func settle() -> void:
	for frame in 6: await process_frame
	await physics_frame
func mouse(point: Vector2,pressed: bool) -> InputEventMouseButton:
	var result:=InputEventMouseButton.new(); result.position=point; result.button_index=MOUSE_BUTTON_LEFT; result.pressed=pressed; return result
func screen(studio: Control,point: Vector2) -> Vector2:
	var height: float=Plan.sample(studio.current().data,point)["height"]; var world: Node=studio.worlds[studio.mode]
	return world.get_viewport().get_canvas_transform()*Plan.project_2d(Vector3(point.x,height,point.y)) if studio.mode=="2d" else world.camera.unproject_position(Vector3(point.x,height,point.y))
func run() -> void:
	root.size=Vector2i(1480,900); var studio: Control=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio); await settle(); var tools: RefCounted=studio.terrain_tools
	for mode in ["2d","3d"]:
		studio.switch_mode(mode); var doc=preload("res://scripts/builder/document.gd").new(); doc.data=preload("res://scripts/builder/templates.gd").make(mode,"blank"); doc.data["objects"]=[]; doc.data["roads"]=[]; studio.documents[mode]=doc; studio.changed(); await settle()
		tools.show(); tools.enabled.button_pressed=true; tools.width.value=64; tools.depth.value=64; tools.center_x.value=0; tools.center_z.value=0; tools.land.color=Color("607e56"); tools.water.color=Color("368aa4"); tools.apply_settings(); tools.activate()
		var world: Node=studio.worlds[mode]
		if mode=="2d": world.camera.position=Vector2.ZERO; world.camera.zoom=Vector2.ONE
		else: world.target=Vector3.ZERO; world.distance=45; world.update_camera()
		await settle()
		for stroke in [[0,Vector2(-8,-4),6,2],[6,Vector2(8,4),5,3],[3,Vector2(8,4),6,.3]]:
			tools.operation.select(stroke[0]); tools.radius.value=stroke[2]; tools.amount.value=stroke[3]; tools.target.value=0; var at: Vector2=screen(studio,stroke[1]); var history: int=doc.undo_history.size(); studio._canvas_input(mouse(at,true)); studio._canvas_input(mouse(at,false))
			check(not tools.drawing and doc.undo_history.size()==history+1,"Canvas sculpting commits one Undo step: "+mode+str(stroke[0]))
		check(Plan.sample(doc.data,Vector2(-8,-4))["height"]>1 and not doc.data["water_cells"].is_empty() and Plan.sample(doc.data,Vector2(8,4))["height"]< -1,"Editor actions create a hill and a filled, smoothed depression: "+mode)
		var ring: PackedVector2Array=tools.preview_circle(screen(studio,Vector2(8,4))); check(ring.size()==49 and ring[0].distance_to(ring[-1])<.01,"Terrain brush footprint is a closed projected radius: "+mode)
		doc.data["terrain"]["extension"]="preserve"; tools.operation.select(0); tools.radius.value=2; tools.amount.value=.5; tools.begin(Vector2(-4,0)); var path: String="res://output/terrain_authored_"+mode+".isocity.json"; var count: int=doc.undo_history.size()
		check(studio.write_project(path) and not tools.drawing and doc.undo_history.size()==count+1,"Saving commits an active terrain gesture: "+mode)
		var saved: Dictionary=doc.data.duplicate(true); doc.undo(); studio.changed(); check(doc.data!=saved,"Committed save gesture remains undoable: "+mode)
		check(studio.load_project(path),"Authored terrain project reopens through the repair-aware loader: "+mode); await settle(); doc=studio.current()
		check(same_serialized(doc.data,saved) and doc.data["terrain"]["extension"]=="preserve","Reopening preserves serialized samples, water, colors and extensions: "+mode)
		check(Plan.sample(doc.data,Vector2(-8,-4))["height"]>1 and Plan.water_level(doc.data,Vector2(8,4))!=null,"Reopened terrain reconstructs the same hill and pond: "+mode)
		if "--capture" in OS.get_cmdline_user_args():
			tools.show(); tools.operation.select(3); tools.activate(); studio.control_settings.cursor_active=true; studio.control_settings.cursor_position=screen(studio,Vector2(8,4)); await settle(); studio.update_overlay(true); RenderingServer.force_draw(false); RenderingServer.force_draw(false); root.get_texture().get_image().save_png("res://output/terrain_authored_"+mode+".png"); studio.control_settings.cursor_active=false
	studio.free(); print("TERRAIN AUTHORING: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
