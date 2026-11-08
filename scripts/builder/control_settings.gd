extends RefCounted

# Bindings are user preferences, shared by both worlds, never city content.
const PATH = "user://studio_controls.json"
const CTRL = KEY_MASK_CTRL
const SHIFT = KEY_MASK_SHIFT
const ALT = KEY_MASK_ALT
const SPECS: Array = [
	["commands","Command palette","General",[CTRL|SHIFT|KEY_P]],
	["controls","Controls and shortcuts","General",[KEY_F1]],
	["accessibility","Accessibility settings","General",[KEY_F2]],
	["first_build","Guided first build","General",[KEY_F3]],
	["resident_activities","Resident interior activities","City life",[]],
	["asset_search","Search asset library","Canvas",[CTRL|KEY_F]],
	["focus_canvas","Toggle canvas focus","General",[KEY_F10]],
	["walk","Walk / return to Build","General",[KEY_TAB]],
	["cancel","Cancel / return to Build","General",[KEY_ESCAPE]],
	["save","Save project","Project",[CTRL|KEY_S]],
	["save_as","Save project as","Project",[CTRL|SHIFT|KEY_S]],
	["undo","Undo","Editing",[CTRL|KEY_Z]],
	["redo","Redo","Editing",[CTRL|KEY_Y]],
	["copy","Copy selection","Editing",[CTRL|KEY_C]],
	["paste","Paste selection","Editing",[CTRL|KEY_V]],
	["duplicate","Duplicate selection","Editing",[CTRL|KEY_D]],
	["remove","Remove selection","Editing",[KEY_DELETE]],
	["select_all","Select all editable objects","Editing",[CTRL|KEY_A]],
	["group","Group selection","Editing",[CTRL|KEY_G]],
	["ungroup","Ungroup selection","Editing",[CTRL|SHIFT|KEY_G]],
	["rotate","Rotate clockwise","Editing",[KEY_R]],
	["rotate_ccw","Rotate counterclockwise","Editing",[SHIFT|KEY_R]],
	["rotate_reset","Reset rotation","Editing",[ALT|KEY_R,ALT|SHIFT|KEY_R]],
	["handles_move","Move canvas handles","Canvas",[]],
	["handles_rotate","Rotate canvas handles","Canvas",[]],
	["handles_resize","Resize canvas handles","Canvas",[]],
	["handles_off","Hide canvas handles","Canvas",[]],
	["overlap_next","Next overlapping object","Editing",[KEY_PAGEDOWN]],
	["overlap_previous","Previous overlapping object","Editing",[KEY_PAGEUP]],
	["connector_next","Next connection target","Editing",[ALT|KEY_PAGEDOWN]],
	["connector_previous","Previous connection target","Editing",[ALT|KEY_PAGEUP]],
	["small_props_focus","Frame selected props","Editing",[KEY_F]],
	["small_props_magnify","Magnify selected props","Editing",[SHIFT|KEY_F]],
	["small_props_isolate","Isolate selection temporarily","Editing",[]],
	["small_props_return","Return to previous editing view","Editing",[]],
	["interact","Interact / enter / exit","Walking",[KEY_E]],
	["business","Business activity","Walking",[KEY_G]],
	["business_secondary","Second business activity","Walking",[SHIFT|KEY_G]],
	["business_cancel","Cancel business activity","Walking",[ALT|KEY_G]],
	["service_request","Request nearby city service","Walking",[KEY_V]],
	["service_type","Next city service type","Walking",[SHIFT|KEY_V]],
	["vehicle_service","Request vehicle care","Walking",[KEY_B]],
	["vehicle_service_cancel","Cancel vehicle care","Walking",[SHIFT|KEY_B]],
	["delivery_cargo","Load or unload delivery cargo","Walking",[KEY_H]],
	["delivery_cancel","Cancel local delivery","Walking",[SHIFT|KEY_H]],
	["jump","Jump (3D)","Walking",[KEY_SPACE]],
	["recover","Recover character","Walking",[KEY_X]],
	["ambience_mute","Mute / unmute ambience","General",[KEY_M]],
	["move_left","Move / pan left","Movement",[KEY_A,KEY_LEFT]],
	["move_right","Move / pan right","Movement",[KEY_D,KEY_RIGHT]],
	["move_up","Move / pan forward","Movement",[KEY_W,KEY_UP]],
	["move_down","Move / pan backward","Movement",[KEY_S,KEY_DOWN]],
	["cursor_toggle","Toggle keyboard canvas cursor","Canvas",[KEY_F6]],
	["cursor_left","Canvas cursor left","Canvas",[ALT|KEY_LEFT]],
	["cursor_right","Canvas cursor right","Canvas",[ALT|KEY_RIGHT]],
	["cursor_up","Canvas cursor up","Canvas",[ALT|KEY_UP]],
	["cursor_down","Canvas cursor down","Canvas",[ALT|KEY_DOWN]],
	["cursor_fine_left","Canvas cursor left by one pixel","Canvas",[ALT|SHIFT|KEY_LEFT]],
	["cursor_fine_right","Canvas cursor right by one pixel","Canvas",[ALT|SHIFT|KEY_RIGHT]],
	["cursor_fine_up","Canvas cursor up by one pixel","Canvas",[ALT|SHIFT|KEY_UP]],
	["cursor_fine_down","Canvas cursor down by one pixel","Canvas",[ALT|SHIFT|KEY_DOWN]],
	["cursor_click","Use tool at canvas cursor","Canvas",[KEY_F7]],
	["cursor_add","Add / remove at cursor selection","Canvas",[SHIFT|KEY_F7]],
	["cursor_drag","Start / finish canvas drag","Canvas",[KEY_F8]],
	["zoom_in","Zoom in","Camera",[KEY_EQUAL]],
	["zoom_out","Zoom out","Camera",[KEY_MINUS]],
	["orbit_left","Orbit camera left (3D)","Camera",[KEY_BRACKETLEFT]],
	["orbit_right","Orbit camera right (3D)","Camera",[KEY_BRACKETRIGHT]],
	["tilt_up","Tilt camera up (3D)","Camera",[CTRL|KEY_BRACKETLEFT]],
	["tilt_down","Tilt camera down (3D)","Camera",[CTRL|KEY_BRACKETRIGHT]],
	["home","Reset camera","Camera",[KEY_HOME]],
	["photo","Photo / normal camera","Camera",[KEY_P]],
	["photo_capture","Save clean screenshot","Camera",[KEY_F4]],
	["photo_record","Record / save camera path","Camera",[KEY_F5]]
]
const CONTINUOUS = ["move_left","move_right","move_up","move_down","jump","recover"]
var studio: Control
var settings_path: String = PATH
var bindings: Dictionary = {}
var dialog: AcceptDialog
var query: LineEdit
var rows: ItemList
var detail: Label
var notice: Label
var bind_buttons: Array[Button] = []
var visible_ids: Array[String] = []
var capturing: String = ""
var capture_slot: int = 0
var cursor_active: bool = false
var cursor_position: Vector2 = Vector2.ZERO
var dragging: bool = false
var synthetic_input: bool = false
var marker: Control

