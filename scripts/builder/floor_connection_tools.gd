extends RefCounted

const Plan=preload("res://scripts/builder/floor_plan.gd")
var studio: Control
var button: Button
var dialog: AcceptDialog
var list: ItemList
var lower: OptionButton
var upper: OptionButton
var width: SpinBox
var start_x: SpinBox
var start_z: SpinBox
var end_x: SpinBox
var end_z: SpinBox
var remove_button: Button
var message: Label
var selected_uid: String=""
var stamp: int=0
var kind: OptionButton
var apply_button: Button
var help: Label
var fresh_button: Button

func _init(owner_control: Control,row: Node) -> void:
	studio=owner_control
	button=Button.new(); button.text="Connections"; button.tooltip_text="Connect floors with stairs or an elevator."; row.add_child(button)
	button.pressed.connect(show)
	dialog=AcceptDialog.new(); dialog.title="Floor connections"; dialog.min_size=Vector2i(520,370); studio.add_child(dialog)
	var scroll:=ScrollContainer.new(); scroll.custom_minimum_size=Vector2(480,290); scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; dialog.add_child(scroll)
	var column:=VBoxContainer.new(); column.size_flags_horizontal=Control.SIZE_EXPAND_FILL; column.add_theme_constant_override("separation",9); scroll.add_child(column)
	list=ItemList.new(); list.custom_minimum_size.y=90; column.add_child(list); list.item_selected.connect(func(index: int): load_record(str(list.get_item_metadata(index))))
	fresh_button=Button.new(); column.add_child(fresh_button); fresh_button.pressed.connect(new_record)
	kind=OptionButton.new(); kind.add_item("Stairs"); kind.add_item("Elevator"); kind.accessibility_name="Connection type"; column.add_child(kind); kind.item_selected.connect(update_kind)
	lower=floor_field(column,"Lower floor"); upper=floor_field(column,"Upper floor")
	start_x=number_field(column,"Start X (m)",-64,64,0.25); start_z=number_field(column,"Start Z (m)",-64,64,0.25)
	end_x=number_field(column,"End X (m)",-64,64,0.25); end_z=number_field(column,"End Z (m)",-64,64,0.25)
	width=number_field(column,"Clear width (m)",0.8,4,0.1)
	help=studio.label(column,"",13); help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	apply_button=Button.new(); column.add_child(apply_button); apply_button.pressed.connect(apply_record)
	remove_button=Button.new(); remove_button.text="Remove staircase"; column.add_child(remove_button); remove_button.pressed.connect(remove_record)
	message=studio.label(column,"",13); message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	start_x.value_changed.connect(func(_value: float): synchronize_shaft()); start_z.value_changed.connect(func(_value: float): synchronize_shaft()); update_kind()

func synchronize_shaft() -> void:
	if kind.selected==1: end_x.value=start_x.value; end_z.value=start_z.value

func update_kind(_index: int=0) -> void:
	var lift: bool=kind.selected==1
	var unit: String="cells" if studio.mode=="2d" else "m"
	end_x.get_parent().visible=not lift; end_z.get_parent().visible=not lift
	start_x.get_parent().get_child(0).text=("Shaft X" if lift else "Start X")+" ("+unit+")"
	start_z.get_parent().get_child(0).text=("Shaft Z" if lift else "Start Z")+" ("+unit+")"
	end_x.get_parent().get_child(0).text="End X ("+unit+")"; end_z.get_parent().get_child(0).text="End Z ("+unit+")"; width.get_parent().get_child(0).text="Clear width ("+unit+")"
	apply_button.text="Apply elevator" if lift else "Apply staircase"; remove_button.text="Remove elevator" if lift else "Remove staircase"
	fresh_button.text="New elevator" if lift else "New staircase"
	help.text=("Every floor between the endpoints gets a gated landing. Walk into the cabin and press E to choose a floor. " if lift else "Keep the flight and both landings clear. ")+("X/Z and width use room grid cells in 2D; heights use metres. " if studio.mode=="2d" else "Coordinates and widths use metres. ")+"Keep water, raised ground and objects away from exits."
	synchronize_shaft()

func floor_field(parent: Node,title: String) -> OptionButton:
	studio.label(parent,title,13)
	var field:=OptionButton.new(); field.accessibility_name=title; field.size_flags_horizontal=Control.SIZE_EXPAND_FILL; field.clip_text=true; parent.add_child(field); return field

func number_field(parent: Node,title: String,low: float,high: float,step: float) -> SpinBox:
	var row:=HBoxContainer.new(); parent.add_child(row)
	var label: Label=studio.label(row,title,13); label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var field:=SpinBox.new(); field.min_value=low; field.max_value=high; field.step=step; field.custom_minimum_size.x=125; field.accessibility_name=title; row.add_child(field); return field

func tools() -> RefCounted:
	return studio.interior_tools.floor_tools

func root_data() -> Dictionary:
	return tools().root_data()

func select_floor(field: OptionButton,uid: String) -> void:
	for index in field.item_count:
		if field.get_item_metadata(index)==uid: field.select(index); return

