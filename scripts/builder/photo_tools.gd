extends RefCounted
const Plan=preload("res://scripts/builder/photo_plan.gd")
var studio: Control
var dialog: AcceptDialog
var scroll: ScrollContainer
var file: FileDialog
var name_field: LineEdit
var status: Label
var dof: CheckButton
var hide_avatar: CheckButton
var fields: Dictionary={}
var rows: Dictionary={}
var bookmarks: ItemList
var paths: ItemList
var record_button: Button
var dirty: Dictionary={}
var loading: bool=false
var elapsed: float=0
var stamp: int=0
var settings_stamp: int=0
var overlay_visibility: Variant=null
func _init(owner_control: Control) -> void:
	studio=owner_control; dialog=AcceptDialog.new(); dialog.title="Photo and cinematic mode"; dialog.min_size=Vector2i(390,420); dialog.exclusive=false; dialog.get_ok_button().text="Return to normal camera"; studio.add_child(dialog)
	dialog.confirmed.connect(stop); dialog.canceled.connect(stop); dialog.close_requested.connect(stop)
	dialog.window_input.connect(window_input)
	scroll=ScrollContainer.new(); scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; scroll.follow_focus=true; scroll.custom_minimum_size=Vector2(410,520); dialog.add_child(scroll)
	var box:=VBoxContainer.new(); box.size_flags_horizontal=Control.SIZE_EXPAND_FILL; box.add_theme_constant_override("separation",8); scroll.add_child(box)
	status=studio.label(box,"Free camera",12); status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var help: Label=studio.label(box,"Use movement and camera shortcuts, or right-drag to look in 3D / pan in 2D and wheel to zoom. Jump / Recover raise and lower a 3D camera. The photo shortcut returns. Screenshots retain the scene and weather while removing annotations.",12); help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	dof=CheckButton.new(); box.add_child(dof); dof.toggled.connect(func(value: bool):mark("dof_enabled",value))
	hide_avatar=CheckButton.new(); hide_avatar.text="Hide avatar"; box.add_child(hide_avatar); hide_avatar.toggled.connect(func(value: bool):mark("hide_avatar",value))
	for spec in [["focus_distance","Focus distance",.1,500,.5],["focus_range","Focus range",.1,100,.5],["focus_band","Focus band · 2D",0,1,.05],["band_width","Band width · 2D",.05,1,.05],["blur","Blur amount",0,1,.05],["move_speed","Camera speed",.5,40,.5]]:
		var row:=VBoxContainer.new(); box.add_child(row); studio.label(row,spec[1],12); rows[spec[0]]=row
		var field:=SpinBox.new(); field.min_value=spec[2]; field.max_value=spec[3]; field.step=spec[4]; field.accessibility_name=spec[1]; row.add_child(field); fields[spec[0]]=field
		var key: String=spec[0]; field.value_changed.connect(func(value: float):mark(key,value))
	button(box,"Apply camera settings",apply_settings); button(box,"Save clean screenshot…",choose_screenshot)
	name_field=LineEdit.new(); name_field.placeholder_text="Bookmark or take name"; name_field.accessibility_name="Camera bookmark or recording name"; name_field.max_length=120; box.add_child(name_field)
	bookmarks=ItemList.new(); bookmarks.custom_minimum_size.y=100; bookmarks.accessibility_name="Camera bookmarks in this location"; box.add_child(bookmarks); bookmarks.item_activated.connect(func(_index: int):recall())
	button(box,"Save camera bookmark",save_bookmark); button(box,"Recall selected bookmark",recall); button(box,"Remove selected bookmark",remove_bookmark)
	paths=ItemList.new(); paths.custom_minimum_size.y=100; paths.accessibility_name="Recorded camera paths in this location"; box.add_child(paths)
	record_button=button(box,"Record camera path",record_toggle); button(box,"Play selected path",func():play(false)); button(box,"Loop selected path",func():play(true)); button(box,"Stop path playback",func():runtime().playing=[]); button(box,"Remove selected path",remove_path)
	button(box,"Discard unsaved take",func():runtime().stop_recording(); runtime().recorded=[]; runtime().pending_take=false; refresh_status())
	button(box,"Hide controls",func():dialog.hide())
	file=FileDialog.new(); file.file_mode=FileDialog.FILE_MODE_SAVE_FILE; file.access=FileDialog.ACCESS_FILESYSTEM; file.filters=PackedStringArray(["*.png ; PNG image"]); file.title="Save clean city screenshot"; studio.add_child(file)
	file.file_selected.connect(func(path: String):await save_screenshot(path))
func button(parent: Node,title: String,callback: Callable) -> Button:
	var control:=Button.new(); control.text=title; control.clip_text=true; control.custom_minimum_size.y=36; parent.add_child(control); control.pressed.connect(callback); return control