func _init(owner_control: Control) -> void:
	studio = owner_control
	reset_defaults(false)
	if studio.storage_enabled:
		var saved: Variant = studio.Store.read_json(PATH,{})
		restore(saved)
	build_dialog()
	marker = Control.new()
	marker.name = "KeyboardCanvasCursor"
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	studio.canvas.add_child(marker)
	marker.draw.connect(draw_cursor)
	var button := Button.new()
	button.text = "Controls"
	button.tooltip_text = "Search shortcuts, remap keys, and find keyboard canvas controls"
	studio.workspace_presets.choice.get_parent().add_child(button)
	button.pressed.connect(show)
	studio.search.text_submitted.connect(func(_text: String):
		for card in studio.cards.get_children():
			if card is Button:
				studio.search.release_focus()
				studio.select_asset(card.asset_id)
				return)
	for world in studio.worlds.values(): world.player.control_input = held

func default_bindings() -> Dictionary:
	var result: Dictionary = {}
	for spec in SPECS: result[spec[0]] = spec[3].duplicate()
	return result

func reset_defaults(save: bool = true) -> void:
	bindings = default_bindings()
	if save: persist(); refresh()

func restore(data: Variant) -> void:
	if not data is Dictionary: return
	# Validate the complete preference atomically; corrupt files keep working defaults.
	var candidate: Dictionary = default_bindings()
	for id in candidate:
		if not data.has(id): continue
		if not data[id] is Array or data[id].size()>2: return
		var keys: Array = []
		for value in data[id]:
			if not (value is int or value is float) or not is_finite(float(value)) or float(value)!=floor(float(value)): return
			var code: int = int(value)
			if not valid_code(code): return
			keys.append(code)
		candidate[id] = keys
	# Preserve shortcuts already claimed by older preference files.
	for id in ["delivery_cargo","delivery_cancel","connector_next","connector_previous"]:
		if data.has(id): continue
		var default_code: int=candidate[id][0]
		for action in candidate:
			if data.has(action) and default_code in candidate[action]:
				candidate[id]=[]
				break
	var seen: Array = []
	for id in candidate:
		for code in candidate[id]:
			if code in seen: return
			seen.append(code)
	bindings = candidate

