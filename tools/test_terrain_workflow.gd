extends SceneTree
const Plan=preload("res://scripts/builder/terrain_plan.gd")
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for frame in 6: await process_frame
	await physics_frame
func mouse(at: Vector2,pressed: bool,button: int=MOUSE_BUTTON_LEFT) -> InputEventMouseButton:
	var event:=InputEventMouseButton.new(); event.position=at; event.button_index=button; event.pressed=pressed; return event
func run() -> void:
	root.size=Vector2i(1480,900)
	var studio: Control=load("res://scenes/builder.tscn").instantiate(); studio.storage_enabled=false; root.add_child(studio); await settle()
	var tools: RefCounted=studio.terrain_tools
	for mode in ["2d","3d"]:
		studio.switch_mode(mode)
		var doc=preload("res://scripts/builder/document.gd").new(); doc.data=preload("res://scripts/builder/templates.gd").make(mode,"blank"); doc.data["objects"]=[]; doc.data["roads"]=[]; studio.documents[mode]=doc; studio.changed(); await settle()
		studio._command("terrain",null); check(studio.workspace_layout.tabs.current_tab==tools.panel.get_index(),"Palette opens terrain controls: "+mode)
		tools.enabled.button_pressed=true; tools.width.value=32; tools.depth.value=32; tools.land.color=Color("76885a"); tools.protect_objects.button_pressed=false; tools.protect_roads.button_pressed=false; tools.protect_actors.button_pressed=false; tools.apply_settings(); await settle()
		check(Plan.settings(doc.data)["enabled"] and Plan.bounds(doc.data).size==Vector2i(16,16),"Settings enable the requested terrain bounds: "+mode)
		check(Plan.settings(doc.data)["land_color"]=="76885aff","Land color saves in the document: "+mode)
		tools.activate(); check(studio.tool=="terrain" and studio.workspace_layout.tabs.get_current_tab_control()==tools.panel,"Sculpt activates the contextual terrain tab: "+mode)
		var world: Node=studio.worlds[mode]
		if mode=="2d": world.camera.position=Vector2.ZERO
		else: world.target=Vector3.ZERO; world.update_camera()
		await settle(); var at: Vector2=studio.canvas.size*.5; var hit: Dictionary=tools.point(at); check(hit["ok"],"Canvas center picks editable terrain: "+mode)
		var original: Dictionary=doc.data.duplicate(true); tools.radius.value=4; tools.amount.value=1; tools.operation.select(0)
		studio._canvas_input(mouse(at,true)); check(tools.drawing and studio.stroke,"Canvas press starts a terrain gesture: "+mode)
		var motion:=InputEventMouseMotion.new(); motion.position=at+Vector2(4,0); studio._canvas_input(motion); studio._canvas_input(mouse(motion.position,false))
		var raised: Dictionary=doc.data.duplicate(true); check(not tools.drawing and not studio.stroke and raised!=original,"Release commits a multi-dab gesture: "+mode)
		doc.undo(); check(doc.data==original,"One Undo restores the complete brush stroke: "+mode); doc.redo(); check(doc.data==raised,"Redo reconstructs every changed sample: "+mode); studio.changed(); await settle()
		studio._canvas_input(mouse(at,true)); studio._canvas_input(mouse(at,true,MOUSE_BUTTON_RIGHT)); check(doc.data==raised and not tools.drawing,"Right click cancels without changing history: "+mode)
		tools.begin(Vector2.ZERO); studio.control_settings.execute("cancel"); check(doc.data==raised and not tools.drawing,"Remappable Cancel restores the unfinished stroke: "+mode)
		tools.begin(Vector2(8,8)); var committed: Dictionary=doc.data.duplicate(true); studio.set_tool("select"); check(not tools.drawing and doc.data==committed,"Choosing another tool commits the current terrain stroke: "+mode); doc.undo(); studio.changed(); tools.activate()
		tools.begin(Vector2.ZERO); tools.operation.select(6); tools.target.value=0; tools.amount.value=3; tools.dab(Vector2.ZERO); studio.finish_edit(at); check(not tools.drawing and not doc.data.get("water_cells",[]).is_empty(),"Basin creates water and generic finish commits the gesture: "+mode)
		var saved: Dictionary=doc.data.duplicate(true); tools.width.value=8; tools.depth.value=8; tools.apply_settings(); check(doc.data==saved,"Shrinking bounds refuses to discard existing samples: "+mode)
		tools.operation.select(0); tools.begin(Vector2(8,8)); studio.switch_mode("3d" if mode=="2d" else "2d"); check(doc.data==saved and not tools.drawing,"Switching worlds cancels the unfinished terrain gesture: "+mode); studio.switch_mode(mode)
		if "--capture" in OS.get_cmdline_user_args():
			tools.show(); await settle(); await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png("res://output/terrain_workflow_"+mode+".png")
	studio.free(); print("TERRAIN WORKFLOW: %d/%d checks passed"%[checks-failures,checks]); quit(1 if failures else 0)
