extends RefCounted

const Plan=preload("res://scripts/builder/floor_plan.gd")
var studio: Control
var row: HBoxContainer
var choice: OptionButton
var manage: Button
var dialog: AcceptDialog
var name_input: LineEdit
var height_input: SpinBox
var new_name: LineEdit
var new_height: SpinBox
var remove_button: Button
var message: Label
var stamp: String=""
var connections: RefCounted
var entrances: RefCounted

func _init(owner_control: Control,center: Node) -> void:
	studio=owner_control
	row=HBoxContainer.new(); center.add_child(row); center.move_child(row,2)
	studio.label(row,"Floor",13)
	choice=OptionButton.new(); choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL; choice.clip_text=true; row.add_child(choice)
	choice.item_selected.connect(func(index: int): switch_floor(str(choice.get_item_metadata(index))))
	manage=Button.new(); manage.text="Manage floors"; row.add_child(manage)
	manage.pressed.connect(func(): refresh_fields(); message.text=""; dialog.popup_centered(Vector2i(480,390)))
	dialog=AcceptDialog.new(); dialog.title="Building floors"; dialog.min_size=Vector2i(460,360); studio.add_child(dialog)
	var scroll:=ScrollContainer.new(); scroll.custom_minimum_size=Vector2(420,290); scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; dialog.add_child(scroll)
	var column:=VBoxContainer.new(); column.size_flags_horizontal=Control.SIZE_EXPAND_FILL; column.add_theme_constant_override("separation",10); scroll.add_child(column)
	studio.label(column,"Selected floor",16)
	name_input=LineEdit.new(); name_input.max_length=80; name_input.placeholder_text="Floor name"; name_input.accessibility_name="Selected floor name"; column.add_child(name_input)
	height_input=height_field(column,"Height above ground (m)")
	var apply:=Button.new(); apply.text="Apply name and height"; column.add_child(apply); apply.pressed.connect(update_floor)
	studio.label(column,"Add a floor",16)
	new_name=LineEdit.new(); new_name.max_length=80; new_name.placeholder_text="New floor name"; new_name.accessibility_name="New floor name"; column.add_child(new_name)
	new_height=height_field(column,"New floor height (m)")
	var add:=Button.new(); add.text="Add floor"; column.add_child(add); add.pressed.connect(add_floor)
	remove_button=Button.new(); remove_button.text="Remove selected floor and its contents"; remove_button.tooltip_text="Undo restores the room, its contents, connections and entrances."; column.add_child(remove_button); remove_button.pressed.connect(remove_floor)
	message=studio.label(column,"",13); message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	entrances=load("res://scripts/builder/floor_entrance_tools.gd").new(studio,column)
	connections=load("res://scripts/builder/floor_connection_tools.gd").new(studio,row)
	row.visible=false

func height_field(parent: Node,title: String) -> SpinBox:
	var line:=HBoxContainer.new(); parent.add_child(line)
	var label: Label=studio.label(line,title,13); label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var field:=SpinBox.new(); field.min_value=-24; field.max_value=32; field.step=0.1; field.custom_minimum_size.x=110; field.accessibility_name=title; line.add_child(field)
	return field

func active() -> bool:
	return studio.interior_tools!=null and studio.interior_tools.editing()

func root_data() -> Dictionary:
	return studio.current().canonical.data if active() else {}

func refresh() -> void:
	if connections: connections.refresh()
	if entrances: entrances.refresh()
	row.visible=active() and not studio.walking
	if not active():
		stamp=""
		if dialog.visible: dialog.hide()
		return
	var definitions: Array=Plan.definitions(root_data()); var next: String=studio.current().floor_uid
	for floor in definitions: next+="|"+str([floor["uid"],floor["name"],floor["height"]])
	if next==stamp: return
	stamp=next; choice.clear()
	for floor in definitions:
		choice.add_item("%s · %+.1f m"%[floor["name"],floor["height"]]); choice.set_item_metadata(choice.item_count-1,floor["uid"])
		if floor["uid"]==studio.current().floor_uid: choice.select(choice.item_count-1)
	if dialog.visible: refresh_fields()

func refresh_fields() -> void:
	if not active(): return
	for floor in Plan.definitions(root_data()):
		if floor["uid"]==studio.current().floor_uid: name_input.text=floor["name"]; height_input.value=float(floor["height"])
	height_input.editable=studio.current().floor_uid!="ground"
	remove_button.disabled=studio.current().floor_uid=="ground"
	new_name.text="Floor "+str(root_data().get("floors",[]).size()+2)
	var highest: float=0
	for floor in root_data().get("floors",[]): highest=maxf(highest,float(floor["height"]))
	new_height.value=minf(32,highest+3)

func prepare() -> bool:
	if not active(): return false
	if "small_prop_tools" in studio and studio.small_prop_tools:studio.small_prop_tools.leave()
	studio.finish_edit(studio.canvas.get_local_mouse_position()); studio.set_walking(false)
	studio.current().finish_checkpoint()
	return true

func present() -> void:
	studio.interior_tools.clear_selection()
	studio.worlds[studio.mode].apply(studio.current().data)
	studio.worlds[studio.mode].reset_camera("room")
	studio.worlds[studio.mode].player.teleport_to(studio.interior_tools.exit_point())
	studio.changed(); studio.interior_tools.refresh(); refresh()

func switch_floor(uid: String) -> void:
	if not prepare() or not studio.current().switch_floor(uid): return
	present()

func commit(result: Dictionary,selected: String) -> void:
	if not result["ok"]: message.text=result["error"]; return
	if not result.get("changed",true): message.text="No changes."; return
	var previous_redo: Array=studio.current().redo_history.duplicate(true)
	var history_size: int=studio.current().undo_history.size()
	studio.current().replace_plan(result["data"],selected)
	present()
	if not is_same(root_data(),result["data"]):
		if studio.current().undo_history.size()>history_size: studio.current().undo_history.pop_back()
		studio.current().redo_history.assign(previous_redo)
		message.text=studio.interior_tools.outer.economy_error
		studio.refresh_controls()
		return
	message.text="Saved floor changes. Undo restores the previous state."

func update_floor() -> void:
	if not prepare(): return
	var selected: String=studio.current().floor_uid
	if selected=="ground":
		var copy: Dictionary=root_data().duplicate(true); copy["floor_name"]=name_input.text.strip_edges()
		commit(Plan.result(root_data(),copy),selected)
	else:
		for floor in root_data().get("floors",[]):
			if floor["uid"]!=selected: continue
			var copy: Dictionary=floor.duplicate(true); copy["name"]=name_input.text.strip_edges(); copy["height"]=height_input.value
			commit(Plan.put_floor(root_data(),copy),selected); return

func add_floor() -> void:
	if not prepare(): return
	var uid: String="floor_"+str(Time.get_ticks_usec())+"_"+str(randi())
	var room: Dictionary=preload("res://scripts/builder/interiors.gd").make(studio.mode,new_name.text.strip_edges())
	room["objects"]=[]; room["roads"]=[]
	var floor: Dictionary={"uid":uid,"name":new_name.text.strip_edges(),"height":new_height.value,"room":room}
	commit(Plan.put_floor(root_data(),floor),uid)

func remove_floor() -> void:
	if not prepare(): return
	commit(Plan.remove_floor(root_data(),studio.current().floor_uid),"ground")