func valid_code(code: int) -> bool:
	var key: int = code & KEY_CODE_MASK
	return code>0 and code<(1<<31) and key>0 and not key in [KEY_SHIFT,KEY_CTRL,KEY_ALT,KEY_META] and not OS.get_keycode_string(key).is_empty()

func persist() -> void:
	if studio.storage_enabled: studio.Store.write_json(settings_path,bindings)
	if studio.workspace_presets: studio.workspace_presets.refresh()
	if studio.command_palette: studio.command_palette.dialog.title="Commands · "+label_for("commands")
	refresh_mode_hint()
	refresh_button_hints(studio)
	studio.tools["select"].tooltip_text="Select and drag to move. Alt+click cycles stacked objects; Alt+Shift+click cycles back. Alt+right-click lists objects. "+label_for("overlap_next")+" / "+label_for("overlap_previous")+" cycle with the keyboard. Controls lists canvas cursor alternatives."

func refresh_button_hints(node: Node) -> void:
	if node is Button:
		var action: String=str(node.get_meta("editor_action",""))
		if bindings.has(action): node.tooltip_text=title_for(action)+" · "+label_for(action)
	for child in node.get_children(): refresh_button_hints(child)

func refresh_mode_hint() -> void:
	if not studio.mode_badge: return
	studio.mode_badge.text=("WALK MODE · "+label_for("move_up")+" move · "+(label_for("jump")+" jump · " if studio.mode=="3d" else "")+label_for("interact")+" interact · "+label_for("recover")+" recover · "+label_for("walk")+": Build") if studio.walking else "BUILD MODE · Place / select · "+label_for("walk")+" to walk"
	if not studio.walking and studio.tool=="zone": studio.mode_badge.text="BUILD MODE · Zoning · drag lots · "+label_for("walk")+" to walk"

func walk_hint(text: String) -> String:
	return text.replace("WASD",label_for("move_up")).replace("E ·",label_for("interact")+" ·").replace("E near",label_for("interact")+" near").replace("Tab to",label_for("walk")+" to").replace("Tab ·",label_for("walk")+" ·").replace("X ·",label_for("recover")+" ·").replace("Space brakes",label_for("jump")+" brakes")

func label_for(id: String) -> String:
	var names: PackedStringArray = []
	for code in bindings.get(id,[]): names.append(OS.get_keycode_string(int(code)))
	return " / ".join(names) if not names.is_empty() else "Unbound"

func title_for(id: String) -> String:
	for spec in SPECS:
		if spec[0]==id: return spec[1]
	return id

func assign(id: String,slot: int,code: int) -> String:
	if not bindings.has(id) or slot<0 or slot>1 or not valid_code(code): return "Choose a valid key combination."
	for other in bindings:
		for i in bindings[other].size():
			if int(bindings[other][i])==code and not (other==id and i==slot): return "Already used by "+title_for(other)+". Clear that binding first."
	var keys: Array = bindings[id].duplicate()
	if slot<keys.size(): keys[slot]=code
	else: keys.append(code)
	bindings[id]=keys
	persist()
	return ""

func clear_binding(id: String,slot: int) -> void:
	if not bindings.has(id) or slot>=bindings[id].size(): return
	bindings[id].remove_at(slot)
	persist()
	refresh()

