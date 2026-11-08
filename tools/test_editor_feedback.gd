extends SceneTree
var checks: int=0
var failures: int=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; print("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for i in 5: await process_frame
	await physics_frame
func capture(name: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await settle()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://output/"+name+".png")
func run() -> void:
	var studio: Control=load("res://scenes/builder.tscn").instantiate()
	studio.storage_enabled=false
	root.add_child(studio)
	await settle()
	var feedback: RefCounted=studio.editor_feedback
	studio.update_save_badge()
	check(studio.save_badge.text.contains("Unsaved project"),"An unnamed workspace does not claim a named save")
	var save_text: String=studio.save_badge.text
	studio.status.text="Rotated two objects"
	feedback.tick(0)
	check(feedback.records[0].contains("Rotated two objects") and studio.save_badge.text==save_text,"Action feedback leaves persistent save state intact")
	feedback.tick(9)
	check(studio.status.text.is_empty() and studio.save_badge.text==save_text,"Temporary action feedback expires while saved state remains")
	studio.status.text="Could not save: destination unavailable"
	feedback.tick(0)
	feedback.show_history()
	await settle()
	check(studio.modal_visible() and feedback.list.item_count>=2,"Expired and error feedback remains available in history")
	feedback.list.item_selected.emit(1)
	check(feedback.detail.text.contains("Rotated two objects"),"Recent action rows reveal their complete message")
	studio.status.text="Background save feedback"
	feedback.tick(0)
	feedback.list.item_selected.emit(1)
	check(feedback.detail.text.contains("Rotated two objects"),"History row details stay matched when background feedback arrives")
	check(feedback.dialog.position.y>=0 and feedback.dialog.position.y+feedback.dialog.size.y<=root.size.y,"Recent action history fits the window on first open")
	await capture("editor_feedback_history")
	feedback.dialog.hide()
	for mode in ["2d","3d"]:
		studio.switch_mode(mode)
		studio.current().data=preload("res://scripts/builder/templates.gd").make(mode,"blank")
		studio.refresh_worlds()
		studio.worlds[mode].reset_camera("room")
		var doc: RefCounted=studio.current()
		var id: String="2d:Coffee_Shop" if mode=="2d" else "3d:HanX_City/Cafe_Small"
		studio.select_asset(id)
		var layer: String=studio.Layers.classify(id,studio.library)
		for state in ["hidden","locked"]:
			studio.Layers.set_state(doc.data,layer,"visible",state!="hidden")
			studio.Layers.set_state(doc.data,layer,"locked",state=="locked")
			var diagnostic: Dictionary=feedback.diagnostics(Vector2(20,20),{})
			check(diagnostic["blocked"] and diagnostic["text"].contains(state) and diagnostic["text"].contains(layer),"Cursor names the exact blocking layer state: "+mode+" "+state)
			var count: int=doc.data["objects"].size()
			studio.paint(Vector2(20,20))
			check(doc.data["objects"].size()==count and studio.status.text.contains(state),"Blocked placement and cursor reason agree: "+mode+" "+state)
		studio.worlds[mode].preview(id,[0,0,0],studio.direction,1,true)
		studio.update_overlay(true)
		check(studio.overlay.caption.contains("Blocked") and not studio.overlay.caption.contains("click to place"),"Blocked cursor never invites placement: "+mode)
		if "--capture" in OS.get_cmdline_user_args():
			# Stage the diagnostic inside the canvas without moving the user's mouse.
			studio.set_process(false)
			studio.overlay.caption_position=studio.canvas.size*0.5+Vector2(18,22)
			await capture("editor_feedback_blocked_"+mode)
			studio.set_process(true)
		studio.Layers.set_state(doc.data,layer,"visible",true)
		studio.Layers.set_state(doc.data,layer,"locked",false)
		studio.snap_input.button_pressed=false
		check(feedback.diagnostics(Vector2.ZERO,{"position":[0,0,0]})["text"].contains("Grid snap is off"),"Free placement explains disabled grid snapping: "+mode)
		check(feedback.diagnostics(Vector2.ZERO,{"position":[INF,0,0]})["blocked"],"Unsupported positions receive a specific blocked reason: "+mode)
		studio.select_asset("2d:Sedan_Red" if mode=="2d" else "3d:HanX_Traffic/Car_Sedan")
		studio.arrange_tools.snap_target.select(0)
		check(feedback.diagnostics(Vector2.ZERO,{"position":[0,0,0],"snapped":false})["text"].contains("No nearby road lane"),"Unsuccessful vehicle lane snapping explains its fallback: "+mode)
		studio.arrange_tools.snap_target.select(1)
		check(feedback.diagnostics(Vector2.ZERO,{"position":[0,0,0]})["text"].contains("anchor takes priority"),"Custom anchors explain lane-snap precedence: "+mode)
		studio.arrange_tools.snap_target.select(0)
		studio.rotation_manual=true
		check(feedback.diagnostics(Vector2.ZERO,{"position":[0,0,0],"snapped":true})["text"].contains("manual facing"),"Manual vehicle facing is explained: "+mode)
		check(feedback.diagnostics(Vector2.ZERO,{"position":[0,0,0],"snapped":true})["text"].contains("still snapped"),"Disabling grid snap does not mislabel lane-snapped placement as free: "+mode)
		studio.select_asset("2d:Grass")
		studio.surface_input.button_pressed=false
		studio.ground_brush.operation.select(3)
		var at: Vector2=studio.canvas.size*0.5
		var info: Dictionary=studio.placement(at)
		check(feedback.diagnostics(at,info)["text"].contains("keeps its cell grid") and not feedback.diagnostics(at,info)["text"].contains("free placement"),"Cell painting explains its fixed grid independently of the grid checkbox: "+mode)
		check(feedback.diagnostics(at,info)["text"].contains("needs existing ground"),"Empty flood-fill targets are explained at the cursor: "+mode)
		var cell: Vector2i=studio.ground_brush.cell_at(at)
		if mode=="2d": doc.data["tiles"].append({"cell":[cell.x,cell.y],"asset":"2d:Grass","direction":"SE"})
		else: doc.add("2d:Grass",studio.ground_brush.position_for(cell),"SE")
		studio.changed()
		info=studio.placement(at)
		check(not feedback.diagnostics(at,info)["text"].contains("needs existing ground"),"Ground diagnostics invalidate their cache after edits: "+mode)
		if mode=="3d":
			var ground: Dictionary=doc.data["objects"][0]
			ground["name"]="Protected lawn"
			ground["locked"]=true
			studio.changed()
			check(feedback.diagnostics(at,studio.placement(at))["text"].contains("Protected lawn is locked · unlock it in Scene"),"Protected ground identifies the object and its actual unlock control")
			ground["locked"]=false
			ground["visible"]=false
			studio.changed()
			check(feedback.diagnostics(at,studio.placement(at))["text"].contains("Protected lawn is hidden · show it in Scene"),"Hidden ground identifies the object and its actual visibility control")
			ground["visible"]=true
			studio.changed()
		studio.set_tool("crossing")
		check(feedback.diagnostics(at,{})["text"].contains("No road section"),"Crossing tools explain missing road targets: "+mode)
		studio.set_tool("road_erase")
		check(not feedback.diagnostics(at,{})["blocked"],"Road erasing may begin in empty space and skip it: "+mode)
		studio.select_asset("not-installed")
		check(feedback.diagnostics(at,{})["text"].contains("unavailable"),"Rejected source assets leave a cursor explanation: "+mode)
		feedback.tick(9)
		check(feedback.diagnostics(at,{}).is_empty(),"Rejected-asset cursor feedback expires")
	studio.switch_mode("3d")
	studio.select_asset("3d:HanX_Park/Bench_Park")
	studio.surface_input.button_pressed=true
	var world: Node=studio.worlds["3d"]
	world.surface_snapping=true
	world.surface_point(Vector2(-100000,-100000),false,0)
	check(world.surface_feedback.contains("No surface hit"),"A real failed surface ray records its height-plane fallback")
	check(feedback.diagnostics(Vector2.ZERO,{"position":[0,0,0]})["text"].contains("height plane"),"Surface fallback reaches the cursor explanation")
	var wall:=StaticBody3D.new()
	wall.collision_layer=1
	var shape:=CollisionShape3D.new()
	var box:=BoxShape3D.new()
	box.size=Vector3(4,4,.1)
	shape.shape=box
	wall.add_child(shape)
	wall.position=Vector3(0,1.5,1)
	world.add_child(wall)
	await settle()
	world.surface_point(world.camera.unproject_position(Vector3(0,1.5,0)),false,0)
	check(world.surface_feedback.contains("too steep"),"A real vertical surface ray explains why it cannot accept surface snapping")
	wall.free()
	check(studio.write_project("user://editor_feedback_test.isocity.json"),"Project saves with feedback UI")
	studio.update_save_badge()
	check(studio.save_badge.text.contains("Saved") and studio.save_badge.text.contains("Recovery disabled") and not studio.dirty,"An explicit save updates saved state without claiming disabled recovery is pending")
	studio.set_walking(true)
	studio.status.text="Saved while walking"
	studio._process(0.01)
	check(studio.status.text=="Saved while walking" and feedback.walk_prompt.visible and not feedback.walk_prompt.text.is_empty(),"Walking prompts do not overwrite action feedback")
	check(studio.save_badge.is_visible_in_tree(),"Saved state remains visible while walking")
	studio.set_walking(false)
	for i in 45: studio.status.text="Action "+str(i); feedback.tick(0)
	check(feedback.records.size()==40,"Recent feedback retention is bounded")
	var lines: PackedStringArray=studio.overlay.caption_lines("A blocked placement reason with words and a verylongunbrokenassetname12345678901234567890",160)
	for line in lines: check(ThemeDB.fallback_font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x<=160,"Cursor feedback wraps within the canvas")
	await capture("editor_feedback_saved_state")
	studio.free()
	print("EDITOR FEEDBACK: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
