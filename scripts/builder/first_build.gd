extends RefCounted

const PATH = "user://studio_first_build.json"
const STEPS = ["Place a bench","Select your bench","Rotate it","Undo the rotation","Save your build","Take a short walk","Return to Build"]
var studio: Control
var settings_path: String = PATH
var seen: bool = false
var completed: bool = false
var phase: int = -2 # Closed, introduction, then seven observed actions.
var guide_mode: String = ""
var document: RefCounted
var asset: String = ""
var uid: String = ""
var initial_ids: Dictionary = {}
var before_rotation: Array = []
var saved_path: String = ""
var walk_started: bool = false
var walk_start: Variant
var undo_was_rotated: bool = false
var reveal_pending: bool = false
var page: ScrollContainer
var heading: Label
var instructions: Label
var hint: Label
var primary: Button
var focus_button: Button
var restart_button: Button
var banner: HFlowContainer
var banner_text: Label
var banner_return: Button

func _init(host: Control) -> void:
	studio=host
	if studio.storage_enabled: restore_preferences(studio.Store.read_json(settings_path,{}))
	page=ScrollContainer.new(); page.name="First build"
	page.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; page.follow_focus=true
	studio.workspace_layout.tabs.add_child(page)
	var box:=VBoxContainer.new(); box.size_flags_horizontal=Control.SIZE_EXPAND_FILL; box.add_theme_constant_override("separation",12); page.add_child(box)
	heading=make_label(box,"",18)
	instructions=make_label(box,"",14)
	hint=make_label(box,"",12)
	primary=make_button(box,"Start guided build",act)
	focus_button=make_button(box,"Find my bench",frame_bench)
	restart_button=make_button(box,"Restart",begin)
	restart_button.tooltip_text="Start with another bench. Existing edits remain in normal undo history."
	make_button(box,"Close guide",close)
	var center: Node=studio.canvas.get_parent()
	banner=HFlowContainer.new(); banner.name="FirstBuildWalkPrompt"; center.add_child(banner); center.move_child(banner,1)
	banner_text=make_label(banner,"",14)
	banner_text.custom_minimum_size.x=240
	banner_text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	banner_return=make_button(banner,"Back to Build",func(): studio.set_walking(false))
	banner_return.custom_minimum_size.x=140
	banner.hide()
	studio.workspace_layout.tabs.set_tab_hidden(page.get_index(),true)
	studio.control_settings.dialog.add_button("Guided build…",false,"first_build")
	studio.control_settings.dialog.custom_action.connect(func(action: String):
		if action=="first_build": studio.control_settings.dialog.hide(); show())

func make_label(parent: Node,text: String,size: int) -> Label:
	var label: Label=studio.label(parent,text,size)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	return label

func make_button(parent: Node,text: String,callback: Callable) -> Button:
	var button:=Button.new(); button.text=text; button.clip_text=true
	parent.add_child(button); button.pressed.connect(callback)
	return button

func restore_preferences(value: Variant) -> void:
	var data: Dictionary=value if value is Dictionary else {}
	seen=data.get("seen",false) if data.get("seen",false) is bool else false
	completed=data.get("completed",false) if data.get("completed",false) is bool else false

func persist() -> void:
	if studio.storage_enabled: studio.Store.write_json(settings_path,{"seen":seen,"completed":completed})

func offer() -> void:
	if seen or studio.walking: return
	show()

func show() -> void:
	if phase==-2: phase=-1
	seen=true; persist()
	if studio.walking and not phase in [5,6]: studio.set_walking(false)
	studio.workspace_presets.set_focus(false)
	reveal()
	render()

func reveal() -> void:
	studio.workspace_layout.tabs.set_tab_hidden(page.get_index(),false)
	studio.workspace_layout.inspector_toggle.button_pressed=true
	studio.workspace_layout.tabs.current_tab=page.get_index()
	page.scroll_vertical=0
	call_deferred("bring_into_view")

func bring_into_view() -> void:
	if not is_instance_valid(studio) or phase==-2 or studio.walking or not is_instance_valid(page) or not page.is_visible_in_tree(): return
	if studio.accessibility_settings.root_scroll and studio.accessibility_settings.root_scroll.is_ancestor_of(page): studio.accessibility_settings.root_scroll.ensure_control_visible(page)