func runtime() -> Node: return studio.worlds[studio.mode].exploration.photo
func target() -> Dictionary:
	var exploration: Node=studio.worlds[studio.mode].exploration
	if exploration.interior: return {"doc":studio.interior_tools.root_document(studio.mode),"data":preload("res://scripts/builder/floor_plan.gd").room(exploration.owned_room,exploration.active_floor())}
	return {"doc":studio.current(),"data":studio.current().data}
func can_input() -> bool:
	return not file.visible and not studio.modal_visible() and not studio.control_settings.text_focused()
func window_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or studio.control_settings.text_focused(): return
	var action: String=studio.control_settings.match_event(event)
	if action in ["photo","photo_capture","photo_record"]: studio.control_settings.execute(action); dialog.set_input_as_handled()
	elif runtime().action(action): dialog.set_input_as_handled()
func release_focus() -> void:
	var focus: Control=dialog.gui_get_focus_owner()
	if focus: focus.release_focus()
func start() -> void:
	if studio.small_prop_tools:studio.small_prop_tools.leave()
	studio.finish_edit(studio.canvas_pointer())
	if not runtime().start(): return
	if overlay_visibility==null: overlay_visibility=studio.overlay.visible; studio.overlay.hide()
	if studio.simulation_diagnostic_tools: studio.simulation_diagnostic_tools.overlay.hide()
	stamp=0; settings_stamp=hash(focus_settings(Plan.settings(target()["data"]))); refresh()
func show() -> void:
	if not runtime().active: start()
	var size: Vector2i=Vector2i(studio.get_viewport_rect().size)
	scroll.custom_minimum_size=Vector2(mini(430,size.x-60),mini(620,size.y-120)); dialog.popup_centered(Vector2i(mini(470,size.x-40),mini(740,size.y-40)))
	dialog.position=Vector2i(maxi(10,size.x-dialog.size.x-20),maxi(10,(size.y-dialog.size.y)/2))
func toggle() -> void:
	if runtime().active: stop()
	else: show()
func stop() -> void:
	runtime().stop(); dialog.hide(); dirty.clear()
	if overlay_visibility!=null: studio.overlay.visible=overlay_visibility; overlay_visibility=null
func mark(key: String,value: Variant) -> void:
	if loading: return
	dirty[key]=value
	if runtime().active: runtime().configure({key:value})
func focus_settings(config: Dictionary) -> Dictionary:
	var result: Dictionary={}
	for key in ["dof_enabled","hide_avatar","focus_distance","focus_range","blur","focus_band","band_width","move_speed"]: result[key]=config[key]
	return result
func commit(photo: Dictionary) -> bool:
	var context: Dictionary=target()
	if context["data"].get("photo",{})==photo: return true
	context["doc"].checkpoint(); context["data"]["photo"]=photo; context["doc"].finish_checkpoint(); studio.changed(); stamp=0
	settings_stamp=hash(focus_settings(Plan.settings(context["data"]))); refresh()
	return true
func apply_settings() -> void:
	if dirty.is_empty(): return
	var photo: Dictionary=target()["data"].get("photo",{}).duplicate(true)
	for key in dirty: photo[key]=dirty[key]
	if commit(photo): dirty.clear(); studio.status.text="Camera settings saved."
	else: studio.status.text=runtime().notice
func named(fallback: String) -> String:
	return name_field.text.strip_edges() if not name_field.text.strip_edges().is_empty() else fallback
func uid(prefix: String) -> String: return prefix+str(Time.get_ticks_usec())
func save_bookmark() -> void:
	if not runtime().active: start()
	var photo: Dictionary=target()["data"].get("photo",{}).duplicate(true); var entries: Array=photo.get("bookmarks",[]).duplicate(true)
	if entries.size()>=Plan.MAX_BOOKMARKS: status.text="Bookmark limit reached. Remove one to save another."; return
	entries.append({"uid":uid("camera_"),"name":named("Camera "+str(entries.size()+1)),"view":runtime().capture_view()}); photo["bookmarks"]=entries; commit(photo)
func selected(list: ItemList,key: String) -> Dictionary:
	var indices: PackedInt32Array=list.get_selected_items()
	if indices.is_empty(): return {}
	var id: String=list.get_item_metadata(indices[0])
	for entry in Plan.settings(target()["data"])[key]:
		if entry["uid"]==id: return entry
	return {}
func recall() -> void:
	var entry: Dictionary=selected(bookmarks,"bookmarks")
	if entry.is_empty(): return
	if not runtime().active: start()
	runtime().playing=[]; runtime().apply_view(entry["view"]); stamp=0; refresh()