func event_code(event: InputEventKey) -> int:
	var key: int = event.keycode if event.keycode else DisplayServer.keyboard_get_keycode_from_physical(event.physical_keycode)
	return key | (CTRL if event.ctrl_pressed else 0) | (SHIFT if event.shift_pressed else 0) | (ALT if event.alt_pressed else 0) | (KEY_MASK_META if event.meta_pressed else 0)

func match_event(event: InputEventKey) -> String:
	var code: int = event_code(event)
	for id in bindings:
		if code in bindings[id]: return id
	return ""

func held(id: String) -> bool:
	for value in bindings.get(id,[]):
		var code: int = int(value)
		if Input.is_key_pressed(code & KEY_CODE_MASK) and Input.is_key_pressed(KEY_CTRL)==bool(code & CTRL) and Input.is_key_pressed(KEY_SHIFT)==bool(code & SHIFT) and Input.is_key_pressed(KEY_ALT)==bool(code & ALT) and Input.is_key_pressed(KEY_META)==bool(code & KEY_MASK_META): return true
	return false

func driving_held(id: String) -> bool:
	return held(id) if not studio.modal_visible() and not text_focused() else false

func movement() -> Vector2:
	var focus: Control=studio.get_viewport().gui_get_focus_owner()
	if focus and studio.cards.is_ancestor_of(focus): return Vector2.ZERO
	return Vector2(float(held("move_right"))-float(held("move_left")),float(held("move_down"))-float(held("move_up")))

func text_focused() -> bool:
	var focus: Control = studio.get_viewport().gui_get_focus_owner()
	if studio.photo_tools and studio.photo_tools.dialog.visible:
		var photo_focus: Control=studio.photo_tools.dialog.gui_get_focus_owner()
		if photo_focus is LineEdit or photo_focus is TextEdit: return true
	return focus is LineEdit or focus is TextEdit

func input(event: InputEvent) -> bool:
	if not event is InputEventKey or not event.pressed: return false
	if not capturing.is_empty():
		if event.echo: return true
		if event.keycode==KEY_ESCAPE:
			capturing=""; notice.text="Binding unchanged."; return true
		if event.keycode in [KEY_SHIFT,KEY_CTRL,KEY_ALT,KEY_META]: return true
		var error: String = assign(capturing,capture_slot,event_code(event))
		if error.is_empty(): capturing=""; notice.text="Binding saved."; refresh()
		else: notice.text=error+" Press another key or Escape to cancel."
		return true
	if studio.modal_visible() or text_focused(): return false
	var id: String = match_event(event)
	if id=="walk" and event_code(event)==KEY_TAB and studio.get_viewport().gui_get_focus_owner(): return false
	if event.echo and not (id in ["cursor_left","cursor_right","cursor_up","cursor_down"] or id.begins_with("cursor_fine_")): return false
	if id in ["walk","commands","controls","accessibility","first_build","focus_canvas","asset_search","photo","photo_capture","photo_record","resident_activities"] or id.begins_with("cursor_"):
		execute(id)
		return true
	return false

func unhandled(event: InputEvent) -> bool:
	if not event is InputEventKey or not event.pressed or event.echo or studio.modal_visible() or text_focused(): return false
	var id: String = match_event(event)
	if id=="walk" and event_code(event)==KEY_TAB and studio.get_viewport().gui_get_focus_owner(): return false
	if id.is_empty() or id in CONTINUOUS: return false
	if studio.walking and not id in ["walk","cancel","interact","business","business_secondary","business_cancel","service_request","service_type","vehicle_service","vehicle_service_cancel","delivery_cargo","delivery_cancel","ambience_mute","save","save_as","home","zoom_in","zoom_out","orbit_left","orbit_right","tilt_up","tilt_down"]: return false
	execute(id)
	return true