func close() -> void:
	phase=-2; document=null; uid=""
	banner.hide(); studio.workspace_layout.tabs.set_tab_hidden(page.get_index(),true)
	seen=true; persist()
	studio.status.text="Guide closed. Your edits remain available through normal Undo and Save."

func begin() -> void:
	if studio.interior_tools.editing():
		hint.text="Return to the city from room editing, then start the guided build."
		return
	studio.control_settings.finish_drag()
	studio.set_walking(false)
	guide_mode=studio.mode
	document=studio.current()
	asset="2d:Park_Bench" if guide_mode=="2d" else "3d:HanX_Park/Bench_Park"
	if not studio.library.assets.has(asset):
		hint.text="The guide's bench asset is unavailable. Repair or reinstall it before starting."
		return
	phase=0; uid=""; saved_path=""; walk_started=false
	studio.rotation_controls.choice.select(0)
	studio.rotation_step.set_value_no_signal(90)
	studio.arrange_tools.pivot_mode.select(0)
	remember_ids()
	seen=true; persist(); reveal(); choose_bench(); render()

func remember_ids() -> void:
	initial_ids.clear()
	for item in document.data["objects"]: initial_ids[item["uid"]]=true

func choose_bench() -> void:
	studio.select_asset(asset)
	studio.repeat_input.set_pressed_no_signal(false)
	reveal()

func pose(item: Dictionary) -> Array:
	return [item.get("direction",""),float(item.get("angle",0)),item.get("tilt",[0,0]).duplicate()]

func selected() -> bool:
	return studio.mode==guide_mode and studio.selected_uids.has(uid) and studio.selection_items().size()==1

func tick() -> void:
	if phase<0: return
	var previous: int=phase
	if not studio.documents.has(guide_mode) or studio.documents[guide_mode]!=document:
		close(); studio.status.text="Project changed. Reopen Guided build to start a new task."
		return
	if studio.mode!=guide_mode: render(); return
	if reveal_pending and not studio.walking: reveal_pending=false; reveal()
	if phase<7 and phase>0 and document.object(uid).is_empty():
		phase=0; uid=""; walk_started=false; remember_ids()
		studio.status.text="Your guide bench was removed. Choose the bench and place another to continue."
	if phase==1 and selected():
		before_rotation=pose(document.object(uid)); phase=2
	elif phase==2 and pose(document.object(uid))!=before_rotation and not (studio.transform_handles and studio.transform_handles.dragging):
		phase=3
	elif phase==5 and studio.walking:
		if not walk_started: on_walking(true)
		var player: Node=studio.worlds[guide_mode].player
		if player.position.distance_to(walk_start)>=(20.0 if guide_mode=="2d" else 0.8) and player.velocity.length()>0.01: phase=6
	if phase!=previous and not studio.walking: reveal()
	render()

func on_placed(item: Dictionary) -> void:
	if phase==0 and studio.mode==guide_mode and studio.current()==document and item["asset"]==asset and not initial_ids.has(item["uid"]):
		uid=item["uid"]; phase=1; reveal_pending=true; render()

func before_undo() -> void:
	undo_was_rotated=phase==3 and studio.mode==guide_mode and not document.object(uid).is_empty() and pose(document.object(uid))!=before_rotation

func on_undo() -> void:
	if undo_was_rotated and phase==3 and studio.mode==guide_mode and not document.object(uid).is_empty() and not document.redo_history.is_empty() and pose(document.object(uid))==before_rotation:
		phase=4; reveal(); render()
	undo_was_rotated=false

func on_saved(path: String) -> void:
	if phase==4 and studio.mode==guide_mode and studio.current()==document and not document.object(uid).is_empty():
		saved_path=path; phase=5; walk_started=false; render()

func on_walking(enabled: bool) -> void:
	if phase==-2 and not enabled and studio.storage_enabled and not seen: offer(); return
	if phase<0 or studio.mode!=guide_mode: return
	if phase==5:
		walk_started=enabled
		if enabled: walk_start=studio.worlds[guide_mode].player.position
	elif phase==6 and not enabled:
		phase=7; completed=true; persist(); reveal()
	render()

func project_loaded() -> void:
	if phase>=0:
		close(); studio.status.text="Project opened. Reopen Guided build to start a new task."