func remove(list: ItemList,key: String) -> void:
	var entry: Dictionary=selected(list,key)
	if entry.is_empty(): return
	var photo: Dictionary=target()["data"].get("photo",{}).duplicate(true); photo[key]=photo.get(key,[]).filter(func(value: Dictionary)->bool:return value["uid"]!=entry["uid"]); commit(photo)
func remove_bookmark() -> void: remove(bookmarks,"bookmarks")
func remove_path() -> void: remove(paths,"paths")
func record_toggle() -> void:
	if runtime().recording or runtime().pending_take:
		if runtime().record_scope!=preload("res://scripts/builder/prop_plan.gd").scope(studio.worlds[studio.mode].exploration): status.text="Return to the recorded location to save this take, or discard it."; return
		var samples: Array=runtime().stop_recording(); var photo: Dictionary=target()["data"].get("photo",{}).duplicate(true); var entries: Array=photo.get("paths",[]).duplicate(true)
		if samples.size()<2: return
		if entries.size()>=Plan.MAX_PATHS: status.text="Recording limit reached. Remove a path to save this take."; return
		entries.append({"uid":uid("take_"),"name":named("Take "+str(entries.size()+1)),"samples":samples.duplicate(true)}); photo["paths"]=entries
		if commit(photo): runtime().pending_take=false; runtime().notice=""
	else:
		if not runtime().active: start()
		runtime().start_recording()
	refresh_status()
func play(repeat: bool) -> void:
	var entry: Dictionary=selected(paths,"paths")
	if not entry.is_empty(): runtime().play(entry,repeat); stamp=0; refresh()
func choose_screenshot() -> void:
	if not runtime().active: start()
	file.current_file="city-photo.png"; file.popup_centered_ratio(.7)
func save_screenshot(path: String) -> void:
	var result: Error=await runtime().screenshot(path); studio.status.text="Saved clean screenshot: "+path if result==OK else runtime().notice
func populate(list: ItemList,entries: Array,path: bool=false) -> void:
	var indices: PackedInt32Array=list.get_selected_items(); var id: String=list.get_item_metadata(indices[0]) if not indices.is_empty() else ""
	list.clear()
	for entry in entries:
		var text: String=entry["name"]+(" · %.1fs"%float(entry["samples"][-1]["time"]) if path else ""); list.add_item(text); list.set_item_metadata(list.item_count-1,entry["uid"]); list.set_item_tooltip(list.item_count-1,text)
		if entry["uid"]==id: list.select(list.item_count-1)
func refresh_status() -> void:
	var photo: Node=runtime()
	record_button.text="Stop and save camera path" if photo.recording else ("Save recorded take" if photo.pending_take else "Record camera path")
	status.text=("Recording · %.1fs"%photo.record_elapsed if photo.recording else ("Playing camera path" if not photo.playing.is_empty() else ("Photo mode · "+str(target()["data"].get("title","Current location")) if photo.active else "Normal camera")))+("\n"+photo.notice if not photo.notice.is_empty() else "")
func refresh() -> void:
	var photo: Node=runtime(); var stored: Dictionary=Plan.settings(target()["data"]); var next: int=hash([studio.mode,photo.scope,target()["data"].get("photo",{})])
	if next==stamp: refresh_status(); return
	stamp=next; loading=true; var config: Dictionary=photo.config if photo.active else stored
	dof.text="Depth of field · 3D" if studio.mode=="3d" else "Focus band blur · 2D"
	dof.disabled=studio.mode=="3d" and RenderingServer.get_current_rendering_method()=="gl_compatibility"
	dof.tooltip_text="Depth of field requires Forward+ or Mobile rendering. Open project.godot in Godot to change the renderer." if dof.disabled else ""
	dof.set_pressed_no_signal(config.get("dof_enabled",false)); hide_avatar.set_pressed_no_signal(config.get("hide_avatar",false))
	for key in fields: fields[key].set_value_no_signal(config.get(key,Plan.defaults()[key]))
	for key in ["focus_distance","focus_range"]: rows[key].visible=studio.mode=="3d"
	for key in ["focus_band","band_width"]: rows[key].visible=studio.mode=="2d"
	populate(bookmarks,stored["bookmarks"]); populate(paths,stored["paths"],true); loading=false; refresh_status()
func tick(delta: float) -> void:
	elapsed+=delta
	if elapsed<.15: return
	elapsed=0
	if not studio.worlds.has(studio.mode): return
	if not runtime().active and overlay_visibility!=null: studio.overlay.visible=overlay_visibility; overlay_visibility=null
	var config: Dictionary=Plan.settings(target()["data"]); var next: int=hash(focus_settings(config))
	if settings_stamp==0: settings_stamp=next
	elif runtime().active and next!=settings_stamp: runtime().configure(focus_settings(config)); settings_stamp=next; stamp=0
	if dialog.visible: refresh()
