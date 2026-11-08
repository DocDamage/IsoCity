extends RefCounted

const Plan=preload("res://scripts/builder/floor_plan.gd")
const Entries=preload("res://scripts/builder/floor_entrances.gd")
var studio: Control
var button: Button
var dialog: AcceptDialog
var list: ItemList
var floor_choice: OptionButton
var view_choice: OptionButton
var source: Array[SpinBox]=[]
var arrival: Array[SpinBox]=[]
var custom_landing: CheckBox
var remove_button: Button
var walk_button: Button
var message: Label
var selected_uid: String=""
var stamp: int=0

func _init(owner_control: Control,parent: Node) -> void:
	studio=owner_control
	button=Button.new(); button.text="Exterior entrances…"; parent.add_child(button); button.pressed.connect(show)
	dialog=AcceptDialog.new(); dialog.title="Floor-specific exterior entrances"; dialog.min_size=Vector2i(500,360); studio.add_child(dialog)
	var scroll:=ScrollContainer.new(); scroll.custom_minimum_size=Vector2(450,280); scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; scroll.follow_focus=true; dialog.add_child(scroll)
	var column:=VBoxContainer.new(); column.size_flags_horizontal=Control.SIZE_EXPAND_FILL; column.add_theme_constant_override("separation",9); scroll.add_child(column)
	list=ItemList.new(); list.custom_minimum_size.y=85; column.add_child(list); list.item_selected.connect(func(index: int): load_record(str(list.get_item_metadata(index))))
	var fresh:=Button.new(); fresh.text="New exterior entrance"; column.add_child(fresh); fresh.pressed.connect(new_record)
	studio.label(column,"Interior floor",13); floor_choice=OptionButton.new(); floor_choice.clip_text=true; floor_choice.accessibility_name="Entrance floor"; column.add_child(floor_choice); floor_choice.item_selected.connect(func(_index: int): update_landing())
	studio.label(column,"Source sprite view",13); view_choice=OptionButton.new(); view_choice.accessibility_name="Entrance source view"; column.add_child(view_choice)
	var note: Label=studio.label(column,"Exterior standing position, in source metres before the building's rotation and scale. For sprites, X/depth use that view's footprint origin. Provide a clear approach and supporting balcony or stairs outside.",13); note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	for axis in ["Source X (m)","Source height (m)","Source depth / Z (m)"]: source.append(number_field(column,axis))
	custom_landing=CheckBox.new(); custom_landing.text="Choose an interior landing"; column.add_child(custom_landing); custom_landing.toggled.connect(func(_value: bool): update_landing())
	for axis in ["Room X","Room Y","Room Z"]: arrival.append(number_field(column,axis))
	var landing_note: Label=studio.label(column,"Without a custom landing, this entrance uses the selected room's EXIT position. In 2D, room X/Y use canvas pixels; in 3D, room X/Y/Z use metres local to the selected floor.",13); landing_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var apply:=Button.new(); apply.text="Apply exterior entrance"; column.add_child(apply); apply.pressed.connect(apply_record)
	remove_button=Button.new(); remove_button.text="Remove exterior entrance"; column.add_child(remove_button); remove_button.pressed.connect(remove_record)
	walk_button=Button.new(); walk_button.text="Walk from this entrance"; column.add_child(walk_button); walk_button.pressed.connect(walk_here)
	message=studio.label(column,"",13); message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART

func number_field(parent: Node,title: String) -> SpinBox:
	var row:=HBoxContainer.new(); parent.add_child(row); var label: Label=studio.label(row,title,13); label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var field:=SpinBox.new(); field.min_value=-4096; field.max_value=4096; field.step=.01; field.custom_minimum_size.x=125; field.accessibility_name=title; row.add_child(field); return field

func tools() -> RefCounted:
	return studio.interior_tools.floor_tools

func host() -> Dictionary:
	return studio.interior_tools.outer.object(studio.interior_tools.uid) if tools().active() else {}

func root_data() -> Dictionary:
	return tools().root_data()

func select_floor(uid: String) -> void:
	for index in floor_choice.item_count:
		if floor_choice.get_item_metadata(index)==uid: floor_choice.select(index); return

func refresh() -> void:
	if not tools().active(): dialog.hide(); stamp=0; return
	var definitions: Array=Plan.definitions(root_data()); var descriptor: Array=[]
	for floor in definitions: descriptor.append([floor["uid"],floor["name"],floor["height"]])
	var next: int=hash([descriptor,root_data().get("floor_entrances",[]),host()["asset"],host()["direction"]])
	if next==stamp: return
	stamp=next; list.clear()
	var selected_floor: String=str(floor_choice.get_item_metadata(floor_choice.selected)) if floor_choice.selected>=0 else studio.current().floor_uid
	floor_choice.clear()
	for floor in definitions:
		floor_choice.add_item("%s · %+.1f m"%[floor["name"],floor["height"]]); floor_choice.set_item_metadata(floor_choice.item_count-1,floor["uid"])
	select_floor(selected_floor)
	var sprite: bool=host()["asset"].begins_with("2d:"); view_choice.visible=sprite; view_choice.get_parent().get_child(view_choice.get_index()-1).visible=sprite
	view_choice.clear(); view_choice.add_item("All source views"); view_choice.set_item_metadata(0,"")
	if sprite:
		for view in studio.library.assets[host()["asset"]]["data"]["directions"]:
			view_choice.add_item(view); view_choice.set_item_metadata(view_choice.item_count-1,view)
	arrival[2].get_parent().visible=studio.mode=="3d"
	for index in 3:
		arrival[index].get_parent().get_child(0).text=(["Room X (px)","Room Y (px)","Room Z"][index] if studio.mode=="2d" else ["Room X (m)","Room height (m)","Room Z (m)"][index])
	for entry in root_data().get("floor_entrances",[]):
		list.add_item("%s · %s · (%.2f, %.2f, %.2f)"%[Entries.name_for(root_data(),entry["floor"]),entry.get("view","All views"),entry["position"][0],entry["position"][1],entry["position"][2]])
		list.set_item_metadata(list.item_count-1,entry["uid"])
		if entry["uid"]==selected_uid: list.select(list.item_count-1)
	remove_button.disabled=selected_uid.is_empty() or list.get_selected_items().is_empty(); walk_button.disabled=remove_button.disabled or host().has("missing_asset")