func execute(id: String) -> void:
	if id.is_empty(): return
	if studio.worlds.has(studio.mode) and studio.worlds[studio.mode].exploration and studio.worlds[studio.mode].exploration.photo.action(id): return
	if dragging and not id.begins_with("cursor_"): finish_drag()
	match id:
		"small_props_focus","small_props_magnify","small_props_isolate","small_props_return","resident_activities":studio._command(id,null)
		"photo": studio.photo_tools.toggle()
		"photo_capture": studio.photo_tools.choose_screenshot()
		"photo_record": studio.photo_tools.record_toggle()
		"handles_move","handles_rotate","handles_resize","handles_off": studio._command("handles_mode",id.trim_prefix("handles_"))
		"asset_search":
			if studio.consumer_shell and studio.consumer_shell.active:
				studio.consumer_shell.open_drawer("build"); studio.consumer_shell.query.grab_focus(); studio.consumer_shell.query.select_all(); return
			if studio.walking: studio.set_walking(false)
			studio.workspace_presets.set_focus(false)
			studio.workspace_layout.library_toggle.button_pressed=true
			studio.search.grab_focus()
			studio.search.select_all()
		"controls": show()
		"cancel":
			if studio.worlds[studio.mode].exploration.photo.active: studio.photo_tools.stop(); return
			if studio.worlds[studio.mode].exploration.pet.close(): return
			if studio.worlds[studio.mode].exploration.village.close(): return
			if studio.worlds[studio.mode].exploration.camping.cancel_player(): return
			var fitness: Node=studio.worlds[studio.mode].exploration.fitness
			if not fitness.menu.is_empty(): fitness.close_view(); return
			var laundry: Node=studio.worlds[studio.mode].exploration.laundry
			if not laundry.counter.is_empty(): laundry.close_counter(); return
			if studio.terrain_tools and studio.terrain_tools.drawing: studio.terrain_tools.cancel(); return
			if studio.tool=="modular_room": studio.set_tool("select"); return
			if studio.transform_handles and studio.transform_handles.dragging: studio.transform_handles.cancel(); return
			if studio.small_prop_tools and studio.small_prop_tools.active:
				if dragging:finish_drag()
				studio.small_prop_tools.leave();return
			var focus: Control=studio.get_viewport().gui_get_focus_owner()
			if focus: focus.release_focus()
			if dragging: finish_drag()
			if studio.walking: studio.set_walking(false); return
			if studio.ground_brush.drawing: studio.ground_brush.finish(studio.ground_brush.last_pointer)
			studio.arrange_tools.picking_pivot=false
			studio.selected_uids.clear()
			studio.clear_assembly()
			studio.clear_placement()
		"interact":
			if studio.walking:
				var exploration: Node=studio.worlds[studio.mode].exploration
				if (exploration.driving and not exploration.driving.active.is_empty()) or (exploration.props and not exploration.props.active.is_empty()) or not studio.interior_tools.interact_exit(): exploration.interact()
		"business":
			if studio.walking and not studio.worlds[studio.mode].exploration.cycling.guide():
				studio.business_tools.managers[studio.mode].primary_action()
		"business_secondary":
			if studio.walking: studio.business_tools.managers[studio.mode].primary_action(1)
		"business_cancel":
			if studio.walking: studio.business_tools.managers[studio.mode].cancel_activity()
		"service_request":
			if studio.walking: studio.service_tools.managers[studio.mode].request_nearby()
		"service_type":
			if studio.walking: studio.service_tools.managers[studio.mode].cycle_request()
		"vehicle_service":
			if studio.walking: studio.worlds[studio.mode].exploration.driving.request_vehicle_service()
		"vehicle_service_cancel":
			if studio.walking: studio.worlds[studio.mode].exploration.driving.cancel_vehicle_service()
		"delivery_cargo":
			if studio.walking: studio.worlds[studio.mode].exploration.driving.request_delivery()
		"delivery_cancel":
			if studio.walking: studio.worlds[studio.mode].exploration.driving.cancel_delivery()
		"ambience_mute": studio.ambience_tools.toggle_mute()
		"copy": studio.copy_selection()
		"paste":
			if studio.clipboard_mode==studio.mode: studio.paste_objects(studio.clipboard,[16,8,0] if studio.mode=="2d" else [1,0,1],false,studio.clipboard_connections,studio.clipboard_utility)
		"select_all":
			studio.selected_uids.clear()
			for item in studio.current().data["objects"]:
				if studio.Layers.editable(studio.current().data,item,studio.library): studio.selected_uids.append(item["uid"])
			studio.selected_uid=studio.selected_uids[0] if not studio.selected_uids.is_empty() else ""
			studio.set_tool("select"); studio.refresh_controls()
		"overlap_previous": studio.overlap_picker.cycle(pointer(),-1)
		"overlap_next": studio.overlap_picker.cycle(pointer(),1)
		"connector_next": studio.cycle_connection(1)
		"connector_previous": studio.cycle_connection(-1)
		"cursor_toggle":
			var focus: Control=studio.get_viewport().gui_get_focus_owner()
			if focus: focus.release_focus()
			if dragging: finish_drag()
			cursor_active=not cursor_active
			if cursor_active: cursor_position=studio.canvas.size/2
			marker.queue_redraw()
		"cursor_left","cursor_right","cursor_up","cursor_down","cursor_fine_left","cursor_fine_right","cursor_fine_up","cursor_fine_down":
			if studio.walking: return
			ensure_cursor()
			var direction: String=id.trim_prefix("cursor_").trim_prefix("fine_")
			var shift: Vector2={"left":Vector2.LEFT,"right":Vector2.RIGHT,"up":Vector2.UP,"down":Vector2.DOWN}[direction]*(1 if id.begins_with("cursor_fine_") else 16)
			cursor_position=(cursor_position+shift).clamp(Vector2.ZERO,studio.canvas.size)
			if dragging:
				var motion:=InputEventMouseMotion.new()
				motion.position=cursor_position; motion.relative=shift; motion.button_mask=MOUSE_BUTTON_MASK_LEFT
				synthetic_input=true
				studio._canvas_input(motion)
				synthetic_input=false
			marker.queue_redraw()
		"cursor_click","cursor_add":
			if studio.walking: return
			ensure_cursor()
			if dragging: finish_drag(); return
			canvas_button(true,id=="cursor_add"); canvas_button(false,id=="cursor_add")
		"cursor_drag":
			if studio.walking: return
			ensure_cursor()
			if dragging: finish_drag()
			else: dragging=true; canvas_button(true)
			marker.queue_redraw()
		"zoom_in","zoom_out":
			var wheel:=InputEventMouseButton.new()
			wheel.pressed=true
			wheel.button_index=MOUSE_BUTTON_WHEEL_UP if id=="zoom_in" else MOUSE_BUTTON_WHEEL_DOWN
			studio._canvas_input(wheel)
		"orbit_left","orbit_right":
			if studio.mode=="3d": studio.worlds["3d"].yaw+=-15 if id=="orbit_left" else 15; studio.worlds["3d"].update_camera()
		"tilt_up","tilt_down":
			if studio.mode=="3d": studio.worlds["3d"].pitch=clampf(studio.worlds["3d"].pitch+(-5 if id=="tilt_up" else 5),15,80); studio.worlds["3d"].update_camera()
		_: studio._command(id,null)

