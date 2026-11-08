extends SceneTree
const Document=preload("res://scripts/builder/document.gd")
const Templates=preload("res://scripts/builder/templates.gd")
var checks: int=0
var failures: int=0
var studio: Control
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;print("FAIL: "+message)
func _initialize() -> void:call_deferred("run")
func settle(count: int=8) -> void:
	for i in count:await process_frame
	await physics_frame
func capture(name: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args():return
	await settle(12);RenderingServer.force_draw(false);RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("res://output/verification/asset_expansion/U18/"+name+".png")
func hit(uid: String) -> Vector2:
	var bounds: Rect2=studio.screen_bounds(uid).intersection(Rect2(Vector2.ZERO,studio.canvas.size))
	for y in 17:
		for x in 17:
			var at: Vector2=bounds.position+bounds.size*Vector2((x+.5)/17.0,(y+.5)/17.0)
			if studio.worlds[studio.mode].pick(at)==uid:return at
	return Vector2(-1,-1)
func masks(node: Node,result: Dictionary={}) -> Dictionary:
	if node is CollisionObject2D or node is CollisionObject3D:result[str(node.get_path())]=[node.collision_layer,node.collision_mask]
	for child in node.get_children():masks(child,result)
	return result
func key(code: int,shift: bool=false,ctrl: bool=false) -> void:
	var focus: Control=root.gui_get_focus_owner()
	if focus:focus.release_focus()
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.shift_pressed=shift;event.ctrl_pressed=ctrl;event.pressed=true;Input.parse_input_event(event)
	await settle();event.pressed=false;Input.parse_input_event(event);await settle()
func ui_review(mode: String,uid: String) -> void:
	for simple in [true,false]:
		studio.consumer_shell.set_active(simple,false)
		for size in [Vector2i(1480,900),Vector2i(960,640)]:
			root.size=size;studio.accessibility_settings.restore({"text_scale":1.5 if size.x==960 else 1.0,"high_contrast":size.x==960,"large_targets":size.x==960});await settle(14)
			studio.overlap_picker.choose(uid);studio._command("small_props_isolate",null);await settle(16)
			var tools: RefCounted=studio.small_prop_tools;var rect: Rect2=tools.panel.get_global_rect()
			check(Rect2(Vector2.ZERO,Vector2(size)).encloses(rect),"Temporary controls fit visible window: %s/%s/%s"%[mode,simple,size])
			check(tools.return_button.is_visible_in_tree() and rect.encloses(tools.return_button.get_global_rect()) and tools.return_button.size.y>=44,"Return is visible with keyboard focus and a usable target: %s/%s/%s"%[mode,simple,size])
			check(not studio.screen_bounds(uid).intersects(Rect2(rect.position-studio.canvas.global_position,rect.size)),"Selected prop clears the control bar: %s/%s/%s"%[mode,simple,size])
			check(studio.workspace_presets.focused and tools.panel.theme==studio.theme,"Temporary canvas uses current accessibility theme: %s/%s/%s"%[mode,simple,size])
			await capture("view_%s_%s_%d"%[mode,"simple" if simple else "precision",size.x])
			if size.x==960:await key(KEY_ESCAPE)
			else:
				tools.return_button.grab_focus();var event:=InputEventKey.new();event.keycode=KEY_SPACE;event.pressed=true;Input.parse_input_event(event);await settle();event.pressed=false;Input.parse_input_event(event);await settle()
			check(not tools.active and not studio.workspace_presets.focused,"Actual Escape/Space returns to original workspace: %s/%s/%s"%[mode,simple,size])
			if simple and size.x==960:
				check(Rect2(Vector2.ZERO,Vector2(size)).encloses(studio.consumer_shell.context_focus_actions.get_global_rect()),"Simple Magnify/Isolate actions fit enlarged compact selection card: "+mode)
				await capture("actions_"+mode)
	studio.accessibility_settings.restore({});studio.consumer_shell.set_active(true,false);root.size=Vector2i(1480,900);await settle()
func run() -> void:
	studio=load("res://scenes/builder.tscn").instantiate();studio.storage_enabled=false;root.add_child(studio);await settle(16)
	root.size=Vector2i(1480,900)
	for mode in ["2d","3d"]:
		studio.switch_mode(mode)
		var doc: RefCounted=Document.new();doc.data=Templates.make(mode,"blank");studio.documents[mode]=doc
		var asset: String="2d:Supplemental_Kitchen_cookware_kit_chef_knife_67e36712" if mode=="2d" else "3d:Fire_Station_PSX/bench_vise"
		var prop: Dictionary=doc.add(asset,[0,0,0],str(studio.library.directions(asset)[0]))
		var other: Dictionary=doc.add(asset,[20,0,0] if mode=="2d" else [1,0,0],prop["direction"])
		var hidden: Dictionary=doc.add(asset,[-20,0,0] if mode=="2d" else [-1,0,0],prop["direction"]);hidden["visible"]=false
		studio.changed();studio.worlds[mode].reset_camera("room");studio.overlap_picker.choose(prop["uid"]);await settle()
		var tools: RefCounted=studio.small_prop_tools;var world: Node=studio.worlds[mode];var original: Dictionary=doc.data.duplicate(true);var camera: Dictionary=tools.camera_state();var undo_count: int=doc.undo_history.size()
		studio.capture_workspace();var stored: Array=studio.workspace[mode]["camera"].duplicate()
		var before: Rect2=studio.screen_bounds(prop["uid"])
		var collision_masks: Dictionary=masks(world.objects,{})
		studio._command("small_props_magnify",null);await settle()
		var after: Rect2=studio.screen_bounds(prop["uid"])
		check(tools.active and world.detail_view_active,"Temporary view starts: "+mode)
		check(after.size.length()>before.size.length()*1.5,"Tiny source occupies more screen space without scaling: "+mode)
		check(doc.data==original and doc.undo_history.size()==undo_count,"Framing changes no authored data or history: "+mode)
		studio.capture_workspace();check(studio.workspace[mode]["camera"]==stored,"Saved workspace retains original camera: "+mode)
		tools.toggle_isolation();await settle()
		check(world.instances[prop["uid"]].is_visible_in_tree() and not world.instances[other["uid"]].visible and not world.instances[hidden["uid"]].visible,"Isolation affects presentation only: "+mode)
		world.apply(doc.data);await settle()
		check(not world.instances[other["uid"]].visible,"World refresh preserves active filter: "+mode)
		check(doc.data==original and doc.undo_history.size()==undo_count,"Isolation does not dirty authored state: "+mode)
		check(masks(world.objects,{})==collision_masks,"Isolation preserves authored physics masks: "+mode)
		var at: Vector2=hit(prop["uid"]);check(at.x>=0 and world.pick_all(at)==[prop["uid"]],"Only visible isolated selection is pickable: "+mode)
		await capture("detail_"+mode)
		studio._command("small_props_return",null);await settle()
		check(not tools.active and not world.detail_view_active and world.editor_focus.is_empty(),"Return clears temporary state: "+mode)
		check(world.instances[other["uid"]].visible and not world.instances[hidden["uid"]].visible,"Return restores authored visibility: "+mode)
		check(tools.camera_state()==camera,"Return restores exact camera: "+mode)
		check(doc.data==original and doc.undo_history.size()==undo_count,"Return preserves source data and history: "+mode)
		studio._command("small_props_isolate",null);await settle();studio.clear_placement();studio.selected_uid="";studio.selected_uids.clear();studio.refresh_controls();await settle()
		check(not tools.active and world.instances[other["uid"]].visible,"Clearing selection safely resets isolation: "+mode)
		await ui_review(mode,prop["uid"])
		studio.overlap_picker.choose(prop["uid"]);await key(KEY_F,true)
		check(tools.active,"Actual Shift+F magnifies selected prop: "+mode)
		tools.toggle_isolation();await settle()
		var controls: RefCounted=studio.control_settings;controls.cursor_active=true;controls.cursor_position=hit(prop["uid"]);studio.snap_input.set_pressed_no_signal(false);studio.transform_handles.set_mode("off")
		var original_position: Array=doc.object(prop["uid"])["position"].duplicate();var history: int=doc.undo_history.size()
		controls.execute("cursor_drag")
		for i in 5:controls.execute("cursor_fine_right")
		check(doc.object(prop["uid"])["position"]==original_position and doc.undo_history.size()==history,"High zoom retains six-pixel drag threshold: "+mode)
		for i in 20:controls.execute("cursor_fine_right")
		controls.execute("cursor_drag")
		check(doc.object(prop["uid"])["position"]!=original_position and doc.undo_history.size()==history+1,"Keyboard tiny-prop move is one normal transaction: "+mode)
		check(doc.object(prop["uid"])["scale"]==original["objects"][0]["scale"],"Magnified editing preserves actual source scale: "+mode)
		studio._command("undo",null);await settle();check(doc.object(prop["uid"])["position"]==original_position,"Undo restores exact tiny-prop position: "+mode)
		studio._command("redo",null);await settle();check(doc.object(prop["uid"])["position"]!=original_position,"Redo restores tiny-prop move: "+mode)
		studio._command("undo",null);tools.leave();controls.cursor_active=false
		studio.overlap_picker.choose(prop["uid"]);tools.begin(true,true);await settle();var view_data: Dictionary=doc.data.duplicate(true);var selection: Array=studio.selected_uids.duplicate();controls.cursor_active=true;controls.cursor_position=tools.panel.get_global_rect().get_center()-studio.canvas.global_position;controls.execute("cursor_click")
		check(tools.active and studio.selected_uids==selection and doc.data==view_data,"Keyboard canvas input cannot select or paint behind temporary controls: "+mode)
		check(tools.over_ui(tools.return_button.get_global_rect().get_center()),"Temporary control bar participates in overlay hit-testing: "+mode)
		controls.cursor_active=false;var click_at: Vector2=tools.return_button.get_global_rect().get_center();var motion:=InputEventMouseMotion.new();motion.position=click_at;motion.global_position=click_at;Input.parse_input_event(motion);await settle();var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.position=click_at;click.global_position=click_at;click.pressed=true;Input.parse_input_event(click);await settle();click.pressed=false;Input.parse_input_event(click);await settle()
		check(not tools.active and doc.data==view_data,"Actual pointer Return restores view without editing underneath: "+mode)
		tools.begin(true,true);await settle();studio.workspace_presets.focus_button.button_pressed=false;await settle();check(not tools.active and not studio.workspace_presets.focused and world.editor_focus.is_empty(),"Existing Exit focus button returns from temporary view as one action: "+mode)
		tools.begin(true,true);await settle();studio.consumer_shell.set_active(false,false);await settle();check(not tools.active and world.editor_focus.is_empty(),"Switching Simple/precision workspace restores the temporary view: "+mode);studio.consumer_shell.set_active(true,false);await settle()
		var member: String=other["uid"];doc.object(prop["uid"])["group"]="micro";doc.object(member)["group"]="micro";studio.changed();studio.selected_uid=prop["uid"];studio.selected_uids.assign([prop["uid"],member]);studio.refresh_controls()
		var grouped: Dictionary=doc.data.duplicate(true);history=doc.undo_history.size();tools.begin(true,true);await settle()
		check(tools.selected_ids().size()==2 and world.instances[prop["uid"]].visible and world.instances[member].visible,"Group framing and isolation retain all editable selected members: "+mode)
		check(doc.data==grouped and doc.undo_history.size()==history,"Group magnification preserves positions, scale and history: "+mode)
		doc.object(member)["locked"]=true;studio.changed();await settle();check(tools.selected_ids()==[prop["uid"]] and not world.instances[member].visible,"A newly locked group member cannot enter isolated editing: "+mode)
		tools.leave();doc.object(member).erase("locked");studio.changed();studio.overlap_picker.choose(prop["uid"]);tools.begin(true,true);await settle();studio.set_tool("color");await settle()
		check(not tools.active and world.instances[member].visible and not world.instances[hidden["uid"]].visible,"Changing to paint restores authored visibility before protected color picking: "+mode)
		studio.set_tool("select");studio.overlap_picker.choose(prop["uid"]);studio.workspace_presets.set_focus(true);tools.begin();await settle();tools.leave();check(studio.workspace_presets.focused,"Return preserves a pre-existing focused workspace: "+mode);studio.workspace_presets.set_focus(false)
		var binding_before: Dictionary=controls.bindings.duplicate(true);check(controls.assign("small_props_magnify",0,KEY_MASK_CTRL|KEY_MASK_SHIFT|KEY_M).is_empty(),"Magnify action supports remapping: "+mode)
		await key(KEY_F,true);check(not tools.active,"Removed magnify shortcut no longer starts temporary view: "+mode)
		await key(KEY_M,true,true);check(tools.active,"Actual remapped chord starts temporary view: "+mode);tools.leave();controls.bindings=binding_before
		var camera_before_photo: Dictionary=tools.camera_state();tools.begin(true,true);await settle();studio.photo_tools.start();await settle();check(not tools.active and world.exploration.photo.active,"Direct photo action exits isolation before starting capture view: "+mode);studio.photo_tools.stop();await settle()
		var photo_restored: bool=tools.camera_state()==camera_before_photo if mode=="3d" else world.camera.position==camera_before_photo["position"] and world.camera.zoom.is_equal_approx(camera_before_photo["zoom"])
		check(photo_restored,"Photo return restores ordinary editing camera (2D frame-height conversion uses float tolerance): "+mode)
	studio.free();await settle();print("Small prop view: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