func show() -> void:
	refresh(); tools().dialog.hide(); message.text=""
	if selected_uid.is_empty(): new_record()
	else: load_record(selected_uid)
	dialog.popup_centered(Vector2i(540,470))

func update_landing() -> void:
	for field in arrival: field.editable=custom_landing.button_pressed
	if not tools().active() or floor_choice.selected<0 or custom_landing.button_pressed: return
	var point: Variant=Entries.landing(root_data(),{"floor":floor_choice.get_item_metadata(floor_choice.selected)},studio.mode)
	for index in 3: arrival[index].value=(point[index] if studio.mode=="3d" or index<2 else 0)

func new_record() -> void:
	selected_uid=""; list.deselect_all(); remove_button.disabled=true; walk_button.disabled=true; select_floor(studio.current().floor_uid)
	var item: Dictionary=host(); var profile: Dictionary=preload("res://scripts/builder/entrance_anchors.gd").profile(item,studio.library) if not item.has("missing_asset") else {}
	var raw: Array=profile.get("arrival",[0,0,0]); var sprite: bool=item["asset"].begins_with("2d:")
	source[0].value=raw[0]; source[1].value=0 if sprite else raw[1]; source[2].value=raw[1] if sprite else raw[2]
	for floor in Plan.definitions(root_data()):
		if floor["uid"]==studio.current().floor_uid: source[1].value+=float(floor["height"])
	view_choice.select(0)
	if sprite:
		for index in view_choice.item_count:
			if view_choice.get_item_metadata(index)==item["direction"]: view_choice.select(index)
	custom_landing.button_pressed=false; update_landing(); message.text=""

func load_record(uid: String) -> void:
	for entry in root_data().get("floor_entrances",[]):
		if entry["uid"]!=uid: continue
		selected_uid=uid; select_floor(entry["floor"])
		for index in list.item_count:
			if list.get_item_metadata(index)==uid: list.select(index)
		for index in 3: source[index].value=entry["position"][index]
		view_choice.select(0)
		if entry.has("view") and not range(view_choice.item_count).any(func(index: int)->bool:return view_choice.get_item_metadata(index)==entry["view"]):
			view_choice.add_item(entry["view"]+" (unavailable)"); view_choice.set_item_metadata(view_choice.item_count-1,entry["view"])
		for index in view_choice.item_count:
			if view_choice.get_item_metadata(index)==entry.get("view",""): view_choice.select(index)
		custom_landing.button_pressed=entry.has("arrival"); update_landing()
		if entry.has("arrival"):
			for index in 3: arrival[index].value=entry["arrival"][index]
		remove_button.disabled=false; walk_button.disabled=host().has("missing_asset"); return
	new_record()

func apply_record() -> void:
	if not tools().prepare() or floor_choice.selected<0: return
	if host().has("missing_asset"): message.text="Restore the building asset before authoring source entrance positions."; return
	var record: Dictionary={}
	for entry in root_data().get("floor_entrances",[]):
		if entry["uid"]==selected_uid: record=entry.duplicate(true)
	var uid: String=selected_uid if not selected_uid.is_empty() else "entry_"+str(Time.get_ticks_usec())+"_"+str(randi())
	record.merge({"uid":uid,"floor":floor_choice.get_item_metadata(floor_choice.selected),"position":[source[0].value,source[1].value,source[2].value]},true)
	if host()["asset"].begins_with("2d:") and view_choice.selected>0: record["view"]=view_choice.get_item_metadata(view_choice.selected)
	else: record.erase("view")
	if custom_landing.button_pressed: record["arrival"]=[arrival[0].value,arrival[1].value,arrival[2].value]
	else: record.erase("arrival")
	var result: Dictionary=Plan.put_record(root_data(),"floor_entrances",record)
	if not result["ok"]: message.text="Choose a valid floor and supported coordinates. A building supports up to 16 exterior entrances."; return
	selected_uid=uid; tools().commit(result,studio.current().floor_uid); refresh(); load_record(uid); message.text=tools().message.text

func remove_record() -> void:
	if selected_uid.is_empty() or not tools().prepare(): return
	tools().commit(Plan.remove_record(root_data(),"floor_entrances",selected_uid),studio.current().floor_uid)
	selected_uid=""; refresh(); new_record(); message.text="Removed exterior entrance. Undo restores it."

func walk_here() -> void:
	var record: Dictionary={}
	for entry in root_data().get("floor_entrances",[]):
		if entry["uid"]==selected_uid: record=entry.duplicate(true)
	if record.is_empty(): return
	var uid: String=studio.interior_tools.uid
	dialog.hide(); studio.interior_tools.leave()
	var item: Dictionary=studio.current().object(uid); var world: Node=studio.worlds[studio.mode]
	var point: Variant=Entries.outside(world.instances[uid],item,record,studio.mode,studio.library)
	studio.set_walking(true); world.player.teleport_to(point)