func ensure_cursor() -> void:
	if not cursor_active: cursor_active=true; cursor_position=studio.canvas.size/2
	cursor_position=cursor_position.clamp(Vector2.ZERO,studio.canvas.size)
	marker.queue_redraw()

func pointer() -> Vector2:
	return cursor_position.clamp(Vector2.ZERO,studio.canvas.size) if cursor_active else studio.canvas.get_local_mouse_position()

func canvas_button(pressed: bool,additive: bool = false) -> void:
	var event:=InputEventMouseButton.new()
	event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed; event.position=cursor_position; event.shift_pressed=additive
	synthetic_input=true
	studio._canvas_input(event)
	synthetic_input=false

func finish_drag() -> void:
	if not dragging: return
	studio.finish_edit(cursor_position)
	dragging=false
	marker.queue_redraw()

func draw_cursor() -> void:
	if not cursor_active or studio.walking: return
	var at: Vector2 = cursor_position.clamp(Vector2.ZERO,studio.canvas.size)
	marker.draw_circle(at,10,Color.BLACK,false,5)
	marker.draw_circle(at,10,Color.WHITE,false,2)
	for delta in [Vector2(16,0),Vector2(0,16)]:
		marker.draw_line(at-delta,at+delta,Color.BLACK,5)
		marker.draw_line(at-delta,at+delta,Color.WHITE,2)
	var scale: float=studio.accessibility_settings.text_scale if studio.accessibility_settings else 1.0
	marker.draw_string(ThemeDB.fallback_font,at+Vector2(18,-16),"DRAG" if dragging else "KEYBOARD",HORIZONTAL_ALIGNMENT_LEFT,-1,roundi(14*scale),Color.WHITE)