func refresh() -> void:
	if not tools().active(): button.disabled=true; dialog.hide(); stamp=0; return
	button.disabled=root_data().get("floors",[]).is_empty()
	var definitions: Array=Plan.definitions(root_data()); var descriptor: Array=[]
	for floor in definitions: descriptor.append([floor["uid"],floor["name"],floor["height"]])
	var next: int=hash([descriptor,root_data().get("floor_links",[])])
	if next==stamp: return
	stamp=next; list.clear(); var names: Dictionary={}
	var previous_lower: String=str(lower.get_item_metadata(lower.selected)) if lower.selected>=0 else "ground"
	var previous_upper: String=str(upper.get_item_metadata(upper.selected)) if upper.selected>=0 else "ground"
	lower.clear(); upper.clear()
	for floor in definitions:
		names[floor["uid"]]=floor["name"]
		for field in [lower,upper]: field.add_item("%s · %+.1f m"%[floor["name"],floor["height"]]); field.set_item_metadata(field.item_count-1,floor["uid"])
	select_floor(lower,previous_lower); select_floor(upper,previous_upper)
	for link in root_data().get("floor_links",[]):
		list.add_item("%s · %s → %s · (%.2f, %.2f)"%["Elevator" if link["kind"]=="elevator" else "Stairs",names[link["lower"]],names[link["upper"]],link["start"][0],link["start"][1]])
		list.set_item_metadata(list.item_count-1,link["uid"])
		if link["uid"]==selected_uid: list.select(list.item_count-1)
	remove_button.disabled=selected_uid.is_empty() or list.get_selected_items().is_empty()

func show() -> void:
	refresh(); message.text=""
	if selected_uid.is_empty(): new_record()
	else: load_record(selected_uid)
	dialog.popup_centered(Vector2i(560,470))

func new_record() -> void:
	selected_uid=""; list.deselect_all(); remove_button.disabled=true
	var index: int=0; var definitions: Array=Plan.definitions(root_data())
	for position in definitions.size():
		if definitions[position]["uid"]==studio.current().floor_uid: index=position
	index=mini(index,definitions.size()-2)
	if index>=0: lower.select(index); upper.select(index+1)
	start_x.value=5; start_z.value=1; end_x.value=5; end_z.value=-4; width.value=1.2; message.text=""
	update_kind()

func load_record(uid: String) -> void:
	for link in root_data().get("floor_links",[]):
		if link["uid"]!=uid: continue
		selected_uid=uid; select_floor(lower,link["lower"]); select_floor(upper,link["upper"])
		kind.select(1 if link["kind"]=="elevator" else 0)
		for index in list.item_count:
			if list.get_item_metadata(index)==uid: list.select(index)
		start_x.value=link["start"][0]; start_z.value=link["start"][1]; end_x.value=link["end"][0]; end_z.value=link["end"][1]; width.value=link["width"]; remove_button.disabled=false; update_kind(); return
	new_record()

func apply_record() -> void:
	if not tools().prepare() or lower.selected<0 or upper.selected<0: return
	if lower.selected>=upper.selected: message.text="Choose a lower start floor and a higher end floor."; return
	var lift: bool=kind.selected==1
	if not lift and upper.selected!=lower.selected+1: message.text="A staircase joins neighbouring floors. Add a separate flight for each storey."; return
	var definitions: Array=Plan.definitions(root_data()); var rise: float=float(definitions[upper.selected]["height"])-float(definitions[lower.selected]["height"])
	var run: float=Vector2(start_x.value,start_z.value).distance_to(Vector2(end_x.value,end_z.value))
	if not lift and rise>8: message.text="A staircase can rise at most 8 m. Add an intermediate floor."; return
	if not lift and (run<rise*1.4-0.00001 or run>32):
		var unit: String="cells" if studio.mode=="2d" else "m"
		message.text="Give this staircase at least %.2f %s of run and no more than 32 %s."%[rise*1.4,unit,unit]; return
	if lift: synchronize_shaft()
	var record: Dictionary={}
	for link in root_data().get("floor_links",[]):
		if link["uid"]==selected_uid: record=link.duplicate(true)
	var uid: String=selected_uid if not selected_uid.is_empty() else ("lift_" if lift else "stairs_")+str(Time.get_ticks_usec())+"_"+str(randi())
	record.merge({"uid":uid,"kind":"elevator" if lift else "stairs","lower":lower.get_item_metadata(lower.selected),"upper":upper.get_item_metadata(upper.selected),"start":[start_x.value,start_z.value],"end":[end_x.value,end_z.value],"width":width.value},true)
	if lift:
		var heights: Dictionary={}
		for floor in definitions: heights[floor["uid"]]=float(floor["height"])
		if not Plan.compatible_link(record,root_data().get("floor_links",[]).filter(func(other: Dictionary)->bool:return other["uid"]!=uid),heights): message.text="Elevator shafts need separate space. Extend the existing elevator's floor range instead."; return
	var result: Dictionary=Plan.put_record(root_data(),"floor_links",record)
	if not result["ok"]: message.text=result["error"]; return
	selected_uid=uid; tools().commit(result,studio.current().floor_uid); refresh(); load_record(uid); message.text=tools().message.text

func remove_record() -> void:
	if selected_uid.is_empty() or not tools().prepare(): return
	tools().commit(Plan.remove_record(root_data(),"floor_links",selected_uid),studio.current().floor_uid)
	var removed: String="elevator" if kind.selected==1 else "staircase"
	selected_uid=""; refresh(); new_record(); message.text="Removed "+removed+". Undo restores it."