func frame_bench() -> void:
	if studio.mode!=guide_mode: studio.switch_mode(guide_mode)
	if not document or document.object(uid).is_empty(): return
	var position: Array=document.object(uid)["position"]
	if guide_mode=="2d":
		studio.worlds[guide_mode].camera.position=Vector2(position[0],position[1]-position[2]*8)
	else:
		studio.worlds[guide_mode].target=Vector3(position[0],position[1],position[2]); studio.worlds[guide_mode].distance=12
		studio.worlds[guide_mode].update_camera()

func act() -> void:
	if phase==-1: begin(); return
	if phase<0: return
	if studio.mode!=guide_mode:
		studio.switch_mode(guide_mode)
		if phase==0: choose_bench()
		reveal(); render(); return
	match phase:
		0: choose_bench()
		1: studio.set_tool("select")
		2:
			if selected(): studio._command("rotate",null)
			else: studio.set_tool("select")
		3: studio._command("undo",null)
		4: studio._command("save_as",null)
		5: studio.set_walking(true)
		6: studio.set_walking(false)
		7: close()
	if phase>=0 and not studio.walking: reveal()

func render() -> void:
	if phase==-2: return
	focus_button.visible=phase>=1 and phase<7
	restart_button.visible=phase>=0
	primary.disabled=false
	banner.visible=phase>=5 and phase<=6 and studio.walking and studio.mode==guide_mode
	if phase==-1:
		heading.text="Your first build"
		instructions.text="Add a bench to this city, select and rotate it, undo the rotation, save the project, then take a short walk. Each step uses the normal editor. You can close this guide at any time."
		hint.text="Start in either world. Existing objects stay in place, and your edits use normal undo history."
		primary.text="Start guided build"; return
	if studio.mode!=guide_mode:
		heading.text="Guide paused"
		instructions.text="This task belongs to the "+guide_mode.to_upper()+" world. Return there to continue from the same step."
		hint.text="You can keep working in this world or close the guide."
		primary.text="Return to "+guide_mode.to_upper(); return
	if phase==7:
		heading.text="First build complete"
		instructions.text="You placed and selected a bench, rotated it, undid the rotation, saved a project, explored and returned to Build. Keep building, or restart to practise with another bench."
		hint.text="Saved project: "+saved_path.get_file()
		primary.text="Finish guide"; return
	heading.text="%d / 7 · %s" % [phase+1,STEPS[phase]]
	var keys: RefCounted=studio.control_settings
	match phase:
		0:
			instructions.text="A bench is ready to place. Click an open spot on the canvas, or drag it from the library."
			hint.text="Keyboard: "+keys.label_for("cursor_toggle")+" enables the canvas cursor; "+keys.label_for("cursor_click")+" places the bench. Hidden or locked layers must be shown and unlocked in Layers."
			primary.text="Choose bench"
		1:
			instructions.text="Choose Select / move, then click the bench you just placed. The outliner and keyboard canvas cursor can select it too."
			hint.text="Find my bench centers the camera on your target. Select only this bench for the next step."
			primary.text="Select tool"
		2:
			instructions.text="Rotate the selected bench once. Watch its facing change on the canvas."
			hint.text="Use "+keys.label_for("rotate")+", the inspector's Rotate button, or Rotate bench below. Select your bench again if you selected something else."
			primary.text="Rotate bench" if selected() else "Select tool"
		3:
			instructions.text="Undo the rotation. Your bench should return to its previous facing."
			hint.text="Use Undo or "+keys.label_for("undo")+". Undo reverses one completed edit at a time."
			primary.text="Undo rotation"
		4:
			instructions.text="Save this build to a project file. Choose a location and filename in the save window."
			hint.text="Save project opens Save As. A successful normal Save ("+keys.label_for("save")+") also counts; cancelling or a failed save does not."
			primary.text="Save project…"
		5:
			instructions.text="Enter Walk, then move the character a short distance."
			hint.text="Use Walk around or "+keys.label_for("walk")+". Move with your Movement bindings in Controls."
			primary.text="Walk around"
		6:
			instructions.text="Your character moved. Return to Build to finish the task."
			hint.text="Use Back to Build or "+keys.label_for("walk")+". Building controls return when you leave Walk."
			primary.text="Back to Build"
	banner_text.text="Guide · Move a short distance, then return to Build." if phase==5 else "Guide · Walk complete. Return to Build to finish."
	banner_return.text="Back to Build"