func build_dialog() -> void:
	dialog=AcceptDialog.new(); dialog.title="Controls and shortcuts"; dialog.min_size=Vector2i(720,560); dialog.size=Vector2i(720,560)
	dialog.get_ok_button().text="Close"
	studio.add_child(dialog)
	var box:=VBoxContainer.new(); dialog.add_child(box)
	query=LineEdit.new(); query.placeholder_text="Search action, category, or key"; query.clear_button_enabled=true; box.add_child(query)
	rows=ItemList.new(); rows.custom_minimum_size=Vector2(670,190); rows.size_flags_vertical=Control.SIZE_EXPAND_FILL; box.add_child(rows)
	detail=Label.new(); detail.custom_minimum_size.x=670; detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; box.add_child(detail)
	var actions:=HFlowContainer.new(); box.add_child(actions)
	for slot in 2:
		var bind:=Button.new(); bind.text="Set key "+str(slot+1); actions.add_child(bind); bind_buttons.append(bind)
		bind.pressed.connect(func(): begin_capture(slot))
		var clear:=Button.new(); clear.text="Clear "+str(slot+1); actions.add_child(clear)
		clear.pressed.connect(func():
			var id: String=selected_id()
			if not id.is_empty(): clear_binding(id,slot))
	var run:=Button.new(); run.text="Run action"; actions.add_child(run)
	run.pressed.connect(func():
		var id: String=selected_id()
		if id in CONTINUOUS: notice.text="Hold a bound key to move, jump or recover."; return
		dialog.hide(); query.release_focus(); execute(id))
	var reset:=Button.new(); reset.text="Restore defaults"; actions.add_child(reset); reset.pressed.connect(func(): reset_defaults(); notice.text="Default bindings restored.")
	notice=Label.new(); notice.custom_minimum_size.x=670; notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; box.add_child(notice)
	var help:=RichTextLabel.new(); help.custom_minimum_size=Vector2(670,85)
	help.text="Keyboard canvas: toggle cursor, move it, use the current tool, or start a drag and move to its endpoint. Finish the drag with the same action. Works with object moves, roads and ground shapes. Use the outliner to select and the inspector to resize or edit precise positions. Tab navigates these controls while this window is open."
	box.add_child(help)
	query.text_changed.connect(func(_text: String): refresh())
	rows.item_selected.connect(func(_index: int): update_detail())
	dialog.visibility_changed.connect(func():
		if not dialog.visible: capturing="")

func selected_id() -> String:
	var selected: PackedInt32Array=rows.get_selected_items()
	return visible_ids[selected[0]] if not selected.is_empty() and selected[0]<visible_ids.size() else ""

func show() -> void:
	finish_drag()
	query.text=""; notice.text="Select an action to edit up to two bindings. Escape cancels key capture. Conflicts must be cleared first."
	refresh(); dialog.popup_centered(Vector2i(720,560)); query.grab_focus()

func refresh() -> void:
	if not rows: return
	var previous: String=selected_id()
	rows.clear(); visible_ids.clear()
	for spec in SPECS:
		var text: String=spec[2]+" · "+spec[1]+"    ["+label_for(spec[0])+"]"
		var include: bool=true
		for word in query.text.to_lower().split(" ",false):
			if not word in text.to_lower(): include=false; break
		if include: visible_ids.append(spec[0]); rows.add_item(text)
	if rows.item_count: rows.select(maxi(visible_ids.find(previous),0))
	update_detail()

func update_detail() -> void:
	var id: String=selected_id()
	detail.text=title_for(id)+" · "+label_for(id) if not id.is_empty() else "No matching shortcuts."
	for button in bind_buttons: button.disabled=id.is_empty()

func begin_capture(slot: int) -> void:
	capturing=selected_id(); capture_slot=slot
	if not capturing.is_empty(): notice.text="Press a key combination for "+title_for(capturing)+". Escape cancels."
